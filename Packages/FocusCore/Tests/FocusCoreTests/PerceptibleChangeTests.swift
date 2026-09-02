import Foundation
import Testing

@testable import FocusCore

/// **The charging invariant, at the level where it is a value** (focus-1b5, focus-nrl, U-1).
///
/// The host's own proof drives real AppKit surfaces and counts real writes; this one folds the
/// decision over the whole space of readings, which is the half a driven proof cannot reach.
/// Every case here is a *pair* of `SurfaceObservation`s, and the assertion is always the same
/// one: a receipt exists exactly when something moved on the surface's own channel.
@Suite("A charge needs a change the person could perceive")
@MainActor
struct PerceptibleChangeTests {
    /// **A reading blessed by a real seam** (focus-my0).
    ///
    /// Every fold below is about *what* was on the surfaces, so each one needs an `after` half
    /// that the type will accept — and there is exactly one way to get one, which is to let a
    /// `SurfaceTurn` finish. Written as a helper rather than as a stub because a stub would be a
    /// second producer, and the whole of focus-my0 is that a reading nothing vouched for was
    /// treated as evidence.
    static func settled(_ reading: SurfaceObservation) -> SettledObservation {
        var blessed: SettledObservation?
        let turn = SurfaceTurn()
        turn.atSeam = { seam in blessed = seam.settled(reading) }
        turn.run {}
        guard let blessed else {
            fatalError("a turn ended without reaching its seam")
        }
        return blessed
    }

    /// A window surface either carrying the nudge with every action reachable, or not up at all.
    ///
    /// **The two ends of `WindowSurfaceReading`, spelled here rather than on the type** (focus-2bj).
    /// The product builds these from a live `NSWindow` and a live layout; a convenience on the
    /// value itself would be a `Bool` constructor by another name, and a `Bool` constructor is
    /// what this round exists to remove.
    static func window(showing: Bool) -> WindowSurfaceReading {
        guard showing else { return .nothingUp }
        return WindowSurfaceReading(
            isCarryingTheNudge: true,
            reading: DecisionSurfaceReading(
                isVisible: true,
                isWhollyOnAScreen: true,
                unreportedActions: [],
                unreachableActions: []
            )
        )
    }

    /// Every reading a surface can be in, as a small closed set the folds below cross.
    static func readings() -> [SurfaceObservation] {
        var all: [SurfaceObservation] = []
        for writes in [0, 1] {
            for announcements in [0, 1] {
                for mark in MenuBarAttention.allCases {
                    for panel in [false, true] {
                        for popover in [false, true] {
                            all.append(
                                SurfaceObservation(
                                    menuBarWrites: writes,
                                    menuBarAnnouncements: announcements,
                                    markOnTheItem: mark,
                                    panel: Self.window(showing: panel),
                                    popover: Self.window(showing: popover)
                                )
                            )
                        }
                    }
                }
            }
        }
        return all
    }

    /// **Every surface has exactly one channel, and every channel has a surface.**
    ///
    /// The join `NudgeSurfaceTests` makes between `reachesThePersonOnLanding` and
    /// `menuBarAttention`, made for the third column: a surface that gained a channel nothing can
    /// observe, or a channel no surface reaches, is a build that does not pass.
    @Test("the channel table is a bijection")
    func everySurfaceHasItsOwnChannel() {
        let channels = NudgeSurface.allCases.map(\.perceptionChannel)
        #expect(Set(channels).count == NudgeSurface.allCases.count)
        #expect(Set(channels) == Set(PerceptionChannel.allCases))
    }

    /// **focus-1b5 and focus-nrl, as arithmetic.**
    ///
    /// Over every pair of readings: a glyph rung is charged if and only if the item was actually
    /// written to (or spoke) **and** it went from not saying `noticing` to saying it. The three
    /// conjuncts are separately necessary, which is what makes the mutation proof meaningful —
    /// deleting any one of them turns this test red on a named pair.
    @Test("the glyph is charged exactly when the item started saying something new")
    func theGlyphIsChargedOnlyWhenTheItemMoved() {
        var charged = 0
        var refused = 0
        for before in Self.readings() {
            for after in Self.readings() {
                let change = PerceptibleChange.proven(
                    on: .menuBar, from: before, to: Self.settled(after)
                )
                let itemMoved = after.menuBarWrites > before.menuBarWrites
                    || after.menuBarAnnouncements > before.menuBarAnnouncements
                let expected = itemMoved
                    && before.markOnTheItem != .noticing
                    && after.markOnTheItem == .noticing
                #expect(
                    (change != nil) == expected,
                    """
                    menuBar: before(writes \(before.menuBarWrites), said \
                    \(before.markOnTheItem.rawValue)) -> after(writes \(after.menuBarWrites), \
                    says \(after.markOnTheItem.rawValue)) charged=\(change != nil) \
                    expected=\(expected)
                    """
                )
                #expect(change?.surface == (expected ? .menuBar : nil))
                if expected { charged += 1 } else { refused += 1 }
            }
        }
        // Non-vacuity in both directions. A fold that charged everything and a fold that charged
        // nothing would both satisfy an implication written one way round.
        #expect(charged > 0, "no pair of readings ever charged, so this fold proves nothing")
        #expect(refused > 0, "every pair of readings charged, so this fold proves nothing")
    }

    /// **focus-nrl in one sentence.** A badge nudge holds the item at `waiting`, so the glyph
    /// rung underneath it is never charged however many times the item is written — and the
    /// moment the badge clears and the item falls to `noticing`, it is.
    @Test("a rung under a pending badge is charged nothing until the mark falls to it")
    func aPendingBadgeDefersTheGlyphCharge() {
        let atLanding = SurfaceObservation(
            menuBarWrites: 0,
            menuBarAnnouncements: 0,
            markOnTheItem: .unmarked,
            panel: .nothingUp,
            popover: .nothingUp
        )
        // The badge outranks the rung: the item is written, and what it says is `waiting`.
        let whileTheBadgeIsUp = SurfaceObservation(
            menuBarWrites: 1,
            menuBarAnnouncements: 1,
            markOnTheItem: .waiting,
            panel: .nothingUp,
            popover: .nothingUp
        )
        #expect(
            PerceptibleChange.proven(
                on: .menuBar, from: atLanding, to: Self.settled(whileTheBadgeIsUp)
            ) == nil,
            "a rung the item never mentioned was charged"
        )
        // The question is answered, the badge goes, the item falls to the rung's own mark.
        let afterTheBadgeGoes = SurfaceObservation(
            menuBarWrites: 1,
            menuBarAnnouncements: 1,
            markOnTheItem: .noticing,
            panel: .nothingUp,
            popover: .nothingUp
        )
        #expect(
            PerceptibleChange.proven(
                on: .menuBar, from: atLanding, to: Self.settled(afterTheBadgeGoes)
            ) != nil,
            "the item said the rung's own mark and the rung was still not charged"
        )
    }

    /// **focus-1b5 in one sentence.** The second glyph rung on a second application finds the
    /// item already `noticing`: the mark carries no subject, so there is nothing new on screen.
    @Test("a second glyph rung on an item already noticing is charged nothing")
    func aSecondGlyphRungIsChargedNothing() {
        let alreadyNoticing = SurfaceObservation(
            menuBarWrites: 1,
            menuBarAnnouncements: 1,
            markOnTheItem: .noticing,
            panel: .nothingUp,
            popover: .nothingUp
        )
        let laterStillNoticing = SurfaceObservation(
            menuBarWrites: 1 + 1,
            menuBarAnnouncements: 1 + 1,
            markOnTheItem: .noticing,
            panel: .nothingUp,
            popover: .nothingUp
        )
        #expect(
            PerceptibleChange.proven(
                on: .menuBar, from: alreadyNoticing, to: Self.settled(laterStillNoticing)
            ) == nil
        )
    }

    /// **The window and the popover are states, and honestly so** — but they are readings of the
    /// real object, never of a predicate. Folded over the same space: the panel is charged
    /// exactly when the panel is showing the nudge, and the badge exactly when the popover is.
    @Test("the window and the popover are charged exactly when they are showing the nudge")
    func theWindowAndThePopoverAreChargedOnWhatTheyShow() {
        var panelCharges = 0
        var popoverCharges = 0
        for before in Self.readings() {
            for after in Self.readings() {
                let onPanel = PerceptibleChange.proven(
                    on: .panel, from: before, to: Self.settled(after)
                )
                #expect((onPanel != nil) == after.panelIsShowingTheNudge)
                let onBadge = PerceptibleChange.proven(
                    on: .popoverBadge, from: before, to: Self.settled(after)
                )
                #expect((onBadge != nil) == after.popoverIsShowingTheNudge)
                if onPanel != nil { panelCharges += 1 }
                if onBadge != nil { popoverCharges += 1 }
            }
        }
        #expect(panelCharges > 0)
        #expect(popoverCharges > 0)
    }

    /// **A banner can never be charged** (U-2, focus-wy0). Nothing posts one, nothing can observe
    /// one, and the arithmetic says so rather than a comment saying so.
    @Test("no reading whatsoever charges a notification")
    func aNotificationIsNeverCharged() {
        var pairs = 0
        for before in Self.readings() {
            for after in Self.readings() {
                #expect(
                    PerceptibleChange.proven(
                        on: .notification, from: before, to: Self.settled(after)
                    ) == nil
                )
                pairs += 1
            }
        }
        #expect(pairs > 0, "no readings were folded, so this proves nothing")
    }

    /// **A turn entered from inside a turn is the same turn** (focus-my0).
    ///
    /// The nudge loop reaches its own entry points through its own synchronous callbacks: a
    /// landing asks the composition root for a redraw, the redraw writes the item, and the write
    /// calls `menuBarItemRedrawn()` — which is an entry point, in the middle of the one already
    /// being served. If that inner call reached a seam, the charge would be proven against a
    /// reading taken exactly where the defect took it, and the whole repair would be a no-op.
    @Test("the seam is reached once, when the outermost turn ends")
    func aNestedTurnReachesNoSeam() {
        let turn = SurfaceTurn()
        var seams = 0
        var openAtSeam: [Bool] = []
        turn.atSeam = { _ in
            seams += 1
            openAtSeam.append(turn.isOpen)
        }
        turn.run {
            #expect(turn.isOpen)
            #expect(seams == 0)
            turn.run {
                #expect(turn.isOpen)
            }
            #expect(seams == 0, "an inner turn reached a seam of its own")
            turn.run {
                turn.run {}
            }
            #expect(seams == 0, "a doubly nested turn reached a seam of its own")
        }
        #expect(seams == 1)
        #expect(openAtSeam == [false], "the seam ran while the surfaces were still moving")
        #expect(!turn.isOpen)
        // And the next event is its own turn, with its own seam.
        turn.run {}
        #expect(seams == 2)
    }

    /// **The seam is reached on the way out of a turn that threw**, because a turn that failed
    /// half way through has still left the surfaces in the state a person is about to see.
    @Test("a turn that throws still reaches its seam")
    func aThrowingTurnReachesItsSeam() {
        struct Stop: Error {}
        let turn = SurfaceTurn()
        var seams = 0
        turn.atSeam = { _ in seams += 1 }
        #expect(throws: Stop.self) {
            try turn.run { throw Stop() }
        }
        #expect(seams == 1)
        #expect(!turn.isOpen, "a turn that threw was left open")
    }

    /// **A proof names its own surface**, so one cannot be spent on another. The host reads the
    /// surface off the receipt rather than taking a second argument beside it.
    @Test("a receipt carries the surface it was taken on")
    func aReceiptNamesItsSurface() {
        let shown = SurfaceObservation(
            menuBarWrites: 0,
            menuBarAnnouncements: 0,
            markOnTheItem: .unmarked,
            panel: Self.window(showing: true),
            popover: Self.window(showing: true)
        )
        let change = PerceptibleChange.proven(
            on: .panel, from: .nothingSeen, to: Self.settled(shown)
        )
        #expect(change?.surface == .panel)
        #expect(change?.channel == .panelWindow)
        let badge = PerceptibleChange.proven(
            on: .popoverBadge, from: .nothingSeen, to: Self.settled(shown)
        )
        #expect(badge?.surface == .popoverBadge)
        #expect(badge?.channel == .popoverContents)
    }
}
