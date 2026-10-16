import Foundation

/// What drift is *about*.
///
/// Either one subject, or several — and "several" carries no name, deliberately. Three
/// unrelated applications in ninety seconds is drift, not three fresh grace periods, and a
/// mandate that named the last of them would be the app misdescribing somebody's afternoon
/// (R-60).
public enum DriftSubject: Sendable, Equatable, Hashable, Codable {
    /// One application, selected item, or normalised browser page.
    case single(String)
    /// Drift accumulated across more than one unrelated subject.
    case mixed

    /// The subject's identifier, or `nil` when there is nobody to name.
    public var identifier: String? {
        switch self {
        case .single(let subject): subject
        case .mixed: nil
        }
    }

    public var isMixed: Bool { identifier == nil }
}

/// Where the drift accumulator has got to.
///
/// A value, reduced by a pure function on an injected `MonotonicClock` reading. There is no
/// timer object anywhere in this programme — e03's R-46 doctrine, applied to the second state
/// machine that needed it — which is what makes every sequence fixture an exact assertion
/// rather than a flaky one (R-60, F-48).
///
/// The four cases and what each means:
///
/// | state | meaning |
/// |---|---|
/// | `aligned` | nothing is accumulating |
/// | `grace` | drift has started and has not been sustained |
/// | `sustained` | drift is past the effective threshold; a mandate is possible |
/// | `cooldown` | a mandate was issued recently and will not be repeated until `until` |
public enum DriftState: Sendable, Equatable, Hashable, Codable {
    case aligned
    /// `since` and `accumulated` are both readings of the monotonic clock, never wall time.
    case grace(subject: DriftSubject, since: Duration, accumulated: Duration)
    /// `isMixed` is carried separately from `subject` because a mandate reports it, and a
    /// surface must be able to say "several unrelated items" without inspecting an enum case.
    case sustained(subject: DriftSubject, accumulated: Duration, isMixed: Bool)
    case cooldown(subject: DriftSubject, until: Duration)

    /// The subject drift is about, if there is one.
    public var subject: DriftSubject? {
        switch self {
        case .aligned: nil
        case .grace(let subject, _, _): subject
        case .sustained(let subject, _, _): subject
        case .cooldown(let subject, _): subject
        }
    }

    /// How much drift has accumulated. `.zero` when nothing has.
    public var accumulated: Duration {
        switch self {
        case .aligned, .cooldown: .zero
        case .grace(_, _, let accumulated): accumulated
        case .sustained(_, let accumulated, _): accumulated
        }
    }

    /// Whether drift has accumulated across more than one subject.
    public var isMixed: Bool {
        switch self {
        case .aligned: false
        case .sustained(let subject, _, let isMixed): isMixed || subject.isMixed
        case .grace(let subject, _, _), .cooldown(let subject, _): subject.isMixed
        }
    }

    /// Whether this state is one an intervention could be authorised from. **Necessary, never
    /// sufficient**: `InterventionEligibility.decide(…)` reads six other things first, and
    /// this property authorises nothing on its own — it exists so a surface can draw the
    /// drift clock differently once it is past the threshold.
    public var isSustained: Bool {
        if case .sustained = self { return true }
        return false
    }
}
