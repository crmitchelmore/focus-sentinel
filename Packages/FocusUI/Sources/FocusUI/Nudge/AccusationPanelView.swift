import FocusCore
import SwiftUI

/// **Everything the accusation panel needs to draw itself**, as one value.
///
/// A value rather than a bundle of arguments, for the reason every other surface in this
/// package takes one: the snapshot lane renders it with no host, no store and no clock, and the
/// running app hands the same shape in. What the panel is *about* has already been decided by
/// `NudgeDecider`; this is the rendering of that decision and it decides nothing.
public struct AccusationPresentation: Sendable, Equatable {
    /// Which rung. The panel draws rung 2 and rung 3; rung 1 is the menu-bar glyph and has no
    /// panel at all.
    public let rung: LadderRung.Kind
    /// One of the five static decks.
    public let voice: NudgeVoice
    /// The priority's own sentence, in the person's own words. `{task}`.
    public let task: String
    /// The application this is about, or `nil` when drift accumulated across several.
    ///
    /// `nil` is not a missing value: an accusation over mixed drift names nobody, so the body
    /// line — which exists only to say *what* you have been in — is **omitted** rather than
    /// filled with an invented subject. The two actions that would write a rule about a subject
    /// are withdrawn for the same reason (`CorrectionAction.requiresScope`).
    public let subject: String?
    /// How long, monotonic. `{duration}`.
    public let dwelled: Duration
    /// The application "Back to …" would activate, or `nil` when there is no stored anchor —
    /// in which case the action is **not offered**, because a button with nowhere to go is a
    /// button that lies (R-88).
    public let returnTarget: String?
    /// How long a running snooze for this subject has left, when one is running. Drawn as a
    /// countdown, because a suppression a person cannot see is a suppression they cannot trust.
    public let snoozeRemaining: Duration?
    /// The snooze spans on offer. `InterventionPolicy.snoozeDurations` in the shipping app.
    public let snoozeDurations: [Duration]

    public init(
        rung: LadderRung.Kind,
        voice: NudgeVoice = .standard,
        task: String,
        subject: String?,
        dwelled: Duration,
        returnTarget: String? = nil,
        snoozeRemaining: Duration? = nil,
        snoozeDurations: [Duration] = InterventionPolicy.snoozeDurations
    ) {
        self.rung = rung
        self.voice = voice
        self.task = task
        self.subject = subject
        self.dwelled = dwelled
        self.returnTarget = returnTarget
        self.snoozeRemaining = snoozeRemaining
        self.snoozeDurations = snoozeDurations
    }

    /// Whether a rule-writing action has a subject to be about.
    public var hasScope: Bool { subject != nil }

    /// **The order the panel offers the economy in**, and the order is the argument.
    ///
    /// Getting back to work first, because that is what the person came here to do; the two
    /// corrections next, because telling the app it is wrong must be as easy as obeying it;
    /// then the two ways of buying quiet, and finally the one that changes the commitment
    /// itself. `dismiss` is deliberately absent from this list: Escape and the close affordance
    /// are the dismissal, and a row of buttons with "ignore me" in it would be a panel arguing
    /// with itself.
    public static let actionOrder: [CorrectionAction] = [
        .returnToTask, .thisIsRelevant, .notThisTime, .snooze, .pause, .changePriority
    ]

    /// The actions this panel actually shows, in `actionOrder`.
    ///
    /// Two are conditional and both conditions are the same principle: an action the app cannot
    /// honestly perform is not offered at all, rather than offered and then explained away.
    public var offeredActions: [CorrectionAction] {
        Self.actionOrder.filter { action in
            if action == .returnToTask { return returnTarget != nil }
            return !action.requiresScope || hasScope
        }
    }

    /// The one action drawn as the default.
    ///
    /// Returning to work when there is somewhere to return to; otherwise the correction, because
    /// "this is relevant" is the click that makes the app better and it should never be the
    /// hardest button to find. **Never** a coercive default: every action here is optional and
    /// the panel is dismissible whichever one is emphasised (D-07).
    public var primaryAction: CorrectionAction? { offeredActions.first }

    /// The sentence VoiceOver speaks when the panel appears (F-144).
    ///
    /// The title and the body, in the order they are drawn, so a person who cannot see the panel
    /// hears exactly what it says rather than "dialog".
    public func announcement() -> String {
        var parts = [
            NudgeCopy.string(voice: voice, .accusationPanelTitle, arguments: [task])
        ]
        if let subject {
            parts.append(
                NudgeCopy.string(
                    voice: voice,
                    .accusationPanelBody,
                    arguments: [subject, NudgeCopy.duration(dwelled)]
                )
            )
        }
        return parts.joined(separator: " ")
    }
}

/// The copy key each action is titled from.
extension CorrectionAction {
    /// The deck line that names this action, or `nil` for the one that is a gesture rather than
    /// a button.
    public var copyKey: NudgeCopyKey? {
        switch self {
        case .thisIsRelevant: .accusationActionRelevant
        case .notThisTime: .accusationActionNotNow
        case .snooze: .accusationActionSnooze
        case .changePriority: .accusationActionPriority
        case .pause: .accusationActionPause
        case .returnToTask: .accusationActionReturn
        case .dismiss: nil
        }
    }
}

/// **The accusation panel: rung 2, and rung 3 in recommitment form** (R-86, F-57…F-64).
///
/// The Court's product boundary is that a nudge you cannot answer back to is an anti-pattern,
/// and D-07's is that there is **zero coercion**. Both are visible in this view rather than
/// asserted about it: every action the person can take is a button here, the whole panel is
/// dismissible with Escape, and the top rung differs from the one below it only in asking for a
/// choice — not in taking one away.
///
/// ## Rung 3 is not louder, it is more explicit
///
/// The recommitment rung requires an explicit choice and does not auto-dismiss. What it does
/// **not** do is dim anything, block anything, quit anything or impose a friction timer (R-99).
/// The difference a person sees is a line asking them to choose and a title drawn at the
/// heading role; the difference in behaviour is that nothing takes it off screen for them.
public struct AccusationPanelView: View {
    private let presentation: AccusationPresentation
    /// What the person did. The duration is the chosen snooze span, and is `nil` for every
    /// action that is not a snooze.
    ///
    /// **Internal, so the unit lane can invoke it directly.** The view decides nothing and
    /// writes nothing: it reports which button was pressed and `CorrectionAction.outcome(…)`
    /// remains the single place a click becomes a write (R-86). Asserting that by calling the
    /// closure is asserting the contract; asserting it by clicking a rendered button would be
    /// asserting SwiftUI.
    let onAction: (CorrectionAction, Duration?) -> Void

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        presentation: AccusationPresentation,
        onAction: @escaping (CorrectionAction, Duration?) -> Void = { _, _ in }
    ) {
        self.presentation = presentation
        self.onAction = onAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing, scale: textScale)) {
            header
            if let subject = presentation.subject {
                NudgeText(
                    .accusationPanelBody,
                    voice: presentation.voice,
                    arguments: [subject, NudgeCopy.duration(presentation.dwelled)],
                    role: .callout
                )
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            }
            if presentation.rung == .recommitment {
                ShellText(.nudgeRecommitment, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let remaining = presentation.snoozeRemaining {
                snoozeCountdown(remaining)
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: presentation.announcement()))
    }

    // MARK: - The parts

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.spacing(spacing, scale: textScale)) {
            // The same token set every other surface draws, so the panel and the menu bar can
            // never disagree about what the app believes (F-83, F-146).
            StatusBadge(status: .unrelated, showsLabel: false)
            NudgeText(
                .accusationPanelTitle,
                voice: presentation.voice,
                arguments: [presentation.task],
                role: presentation.rung == .recommitment ? .title3 : .headline
            )
            .foregroundStyle(DesignTokens.Palette.primaryText)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            dismissButton
        }
    }

    /// The close affordance. **Every surface is dismissible** (D-07), including this one and
    /// including rung 3; Escape does the same thing through `NudgePanel.cancelOperation(_:)`.
    private var dismissButton: some View {
        Button {
            onAction(.dismiss, nil)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .imageScale(.medium)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ShellStrings.resource(.nudgeDismiss)))
    }

    private func snoozeCountdown(_ remaining: Duration) -> some View {
        HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            Image(systemName: "clock")
                .imageScale(.small)
                .accessibilityHidden(true)
            // The same monospaced-digit field the menu-bar timer uses (P-133): a countdown in a
            // proportional font moves every character beside it once a second.
            Text(verbatim: NudgeCopy.countdown(remaining))
                .font(
                    DesignTokens.font(.callout, scale: textScale)
                        .monospacedDigit()
                )
        }
        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                ShellStrings.string(
                    .nudgeSnoozeCountdown,
                    argument: NudgeCopy.duration(remaining)
                )
            )
        )
    }

    private var actions: some View {
        // A wrapping flow rather than a fixed row: at the accessibility text size six buttons
        // in one line would run off the panel, and truncating an action is the same defect as
        // not offering it.
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ForEach(presentation.offeredActions, id: \.self) { action in
                actionRow(action)
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ action: CorrectionAction) -> some View {
        if action == .snooze {
            snoozeRow
        } else {
            Button {
                onAction(action, nil)
            } label: {
                actionLabel(action)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(
                action == presentation.primaryAction ? .defaultAction : nil
            )
        }
    }

    /// The snooze row: one button per span, so the choice is one click rather than two.
    ///
    /// F-61's own three figures, read from `InterventionPolicy.snoozeDurations` rather than
    /// written here — the panel offers what the policy declares, and a fourth span would appear
    /// without an edit to this file.
    ///
    /// **Three layouts, and the reason is a measured defect.** At the accessibility text size
    /// the one-line arrangement rendered "5 mi…", "10 mi…", "15 mi…" — and an action whose span
    /// a person cannot read is an action they cannot choose, which is the same defect as not
    /// offering it. Every span label is `fixedSize`, so overflow is real rather than silently
    /// truncated, and `ViewThatFits` takes the widest arrangement that actually fits.
    private var snoozeRow: some View {
        let gap = DesignTokens.spacing(spacing / 2, scale: textScale)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: gap) {
                snoozeLabel
                snoozeButtons(gap: gap)
            }
            VStack(alignment: .leading, spacing: gap) {
                snoozeLabel
                snoozeButtons(gap: gap)
            }
            VStack(alignment: .leading, spacing: gap) {
                snoozeLabel
                ForEach(presentation.snoozeDurations, id: \.self) { span in
                    snoozeButton(span)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var snoozeLabel: some View {
        NudgeText(.accusationActionSnooze, voice: presentation.voice, role: .callout)
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .fixedSize(horizontal: true, vertical: false)
    }

    private func snoozeButtons(gap: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(presentation.snoozeDurations, id: \.self) { span in
                snoozeButton(span)
            }
        }
    }

    private func snoozeButton(_ span: Duration) -> some View {
        Button {
            onAction(.snooze, span)
        } label: {
            Text(verbatim: NudgeCopy.duration(span))
                .font(DesignTokens.font(.callout, scale: textScale))
                // Never truncated: `ViewThatFits` can only choose a layout that fits if the
                // arrangement that does not fit says so instead of shrinking its own text.
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func actionLabel(_ action: CorrectionAction) -> some View {
        if let key = action.copyKey {
            NudgeText(
                key,
                voice: presentation.voice,
                arguments: action == .returnToTask
                    ? [presentation.returnTarget ?? ""]
                    : [],
                role: .callout
            )
        } else {
            ShellText(.nudgeDismiss, role: .callout)
        }
    }
}
