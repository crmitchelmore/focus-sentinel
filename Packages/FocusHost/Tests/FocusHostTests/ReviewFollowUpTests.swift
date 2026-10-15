import AppKit
import FocusCore
import FocusSensing
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// The FocusHost findings the release review (#16) reported and left open, each driven through
/// the shipping wires. No window, popover or panel is shown by anything here.
@Suite("Release review follow-ups", .serialized)
@MainActor
struct ReviewFollowUpTests {
    static let passwordManager = "com.1password.1password"
    static let keychain = "com.apple.keychainaccess"
    static let browser = "com.apple.Safari"

    static func payload(_ bundleID: String) -> ObservedNotification {
        ObservedNotification(
            name: NSWorkspace.didActivateApplicationNotification,
            bundleIdentifier: bundleID,
            localizedName: nil,
            pid: 4_242
        )
    }

    static func activation(_ bundleID: String) -> FrontmostActivation {
        FrontmostActivation(bundleIdentifier: bundleID, pid: 4_242, at: NudgeHostFixture.reference)
    }

    /// A joined root whose graph is attached with `front` as the frontmost application.
    static func attachedRoot(front: String = browser) throws -> AppComposition {
        let (root, _) = try CompositionRootWireTests.joinedRoot(clock: FixedMonotonicClock())
        root.sensingHost.frontmostPayload = { Self.payload(front) }
        root.sensingHost.resume()
        try #require(root.sensingHost.isRunning, "the graph never attached")
        return root
    }

    static func causes(_ root: AppComposition) -> Set<PauseReason> {
        root.sessionHost.snapshot?.pauseCauses ?? []
    }

    // MARK: - 1 · the sensitive pause follows the session, not a flag

    @Test("a session started over a password manager is paused for it")
    func aSessionStartedOverASensitiveAppIsPaused() throws {
        let root = try Self.attachedRoot()
        defer { CompositionRootWireTests.tearDown(root) }

        // Brought forward with no session open: nothing to pause.
        root.sensingHost.receive(Self.activation(Self.passwordManager))
        #expect(root.sessionHost.snapshot == nil)

        // Started from the menu bar, which leaves the password manager in front.
        let wire = try #require(root.menuBar.onAction)
        wire(.startSession)
        let started = try #require(root.sessionHost.snapshot, "no session was opened")
        #expect(started.phase == .paused, "the session runs while a password manager is in front")
        #expect(Self.causes(root) == [.sensitiveApp])

        // And leaving lifts it.
        root.sensingHost.receive(Self.activation(Self.browser))
        #expect(root.sessionHost.snapshot?.phase == .focus)
        #expect(Self.causes(root).isEmpty)
    }

    @Test("a Shortcut that starts a session over a password manager succeeds, paused for it")
    func anIntentStartOverASensitiveAppSucceeds() throws {
        let root = try Self.attachedRoot()
        defer { CompositionRootWireTests.tearDown(root) }
        let center = FocusCommandCenter()
        center.provideWorld {
            ShellCommandWorld(
                hasPriority: root.priorityHost.state.priority != nil,
                sessionPhase: root.sessionHost.snapshot?.phase
            )
        }
        root.registerIntentPerformers(on: center)
        let runner = FocusIntentRunner(center: center)

        root.sensingHost.receive(Self.activation(Self.passwordManager))
        try runner.startSession()

        #expect(root.sessionHost.snapshot?.phase == .paused)
        #expect(Self.causes(root) == [.sensitiveApp])
    }

    @Test("a second sensitive app after a session start still holds the pause")
    func movingBetweenSensitiveAppsKeepsThePause() throws {
        let root = try Self.attachedRoot()
        defer { CompositionRootWireTests.tearDown(root) }

        root.sensingHost.receive(Self.activation(Self.passwordManager))
        root.sessionHost.startSession()
        root.sensingHost.receive(Self.activation(Self.keychain))
        #expect(Self.causes(root) == [.sensitiveApp])
        #expect(root.sessionHost.snapshot?.phase == .paused)
    }

    @Test("a session that ended under the pause leaves nothing behind for the next one")
    func theNextSessionIsPausedToo() throws {
        let root = try Self.attachedRoot()
        defer { CompositionRootWireTests.tearDown(root) }

        root.sessionHost.startSession()
        root.sensingHost.receive(Self.activation(Self.passwordManager))
        #expect(Self.causes(root) == [.sensitiveApp])

        root.sessionHost.completeSession()
        #expect(root.sessionHost.snapshot == nil)

        root.sessionHost.startSession()
        #expect(Self.causes(root) == [.sensitiveApp])
    }

    @Test("a user pause taken over a password manager survives leaving it")
    func leavingLiftsOnlyItsOwnCause() throws {
        let root = try Self.attachedRoot()
        defer { CompositionRootWireTests.tearDown(root) }

        root.sessionHost.startSession()
        root.sensingHost.receive(Self.activation(Self.passwordManager))
        root.sessionHost.pauseSession()
        #expect(Self.causes(root) == [.sensitiveApp, .user])

        root.sensingHost.receive(Self.activation(Self.browser))
        #expect(Self.causes(root) == [.user])
        #expect(root.sessionHost.snapshot?.phase == .paused)
    }

    @Test("switching sensing back on over a password manager pauses for it")
    func resumingOverASensitiveAppPauses() throws {
        let root = try Self.attachedRoot()
        defer { CompositionRootWireTests.tearDown(root) }

        root.sessionHost.startSession()
        root.sessionHost.setSensingPaused(true)
        #expect(Self.causes(root) == [.globalPause])

        root.sensingHost.frontmostPayload = { Self.payload(Self.passwordManager) }
        root.sessionHost.setSensingPaused(false)

        #expect(Self.causes(root) == [.sensitiveApp])
        #expect(root.sessionHost.snapshot?.phase == .paused)
        #expect(root.sensingHost.sensitiveAppIsFrontmost)
    }

    @Test("switching sensing back on after leaving a password manager lifts its pause")
    func resumingAwayFromASensitiveAppLifts() throws {
        let root = try Self.attachedRoot()
        defer { CompositionRootWireTests.tearDown(root) }

        root.sessionHost.startSession()
        root.sensingHost.receive(Self.activation(Self.passwordManager))
        root.sessionHost.setSensingPaused(true)
        #expect(Self.causes(root) == [.globalPause, .sensitiveApp])

        // The person left the password manager while nothing was watching.
        root.sensingHost.frontmostPayload = { Self.payload(Self.browser) }
        root.sessionHost.setSensingPaused(false)

        #expect(Self.causes(root).isEmpty)
        #expect(root.sessionHost.snapshot?.phase == .focus)
    }

    // MARK: - 2 · Stop keeps what the sheet showed

    @Test("Stop keeps the last foreign app the sheet showed, not this one")
    func interruptionKeepsTheSheetsBundleID() throws {
        let root = try Self.attachedRoot()
        defer { CompositionRootWireTests.tearDown(root) }

        root.sessionHost.startSession()
        let sessionID = try #require(root.sessionHost.snapshot?.sessionID)
        root.sensingHost.receive(Self.activation(Self.browser))
        // Pressing Stop in the cockpit brings this app forward.
        root.sensingHost.receive(Self.activation(FocusStore.bundleIdentifier))
        #expect(root.lastActiveBundleID == Self.browser, "the sheet would show something else")

        root.sessionHost.interruptSession(reason: .user, note: nil)

        let record = try #require(try root.sessionHost.sessionStore.session(id: sessionID))
        #expect(record.lastActiveBundleID == root.lastActiveBundleID)
        #expect(record.lastActiveBundleID == Self.browser)
    }

    // MARK: - 3 · an imported shortcut is bound now

    @Test("an imported shortcut is registered without a relaunch")
    func importRebindsTheHotKey() throws {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imported = HotKeySpec(keyCode: HotKeySpec.quickCaptureDefault.keyCode, modifiers: [.command, .option])
        try #require(imported.isRegistrable && imported != .quickCaptureDefault)
        try #require(root.setQuickCaptureShortcut(imported) != nil)
        let url = directory.appending(path: "settings.json")
        guard case .exported = root.writeSettingsExport(to: url) else {
            Issue.record("the settings export failed")
            return
        }

        try #require(root.setQuickCaptureShortcut(.quickCaptureDefault) != nil)
        try #require(root.hotKeyRegistrar.registeredSpec == .quickCaptureDefault)

        guard case .imported = root.readSettingsImport(from: url) else {
            Issue.record("the settings import was refused")
            return
        }
        #expect(root.hotKeyRegistrar.registeredSpec == imported, "bound only at the next launch")
        #expect(root.hotKeySpec == imported)
    }

    @Test("an import binds nothing in a process that never bound a shortcut")
    func importDoesNotStartBinding() throws {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "settings.json")
        guard case .exported = root.writeSettingsExport(to: url) else {
            Issue.record("the settings export failed")
            return
        }
        try FocusStore.setHotKeySpec(
            HotKeySpec(keyCode: HotKeySpec.quickCaptureDefault.keyCode, modifiers: [.command, .option]),
            in: root.modelContainer.mainContext,
            now: NudgeHostFixture.reference
        )
        _ = root.readSettingsImport(from: url)
        #expect(root.hotKeyRegistration == nil)
        #expect(root.hotKeyRegistrar.registeredSpec == nil)
    }

    // MARK: - 4 · a moved dial rebuilds the snapshot

    @Test("adopting moved dials rebuilds the rule snapshot, and unmoved ones do not")
    func adoptingDialsInvalidatesTheSnapshot() async throws {
        let root = CompositionRootTests.root()
        defer { root.stop() }
        let host = root.relevanceHost
        await host.rebuildSnapshot()
        await Self.settle()
        let before = host.snapshotBuildCount

        host.adopt(host.tunings)
        await Self.settle()
        #expect(host.snapshotBuildCount == before, "an unmoved dial cost a store read")

        var moved = host.tunings
        moved.set(.minimumTokenLength, to: Double(moved.count(.minimumTokenLength) + 1))
        try #require(moved != host.tunings)
        host.adopt(moved)
        await Self.settle()
        #expect(host.snapshotBuildCount == before + 1, "the snapshot still holds the old tokens")
    }

    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
