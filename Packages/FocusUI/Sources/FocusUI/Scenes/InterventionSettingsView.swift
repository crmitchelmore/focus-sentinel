import FocusCore
import SwiftUI
import UserNotifications

/// **What the person has set, and what the app has spent** (R-98).
///
/// A value, so the pane renders with no store, no clock and no notification centre — which is
/// what lets the routing matrix be snapshot-tested against `SurfaceRouter`'s own table rather
/// than against a description of it.
public struct InterventionSettings: Sendable, Equatable {
    /// One of the five static decks.
    public var voice: NudgeVoice
    /// F-148's flag. Forced on by `accessibilityDisplayShouldReduceMotion`, and the pane says so.
    public var reducedInterruption: Bool
    /// Whether Reduce Motion is what turned it on, in which case the switch is shown as forced
    /// rather than as a preference the person could change here.
    public var reducedInterruptionIsForced: Bool
    /// The person's own window, or `nil` for off — which is what ships (R-85).
    public var quietHours: QuietHoursWindow?
    /// From `getNotificationSettings`, which never prompts (P-134).
    public var authorisation: NotificationAuthorisation
    /// Today's spend, from `InterventionLog.budget(on:priorityID:)`. Shown as usage over the
    /// cap — **information, never a score** (D-01).
    public var usage: InterruptionBudget
    /// e03's presentation exclusion list: applications the person has said are not
    /// presentations, so a full-screen editor does not silence the app all afternoon.
    public var presentationExclusions: [String]

    public init(
        voice: NudgeVoice = .standard,
        reducedInterruption: Bool = false,
        reducedInterruptionIsForced: Bool = false,
        quietHours: QuietHoursWindow? = InterventionPolicy.quietHoursDefault,
        authorisation: NotificationAuthorisation = .notRequested,
        usage: InterruptionBudget = .empty,
        presentationExclusions: [String] = []
    ) {
        self.voice = voice
        self.reducedInterruption = reducedInterruption
        self.reducedInterruptionIsForced = reducedInterruptionIsForced
        self.quietHours = quietHours
        self.authorisation = authorisation
        self.usage = usage
        self.presentationExclusions = presentationExclusions
    }
}

/// What the pane asks the composition root to do.
public enum InterventionSettingsAction: Sendable, Equatable {
    case setVoice(NudgeVoice)
    case setReducedInterruption(Bool)
    case setQuietHours(QuietHoursWindow?)
    case removePresentationExclusion(String)
    /// The **one** user-initiated authorisation request in the repository (R-96g). The pane
    /// performs the call itself — that is what makes the lint's "exactly one file" assertion
    /// mean something — and reports the outcome so the root can re-read the settings.
    case notificationAuthorisationChanged
}

/// **The only place in this repository that asks for a permission** (R-96g, SC-5).
///
/// It is a free function in this file rather than a method on a service, because R-96g asserts
/// that `requestAuthorization(` appears in **exactly one source file** and that the file is the
/// settings pane's action. A service would be a second file and the assertion would have to be
/// weakened to accommodate it.
///
/// Everything else about notifications is decided from `getNotificationSettings`, which P-134
/// measured never prompting — so no routing path, no host and no gate stage can reach this
/// function, and `requestAuthorizationCallCount == 0` in every automated run is a property of
/// the call graph rather than of a counter somebody remembered to leave alone.
@MainActor
public enum NotificationConsent {
    /// Ask, once, because a person clicked a button that says so.
    ///
    /// Offered only when nobody has been asked yet (`NotificationAuthorisation.mayOfferToEnable`
    /// is `notRequested` alone) — asking somebody who has already said no is the re-prompt
    /// F-127's policy forbids.
    public static func ask(_ completion: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert]) { granted, _ in
                Task { @MainActor in completion(granted) }
            }
    }
}

/// **The Intervention settings pane** (R-98, R-92, F-132, F-148).
///
/// Six sections, and one of them is the honest answer to a question a person is entitled to ask:
///
/// * the **voice**, five static decks and no sixth;
/// * **reduced interruption**, which is a routing flag inside the existing router rather than a
///   second surface stack (R-92) — and which Reduce Motion forces on, as the pane says;
/// * **quiet hours**, off by default and explicitly *not* the system Focus (R-85, P-137);
/// * **notifications**, with the one sanctioned request and the never-re-prompt policy;
/// * **what happens if I say no** — `SurfaceRouter.table(…)` rendered as a plain matrix, so the
///   copy cannot drift from the behaviour, because it *is* the behaviour;
/// * the **caps and thresholds**, as read-only mirrors of `InterventionPolicy` with today's
///   usage beside them.
///
/// The usage rows are **information, never a score** (D-01): "2 / 4 questions today" is a fact
/// about what the app did, and there is no streak, no total and no trend anywhere on this pane
/// for a person to feel they are failing.
public struct InterventionSettingsView: View {
    private let settings: InterventionSettings
    /// What was clicked. **Internal, so the unit lane can invoke it directly.**
    let onAction: (InterventionSettingsAction) -> Void

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(
        settings: InterventionSettings,
        onAction: @escaping (InterventionSettingsAction) -> Void = { _ in }
    ) {
        self.settings = settings
        self.onAction = onAction
    }

    /// How far one press moves a quiet-hours boundary.
    ///
    /// Half an hour, and buttons rather than a `DatePicker`: the AppKit date picker does not
    /// rasterise under `ImageRenderer`, so a picker here would ship a baseline nobody could
    /// read — and a snapshot nobody can read is a snapshot that proves nothing.
    nonisolated public static let quietHoursStep = 30
    /// Minutes in a day, for the wrap. The window itself wraps midnight by construction
    /// (`end` may be less than `start`), so this is arithmetic rather than a rule.
    nonisolated public static let minutesPerDay = 1_440

    /// Laid out as one column with **no scroll view**, and that is a rendering decision with a
    /// measurement behind it — the same one `PrivacySettingsView` records. A `ScrollView`
    /// reports no intrinsic height, so under `ImageRenderer` a pane inside one rasterises as a
    /// blank rectangle and the committed baseline would be a picture of nothing. The Settings
    /// window sizes itself to the tab's content instead.
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing, scale: textScale)) {
            // **All seven fields of `InterventionSettings`, each reported beside the section that
            // draws it** (focus-7ow).
            //
            // Two of the seven were reported before, from the Settings *window*, and the other
            // five — quiet hours, the authorisation, today's spend, the exclusion list, and
            // whether Reduce Motion forced the switch — could be replaced with anything at all
            // while the whole nineteen-stage gate stayed green. They are what the person is
            // shown when they ask "what will this app do, and when will it leave me alone".
            voiceSection
                .shellRendered(.interventionVoice, settings.voice.rawValue)
            Divider()
            reducedInterruptionSection
                .shellRendered(
                    .reducedInterruption, settings.reducedInterruption ? "on" : "off"
                )
                .shellRendered(
                    .reducedInterruptionForced,
                    settings.reducedInterruptionIsForced ? "forced" : "chosen"
                )
            Divider()
            quietHoursSection
                .shellRendered(.quietHours, ShellValueDigest.describe(settings.quietHours))
            Divider()
            notificationSection
                .shellRendered(.notificationAuthorisation, settings.authorisation.rawValue)
            Divider()
            routingMatrix
            Divider()
            capsSection
                .shellRendered(.interruptionUsage, ShellValueDigest.describe(settings.usage))
            Divider()
            thresholdsSection
            Divider()
            exclusionsSection
                .shellRendered(
                    .presentationExclusions,
                    ShellValueDigest.describe(settings.presentationExclusions)
                )
        }
        .padding(DesignTokens.spacing(spacing, scale: textScale))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(.interventionVoiceLabel, role: .headline)
            ForEach(NudgeVoice.allCases, id: \.self) { voice in
                Button {
                    onAction(.setVoice(voice))
                } label: {
                    HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                        Image(
                            systemName: voice == settings.voice
                                ? "largecircle.fill.circle"
                                : "circle"
                        )
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                        ShellText(Self.voiceKey(voice), role: .callout)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text(ShellStrings.resource(Self.voiceKey(voice))))
                .accessibilityAddTraits(voice == settings.voice ? [.isSelected] : [])
            }
        }
    }

    /// Each deck's name. Declared as a total switch, so a sixth voice is a compile error here
    /// rather than a blank row in a settings pane.
    nonisolated public static func voiceKey(_ voice: NudgeVoice) -> ShellStringKey {
        switch voice {
        case .neutral: .interventionVoiceNeutral
        case .warm: .interventionVoiceWarm
        case .direct: .interventionVoiceDirect
        case .playful: .interventionVoicePlayful
        case .silentVisual: .interventionVoiceSilentVisual
        }
    }

    // MARK: - Reduced interruption (R-92, F-148)

    private var reducedInterruptionSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            Button {
                onAction(.setReducedInterruption(!settings.reducedInterruption))
            } label: {
                HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                    Image(
                        systemName: settings.reducedInterruption
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                    ShellText(.interventionReducedLabel, role: .headline)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(settings.reducedInterruptionIsForced)
            .accessibilityLabel(Text(ShellStrings.resource(.interventionReducedLabel)))
            .accessibilityAddTraits(settings.reducedInterruption ? [.isSelected] : [])

            ShellText(
                settings.reducedInterruptionIsForced
                    ? .interventionReducedForced
                    : .interventionReducedExplanation,
                role: .footnote
            )
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Quiet hours (R-85)

    private var quietHoursSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                ShellText(.interventionQuietHoursLabel, role: .headline)
                Spacer(minLength: 0)
                Button {
                    onAction(.setQuietHours(settings.quietHours == nil ? Self.startingWindow : nil))
                } label: {
                    ShellText(
                        settings.quietHours == nil
                            ? .interventionQuietHoursTurnOn
                            : .interventionQuietHoursTurnOff,
                        role: .callout
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
            }

            if let window = settings.quietHours {
                HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                    Text(verbatim: Self.render(window))
                        .font(DesignTokens.font(.body, scale: textScale).monospacedDigit())
                    Spacer(minLength: 0)
                    boundaryButtons(window)
                }
            } else {
                ShellText(.interventionQuietHoursOff, role: .callout)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }

            // **The sentence that keeps a capability claim honest.** The app makes no claim to
            // read the system Focus: P-137 measured the private route unreadable as well as
            // forbidden, so what it honours is this window and — on the notification rung only —
            // whatever `UNUserNotificationCenter` honours for free.
            ShellText(.interventionQuietHoursExplanation, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func boundaryButtons(_ window: QuietHoursWindow) -> some View {
        HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            adjust(.interventionQuietHoursStartEarlier) {
                onAction(.setQuietHours(Self.moved(window, startBy: -Self.quietHoursStep)))
            }
            adjust(.interventionQuietHoursStartLater) {
                onAction(.setQuietHours(Self.moved(window, startBy: Self.quietHoursStep)))
            }
            adjust(.interventionQuietHoursEndEarlier) {
                onAction(.setQuietHours(Self.moved(window, endBy: -Self.quietHoursStep)))
            }
            adjust(.interventionQuietHoursEndLater) {
                onAction(.setQuietHours(Self.moved(window, endBy: Self.quietHoursStep)))
            }
        }
    }

    private func adjust(
        _ key: ShellStringKey,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            ShellText(key, role: .footnote)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
    }

    /// The window a person gets when they first switch quiet hours on.
    ///
    /// **Not a shipped default.** `InterventionPolicy.quietHoursDefault` is `nil` and stays
    /// `nil`; this is the starting point of an edit somebody deliberately began, which is a
    /// different thing from the app having an opinion about their evenings.
    nonisolated public static let startingWindow = QuietHoursWindow(
        startMinuteOfDay: 22 * 60,
        endMinuteOfDay: 8 * 60
    )

    nonisolated public static func moved(
        _ window: QuietHoursWindow,
        startBy delta: Int = 0,
        endBy endDelta: Int = 0
    ) -> QuietHoursWindow {
        QuietHoursWindow(
            startMinuteOfDay: wrapped(window.startMinuteOfDay + delta),
            endMinuteOfDay: wrapped(window.endMinuteOfDay + endDelta)
        )
    }

    nonisolated private static func wrapped(_ minute: Int) -> Int {
        ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }

    /// `22:00 – 08:00`. Digits, so it is data rather than prose.
    nonisolated public static func render(_ window: QuietHoursWindow) -> String {
        "\(clock(window.startMinuteOfDay)) – \(clock(window.endMinuteOfDay))"
    }

    nonisolated private static func clock(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                ShellText(.interventionNotificationsLabel, role: .headline)
                Spacer(minLength: 0)
                ShellText(
                    resource: ShellStrings.resource(
                        Self.authorisationKey(settings.authorisation)
                    ),
                    role: .callout
                )
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }

            // **Offered once, to the one state that has never been asked.** Showing it to
            // somebody who said no would be the re-prompt F-127 forbids, and showing it inside a
            // nudge would be asking for a permission at the moment they are least inclined to
            // think about it.
            if settings.authorisation.mayOfferToEnable {
                Button {
                    NotificationConsent.ask { _ in
                        onAction(.notificationAuthorisationChanged)
                    }
                } label: {
                    ShellText(.interventionNotificationsEnable, role: .callout)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
            }

            ShellText(.interventionNotificationsExplanation, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    nonisolated public static func authorisationKey(_ state: NotificationAuthorisation) -> ShellStringKey {
        switch state {
        case .authorised: .interventionAuthorisationAuthorised
        case .denied: .interventionAuthorisationDenied
        case .notRequested: .interventionAuthorisationNotRequested
        case .provisional: .interventionAuthorisationProvisional
        }
    }

    // MARK: - The routing matrix — the honest answer to "what if I say no"

    /// **The rendered table is `SurfaceRouter.table(…)` itself**, not a description of it.
    ///
    /// R-82 requires the routing table to be a value precisely so this pane can render it: a
    /// pane that explained the routing in prose would be a pane somebody has to remember to
    /// edit. `InterventionSettingsTests` asserts the rendered rows equal the router's own, so
    /// the copy cannot drift from the behaviour because it is not copy.
    private var routingMatrix: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(.interventionRoutingHeading, role: .headline)
            ShellText(.interventionRoutingExplanation, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(drawnRows, id: \.self) { row in
                HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                    ShellText(resource: row.rung.copyResource, role: .footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ShellText(
                        resource: ShellStrings.resource(Self.authorisationKey(row.authorisation)),
                        role: .footnote
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ShellText(
                        resource: ShellStrings.resource(Self.surfaceKey(row.route)),
                        role: .footnote
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The rows this pane draws, for the settings the person actually has.
    ///
    /// Exposed so the test compares the **drawn** rows against `SurfaceRouter.table(…)` rather
    /// than re-deriving them, which would be the test agreeing with itself.
    nonisolated public var drawnRows: [SurfaceRoutingRow] {
        SurfaceRouter.table(
            reducedInterruption: settings.reducedInterruption,
            voice: settings.voice
        )
    }

    nonisolated public static func surfaceKey(_ route: SurfaceRoute) -> ShellStringKey {
        switch route {
        case .surface(let surface):
            switch surface {
            case .menuBar: .interventionSurfaceMenuBar
            case .panel: .interventionSurfacePanel
            case .notification: .interventionSurfaceNotification
            case .popoverBadge: .interventionSurfacePopoverBadge
            }
        case .unavailable: .interventionSurfaceUnavailable
        }
    }

    // MARK: - The caps, as usage (D-01)

    private var capsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(.interventionCapsHeading, role: .headline)
            usageRow(
                .interventionCapsQueriesPriority,
                used: settings.usage.queriesForPriorityToday,
                cap: InterventionPolicy.dailyQueryCap
            )
            usageRow(
                .interventionCapsQueriesDay,
                used: settings.usage.queriesAllPrioritiesToday,
                cap: InterventionPolicy.dailyQueryCapAllPriorities
            )
            usageRow(
                .interventionCapsAccusations,
                used: settings.usage.accusationsToday,
                cap: InterventionPolicy.dailyAccusationCap
            )
            usageRow(
                .interventionCapsInterruptions,
                used: settings.usage.interruptionsToday,
                cap: InterventionPolicy.dailyInterruptionCap
            )
            ShellText(.interventionCapsExplanation, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func usageRow(_ key: ShellStringKey, used: Int, cap: Int) -> some View {
        HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(key, role: .callout)
            Spacer(minLength: 0)
            // Digits, monospaced, and no bar: a progress bar is a thing to fill, and a thing to
            // fill is a score to defend (D-01).
            Text(verbatim: "\(used) / \(cap)")
                .font(DesignTokens.font(.callout, scale: textScale).monospacedDigit())
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
        }
    }

    // MARK: - The thresholds, as read-only mirrors

    /// Read-only, and read from `InterventionPolicy` — so the numbers a person sees are the
    /// numbers the app uses, and there is no second place for them to drift.
    private var thresholdsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(.interventionThresholdsHeading, role: .headline)
            thresholdRow(.interventionThresholdQueryDwell, InterventionPolicy.queryDwellThreshold)
            thresholdRow(.interventionThresholdQueryCooldown, InterventionPolicy.queryCooldown)
            thresholdRow(
                .interventionThresholdAccusationCooldown,
                RelevancePolicy.mandateCooldown
            )
            thresholdRow(
                .interventionThresholdEscalation,
                RelevancePolicy.escalationDwell
            )
            HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                ShellText(.interventionThresholdSnooze, role: .callout)
                Spacer(minLength: 0)
                Text(
                    verbatim: InterventionPolicy.snoozeDurations
                        .map(NudgeCopy.duration)
                        .joined(separator: ", ")
                )
                .font(DesignTokens.font(.callout, scale: textScale))
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }
        }
    }

    private func thresholdRow(_ key: ShellStringKey, _ span: Duration) -> some View {
        HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(key, role: .callout)
            Spacer(minLength: 0)
            Text(verbatim: NudgeCopy.duration(span))
                .font(DesignTokens.font(.callout, scale: textScale))
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
        }
    }

    // MARK: - e03's presentation exclusions

    private var exclusionsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(.interventionExclusionsHeading, role: .headline)
            if settings.presentationExclusions.isEmpty {
                ShellText(.interventionExclusionsEmpty, role: .callout)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(settings.presentationExclusions, id: \.self) { subject in
                    HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                        Text(verbatim: subject)
                            .font(DesignTokens.font(.callout, scale: textScale))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button {
                            onAction(.removePresentationExclusion(subject))
                        } label: {
                            ShellText(.interventionExclusionsRemove, role: .footnote)
                                .foregroundStyle(DesignTokens.Palette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
