import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// The design-token layer exists so that four of the five appearance variants can be
/// exercised on a machine where every accessibility setting is switched off. These tests are
/// what make that true: each one injects a trait value and asserts the token layer answers
/// differently, with no reference to the live system anywhere.
@Suite("Design tokens")
struct DesignTokenTests {
    // MARK: - Liquid Glass

    @Test("glass is drawn only where a summoned surface may be translucent")
    func glassFallsBackToOpaque() {
        #expect(DesignTokens.drawsGlass(for: .light))
        #expect(DesignTokens.drawsGlass(for: .dark))
        #expect(!DesignTokens.drawsGlass(for: .reduceTransparency))
        #expect(!DesignTokens.drawsGlass(for: .increasedContrast))
        #expect(DesignTokens.liquidAnimation(for: .light) != nil)
        #expect(DesignTokens.liquidAnimation(for: .reduceMotion) == nil)
    }

    @Test("content panes are opaque and quiet: a faint accent wash, a lift in Light, a rim in Dark")
    func contentPanesStayQuiet() {
        #expect(DesignTokens.accentWashOpacity < 0.12)
        #expect(DesignTokens.insetWashOpacity < DesignTokens.controlWashOpacity)
        #expect(DesignTokens.controlWashOpacity < DesignTokens.controlHoverWashOpacity)
        #expect(DesignTokens.quietRuleOpacity < 0.25)
        #expect(DesignTokens.paneLiftOpacity(for: .light) > 0)
        #expect(DesignTokens.paneLiftOpacity(for: .dark) == 0)
        #expect(DesignTokens.paneRimOpacity(for: .light) == 0)
        #expect(DesignTokens.paneRimOpacity(for: .dark) > 0)
    }

    /// **A card rises off the ground in both schemes** (the legibility ruling). Bench is the
    /// lighter role in Light and the darker in Dark, so a Bench card on an Inlay ground recessed
    /// in Dark; the roles swap with the scheme.
    @Test("a content pane is lighter than the ground in both schemes", arguments: [
        AppearanceTraits.light, .dark,
    ])
    func panesRiseOffTheGround(traits: AppearanceTraits) {
        let ground = DesignTokens.groundRole(for: traits).value(for: traits)
        let pane = DesignTokens.paneRole(for: traits).value(for: traits)
        #expect(DesignTokens.groundRole(for: traits) != DesignTokens.paneRole(for: traits))
        #expect(pane.relativeLuminance > ground.relativeLuminance)
    }

    /// **Words on a control are legible** — the selected tab's ink on its thumb, a primary
    /// button's Bench ink on Spruce, and a secondary button's Slate ink on a pane — at WCAG AA.
    @Test("control labels keep 4.5:1 on their fills", arguments: [
        AppearanceTraits.light, .dark,
    ])
    func controlLabelsAreLegible(traits: AppearanceTraits) {
        typealias Role = DesignTokens.Palette.Role
        let pane = DesignTokens.paneRole(for: traits).value(for: traits)
        let ground = DesignTokens.groundRole(for: traits).value(for: traits)
        let spruce = Role.spruce.value(for: traits)
        #expect(Role.slate.value(for: traits).contrastRatio(against: pane) >= 4.5)
        #expect(Role.slate.value(for: traits).contrastRatio(against: ground) >= 4.5)
        #expect(Role.bench.value(for: traits).contrastRatio(against: spruce) >= 4.5)
    }

    // MARK: - Reduce Transparency

    @Test("materials collapse to an opaque fill under Reduce Transparency")
    func materialCollapsesUnderReduceTransparency() {
        #expect(DesignTokens.material(for: .light, provenance: .summoned) == .material)
        #expect(DesignTokens.material(for: .dark, provenance: .summoned) == .material)
        #expect(DesignTokens.material(for: .reduceTransparency, provenance: .summoned) == .opaque)
        #expect(
            DesignTokens.material(for: .light, provenance: .summoned)
                != DesignTokens.material(for: .reduceTransparency, provenance: .summoned)
        )
    }

    // MARK: - Reduce Motion

    @Test("no animation is offered under Reduce Motion")
    func animationIsNilUnderReduceMotion() {
        #expect(DesignTokens.animation(for: .reduceMotion) == nil)
        #expect(DesignTokens.animation(for: .light) != nil)
        #expect(DesignTokens.animation(for: .dark) != nil)
    }

    // MARK: - Increase Contrast

    @Test("structure is drawn harder under Increase Contrast")
    func emphasisDiffersUnderIncreasedContrast() {
        let plain = DesignTokens.emphasis(for: .light)
        let contrasted = DesignTokens.emphasis(for: .increasedContrast)

        #expect(plain != contrasted)
        #expect(contrasted.borderWidth > plain.borderWidth)
        #expect(contrasted.outlineOpacity > plain.outlineOpacity)
        #expect(contrasted.promotesSecondaryText)
        #expect(!plain.promotesSecondaryText)
    }

    @Test("supporting text is promoted to primary under Increase Contrast")
    func supportingTextIsPromotedUnderIncreasedContrast() {
        #expect(DesignTokens.supportingTextColor(for: .light) == DesignTokens.Palette.secondaryText)
        #expect(
            DesignTokens.supportingTextColor(for: .increasedContrast)
                == DesignTokens.Palette.primaryText
        )
    }

    // MARK: - Provenance: who put the surface on the screen (focus-0nm, U-1)

    /// **All four cells of {provenance} × {reduceTransparency}, and both directions.**
    ///
    /// A membership test would not do here. The claim is not "an uninvited surface can be
    /// opaque" — it is that it is opaque in every cell, and that the summoned half still answers
    /// the way it always has, so the axis is a real second reason rather than a switch that
    /// turned transparency off everywhere.
    @Test("an uninvited surface is opaque in all four cells, and a summoned one is not")
    func provenanceDecidesTheFillIndependentlyOfTheTraits() {
        for traits in [AppearanceTraits.light, .dark, .reduceTransparency] {
            #expect(
                DesignTokens.material(for: traits, provenance: .uninvited) == .opaque,
                "an uninvited surface stayed translucent under \(traits.colorScheme)"
            )
        }
        // The other half, in both directions: the summoned answer still follows the trait, so
        // this is an axis rather than a global opacity switch.
        #expect(DesignTokens.material(for: .light, provenance: .summoned) == .material)
        #expect(DesignTokens.material(for: .dark, provenance: .summoned) == .material)
        #expect(DesignTokens.material(for: .reduceTransparency, provenance: .summoned) == .opaque)
        #expect(
            DesignTokens.material(for: .light, provenance: .uninvited)
                != DesignTokens.material(for: .light, provenance: .summoned),
            "the two provenances agree in the cell where they must differ"
        )
        #expect(SurfaceProvenance.allCases.count == 2, "a third provenance decides nothing yet")
    }

    // MARK: - The leading-edge rule (focus-0nm, U-1)

    /// **A question and an accusation must not look alike**, and this is the colour half of it.
    ///
    /// Resolved rather than described, for the reason the status fold is: e11b moves both hues
    /// into an asset catalogue, and two Color Sets with one value would otherwise stay "distinct"
    /// for ever. The popover takes no rule at all — it is summoned, and a person who clicked the
    /// status item already knows why it is on their screen.
    @Test("the question's rule and the accusation's rule are different colours")
    func theTwoDecisionSurfacesAreTintedApart() {
        for traits in [AppearanceTraits.light, .dark, .increasedContrast] {
            let accusation = DesignTokens.decisionRuleTint(for: .accusationPanel, traits: traits)
            let question = DesignTokens.decisionRuleTint(for: .questionPanel, traits: traits)
            let drawnAccusation = accusation.flatMap { Self.drawnComponents($0, traits) }
            let drawnQuestion = question.flatMap { Self.drawnComponents($0, traits) }
            #expect(drawnAccusation != nil && drawnQuestion != nil)
            #expect(
                drawnAccusation != drawnQuestion,
                """
                the question and the accusation draw the same rule in \(traits.colorScheme): \
                \(String(describing: drawnAccusation)) — U-1's two surfaces have stopped being \
                told apart at a glance
                """
            )
        }
        #expect(
            DesignTokens.decisionRuleTint(for: .menuBarPopover, traits: .light) == nil,
            "the summoned surface grew a rule it does not need"
        )
        #expect(DesignTokens.decisionRuleWidth == 3)
    }

    // MARK: - The colour-scheme mapping (P-32: the only place the two vocabularies meet)

    @Test("the domain colour scheme maps to the SwiftUI one it names")
    func colorSchemeMappingHolds() {
        #expect(AppearanceColorScheme.dark.swiftUI == .dark)
        #expect(AppearanceColorScheme(.dark) == .dark)
        #expect(AppearanceColorScheme(.light) == .light)
    }

    // MARK: - Colour is never the only channel

    @Test("every status has a distinct tint, and three non-colour channels besides")
    func statusChannelsAreIndependent() {
        let statuses = FocusStatus.allCases
        #expect(statuses.count == 5)

        // The non-colour channels are the ones that must survive a user who cannot use
        // colour at all. Tint distinctness is asserted too, but it is the fourth channel.
        #expect(Set(statuses.map(\.markAssetName)).count == statuses.count)
        #expect(Set(statuses.map(\.shape)).count == statuses.count)
        #expect(Set(statuses.map(\.shortLabelKey)).count == statuses.count)
        // **Resolved, not described** (focus-0nm). This line used to compare
        // `tint(for:).description`, and for a `Color` backed by an asset Color Set that string
        // is the ASSET NAME: two Color Sets holding identical values stay "distinct" for ever,
        // and the witness this assertion is supposed to be could never go red. e11b moves these
        // five tints into an asset catalogue, so the witness had to start working before the
        // palette arrives, not after. It now collapses each dynamic colour to the four numbers
        // a person's eye is actually served, in both schemes.
        for traits in [AppearanceTraits.light, .dark, .increasedContrast] {
            let drawn = statuses.map { Self.drawnComponents(DesignTokens.tint(for: $0, traits: traits), traits) }
            #expect(
                drawn.allSatisfy { $0 != nil },
                "a status tint could not be resolved at all in \(traits.colorScheme)"
            )
            #expect(
                Set(drawn.map { $0 ?? [] }).count == statuses.count,
                """
                two statuses draw the same colour in \(traits.colorScheme): \(drawn) — colour is                 the fourth channel and it has stopped telling the five apart
                """
            )
        }
    }

    /// **The repair itself, red-proofed** (focus-0nm).
    ///
    /// The old spelling compared `Color.description`, and for a *named* colour — which is what
    /// an asset Color Set produces — that string carries the name. Two Color Sets holding the
    /// same values are therefore "distinct" for ever under it, which is precisely the leak e11b's
    /// palette work needs this witness to catch. There is no asset catalogue in the build yet, so
    /// the case is constructed the way `NSColor` constructs one: two names over one value.
    ///
    /// Without this test the repair above would rest on an argument. With it, restoring
    /// `.description` fails here as well as leaving the fold vacuous.
    @Test("the tint witness compares what is drawn, not what a colour calls itself")
    func theTintWitnessResolvesRatherThanDescribes() {
        let spruce = Color(nsColor: NSColor(name: "Spruce") { _ in .systemGreen })
        let kiln = Color(nsColor: NSColor(name: "Kiln") { _ in .systemGreen })

        #expect(
            spruce.description != kiln.description,
            "two named colours over one value describe themselves alike — the leak is elsewhere"
        )
        #expect(
            Self.drawnComponents(spruce, .light) == Self.drawnComponents(kiln, .light),
            "the two names really do draw the same colour, so the witness must say so"
        )
        #expect(Self.drawnComponents(spruce, .light) != nil)
    }

    /// A dynamic colour as the four 8-bit numbers it is drawn with, in the appearance the traits
    /// name, or `nil` when it cannot be resolved at all.
    ///
    /// sRGB because that is the space the snapshot lane rasterises into, so this compares what a
    /// person sees rather than what a colour calls itself. `nil` rather than a substitute value:
    /// an unresolvable tint is a finding, and a substitute would let two of them collide into
    /// "distinct enough".
    static func drawnComponents(_ color: Color, _ traits: AppearanceTraits) -> [Int]? {
        guard let srgb = NSColor(color).resolved(for: traits).usingColorSpace(.sRGB) else {
            return nil
        }
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent]
            .map { Int(($0 * 255).rounded()) }
    }

    @Test("the status label is forced on when the user differentiates without colour")
    func labelIsForcedWithoutColor() {
        // A compact surface may legitimately ask for a glyph-only badge …
        #expect(!StatusBadge.showsLabel(requested: false, traits: .light))
        #expect(StatusBadge.showsLabel(requested: true, traits: .light))

        // … but not when the label is the channel the user is relying on.
        let withoutColor = AppearanceTraits(differentiateWithoutColor: true)
        #expect(StatusBadge.showsLabel(requested: false, traits: withoutColor))
        #expect(StatusBadge.showsLabel(requested: true, traits: withoutColor))
    }

    @Test("every status outline draws a non-empty, distinct path")
    func statusOutlinesAreDistinct() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 24)
        var descriptions: Set<String> = []

        for shape in StatusShape.allCases {
            let path = StatusOutline(shape).path(in: rect)
            #expect(!path.isEmpty)
            #expect(!path.boundingRect.isEmpty)
            descriptions.insert(path.description)
        }

        #expect(descriptions.count == StatusShape.allCases.count)
    }

    // MARK: - The string seam

    @Test("the identity transform leaves catalog text untouched")
    func identityTransformIsIdentity() {
        let transform = ShellStringTransform.identity
        #expect(transform("Close Window") == "Close Window")
        #expect(transform.name == "identity")
    }

    @Test("a transform is applied to whatever the catalog resolved to")
    func transformIsApplied() {
        let shouting = ShellStringTransform(name: "shout") { $0.uppercased() }
        #expect(shouting(ShellStrings.string(.commandCloseWindow)).uppercased()
            == ShellStrings.string(.commandCloseWindow).uppercased())
        #expect(shouting("close") == "CLOSE")
    }

    @Test("the environment default is the shipping transform, not a test one")
    func environmentDefaultIsIdentity() {
        var values = EnvironmentValues()
        #expect(values.shellStringTransform.name == "identity")

        values.shellStringTransform = ShellStringTransform(name: "other") { $0 }
        #expect(values.shellStringTransform.name == "other")
    }
}
