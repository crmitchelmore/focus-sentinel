import FocusCore
import Foundation

/// A bounded, deterministic look-back over the observation stream, which answers exactly one
/// question (R-61, F-49, D-05).
///
/// > **Is there a return anchor?** — a subject that was judged `relevant`, that held for at
/// > least `returnAnchorDwell`, and that was the *immediately preceding* aligned subject before
/// > the current drift began.
///
/// If yes, the drift machine's effective threshold becomes
/// `sustainedDriftThreshold + detourExtension`, which is D-05's own worked example: leaving the
/// IDE for the documentation and coming back is not drift. If no, nothing changes.
///
/// ## The window may only ever **extend**
///
/// It may never shorten the threshold, never raise a band, never produce a verdict and never
/// flip one. `effectiveThreshold` returns one of exactly two values and the larger only when an
/// anchor was found, so "the look-back can only make the app *less* likely to speak" is a
/// property of the return type rather than a claim about the code. A look-back that could make
/// the app *more* likely to nudge is a look-back that has to be right; one that can only make
/// it less likely is one that can only be conservative, and conservative is the posture this
/// whole epic is built in.
///
/// ## Bounded by **both** a span and a count
///
/// So that its cost is a constant and its result is a pure function of a finite prefix — which
/// is what lets a sequence fixture assert a byte-identical transcript. R-74.4 owes the
/// *sufficiency* of `maximumLookBackEvents` a benchmark: truncating to it must produce a
/// transcript identical to an untruncated replay over every sequence fixture, which is what
/// makes 32 a bound somebody measured rather than a round number.
///
/// **The count bound retains the anchor.** A bound that simply dropped the oldest observations
/// would be a bound that can *shorten* the threshold — see `prune(now:)` for the ordinary route
/// by which that happens and the harm it does — so the window holds at most `capacity + 2`
/// observations rather than `capacity`, and the two extra slots are the anchor and the
/// observation that dates it.
public struct TransitionWindow: Sendable, Equatable {
    /// The retained observations, oldest first. Never spanning more than `lookBackSpan`, and
    /// never longer than `capacity` — plus the two slots `prune(now:)` reserves for an anchor
    /// the count bound would otherwise discard.
    public private(set) var observations: [DriftObservation] = []

    /// How many observations the window keeps. `RelevancePolicy.maximumLookBackEvents` in every
    /// shipping path — the parameter exists so R-74.4's *sufficiency* proof can replay the very
    /// same fixtures against a window that keeps everything and compare the transcripts. A
    /// benchmark that can only run the bounded version cannot say the bound changed nothing.
    public let capacity: Int

    /// The dials the window reads (focus-exdi): the look-back span, the anchor dwell, the
    /// drift threshold and the detour extension.
    public var tunings: PolicyTunings

    public init(
        capacity: Int = RelevancePolicy.maximumLookBackEvents,
        tunings: PolicyTunings = .shipped
    ) {
        self.capacity = capacity
        self.tunings = tunings
    }

    /// Add an observation and prune, in that order.
    ///
    /// Pruning by span is relative to the newest observation rather than to a clock read here,
    /// because a window whose contents depended on *when it was asked* would not be replayable.
    public mutating func record(_ observation: DriftObservation) {
        observations.append(observation)
        prune(now: observation.now)
    }

    /// Prune by span, then by count — **without ever discarding the anchor.**
    ///
    /// The count bound used to drop the oldest observations outright, and that is a way for this
    /// window to *shorten* the effective threshold, which R-61 says it may never do. The route
    /// is not exotic, it is the ordinary one: the host judges on every accepted activation **and
    /// on e03's five-second corroboration tick**, so a `lookBackSpan` of 180 seconds holds
    /// around thirty-six observations whenever somebody stays anywhere for three minutes. Past
    /// that point the oldest observation is the `relevant` one the detour began from — and
    /// losing it turns D-05's own worked example inside out: the effective threshold collapses
    /// from 180 seconds back to 90, the accumulator is already past 90, and the app nudges a
    /// person for a detour it had already agreed was a detour.
    ///
    /// So the most recent `relevant` observation is retained past the bound, **together with the
    /// one immediately after it**, because those two are exactly the pair `returnAnchor` reads
    /// to decide how long the anchor held. Retaining the first without the second would measure
    /// the hold against whatever survived instead, which would *overstate* it and invent anchors
    /// rather than lose them. The window therefore holds at most `capacity + 2` observations,
    /// which is still a constant, and truncating it is answer-preserving — which is the property
    /// R-74.4 asks `SequenceReplayTests` to demonstrate.
    mutating func prune(now: Duration) {
        let horizon = now - tunings.duration(.lookBackSpan)
        observations.removeAll { $0.now < horizon }
        guard observations.count > capacity else { return }

        let firstRetained = observations.count - capacity
        guard let anchor = observations.lastIndex(where: { $0.verdict == .relevant }),
              anchor < firstRetained
        else {
            observations.removeFirst(firstRetained)
            return
        }

        var kept = [observations[anchor]]
        let successor = observations.index(after: anchor)
        if successor < firstRetained {
            kept.append(observations[successor])
        }
        kept.append(contentsOf: observations[firstRetained...])
        observations = kept
    }

    /// The anchor, if there is one: the subject the person was working in before this drift
    /// began, held long enough to count as somewhere they *were*.
    ///
    /// `now` is the current clock reading, used only to measure how long the most recent
    /// observation has held — so an anchor that is still the frontmost subject is measured
    /// against the present rather than against nothing.
    public func returnAnchor(at now: Duration) -> String? {
        // Walk back through the current run of non-relevant observations. The first `relevant`
        // one before it is the candidate; anything earlier is a previous detour and not this
        // one's anchor.
        guard let index = observations.lastIndex(where: { $0.verdict == .relevant }) else {
            return nil
        }
        guard let subject = observations[index].subject else { return nil }

        let next = observations.index(after: index)
        let until = next < observations.endIndex ? observations[next].now : now
        let held = until - observations[index].now
        guard held >= tunings.duration(.returnAnchorDwell) else { return nil }
        return subject
    }

    /// `sustainedDriftThreshold`, extended by `detourExtension` when an anchor was found.
    ///
    /// **Two values, and the larger one only.** There is no arithmetic here that could produce
    /// a third, which is what makes "the window may only extend" structural.
    public func effectiveThreshold(at now: Duration) -> Duration {
        returnAnchor(at: now) == nil
            ? tunings.duration(.sustainedDriftThreshold)
            : tunings.duration(.sustainedDriftThreshold) + tunings.duration(.detourExtension)
    }

    /// Whether the person has just come back to the subject they were anchored in — the
    /// condition the `.returnedToAnchor` explanation clause is drawn for.
    public func hasReturned(to subject: String?, at now: Duration) -> Bool {
        guard let subject, let anchor = returnAnchor(at: now) else { return false }
        return anchor == subject
    }

    /// The anchor as something an explanation may carry. A bundle identifier is already a
    /// token; an origin is reduced to its host, which is the part a person recognises a site by.
    public func anchorToken(at now: Duration) -> NormalisedToken? {
        guard let anchor = returnAnchor(at: now) else { return nil }
        return NormalisedToken.normalised(TokenNormalizer.host(of: anchor).lowercased())
    }

    /// How many **distinct** unrelated subjects the window has seen.
    ///
    /// What `ExplanationClause.mixedSubjects` reports. Counted from the window rather than
    /// carried on `DriftSubject`, which deliberately holds no list: three unrelated
    /// applications in ninety seconds is one fact about somebody's afternoon, not three names
    /// to read back to them, and a mandate that named the last of them would be the app
    /// misdescribing what they did.
    public var distinctUnrelatedSubjects: Int {
        Set(observations.filter { $0.verdict == .unrelated }.compactMap(\.subject)).count
    }

    /// Forget everything. Used when the session ends or the priority changes, both of which
    /// make every earlier observation evidence about a different question.
    public mutating func reset() {
        observations.removeAll()
    }

    /// The same window truncated to a given number of most-recent observations.
    ///
    /// R-74.4's instrument for a *single* window. The whole-replay form — the one the ruling
    /// actually asks for — is `SequenceReplayHarness.replay(_:lookBackCapacity:)`, which runs
    /// every fixture against a window that keeps everything and compares the transcript byte for
    /// byte with the bounded run.
    public func truncated(to count: Int) -> TransitionWindow {
        var copy = TransitionWindow(capacity: count, tunings: tunings)
        copy.observations = observations
        if copy.observations.count > count {
            copy.observations.removeFirst(copy.observations.count - count)
        }
        return copy
    }
}
