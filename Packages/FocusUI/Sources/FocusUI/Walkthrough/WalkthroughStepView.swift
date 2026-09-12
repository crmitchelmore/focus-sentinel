import FocusCore
import SwiftUI

/// **One step of the coach-mark tour** (focus-u6de).
///
/// The panel that sits beside the control the step is about. It carries the page's title as a
/// heading, one instruction — what to do, in the real app, right now — and, once the app's
/// state says it was done, the sentence that says what changed. Under those, the button that
/// does it for the person, and Back and Next.
///
/// The view decides nothing and writes nothing: `onAction` reports the fallback button,
/// `onNavigate` reports Back and Next, and `FocusHost` performs both, the same division
/// `AccusationPanelView` keeps with the nudge loop. It is rendered by
/// `WalkthroughPanelController` in the app and by the snapshot lane on its own, which is why it
/// takes plain values.
public struct WalkthroughStepView: View {
    public let step: WalkthroughAction
    /// Whether the app's state says this step has been done.
    public let isDone: Bool
    public let onAction: (WalkthroughAction) -> Void
    public let onNavigate: (WalkthroughAction) -> Void

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12
    @FocusState private var focus: FocusField?

    public init(
        step: WalkthroughAction,
        isDone: Bool = false,
        onAction: @escaping (WalkthroughAction) -> Void = { _ in },
        onNavigate: @escaping (WalkthroughAction) -> Void = { _ in }
    ) {
        self.step = step
        self.isDone = isDone
        self.onAction = onAction
        self.onNavigate = onNavigate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(step.page.titleKey, role: .headline)
                .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            instruction

            if isDone, let doneKey = step.doneKey {
                HStack(alignment: .top, spacing: spacing) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))
                        .accessibilityHidden(true)
                    ShellText(doneKey, role: .callout)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, spacing / 2)
            }

            footer
        }
        // The one dialog margin (focus-udn9).
        .dialogInset()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Palette.windowBackground(for: traits))
        .animation(DesignTokens.animation(for: traits), value: isDone)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(step.instructionKey)))
    }

    /// The instruction, at the body role: it is the one thing on the panel the person acts on.
    private var instruction: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDone ? "checkmark" : "hand.point.right")
                .foregroundStyle(DesignTokens.Palette.role(isDone ? .mist : .kiln, for: traits))
                .frame(width: 24)
                .accessibilityHidden(true)
            ShellText(step.instructionKey, role: .body)
                .foregroundStyle(isDone ? DesignTokens.supportingTextColor(for: traits) : DesignTokens.Palette.primaryText)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The fallback on the left, then Back, the position and Next.
    ///
    /// The last step has no Next: its fallback *is* the way out. Next is prominent once the step
    /// is done and plain before, so the eye goes to the app until then.
    private var footer: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let fallbackTitle = step.fallbackTitleKey {
                Button {
                    onAction(step)
                } label: {
                    Label {
                        ShellText(fallbackTitle, role: .callout)
                    } icon: {
                        Image(systemName: step == .finishDemo ? "flag.checkered" : "wand.and.stars")
                    }
                }
                .buttonStyle(CompanionButtonStyle(prominent: step == .finishDemo))
                .disabled(isDone && !step.performsOnArrival && step != .finishDemo)
                .focused($focus, equals: .walkthroughAction)
                // Every control carries a tooltip (focus-8ski); a disabled one says why.
                .shellHelp(
                    Self.fallbackHelpKey(for: step),
                    disabled: .walkthroughDoItForMeDisabledHelp,
                    when: isDone && !step.performsOnArrival && step != .finishDemo
                )
            }

            HStack(spacing: spacing) {
                Button {
                    if let previous = step.previousStep { onNavigate(previous) }
                } label: {
                    ShellText(.walkthroughBack)
                }
                .buttonStyle(CompanionButtonStyle())
                .disabled(step.previousStep == nil)
                .focused($focus, equals: .walkthroughBack)
                .shellHelp(.walkthroughBackHelp, disabled: .walkthroughBackDisabledHelp, when: step.previousStep == nil)

                Spacer(minLength: 0)

                position

                Spacer(minLength: 0)

                if let next = step.nextStep {
                    Button {
                        onNavigate(next)
                    } label: {
                        ShellText(.walkthroughNext)
                    }
                    .buttonStyle(CompanionButtonStyle(prominent: isDone))
                    .focused($focus, equals: .walkthroughNext)
                    .shellHelp(.walkthroughNextHelp)
                }
            }
        }
        .padding(.top, spacing)
    }

    /// The tooltip for the fallback button, one per label it can carry.
    static func fallbackHelpKey(for step: WalkthroughAction) -> ShellStringKey {
        switch step.fallbackTitleKey {
        case .walkthroughShowItAgain: .walkthroughShowItAgainHelp
        case .walkthroughActionFinishDemo: .walkthroughActionFinishDemoHelp
        default: .walkthroughDoItForMeHelp
        }
    }

    /// "3 of 11" through the locale's own digits, with one dot per step under it.
    private var position: some View {
        VStack(spacing: spacing / 2) {
            HStack(spacing: 4) {
                ForEach(WalkthroughAction.steps) { candidate in
                    Circle()
                        .fill(
                            candidate == step
                                ? DesignTokens.Palette.role(.spruce, for: traits)
                                : DesignTokens.Palette.role(.mist, for: traits).opacity(0.4)
                        )
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            ShellText(
                .walkthroughPosition,
                role: .caption,
                arguments: [step.ordinal.formatted(), WalkthroughAction.steps.count.formatted()]
            )
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .monospacedDigit()
        }
    }
}
