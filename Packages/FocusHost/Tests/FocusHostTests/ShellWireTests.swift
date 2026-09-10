import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

/// **The far end of the three wires that live in `App/`** (focus-cp2).
///
/// `App/` is not a package: no test bundle can import it, and four no-op mutations to its scene
/// graph survived the whole nineteen-stage gate. What can be reached from here is the *other* end
/// of each wire — the named verb the scene calls — and that is what these drive. The wires
/// themselves are asserted by `scripts/self-check.sh`, which is the only lane in the programme
/// that runs the shipping scene graph in the shipping process.
///
/// Both halves are needed and neither is sufficient. If the verb does nothing, the self-check's
/// effect assertions fail while its receipt passes; if the wire is a no-op, the receipt fails
/// while everything here still passes.
@Suite("The shell's three wires, at the composition root's end", .serialized)
@MainActor
struct ShellWireTests {
    static func root() -> AppComposition {
        CompositionRootTests.root()
    }

    @Test("nothing is claimed to have fired before anything has")
    func noWireHasFiredAtLaunch() {
        let root = Self.root()
        defer { root.stop() }
        #expect(root.shellWires.isEmpty)
    }

    /// The undo wire, which is F-93's whole menu integration: the manager reaches **both**
    /// journals, because the two of them drive one Edit menu and a scene that adopted into one
    /// and forgot the other is a scene with a half-working ⌘Z.
    @Test("the undo-manager wire hands the window's manager to both journals")
    func theUndoWireReachesBothJournals() {
        let root = Self.root()
        defer { root.stop() }
        let manager = UndoManager()

        root.undoManagerChanged(manager)

        #expect(root.shellWires.contains(.undoManagerChanged))
        #expect(root.priorityHost.journalUndoManager === manager)
        #expect(root.sessionHost.journalUndoManager === manager)
    }

    /// The appearance wire, and the sentinel the self-check reads. `adoptedTraits` is `nil` until
    /// somebody hands the panel traits, which is what makes "the shell themed it" distinguishable
    /// from "nobody ever told it anything" on a machine whose appearance is the default.
    @Test("the appearance wire themes the pre-built quick-capture panel")
    func theAppearanceWireThemesTheCapturePanel() {
        let root = Self.root()
        defer { root.stop() }
        #expect(
            root.quickCapturePanel.adoptedTraits == nil,
            "the panel claims to have been themed before anything themed it"
        )

        let traits = AppearanceTraits(
            colorScheme: .dark,
            increasedContrast: true,
            reduceTransparency: true,
            reduceMotion: true,
            differentiateWithoutColor: true
        )
        root.appearanceChanged(traits)

        #expect(root.shellWires.contains(.appearanceChanged))
        #expect(root.quickCapturePanel.adoptedTraits == traits)
    }

    /// The handoff wire. It **shows** and never mutates: there is no route from a delivered URL
    /// to a stored priority that does not pass through a person pressing Replace (F-142).
    @Test("the handoff wire shows a focus:// URL and changes no stored priority")
    func theHandoffWireShowsAndDoesNotMutate() throws {
        let root = Self.root()
        defer { root.stop() }
        let priorities = PriorityStore(
            context: root.modelContainer.mainContext,
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
        )
        let committed = try priorities.setPriority(intent: "Write the Q3 proposal for Acme")
        root.refreshCockpit()

        let url = try #require(URL(string: "focus://start?task=Review%20the%20Acme%20contract"))
        root.receive(url)

        #expect(root.shellWires.contains(.handoffReceived))
        #expect(root.cockpitState.pendingHandoff?.task == "Review the Acme contract")
        #expect(
            try priorities.activeTask()?.id == committed,
            "a URL replaced the person's commitment without them pressing anything"
        )
    }

    /// A URL the parser refuses reaches the same place and shows nothing. The wire still fired —
    /// the receipt is about the closure, not about the URL — and there is no sheet to dismiss.
    @Test("a refused focus:// URL shows nothing")
    func aRefusedHandoffShowsNothing() throws {
        let root = Self.root()
        defer { root.stop() }

        let url = try #require(URL(string: "focus://complete?task=whatever"))
        root.receive(url)

        #expect(root.shellWires.contains(.handoffReceived))
        #expect(root.cockpitState.pendingHandoff == nil)
    }
}
