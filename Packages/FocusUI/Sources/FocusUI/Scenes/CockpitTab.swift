import Foundation

/// **The cockpit's two destinations** (focus-1rj7, focus-g9iw).
///
/// The owner's reading of the one-column cockpit was that the first thing on screen should be
/// what needs doing and how long, with everything else a step away. The three-tab split that
/// followed put the session in full, the context pack and the rules on a *Details* tab that
/// repeated half of *Now* and said nothing about how it connected to it, and a *Recent* tab
/// that drew the standing priorities beside the past. So the work reads as it is lived instead:
///
/// * *Now* — the priority and everything about doing it. While no session is open it is
///   **planning**: the standing priorities beside the capture field and the priority's setup.
///   While a session runs or is paused it is **working**: the task, the timer and the session's
///   whole set of verbs, once. The context and its rules are one *Configure context…* away.
/// * *History* — the earlier priorities, to pick one up again, and the route to the day's log.
///
/// The priority's hero is Now's first section rather than a header over both, because History
/// is the one place a person goes to look away from it; switching back is one press, and every
/// verb that acts on the priority is on Now and nowhere else.
public enum CockpitTab: String, Sendable, CaseIterable, Hashable, Identifiable {
    case now
    case history

    public var id: String { rawValue }

    /// The tab's name in the catalog.
    public var titleKey: ShellStringKey {
        switch self {
        case .now: .cockpitTabNow
        case .history: .cockpitTabHistory
        }
    }
}
