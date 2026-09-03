import AppKit
import FocusCore
import FocusSensing
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **Two readers of one API, held to one answer** (e08a, `focus-26b`).
///
/// The four e08a readings — `safeAreaInsets.top`, both `auxiliaryTop*Area` and
/// `CGDisplayIsBuiltin` — are taken at `SystemScreenList.geometry(of:)`, which is FocusSensing's
/// seam, and again at `NudgePanelController.currentScreens()`, which is FocusUI's. There are two
/// because the package boundary forbids FocusUI importing FocusSensing, and this suite is the only
/// place in the programme that can see both: `FocusHost` is the one package that may import every
/// sibling.
///
/// The failure it exists for is silent and shippable. A twin that stopped short of the four fields
/// would hand the notch companion a display list in which **no Mac has a built-in panel** — the
/// companion would refuse `.noBuiltInDisplay` on a MacBook Pro, the Settings row would repeat the
/// lie, and every gate on every rig in this programme would stay green, because no rig in this
/// programme has a notch.
///
/// ## The residual, stated
///
/// On a Mac with no built-in display **this suite cannot catch a projection that reads the wrong
/// value**, and no suite can: the honest answers here are `0`, `nil`, `nil`, `false`, and so are
/// the dishonest ones. What is held is narrower and is held two ways. `DisplayGeometry.NotchReadings`
/// has no defaults, so a projection that *omitted* a reading does not compile; and this suite
/// fails on any *divergence* between the two readers, which is the drift a later edit produces.
/// The third case — both readers wrong in the same way — is P-e08-B's, and it is named in the
/// README's e08b receipts rather than pretended away here.
@Suite("The two display projections agree about the notch")
@MainActor
struct NotchGeometrySeamTests {
    @Test("both readers project the same displays, field for field")
    func theProjectionsAgree() {
        let sensing = SystemScreenList.geometry(of: NSScreen.screens)
        let ui = NudgePanelController.currentScreens()

        #expect(!sensing.isEmpty, "no displays at all, so the comparison proves nothing")
        #expect(sensing.count == ui.count)

        for (left, right) in zip(sensing, ui) {
            #expect(left.displayID == right.displayID)
            #expect(left.frame == right.frame)
            #expect(left.visibleFrame == right.visibleFrame)
            #expect(left.backingScaleFactor == right.backingScaleFactor)
            // The four e08a fields, named one by one rather than through `==` on the whole value:
            // a failure that says *which* reading the twin stopped short of is the difference
            // between a five-minute fix and an afternoon.
            #expect(
                left.safeAreaTopInset == right.safeAreaTopInset,
                "the two readers disagree about the safe-area inset of display \(left.displayID)"
            )
            #expect(left.auxiliaryTopLeft == right.auxiliaryTopLeft)
            #expect(left.auxiliaryTopRight == right.auxiliaryTopRight)
            #expect(
                left.isBuiltIn == right.isBuiltIn,
                "the two readers disagree about whether display \(left.displayID) is built in"
            )
            // And therefore about the only thing either reading is for.
            #expect(left.notchLanding == right.notchLanding)
        }
    }

    /// **This machine, read through the shipping seam rather than from a fixture.**
    ///
    /// The one non-synthetic e08a assertion in the unit lane: whatever else is true, on the rig
    /// this programme is built on the answer is a refusal, and the refusal names a missing
    /// built-in display rather than a missing notch.
    @Test("this Mac's real displays all refuse, and none of them is built in")
    func theRealRig() {
        let screens = SystemScreenList.geometry(of: NSScreen.screens)
        try? #require(!screens.isEmpty)

        for screen in screens {
            #expect(
                !screen.isBuiltIn,
                """
                display \(screen.displayID) reports as built in; this rig is a Mac mini and every \
                e08a fixture that draws is labelled synthetic on that basis
                """
            )
            #expect(screen.safeAreaTopInset == 0)
            #expect(screen.auxiliaryTopLeft == nil)
            #expect(screen.auxiliaryTopRight == nil)
            #expect(screen.notchLanding == .refused(.noBuiltInDisplay))
        }
    }

    /// The composition root's own answer, which is what the Settings row and the self-check both
    /// read. Driven through `AppComposition` rather than through a controller a test built, so a
    /// wiring that stopped handing the companion the real display list fails here.
    @Test("the composition root refuses this Mac by name, and its companion never drew")
    func theCompositionRootAgrees() {
        let root = AppComposition(
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            monotonicClock: FixedMonotonicClock(),
            calendar: NudgeHostFixture.londonCalendar,
            locale: Locale(identifier: "en_GB"),
            hotKeyRegistrar: InertHotKeyRegistrar(),
            storeKind: .inMemory,
            notificationCentre: SilentNotificationCentre()
        )
        defer { root.menuBar.remove(); root.stop() }

        #expect(root.notchCompanion.landing() == .refused(.noBuiltInDisplay))
        #expect(root.notchCompanion.writeCount == 0)
        #expect(!root.notchCompanion.isVisible)
        // And the row a person reads is that same reason, not a preference.
        #expect(root.interventionSettings.notchRefusal == .noBuiltInDisplay)
        // Two renderers, named, and the notch is the second.
        #expect(AppComposition.ambientRungRenderers == ["menuBarItem", "notchCompanion"])
    }
}
