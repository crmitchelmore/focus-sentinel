import FocusCore
import SwiftUI

/// **The popover behind the glyph** (R-91, F-82).
///
/// The Court's list, in the Court's order: the priority most prominent — because the product
/// boundary is that the priority outranks the app's opinions, and a command centre that led with
/// its own verdict would have inverted that — then the timer, then what the app currently
/// believes, then **the accusation and the question when reduced interruption routed one here**
/// (R-92), then what is snoozed, then the session controls and F-119's global switch.
///
/// The accusation sits above the question because it is the louder of the two and because U-2
/// says an accusation *waits* for a question rather than displacing it: when both are here, the
/// person meets them in the order the app raised them.
///
/// It draws **no score and no streak** (D-01): there is no "you were distracted for 42 minutes
/// today" here and no field one could be put in. What it shows are facts about right now.
public struct MenuBarPopoverView: DecisionSurfaceContent {
    private let presentation: MenuBarPresentation
    /// What was clicked. **Internal, so the unit lane can invoke it directly**: the popover
    /// performs nothing and the composition root decides everything.
    let onAction: (MenuBarAction) -> Void

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 10

    public init(
        presentation: MenuBarPresentation,
        onAction: @escaping (MenuBarAction) -> Void = { _ in }
    ) {
        self.presentation = presentation
        self.onAction = onAction
    }

    /// **Every row this popover draws, in the Court's order** (focus-din).
    ///
    /// A named list rather than a sequence of statements in one `VStack`, because the popover is
    /// drawn three ways now — whole, as context alone, and as decision alone — and three hand-
    /// written columns would be three things to keep in step. This is the closed set; the three
    /// renderings are folds over it, so a row added here appears in all of them or in none.
    enum Section: String, CaseIterable {
        case priority
        case status
        case belief
        case accusation
        case question
        case snoozes
        case session
        case sensing
        case openCockpit

        /// Whether this row is part of the **decision** the popover is carrying, for a given
        /// presentation.
        ///
        /// The pending accusation and the pending question are the only two rows that offer an
        /// action a nudge is charged for. Everything else is a command centre a person clicked
        /// into, and nothing in it is a nudge anybody is being asked to answer.
        ///
        /// **When both are drawn, the question is the decision** (e07a, focus-cxb). U-1 licenses
        /// the interruption *because* the question is cheaply answerable, and U-2 makes an
        /// accusation wait behind an open question rather than displace it — so the question is
        /// the live decision and the accusation the residual. Pinning both together needed over
        /// 815 points against a 911-point ceiling at the largest text size, so neither could be
        /// pinned and neither nudge was chargeable in that state. The accusation now scrolls with
        /// the context, and its charge in a both-state is the ledger's half of this ruling
        /// (`focus-6pr.4`): `NudgeHost` still reads the two nudges independently.
        /// **The rule is `MenuBarPresentation.pins(_:)`'s** (focus-6pr.4), not a second copy of
        /// it written here: the charge `NudgeHost` takes and the shelf this layout pins are the
        /// same ruling, and while they were two spellings the ledger's copy was the missing one.
        func isDecision(in presentation: MenuBarPresentation) -> Bool {
            switch self {
            case .question: presentation.pins(.query)
            case .accusation: presentation.pins(.accusation)
            default: false
            }
        }
    }

    public var body: some View {
        column(Section.allCases)
    }

    public static let decisionSurface: DecisionSurface = .menuBarPopover

    /// **Which part of the popover is the decision** (focus-din).
    ///
    /// ## And why the pinned rows move to the foot
    ///
    /// R-91's order — the priority most prominent, then the timer, then the belief, then the
    /// nudges — is the order of a surface a person can see all of. Once the popover has to scroll
    /// that order stops being about prominence and starts being about which rows survive: at
    /// `accessibilityLarge` on a 1080-point display **every** state of this popover scrolls, and
    /// the accusation's corrections and the question's answers were the rows below the fold. A
    /// nudge whose answers cannot be clicked is not charged, so the ladder parked.
    ///
    /// So when — and only when — the popover has to give way, the two nudge rows are pinned to
    /// the foot and the command centre scrolls above them. The Court's order stands whenever the
    /// popover fits, which is `nothingScrolls` and is what the great majority of people see;
    /// pinned, the thing the app interrupted for is the thing that cannot be scrolled away from.
    public var surfaceLayout: DecisionSurfaceLayout {
        DecisionSurfaceLayout(
            whole: AnyView(column(Section.allCases)),
            context: AnyView(column(Section.allCases.filter { !$0.isDecision(in: presentation) })),
            decision: AnyView(column(Section.allCases.filter { $0.isDecision(in: presentation) }))
        )
    }

    /// **The sections that are the decision, for this presentation** — the same rule
    /// `surfaceLayout` splits on, published so a test can hold the split against the ruling
    /// rather than against a picture.
    var decisionSections: [Section] {
        Section.allCases.filter { $0.isDecision(in: presentation) }
    }

    /// **Every catalog string this popover draws in a row of its own**, with the role it is drawn
    /// in, for a presentation (e07a, focus-0q4).
    ///
    /// Not the person's sentence, not the timer, and not the two nudges' own views — those have
    /// folds of their own. These are the labels the rows this file owns put in a column, and the
    /// fold `MenuBarPopoverLayoutTests` runs over them is the rule the rows are laid out by: **a
    /// column is never narrower than its longest word**, so every stacking row below grants a
    /// label the full content width the moment its siblings would squeeze it, and no label breaks
    /// mid-word at any size. A label added here and not to a stacking row is the next
    /// `Unr / elat / ed`.
    static func drawnLabels(
        for presentation: MenuBarPresentation
    ) -> [(text: String, role: DesignTokens.FontRole)] {
        var labels: [(text: String, role: DesignTokens.FontRole)] = [
            (String(localized: presentation.status.shortLabelResource), .body)
        ]
        if let rung = presentation.rung {
            labels.append((String(localized: ShellStrings.resource(.menuBarNudgeRung)), .footnote))
            labels.append((String(localized: rung.copyResource), .footnote))
        }
        if let band = presentation.band {
            labels.append((String(localized: ShellStrings.resource(.verdictBandLabel)), .footnote))
            labels.append((String(localized: band.labelResource), .footnote))
        }
        if presentation.pendingQuery != nil {
            labels.append((String(localized: ShellStrings.resource(.menuBarPendingQuestion)), .footnote))
        }
        if !presentation.snoozes.isEmpty {
            labels.append((String(localized: ShellStrings.resource(.menuBarSnoozedHeading)), .footnote))
            labels.append((String(localized: ShellStrings.resource(.menuBarCancelSnooze)), .footnote))
        }
        for key in [ShellStringKey.sessionActionStart, .sessionActionPause, .sessionActionComplete,
                    .sensingPauseLabel, .menuBarOpenCockpit] {
            labels.append((String(localized: ShellStrings.resource(key)), .callout))
        }
        return labels
    }

    /// The popover's column, over whichever sections it is being asked to draw.
    private func column(_ sections: [Section]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing, scale: textScale)) {
            ForEach(sections, id: \.self) { section in
                view(of: section)
            }
        }
        .padding(DesignTokens.spacing(spacing, scale: textScale))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// One row, including the divider that introduces it.
    ///
    /// The divider travels **with** the section rather than being a statement between two of
    /// them, so a section drawn on its own — the pinned decision — brings its own separator and a
    /// section that is not drawn takes its separator with it.
    @ViewBuilder
    private func view(of section: Section) -> some View {
        switch section {
        case .priority:
            priority
        case .status:
            statusRow
        case .belief:
            belief
        case .accusation:
            if let accusation = presentation.pendingAccusation {
                Divider()
                pendingAccusation(accusation)
            }
        case .question:
            if let query = presentation.pendingQuery {
                Divider()
                pendingQuestion(query)
            }
        case .snoozes:
            if !presentation.snoozes.isEmpty {
                Divider()
                snoozeList
            }
        case .session:
            Divider()
            sessionControls
        case .sensing:
            sensingSwitch
        case .openCockpit:
            Button { onAction(.openCockpit) } label: {
                ShellText(.menuBarOpenCockpit, role: .callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - The priority, first

    @ViewBuilder
    private var priority: some View {
        if let intent = presentation.priorityIntent, !intent.isEmpty {
            // `Text(verbatim:)` because this is the person's own sentence — data, not prose the
            // app authored, and the one string in this package that must never be transformed.
            Text(verbatim: intent)
                .font(DesignTokens.font(.headline, scale: textScale))
                .foregroundStyle(DesignTokens.Palette.primaryText)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ShellText(.priorityHeroEmpty, role: .headline)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The glyph and the timer

    /// The badge beside the timer where they fit, and the timer under the badge where they do
    /// not (e07a, focus-0q4). In one `HStack` the badge was handed a fraction of 300 points at
    /// the largest text size and its label broke mid-word — `Unr / elat / ed` — which is the
    /// column being narrower than its longest word. `ViewThatFits` measures the row at its ideal
    /// width and stacks it the moment it would not fit, so the label is never squeezed.
    private var statusRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.spacing(spacing, scale: textScale)) {
                StatusBadge(status: presentation.status)
                Spacer(minLength: 0)
                timer
            }
            VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                StatusBadge(status: presentation.status)
                timer
            }
        }
    }

    @ViewBuilder
    private var timer: some View {
        if !presentation.timerText.isEmpty {
            // The same monospaced-digit treatment as the menu-bar item itself (P-133), so a
            // person watching both does not see two different numbers of the same fact
            // drawn two different widths.
            Text(verbatim: presentation.timerText)
                .font(DesignTokens.font(.body, scale: textScale).monospacedDigit())
                .foregroundStyle(DesignTokens.Palette.primaryText)
        }
    }

    /// What the app currently believes, with its rung and its band — or nothing at all.
    ///
    /// Nothing at all is a real answer: before the first judgement the app has concluded
    /// nothing, and drawing a band it does not have would be inventing one.
    ///
    /// **Every value in this row is the present tense** (focus-7to). `presentation.rung` is
    /// `LadderState.rung` — *"the rung currently occupied"* — and its label read *"Next nudge"*,
    /// so the popover said **"Next nudge   Something you can answer"** directly above the
    /// answerable accusation that was on screen at that moment. The ladder has no scheduled next
    /// step to name: `LadderRung.escalated()` is computed on demand and `LadderMachine` gates it
    /// on four further facts — a still-live mandate, a delivered previous rung, `escalationDwell`
    /// elapsed since that delivery, and budget. Copy whose tense the mechanism cannot honour is
    /// the same defect as the notification copy that was removed and the Reduce Motion string
    /// that described a setting nothing read.
    /// Two labelled pairs side by side where they fit and stacked where they do not — and each
    /// pair the same again (e07a, focus-0q4). Four texts in one `HStack` each took a quarter of
    /// 300 points at the largest text size and broke mid-word — `Curr / ent / nudg / e`,
    /// `Eviden / ce`. A column is never narrower than its longest word: the row stacks, then the
    /// pair stacks, and a label always has the full content width to wrap at a word boundary.
    @ViewBuilder
    private var belief: some View {
        if presentation.rung != nil || presentation.band != nil {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DesignTokens.spacing(spacing, scale: textScale)) {
                    beliefPairs
                }
                VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                    beliefPairs
                }
            }
        }
    }

    @ViewBuilder
    private var beliefPairs: some View {
        if let rung = presentation.rung {
            labelled(.menuBarNudgeRung, value: rung.copyResource)
        }
        if let band = presentation.band {
            labelled(.verdictBandLabel, value: band.labelResource)
        }
    }

    private func labelled(
        _ key: ShellStringKey,
        value: LocalizedStringResource
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                labelledTexts(key, value: value)
            }
            VStack(alignment: .leading, spacing: 0) {
                labelledTexts(key, value: value)
            }
        }
    }

    @ViewBuilder
    private func labelledTexts(_ key: ShellStringKey, value: LocalizedStringResource) -> some View {
        ShellText(key, role: .footnote)
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        ShellText(resource: value, role: .footnote)
            .foregroundStyle(DesignTokens.Palette.primaryText)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The accusation, when reduced interruption sent it here (R-92, focus-uru)

    /// **The top rung, with the answers it is required to carry.**
    ///
    /// The defect this closes was that there were none. `SurfaceRouter` sends the panel rung to
    /// this surface whenever `reducedInterruption` is set — which the composition root forces on
    /// from `AppearanceObserver`'s traits under macOS Reduce Motion, and under the `silentVisual`
    /// deck, and while a microphone is running — and all the popover drew was the `belief` row
    /// above: *"Nudge: Panel"*, a read-only
    /// label. The repo's own rule is that a nudge you cannot answer back to is an anti-pattern
    /// and that every surface, including the top rung, is dismissible; for a Reduce Motion user
    /// that sentence was false, and U-1's licence to interrupt — earned by the answer being one
    /// cheap click — had nothing to spend.
    ///
    /// **The same view the panel draws**, exactly as `pendingQuestion(_:)` reuses
    /// `QueryPanelView`, so a rung routed here is the same rung with the same actions in the same
    /// order and the same announcement. A second rendering would be a second place its tone, its
    /// action set and its scope rules could drift — and it is the reuse that makes
    /// `AccusationPresentation.offeredActionIdentifiers` a true statement about this surface too.
    ///
    /// Routing these users to a panel instead was the alternative and is the wrong fix twice
    /// over: it overrides a setting the person chose, and the microphone case forbids it outright
    /// — a panel over a call is a panel everybody on the call can see.
    private func pendingAccusation(_ accusation: AccusationPresentation) -> some View {
        // **`.summoned`, and it is the only caller that says so** (focus-0nm). The popover is
        // shown by `MenuBarController.togglePopover()` and by nothing else — the person clicked
        // the status item — so it sits inside the menu bar's own idiom and keeps the material
        // an ordinary Mac popover has. The nudge panel is the uninvited surface and takes the
        // opaque branch; a popover that went opaque would be a second, unasked-for departure
        // from the platform in a design whose floor is the HIG.
        AccusationPanelView(presentation: accusation, provenance: .summoned) { action, span in
            onAction(.correct(action, snoozeDuration: span))
        }
    }

    // MARK: - The question, when reduced interruption sent it here (R-92)

    private func pendingQuestion(_ query: QueryPresentation) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(.menuBarPendingQuestion, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            // The **same view** the panel draws, so a question routed to the popover is the same
            // question with the same three answers and the same stated scope. A second rendering
            // of the question would be a second place its tone could drift.
            QueryPanelView(presentation: query, provenance: .summoned) { answer in
                onAction(.answerQuery(answer))
            }
        }
    }

    // MARK: - What is snoozed, and how to stop it

    private var snoozeList: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(.menuBarSnoozedHeading, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            ForEach(presentation.snoozes) { snooze in
                HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                    // The name, and only ever the name (focus-ebv). This row drew the snooze's
                    // own key, so the popover said "com.apple.Safari" beside its countdown while
                    // the context chips above it said "Safari".
                    Text(verbatim: snooze.subject.displayName)
                        .font(DesignTokens.font(.callout, scale: textScale))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(verbatim: NudgeCopy.countdown(snooze.remaining))
                        .font(DesignTokens.font(.callout, scale: textScale).monospacedDigit())
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    Button {
                        onAction(.cancelSnooze(subject: snooze.subject))
                    } label: {
                        ShellText(.menuBarCancelSnooze, role: .footnote)
                            .foregroundStyle(DesignTokens.Palette.accent(for: traits))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - The session, through e03's own verbs

    /// The session verbs, in one row where they fit and stacked where they do not.
    ///
    /// Every label is `fixedSize`, so a row that does not fit says so instead of truncating —
    /// "Start Sess…" is a verb a person has to guess at, which is the same defect as not
    /// offering it (the same fix the accusation panel's snooze row needed).
    private var sessionControls: some View {
        let gap = DesignTokens.spacing(spacing / 2, scale: textScale)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: gap) { sessionButtons }
            VStack(alignment: .leading, spacing: gap) { sessionButtons }
        }
    }

    @ViewBuilder
    private var sessionButtons: some View {
        sessionButton(.sessionActionStart) { onAction(.startSession) }
        sessionButton(.sessionActionPause) { onAction(.pauseSession) }
        sessionButton(.sessionActionComplete) { onAction(.completeSession) }
    }

    private func sessionButton(
        _ key: ShellStringKey,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            ShellText(key, role: .callout)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
    }

    /// F-119's one global switch, reachable without opening a window.
    ///
    /// The binding carries the value the person asked *for* rather than a toggle, so a popover
    /// drawn from a stale presentation cannot invert the switch. The label reads **positively**
    /// — "Watch what I am working on" — and is the cockpit's own key, because the menu bar is a
    /// second place to see one stored row rather than a second opinion about it.
    ///
    /// Drawn as a selectable row rather than as the cockpit's `NSSwitch`. Two reasons, and both
    /// are about this surface rather than about the setting: a menu-bar popover is a list of
    /// commands, and neither the switch nor the checkbox control rasterises under
    /// `ImageRenderer` — a baseline nobody can read is a baseline that proves nothing, so the
    /// row is built from the primitives the snapshot lane can actually draw. The state is
    /// carried to VoiceOver as a selection trait, so the control still announces whether it is
    /// on.
    private var sensingSwitch: some View {
        let isWatching = !presentation.sensingPaused
        return Button {
            onAction(.setSensingPaused(isWatching))
        } label: {
            HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                Image(systemName: isWatching ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                ShellText(.sensingPauseLabel, role: .callout)
                    // **Both**, and the first is the repair (e07a, focus-0q4). The bordered
                    // button style limits its label to one line, and `fixedSize` alone cannot
                    // lift that: the label read "Watch what I a…" at the largest text size in
                    // every committed picture, which for the channel a person is relying on is
                    // the same defect as not offering the switch. The inner limit wins.
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Text(ShellStrings.resource(.sensingPauseLabel)))
        .accessibilityAddTraits(isWatching ? [.isSelected] : [])
    }
}
