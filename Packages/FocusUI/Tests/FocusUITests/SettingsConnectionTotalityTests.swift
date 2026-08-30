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
///
/// Two of those seven are gone rather than repaired: the notification authorisation with the
/// section that asked for a permission this app cannot use (focus-wy0), and the
/// presentation-exclusion list with the section that told the person to add an app the
/// application offered no way to add (focus-1qm). Five remain, and the walk still descends
/// through every one of them.
@Suite("Totality: the Settings connection")
@MainActor
struct SettingsConnectionTotalityTests {
    /// ## Why every optional is populated (focus-cxs)
    ///
    /// Because a `nil` has no members to walk. Round 6 closed this boundary at the connection
    /// struct and named its own residue in the same breath — *"deeper structs are leaves"* — so a
    /// field invented inside `InterventionSettings`' `usage` or `quietHours` was reached by
    /// nothing. The walk now descends into every value type of ours it meets; asking it the
    /// question about the **type** means handing it a value with every branch filled in.
    @Test("every field of ShellSettingsConnection, to the leaves, is bound to a receipt")
    func theSettingsConnectionIsTotal() {
        let reading = ShellConnectionTotality.audit(
            ShellSettingsConnection(
                preference: .matchSystem,
                setPreference: { _ in },
                storeURL: URL(fileURLWithPath: "/tmp/focus"),
                summary: SensingSummary(isObserving: true, liveObserverCount: 3),
                capabilities: CapabilityMatrix(),
                verdict: Self.verdict,
                intervention: InterventionSettings(
                    quietHours: QuietHoursWindow(startMinuteOfDay: 22 * 60, endMinuteOfDay: 7 * 60)
                ),
                onInterventionAction: { _ in }
            ),
            reported: Set(ShellRenderedField.allCases)
        )

        #expect(reading.isTotal, "\(reading.summary)")
        // Non-vacuity, one level down and further: the walk descends into the intervention
        // settings rather than stopping at them — five of those seven fields were unreported —
        // and now into the values *they* hold. Five fields now: the notification authorisation
        // went with the section that drew it (focus-wy0) and the exclusion list with its own
        // (focus-1qm).
        for member in [
            "intervention.quietHours",
            "intervention.usage",
            "intervention.reducedInterruptionIsForced",
            "intervention.usage.accusationsToday",
            "intervention.quietHours.startMinuteOfDay",
            "summary.isOnSecondaryDisplay",
            "capabilities.observations"
        ] {
            let reached = reading.walkedPaths.contains(member)
            #expect(reached, "the walk never reached \(member)")
        }
        let count = reading.walkedPaths.count
        #expect(count >= 35, "the walk reached only \(count) fields: \(reading.walkedPaths)")
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
    /// A verdict with every member filled in, so the walk has something to reach at each path
    /// `VerdictSnapshot` declares (focus-cxs).
    static let verdict = VerdictSnapshot(
        status: .unrelated,
        stage: .heuristic,
        band: .high,
        drift: .aligned,
        eligibility: .suppressed(.noActivePriority),
        explanation: Explanation.make(
            stage: .heuristic,
            band: .high,
            clauses: [.sustainedDwell(seconds: 180)],
            stamp: .current
        ),
        stampKey: EngineStamp.current.cacheKey
    )

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
