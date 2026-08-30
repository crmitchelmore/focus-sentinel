import FocusCore
import SwiftUI

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
        usage: InterruptionBudget = .empty,
        presentationExclusions: [String] = []
    ) {
        self.voice = voice
        self.reducedInterruption = reducedInterruption
        self.reducedInterruptionIsForced = reducedInterruptionIsForced
        self.quietHours = quietHours
        self.usage = usage
        self.presentationExclusions = presentationExclusions
    }
}

/// What the pane asks the composition root to do.
///
/// **There is no `notificationAuthorisationChanged`** (focus-wy0). It was the report that the
/// pane's own `requestAuthorization` had returned, and both are gone: this app posts no
/// notifications, so there is no permission for a person to grant it and nothing to re-read when
/// they do.
public enum InterventionSettingsAction: Sendable, Equatable {
    case setVoice(NudgeVoice)
    case setReducedInterruption(Bool)
    case setQuietHours(QuietHoursWindow?)
    case removePresentationExclusion(String)
}

/// **The Intervention settings pane** (R-98, R-92, F-132, F-148).
///
/// Five sections, and one of them is the honest answer to a question a person is entitled to ask:
///
/// * the **voice**, five static decks and no sixth;
/// * **reduced interruption**, which is a routing flag inside the existing router rather than a
///   second surface stack (R-92) — and which Reduce Motion forces on, as the pane says;
/// * **quiet hours**, off by default and explicitly *not* the system Focus (R-85, P-137);
/// * **where a nudge appears** — `SurfaceRouter.table(…)` rendered as a plain matrix, so the
///   copy cannot drift from the behaviour, because it *is* the behaviour;
/// * the **caps and thresholds**, as read-only mirrors of `InterventionPolicy` with today's
///   usage beside them.
///
/// **There was a sixth, and it asked for a system permission this app cannot use** (focus-wy0).
/// It drew the notification authorisation, and a "Turn on notifications" button whenever nobody
/// had been asked — which is every fresh install — under copy promising that *"the last step of a
/// nudge appears in the app instead"*. That last step was the recommitment rung, deferred to
/// focus-5ab by U-2; since then no rung has routed to a notification and the three routing tables
/// the Release binary reports at `authorised`, `denied` and `notRequested` have been identical.
/// The button therefore raised a real `UNUserNotificationCenter` prompt to buy nothing. Under
/// this product's privacy tenets that is worse than a dead control, so the section, its copy, its
/// action and the one `requestAuthorization` call site in the repository were deleted rather than
/// disabled.
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
            // **All six fields of `InterventionSettings`, each reported beside the section that
            // draws it** (focus-7ow).
            //
            // Two of them were reported before, from the Settings *window*, and the other four —
            // quiet hours, today's spend, the exclusion list, and whether Reduce Motion forced
            // the switch — could be replaced with anything at all while the whole nineteen-stage
            // gate stayed green. They are what the person is shown when they ask "what will this
            // app do, and when will it leave me alone".
            //
            // There were seven. The notification authorisation went with the section that drew
            // it (focus-wy0).
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
            // forbidden, so what it honours is this window and nothing else.
            //
            // It used to add *"notifications still follow your Mac's Focus, because the system
            // applies it for us"* — true of an app that posts notifications, and this one does
            // not (focus-wy0). A true sentence about a capability the app has given up is still
            // a claim a person will read as a capability.
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

    // MARK: - The routing matrix — where a nudge actually appears

    /// **The rendered table is `SurfaceRouter.table(…)` itself**, not a description of it.
    ///
    /// R-82 requires the routing table to be a value precisely so this pane can render it: a
    /// pane that explained the routing in prose would be a pane somebody has to remember to
    /// edit. `InterventionSettingsTests` asserts the rendered rows equal the router's own, so
    /// the copy cannot drift from the behaviour because it is not copy.
    ///
    /// **Two columns, and it used to draw three** (focus-wy0). The middle one was the notification
    /// authorisation, and the four rows it produced for each rung carried four different headings
    /// over one identical route. A table whose extra column never changes an answer is a table
    /// making a promise about consequence that the router does not keep.
    private var routingMatrix: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            ShellText(.interventionRoutingHeading, role: .headline)
            ShellText(.interventionRoutingExplanation, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(drawnRows, id: \.self) { row in
                if let key = Self.surfaceKey(row.route) {
                    HStack(spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
                        ShellText(resource: row.rung.copyResource, role: .footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ShellText(resource: ShellStrings.resource(key), role: .footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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

    /// The sentence for a route, **or nothing when the pane has no business drawing one**
    /// (focus-pzl).
    ///
    /// ## Why this went from total to partial
    ///
    /// `SurfaceRoute` is wider than this pane's domain by exactly two cases, and both of them
    /// had a shipped sentence nobody could reach. `settings.intervention.surface.notification`
    /// read *"A notification"* four lines under
    /// `settings.intervention.routing.explanation` — *"Every step of a nudge appears inside
    /// Focus. It never sends a notification, and never asks for permission to."* The catalogue
    /// held the row that contradicted the app's own promise, and the switch arm that mentioned
    /// the key was what passed it through the string lint.
    ///
    /// Neither can be handed to this function by anything the pane draws.
    /// `SurfaceRouter.table(…)` pins `presentation: .notPresenting`, `media: .idle` and
    /// `menuBarVisible: true`, so no row can be `.unavailable`; and no branch of `route(…)`
    /// returns `.notification` at all since U-2 deferred the recommitment rung to focus-5ab —
    /// the shipped binary says so about itself, with `surfacesARungCanReach = [menuBar, panel]`.
    ///
    /// ## What happens if that stops being true
    ///
    /// `routingMatrix` draws no row for a route with no sentence, and
    /// `InterventionSettingsTests.everyDrawnRowHasASentence` fails over the whole voice × flag
    /// cross-product the moment the router produces one. That is the difference this change is
    /// about: the day focus-5ab puts a rung back on a notification, the gate says *"this route
    /// has no copy"* instead of a person reading a sentence the app spent a year contradicting.
    nonisolated public static func surfaceKey(_ route: SurfaceRoute) -> ShellStringKey? {
        switch route {
        case .surface(.menuBar): .interventionSurfaceMenuBar
        case .surface(.panel): .interventionSurfacePanel
        case .surface(.popoverBadge): .interventionSurfacePopoverBadge
        case .surface(.notification), .unavailable: nil
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
            //
            // **`.formatted()`, not interpolation** (focus-7zr's sweep). String interpolation of
            // an `Int` is `String(describing:)` and draws Western Arabic digits in every locale;
            // every other number this app shows a person goes through `.formatted()` —
            // `CascadePrecedenceView`'s rank, `RecentPrioritiesView`'s attachment count,
            // `SensingStatusView`'s readings. This row was the one that did not, and
            // `Text(verbatim:)` is why nothing noticed: it is the construct the string lint
            // exempts by design.
            Text(verbatim: "\(used.formatted()) / \(cap.formatted())")
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
                        // An exclusion is filed under a bundle identifier — `SensingHost` tests
                        // it against `cleared.bundleIdentifier` — and the row below removes it by
                        // that same key. The row *reads* the name (focus-7zr): "Not presentations"
                        // over a list of `com.apple.Keynote` is a list of things the person has to
                        // decode before they can decide whether to remove one.
                        Text(verbatim: SubjectDisplay.name(of: subject, resolvingApplication: true))
                            .font(DesignTokens.font(.callout, scale: textScale))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button {
                            onAction(.removePresentationExclusion(subject))
                        } label: {
                            ShellText(.interventionExclusionsRemove, role: .footnote)
                                .foregroundStyle(DesignTokens.Palette.accent(for: traits))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
