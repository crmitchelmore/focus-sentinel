import Foundation
import Testing

@testable import FocusCore

@Suite("Appearance traits")
struct AppearanceTraitsTests {
    @Test("systemDefault is the all-false light configuration")
    func systemDefaultIsAllFalseLight() {
        let traits = AppearanceTraits.systemDefault

        #expect(traits.colorScheme == .light)
        #expect(traits.increasedContrast == false)
        #expect(traits.reduceTransparency == false)
        #expect(traits.reduceMotion == false)
        #expect(traits.differentiateWithoutColor == false)
        #expect(traits == AppearanceTraits.light)
    }

    @Test("the five named snapshot variants are pairwise distinct")
    func namedVariantsArePairwiseDistinct() {
        let variants = AppearanceTraits.namedVariants
        #expect(variants.count == 5)

        let names = Set(variants.map(\.name))
        #expect(names.count == 5, "variant names must be unique — they become file names")

        let traits = variants.map(\.traits)
        for i in traits.indices {
            for j in traits.indices where j > i {
                #expect(
                    traits[i] != traits[j],
                    "variants \(variants[i].name) and \(variants[j].name) are identical, so a snapshot could not tell them apart"
                )
            }
        }
    }

    @Test("the named variants are exactly the five the matrix promises, in order")
    func namedVariantsAreTheDocumentedFive() {
        #expect(
            AppearanceTraits.namedVariants.map(\.name)
                == ["light", "dark", "increasedContrast", "reduceTransparency", "reduceMotion"]
        )
    }

    @Test("each accessibility variant differs from light in exactly the one field it names")
    func eachVariantIsolatesOneSetting() {
        #expect(AppearanceTraits.dark.colorScheme == .dark)
        #expect(AppearanceTraits.dark.increasedContrast == false)

        #expect(AppearanceTraits.increasedContrast.increasedContrast == true)
        #expect(AppearanceTraits.increasedContrast.reduceTransparency == false)
        #expect(AppearanceTraits.increasedContrast.reduceMotion == false)

        #expect(AppearanceTraits.reduceTransparency.reduceTransparency == true)
        #expect(AppearanceTraits.reduceTransparency.increasedContrast == false)
        #expect(AppearanceTraits.reduceTransparency.reduceMotion == false)

        #expect(AppearanceTraits.reduceMotion.reduceMotion == true)
        #expect(AppearanceTraits.reduceMotion.increasedContrast == false)
        #expect(AppearanceTraits.reduceMotion.reduceTransparency == false)
    }

    @Test("traits round-trip through Codable")
    func traitsRoundTripThroughCodable() throws {
        let original = AppearanceTraits(
            colorScheme: .dark,
            increasedContrast: true,
            reduceTransparency: true,
            reduceMotion: true,
            differentiateWithoutColor: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppearanceTraits.self, from: data)

        #expect(decoded == original)
    }
}
