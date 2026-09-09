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
    /// One of the four static decks.
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
    /// Owner-selected shortcuts; custom durations use the same snooze action.
    public var snoozeDurations: [Duration] { [.seconds(60), .seconds(300), .seconds(1_200)] }

    public init(
        rung: LadderRung.Kind,
        voice: NudgeVoice = .standard,
        task: String,
        subject: NudgeSubject?,
        dwelled: Duration,
        returnTarget: String? = nil,
        snoozeRemaining: Duration? = nil,
        hasOpenSession: Bool
    ) {
        self.rung = rung
        self.voice = voice
        self.task = task
        self.subject = subject
        self.dwelled = dwelled
        self.returnTarget = returnTarget
        self.snoozeRemaining = snoozeRemaining
        self.hasOpenSession = hasOpenSession
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
    /// **Who put this on the screen** (focus-0nm, U-1).
    ///
    /// `.uninvited` by default, and the default is the point: this view exists to be raised by
    /// the app over whatever the person was looking at, which under U-1 is by definition the
    /// thing the app is interrupting them about. An uninvited surface is opaque whatever the
    /// traits say, so a full-screen video or a bright document cannot read through the sentence
    /// explaining itself. The one caller that is genuinely summoned — the popover under the
    /// status item the person clicked — says so.
    ///
    /// The default is deliberately the strict answer rather than the permissive one: forgetting
    /// to state it produces a legible surface, never a translucent one.
    let provenance: SurfaceProvenance

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12
    @State private var showsCustomSnooze = false
    @State private var customMinutes = "5"

    public init(
        presentation: AccusationPresentation,
        provenance: SurfaceProvenance = .uninvited,
        onAction: @escaping (CorrectionAction, Duration?) -> Void = { _, _ in }
    ) {
        self.presentation = presentation
        self.provenance = provenance
        self.onAction = onAction
    }

    private enum LayoutPart { case whole, context, decision }
    private var layoutPart: LayoutPart?

    @ViewBuilder
    public var body: some View {
        switch layoutPart {
        case .whole: column { context; actions }
        case .context: column { context }
        case .decision: column { actions }
        case nil: styledContent
        }
    }

    private var styledContent: some View {
        column { context; actions }
            // The rule lives in this inset, never on top of the words (see `decisionRuleInset`).
            .padding(.leading, DesignTokens.decisionRuleInset)
            .shellSurface(
                DesignTokens.material(for: traits, provenance: provenance),
                in: Rectangle(),
                traits: traits
            )
            .overlay(alignment: .leading) {
                // **The rule is drawn, and it is not the only channel** (focus-0nm). Colour is
                // the fourth channel here as everywhere else: the grammar of the title (R-96v),
                // the action set and the announcement all already say which surface this is, and
                // a person who cannot use colour loses nothing by this rule being absent. So it
                // is hidden from the accessibility tree rather than labelled — a rule with a
                // spoken name would be VoiceOver reading out a decoration.
                if let tint = DesignTokens.decisionRuleTint(for: Self.decisionSurface, traits: traits) {
                    Rectangle()
                        .fill(tint)
                        .frame(width: DesignTokens.decisionRuleWidth)
                        .accessibilityHidden(true)
                }
            }
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
            whole: AnyView(layoutView(.whole)),
            context: AnyView(layoutView(.context)),
            decision: AnyView(layoutView(.decision))
        )
    }

    // Return a View value; read its Environment only after SwiftUI installs it.
    private func layoutView(_ part: LayoutPart) -> Self {
        var view = self
        view.layoutPart = part
        return view
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
        if provenance == .uninvited && textScale == .standard {
            CompanionHeader { ShellText(.cockpitWindowTitle, role: .title2) }
        }
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

    /// **The row where it fits, and the glyph above the title where it does not** (focus-6pr.5,
    /// on the rule focus-0q4 laid the popover's own rows out under).
    ///
    /// The header is `badge · title · spacer · dismiss`. Inside the 300-point popover at
    /// `accessibilityLarge` the title column was narrower than its longest word and the committed
    /// picture broke one: `propo / sal`, `waitin / g`. A column is never narrower than its
    /// longest word — so it stacks.
    ///
    /// **`.frame(idealWidth:)` is the whole of the repair, and it is not a trick.** A plain
    /// `ViewThatFits` measures the first candidate's *ideal* width, and a wrapping `Text`'s ideal
    /// width is its whole single-line width — so on the 380-point panel the header would have
    /// stacked at standard size for any task sentence longer than about thirty characters, moving
    /// every accusation baseline for a row that fits perfectly well. That is the objection this
    /// bead was deferred for. Setting the title's ideal width to the width of its **longest word**
    /// makes the candidate's measurement ask the question the rule is about: *is there room for a
    /// word?* — not *is there room for the sentence?* The real layout is untouched, because a
    /// definite proposal overrides an ideal.
    /// The row candidate alone, exposed so it can be measured (see `headerRowIdealWidth`). It is
    /// the same value the `ViewThatFits` below offers first, not a copy of it.
    var headerRowCandidate: some View {
        headerRow
    }

    private var headerRow: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: DesignTokens.spacing(spacing, scale: textScale)
        ) {
            badge
            // **No `Spacer` here, and that is the second half of the repair.** A `Spacer`'s ideal
            // width is infinite, so a `ViewThatFits` measuring a row that contains one rejects it
            // at every width and stacks always — which is the regression this bead was deferred
            // over, arrived at from the other direction. The title takes the slack instead: its
            // IDEAL width is its longest word, which is the question the rule asks, and its
            // MAXIMUM is the whole row, which is what pushes the dismissal to the trailing edge.
            title.frame(
                idealWidth: Self.headerTitleLongestWordWidth(
                    presentation: presentation,
                    scale: textScale
                ),
                maxWidth: .infinity,
                alignment: .leading
            )
            dismissButton
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow
            VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                HStack(spacing: DesignTokens.spacing(spacing, scale: textScale)) {
                    badge
                    Spacer(minLength: 0)
                    dismissButton
                }
                title
            }
        }
    }

    /// The same token set every other surface draws, so the panel and the menu bar can never
    /// disagree about what the app believes (F-83, F-146).
    private var badge: some View {
        StatusBadge(status: .unrelated, showsLabel: false)
    }

    private var title: some View {
        NudgeText(
            .accusationPanelTitle,
            voice: presentation.voice,
            arguments: [presentation.task],
            role: .headline
        )
        .foregroundStyle(DesignTokens.Palette.primaryText)
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The header's arithmetic, published so a test can measure it (focus-6pr.5)

    /// The role the header's title is set in. One place, read by the view and by the fold.
    static let headerTitleRole: DesignTokens.FontRole = .headline

    /// The header's title, resolved exactly as `NudgeText` resolves it.
    static func headerTitle(presentation: AccusationPresentation) -> String {
        NudgeCopy.string(
            voice: presentation.voice,
            .accusationPanelTitle,
            arguments: [presentation.task]
        )
    }

    /// The widest single word of that title, measured in the font it is drawn in.
    ///
    /// `NSFont` rather than `Text`: this is the number the layout is decided by, so it has to be
    /// the same number the test measures, and a `Text` cannot be asked its width outside a
    /// rendering pass.
    static func headerTitleLongestWordWidth(
        presentation: AccusationPresentation,
        scale: ShellTextScale
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: DesignTokens.pointSize(headerTitleRole, scale: scale))
        return headerTitle(presentation: presentation)
            .split(whereSeparator: \.isWhitespace)
            .map { NSAttributedString(string: String($0), attributes: [.font: font]).size().width }
            .max() ?? 0
    }

    /// **The ideal width of the header ROW, measured by SwiftUI's own layout** (focus-6pr.5).
    ///
    /// This is the number `ViewThatFits` decides on: the real badge, the real dismissal, the real
    /// spacings, and a title whose ideal width is its longest word. `fittingSize` is the ideal
    /// size — the unspecified proposal a `ViewThatFits` candidate is measured with —
    /// and `sizeThatFits(in:)` with a large proposal would answer the maximum instead, which for
    /// a row that can grow is a different number entirely.
    ///
    /// Measured rather than added up from tokens, because a first draft that added them up was
    /// **56 points wrong** and the fold it fed was green over a picture reading `propo / sal`.
    ///
    /// It measures at the shell's standard scale: `@Environment` resolves inside a `body`, and a
    /// view value built outside one reads the default. That is enough for what this is for — the
    /// property being asserted is that the ideal tracks the longest WORD rather than the whole
    /// sentence, which is scale-free. The largest-size half of the claim is the re-recorded
    /// picture, read by eye, which is also where the defect was found.
    @MainActor
    static func headerRowIdealWidth(presentation: AccusationPresentation) -> CGFloat {
        let controller = NSHostingController(
            rootView: AccusationPanelView(presentation: presentation).headerRowCandidate
        )
        return controller.view.fittingSize.width
    }

    /// What the row asks for over and above the word it is drawn around: the badge chip, the
    /// dismissal and the two gaps. A constant of the row, which is the whole point — it does not
    /// depend on the sentence.
    @MainActor
    static func headerFurnitureWidth(presentation: AccusationPresentation) -> CGFloat {
        headerRowIdealWidth(presentation: presentation)
            - headerTitleLongestWordWidth(presentation: presentation, scale: .standard)
    }

    /// The close affordance. **Every surface is dismissible** (D-07), including this one and
    /// including rung 3; Escape does the same thing through `NudgePanel.cancelOperation(_:)`
    /// once the panel has been clicked into — from another application it reaches that
    /// application, because the panel is never made key (see `NudgePanel`).
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
            plainActionButton(action).buttonStyle(CompanionButtonStyle(prominent: true))
        } else {
            plainActionButton(action).buttonStyle(CompanionButtonStyle())
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

    /// Three one-click shortcuts and a custom editor, with a stacked fallback at large text sizes.
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
                customSnoozeButton
            }
        }
        .popover(isPresented: $showsCustomSnooze) {
            customSnoozeEditor
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
            customSnoozeButton
        }
    }

    private var customSnoozeButton: some View {
        Button {
            showsCustomSnooze = true
        } label: {
            ShellText(.nudgeSnoozeCustom, role: .callout)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(CompanionButtonStyle())
        .accessibilityIdentifier("nudge-snooze-custom")
    }

    /// Limit the editor to a positive whole number of minutes, up to one day.
    private var customSnoozeDuration: Duration? {
        guard let minutes = Int(customMinutes.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...1_440).contains(minutes) else { return nil }
        return .seconds(minutes * 60)
    }

    private var customSnoozeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShellText(.nudgeSnoozeCustomMinutes, role: .callout)
            TextField(ShellStrings.string(.nudgeSnoozeCustomMinutes), text: $customMinutes)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("nudge-snooze-custom-minutes")
                .onSubmit { applyCustomSnooze() }
            HStack {
                Button { showsCustomSnooze = false } label: {
                    ShellText(.priorityCompleteActionCancel, role: .callout)
                }
                Spacer()
                Button { applyCustomSnooze() } label: {
                    NudgeText(.accusationActionSnooze, voice: presentation.voice, role: .callout)
                    if let span = customSnoozeDuration {
                        Text(verbatim: NudgeCopy.duration(span))
                    }
                }
                .buttonStyle(CompanionButtonStyle(prominent: true))
                .disabled(customSnoozeDuration == nil)
            }
        }
        .font(DesignTokens.font(.callout, scale: textScale))
        .padding(16)
        .frame(minWidth: 260)
    }

    private func applyCustomSnooze() {
        guard let span = customSnoozeDuration else { return }
        showsCustomSnooze = false
        onAction(.snooze, span)
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
        .buttonStyle(CompanionButtonStyle())
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
