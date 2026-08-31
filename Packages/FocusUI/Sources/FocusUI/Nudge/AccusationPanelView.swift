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
    ///
    /// **Both halves, and the body line draws only one of them** (focus-ebv). This was a
    /// `String?` carrying `LadderRung.subject` — the storage key — so the panel said
    /// *"com.apple.Safari, 12 minutes."* three lines under a button reading *"Back to Pages"*.
    /// A rule, a snooze and a receipt are still keyed on `subject.identifier`; the sentence
    /// draws `subject.displayName` and nothing else.
    public let subject: NudgeSubject?
    /// How long, monotonic. `{duration}`.
    public let dwelled: Duration
    /// The application "Back to …" would activate, or `nil` when there is no stored anchor —
    /// in which case the action is **not offered**, because a button with nowhere to go is a
    /// button that lies (R-88).
    public let returnTarget: String?
    /// How long a running snooze for this subject has left, when one is running. Drawn as a
    /// countdown, because a suppression a person cannot see is a suppression they cannot trust.
    public let snoozeRemaining: Duration?
    /// **Whether there is a session for the two session-scoped actions to act on** (focus-rdw).
    ///
    /// A world-fact rather than a style, and it is here for the reason `returnTarget` is: it
    /// decides whether an action can honestly be offered. No open session is a supported default
    /// state — there is no auto-start, so the panel really does appear with only a priority set
    /// — and in it *"Not this time"* wrote no rule and *"Pause"* threw `noOpenSession`, while the
    /// panel came down and the log recorded a correction anyway.
    ///
    /// It has **no default**. Every construction of this value states it, because a default is
    /// what would let the next surface inherit the wrong half of the answer in silence.
    public let hasOpenSession: Bool
    /// The snooze spans on offer. `InterventionPolicy.snoozeDurations` in the shipping app.
    public let snoozeDurations: [Duration]

    public init(
        rung: LadderRung.Kind,
        voice: NudgeVoice = .standard,
        task: String,
        subject: NudgeSubject?,
        dwelled: Duration,
        returnTarget: String? = nil,
        snoozeRemaining: Duration? = nil,
        hasOpenSession: Bool,
        snoozeDurations: [Duration] = InterventionPolicy.snoozeDurations
    ) {
        self.rung = rung
        self.voice = voice
        self.task = task
        self.subject = subject
        self.dwelled = dwelled
        self.returnTarget = returnTarget
        self.snoozeRemaining = snoozeRemaining
        self.hasOpenSession = hasOpenSession
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
    /// **Four** are conditional now, and all four conditions are the same principle: an action
    /// the app cannot honestly perform is not offered at all, rather than offered and then
    /// explained away. `returnToTask` needs somewhere to go (R-88); the two rule-writing actions
    /// need a subject to be about; and the two session-scoped ones need a session to act on
    /// (focus-rdw) — with none, *"Not this time"* wrote no rule and *"Pause"* threw, while the
    /// panel came down and the log recorded a correction regardless.
    public var offeredActions: [CorrectionAction] {
        Self.actionOrder.filter { action in
            if action == .returnToTask { return returnTarget != nil }
            if action.requiresOpenSession, !hasOpenSession { return false }
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
                    arguments: [subject.displayName, NudgeCopy.duration(dwelled)]
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
public struct AccusationPanelView: DecisionSurfaceContent {
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
        column { context; actions }
    }

    public static let decisionSurface: DecisionSurface = .accusationPanel

    /// **Which half of this panel is the decision** (focus-din).
    ///
    /// The accusation, the subject it is about and the snooze countdown are what the decision is
    /// *about*; the six corrections are the decision. When the panel has to give way it is the
    /// first group that scrolls, so a person at the largest text size still has every correction
    /// in front of them — which is the difference between a rung that can be charged and a ladder
    /// that parks.
    ///
    /// `whole` is built from the same two halves as `body`, so the split and the drawing cannot
    /// describe two different panels.
    public var surfaceLayout: DecisionSurfaceLayout {
        DecisionSurfaceLayout(
            whole: AnyView(column { context; actions }),
            context: AnyView(column { context }),
            decision: AnyView(column { actions })
        )
    }

    /// The one column every rendering of this panel is built in, so the spacing, the width and
    /// the accessibility grouping are stated once.
    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing, scale: textScale)) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: presentation.announcement()))
    }

    @ViewBuilder
    private var context: some View {
        header
        if let subject = presentation.subject {
            NudgeText(
                .accusationPanelBody,
                voice: presentation.voice,
                arguments: [subject.displayName, NudgeCopy.duration(presentation.dwelled)],
                role: .callout
            )
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let remaining = presentation.snoozeRemaining {
            snoozeCountdown(remaining)
        }
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
                role: .headline
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
                // **Every offered action reports where it landed** (focus-vpu). A panel whose
                // Pause row is below the clip is not a panel with one button missing — it is not
                // a decision surface at all, and `NudgePanelController` can only know that if the
                // layout says where each row is.
                actionRow(action).nudgeActionTarget(action.rawValue)
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ action: CorrectionAction) -> some View {
        if action == .snooze {
            snoozeRow
        } else if action == presentation.primaryAction {
            // **Prominent, never default.** An earlier draft bound the primary action to
            // `.keyboardShortcut(.defaultAction)`; `DefaultActionContractTests` is right to
            // forbid it here, and R-89 is the stronger reason. A window default button collects
            // every Return no focused field claimed — so the moment a person clicked this panel
            // and made it key, a bare Return would perform "Back to …". The panel exists to take
            // nothing; emphasis is a colour, not a key equivalent.
            plainActionButton(action).buttonStyle(.borderedProminent)
        } else {
            plainActionButton(action).buttonStyle(.bordered)
        }
    }

    private func plainActionButton(_ action: CorrectionAction) -> some View {
        Button {
            onAction(action, nil)
        } label: {
            actionLabel(action)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                snoozeLabel(wraps: false)
                snoozeButtons(gap: gap)
            }
            VStack(alignment: .leading, spacing: gap) {
                snoozeLabel(wraps: false)
                snoozeButtons(gap: gap)
            }
            // **The fallback, and it is the one arrangement that must not be honest about
            // overflowing** (focus-vpu). The first two candidates are `fixedSize` so that "this
            // does not fit" is a real answer rather than a silent truncation; this one is what is
            // left when neither fits, and at the largest accessibility text size *it* demanded
            // 410 points inside a 348-point column — dragging every other action out with it,
            // because a leading-aligned stack is as wide as its widest child. Measured: all six
            // actions reported frames ending 46 points past the edge of the panel. So the last
            // candidate wraps instead of insisting, which is the layout adapting rather than the
            // person losing the buttons.
            VStack(alignment: .leading, spacing: gap) {
                snoozeLabel(wraps: true)
                ForEach(presentation.snoozeDurations, id: \.self) { span in
                    snoozeButton(span, wraps: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func snoozeLabel(wraps: Bool) -> some View {
        NudgeText(.accusationActionSnooze, voice: presentation.voice, role: .callout)
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(wraps ? nil : 1)
            .fixedSize(horizontal: !wraps, vertical: wraps)
    }

    private func snoozeButtons(gap: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(presentation.snoozeDurations, id: \.self) { span in
                snoozeButton(span, wraps: false)
            }
        }
    }

    private func snoozeButton(_ span: Duration, wraps: Bool) -> some View {
        Button {
            onAction(.snooze, span)
        } label: {
            Text(verbatim: NudgeCopy.duration(span))
                .font(DesignTokens.font(.callout, scale: textScale))
                // Never truncated: `ViewThatFits` can only choose a layout that fits if the
                // arrangement that does not fit says so instead of shrinking its own text. The
                // fallback wraps for the opposite reason — see `snoozeRow`.
                .lineLimit(wraps ? nil : 1)
                .fixedSize(horizontal: !wraps, vertical: wraps)
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
