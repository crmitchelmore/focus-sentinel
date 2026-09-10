import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// **The composition root's half of window restoration** (focus-odz.6).
///
/// `ShellWindowRestorationTests` holds the rule; this holds the wiring around it — that the record
/// is written to the store, that it is read back at launch, that only what really opened is
/// counted as restored, and that a launch restores once.
///
/// What no unit process can settle is whether the request becomes a window: only a launch with a
/// scene graph has an `openWindow` to install. The self-check settles that, by seeding a store
/// that says the Keyboard Shortcuts window was open and reading the window list back on the next
/// launch.
@Suite("Window restoration, in the composition root", .serialized)
@MainActor
struct WindowRestorationTests {
    /// Stands where `ShellCommands` stands: the one thing in the application holding SwiftUI's
    /// `openWindow`. Installed on the **shared** centre, because that is the object the root
    /// reaches, and removed on the way out so no later suite inherits it.
    @MainActor
    final class Opener {
        private(set) var opened: [String] = []

        func install() {
            FocusCommandCenter.shared.registerWindowOpener { [self] in opened.append($0) }
        }

        func remove() {
            FocusCommandCenter.shared.unregisterWindowOpener()
        }
    }

    static func root() throws -> AppComposition {
        CompositionRootWireTests.root(clock: FixedMonotonicClock())
    }

    @Test("the record written at quit is the scenes that were open, narrowed and sorted")
    func recordingNarrowsToScenes() throws {
        let root = try Self.root()
        defer { CompositionRootWireTests.tearDown(root) }

        let recorded = root.recordOpenWindows(["help", "quick-capture", "cockpit"])
        #expect(recorded == ["cockpit", "help"])
        #expect(root.lastRecordedOpenWindows == ["cockpit", "help"])
        // …and it is in the store, not only in the object: the reader is the next launch.
        #expect(
            FocusStore.shellState(in: root.modelContainer.mainContext).openWindowsAtLastQuit
                == ["cockpit", "help"]
        )
    }

    /// **The claim.** A store saying the reference was open makes the next launch ask for it.
    @Test("a launch asks for the recorded window that is not already open")
    func restorationAsksForTheRecordedWindow() throws {
        let root = try Self.root()
        defer { CompositionRootWireTests.tearDown(root) }
        let opener = Opener()
        opener.install()
        defer { opener.remove() }

        root.recordOpenWindows(["cockpit", "help"])

        let restored = root.restoreWindows(alreadyOpen: ["cockpit"])
        #expect(restored == ["help"])
        #expect(opener.opened == ["help"])
        #expect(root.restorationRecord == ["cockpit", "help"])
    }

    /// One launch, one restoration: a delegate notification arriving twice, or a scene graph
    /// rebuilt, must not re-open a window somebody has just closed.
    @Test("restoration runs once per launch")
    func restorationIsOncePerLaunch() throws {
        let root = try Self.root()
        defer { CompositionRootWireTests.tearDown(root) }
        let opener = Opener()
        opener.install()
        defer { opener.remove() }

        root.recordOpenWindows(["cockpit", "help"])
        #expect(!root.hasRestoredWindows)

        #expect(root.restoreWindows(alreadyOpen: []) == ["cockpit", "help"])
        #expect(root.hasRestoredWindows)
        // The person closes the reference; a second call must not put it back.
        #expect(root.restoreWindows(alreadyOpen: ["cockpit"]) == [])
        #expect(opener.opened == ["cockpit", "help"])
    }

    /// **A refusal is not a restoration.** With no scene graph there is no opener, and a launch
    /// that counted the refusal as a success would be reporting a window nobody has.
    @Test("with nothing able to open a window, nothing is reported as restored")
    func aRefusedRequestIsNotRecorded() throws {
        let root = try Self.root()
        defer { CompositionRootWireTests.tearDown(root) }
        FocusCommandCenter.shared.unregisterWindowOpener()

        root.recordOpenWindows(["cockpit", "help"])
        let requestsBefore = FocusCommandCenter.shared.windowRequests

        #expect(root.restoreWindows(alreadyOpen: []) == [])
        // The **request** was still made, and is observable: that is what tells "the restoration
        // never ran" apart from "it ran and nothing could answer".
        #expect(FocusCommandCenter.shared.windowRequests == requestsBefore + 2)
        #expect(root.restorationRecord == ["cockpit", "help"])
    }

    /// A store the app has never quit from has nothing recorded, which is not the same as a
    /// person who closed everything — and neither asks for a window.
    @Test("a store with no record asks for nothing")
    func noRecordAsksForNothing() throws {
        let root = try Self.root()
        defer { CompositionRootWireTests.tearDown(root) }
        let opener = Opener()
        opener.install()
        defer { opener.remove() }

        #expect(FocusStore.shellState(in: root.modelContainer.mainContext)
            .openWindowsAtLastQuit == nil)
        #expect(root.restoreWindows(alreadyOpen: []) == [])
        #expect(opener.opened.isEmpty)
        #expect(root.restorationRecord == nil)
    }
}
