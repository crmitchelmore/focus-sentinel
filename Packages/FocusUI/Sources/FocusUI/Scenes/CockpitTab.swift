import Foundation

/// **The cockpit's three tabs** (focus-1rj7).
///
/// The owner's reading of the one-column cockpit was that the first thing on screen should be
/// what needs doing and how long, with everything else a step away. So the column splits into
/// three: *Now* — the definition of done, the priority's verbs, the timebox and the session's
/// primary control; *Details* — the session in full, the context pack and the rules; *Recent* —
/// the previous priorities and the route to the day's history. The hero and the status stay
/// above the tabs on every one of them: the priority is never a tab away.
public enum CockpitTab: String, Sendable, CaseIterable, Hashable, Identifiable {
    case now
    case details
    case recent

    public var id: String { rawValue }

    /// The tab's name in the catalog.
    public var titleKey: ShellStringKey {
        switch self {
        case .now: .cockpitTabNow
        case .details: .cockpitTabDetails
        case .recent: .cockpitTabRecent
        }
    }
}
