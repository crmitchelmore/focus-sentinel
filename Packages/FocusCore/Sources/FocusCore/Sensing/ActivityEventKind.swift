import Foundation

/// What kind of thing happened.
///
/// Raw values are strings and are persisted as `ActivityEvent.kindRaw`, so reordering this enum
/// can never reinterpret stored history (e01's R-05). The five e01 shipped keep their raw
/// values **exactly**; e03 adds nine and renames none.
///
/// ## Why it lives here and not beside the observation seam
///
/// e01 declared it in `FocusSensing`, next to `ActivityObserving`, because that was the only
/// thing that produced one. From e03 it is also the vocabulary of a **persisted column**, and
/// `ActivityEventStore` — which owns that column — is in `FocusCore`, which may not import
/// `FocusSensing`. A typed `append` therefore needs the enum on this side of the seam.
/// `FocusSensing` keeps the name as a `typealias`, so every existing call site is untouched and
/// there is still exactly one vocabulary rather than two that could drift apart.
public enum ActivityEventKind: String, Sendable, CaseIterable, Codable, Hashable {
    // MARK: The five e01 shipped — raw values unchanged, forever

    /// The frontmost application changed.
    case frontmostApplicationChanged
    /// The frontmost window's context changed (a different document, tab or origin).
    case contextChanged
    /// The user stopped interacting with the machine.
    case userIdle
    /// The user started interacting again.
    case userActive
    /// The display went to sleep or the screen was locked.
    case displayInactive

    // MARK: The nine e03 adds

    /// A session moved between phases, or its pause causes changed.
    case sessionPhaseChanged
    /// The global sensing switch went off and every observer was detached (F-119).
    case sensingPaused
    /// It went back on and they were re-installed.
    case sensingResumed
    /// The frontmost application was on the sensitive list, so nothing deeper was read.
    ///
    /// The row carries the bundle identifier **and nothing else**: the person is entitled to
    /// see that the app noticed and stood down (F-118).
    case sensitiveAppSuppressed
    /// A microphone started or stopped running somewhere. Never a claim that a meeting is
    /// occurring — `MediaActivity` has no member such a claim could be built from.
    case mediaActivityChanged
    /// The frontmost application took over the screen, or gave it back (F-35).
    case presentationChanged
    /// The focused window moved to a different display (F-34).
    case displayChanged
    /// The two idle counters diverged beyond the threshold, so something is posting synthetic
    /// events while nobody is typing. Written **once per transition**, so a timeline that looks
    /// strange later has an explanation in it rather than a mystery (R-36).
    case syntheticInputObserved
    /// A capability changed state (F-126).
    case capabilityChanged

    /// The one sanctioned decoder, in the same exhaustive-`switch` spirit as
    /// `SessionPhase.decode(_:)`: a row written by a build that knew a kind this one does not
    /// reads back as `nil` and is shown as nothing, rather than being guessed at or crashing
    /// the launch of an app whose whole job is to be there when you open it.
    public static func decode(_ raw: String?) -> ActivityEventKind? {
        guard let raw else { return nil }
        return allCases.first { $0.rawValue == raw }
    }
}
