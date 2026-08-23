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

public struct TransitionWindow: Sendable, Equatable {
    /// The retained observations, oldest first. Never longer than `capacity`, and never
    /// spanning more than `lookBackSpan`.
    public private(set) var observations: [DriftObservation] = []

    /// How many observations the window keeps. `RelevancePolicy.maximumLookBackEvents` in every
    /// shipping path — the parameter exists so R-74.4's *sufficiency* proof can replay the very
    /// same fixtures against a window that keeps everything and compare the transcripts. A
    /// benchmark that can only run the bounded version cannot say the bound changed nothing.
    public let capacity: Int

    public init(capacity: Int = RelevancePolicy.maximumLookBackEvents) {
        self.capacity = capacity
    }

    /// Add an observation and prune, in that order.
    ///
    /// Pruning by span is relative to the newest observation rather than to a clock read here,
    /// because a window whose contents depended on *when it was asked* would not be replayable.
    public mutating func record(_ observation: DriftObservation) {
        observations.append(observation)
        prune(now: observation.now)
    }

    mutating func prune(now: Duration) {
        let horizon = now - RelevancePolicy.lookBackSpan
        observations.removeAll { $0.now < horizon }
        if observations.count > capacity {
            observations.removeFirst(observations.count - capacity)
        }
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
        guard held >= RelevancePolicy.returnAnchorDwell else { return nil }
        return subject
    }

    /// `sustainedDriftThreshold`, extended by `detourExtension` when an anchor was found.
    ///
    /// **Two values, and the larger one only.** There is no arithmetic here that could produce
    /// a third, which is what makes "the window may only extend" structural.
    public func effectiveThreshold(at now: Duration) -> Duration {
        returnAnchor(at: now) == nil
            ? RelevancePolicy.sustainedDriftThreshold
            : RelevancePolicy.sustainedDriftThreshold + RelevancePolicy.detourExtension
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
        var copy = TransitionWindow(capacity: count)
        copy.observations = observations
        if copy.observations.count > count {
            copy.observations.removeFirst(copy.observations.count - count)
        }
        return copy
    }
}
