import Foundation
import Testing

@testable import FocusUI

/// **Which windows a relaunch puts back** (focus-odz.6).
///
/// AppKit restores a window's frame and, for a SwiftUI `Window(id:)` scene, not whether the window
/// exists at all — measured in this app's own self-check, where a launch inheriting a closed
/// cockpit has no `NSWindow` for it. So the app records the scenes that were open when it quit and
/// asks for them again. The rule is a pure function over two lists precisely so it can be held
/// here, with no window server: what it does in the shipping process is the self-check's, which
/// seeds a store saying the reference was open and reads the window list back on the next launch.
@Suite("Window restoration")
struct ShellWindowRestorationTests {
    /// **`nil` is not `[]`, and the app acts differently on them.**
    ///
    /// Nothing recorded — a first launch, or one after a crash — means leave the scene graph
    /// alone. An empty list means the person really had closed everything. They agree about what
    /// to *open*, and they are kept apart in the store because that is where the distinction
    /// stops a first launch being read as "they closed everything".
    @Test("with nothing recorded, nothing is asked for")
    func nothingRecordedOpensNothing() {
        #expect(ShellWindowRestoration.windowsToReopen(recorded: nil, alreadyOpen: []) == [])
        #expect(
            ShellWindowRestoration.windowsToReopen(recorded: nil, alreadyOpen: ["cockpit"]) == []
        )
        #expect(ShellWindowRestoration.windowsToReopen(recorded: [], alreadyOpen: []) == [])
    }

    /// The claim: a window recorded and not currently on screen is asked for.
    @Test("a recorded window that is not open is asked for")
    func recordedWindowsAreReopened() {
        #expect(
            ShellWindowRestoration.windowsToReopen(recorded: ["help"], alreadyOpen: [])
                == [.help]
        )
        #expect(
            ShellWindowRestoration.windowsToReopen(
                recorded: ["cockpit", "help"],
                alreadyOpen: ["cockpit"]
            ) == [.help]
        )
    }

    /// SwiftUI's `Window` scene opens the cockpit itself, so asking again would be asking for a
    /// window that is already there — and `openWindow(id:)` on an open window brings it forward,
    /// which is a thing this must not do behind somebody's back at launch.
    @Test("a window that is already open is never asked for again")
    func alreadyOpenWindowsAreLeftAlone() {
        #expect(
            ShellWindowRestoration.windowsToReopen(
                recorded: ["cockpit", "help"],
                alreadyOpen: ["cockpit", "help"]
            ) == []
        )
    }

    /// Declaration order rather than recorded order, so two runs that recorded the same set in
    /// different orders ask for the same thing.
    @Test("the order asked for is the declaration order, not the recorded one")
    func theOrderIsDeclared() {
        #expect(
            ShellWindowRestoration.windowsToReopen(
                recorded: ["history", "help", "cockpit"],
                alreadyOpen: []
            ) == ShellWindow.allCases
        )
    }

    /// An id no scene declares cannot be asked for: there is nothing to ask.
    @Test("an unrecognised identifier is not a window this app can open")
    func unknownIdentifiersAreIgnored() {
        #expect(
            ShellWindowRestoration.windowsToReopen(
                recorded: ["quick-capture", "status-item", "help"],
                alreadyOpen: []
            ) == [.help]
        )
    }

    /// **What is worth writing down**, out of whatever `NSApp.windows` happens to hold.
    ///
    /// AppKit's window list carries a great deal that is not a scene — the status item's own
    /// window, the quick-capture panel, a nudge panel, an About panel. Storing one of those would
    /// put a value in the column that nothing could ever act on.
    @Test("only declared scenes are recorded, sorted and de-duplicated")
    func onlyScenesAreRecordable() {
        #expect(
            ShellWindowRestoration.recordable(
                ["help", "quick-capture", "cockpit", "", "help"]
            ) == ["cockpit", "help"]
        )
        #expect(ShellWindowRestoration.recordable([]) == [])
        #expect(ShellWindowRestoration.recordable(["nudge-panel"]) == [])
    }

    /// The round trip the store makes: what was recorded is exactly what can be asked for again.
    @Test("everything recordable is something restoration can ask for")
    func theTwoHalvesAgree() {
        let recorded = ShellWindowRestoration.recordable(
            ShellWindow.allCases.map(\.id) + ["quick-capture"]
        )
        #expect(
            ShellWindowRestoration.windowsToReopen(recorded: recorded, alreadyOpen: [])
                == ShellWindow.allCases
        )
    }
}
