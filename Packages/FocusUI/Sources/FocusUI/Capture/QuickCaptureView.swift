import FocusCore
import Observation
import SwiftUI

/// What the quick-capture panel is showing, and what it should do about it.
///
/// A small observable box rather than view state, because the panel is an `NSPanel` built at
/// launch and driven from a Carbon hot-key handler: the controller has to be able to clear
/// the field and re-focus it from *outside* the view hierarchy, and SwiftUI state cannot be
/// reached from there.
@MainActor
@Observable
public final class QuickCaptureModel {
    /// Bumped by the controller every time the panel is shown. The view watches it and takes
    /// first responder, which is what makes the panel typeable the instant it appears rather
    /// than one click later.
    public internal(set) var showToken: Int = 0
    /// The appearance the panel draws with. Injected, like everywhere else in this package.
    public var traits: AppearanceTraits = .systemDefault

    /// Commit: the sentence, an optional definition of done, and whether the user asked to be
    /// returned to whatever they were interrupted from (⌘Return).
    @ObservationIgnored
    var onCommit: ((String, String?, Bool) -> Void)?
    /// Escape.
    @ObservationIgnored
    var onCancel: (() -> Void)?

    public init() {}
}

/// The contents of the global quick-capture panel.
///
/// The same `CaptureFieldView` the cockpit uses, so a vague sentence is answered the same way
/// wherever it is typed, plus the one line of guidance a panel summoned from another app
/// needs: what Return does, what ⌘Return does, and how to get out.
public struct QuickCaptureView: View {
    @Bindable private var model: QuickCaptureModel

    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(model: QuickCaptureModel) {
        self._model = Bindable(model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            CaptureFieldView(
                commit: { intent, doneWhen in
                    model.onCommit?(intent, doneWhen, false)
                },
                alternateCommit: { intent, doneWhen in
                    model.onCommit?(intent, doneWhen, true)
                },
                isEnabled: true,
                fieldFocus: .quickCaptureField,
                buttonFocus: .quickCaptureSet,
                focus: $focus
            )

            ShellText(.capturePanelHint, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: model.traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(spacing * 2)
        .frame(minWidth: 520, alignment: .leading)
        .background(DesignTokens.Palette.windowBackground)
        .appearanceTraits(model.traits)
        .onExitCommand { model.onCancel?() }
        .defaultFocus($focus, .quickCaptureField)
        .onChange(of: model.showToken) { focus = .quickCaptureField }
    }
}
