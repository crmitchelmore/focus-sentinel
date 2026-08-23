import FocusCore
import SwiftUI

/// A session phase, drawn.
///
/// ## Why this is not `StatusBadge` with a different enum
///
/// `FocusStatus` and `SessionPhase` answer different questions — *what does the app make of
/// what you are looking at* and *what are you doing about it* — and they are shown together, so
/// they must not be mistakable for one another. They are also different sizes: five statuses
/// against six phases, and `StatusShape` has exactly five cases. Reusing it would have meant
/// either giving two phases the same silhouette, which defeats the whole point of a second
/// channel, or inventing a sixth shape nothing else uses.
///
/// ## The channels, and the one that is deliberately absent
///
/// Two non-colour channels, always: a **distinct SF Symbol** and a **label that is never
/// hidden**. Colour is a third and is never alone. There is no outline silhouette here, and
/// that is a decision rather than an omission — the badge's job beside the status badge is to
/// read as a *different kind of thing*, and the capsule with no inner outline is what makes the
/// two tell apart at a glance even in monochrome.
///
/// The label is not optional. `StatusBadge` lets a caller ask for a glyph-only badge and forces
/// the label back on under Differentiate Without Colour; this badge never offers the choice,
/// because six phases is more than a person should be asked to learn six glyphs for.
///
/// `SessionPhaseSnapshotTests` renders all six under `differentiateWithoutColor` and asserts
/// every pair is a different picture.
public struct SessionPhaseBadge: View {
    public let phase: SessionPhase

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .title3) private var glyphSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    public init(phase: SessionPhase) {
        self.phase = phase
    }

    public var body: some View {
        let emphasis = DesignTokens.emphasis(for: traits)

        return HStack(spacing: spacing) {
            Image(systemName: Self.symbolName(for: phase))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.tint(for: phase))
                .font(DesignTokens.font(.title3, scale: textScale))
                .frame(
                    width: DesignTokens.spacing(glyphSize, scale: textScale),
                    height: DesignTokens.spacing(glyphSize, scale: textScale)
                )
                .accessibilityHidden(true)

            ShellText(Self.labelKey(for: phase), role: .callout)
                .foregroundStyle(DesignTokens.Palette.primaryText)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, spacing)
        .padding(.vertical, spacing / 2)
        .shellSurface(DesignTokens.material(for: traits), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    DesignTokens.Palette.separator.opacity(emphasis.outlineOpacity),
                    lineWidth: emphasis.borderWidth
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(ShellStrings.resource(Self.labelKey(for: phase))))
    }

    /// The glyph for a phase. Six silhouettes that differ from each other **and** from the five
    /// `FocusStatus` glyphs, because both badges appear on the cockpit at once.
    nonisolated public static func symbolName(for phase: SessionPhase) -> String {
        switch phase {
        case .focus: "scope"
        case .intentionalDetour: "arrow.triangle.branch"
        case .onBreak: "figure.walk"
        case .paused: "pause.fill"
        case .interrupted: "bolt.horizontal.fill"
        case .complete: "flag.checkered"
        }
    }

    /// The catalog key for a phase's label. `FocusCore` owns the machine and `FocusUI` owns the
    /// words: the session machine returns typed values and never a string (plan R-52).
    nonisolated public static func labelKey(for phase: SessionPhase) -> ShellStringKey {
        switch phase {
        case .focus: .sessionBadgeFocus
        case .intentionalDetour: .sessionBadgeDetour
        case .onBreak: .sessionBadgeBreak
        case .paused: .sessionBadgePaused
        case .interrupted: .sessionBadgeInterrupted
        case .complete: .sessionBadgeComplete
        }
    }

    /// The catalog key for a pause cause, phrased to finish the sentence "Paused because …".
    ///
    /// The three lock-and-sleep causes all end "as far as macOS tells us", which is not padding:
    /// the Feasibility Court forbade any copy that claims exact lock detection, and this is
    /// where the app would otherwise make that claim (goal criterion 13).
    nonisolated public static func labelKey(for cause: PauseReason) -> ShellStringKey {
        switch cause {
        case .user: .sessionCauseUser
        case .sensitiveApp: .sessionCauseSensitiveApp
        case .globalPause: .sessionCauseGlobalPause
        case .screenLocked: .sessionCauseScreenLocked
        case .displaysAsleep: .sessionCauseDisplaysAsleep
        case .systemAsleep: .sessionCauseSystemAsleep
        case .sessionInactive: .sessionCauseSessionInactive
        case .relaunch: .sessionCauseRelaunch
        case .systemRestart: .sessionCauseSystemRestart
        }
    }

    /// The catalog key for something restoration had to say about the session.
    nonisolated public static func labelKey(
        for note: RestoredSession.ReconciliationNote
    ) -> ShellStringKey {
        switch note {
        case .rebootedDuringSession: .sessionNoteRebooted
        case .restoredStale: .sessionNoteStale
        case .clockAnomaly: .sessionNoteClockAnomaly
        }
    }
}
