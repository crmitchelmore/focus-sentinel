import AppKit
import FocusCore
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **What the Edit menu's Undo item is actually validated against** (F-93, focus-h6d, focus-icq).
///
/// ## The failure this explains
///
/// `scripts/self-check.sh` failed two assertions on both configurations, so `build-gate.sh`
/// reported FAIL at `selfcheck-debug` and `selfcheck-release` while every other stage was
/// `EXIT=0`:
///
///     FAIL: the Edit menu reads 'Undo Change Priority' after one scripted mutation   got: 'Undo'
///     FAIL: the Edit menu's Undo item is disabled again after taking it              got: True
///
/// and one run read `Undo Typing`, which is the word that gives it away. The report insisted the
/// journal's own manager was correct — `undoManagerTitle` was `Undo Change Priority` — so the menu
/// and the journal were reading two different objects.
///
/// Instrumented in the running application, they were: `journalUndoManager === keyWindow.undoManager`
/// came back **true**, and `keyWindow.firstResponder` was a **field editor** whose `undoManager`
/// was **not** the journal's. `NSTextView` overrides `undoManager` to answer with its own, and
/// AppKit resolves `undo:` by walking the key window's responder chain — so while a `TextField`
/// in the cockpit has focus, the item a person sees belongs to the text field. That is macOS
/// working: while you are editing text, Undo undoes your typing.
///
/// ## What is asserted here
///
/// The mechanism, on real AppKit objects, so the explanation is a test rather than a paragraph:
/// a field editor in the chain hides the window's manager, and ending editing gives it back. It
/// is the executable form of the precondition `SelfCheck.undoReport()` now establishes before it
/// reads the menu, and it is why the gate could pass three times and fail the fourth on
/// byte-identical code — whether a field editor exists at all is app state, not code.
@Suite("The Edit menu's undo and the responder chain", .serialized)
@MainActor
struct UndoResponderChainTests {
    /// A window with one text field in it, which is the whole of the cockpit that matters here.
    ///
    /// Ordered out: nothing needs to be seen, and a test that put a window on the machine running
    /// the gate would be a test with a side effect.
    static func windowWithATextField() -> (NSWindow, NSTextField) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // Never released by `close()`: these tests hold the window in a local, and an
        // AppKit window that releases itself out from under one is a crash rather than a failure.
        window.isReleasedWhenClosed = false
        let field = NSTextField(string: "the priority a person is part-way through typing")
        field.frame = NSRect(x: 20, y: 20, width: 360, height: 24)
        field.isEditable = true
        window.contentView?.addSubview(field)
        return (window, field)
    }

    /// **A focused text field takes Undo, and giving up focus gives it back.**
    ///
    /// The `undoManager` a responder answers with is what AppKit walks to find a target for
    /// `undo:`. `NSResponder`'s default implementation forwards up the chain to the window's; a
    /// field editor's does not. So the two states below are two different menus.
    @Test("a field editor in the responder chain hides the window's undo manager")
    func aFieldEditorOwnsUndoWhileItHasFocus() throws {
        let (window, field) = Self.windowWithATextField()
        defer { window.orderOut(nil) }

        #expect(window.makeFirstResponder(field), "the text field would not take first responder")
        let editing = window.firstResponder
        #expect(
            (editing as? NSTextView)?.isFieldEditor == true,
            "AppKit did not install a field editor, so this is not the state being described"
        )
        #expect(
            editing?.undoManager !== window.undoManager,
            """
            the field editor answered with the window's undo manager, so nothing here explains \
            the Edit menu reading a different one
            """
        )

        // Clicking outside the field, or the probe ending editing, is this.
        #expect(window.makeFirstResponder(nil))
        #expect((window.firstResponder as? NSTextView)?.isFieldEditor != true)
        #expect(
            window.firstResponder?.undoManager === window.undoManager,
            "the window is first responder and the chain still does not resolve to its manager"
        )
    }

    /// **The gate's own failure, reproduced on real AppKit objects.**
    ///
    /// The other half, with the real thing on both ends: `PriorityStore.activate(taskID:undo:)` is
    /// the operation whose action name is `Change Priority`, registered on the window's own
    /// manager exactly as `PriorityHost.adoptUndoManager(_:)` arranges — and then somebody types a
    /// character into the text field.
    ///
    /// That last step is what makes this a reproduction rather than an illustration. A freshly
    /// installed field editor's undo manager **forwards**, so the menu reads the journal's title
    /// and nothing looks wrong; the moment there is a keystroke to take back it answers for
    /// itself, and the title becomes `Undo Typing` — which is the exact string one gate run
    /// reported while `undoManagerTitle` stayed `Undo Change Priority`. The other runs read a bare
    /// `Undo`, the same object at a different point in its own history.
    ///
    /// The titles are compared against each other rather than against English literals, because
    /// `Typing` and `Undo` are AppKit's own localised strings and this is a claim about which
    /// object the chain resolves to, not about what language the machine is in.
    @Test("a keystroke in the cockpit's text field takes the Edit menu off the journal's manager")
    func typingInAFieldTakesTheMenuOffTheJournal() throws {
        let (window, field) = Self.windowWithATextField()
        defer { window.orderOut(nil) }
        let manager = try #require(window.undoManager)

        let container = try FocusStore.makeContainer(kind: .inMemory)
        let store = PriorityStore(context: ModelContext(container))
        let taskID = try store.createTask(intent: "Write the Q3 proposal for Acme")
        try store.activate(taskID: taskID, undo: manager)

        // The relation, which holds whatever locale or lane this runs in: the journal registered a
        // named operation, and the menu title AppKit builds from it is that name.
        #expect(!manager.undoActionName.isEmpty, "the journal registered an operation with no name")
        #expect(manager.undoMenuItemTitle.contains(manager.undoActionName))
        let journalTitle = manager.undoMenuItemTitle

        // And the exact words the gate asserts, where the String Catalog has been processed. In
        // the inner loop it has not and `undo.priority.change` resolves to its own key — a fact
        // about the lane rather than about the journal, so it is gated rather than fudged.
        if LocalizationLane.catalogsAreCompiled {
            #expect(manager.undoActionName == "Change Priority")
            #expect(journalTitle == "Undo Change Priority")
        }

        // The person is in the middle of typing a priority. The field editor now has something of
        // its own to take back, so it stops forwarding and answers for itself.
        #expect(window.makeFirstResponder(field))
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.isFieldEditor)
        editor.insertText(
            "a",
            replacementRange: NSRange(location: editor.string.count, length: 0)
        )

        let whileTyping = try #require(window.firstResponder?.undoManager)
        #expect(whileTyping !== manager)
        #expect(
            whileTyping.undoMenuItemTitle != journalTitle,
            """
            the responder chain still answers with the journal's operation, so nothing here             explains the Edit menu reading something else
            """
        )
        #expect(
            !whileTyping.undoMenuItemTitle.contains(manager.undoActionName),
            "the field editor's manager is carrying the journal's operation, which is not possible"
        )
        // The journal itself never changed. This is the pair of readings the gate reported —
        // `undoManagerTitle` correct, `menuItemTitle` not — and they are two different objects.
        #expect(manager.undoMenuItemTitle == journalTitle)

        // Ending editing is what gives the priority change back to ⌘Z, and it is what
        // `SelfCheck.undoReport()` now does before it reads the menu.
        #expect(window.makeFirstResponder(nil))
        #expect((window.firstResponder as? NSTextView)?.isFieldEditor != true)
        #expect(window.firstResponder?.undoManager === manager)
        #expect(manager.canUndo)

        // …and taking it leaves the manager with nothing to offer, which is the second assertion
        // the gate makes and the second one that was failing.
        manager.undo()
        #expect(!manager.canUndo)
        #expect(manager.undoMenuItemTitle != journalTitle)
    }
}
