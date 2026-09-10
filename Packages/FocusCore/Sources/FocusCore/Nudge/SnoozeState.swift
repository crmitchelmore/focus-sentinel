import Foundation

/// **A snooze is about a subject, not about the guardian** (R-87, F-61).
///
/// Three properties, and each of them is the difference between a snooze and a mute:
///
/// * **Subject-scoped.** Snoozing Safari says nothing about Messages. A snooze that silenced
///   everything would be a global pause with a friendlier name, and the app already has a
///   global pause the person can see (F-119).
/// * **In memory only.** A snooze that survived a relaunch would be a snooze that outlived the
///   situation it was for — the meeting ended, the tab was closed, the afternoon moved on.
///   There is deliberately no column for it in `FocusSchemaV4`.
/// * **Visible.** The menu bar shows the countdown in the same monospaced-digit field as the
///   session timer (P-133), and the popover shows what is snoozed and offers cancel. A
///   suppression a person cannot see is a suppression they cannot trust.
///
/// And one thing it deliberately does **not** do: a snooze does not stop the **ambient rung**.
/// The glyph still tells the truth, because F-146's whole point is that the state is always
/// legible — a person who snoozed a panel asked for quiet, not for a lie.
public struct SnoozeState: Sendable, Equatable, Hashable {
    /// The subject this snooze is about — a bundle identifier or a normalised origin.
    public let subject: String
    /// The monotonic reading at which it lifts. Monotonic, never wall clock: a Mac that slept
    /// for an hour has not spent that hour ignoring somebody.
    public let until: Duration

    public init(subject: String, until: Duration) {
        self.subject = subject
        self.until = until
    }

    /// A snooze starting now, for one of `InterventionPolicy.snoozeDurations`.
    public static func starting(
        subject: String,
        for duration: Duration,
        now: Duration
    ) -> SnoozeState {
        SnoozeState(subject: subject, until: now + duration)
    }

    /// Whether this snooze is still running.
    public func isActive(at now: Duration) -> Bool { now < until }

    /// How long is left, or `.zero` once it has lifted. What the menu bar draws.
    public func remaining(at now: Duration) -> Duration {
        isActive(at: now) ? until - now : .zero
    }

    /// **Whether this snooze suppresses a nudge about `candidate`.**
    ///
    /// Subject equality, and nothing looser. No prefix matching, no "same company", no
    /// "probably the same thing": a snooze the person did not ask for is a nudge they did not
    /// get, and a guessed match is exactly how a subject-scoped suppression quietly becomes a
    /// global one.
    public func suppresses(subject candidate: String, at now: Duration) -> Bool {
        isActive(at: now) && candidate == subject
    }
}

/// Every snooze currently running, keyed by subject.
///
/// A value, so a reducer can hand back a new one rather than mutating shared state, and so two
/// tests cannot interfere.
public struct SnoozeBook: Sendable, Equatable {
    private var storage: [String: SnoozeState]

    public init(_ snoozes: [SnoozeState] = []) {
        storage = Dictionary(
            snoozes.map { ($0.subject, $0) },
            uniquingKeysWith: { first, second in first.until > second.until ? first : second }
        )
    }

    public static let none = SnoozeBook()

    /// The book with one more snooze in it. A second snooze for the same subject **replaces**
    /// the first rather than stacking, so a person who clicks 15 minutes twice gets fifteen
    /// minutes from the second click, not thirty.
    public func adding(_ snooze: SnoozeState) -> SnoozeBook {
        var copy = self
        copy.storage[snooze.subject] = snooze
        return copy
    }

    /// The book with one snooze cancelled — the popover's cancel action.
    public func cancelling(subject: String) -> SnoozeBook {
        var copy = self
        copy.storage.removeValue(forKey: subject)
        return copy
    }

    /// The book with everything that has lifted removed.
    public func pruned(at now: Duration) -> SnoozeBook {
        SnoozeBook(storage.values.filter { $0.isActive(at: now) })
    }

    /// Whether a nudge about this subject is snoozed.
    public func suppresses(subject: String, at now: Duration) -> Bool {
        storage[subject]?.suppresses(subject: subject, at: now) ?? false
    }

    // **`suppresses(rung:subject:at:)` is gone, and R-87 did not go with it** (focus-uru).
    //
    // It read `rung != .ambient && suppresses(subject:at:)` — the third of four spellings of one
    // rule, beside the fatigue controller's `rung != .ambient`, its `InterruptionCharge` ask, and
    // the suppression stack's `kind == .accusation, rung == .ambient`. Four homes for a rule is
    // four places it can be moved in one of them, and the gate that had none is what this round
    // repaired. The rule now lives in `SilenceSubject`, which
    // `FatigueRefusal.Kind.snoozed.subject` names — and `FatigueController.decide(…)` applies
    // once, to all five of its refusals, rather than threading it through a defaulted parameter
    // here. `SnoozeStateTests.ambientRungIsNeverSnoozed` asks the ruling directly and drives the
    // controller, so R-87 is proved where it is now decided.

    /// The snooze for a subject, if one is running.
    public func snooze(for subject: String) -> SnoozeState? { storage[subject] }

    /// Everything still running, longest remaining first — what the popover lists.
    public func active(at now: Duration) -> [SnoozeState] {
        storage.values
            .filter { $0.isActive(at: now) }
            .sorted { lhs, rhs in
                lhs.until == rhs.until ? lhs.subject < rhs.subject : lhs.until > rhs.until
            }
    }

    public var isEmpty: Bool { storage.isEmpty }
}

/// **A pause the person asked for, in F-64's three shapes.**
///
/// This is a *request*, not a second pause concept: it resolves to
/// `SessionEvent.paused(cause: .user)` through e03's existing `SessionMachine`, and the phase
/// it produces is e03's `SessionPhase.paused`. A nudge that introduced its own idea of "paused"
/// would be a second source of truth for the one thing the whole app is about.
public struct PauseRequest: Sendable, Equatable, Hashable {
    /// Which of `InterventionPolicy.pauseDurations` the person chose.
    public let preset: PausePreset
    /// The wall-clock instant they picked, for `.untilTime`. Ignored otherwise.
    public let chosenTime: Date?

    public init(preset: PausePreset, chosenTime: Date? = nil) {
        self.preset = preset
        self.chosenTime = chosenTime
    }

    /// The event this request hands to e03's session machine. **Always the same one**, because
    /// the duration is the app's business and the transition is the session's.
    public var sessionEvent: SessionEvent { .paused(cause: .user) }

    /// When the pause lifts, in wall-clock terms.
    ///
    /// Wall clock rather than monotonic, deliberately, and for the opposite reason to a
    /// snooze's: "until 3 pm" and "the rest of today" are promises about the clock on the wall,
    /// so a Mac that slept through the afternoon has spent it.
    ///
    /// - Returns: the instant the pause ends, or `nil` when the request is malformed — an
    ///   `.untilTime` with no time chosen, or a chosen time already in the past.
    public func expiry(now: Date, calendar: Calendar) -> Date? {
        switch preset {
        case .fixed(let span):
            return now.addingTimeInterval(TimeInterval(span.components.seconds))
        case .untilTime:
            guard let chosenTime, chosenTime > now else { return nil }
            return chosenTime
        case .restOfDay:
            // The start of tomorrow in the user's own calendar — never a UTC day, and never a
            // fixed number of hours, because "the rest of today" is shorter in the evening.
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        }
    }

    /// Whether this request can be acted on at all.
    public func isWellFormed(now: Date, calendar: Calendar) -> Bool {
        expiry(now: now, calendar: calendar) != nil
    }
}
