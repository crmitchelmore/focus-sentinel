import AppKit
import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// **The menu bar says a nudge is there** (focus-mkk, focus-2xw).
///
/// ## The two defects, which are one defect reached from two sides
///
/// `NudgeSurface.reachesThePersonOnLanding` answers `true` for `.menuBar` on the stated ground
/// that *"the glyph is redrawn on the next refresh"*, and `NudgeHost.accuse(…)` charges the day's
/// budget on the strength of it. Nothing redrew it. `MenuBarPresentation` carried the status, the
/// timer and the popover's contents; `MenuBarController.redraw` drew the glyph, the title and the
/// VoiceOver announcement from the status alone; and a mandate needs ninety seconds of sustained
/// drift, so the status had already been `.unrelated` throughout. Measured on the shipping loop
/// with a real installed `NSStatusItem`, seven drifts seven hundred seconds apart: **six delivered
/// rows, the whole day's accusation cap spent, the query budget squeezed from four to one, and one
/// write to the menu bar — made before the first rung existed.**
///
/// The badge half is the same absence with the sign flipped. Delivery there is correctly withheld
/// until somebody opens the popover, and nothing in the menu bar ever asked them to — so a nudge
/// routed to the badge was never delivered, never counted and never answered.
///
/// ## Why these assertions are shaped the way they are
///
/// The previous repair split `reachesThePersonOnLanding` out of `holdsTheInterruptionSlot` and
/// then **blessed the glyph cell by assertion** — a test that read the predicate back. So nothing
/// here asserts a predicate about a surface. These read the *picture* the item would be handed and
/// the *sentence* VoiceOver would be given; the count of actual writes to a real status item is
/// `NudgeHostGlyphRungTests`, on the shipping loop, where it belongs.
@Suite("The status item's attention mark")
@MainActor
struct MenuBarAttentionTests {
    /// **The mark is a different picture, and this is the assertion the bead asked for in the
    /// small.**
    ///
    /// `tiffRepresentation` rasterises the composite — the drawing handler really runs — so a
    /// mark that drew nothing, or drew the same thing twice, is three equal byte strings and a red
    /// run. Replacing either arm of `MenuBarController.marked(_:attention:describing:)` with
    /// `break` fails here; so does making `glyph(for:attention:)` ignore its second argument.
    @Test("each mark makes a different picture, for every status", arguments: FocusStatus.allCases)
    func everyMarkDrawsSomethingElse(status: FocusStatus) throws {
        var pictures: [MenuBarAttention: Data] = [:]
        for attention in MenuBarAttention.allCases {
            let image = try #require(MenuBarController.glyph(for: status, attention: attention))
            #expect(image.isTemplate, "the mark must be tinted by the menu bar, never coloured here")
            pictures[attention] = try #require(
                image.tiffRepresentation,
                "the composite for \(attention.rawValue) could not be rasterised"
            )
        }
        #expect(
            Set(pictures.values).count == MenuBarAttention.allCases.count,
            """
            \(status.rawValue): the three marks drew \(Set(pictures.values).count) distinct \
            pictures — a mark nobody can see is the defect, not the fix
            """
        )
    }

    /// **P-133's promise survives the mark** (focus-2xw's own acceptance).
    ///
    /// The bead names the wrong shape explicitly: *"an indicator that changes the string width is
    /// the wrong shape"*, because the title is rewritten as often as once a second and a width
    /// that moved with it would shove every item to its left. So the mark is drawn **into** the
    /// glyph at the glyph's own size, and neither channel that decides the item's width is
    /// touched.
    @Test("the mark moves neither the glyph's bounds nor the title", arguments: FocusStatus.allCases)
    func theMarkDoesNotMoveTheMenuBar(status: FocusStatus) throws {
        let sizes = try MenuBarAttention.allCases.map { attention in
            try #require(MenuBarController.glyph(for: status, attention: attention)).size
        }
        #expect(Set(sizes.map(\.width)).count == 1)
        #expect(Set(sizes.map(\.height)).count == 1)

        // And the title is not a function of the mark at all — the same string, before and after
        // a rung lands, for both settings of the one preference that lengthens it.
        for differentiate in [false, true] {
            let titles = [nil, NudgeSurface.menuBar, NudgeSurface.popoverBadge].map { surface in
                MenuBarController.buttonTitle(
                    MenuBarFixture.presentation(
                        status: status,
                        rungSurface: surface,
                        differentiateWithoutColor: differentiate
                    )
                )
            }
            #expect(Set(titles).count == 1, "the mark changed the drawn title: \(titles)")
        }
    }

    /// **What the item is marked with, from what is actually standing where** (focus-mkk).
    ///
    /// Driven over the presentation the composition root builds rather than asserted against
    /// `NudgeSurface.menuBarAttention`, which is the rule rather than its use. The last row is the
    /// one that needed the `max`: an ambient rung on the glyph *and* a question waiting behind the
    /// click is a person who must be told to click, and reporting "nothing to answer" because the
    /// glyph also has a rung on it would be the worse of the two truths.
    @Test("the item is marked from what is standing where, and the invitation wins")
    func theMarkFollowsWhatIsActuallyThere() {
        #expect(MenuBarFixture.presentation().attention == .unmarked)
        #expect(MenuBarFixture.presentation(rungSurface: .panel).attention == .unmarked)
        #expect(MenuBarFixture.presentation(rungSurface: .menuBar).attention == .noticing)
        #expect(MenuBarFixture.presentation(rungSurface: .popoverBadge).attention == .waiting)

        // focus-2xw's own half: a **question** on the badge is exactly as invisible as an
        // accusation was, and is marked by the same line rather than by a second one.
        #expect(MenuBarFixture.withQuestion.attention == .waiting)
        #expect(MenuBarFixture.withAccusation.attention == .waiting)

        let both = MenuBarFixture.presentation(
            pendingQuery: MenuBarFixture.query,
            rungSurface: .menuBar
        )
        #expect(both.attention == .waiting)
    }

    /// **VoiceOver is told which mark it is, in words** (focus-2xw).
    ///
    /// The bead requires the indication to be readable by VoiceOver, and names the reason: the
    /// announcement was keyed to `FocusStatus`, which a rung landing does not change. A mark with
    /// no sentence would repair the defect for people who can see the dot and leave it exactly as
    /// it was for everybody else.
    ///
    /// The announcement is asserted to carry **no timer**: keyed on a string containing the
    /// countdown, the item would be read aloud once a second while a snooze runs.
    @Test(
        "each mark has its own sentence, and the announcement carries no countdown",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func theSentenceSaysWhichMarkItIs() {
        let labels = [nil, NudgeSurface.menuBar, NudgeSurface.popoverBadge].map { surface in
            MenuBarController.accessibilityLabel(
                MenuBarFixture.presentation(status: .unrelated, rungSurface: surface)
            )
        }
        #expect(Set(labels).count == 3, "two marks read the same aloud: \(labels)")
        for label in labels {
            #expect(label.contains(FocusStatus.unrelated.shortLabel))
            #expect(label.contains("25:05"), "the label is where the countdown belongs")
        }

        let announcements = MenuBarAttention.allCases.map {
            MenuBarController.announcement(status: .unrelated, attention: $0)
        }
        #expect(Set(announcements).count == MenuBarAttention.allCases.count)
        for announcement in announcements {
            #expect(!announcement.contains("25:05"), "the announcement must not read the clock")
        }
    }
}
