import FocusUI
import Observation

/// **Which Settings pane is on screen, as something a window can observe** (focus-7ow).
///
/// ## Why this is an object and not a `var` on the composition root
///
/// A macOS `TabView` builds only the pane a person has selected. That was measured, and it is the
/// structural residue round 5 named: the Privacy pane's own receipts never arrived at all, because
/// nobody had clicked Privacy — so every value the Settings window reported had to be reported
/// from the **window**, out of the argument it was about to hand a pane. A defect *inside* an
/// unselected pane was invisible to every lane in the programme, and a mutation that handed the
/// Privacy pane `URL(fileURLWithPath: "/")` was reported as the truth by a window stamping its own
/// `storeURL`.
///
/// Closing that needs the selection driven from the host, and driving it needs the window to
/// **notice**. `AppComposition` is a plain `final class`: writing a property on it invalidates no
/// SwiftUI body, so a selection stored there would move and no pane would ever be rebuilt —
/// measured here, in the built app, on the first attempt: all three tabs were driven, the run loop
/// was given a turn after each, and the window went on reporting the General pane's one value.
///
/// This is an `@Observable` box, in the shape `AppearanceObserver` already established for exactly
/// the same reason. It holds one enum. The composition root owns it, `settingsConnection()` reads
/// it — which is the read SwiftUI records — and the self-check writes it.
@Observable
@MainActor
public final class SettingsTabSelection {
    public var tab: SettingsTab = .general

    public init(tab: SettingsTab = .general) {
        self.tab = tab
    }
}
