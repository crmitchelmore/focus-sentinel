import Foundation

/// What the app currently knows about whether a capability works.
///
/// Five states, which are the five the Feasibility Court named — no more and no fewer. The
/// distinctions are load-bearing, and collapsing any two of them would lose something the user
/// is entitled to be told:
///
/// * `.unavailable` is **not** `.denied`. There is no camera on this Mac; nobody refused
///   anything, and offering to "fix" it would be an insult.
/// * `.notRequested` is **not** `.denied` either. The app has not asked, which in e03 means it
///   never will — every prompting API is banned from the shipping graph by lint.
/// * `.restricted` is not the user's decision at all: it is an MDM profile or Screen Time, and
///   a call to action would send them somewhere they cannot change anything.
public enum CapabilityState: String, Sendable, CaseIterable, Codable, Hashable {
    /// It works, right now.
    case available
    /// The user said no. Never re-asked: their answer is not a prompt to try again.
    case denied
    /// Policy — an MDM profile, Screen Time, a managed device. Not the user's to change.
    case restricted
    /// The hardware or the platform does not offer it here. Not a refusal.
    case unavailable
    /// Nothing has been asked, and nothing has been observed.
    case notRequested

    /// Whether a consumer may use the capability as designed.
    public var isUsable: Bool { self == .available }

    /// Whether this state is one the user could change by answering a question differently.
    ///
    /// `.denied` alone. `.restricted` is not theirs, `.unavailable` is not anybody's, and
    /// `.notRequested` has no answer to change yet. The UI uses this to decide whether an
    /// explanation is even meaningful — and never to decide whether to ask.
    public var isUserReversible: Bool { self == .denied }
}
