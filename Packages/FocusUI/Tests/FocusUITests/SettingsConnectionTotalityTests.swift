import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// **The Settings connection's half of the totality boundary** (focus-7ow).
///
/// `ShellSettingsConnection` lives here rather than in `FocusCore`, so its audit does too. Five of
/// `InterventionSettings`' seven fields — quiet hours, the notification authorisation, today's
/// spend, the presentation-exclusion list, and whether Reduce Motion forced the switch — reached
/// the Settings window and were reported by nothing, and the Privacy pane's store path was
/// reported by the **window** rather than by the pane, so a mutation that handed the pane
/// `URL(fileURLWithPath: "/")` was invisible.
@Suite("Totality: the Settings connection")
@MainActor
struct SettingsConnectionTotalityTests {
    @Test("every field of ShellSettingsConnection is bound to a receipt")
    func theSettingsConnectionIsTotal() {
        let reading = ShellConnectionTotality.audit(
            ShellSettingsConnection(
                preference: .matchSystem,
                setPreference: { _ in },
                storeURL: URL(fileURLWithPath: "/tmp/focus"),
                summary: .inactive,
                capabilities: CapabilityMatrix(),
                verdict: nil,
                intervention: InterventionSettings(),
                onInterventionAction: { _ in }
            ),
            reported: Set(ShellRenderedField.allCases)
        )

        #expect(reading.isTotal, "\(reading.summary)")
        // Non-vacuity: the walk descended into the intervention settings rather than stopping at
        // them, which is the whole point — five of those seven fields were unreported.
        for member in [
            "intervention.quietHours",
            "intervention.authorisation",
            "intervention.usage",
            "intervention.presentationExclusions",
            "intervention.reducedInterruptionIsForced"
        ] {
            #expect(reading.walkedPaths.contains(member), "the walk never reached \(member)")
        }
        #expect(
            reading.walkedPaths.count >= 20,
            "the walk reached only \(reading.walkedPaths.count) fields: \(reading.walkedPaths)"
        )
    }

    /// **Nothing may be bound to a field no window ever stamps.** The audit chains into
    /// `ShellRenderFidelity` through the expectation set, and `ShellRenderFidelity` skips a field
    /// nobody expects — so a binding whose field appears in no view is a binding to nothing, and
    /// the chain would have a hole in the middle where nobody was looking.
    @Test("every field both connections bind is stamped by some view in the shell")
    func everyBoundFieldIsStampedSomewhere() throws {
        let sources = try Self.shellSourceFiles()
        var bound: Set<ShellRenderedField> = []
        for echoes in [CockpitConnection.fieldEchoes, ShellSettingsConnection.fieldEchoes] {
            for echo in echoes.values {
                if case .drawn(let fields) = echo { bound.formUnion(fields) }
            }
        }

        var stamped: Set<ShellRenderedField> = []
        for text in sources {
            for field in ShellRenderedField.allCases where text.contains(".\(field.rawValue),") {
                stamped.insert(field)
            }
        }

        let missing = bound.subtracting(stamped).map(\.rawValue).sorted()
        #expect(missing.isEmpty, "no view stamps \(missing)")
        #expect(!bound.isEmpty)
    }

    /// Every `.swift` file in this package, read once.
    ///
    /// A source read rather than a render, because what is being asserted is that a **call site
    /// exists** for each bound field — the render half is `ShellRenderFidelity`'s, and it runs in
    /// the app where the windows are real. This is the cheap half, and it is the half that
    /// catches a binding added without a stamp.
    static func shellSourceFiles() throws -> [String] {
        var directory = URL(fileURLWithPath: #filePath)
        // …/Tests/FocusUITests/<this file> → the package root, then Sources.
        directory.deleteLastPathComponent()
        directory.deleteLastPathComponent()
        directory.deleteLastPathComponent()
        let sources = directory.appendingPathComponent("Sources")

        guard
            let walker = FileManager.default.enumerator(
                at: sources,
                includingPropertiesForKeys: nil
            )
        else {
            Issue.record("the package's Sources directory could not be walked at \(sources.path)")
            return []
        }

        var texts: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            texts.append(try String(contentsOf: url, encoding: .utf8))
        }
        #expect(texts.count > 10, "only \(texts.count) source files were read")
        return texts
    }
}
