import SwiftUI

/// **Tooltips, from the catalog** (focus-8ski).
///
/// Every control in the shell carries one, so a person who hovers learns what the control does
/// before they press it — and, when it is disabled, *why it will not work* rather than nothing.
/// The text is a catalog entry like every other sentence the app draws: `check-strings.sh`
/// bans `.help("…")` with a literal, and these two helpers are the only shape a tooltip takes.
///
/// ## Order matters at the call site
///
/// Put the tooltip **after** `.disabled(…)`. `.help` attaches to the view it is applied to, and
/// a tooltip attached inside a disabled view is a tooltip AppKit does not show. Applied outside,
/// the wrapper is live, the button inside it is not, and the sentence explaining the disablement
/// is exactly what the pointer finds.
extension View {
    /// A tooltip naming what this control does.
    func shellHelp(_ key: ShellStringKey) -> some View {
        help(Text(ShellStrings.resource(key)))
    }

    /// A tooltip naming what this control does while it is live, and why it is not while it is
    /// disabled. `reason` is shown whenever `isDisabled` is true; the control itself still owns
    /// its `.disabled(…)`, so the two cannot disagree by more than one render.
    func shellHelp(_ key: ShellStringKey, disabled reason: ShellStringKey, when isDisabled: Bool) -> some View {
        help(Text(ShellStrings.resource(isDisabled ? reason : key)))
    }

    /// A tooltip from another package's catalog — the status labels and rule dispositions
    /// `FocusCore` owns.
    func shellHelp(resource: LocalizedStringResource) -> some View {
        help(Text(resource))
    }
}
