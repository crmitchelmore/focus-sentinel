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
struct PerceptibleChangeTests {
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
                                    panelIsShowingTheNudge: panel,
                                    popoverIsShowingTheNudge: popover
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
                let change = PerceptibleChange.proven(on: .menuBar, from: before, to: after)
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
            panelIsShowingTheNudge: false,
            popoverIsShowingTheNudge: false
        )
        // The badge outranks the rung: the item is written, and what it says is `waiting`.
        let whileTheBadgeIsUp = SurfaceObservation(
            menuBarWrites: 1,
            menuBarAnnouncements: 1,
            markOnTheItem: .waiting,
            panelIsShowingTheNudge: false,
            popoverIsShowingTheNudge: false
        )
        #expect(
            PerceptibleChange.proven(on: .menuBar, from: atLanding, to: whileTheBadgeIsUp) == nil,
            "a rung the item never mentioned was charged"
        )
        // The question is answered, the badge goes, the item falls to the rung's own mark.
        let afterTheBadgeGoes = SurfaceObservation(
            menuBarWrites: 1,
            menuBarAnnouncements: 1,
            markOnTheItem: .noticing,
            panelIsShowingTheNudge: false,
            popoverIsShowingTheNudge: false
        )
        #expect(
            PerceptibleChange.proven(on: .menuBar, from: atLanding, to: afterTheBadgeGoes) != nil,
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
            panelIsShowingTheNudge: false,
            popoverIsShowingTheNudge: false
        )
        let laterStillNoticing = SurfaceObservation(
            menuBarWrites: 1 + 1,
            menuBarAnnouncements: 1 + 1,
            markOnTheItem: .noticing,
            panelIsShowingTheNudge: false,
            popoverIsShowingTheNudge: false
        )
        #expect(
            PerceptibleChange.proven(
                on: .menuBar, from: alreadyNoticing, to: laterStillNoticing
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
                let onPanel = PerceptibleChange.proven(on: .panel, from: before, to: after)
                #expect((onPanel != nil) == after.panelIsShowingTheNudge)
                let onBadge = PerceptibleChange.proven(on: .popoverBadge, from: before, to: after)
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
                    PerceptibleChange.proven(on: .notification, from: before, to: after) == nil
                )
                pairs += 1
            }
        }
        #expect(pairs > 0, "no readings were folded, so this proves nothing")
    }

    /// **A proof names its own surface**, so one cannot be spent on another. The host reads the
    /// surface off the receipt rather than taking a second argument beside it.
    @Test("a receipt carries the surface it was taken on")
    func aReceiptNamesItsSurface() {
        let shown = SurfaceObservation(
            menuBarWrites: 0,
            menuBarAnnouncements: 0,
            markOnTheItem: .unmarked,
            panelIsShowingTheNudge: true,
            popoverIsShowingTheNudge: true
        )
        let change = PerceptibleChange.proven(on: .panel, from: .nothingSeen, to: shown)
        #expect(change?.surface == .panel)
        #expect(change?.channel == .panelWindow)
        let badge = PerceptibleChange.proven(on: .popoverBadge, from: .nothingSeen, to: shown)
        #expect(badge?.surface == .popoverBadge)
        #expect(badge?.channel == .popoverContents)
    }
}
