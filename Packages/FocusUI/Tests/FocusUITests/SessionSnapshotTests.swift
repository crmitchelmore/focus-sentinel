import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// The fixed values every session render is drawn from.
///
/// Fixed, and fixed in a *file*, for the same reason `PriorityFixture` is: a baseline whose
/// content depends on the clock, the locale or the machine is a baseline that fails on somebody
/// else's Tuesday. Every date here is an explicit `timeIntervalSince1970` — `Date()` is banned
/// repository-wide, tests included (R-26).
enum SessionFixture {
    /// 2026-01-01T00:00:00Z, the same instant `PriorityFixture` uses.
    static let now = Date(timeIntervalSince1970: 1_767_225_600)

    static let sessionID = UUID(uuidString: "E0300000-0000-4000-A000-000000000001")!
    static let taskID = UUID(uuidString: "E0200000-0000-4000-A000-000000000001")!

    /// Ninety minutes, which is the figure the zero-grant restoration proof also uses.
    static let elapsedSeconds: Double = 5_400

    static func session(
        phase: SessionPhase,
        pauseCauses: Set<PauseReason> = [],
        resumeTo: ResumablePhase? = nil,
        notes: Set<RestoredSession.ReconciliationNote> = []
    ) -> SessionSnapshot {
        SessionSnapshot(
            sessionID: sessionID,
            taskID: taskID,
            phase: phase,
            pauseCauses: pauseCauses,
            resumeTo: resumeTo,
            kind: .openEnded,
            startedAt: now,
            notes: notes
        )
    }

    /// A session paused for two reasons at once, one of which the person cannot clear.
    ///
    /// This is the case the whole cause mechanism exists for: a user pause taken during a screen
    /// lock survives the unlock, and the Resume control has to say so rather than being pressed
    /// and doing nothing (R-45, goal criterion 37a).
    static let doublyPaused = session(
        phase: .paused,
        pauseCauses: [.user, .screenLocked],
        resumeTo: .focus
    )

    /// A session that came back from a relaunch across a reboot with the clock moved under it —
    /// every reconciliation note at once, so the baseline shows the worst case rather than the
    /// tidy one.
    static let restored = session(
        phase: .paused,
        pauseCauses: [.systemRestart],
        resumeTo: .onBreak,
        notes: [.rebootedDuringSession, .restoredStale, .clockAnomaly]
    )
}

/// Every session surface the snapshot matrix covers.
///
/// The **interruption sheet is deliberately absent**, and the reason is measured rather than
/// aesthetic: an AppKit-backed control does not rasterise under `ImageRenderer` — a `TextField`
/// or a `Picker` draws SwiftUI's yellow "unrenderable view" placeholder whatever appearance is
/// injected. Committing a baseline of that sheet would mean committing a picture of a broken
/// control and calling it evidence. It is covered structurally here instead, and by the
/// TCC-gated live frames where AppKit draws it for real.
enum SessionComponent: String, CaseIterable, Sendable {
    case sessionPhaseFocus
    case sessionPhaseDetour
    case sessionPhaseBreak
    case sessionPhasePaused
    case sessionPhaseInterrupted
    case sessionPhaseComplete
    case sessionControlsFocus
    case sessionControlsDoublyPaused
    case sessionControlsRestored
    case sessionControlsNone

    /// The badges size themselves; the controls wrap inside a fixed width so that growing text
    /// grows the *height*, which is what the dynamic-type assertions read.
    var width: CGFloat? { isBadge ? nil : 520 }

    var isBadge: Bool { phase != nil }

    /// The phase a badge component draws, or `nil` for the controls.
    var phase: SessionPhase? {
        switch self {
        case .sessionPhaseFocus: .focus
        case .sessionPhaseDetour: .intentionalDetour
        case .sessionPhaseBreak: .onBreak
        case .sessionPhasePaused: .paused
        case .sessionPhaseInterrupted: .interrupted
        case .sessionPhaseComplete: .complete
        case .sessionControlsFocus, .sessionControlsDoublyPaused,
             .sessionControlsRestored, .sessionControlsNone:
            nil
        }
    }

    @MainActor
    var view: AnyView {
        if let phase {
            return AnyView(SessionPhaseBadge(phase: phase))
        }
        switch self {
        case .sessionControlsFocus:
            return controls(SessionFixture.session(phase: .focus))
        case .sessionControlsDoublyPaused:
            return controls(SessionFixture.doublyPaused)
        case .sessionControlsRestored:
            return controls(SessionFixture.restored)
        case .sessionControlsNone:
            return controls(nil)
        default:
            preconditionFailure("every badge case is handled above")
        }
    }

    @MainActor
    private func controls(_ session: SessionSnapshot?) -> AnyView {
        AnyView(
            FocusHost { focus in
                SessionControls(
                    session: session,
                    elapsedSeconds: session == nil ? nil : SessionFixture.elapsedSeconds,
                    focus: focus
                )
            }
        )
    }
}

/// The F-157 snapshot lane, extended to e03's session surfaces.
///
/// Same machinery as e01's and e02's: `ImageRenderer` inside the ordinary unit lane, with every
/// appearance variant and every text size **injected** rather than read from the system, so a
/// Mac with every accessibility setting switched off still renders all five variants
/// deterministically. Lane-gated on compiled String Catalogs, because under `swift test` SwiftPM
/// copies the catalogs and every label would render as its own key.
@Suite("Session snapshots", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct SessionSnapshotTests {
    @Test(
        "every session surface matches its baseline in every appearance variant",
        arguments: SessionComponent.allCases, AppearanceTraits.namedVariants.map(\.name)
    )
    func componentMatchesBaseline(component: SessionComponent, variant: String) throws {
        for size in SnapshotTypeSize.allCases {
            try SnapshotHarness.assertSnapshot(
                component.view,
                component: component.rawValue,
                variant: variant,
                textScale: size.textScale,
                width: component.width
            )
        }
    }

    @Test("light and dark are different pictures", arguments: SessionComponent.allCases)
    func lightAndDarkDiffer(component: SessionComponent) throws {
        let light = try render(component, variant: "light")
        let dark = try render(component, variant: "dark")
        #expect(
            PNGCompare.areDistinct(light.pixels, dark.pixels),
            "\(component.rawValue) ignores dark mode"
        )
    }

    @Test("increased contrast changes the picture", arguments: SessionComponent.allCases)
    func increasedContrastDiffers(component: SessionComponent) throws {
        let plain = try render(component, variant: "light")
        let contrasted = try render(component, variant: "increasedContrast")
        #expect(
            PNGCompare.areDistinct(plain.pixels, contrasted.pixels),
            "\(component.rawValue) ignores Increase Contrast"
        )
    }

    // MARK: - The channel that has to survive colour blindness

    /// Six phases, none of which may be told apart by hue alone.
    ///
    /// The badge draws two non-colour channels — a distinct SF Symbol and a label that is never
    /// hidden — so every pair has to differ as a *picture* with Differentiate Without Colour on.
    /// This is the assertion that keeps both channels honest: delete the label and the
    /// `paused`/`complete` pair would still differ by glyph, but delete the glyph difference too
    /// and this fails.
    @Test("every session phase renders distinctly without colour")
    func everyPhaseIsDistinctWithoutColour() throws {
        let traits = AppearanceTraits(colorScheme: .light, differentiateWithoutColor: true)
        var renders: [(phase: SessionPhase, snapshot: Snapshot)] = []

        for phase in SessionPhase.allCases {
            renders.append(
                (
                    phase,
                    try SnapshotHarness.render(
                        SessionPhaseBadge(phase: phase),
                        traits: traits,
                        width: nil,
                        name: "sessionPhase.differentiateWithoutColor.\(phase.rawValue)"
                    )
                )
            )
        }

        #expect(renders.count == 6)
        for (index, subject) in renders.enumerated() {
            for other in renders[(index + 1)...] {
                #expect(
                    PNGCompare.areDistinct(subject.snapshot.pixels, other.snapshot.pixels),
                    "\(subject.phase.rawValue) and \(other.phase.rawValue) render identically without colour"
                )
            }
        }
    }

    /// Every phase has its own glyph and its own label key. The picture test above would catch
    /// a collision too, but this says *which* channel collided.
    @Test("no two phases share a glyph or a label key")
    func phaseChannelsAreUnique() {
        let glyphs = SessionPhase.allCases.map(SessionPhaseBadge.symbolName(for:))
        #expect(Set(glyphs).count == glyphs.count, "two phases share an SF Symbol: \(glyphs)")

        let keys = SessionPhase.allCases.map(SessionPhaseBadge.labelKey(for:))
        #expect(Set(keys).count == keys.count)

        // …and no phase glyph may collide with a status glyph either: both badges appear on the
        // cockpit at once, and two identical silhouettes side by side would be worse than one.
        let statusGlyphs = Set(FocusStatus.allCases.map(\.symbolName))
        #expect(Set(glyphs).isDisjoint(with: statusGlyphs))
    }

    // MARK: - What the controls say, and what they refuse to say

    /// Every pause cause, every reconciliation note and every interruption reason has a label.
    ///
    /// A `switch` over an enum makes that true at compile time; this asserts the *other* half —
    /// that no two of them resolve to the same words, which is the failure a copy-paste in the
    /// label table produces and which the compiler cannot see.
    @Test("every typed session reason resolves to its own distinct words")
    func everyReasonHasDistinctWords() {
        let causes = PauseReason.allCases.map { ShellStrings.string(SessionPhaseBadge.labelKey(for: $0)) }
        #expect(Set(causes).count == causes.count, "two pause causes read the same: \(causes)")

        let notes = RestoredSession.ReconciliationNote.allCases
            .map { ShellStrings.string(SessionPhaseBadge.labelKey(for: $0)) }
        #expect(Set(notes).count == notes.count)

        let reasons = InterruptionReason.allCases
            .map { ShellStrings.string(InterruptionSheet.labelKey(for: $0)) }
        #expect(Set(reasons).count == reasons.count)
    }

    /// **No copy anywhere claims exact screen-lock detection** (goal criterion 13).
    ///
    /// The three lock-and-sleep causes and the four lock-and-sleep lifecycle lines all end with
    /// the same hedge, and they end with it because the Feasibility Court required it: a
    /// `pmset displaysleepnow` produced no `screensDidSleepNotification` at all on this macOS
    /// (probe P-88), so the app knows what macOS told it and no more than that.
    @Test("no lock or sleep string claims certainty")
    func lockCopyNeverClaimsCertainty() {
        let hedge = "as far as macOS tells us"

        for cause in [PauseReason.screenLocked, .displaysAsleep, .systemAsleep] {
            let text = ShellStrings.string(SessionPhaseBadge.labelKey(for: cause))
            #expect(text.contains(hedge), "\(cause.rawValue) claims certainty: \(text)")
        }

        for lifecycle in [SystemLifecycle.active, .screenLocked, .displaysAsleep, .systemAsleep] {
            let text = ShellStrings.string(SensingStatusView.lifecycleKey(for: lifecycle))
            #expect(text.contains(hedge), "\(lifecycle.rawValue) claims certainty: \(text)")
        }
    }

    /// A paused session with a cause the person did not set must not offer a live Resume.
    ///
    /// The machine would reject `resumed(cause: .user)` with `notPausedForThatCause`, so the
    /// surface disables the control and lists the reasons instead. This asserts the value the
    /// control reads, and the render above is what shows the reasons being drawn.
    @Test("resume is offered only when the person owns every cause")
    func resumeIsAuthorisedByCause() {
        #expect(!SessionFixture.doublyPaused.userMayResume)
        #expect(SessionFixture.doublyPaused.causesTheUserCannotClear == [.screenLocked])

        let userOnly = SessionFixture.session(phase: .paused, pauseCauses: [.user], resumeTo: .focus)
        #expect(userOnly.userMayResume)
        #expect(userOnly.causesTheUserCannotClear.isEmpty)

        // A session the *system* paused alone is not resumable by the person at all.
        let lockOnly = SessionFixture.session(
            phase: .paused,
            pauseCauses: [.screenLocked],
            resumeTo: .focus
        )
        #expect(!lockOnly.userMayResume)
    }

    /// The elapsed figure is a formatted `Duration`, never minutes interpolated into a sentence.
    @Test("elapsed time is formatted as a duration in every band")
    func elapsedIsFormattedAsADuration() {
        #expect(!SessionControls.format(0).isEmpty)
        #expect(!SessionControls.format(6).isEmpty)
        #expect(!SessionControls.format(SessionFixture.elapsedSeconds).isEmpty)
        // Negative input cannot happen — `startedAt` is never rewritten and the wall clock is
        // injected — but a formatter that produced "-1 min" would be a worse answer than zero.
        #expect(!SessionControls.format(-10).isEmpty)
    }

    // MARK: -

    private func render(_ component: SessionComponent, variant: String) throws -> Snapshot {
        try SnapshotHarness.render(
            component.view,
            traits: SnapshotHarness.variantTraits(named: variant),
            width: component.width,
            name: "\(component.rawValue).distinctness.\(variant)"
        )
    }
}

/// **The session controls' grouping by consequence, held to the machine rather than to taste**
/// (focus-w41, e11 direction §5.1).
///
/// Runs on every lane — no catalogs, no rendering — because the question is structural: `D02`
/// showed five identically weighted lozenges in which pausing a session and ending one were the
/// same object, and the repair splits them into three registers. The register a verb lands in is
/// a claim about what the verb *costs*, and the one claim that can be checked mechanically is
/// which phases can still be ended at all.
@Suite("Session controls group by consequence")
struct SessionConsequenceTests {
    /// The endings are offered in exactly the phases `SessionMachine` would accept an ending in.
    ///
    /// Not a restatement of `offersAnEnding`'s own switch: the right-hand side is the real
    /// transition table, asked the real question, one phase at a time. A future round that made
    /// `complete` legal from a terminal phase — or illegal from a paused one — would fail here
    /// rather than producing a button that is refused on press, which is the shape
    /// `SessionControls` exists to refuse to draw.
    @Test("a verb that ends the session is offered exactly where the machine accepts one")
    func endingsMatchTheTransitionTable() {
        for phase in SessionPhase.allCases {
            let state = SessionState(
                phase: phase,
                pauseCauses: phase == .paused ? [.user] : [],
                phaseChangedAt: SessionFixture.now
            )
            let outcome = SessionMachine.apply(.completed, to: state, at: SessionFixture.now)
            let machineAccepts = if case .accepted = outcome { true } else { false }

            #expect(
                phase.offersAnEnding == machineAccepts,
                """
                the session controls offer an ending in \(phase) (\(phase.offersAnEnding)) and the \
                machine answers \(outcome) — a button offered where the table refuses is a button \
                that teaches people the app is unreliable
                """
            )
        }
    }
}
