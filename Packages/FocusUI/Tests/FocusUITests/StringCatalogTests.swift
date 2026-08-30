import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// The runtime half of F-149's catalog contract.
///
/// `scripts/check-strings.sh` checks the catalogs against the *source*: no hardcoded string,
/// no unreferenced key, no key used but missing, every entry translated. This suite checks
/// them against the *running bundle*, which is where the failure the source lint cannot see
/// shows up: a key that resolves to itself.
///
/// That failure is real and was measured — SwiftPM copies a String Catalog verbatim while
/// Xcode compiles it, so under `swift test` every lookup returns its own key. Hence the lane
/// gate: these assertions run under `xcodebuild test` and report `skipped` in the inner loop,
/// which keeps the inner loop honest instead of green-by-omission.
@Suite("String catalogs", .enabled(if: LocalizationLane.catalogsAreCompiled))
struct StringCatalogTests {
    @Test("every FocusUI key resolves to real text rather than echoing itself")
    func everyShellKeyResolves() {
        for key in ShellStringKey.allCases {
            let resolved = ShellStrings.string(key)
            #expect(!resolved.isEmpty, "\(key.rawValue) resolves to an empty string")
            #expect(
                resolved != key.rawValue,
                "\(key.rawValue) echoes its own key — the catalog was copied, not compiled"
            )
        }
    }

    @Test("every status label resolves from FocusCore's own catalog")
    func everyStatusLabelResolves() {
        for status in FocusStatus.allCases {
            #expect(!status.shortLabel.isEmpty)
            #expect(status.shortLabel != status.shortLabelKey)
        }
        // Distinct labels, not just distinct keys: two statuses that read the same are not
        // distinguishable by the channel a user actually sees.
        #expect(Set(FocusStatus.allCases.map(\.shortLabel)).count == FocusStatus.allCases.count)
    }

    @Test("every registry action title resolves")
    func everyActionTitleResolves() {
        for action in CommandRegistry.shell.actions {
            let resolved = String(localized: action.title)
            #expect(!resolved.isEmpty)
            #expect(resolved != action.titleKey.rawValue)
        }
    }

    @Test("the shell's key table and its catalog are the same set")
    func keyTableMatchesTheCompiledCatalog() throws {
        // The compiled table, read from the package's own bundle — the same file the running
        // app loads. Every declared key must be in it, and it must hold nothing the key
        // table does not declare: a stale key ships text no code can ever draw.
        let url = try #require(
            ShellStrings.bundle.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: "en.lproj"
            )
                ?? ShellStrings.bundle.url(forResource: "Localizable", withExtension: "strings"),
            "FocusUI's compiled strings table is missing from its bundle"
        )

        let table = try #require(
            NSDictionary(contentsOf: url) as? [String: String],
            "FocusUI's compiled strings table could not be read"
        )

        let declared = Set(ShellStringKey.allCases.map(\.rawValue))
        let compiled = Set(table.keys)

        #expect(compiled == declared, "declared but not compiled: \(declared.subtracting(compiled).sorted()); compiled but not declared: \(compiled.subtracting(declared).sorted())")

        for (key, value) in table {
            #expect(!value.isEmpty, "\(key) has an empty English value")
        }
    }

    @Test("no two shell keys share a value by accident in a way that hides a mistake")
    func duplicateValuesAreDeliberate() {
        // Two keys legitimately share text — the cockpit heading and the window title are
        // both "Focus Sentinel" — but a *large* set of duplicates usually means a copy-paste
        // that left a key pointing at the wrong string. Pinning the known pairs makes a new
        // duplicate a deliberate decision.
        var byValue: [String: [String]] = [:]
        for key in ShellStringKey.allCases {
            byValue[ShellStrings.string(key), default: []].append(key.rawValue)
        }
        let duplicated = byValue.filter { $0.value.count > 1 }.map { $0.value.sorted() }.sorted { $0[0] < $1[0] }

        // e05 adds one, and it is the same word for the same act in two places a person reaches
        // it from — which is the case this assertion is meant to permit, not the copy-paste it is
        // meant to catch: "Cancel" backs out of the completion sheet and ends a snooze early. Two
        // retractions, one word.
        //
        // It added two more, and **both pairs are gone with one of their halves**, each with the
        // section that drew it. "Notifications" headed the capability matrix's row and the
        // Intervention pane's own section; that section asked for a permission the app cannot use
        // and went (focus-wy0), and the capability row stays because the matrix reports what this
        // Mac permits rather than what the app intends to do with it. "Remove" took a context
        // item off the pack and an app off the presentation-exclusion list; that list could never
        // hold a row, because nothing in the application could add one, so its section went too
        // (focus-1qm) and only the context pack's verb is left.
        #expect(
            duplicated == [
                ["priority.complete.action.cancel", "shell.menuBar.cancelSnooze"],
                ["shell.cockpit.heading", "shell.window.cockpit.title"],
                ["shell.help.heading", "shell.window.help.title"]
            ],
            "unexpected duplicate catalog values: \(duplicated)"
        )
    }
}
