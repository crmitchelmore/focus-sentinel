import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The live half of the totality boundary** (focus-7ow).
///
/// `ShellConnectionTotalityTests` proves the mechanism and audits each connection type against its
/// own table with every field counted as expected. That is one half of the chain. This is the
/// other: the composition root builds a real connection out of the real graph, records what it
/// handed over, and the audit runs against **the fields it actually recorded an expectation
/// for** — so a table entry pointing at a field this object has no opinion about is a hole, and
/// it is caught here rather than in the app.
///
/// The full chain the two suites close between them:
///
///   every stored property → bound to a field → the root records an expectation for that field
///   → the window reports it → the two are equal
///
/// Break any link and something goes red. Before this existed, the first link did not exist at
/// all: `ShellRenderedField` had a case for every value the round-3 mutant touched and for
/// nothing else, and round 5's residue mutant lied about four more with a nineteen-stage PASS and
/// an empty ok-assertion diff.
@Suite("Totality, against the live composition root", .serialized)
@MainActor
struct ShellTotalityTests {
    static func root() -> AppComposition {
        CompositionRootTests.root()
    }

    @Test("the cockpit connection is total against what the root actually expects")
    func theCockpitIsTotalLive() throws {
        let root = Self.root()
        defer { root.stop() }
        let priorities = PriorityStore(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        _ = try priorities.setPriority(intent: "Write the Q3 proposal for Acme")
        root.refreshCockpit()
        _ = root.cockpitConnection()

        let reading = root.shellTotalityReading(of: .cockpit)
        #expect(reading.isTotal, "\(reading.summary)")
        #expect(reading.connection == "CockpitConnection")
        #expect(reading.walkedPaths.count >= 19, "\(reading.walkedPaths)")
    }

    /// The same with **nothing committed to**, which is the other side of the conditional
    /// expectations: the window draws no session controls and no definition of done, and reports
    /// `noCommitment` for each rather than reporting nothing — because a field nobody mentioned
    /// reads as a section somebody deleted.
    @Test("the cockpit connection is total with no commitment, and says so")
    func theCockpitIsTotalWithNoPriority() {
        let root = Self.root()
        defer { root.stop() }
        root.refreshCockpit()
        _ = root.cockpitConnection()

        let reading = root.shellTotalityReading(of: .cockpit)
        #expect(reading.isTotal, "\(reading.summary)")
    }

    @Test("the Settings connection is total against what the root actually expects")
    func theSettingsWindowIsTotalLive() {
        let root = Self.root()
        defer { root.stop() }
        _ = root.settingsConnection()

        let reading = root.shellTotalityReading(of: .settings)
        #expect(reading.isTotal, "\(reading.summary)")
        #expect(reading.connection == "ShellSettingsConnection")
        #expect(reading.walkedPaths.count >= 20, "\(reading.walkedPaths)")
    }

    /// **The tab selection is the root's, and it reaches the connection** (focus-7ow).
    ///
    /// A macOS `TabView` builds only the selected pane, so before this the Privacy pane's own
    /// receipts never arrived and every Settings value had to be reported from the window — which
    /// left a defect *inside* an unselected pane invisible to every lane in the programme.
    @Test("the root drives which Settings pane the window builds")
    func theRootDrivesTheSettingsTab() {
        let root = Self.root()
        defer { root.stop() }

        #expect(root.settingsConnection().selectedTab == .general)
        root.selectSettingsTab(.privacy)
        #expect(root.settingsTab == .privacy)
        #expect(root.settingsConnection().selectedTab == .privacy)

        // …and the window's own binding writes back through the connection, which is the path a
        // click takes.
        root.settingsConnection().selectTab(.intervention)
        #expect(root.settingsTab == .intervention)
    }

    /// **Reports accumulate forwards; a stale one replaces** (focus-7ow).
    ///
    /// The panes are drawn one at a time and each takes a fresh issue of the connection, so the
    /// reading has to hold what each of them said — the same rule the expectations on the other
    /// side of the comparison already follow. A report carrying an **older** issue still replaces
    /// the whole reading, because a window drawing from a connection the root has replaced is its
    /// own defect and must stay legible as one.
    @Test("the panes' reports accumulate forwards, and a stale one replaces")
    func reportsOfOneIssueAccumulate() {
        let root = Self.root()
        defer { root.stop() }
        let connection = root.settingsConnection()
        let generation = connection.generation

        connection.didDraw(
            ShellSettingsRendering(
                values: ShellRenderedValues(
                    generation: generation,
                    values: [ShellRenderedField.appearancePreference.rawValue: "dark"]
                ),
                setPreference: { _ in },
                onInterventionAction: { _ in }
            )
        )
        // The next pane is drawn under the NEXT issue of the connection — which is what choosing
        // a tab actually produces, because it re-evaluates the window body.
        connection.didDraw(
            ShellSettingsRendering(
                values: ShellRenderedValues(
                    generation: generation + 1,
                    values: [ShellRenderedField.privacyStorePath.rawValue: "/tmp/x"]
                ),
                setPreference: { _ in },
                onInterventionAction: { _ in }
            )
        )

        let merged = root.shellRenderings[.settings] ?? .nothing
        #expect(merged[.appearancePreference] == "dark", "the first pane's report was thrown away")
        #expect(merged[.privacyStorePath] == "/tmp/x")
        #expect(merged.generation == generation + 1)

        // A report from an issue the root has already replaced is not merged into the current
        // answer: it replaces it, so "drawing from something stale" stays readable as that.
        connection.didDraw(
            ShellSettingsRendering(
                values: ShellRenderedValues(
                    generation: 1,
                    values: [ShellRenderedField.settingsTab.rawValue: "general"]
                ),
                setPreference: { _ in },
                onInterventionAction: { _ in }
            )
        )
        let afterStale = root.shellRenderings[.settings] ?? .nothing
        #expect(
            afterStale[.appearancePreference] == nil,
            "a report from a replaced issue was merged into the current answer"
        )
        #expect(afterStale.generation == 1)
    }
}
