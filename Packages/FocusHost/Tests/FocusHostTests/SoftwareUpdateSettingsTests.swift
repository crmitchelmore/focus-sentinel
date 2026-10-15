import FocusCore
import FocusUI
import Foundation
import Observation
import SwiftData
import Synchronization
import Testing

@testable import FocusHost

/// **An updater that records what it was asked and opens nothing.** The double every suite
/// holds in place of `SparkleUpdater`, whose verbs open a socket.
@MainActor
final class SoftwareUpdaterDouble: SoftwareUpdating {
    private(set) var isStarted = false
    private(set) var automaticChecks: [Bool] = []
    private(set) var manualChecks = 0
    var canCheckForUpdates = true
    var lastCheckDate: Date?
    var lastFailure: SoftwareUpdateFailure?
    var onStatusChange: (@MainActor () -> Void)?

    func setAutomaticChecks(_ enabled: Bool) {
        automaticChecks.append(enabled)
        if enabled { isStarted = true }
    }

    func checkForUpdates() {
        manualChecks += 1
        isStarted = true
    }
}

/// **Update checks are off until the person turns them on, and the choice survives a relaunch**
/// (focus-h8jf).
///
/// The shape is `StoredSettingRestorationTests`': the fact that matters spans two processes, so
/// it is proved with two composition roots over one store file. One process cannot tell a
/// restored choice from a defaulted one.
@Suite("Software updates are opt-in", .serialized)
@MainActor
struct SoftwareUpdateSettingsTests {
    /// **A default root never starts the updater.** The unit lane's root is built over an
    /// in-memory store and gets `NoSoftwareUpdater`; this is the reading the self-check takes of
    /// the shipping one on a default store.
    @Test("a fresh root has checks off and has asked the updater for nothing")
    func aFreshRootAsksForNothing() {
        let root = CompositionRootWireTests.root(clock: FixedMonotonicClock())
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        #expect(!root.softwareUpdateStatus.checksAutomatically)
        #expect(!root.softwareUpdater.isStarted)
        #expect(root.softwareUpdater is NoSoftwareUpdater)
        #expect((root.softwareUpdater as? NoSoftwareUpdater)?.requests == 0)
    }

    @Test("the switch stores the choice first and then reaches the updater")
    func theSwitchStoresThenStarts() {
        let updater = SoftwareUpdaterDouble()
        let root = Self.root(updater: updater)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        root.perform(SoftwareUpdateSettingsAction.setAutomaticChecks(true))
        #expect(FocusStore.softwareUpdateChecksEnabled(in: root.modelContainer.mainContext))
        #expect(updater.automaticChecks == [true])
        #expect(root.softwareUpdateStatus.checksAutomatically)

        root.perform(SoftwareUpdateSettingsAction.setAutomaticChecks(false))
        #expect(!FocusStore.softwareUpdateChecksEnabled(in: root.modelContainer.mainContext))
        #expect(updater.automaticChecks == [true, false])
        #expect(!root.softwareUpdateStatus.checksAutomatically)
    }

    @Test("check now reaches the updater once and stores nothing")
    func checkNowStoresNothing() {
        let updater = SoftwareUpdaterDouble()
        let root = Self.root(updater: updater)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        root.perform(SoftwareUpdateSettingsAction.checkNow)
        #expect(updater.manualChecks == 1)
        #expect(updater.automaticChecks.isEmpty)
        #expect(!FocusStore.softwareUpdateChecksEnabled(in: root.modelContainer.mainContext))
    }

    @Test("the File menu reaches the same updater without opening the cockpit or enabling automatic checks")
    func fileMenuChecksOnce() {
        let updater = SoftwareUpdaterDouble()
        let root = Self.root(updater: updater)
        defer { CompositionRootWireTests.tearDown(root) }
        let center = FocusCommandCenter()
        root.registerSoftwareUpdatePerformer(on: center)

        #expect(center.canCheckForUpdates)
        #expect(center.checkForUpdates())
        #expect(updater.manualChecks == 1)
        #expect(updater.automaticChecks.isEmpty)
        #expect(!root.softwareUpdateStatus.checksAutomatically)
        #expect(center.cockpitRequests == 0)

        updater.canCheckForUpdates = false
        updater.onStatusChange?()
        #expect(!center.canCheckForUpdates)
        #expect(!center.checkForUpdates())
        root.perform(SoftwareUpdateSettingsAction.checkNow)
        #expect(updater.manualChecks == 1)

        updater.canCheckForUpdates = true
        updater.lastFailure = .feedUnavailable
        updater.onStatusChange?()
        #expect(center.canCheckForUpdates)
        #expect(root.settingsConnection().softwareUpdates.failure == .feedUnavailable)
        #expect(center.checkForUpdates())
        #expect(updater.manualChecks == 2)
    }

    @Test("an asynchronous updater result invalidates the Settings connection")
    func updaterResultsAreObservable() {
        let updater = SoftwareUpdaterDouble()
        let root = Self.root(updater: updater)
        defer { CompositionRootWireTests.tearDown(root) }
        let center = FocusCommandCenter()
        root.registerSoftwareUpdatePerformer(on: center)
        let changed = Mutex(false)
        withObservationTracking {
            _ = root.settingsConnection().softwareUpdates
        } onChange: {
            changed.withLock { $0 = true }
        }

        updater.lastFailure = .feedUnavailable
        updater.onStatusChange?()
        #expect(changed.withLock { $0 })
        #expect(root.settingsConnection().softwareUpdates.failure == .feedUnavailable)
    }

    /// **The settings connection carries the status and the sink, and the sink reaches the root.**
    @Test("the settings connection draws the status and its sink reaches the root")
    func theConnectionCarriesTheStatus() {
        let updater = SoftwareUpdaterDouble()
        let root = Self.root(updater: updater)
        defer { CompositionRootWireTests.tearDown(root) }
        root.joinHosts()

        let before = root.settingsConnection()
        #expect(!before.softwareUpdates.checksAutomatically)
        #expect(before.softwareUpdates.train == .stable)

        before.onSoftwareUpdateAction(.setAutomaticChecks(true))
        #expect(updater.automaticChecks == [true])
        #expect(root.settingsConnection().softwareUpdates.checksAutomatically)
    }

    /// **The choice is read back at the next launch**, in a second root over the same file, and
    /// that root asks its updater to start at once, because that is what was chosen.
    @Test("a choice made in one launch is applied by the next")
    func theChoiceSurvivesARelaunch() throws {
        let storeURL = StoredSettingRestorationTests.temporaryStoreURL()
        defer {
            for name in FocusStore.storeFileNames() {
                try? FileManager.default.removeItem(
                    at: storeURL.deletingLastPathComponent().appending(path: name)
                )
            }
        }

        let first = Self.root(updater: SoftwareUpdaterDouble(), storeKind: .temporary(storeURL))
        first.joinHosts()
        first.perform(SoftwareUpdateSettingsAction.setAutomaticChecks(true))
        CompositionRootWireTests.tearDown(first)

        // The shipping root builds its updater from the stored choice, which `SparkleUpdater`
        // turns into an immediate start. The double is handed the same fact through the status
        // the second root reads, which is what the pane draws.
        let second = Self.root(updater: SoftwareUpdaterDouble(), storeKind: .temporary(storeURL))
        defer { CompositionRootWireTests.tearDown(second) }
        second.joinHosts()
        #expect(second.softwareUpdateStatus.checksAutomatically)
    }

    static func root(
        updater: any SoftwareUpdating,
        storeKind: FocusStore.Kind = .inMemory
    ) -> AppComposition {
        AppComposition(
            dateProvider: FixedDateProvider(now: NudgeHostFixture.reference),
            monotonicClock: FixedMonotonicClock(),
            calendar: NudgeHostFixture.londonCalendar,
            locale: Locale(identifier: "en_GB"),
            hotKeyRegistrar: InertHotKeyRegistrar(),
            storeKind: storeKind,
            notificationCentre: SilentNotificationCentre(),
            loginItem: LaunchAtLoginDouble(),
            softwareUpdater: updater
        )
    }
}
