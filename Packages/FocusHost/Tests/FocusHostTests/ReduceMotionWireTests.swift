import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **Reduce Motion reaches the nudge loop, driven rather than asserted about** (focus-w7v).
///
/// ## The defect
///
/// Six places in this repository said `AppearanceObserver` forces `reducedInterruption` on under
/// macOS Reduce Motion. Nothing did. `reducedInterruption` was `chosenReducedInterruption` and
/// its only shipping caller was the Intervention pane's own checkbox;
/// `AppComposition.appearanceChanged(_:)` re-themed the capture panel, the nudge panel and the
/// menu bar and never touched `nudgeHost`; and `interventionSettings` was built without
/// `reducedInterruptionIsForced`, so it took its `false` default and
/// `settings.intervention.reduced.forced` — *"Reduce Motion is on, so this stays on."* — shipped
/// in the catalog with no code path that could draw it.
///
/// Two things a person could see: a Reduce Motion user still got a full animated `NSPanel`, and
/// the app shipped a sentence about a wire that did not exist.
///
/// ## Why it survived
///
/// `InterventionSettingsTests` constructs `reducedInterruptionIsForced: true` **by hand** and
/// then asserts what the pane draws from it. That is a true statement about the view and says
/// nothing whatever about where the value comes from, so the pane's snapshot was green over a
/// field the composition root never filled in. So every test here starts at
/// `appearanceChanged(_:)` — the seam the shell actually calls, with
/// `.onChange(of: composition.appearance.traits, initial: true)` — and reads the far end.
/// Nothing below hands a flag to anything.
///
/// The traits are always set explicitly first, never inherited from the machine: a lane whose
/// result depended on the developer's System Settings would be the same defect wearing a green
/// tick.
@Suite("Reduce Motion, wired", .serialized)
@MainActor
struct ReduceMotionWireTests {
    static let subject = NudgeHostFixture.decoy

    static func traits(reduceMotion: Bool) -> AppearanceTraits {
        AppearanceTraits(colorScheme: .light, reduceMotion: reduceMotion)
    }

    /// The panel rung's row of the table the Intervention pane renders, for whatever the loop
    /// currently believes. Read through `InterventionSettingsView.drawnRows`, so this is the row
    /// the person is actually shown rather than a router call the test composed.
    static func drawnTopRung(_ root: AppComposition) -> SurfaceRoute? {
        InterventionSettingsView(settings: root.interventionSettings)
            .drawnRows.first { $0.rung == .panel }?.route
    }

    // MARK: - The wire itself

    /// **The shell's appearance seam reaches the routing decision and the pane's own copy.**
    ///
    /// Both ends, because the defect was two disconnections and either one alone would leave a
    /// half-repair looking green: `reducedInterruption` is what the router routes on, and
    /// `reducedInterruptionIsForced` is what the pane draws its disabled switch and its sentence
    /// from. They were separate literals; they are one fact now.
    @Test("Reduce Motion turns reduced interruption on, and says that is what did it")
    func theAppearanceWireReachesTheLoop() throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try CompositionRootWireTests.joinedRoot(clock: clock)
        defer { CompositionRootWireTests.tearDown(root) }

        root.appearanceChanged(Self.traits(reduceMotion: false))
        #expect(root.interventionSettings.reducedInterruption == false)
        #expect(root.interventionSettings.reducedInterruptionIsForced == false)
        #expect(Self.drawnTopRung(root) == .surface(.panel))

        root.appearanceChanged(Self.traits(reduceMotion: true))
        #expect(
            root.interventionSettings.reducedInterruption,
            "Reduce Motion did not reach the loop, so the router still routes a panel"
        )
        #expect(
            root.interventionSettings.reducedInterruptionIsForced,
            "the pane cannot draw \"Reduce Motion is on, so this stays on.\""
        )
        // The consequence, on the surface whose design principle is that it *is* the behaviour.
        #expect(Self.drawnTopRung(root) == .surface(.popoverBadge))
    }

    /// **And the far end of it: no window is raised at the top rung.**
    ///
    /// The whole product claim. A person who told macOS they wanted less motion was getting a
    /// full animated `NSPanel`; they now meet the same rung, with the same six answers, as a
    /// badge and a row in the popover. Driven through the shipping verdict stream, so the panel
    /// this asserts is not visible is the real one the root owns.
    @Test("with Reduce Motion on, the top rung is a badge and no panel is raised")
    func reduceMotionTakesTheTopRungOffTheScreen() throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try CompositionRootWireTests.joinedRoot(clock: clock)
        defer { CompositionRootWireTests.tearDown(root) }

        root.appearanceChanged(Self.traits(reduceMotion: true))

        for _ in 0..<3 {
            root.relevanceHost.onJudgement?(
                NudgeHostFixture.unrelatedJudgement(subject: Self.subject)
            )
            NudgeHostFixture.settle()
            if root.nudgeHost.currentRung == .panel { break }
            clock.advance(by: RelevancePolicy.mandateCooldown + .seconds(1))
        }

        try #require(
            root.nudgeHost.currentRung == .panel,
            "the ladder never reached the top rung: \(String(describing: root.nudgeHost.lastDecision))"
        )
        #expect(
            !root.nudgePanel.isVisible,
            "Reduce Motion still got a panel, which is the whole of what this bead is about"
        )
        #expect(
            root.nudgeHost.pendingPopoverAccusation != nil,
            "the rung reached no surface a person can answer it on"
        )
    }

    // MARK: - Two writers, and neither may overwrite the other

    /// **The system cannot un-choose what the person chose.**
    ///
    /// The single-field wiring — `appearanceChanged` calling `choose(reducedInterruption:)` —
    /// would pass the test above and fail this one: the next appearance notification, which
    /// arrives on any theme change at all, would silently reset a checkbox the person had set.
    /// That is the "two writers, one field" shape focus-zrs removed from the notification
    /// authorisation, and it is why `preferences` reads `chosen || forced` from two fields.
    @Test("an appearance change does not clear the checkbox the person set")
    func theSystemDoesNotUnchooseThePersonsSetting() throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try CompositionRootWireTests.joinedRoot(clock: clock)
        defer { CompositionRootWireTests.tearDown(root) }

        root.appearanceChanged(Self.traits(reduceMotion: false))
        root.perform(.setReducedInterruption(true))
        #expect(root.interventionSettings.reducedInterruption)
        // …and the switch is still theirs to operate, because Reduce Motion is not why it is on.
        #expect(!root.interventionSettings.reducedInterruptionIsForced)

        // Any appearance change at all — this one is a switch to dark mode.
        root.appearanceChanged(AppearanceTraits(colorScheme: .dark, reduceMotion: false))
        #expect(
            root.interventionSettings.reducedInterruption,
            "an appearance notification cleared a preference the person had set"
        )
        #expect(!root.interventionSettings.reducedInterruptionIsForced)
    }

    /// **And the person cannot switch off what Reduce Motion turned on**, which is what makes the
    /// pane's disabled switch and its sentence honest rather than decorative.
    ///
    /// The pane disables the control, so this press cannot come from the shipping view — it comes
    /// from anything else that can reach `perform(_:)`, and the answer has to be the same one the
    /// pane promises. A "forced" switch a request could beat would be the copy lying again, in
    /// the opposite direction.
    @Test("a request to turn it off does not beat Reduce Motion")
    func thePersonCannotBeatTheForcedSetting() throws {
        let clock = FixedMonotonicClock()
        let (root, _) = try CompositionRootWireTests.joinedRoot(clock: clock)
        defer { CompositionRootWireTests.tearDown(root) }

        root.appearanceChanged(Self.traits(reduceMotion: true))
        root.perform(.setReducedInterruption(false))

        #expect(root.interventionSettings.reducedInterruption)
        #expect(root.interventionSettings.reducedInterruptionIsForced)
        #expect(Self.drawnTopRung(root) == .surface(.popoverBadge))

        // Turning Reduce Motion off in System Settings gives the choice back, and the choice is
        // the one they last made rather than the one the system was imposing.
        root.appearanceChanged(Self.traits(reduceMotion: false))
        #expect(!root.interventionSettings.reducedInterruption)
        #expect(!root.interventionSettings.reducedInterruptionIsForced)
        #expect(Self.drawnTopRung(root) == .surface(.panel))
    }
}
