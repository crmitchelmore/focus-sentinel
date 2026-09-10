import FocusCore
import SwiftUI

/// What the app is actually watching, said plainly — including when the answer is "nothing".
///
/// ## The defect this replaces
///
/// e01's cockpit drew one line, `shell.cockpit.sensing.unavailable`, whatever was happening
/// underneath it. The glyph changed between an open eye and a closed one; the words did not. So
/// the shell said "sensing unavailable" while it was observing and said the same thing while it
/// was switched off, and neither statement was checkable against anything.
///
/// The rule this view exists to keep is the plain one: **when sensing is off, or a capability is
/// unavailable, the app says so.** It never implies it is watching when it is not, and — the
/// half that is easier to get wrong — it never implies it is *not* watching when it is.
///
/// ## Three states, and they are told apart by their causes
///
/// * **Watching.** Attached, with observers on it. The line says what is read (which app is in
///   front) and, just as importantly, what is not (titles, screenshots, keystrokes).
/// * **Switched off.** The person turned it off. The switch detaches every observer rather than
///   setting a flag, and the copy says that rather than "paused".
/// * **Detached.** The graph believes it attached and the platform gave it no tokens. A
///   different fact from the one above and a different sentence, because telling somebody they
///   switched something off when they did not is worse than saying nothing.
///
/// `isWatching` requires **both** halves — `isObserving` and a non-zero observer count — for
/// exactly that reason: a surface trusting only the first would claim to be watching on a Mac
/// where every registration silently failed.
///
/// ## What it may show, and what it has no member for
///
/// Counts, states and closed-vocabulary facts. There is no application name here, no window
/// title, no document and no URL, because `SensingSummary` has nowhere to put one. The
/// microphone line may say a microphone is running; nothing here can say a meeting is
/// occurring, because `MediaActivity` has no member such a claim could be built from.
public struct SensingStatusView: View {
    public let summary: SensingSummary

    /// The capabilities, so the surface can name the ones that are reduced. Drawn only where
    /// `showsReducedCapabilities` is on — the cockpit shows them, because a person looking at
    /// the status line deserves to know what is missing from it.
    public let capabilities: CapabilityMatrix

    /// The eight capabilities the *watching* depends on, and therefore the only ones a status
    /// line about watching should name.
    ///
    /// The other four belong to epics that have not landed — Accessibility depth, screenshots,
    /// notifications and the on-device model — and every one of them is permanently
    /// `.notRequested` or `.unavailable` here. Listing them beside the sensing status would put
    /// four standing lines under a window whose whole point is one sentence, and would say
    /// nothing about what the app is doing now. They are drawn in full, all twelve, by
    /// `CapabilityMatrixView` in Privacy settings, which is the surface that exists to be
    /// complete.
    nonisolated public static let sensingCapabilities: [Capability] = [
        .frontmostApplication,
        .windowMetadata,
        .idle,
        .systemLifecycle,
        .displayGeometry,
        .presentation,
        .microphoneActivity,
        .cameraActivity
    ]

    /// Whether to list the capabilities that are not `.available`.
    public let showsReducedCapabilities: Bool

    /// Whether to draw the per-signal detail rows. The cockpit's footer wants the one-line
    /// answer; the Privacy pane wants the working.
    public let showsDetail: Bool

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    public init(
        summary: SensingSummary,
        capabilities: CapabilityMatrix = CapabilityMatrix(),
        showsReducedCapabilities: Bool = false,
        showsDetail: Bool = false
    ) {
        self.summary = summary
        self.capabilities = capabilities
        self.showsReducedCapabilities = showsReducedCapabilities
        self.showsDetail = showsDetail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing / 2) {
            headline

            if showsDetail {
                detail
            }

            // Only while something is actually attached. A graph that is switched off has one
            // thing to say and the headline says it; following that with eight lines of "never
            // asked for" would bury the sentence that matters under a list of facts about a
            // machine nobody is currently reading.
            if showsReducedCapabilities, summary.isWatching {
                reduced
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(.sensingHeading)))
        // **What this view actually said, reported from where it said it** (focus-h7h).
        //
        // The cockpit's footer is the one place this reaches the report: the Privacy pane's copy
        // of it lives inside a `TabView` that builds only the pane a person selected, so the
        // Settings window reports its own sensing line from `ShellSettingsView` instead. The two
        // fields are separate — `sensingSummary` and `privacySummary` — because a shell that told
        // the truth in one window and not in the other is a real defect and one shared name would
        // be satisfied by whichever drew first.
        .shellRendered(
            .sensingSummary,
            Self.renderedDescription(
                summary: summary,
                capabilities: capabilities,
                showsReducedCapabilities: showsReducedCapabilities
            )
        )
    }

    // MARK: - The one line that must always be true

    private var headline: some View {
        Label {
            ShellText(Self.headlineKey(for: summary), role: .footnote)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: summary.isWatching ? "eye" : "eye.slash")
        }
        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
    }

    /// Which sentence the current state deserves.
    ///
    /// Deliberately a `static` function over the value rather than a property on
    /// `SensingSummary`: `FocusCore` owns the facts and `FocusUI` owns the words, so the state
    /// machine never returns a string (plan R-52).
    nonisolated public static func headlineKey(for summary: SensingSummary) -> ShellStringKey {
        if summary.isWatching { return .sensingStatusWatching }
        return summary.isPausedByUser ? .sensingStatusPaused : .sensingStatusDetached
    }

    /// **What this view puts on the screen, as one comparable line** (focus-h7h).
    ///
    /// One function with two callers — this view, which reports it as the value it drew, and
    /// `AppComposition`, which computes what it expects from the live graph — for the reason
    /// `headlineKey(for:)` is shared with the tests: a second derivation written out beside the
    /// first is a second thing to keep in step, and a comparison between two drifting
    /// derivations proves nothing about the window.
    ///
    /// It carries the sentence *and* the capabilities the view names beneath it, because the two
    /// mutations this field exists to catch differ in the second: a Privacy pane handed
    /// `SensingSummary.inactive` draws a different sentence, and one handed an unprobed
    /// `CapabilityMatrix` draws the same sentence over a different list.
    nonisolated public static func renderedDescription(
        summary: SensingSummary,
        capabilities: CapabilityMatrix,
        showsReducedCapabilities: Bool
    ) -> String {
        var line = headlineKey(for: summary).rawValue
        if showsReducedCapabilities, summary.isWatching {
            let named = capabilities.allStates
                .filter { sensingCapabilities.contains($0.capability) && !$0.state.isUsable }
                .map { "\($0.capability.rawValue)=\($0.state.rawValue)" }
            line += "|" + named.joined(separator: ",")
        }
        return line
    }

    // MARK: - The working

    /// One line per signal, each drawn whether the answer is yes or no.
    ///
    /// Showing the working only when the answer is interesting would be showing half of it: a
    /// person who wants to know whether the app thinks they are at the keyboard is owed the
    /// answer in both directions.
    private var detail: some View {
        VStack(alignment: .leading, spacing: spacing / 3) {
            count(.sensingObserversLabel, summary.liveObserverCount, symbol: "antenna.radiowaves.left.and.right")
            count(.sensingRedundantLabel, summary.redundantActivations, symbol: "arrow.triangle.2.circlepath")

            row(
                Self.lifecycleKey(for: summary.lifecycle),
                symbol: summary.lifecycle.isActive ? "lock.open" : "lock"
            )
            row(
                summary.isUserIdle ? .sensingIdleAway : .sensingIdlePresent,
                symbol: summary.isUserIdle ? "moon.zzz" : "keyboard"
            )
            row(
                summary.media.microphoneRunning ? .sensingMicRunning : .sensingMicIdle,
                symbol: summary.media.microphoneRunning ? "mic" : "mic.slash"
            )
            // The camera half is pinned off on **every** Mac in v1, and the two reasons are
            // different sentences: there is no camera here, or there is one and this version
            // does not use it. Neither is a denial and neither invites the person to fix
            // anything (plan R-40).
            row(
                summary.cameraReason == .noDevices ? .sensingCameraNoDevices : .sensingCameraHeld,
                symbol: "video.slash"
            )
            row(
                summary.presentation.isPresenting ? .sensingPresentationOn : .sensingPresentationOff,
                symbol: summary.presentation.isPresenting
                    ? "rectangle.inset.filled.on.rectangle"
                    : "macwindow"
            )
            row(
                summary.isOnSecondaryDisplay ? .sensingDisplaySecondary : .sensingDisplayPrimary,
                symbol: summary.isOnSecondaryDisplay ? "display.2" : "display"
            )
        }
    }

    private func row(_ key: ShellStringKey, symbol: String) -> some View {
        Label {
            ShellText(key, role: .footnote)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
    }

    /// A labelled number. The number is data and is drawn verbatim; only the label is prose.
    private func count(_ key: ShellStringKey, _ value: Int, symbol: String) -> some View {
        Label {
            HStack(spacing: spacing / 2) {
                ShellText(key, role: .footnote)
                Text(verbatim: value.formatted())
                    .font(DesignTokens.font(.footnote, scale: textScale))
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: symbol)
        }
        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
    }

    // MARK: - What is missing, named

    /// The capabilities that are not available, by name and state.
    ///
    /// No call to action of any kind. F-126 is explicit that a button here would be an ask in
    /// disguise, and in this epic the app could not ask even if somebody added one: every
    /// prompting API is banned from the shipping graph by lint.
    @ViewBuilder
    private var reduced: some View {
        let rows = capabilities.allStates.filter {
            !$0.state.isUsable && Self.sensingCapabilities.contains($0.capability)
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: spacing / 3) {
                ForEach(rows, id: \.capability) { entry in
                    Label {
                        HStack(spacing: spacing / 2) {
                            ShellText(CapabilityMatrixView.labelKey(for: entry.capability), role: .footnote)
                            ShellText(CapabilityMatrixView.labelKey(for: entry.state), role: .footnote)
                                .foregroundStyle(DesignTokens.tint(for: entry.state))
                        }
                    } icon: {
                        Image(systemName: "minus.circle")
                    }
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                }
            }
        }
    }

    // MARK: - Labels

    /// What the Mac itself is doing, in words that **never claim exact lock detection**.
    ///
    /// Every one of these ends "as far as macOS tells us", and that is a Court condition rather
    /// than a hedge: `screensDidSleepNotification` did not fire at all for a real
    /// `pmset displaysleepnow` on this macOS (probe P-88), and the signal that did — the
    /// loginwindow activation — is a strong indication and not a guarantee.
    nonisolated public static func lifecycleKey(for lifecycle: SystemLifecycle) -> ShellStringKey {
        switch lifecycle {
        case .active: .sensingLifecycleActive
        case .screenLocked: .sensingLifecycleScreenLocked
        case .displaysAsleep: .sensingLifecycleDisplaysAsleep
        case .systemAsleep: .sensingLifecycleSystemAsleep
        case .sessionInactive: .sensingLifecycleSessionInactive
        case .poweringOff: .sensingLifecyclePoweringOff
        }
    }
}
