import Foundation
import Testing

@testable import FocusCore

/// **The host presents; the decider decides** (T140, R-84a).
///
/// ## Why this is a source scan rather than a behavioural test
///
/// The claim is not "the host produces the right answer" — `NudgeDeciderTests`' truth table and
/// the 19 440-cell cross-product already hold that, on the pure function, with no store and no
/// window. The claim here is **structural**: that the application has exactly one decision path,
/// that it is `NudgeDecider.decide(…)`, and that no second one has grown beside it. No runtime
/// assertion can see a decision that was never taken; a reader of the sources can.
///
/// It is the same instrument `DefaultActionContractTests` and `TypeHierarchyTests` use, aimed at
/// the app target — and it lives in `FocusCoreTests` because that is where the vocabulary it is
/// about is declared, and because `App` is not a package any test target can import.
///
/// ## The needles are composed rather than written
///
/// Three of the shapes below — the two authorisation constructors and the rung's — are the exact
/// strings `check-forbidden.sh` counts files for (R-96a, R-96b, R-96c). A test file containing
/// one as a literal would be a **file that constructs it** as far as a fixed-string grep is
/// concerned, and would fail the very lint it is corroborating. They are therefore assembled at
/// runtime, which is honest about what they are: needles for a reader, not constructions.
@Suite("The nudge host's decision path")
struct NudgeHostContractTests {
    /// The app target's sources, found from this file rather than from a bundle: the question is
    /// about what the sources say, and a test bundle does not contain them.
    static var appDirectory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // …/Tests/FocusCoreTests
            .deletingLastPathComponent()   // …/Tests
            .deletingLastPathComponent()   // …/FocusCore
            .deletingLastPathComponent()   // …/Packages
            .deletingLastPathComponent()   // …/<repo>
            .appending(path: "App", directoryHint: .isDirectory)
    }

    static func sources() throws -> [(name: String, text: String)] {
        let urls = (FileManager.default.enumerator(
            at: appDirectory,
            includingPropertiesForKeys: nil
        )?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }

        return try urls.map { (name: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Lines of code, with comment lines removed. A comment naming a shape is the opposite of a
    /// use of it, and a scan that cannot tell the difference teaches people to stop writing the
    /// comment.
    static func code(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !(trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*"))
            }
    }

    static func files(containing needle: String) throws -> [String] {
        try sources()
            .filter { code($0.text).contains { $0.contains(needle) } }
            .map(\.name)
    }

    // MARK: - One decision path, in one file

    @Test("the app calls the decider in exactly one file, and that file is the nudge host")
    func oneDecisionPath() throws {
        let callers = try Self.files(containing: "NudgeDecider.decide(")

        #expect(callers == ["NudgeHost.swift"])
    }

    @Test("the host calls the decider exactly once")
    func oneCallSite() throws {
        let host = try #require(
            try Self.sources().first { $0.name == "NudgeHost.swift" }
        )
        let calls = Self.code(host.text).filter { $0.contains("NudgeDecider.decide(") }

        #expect(calls.count == 1)
    }

    /// **The whole point.** Every question the decider answers is answered *by the decider*, so
    /// the host cannot reach a different conclusion by asking one of its parts directly. Each
    /// shape below is a gate the decider already runs, and each would be a second decision path
    /// if the host ran it too.
    @Test(
        "the host re-runs none of the decider's own gates",
        arguments: [
            "QueryEligibility.decide(",
            "InterventionEligibility.decide(",
            "SuppressionStack.evaluate(",
            "FatigueController.decide(",
            "FatigueController.permits(",
            "SurfaceRouter.route(",
            "SurfaceRouter.routeQuery("
        ]
    )
    func hostRunsNoGateItself(shape: String) throws {
        let host = try #require(
            try Self.sources().first { $0.name == "NudgeHost.swift" }
        )

        #expect(!Self.code(host.text).contains { $0.contains(shape) })
    }

    // MARK: - The two authorisations are unconstructible from the app target

    /// R-96a and R-96c as a property of the **application** specifically: the app target is where
    /// a host could most plausibly assemble an authorisation out of what it happens to know, and
    /// there is no file in it that does.
    @Test("no file in the app target constructs either authorisation or a rung")
    func appConstructsNoAuthorisation() throws {
        // Composed, never written as literals. See this suite's documentation.
        let warrant = "QueryWarrant" + "("
        let mandate = "InterventionMandate" + "("
        let rung = "LadderRung" + "("

        #expect(try Self.files(containing: warrant).isEmpty)
        #expect(try Self.files(containing: mandate).isEmpty)
        #expect(try Self.files(containing: rung).isEmpty)
    }

    // MARK: - One answer, one rule (R-78, §3.B.9, §3.B.13)

    /// **The duplicate-learned-rule regression.**
    ///
    /// `QueryLedger.answer(…)` commits the rule *and* the immutable receipt as one transaction,
    /// because R-78 forbids any interval in which the app has learned the answer but forgotten
    /// the asking. The composition root used to match `.ruleAndReceipt` alongside `.rule` in one
    /// `case` and hand the bound rule straight to `addRule(…)` — so a real "Yes, add it" wrote
    /// the learned rule **twice**: once inside the ledger's transaction under `rule.id`, and once
    /// again under a fresh identifier. Two chips in the context row, two rows in the Rules pane,
    /// and a ⌘Z that removed only the second of them.
    ///
    /// The fix is a property rather than a comment: `ruleAwaitingPersistence` is `nil` for the
    /// atomic pair, and the root branches on it. These assertions are what stop the two cases
    /// being collapsed back into one pattern.
    @Test("the composition root never re-inserts a rule the ledger already committed")
    func compositionRootWritesNoDuplicateRule() throws {
        let root = try #require(
            try Self.sources().first { $0.name == "AppComposition.swift" }
        )
        let lines = Self.code(root.text)

        // The insert is decided by the outcome, which knows whether anybody has written the row.
        #expect(lines.contains { $0.contains("outcome.ruleAwaitingPersistence") })
        // …and never by a pattern that binds the atomic pair's rule straight into the insert.
        #expect(
            !lines.contains { $0.contains(".ruleAndReceipt(let") },
            "the root binds the ledger's own rule again, which is how the duplicate was written"
        )
        // One insert call site, guarded by that property.
        #expect(lines.filter { $0.contains("priorityHost.addRule(") }.count == 1)
        // The undo the ledger's transaction had no journal to register with is still registered,
        // so R-86's "yes" row keeps its ⌘Z.
        #expect(lines.contains { $0.contains("registerLearnedRuleUndo(") })
    }

    // MARK: - A panel never outlives the presentation gate (R-84, F-35, P-130)

    /// **The stomped-presentation regression.**
    ///
    /// A nudge panel is deliberately sticky — `hidesOnDeactivate` is `false` (R-89) — and
    /// `.fullScreenAuxiliary` is decided at show time from the gate reading of that moment. A
    /// panel shown while the gate was clear is therefore still on screen, and still flagged, when
    /// somebody starts presenting a minute later; P-130 measured such a panel drawn plainly on
    /// top of a real full-screen space. The suppression stack cannot reach it, because that stack
    /// decides whether to *speak* and this nudge has already spoken.
    ///
    /// So the host has to notice the gate closing as an **event**. It does so on the same
    /// activation and corroboration cadence every other nudge decision runs at.
    @Test("the host takes an open panel off a display a presentation has claimed")
    func hostWithdrawsAnOpenPanelForAPresentation() throws {
        let host = try #require(
            try Self.sources().first { $0.name == "NudgeHost.swift" }
        )
        let lines = Self.code(host.text)

        #expect(
            lines.contains { $0.contains("presentation.suppressesOverlays") },
            "the host never reads the presentation gate, so it cannot notice it closing"
        )
        #expect(
            lines.contains { $0.contains("withdrawForPresentation()") },
            "an open panel is left on a display a presentation has claimed"
        )
    }

    // MARK: - A question nobody could see is never written down (focus-x7d, U-1)

    /// **The burned-question regression, and why it is the worst failure this app has.**
    ///
    /// U-1 licenses the app to interrupt on `uncertain` for exactly one reason: the interruption
    /// is a single cheap click that teaches it, after which it never asks again. Every receipt in
    /// `QueryLedger` is immutable and `hasAsked(…)` is gate 11 of the suppression stack, so the
    /// never-ask-twice promise and the burn-it-once hazard are the same mechanism read from two
    /// sides.
    ///
    /// A live drive found the panel on screen at 380 × 2212 and unreadable. Every path that ends
    /// an unanswered question — `expireOpenQuestion()` on a session end, a phase change, a
    /// priority change or a presentation, and `close(_:)` on a preemption — writes a receipt, so
    /// the app would have recorded that question as asked and never asked it again. The person
    /// saw a blank slab; the ledger recorded a conversation.
    ///
    /// The rule these assertions hold is therefore: **a receipt is written only about a question
    /// that reached a surface a person could read.** A question that did not is deferred,
    /// unwritten, and stays askable.
    @Test("no receipt is written about a question that never reached a readable surface")
    func noReceiptForAQuestionNobodyCouldSee() throws {
        let host = try #require(
            try Self.sources().first { $0.name == "NudgeHost.swift" }
        )
        let lines = Self.code(host.text)

        // The reading exists, and it is the panel's own — not an inference from "we called show".
        #expect(
            lines.contains { $0.contains("panel.isPresentedAtIntendedSize") },
            "the host never asks whether the panel a person is being asked to answer is readable"
        )
        // Every ledger write about an open question is guarded by it.
        #expect(
            lines.contains { $0.contains("guard questionWasPresentable()") },
            "a question nobody could read can still spend the app's one chance to ask it"
        )
        #expect(
            lines.filter { $0.contains("questionWasPresentable()") }.count >= 3,
            "at least one of the receipt-writing paths is unguarded"
        )
        // The panel show path is followed by the guard rather than by the delivery bookkeeping.
        #expect(
            lines.contains { $0.contains("guard panel.isPresentedAtIntendedSize else") },
            "a panel that came up unreadable is still counted as a delivered question"
        )
    }

    // MARK: - The scan is proving something

    /// A scan that found no sources would pass every assertion above by describing nothing.
    @Test("the scan reads a real app target with a real host in it")
    func scanIsNotVacuous() throws {
        let sources = try Self.sources()

        #expect(sources.count > 1)
        #expect(sources.contains { $0.name == "NudgeHost.swift" })
        #expect(sources.contains { $0.name == "AppComposition.swift" })
        #expect(sources.contains { $0.name == "RelevanceHost.swift" })
    }

    /// The verdict stream really is a stream: the host is wired to it in the composition root,
    /// which is the only file allowed to know both ends exist.
    @Test("the composition root is what joins the verdict stream to the nudge loop")
    func compositionRootWiresTheLoop() throws {
        let root = try #require(
            try Self.sources().first { $0.name == "AppComposition.swift" }
        )
        let lines = Self.code(root.text)

        #expect(lines.contains { $0.contains("relevanceHost.onJudgement") })
        #expect(lines.contains { $0.contains("nudgeHost.consider(") })
    }

    /// …and `RelevanceHost` publishes it **after** the judgement it already made, so e04's
    /// "this host publishes; nothing acts" survives in the direction that matters: the acting
    /// cannot reach back into the judging.
    @Test("the relevance host publishes the stream and reads nothing back from it")
    func relevanceHostOnlyPublishes() throws {
        let relevance = try #require(
            try Self.sources().first { $0.name == "RelevanceHost.swift" }
        )
        let lines = Self.code(relevance.text)

        // Declared once, called once, and never read for a value.
        #expect(lines.filter { $0.contains("onJudgement?(") }.count == 1)
        #expect(!lines.contains { $0.contains("NudgeDecision") })
        #expect(!lines.contains { $0.contains("NudgeDecider") })
    }
}
