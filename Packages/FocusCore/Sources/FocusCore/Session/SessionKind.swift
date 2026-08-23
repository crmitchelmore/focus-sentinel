import Foundation

/// What kind of promise a session makes about time.
///
/// Three kinds and no fourth. Stored as `FocusSessionRecord.kindRaw`, defaulting to
/// `openEnded` so that every session written before this column existed reads back as the
/// thing it actually was.
public enum SessionKind: String, Sendable, CaseIterable, Codable, Hashable {
    /// No timebox. "No timebox" is a real answer, not a missing one.
    case openEnded
    /// A fixed length, in `plannedSeconds`.
    case countdown
    /// A wall-clock moment to be finished by, in `deadlineAt`.
    case deadline

    /// The one sanctioned decoder, in the same exhaustive shape as `SessionPhase.decode(_:)`
    /// and for the same reason: a stored string this build does not recognise must degrade to
    /// the harmless reading rather than to no session at all.
    public static func decode(_ raw: String?) -> SessionKind {
        switch raw {
        case "countdown": .countdown
        case "deadline": .deadline
        case "openEnded": .openEnded
        default: .openEnded
        }
    }
}
