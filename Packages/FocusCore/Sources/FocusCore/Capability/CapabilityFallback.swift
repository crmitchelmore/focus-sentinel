import Foundation

/// What one consumer does when one capability is not available.
///
/// Five answers and no sixth. "Handle it gracefully" is not an answer; each of these is.
public enum CapabilityFallback: Sendable, Equatable, Hashable {
    /// The consumer does not need this capability and is unaffected by its absence.
    case fullFunction
    /// The consumer falls back to a cheaper signal it *can* have, and keeps working.
    case degraded(to: Capability)
    /// The consumer cannot run at all without this. **Never permitted for a T1 consumer
    /// against a `.denied` capability** — that combination is the charter's graceful-path
    /// tenet being broken, and a test rejects it.
    case featureAbsent
    /// The consumer treats the missing signal as a reason to do *less*, never more. This is
    /// the safe direction for every suppression rule: not knowing whether a microphone is
    /// running must never become permission to interrupt.
    case suppressOnly
    /// There is nothing to fall back to, and the surface says so plainly — in the user's
    /// language, with **no call to action**, because a call to action here would be an ask in
    /// disguise.
    case showUnavailable

    /// A stable token for the surface and the event stream. `degraded` carries its
    /// destination, so the token names it.
    public var token: String {
        switch self {
        case .fullFunction: "fullFunction"
        case .degraded(let capability): "degraded:\(capability.rawValue)"
        case .featureAbsent: "featureAbsent"
        case .suppressOnly: "suppressOnly"
        case .showUnavailable: "showUnavailable"
        }
    }
}
