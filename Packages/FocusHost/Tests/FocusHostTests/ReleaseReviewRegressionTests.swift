import AppKit
import FocusCore
import FocusUI
import Foundation
import Testing

@testable import FocusHost

@Suite("Release review regressions", .serialized)
@MainActor
struct ReleaseReviewRegressionTests {
    @Test("self-checks never fall back to the person's store or implicitly enable interactive probes")
    func selfCheckStoreIsIsolated() {
        #expect(SelfCheck.storeKind(arguments: ["FocusSentinel"]) == .applicationSupport)
        for mode in ["--focus-self-check-nudge", "--focus-session-seed", "--focus-session-restore"] {
            let arguments = ["FocusSentinel", "--focus-self-check", "/tmp/report.json", mode, "/tmp/fixture.store"]
            #expect(SelfCheck.storeKind(arguments: arguments) == .inMemory)
        }
        #expect(SelfCheck.storeKind(arguments: ["FocusSentinel", "--focus-self-check", "/tmp/report.json"]) == .inMemory)
        let fixture = URL(fileURLWithPath: "/tmp/explicit.store")
        #expect(SelfCheck.storeKind(arguments: ["FocusSentinel", "--focus-self-check", "/tmp/report.json", "--focus-store", fixture.path]) == .temporary(fixture))
        let live = ["FocusSentinel", "--focus-self-check", "/tmp/report.json", "--focus-self-check-live-store"]
        #expect(SelfCheck.storeKind(arguments: live) == .applicationSupport)
        #expect(SelfCheck.storeKind(arguments: live + ["--focus-store", fixture.path]) == .temporary(fixture))
    }

    @Test("export failures remain distinct from cancellation and successful writes")
    func exportFailureIsReported() throws {
        let root = CompositionRootTests.root()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let missingParent = directory.appending(path: "missing/export.json")
        for outcome in [root.writeDataExport(to: missingParent), root.writeSettingsExport(to: missingParent)] {
            guard case .failed(let error) = outcome else {
                Issue.record("An unwritable destination was reported as \(outcome.summary)")
                continue
            }
            #expect(!error.localizedDescription.isEmpty)
            #expect(!outcome.summary.contains(directory.path))
            #expect(outcome != .none)
        }
        let valid = directory.appending(path: "export.json")
        guard case .exported(_, let bytes) = root.writeDataExport(to: valid) else {
            Issue.record("The writable control export failed")
            return
        }
        #expect(bytes > 0)
        #expect(try Data(contentsOf: valid).count == bytes)
    }

    @Test("deletion disconnects entry points before waiting for relaunch")
    func deletionQuiescesTheOldRoot() async throws {
        let root = CompositionRootTests.root()
        root.priorityHost.setPriority(intent: "Deletion sentinel", doneWhen: nil)
        root.menuBar.install()
        #expect(root.menuBar.isInstalled)
        #expect(root.registerHotKey(.quickCaptureDefault).isRegistered)
        #expect(root.hotKeyRegistrar.registeredSpec != nil)

        var prepared = false
        var relaunched = false
        root.prepareForStoreDeletion = {
            #expect(!root.menuBar.isInstalled)
            #expect(root.hotKeyRegistrar.registeredSpec == nil)
            #expect(!root.quickCapturePanel.isVisible)
            // The close-window hook runs before destruction, while this context still works.
            let store = PriorityStore(
                context: root.modelContainer.mainContext,
                dateProvider: FixedDateProvider(now: NudgeHostFixture.reference)
            )
            #expect((try? store.activeTask()?.intent) == "Deletion sentinel")
            prepared = true
        }
        root.relaunch = { relaunched = true }
        root.relevanceHost.invalidateSnapshot()
        root.perform(.deleteEverything)
        #expect(prepared && relaunched)
        #expect(root.hasDeletedEverything)
        #expect(root.hotKeyRegistration == nil)
        #expect(root.quickCapturePanel.onCommit == nil)
        // Both an already queued rebuild and a fresh request must avoid the dead context.
        await Task.yield()
        await root.relevanceHost.rebuildSnapshot()
        root.refreshCockpit()
        #expect(root.todaysHistory().entries.isEmpty)
        let settings = root.settingsConnection()
        #expect(settings.summary == .inactive)
        settings.onPrivacyAction(.exportData)
        settings.setPreference(.matchSystem)
        #expect(root.cockpitConnection().actions == nil)
        #expect(root.writeDataExport(to: URL(fileURLWithPath: "/unreachable/export.json")) == .none)
        root.perform(LaunchAtLoginOfferAction.dismiss)
        root.setRitualEnabled(false)
        #expect(root.setQuickCaptureShortcut(.quickCaptureDefault) == nil)
        #expect(root.hotKeyRegistrar.registeredSpec == nil)
    }

    @Test("the delegate closes main scene graphs and leaves auxiliary panels intact")
    func delegateShutdownIsScoped() {
        let scene = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        scene.isReleasedWhenClosed = false
        let sceneContent = NSView()
        scene.contentView = sceneContent
        let auxiliary = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        auxiliary.isReleasedWhenClosed = false
        let auxiliaryContent = NSView()
        auxiliary.contentView = auxiliaryContent
        defer { auxiliary.close() }
        let commands = FocusCommandCenter()
        commands.register { _ in }

        FocusAppDelegate.prepareForStoreDeletion(windows: [scene, auxiliary], commands: commands)

        #expect(scene.contentView == nil)
        #expect(auxiliary.contentView === auxiliaryContent)
        #expect(commands.send(.newPriority) == .undeliverable)
    }
}
