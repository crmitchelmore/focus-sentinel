import AppKit
import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// **The app's own six colours, held to the two things a palette can actually be wrong about**
/// (focus-w41, e11 direction §1.2).
///
/// A palette is a matter of taste and this file does not pretend otherwise. What it holds is the
/// half that is not: that the two places the values are written say the same thing, and that the
/// contrast promises made *about* those values are true of the values that shipped.
@Suite("The palette")
struct PaletteTests {
    // MARK: - The two spellings, both directions

    /// The `.xcassets` in the source tree, read the way the snapshot baselines are read.
    ///
    /// Through `#filePath` rather than `Bundle.module`, and deliberately: the point is to compare
    /// the *committed* catalogue against the declared table, and a bundled copy would be whatever
    /// the build system decided to put there — which on SwiftPM is a verbatim copy that
    /// `NSColor(named:)` cannot read anyway.
    static var catalogDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FocusUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // FocusUI (package root)
            .appendingPathComponent("Sources/FocusUI/Resources/Palette.xcassets")
    }

    /// One cell of a Color Set: the four appearance combinations, keyed the way the catalogue
    /// keys them.
    struct Cell: Hashable {
        var dark: Bool
        var highContrast: Bool
    }

    /// Every colour in one `.colorset`, read out of its `Contents.json`.
    static func catalogValues(for role: DesignTokens.Palette.Role) throws -> [Cell: DesignTokens.PaletteValue] {
        let url = catalogDirectory
            .appendingPathComponent("\(role.assetName).colorset")
            .appendingPathComponent("Contents.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let colors = ((json as? [String: Any])?["colors"] as? [[String: Any]]) ?? []

        var table: [Cell: DesignTokens.PaletteValue] = [:]
        for entry in colors {
            let appearances = (entry["appearances"] as? [[String: String]]) ?? []
            let cell = Cell(
                dark: appearances.contains { $0["appearance"] == "luminosity" && $0["value"] == "dark" },
                highContrast: appearances.contains { $0["appearance"] == "contrast" && $0["value"] == "high" }
            )
            let components = ((entry["color"] as? [String: Any])?["components"] as? [String: String]) ?? [:]
            func channel(_ name: String) -> Int {
                let text = components[name] ?? ""
                return Int(text.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? -1
            }
            table[cell] = DesignTokens.PaletteValue(channel("red"), channel("green"), channel("blue"))
        }
        return table
    }

    /// **The catalogue and the table are the same palette, cell by cell, and neither may carry a
    /// cell the other does not.**
    ///
    /// The failure this catches is the one a two-spelling palette always eventually has: somebody
    /// tunes a hue in the asset catalogue because that is where Xcode's colour picker writes, and
    /// every SwiftPM lane goes on drawing and asserting the old value. Both directions, because a
    /// one-way check would let a role be quietly deleted from the catalogue and answered for ever
    /// by the fallback.
    @Test("the committed Color Sets and the declared table are the same six colours")
    func theCatalogueAndTheTableAgree() throws {
        let cells: [Cell: AppearanceTraits] = [
            Cell(dark: false, highContrast: false): .light,
            Cell(dark: true, highContrast: false): .dark,
            Cell(dark: false, highContrast: true): AppearanceTraits(
                colorScheme: .light, increasedContrast: true
            ),
            Cell(dark: true, highContrast: true): AppearanceTraits(
                colorScheme: .dark, increasedContrast: true
            )
        ]

        // Direction one: every role the code declares is in the catalogue, with all four cells.
        for role in DesignTokens.Palette.Role.allCases {
            let catalogue = try Self.catalogValues(for: role)
            #expect(
                Set(catalogue.keys) == Set(cells.keys),
                "\(role.assetName).colorset does not carry all four appearance cells: \(catalogue.keys)"
            )
            for (cell, traits) in cells {
                #expect(
                    catalogue[cell] == role.value(for: traits),
                    """
                    \(role.assetName) disagrees in \(cell): the catalogue says \
                    \(String(describing: catalogue[cell])) and the table says \
                    \(role.value(for: traits))
                    """
                )
            }
        }

        // Direction two: the catalogue holds no Color Set the code does not know about — a set
        // nothing can reach is a colour nobody is holding to anything.
        let declared = Set(DesignTokens.Palette.Role.allCases.map { "\($0.assetName).colorset" })
        let onDisk = Set(
            try FileManager.default
                .contentsOfDirectory(atPath: Self.catalogDirectory.path)
                .filter { $0.hasSuffix(".colorset") }
        )
        #expect(onDisk == declared, "the catalogue and the six roles have drifted apart: \(onDisk)")
    }

    /// The six roles are six colours, in every appearance.
    ///
    /// Not a tautology over a literal table: two roles given the same value would be two names
    /// for one decision, and the next round would "change Mist" and silently change Bench.
    @Test("no two roles resolve to the same value in any appearance")
    func theSixRolesAreSix() {
        for traits in Self.everyAppearance {
            let values = DesignTokens.Palette.Role.allCases.map { $0.value(for: traits) }
            #expect(
                Set(values).count == DesignTokens.Palette.Role.allCases.count,
                "two roles collide in \(traits): \(values)"
            )
        }
    }

    /// Every appearance the palette has a cell for.
    static let everyAppearance: [AppearanceTraits] = [
        .light,
        .dark,
        AppearanceTraits(colorScheme: .light, increasedContrast: true),
        AppearanceTraits(colorScheme: .dark, increasedContrast: true)
    ]

    // MARK: - The contrast promises

    /// **Increase Contrast raises contrast, and by enough to matter.**
    ///
    /// The three text roles clear 7:1 against the High Contrast ground in both schemes — the
    /// number the direction's own step was chosen to reach — and every one of them is *further*
    /// from the ground than it was without the setting, which is the half that would catch a step
    /// applied in the wrong direction on some future round.
    @Test("the High Contrast pair clears 7:1 for every text role, in both schemes")
    func highContrastClearsSevenToOne() {
        let textRoles: [DesignTokens.Palette.Role] = [.slate, .mist, .spruce]
        for scheme in [AppearanceColorScheme.light, .dark] {
            let plain = AppearanceTraits(colorScheme: scheme)
            let contrasted = AppearanceTraits(colorScheme: scheme, increasedContrast: true)
            for role in textRoles {
                let contrastedRatio = role.value(for: contrasted)
                    .contrastRatio(against: DesignTokens.Palette.Role.bench.value(for: contrasted))
                let plainRatio = role.value(for: plain)
                    .contrastRatio(against: DesignTokens.Palette.Role.bench.value(for: plain))
                #expect(
                    contrastedRatio >= 7.0,
                    """
                    \(role.assetName) on Bench under Increase Contrast in \(scheme) is \
                    \(contrastedRatio), and a text role must clear 7:1 there
                    """
                )
                #expect(
                    contrastedRatio > plainRatio,
                    """
                    \(role.assetName) in \(scheme) got no further from the ground when the person \
                    asked for more contrast: \(plainRatio) → \(contrastedRatio)
                    """
                )
            }
        }
    }

    /// Every text role clears WCAG AA against the ground it is drawn on, with the setting off too.
    @Test("every text role clears 4.5:1 on Bench without Increase Contrast")
    func textRolesClearAAWithoutTheSetting() {
        for role in [DesignTokens.Palette.Role.slate, .mist, .spruce] {
            for scheme in [AppearanceColorScheme.light, .dark] {
                let traits = AppearanceTraits(colorScheme: scheme)
                let ratio = role.value(for: traits)
                    .contrastRatio(against: DesignTokens.Palette.Role.bench.value(for: traits))
                #expect(ratio >= 4.5, "\(role.assetName) on Bench in \(scheme) is only \(ratio):1")
            }
        }
    }

    // MARK: - Kiln is a lamp, never a voice

    /// **The measurement the ban rests on.**
    ///
    /// Kiln on Bench in the light scheme is 3.87:1 — above WCAG's 3:1 large-text threshold and
    /// below its 4.5:1 body-text one. The direction says "about 4.4:1" (§1.2) and that figure is
    /// wrong in the unsafe direction; this test is where the real number lives, so a future round
    /// that lightens Kiln to make it prettier finds out here rather than in a screenshot.
    @Test("Kiln measures below the body-text threshold on the light ground")
    func kilnIsBelowBodyTextContrastOnBench() {
        let light = AppearanceTraits.light
        let ratio = DesignTokens.contrastAgainstBench(of: .unrelated, traits: light)
        #expect(ratio >= 3.0, "Kiln has fallen below even the large-text threshold: \(ratio):1")
        #expect(ratio < 4.5, "Kiln now clears body text at \(ratio):1 — the ban has lost its reason")

        // Spruce is the comparison the direction draws, and it is why the question's hue may
        // carry the question's words while the accusation's may not.
        let spruce = DesignTokens.contrastAgainstBench(of: .uncertain, traits: light)
        #expect(spruce >= 4.5, "Spruce can no longer carry the query panel's body text: \(spruce):1")
    }

    /// **No text role below 17 pt semibold may be coloured Kiln, in any appearance.**
    ///
    /// The fold is over the whole space — every type role the shell has × every status × every
    /// appearance — rather than over the call sites that exist today, because the rule has to
    /// outlive the call sites. `tintMayCarryText` is arithmetic over the shipped palette and the
    /// role's real point size, so this cannot pass by agreeing with a hand-written table.
    @Test("the drift tint carries no text below the large-text threshold")
    func kilnCarriesNoBodyText() {
        var refused = 0
        for traits in Self.everyAppearance {
            for role in DesignTokens.FontRole.allCases {
                let size = DesignTokens.pointSize(role)
                let large = (role.drawsSemiboldOrHeavier && size >= 17) || size >= 22

                // Only where the arithmetic actually refuses: under Increase Contrast the
                // drift tint darkens to 5.44:1 and legitimately *may* carry body text, which is
                // the setting working rather than the ban failing.
                if !large && traits.colorScheme == .light && !traits.increasedContrast {
                    #expect(
                        !DesignTokens.tintMayCarryText(.unrelated, at: role, traits: traits),
                        """
                        the drift tint is permitted to colour \(role) text at \(size) pt on the \
                        light ground, where it measures \
                        \(DesignTokens.contrastAgainstBench(of: .unrelated, traits: traits)):1 — \
                        Kiln is a lamp, never a voice
                        """
                    )
                    refused += 1
                }

                // The question's hue is the control: a fold that refused everything would prove
                // nothing at all.
                #expect(
                    DesignTokens.tintMayCarryText(.uncertain, at: role, traits: traits),
                    "Spruce may no longer carry \(role) text in \(traits.colorScheme)"
                )
            }
        }
        #expect(refused >= 6, "the fold refused almost nothing — it has stopped covering the space")
    }

    /// And the large end of the space is genuinely reachable: the direction permits Kiln on the
    /// timer digits at ≥ 17 pt semibold, so the token must say yes somewhere or the permission it
    /// grants is imaginary.
    @Test("the drift tint may carry large semibold text, which is what the timer is")
    func kilnMayCarryTheTimer() {
        #expect(DesignTokens.pointSize(.priorityHero) >= 17)
        #expect(DesignTokens.tintMayCarryText(.unrelated, at: .priorityHero, traits: .light))
    }
}
