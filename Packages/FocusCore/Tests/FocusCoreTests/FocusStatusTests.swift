import Foundation
import Testing

@testable import FocusCore

@Suite("Focus status tokens")
struct FocusStatusTests {
    @Test("there are exactly five statuses")
    func thereAreFiveStatuses() {
        #expect(FocusStatus.allCases.count == 5)
        #expect(
            FocusStatus.allCases == [.relevant, .uncertain, .unrelated, .paused, .onBreak]
        )
    }

    @Test("every SF Symbol is distinct")
    func symbolsAreDistinct() {
        let symbols = FocusStatus.allCases.map(\.symbolName)
        #expect(Set(symbols).count == 5, "two statuses share a glyph: \(symbols)")
        for symbol in symbols {
            #expect(!symbol.isEmpty)
        }
    }

    @Test("every shape token is distinct")
    func shapesAreDistinct() {
        let shapes = FocusStatus.allCases.map(\.shape)
        #expect(Set(shapes).count == 5, "two statuses share a shape: \(shapes)")
        // Every shape token in the vocabulary is used; an unused token is a token nobody
        // maintains.
        #expect(Set(shapes) == Set(StatusShape.allCases))
    }

    @Test("every short label key is distinct")
    func labelKeysAreDistinct() {
        let keys = FocusStatus.allCases.map(\.shortLabelKey)
        #expect(Set(keys).count == 5, "two statuses share a label key: \(keys)")
        for key in keys {
            #expect(key.hasPrefix("status."))
            #expect(key.hasSuffix(".short"))
        }
    }

    @Test("raw values are stable strings, not ordinals")
    func rawValuesAreStableStrings() {
        #expect(FocusStatus.relevant.rawValue == "relevant")
        #expect(FocusStatus.uncertain.rawValue == "uncertain")
        #expect(FocusStatus.unrelated.rawValue == "unrelated")
        #expect(FocusStatus.paused.rawValue == "paused")
        #expect(FocusStatus.onBreak.rawValue == "onBreak")
        #expect(FocusStatus(rawValue: "onBreak") == .onBreak)
    }

    @Test("only unrelated permits an intervention")
    func onlyUnrelatedPermitsIntervention() {
        for status in FocusStatus.allCases {
            #expect(status.permitsIntervention == (status == .unrelated))
        }
        #expect(FocusStatus.uncertain.permitsIntervention == false)
    }

    // MARK: - Lane-gated localisation assertions
    //
    // SwiftPM copies `.xcstrings` verbatim, so under `swift test` every lookup below
    // returns its own key and the assertion would be guaranteed false. Under
    // `xcodebuild test` the catalog is compiled and these run for real. Reported as
    // `skipped` in the inner loop, which is honest, rather than deleted, which is not.

    @Test(
        "every short label resolves to a real, non-key-echoing string",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func labelsResolveToRealStrings() {
        for status in FocusStatus.allCases {
            let label = status.shortLabel
            #expect(!label.isEmpty)
            #expect(
                label != status.shortLabelKey,
                "\(status) resolved to its own key '\(label)' — the catalog was not compiled"
            )
            #expect(!label.contains("status."))
        }
    }

    @Test(
        "the five resolved labels are distinct from one another",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func resolvedLabelsAreDistinct() {
        let labels = FocusStatus.allCases.map(\.shortLabel)
        #expect(Set(labels).count == 5, "two statuses resolved to the same label: \(labels)")
    }

    // MARK: - Lane identity
    //
    // The guard against the whole scheme above quietly becoming a no-op. If a future
    // toolchain stops compiling String Catalogs under xcodebuild, the two tests above would
    // silently start reporting `skipped` in *both* lanes and nothing would notice. This
    // one runs only in the gate lane and fails there instead.

    @Test(
        "the gate lane really is the lane that compiles String Catalogs",
        .enabled(if: LocalizationLane.isGateLane)
    )
    func gateLaneCompilesStringCatalogs() {
        #expect(
            LocalizationLane.catalogsAreCompiled,
            """
            FOCUS_GATE_LANE=xcodebuild is set, so this is the gate — but no compiled \
            strings table was found in FocusCore's bundle. Every localisation assertion \
            in this repository is therefore being skipped in the one lane that is \
            supposed to run it.
            """
        )
    }
}
