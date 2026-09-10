import FocusCore
import SwiftUI

/// F-119's one switch.
///
/// ## One stored value, three surfaces, no copies
///
/// The menu bar, the cockpit and — in e09 — the notch all bind to the same
/// `AppSettingsRecord.sensingPaused` through the same `SessionActing.setSensingPaused(_:)`. A
/// surface that kept its own boolean would be a second opinion about one row, and the moment
/// they disagreed the person would have no way to tell which one was true.
///
/// ## It is not a flag anybody checks
///
/// Switching this off **detaches every observer**: every workspace and distributed notification
/// token removed, the corroboration tick invalidated, every CoreAudio property listener removed.
/// A pause implemented as `if paused { return }` inside each handler is a pause that leaks the
/// moment somebody adds a handler, and the explanatory line under the switch says so — because
/// the difference is the whole of what the person is being promised.
///
/// The switch reads *positively* — "Watch what I am working on" — so that on means watching.
/// A control labelled with the thing it stops is a control people have to read twice.
public struct PauseSwitch: View {
    /// Whether the graph is watching. `false` is the paused state.
    public let isWatching: Bool

    /// Set the switch. `nil` for the read-only cockpit, which draws the control disabled rather
    /// than hiding it: the person is entitled to see the state even where they cannot change it.
    public let setWatching: ((Bool) -> Void)?

    @Environment(\.appearanceTraits) private var traits
    @FocusState.Binding private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    public init(
        isWatching: Bool,
        setWatching: ((Bool) -> Void)? = nil,
        focus: FocusState<FocusField?>.Binding
    ) {
        self.isWatching = isWatching
        self.setWatching = setWatching
        self._focus = focus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing / 3) {
            Toggle(isOn: binding) {
                ShellText(.sensingPauseLabel, role: .callout)
            }
            .toggleStyle(.switch)
            .focused($focus, equals: .cockpitSensingPause)
            .disabled(setWatching == nil)
            .accessibilityLabel(Text(ShellStrings.resource(.sensingPauseLabel)))

            ShellText(.sensingPauseExplanation, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Derived from the value rather than mirrored into `@State`.
    ///
    /// The switch belongs to the store, so every route that changes it — this control, the menu
    /// command, e09's notch — has to tell the store, and a local mirror could disagree with it.
    private var binding: Binding<Bool> {
        Binding(
            get: { isWatching },
            set: { newValue in setWatching?(newValue) }
        )
    }
}
