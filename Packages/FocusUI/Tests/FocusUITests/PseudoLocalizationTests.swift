import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// F-149's substrate half, proved rather than promised.
///
/// Translation is parked, so the question a test can honestly answer is not "is the French
/// right" but "does the shell survive what translation does to it": strings roughly twice as
/// long, in characters that are not ASCII. Every render here goes through the *same* text
/// seam the app uses, so a component that quietly clips at 2× expansion fails here and not
/// in front of a user.
@Suite("Pseudo-localisation", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct PseudoLocalizationTests {
    // MARK: - The transform itself

    @Test("the transform is deterministic and roughly doubles length")
    func transformIsDeterministicAndExpands() {
        let source = "Close Window"
        let first = PseudoLocale.expand(source)
        let second = PseudoLocale.expand(source)

        #expect(first == second)
        #expect(first.hasPrefix(PseudoLocale.opening))
        #expect(first.hasSuffix(PseudoLocale.closing))
        #expect(first.count >= Int(Double(source.count) * 1.8))
        #expect(first != source)
    }

    @Test("the transform leaves an empty string alone and preserves shortcut glyphs")
    func transformIsConservative() {
        #expect(PseudoLocale.expand("") == "")
        // The shortcut column is symbols, not prose; accenting ⌘ would make the reference
        // unreadable for no gain.
        #expect(PseudoLocale.expand("⌘W").contains("⌘"))
    }

    @Test("the transform reaches the views through the shell's own text seam")
    func transformReachesTheViews() throws {
        // If the seam were bypassed — a view drawing `Text(resource)` directly — the
        // pseudo-localised render would be pixel-identical to the plain one, and this is the
        // assertion that would catch it.
        let plain = try SnapshotHarness.render(
            CockpitView(state: .ready),
            traits: .light,
            name: "pseudo.seam.plain"
        )
        let pseudo = try SnapshotHarness.render(
            CockpitView(state: .ready),
            traits: .light,
            transform: PseudoLocale.transform,
            name: "pseudo.seam.pseudo"
        )

        let differs = PNGCompare.areDistinct(plain.pixels, pseudo.pixels)
        #expect(differs, "the pseudo transform never reached the cockpit's text")
    }

    // MARK: - Every component survives 2× expansion

    @Test(
        "expanded text draws more ink and never shrinks the layout",
        arguments: SnapshotComponent.allCases
    )
    func expandedTextDrawsMoreInk(component: SnapshotComponent) throws {
        for size in SnapshotTypeSize.allCases {
            let plain = try SnapshotHarness.render(
                component.view,
                traits: .light,
                textScale: size.textScale,
                width: component.width,
                name: "\(component.rawValue).plain.\(size.rawValue)"
            )
            let pseudo = try SnapshotHarness.render(
                component.view,
                traits: .light,
                textScale: size.textScale,
                width: component.width,
                transform: PseudoLocale.transform,
                name: "\(component.rawValue).pseudo.\(size.rawValue)"
            )

            // **Ink, not frame.** The obvious assertion — "the render gets taller" — is
            // wrong for a layout that deliberately has slack in it: the cockpit reserves
            // room below its button, so two extra wrapped lines land in space it already
            // had and the frame stays 584px in both. Measured, not assumed. What cannot
            // stay the same is how much ink is on the page: doubling every string draws
            // more glyphs, and a view that dropped or truncated its strings would draw
            // fewer.
            let plainInk = PNGCompare.inkPixels(plain.pixels)
            let pseudoInk = PNGCompare.inkPixels(pseudo.pixels)
            // **A render with no ink in it is a render CoreGraphics did not make**, not a view
            // that drew nothing (focus-u3w). Past roughly sixteen thousand rows the pixel buffer
            // comes back empty, and "more ink than the plain pass" would then be a comparison
            // between a picture and a blank rectangle. Named here so the failure says which.
            #expect(
                plainInk > 0 && pseudoInk > 0,
                "\(component.rawValue) at \(size.rawValue) rendered no ink: \(plain.height) and \(pseudo.height) rows"
            )
            #expect(
                pseudoInk > plainInk,
                "\(component.rawValue) drew no extra text when pseudo-localised (\(plainInk) → \(pseudoInk)): the strings never reached the view"
            )

            // And nothing may get *smaller*, which is what clipping to a fixed frame looks
            // like from outside.
            #expect(pseudo.height >= plain.height)
            #expect(pseudo.width >= plain.width)

            if component.width == nil {
                // A self-sizing component has no fixed width to wrap inside, so it grows
                // sideways instead.
                #expect(
                    pseudo.width > plain.width,
                    "\(component.rawValue) did not widen (\(plain.width) → \(pseudo.width))"
                )
            }
        }
    }

    /// The same assertion over e02's surfaces.
    ///
    /// `drawsLocalisedProse` is what keeps this honest. The committed priority hero draws the
    /// user's own sentence through `Text(verbatim:)` — it is data, not prose, and it must
    /// **not** move when the locale changes. Asserting "more ink" over it would be asserting
    /// that the hero is translated, which is the opposite of what F-149 wants and the opposite
    /// of what the app does. Every other e02 surface draws catalog strings and is here.
    @Test(
        "the priority surfaces draw more ink when pseudo-localised",
        arguments: PriorityComponent.allCases.filter(\.drawsLocalisedProse)
    )
    func priorityComponentsExpand(component: PriorityComponent) throws {
        for size in SnapshotTypeSize.allCases {
            let plain = try SnapshotHarness.render(
                component.view,
                traits: .light,
                textScale: size.textScale,
                width: component.width,
                name: "\(component.rawValue).plain.\(size.rawValue)"
            )
            let pseudo = try SnapshotHarness.render(
                component.view,
                traits: .light,
                textScale: size.textScale,
                width: component.width,
                transform: PseudoLocale.transform,
                name: "\(component.rawValue).pseudo.\(size.rawValue)"
            )

            let plainInk = PNGCompare.inkPixels(plain.pixels)
            let pseudoInk = PNGCompare.inkPixels(pseudo.pixels)
            #expect(
                pseudoInk > plainInk,
                "\(component.rawValue) drew no extra text when pseudo-localised (\(plainInk) → \(pseudoInk)): the strings never reached the view"
            )
            #expect(pseudo.height >= plain.height)
            #expect(pseudo.width >= plain.width)
        }
    }

    /// The hero's other half: the user's sentence is *not* translated.
    ///
    /// Its empty state is prose and does move — `priorityHeroEmpty` is in the expansion
    /// argument list above and proves it — so this is not "the hero ignores the seam", it is
    /// "the hero tells data and prose apart".
    @Test("the committed priority is drawn verbatim and never pseudo-localised")
    func theCommittedPriorityIsNeverTranslated() throws {
        let plain = try SnapshotHarness.render(
            PriorityComponent.priorityHero.view,
            traits: .light,
            width: PriorityComponent.priorityHero.width,
            name: "priorityHero.verbatim.plain"
        )
        let pseudo = try SnapshotHarness.render(
            PriorityComponent.priorityHero.view,
            traits: .light,
            width: PriorityComponent.priorityHero.width,
            transform: PseudoLocale.transform,
            name: "priorityHero.verbatim.pseudo"
        )

        #expect(
            !PNGCompare.areDistinct(plain.pixels, pseudo.pixels),
            "the user's own priority went through the string catalog seam"
        )
    }

    // MARK: - The committed pseudo-localised pass

    /// The same assertion over e03's surfaces.
    ///
    /// Every one of them draws catalog prose and nothing else — a phase badge is a glyph and a
    /// translated label, and the capability matrix is entirely authored sentences — so there is
    /// no `drawsLocalisedProse` exemption to make here. The priority hero needed one because it
    /// draws the user's own words; nothing in this set does.
    @Test(
        "the session surfaces draw more ink when pseudo-localised",
        arguments: SessionComponent.allCases
    )
    func sessionComponentsExpand(component: SessionComponent) throws {
        try assertExpands(
            component.view,
            named: component.rawValue,
            width: component.width,
            widensWhenSelfSizing: component.width == nil
        )
    }

    @Test(
        "the capability matrix draws more ink when pseudo-localised",
        arguments: CapabilityComponent.allCases
    )
    func capabilityComponentsExpand(component: CapabilityComponent) throws {
        try assertExpands(
            component.view,
            named: component.rawValue,
            width: component.width,
            widensWhenSelfSizing: component.width == nil
        )
    }

    /// One component, at both text scales, plain against pseudo-localised.
    ///
    /// **Ink, not frame** — the same reasoning e01 wrote down: a layout with slack in it can
    /// absorb two extra wrapped lines without growing, and did. What cannot stay the same is how
    /// much ink is on the page, because a view that dropped or truncated its strings would draw
    /// fewer glyphs rather than more.
    private func assertExpands(
        _ view: some View,
        named name: String,
        width: CGFloat?,
        widensWhenSelfSizing: Bool
    ) throws {
        for size in SnapshotTypeSize.allCases {
            let plain = try SnapshotHarness.render(
                view,
                traits: .light,
                textScale: size.textScale,
                width: width,
                name: "\(name).plain.\(size.rawValue)"
            )
            let pseudo = try SnapshotHarness.render(
                view,
                traits: .light,
                textScale: size.textScale,
                width: width,
                transform: PseudoLocale.transform,
                name: "\(name).pseudo.\(size.rawValue)"
            )

            let plainInk = PNGCompare.inkPixels(plain.pixels)
            let pseudoInk = PNGCompare.inkPixels(pseudo.pixels)
            #expect(
                pseudoInk > plainInk,
                "\(name) drew no extra text when pseudo-localised (\(plainInk) → \(pseudoInk)): the strings never reached the view"
            )
            #expect(pseudo.height >= plain.height)
            #expect(pseudo.width >= plain.width)

            if widensWhenSelfSizing {
                #expect(
                    pseudo.width > plain.width,
                    "\(name) did not widen (\(plain.width) → \(pseudo.width))"
                )
            }
        }
    }

    @Test(
        "the pseudo-localised pass matches its baseline",
        arguments: SnapshotComponent.allCases
    )
    func pseudoLocalisedPassMatchesBaseline(component: SnapshotComponent) throws {
        // One committed pass, at the default text size in light appearance, so a change in
        // how expansion lands in the layout is visible as a diff rather than only as a
        // number.
        try SnapshotHarness.assertSnapshot(
            component.view,
            component: component.rawValue,
            variant: "light",
            width: component.width,
            transform: PseudoLocale.transform,
            baselineSuffix: "pseudo"
        )
    }

    @Test(
        "the priority surfaces' pseudo-localised pass matches its baseline",
        arguments: PriorityComponent.allCases.filter(\.drawsLocalisedProse)
    )
    func priorityPseudoLocalisedPassMatchesBaseline(component: PriorityComponent) throws {
        try SnapshotHarness.assertSnapshot(
            component.view,
            component: component.rawValue,
            variant: "light",
            width: component.width,
            transform: PseudoLocale.transform,
            baselineSuffix: "pseudo"
        )
    }

    @Test(
        "the session surfaces' pseudo-localised pass matches its baseline",
        arguments: SessionComponent.allCases
    )
    func sessionPseudoLocalisedPassMatchesBaseline(component: SessionComponent) throws {
        try SnapshotHarness.assertSnapshot(
            component.view,
            component: component.rawValue,
            variant: "light",
            width: component.width,
            transform: PseudoLocale.transform,
            baselineSuffix: "pseudo"
        )
    }

    @Test(
        "the capability matrix's pseudo-localised pass matches its baseline",
        arguments: CapabilityComponent.allCases
    )
    func capabilityPseudoLocalisedPassMatchesBaseline(component: CapabilityComponent) throws {
        try SnapshotHarness.assertSnapshot(
            component.view,
            component: component.rawValue,
            variant: "light",
            width: component.width,
            transform: PseudoLocale.transform,
            baselineSuffix: "pseudo"
        )
    }
}
