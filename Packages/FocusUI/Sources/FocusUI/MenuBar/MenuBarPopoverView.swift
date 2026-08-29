import FocusCore
import SwiftUI

/// **The popover behind the glyph** (R-91, F-82).
///
/// The Court's list, in the Court's order: the priority most prominent — because the product
/// boundary is that the priority outranks the app's opinions, and a command centre that led with
/// its own verdict would have inverted that — then the timer, then what the app currently
/// believes, then the question when reduced interruption routed one here (R-92), then what is
/// snoozed, then the session controls and F-119's global switch.
///
/// It draws **no score and no streak** (D-01): there is no "you were distracted for 42 minutes
/// today" here and no field one could be put in. What it shows are facts about right now.
public struct MenuBarPopoverView: View {
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

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing, scale: textScale)) {
            priority
            statusRow
            belief
            if let query = presentation.pendingQuery {
                Divider()
                pendingQuestion(query)
            }
            if !presentation.snoozes.isEmpty {
                Divider()
                snoozeList
            }
            Divider()
            sessionControls
            sensingSwitch
            Button { onAction(.openCockpit) } label: {
                ShellText(.menuBarOpenCockpit, role: .callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
        .padding(DesignTokens.spacing(spacing, scale: textScale))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
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

    private var statusRow: some View {
        HStack(spacing: DesignTokens.spacing(spacing, scale: textScale)) {
            StatusBadge(status: presentation.status)
            Spacer(minLength: 0)
            if !presentation.timerText.isEmpty {
                // The same monospaced-digit treatment as the menu-bar item itself (P-133), so a
                // person watching both does not see two different numbers of the same fact
                // drawn two different widths.
                Text(verbatim: presentation.timerText)
                    .font(DesignTokens.font(.body, scale: textScale).monospacedDigit())
                    .foregroundStyle(DesignTokens.Palette.primaryText)
            }
        }
    }

    /// What the app currently believes, with its rung and its band — or nothing at all.
    ///
    /// Nothing at all is a real answer: before the first judgement the app has concluded
    /// nothing, and drawing a band it does not have would be inventing one.
    @ViewBuilder
    private var belief: some View {
        if presentation.rung != nil || presentation.band != nil {
            HStack(spacing: DesignTokens.spacing(spacing, scale: textScale)) {
                if let rung = presentation.rung {
                    labelled(.menuBarNudgeRung, value: rung.copyResource)
                }
                if let band = presentation.band {
                    labelled(.verdictBandLabel, value: band.labelResource)
                }
            }
        }
    }

    private func labelled(
        _ key: ShellStringKey,
        value: LocalizedStringResource
    ) -> some View {
        HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(key, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            ShellText(resource: value, role: .footnote)
                .foregroundStyle(DesignTokens.Palette.primaryText)
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
            QueryPanelView(presentation: query) { answer in
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
                    Text(verbatim: snooze.subject)
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
