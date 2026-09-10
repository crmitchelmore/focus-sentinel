import FocusCore
import Foundation

/// One activation, as the drift machine sees it.
///
/// `now` is a reading of an injected `MonotonicClock`, never wall time: a wall clock can jump
/// backwards when NTP corrects it, when the machine sleeps, or when somebody edits the date,
/// and a drift accumulator built on one would be a drift accumulator a timezone change could
/// clear.
public struct DriftObservation: Sendable, Equatable, Hashable, Codable {
    /// Elapsed time since the clock's origin.
    public let now: Duration
    public let verdict: Verdict
    /// The bundle identifier or normalised origin. `nil` for an unbundled process, which can
    /// never be `unrelated` anyway — there is nothing to write a rule about one.
    public let subject: String?
    public let isUserIdle: Bool
    public let phase: SessionPhase
    /// `sustainedDriftThreshold`, plus `detourExtension` when the transition window found a
    /// return anchor (R-61). Carried on the observation rather than held by the machine, because
    /// the window recomputes it per observation and a machine that cached it would be a machine
    /// whose answer depended on when it last looked.
    public let effectiveThreshold: Duration

    public init(
        now: Duration,
        verdict: Verdict,
        subject: String?,
        isUserIdle: Bool = false,
        phase: SessionPhase = .focus,
        effectiveThreshold: Duration = RelevancePolicy.sustainedDriftThreshold
    ) {
        self.now = now
        self.verdict = verdict
        self.subject = subject
        self.isUserIdle = isUserIdle
        self.phase = phase
        self.effectiveThreshold = effectiveThreshold
    }
}

/// The drift accumulator: **a value type with a pure reducer, and no timer anywhere**.
///
/// There is no `Timer`, no `DispatchSourceTimer`, no `Task.sleep` and no `RunLoop` in this
/// package — asserted by lint R-70e, and the same doctrine e03 established for sessions
/// (R-46: *"there is no timer object anywhere in this programme"*). Time enters only as a
/// `Duration` read from an injected `MonotonicClock`, which is what makes a replayed sequence
/// **exact** rather than approximate, and what lets a fixture assert a byte-identical
/// transcript.
///
/// ## The interval belongs to the previous observation
///
/// An activation stream says *"at time t, subject S became frontmost"*. The time that just
/// elapsed was therefore spent on the **previous** subject, not on this one — so `reduce` first
/// applies the interval under the previous observation's verdict, idle state and phase, and
/// then handles the arrival of the new one. Getting this backwards is the classic way a drift
/// detector attributes a person's whole afternoon to whatever they happened to open last.
///
/// ## The five rulings inside the transition table (R-60)
///
/// 1. **A short return does not reset.** Returning to a relevant subject for less than
///    `driftResetGrace` leaves the accumulator intact. Without this, alt-tabbing back to the IDE
///    for one second a minute makes the app permanently mute — the single most obvious way to
///    defeat a drift detector, and the one a naïve implementation always has.
/// 2. **Hopping between distractions accumulates.** Three unrelated applications in ninety
///    seconds is drift, not three fresh grace periods. The subject becomes `.mixed`, the mandate
///    reports `isMixed`, and the explanation says *several unrelated applications* rather than
///    misnaming the last one.
/// 3. **`uncertain` freezes.** An `uncertain` observation is *no information*. It must not act
///    as a return (which would reward ambiguity by muting the app) and must not accumulate
///    (which would let ignorance nudge). Freezing is the only answer consistent with standing
///    condition 6.
/// 4. **Idle freezes.** A person who walked away is not drifting.
/// 5. **Leaving `.focus` resets outright.** A break, an intentional detour, a pause or an
///    interruption is a declaration that the deviation is deliberate.
///
/// The mandate is issued at the **first observation after** the effective threshold — strictly
/// after, so ninety seconds exactly does not mandate — and never at a tick, because there are
/// no ticks.
public struct DriftMachine: Sendable, Equatable {
    public private(set) var state: DriftState

    /// The last observation, so the next one knows whose interval just elapsed.
    private var previous: DriftObservation?

    /// The dials the machine reads (focus-exdi): the return grace and the mandate cooldown.
    public var tunings: PolicyTunings

    public init(state: DriftState = .aligned, tunings: PolicyTunings = .shipped) {
        self.state = state
        self.tunings = tunings
    }

    /// Fold one observation in and return the new state.
    @discardableResult
    public mutating func reduce(_ observation: DriftObservation) -> DriftState {
        defer { previous = observation }

        // Ruling 5. A deliberate deviation is not drift, and the accumulator does not survive
        // one: coming back from a break starts the count again from nothing.
        guard observation.phase.permitsIntervention else {
            state = .aligned
            return state
        }

        if let previous {
            state = Self.advance(state, from: previous, to: observation, tunings: tunings)
        }
        state = Self.arrive(observation, into: state)
        return state
    }

    /// Record that a mandate was issued, so the engine does not say the same thing again for
    /// `mandateCooldown`.
    ///
    /// Called by the engine **after** `InterventionEligibility.decide` returned `.mandated` —
    /// never by the machine itself, because a reducer that knew about interventions would be a
    /// reducer with an opinion about when to interrupt somebody.
    public mutating func recordMandate(at now: Duration) {
        let subject = state.subject ?? .mixed
        state = .cooldown(subject: subject, until: now + tunings.duration(.mandateCooldown))
    }

    // MARK: - The interval, under the previous observation

    static func advance(
        _ state: DriftState,
        from previous: DriftObservation,
        to observation: DriftObservation,
        tunings: PolicyTunings = .shipped
    ) -> DriftState {
        let delta = observation.now - previous.now
        guard delta > .zero else { return state }

        // Ruling 4, and ruling 5 applied to the interval rather than to the arrival: time spent
        // away from the keyboard, or spent on a declared break, accumulates nothing and decays
        // nothing.
        if previous.isUserIdle, RelevancePolicy.idleSuspendsAccumulation { return state }
        guard previous.phase.permitsIntervention else { return state }

        switch previous.verdict {
        case .uncertain:
            // Ruling 3. No information is not a return and is not drift.
            return state

        case .relevant:
            // Ruling 1. A return counts only once it has been *held*.
            return delta >= tunings.duration(.driftResetGrace) ? .aligned : state

        case .unrelated:
            return accumulate(state, delta: delta, previous: previous, observation: observation)
        }
    }

    static func accumulate(
        _ state: DriftState,
        delta: Duration,
        previous: DriftObservation,
        observation: DriftObservation
    ) -> DriftState {
        switch state {
        case .aligned:
            // Not reachable through `reduce`, because an unrelated arrival always opens a grace
            // period first. Handled rather than asserted: a reducer that trapped on a state it
            // believed impossible would be a crash in place of a conservative answer.
            let subject = previous.subject.map(DriftSubject.single) ?? .mixed
            return .grace(subject: subject, since: previous.now, accumulated: delta)

        case .grace(let subject, let since, let accumulated):
            let total = accumulated + delta
            guard total > observation.effectiveThreshold else {
                return .grace(subject: subject, since: since, accumulated: total)
            }
            return .sustained(subject: subject, accumulated: total, isMixed: subject.isMixed)

        case .sustained(let subject, let accumulated, let isMixed):
            // Still drifting. The accumulator keeps running because the band rises with it.
            return .sustained(subject: subject, accumulated: accumulated + delta, isMixed: isMixed)

        case .cooldown(let subject, let until):
            // Already said this recently. Stay quiet until the cooldown expires, then begin a
            // fresh grace period rather than resuming the old accumulator — the person has
            // heard it once, and the second time starts from the beginning.
            guard observation.now >= until else { return state }
            return .grace(subject: subject, since: observation.now, accumulated: .zero)
        }
    }

    // MARK: - The arrival of the new subject

    static func arrive(_ observation: DriftObservation, into state: DriftState) -> DriftState {
        if observation.isUserIdle, RelevancePolicy.idleSuspendsAccumulation { return state }

        switch observation.verdict {
        case .relevant, .uncertain:
            // A return is credited by the *interval* it turns out to have held for, not by the
            // moment it arrives — which is ruling 1 expressed as the absence of code here.
            return state

        case .unrelated:
            guard let identifier = observation.subject else { return state }
            let arriving = DriftSubject.single(identifier)

            switch state {
            case .aligned:
                return .grace(subject: arriving, since: observation.now, accumulated: .zero)

            case .grace(let subject, let since, let accumulated):
                // Ruling 2. A different unrelated subject does not restart the clock.
                guard subject != arriving else { return state }
                return .grace(subject: .mixed, since: since, accumulated: accumulated)

            case .sustained(let subject, let accumulated, _):
                guard subject != arriving else { return state }
                return .sustained(subject: .mixed, accumulated: accumulated, isMixed: true)

            case .cooldown:
                return state
            }
        }
    }
}
