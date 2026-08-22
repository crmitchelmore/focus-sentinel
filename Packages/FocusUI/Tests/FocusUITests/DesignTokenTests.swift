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
    // MARK: - Reduce Transparency

    @Test("materials collapse to an opaque fill under Reduce Transparency")
    func materialCollapsesUnderReduceTransparency() {
        #expect(DesignTokens.material(for: .light) == .material)
        #expect(DesignTokens.material(for: .dark) == .material)
        #expect(DesignTokens.material(for: .reduceTransparency) == .opaque)
        #expect(DesignTokens.material(for: .light) != DesignTokens.material(for: .reduceTransparency))
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
        #expect(Set(statuses.map(\.symbolName)).count == statuses.count)
        #expect(Set(statuses.map(\.shape)).count == statuses.count)
        #expect(Set(statuses.map(\.shortLabelKey)).count == statuses.count)
        #expect(Set(statuses.map { DesignTokens.tint(for: $0).description }).count == statuses.count)
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
