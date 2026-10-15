import FocusCore
import FocusUI
import Foundation
import SwiftData
import Testing

@testable import FocusHost

/// A model no Focus schema has ever declared, so a store written with it is one whose model
/// version Focus's migration plan does not know — the shape of the 134504 failure design QA hit
/// ("Cannot use staged migration with an unknown model version").
@Model
final class StrangerRecord {
    var name: String
    init(name: String) { self.name = name }
}

/// The stranger's own one-version plan, so its container is built through a migration plan
/// like every other container in the repository (R-05).
enum StrangerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(99, 0, 0) }
    static var models: [any PersistentModel.Type] { [StrangerRecord.self] }
}

enum StrangerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [StrangerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// **Seed isolation and the active persistence mode** (focus-k2in, GitHub #4).
///
/// Three defects, one cause: the store a launch was *given* and the store the person's data
/// lives in were the same answer by default.
///
/// - A `--focus-session-seed` or `--focus-session-restore` launch without `--focus-self-check`
///   opened the person's Application Support store in the composition root before the mode ran.
/// - The root kept the *requested* kind after falling back to memory, so delete-everything
///   removed the very file that had just refused to open.
/// - The Privacy pane named `FocusStore.applicationSupportURL` whatever the root had opened.
///
/// Every fixture here is owned by the test: a fresh directory under the process's temporary
/// directory, removed afterwards. Nothing reads or writes the person's store.
@Suite("Store isolation and the active persistence mode", .serialized)
@MainActor
struct StoreIsolationTests {
    // MARK: - Which store a launch selects

    @Test("a seed or restore launch never opens the person's store, with or without a self-check")
    func seedAndRestoreAreIsolated() {
        for mode in [SelfCheck.seedArgument, SelfCheck.restoreArgument] {
            let bare = ["FocusSentinel", mode, "/owned/fixture.store"]
            #expect(SelfCheck.storeKind(arguments: bare) == .inMemory, "\(mode) alone")
            #expect(
                SelfCheck.storeKind(arguments: bare + [SelfCheck.liveStoreArgument]) == .inMemory,
                "\(mode) beside the live-store reader"
            )
            #expect(
                SelfCheck.storeKind(arguments: bare + [SelfCheck.argument, "/owned/report.json"])
                    == .inMemory,
                "\(mode) under a self-check"
            )
        }
    }

    @Test("an explicit --focus-store outranks seed, restore and the live-store reader")
    func explicitStoreWins() {
        let fixture = URL(fileURLWithPath: "/owned/preview.store")
        for mode in [SelfCheck.seedArgument, SelfCheck.restoreArgument, SelfCheck.liveStoreArgument] {
            let arguments = ["FocusSentinel", mode, "/owned/fixture.store",
                             SelfCheck.storeArgument, fixture.path]
            #expect(SelfCheck.storeKind(arguments: arguments) == .temporary(fixture), "\(mode)")
        }
    }

    @Test("an ordinary launch still opens the person's store")
    func ordinaryLaunchIsUnchanged() {
        #expect(SelfCheck.storeKind(arguments: ["FocusSentinel"]) == .applicationSupport)
        #expect(
            SelfCheck.storeKind(arguments: ["FocusSentinel", SelfCheck.argument, "/owned/r.json"])
                == .inMemory
        )
    }

    // MARK: - What the root reports about the store it has

    @Test("a store that opened is the one Privacy, Reveal and export name")
    func openedFixtureIsReported() throws {
        let directory = try Self.ownedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "preview.store")

        let root = CompositionRootTests.root(storeKind: .temporary(url))
        #expect(root.storeStatus.isReady)
        #expect(root.storeKind == .temporary(url))
        #expect(root.requestedStoreKind == .temporary(url))
        #expect(root.activeStoreURL == url)
        #expect(root.settingsConnection().storeURL == url)
        #expect(root.exportDirectoryURL == directory)
        #expect(root.priorityHost.state.storeLocation == url.path(percentEncoded: false))
    }

    @Test("a memory-only root names no file anywhere")
    func memoryOnlyRootNamesNoFile() {
        let root = CompositionRootTests.root(storeKind: .inMemory)
        #expect(root.activeStoreURL == nil)
        #expect(root.settingsConnection().storeURL == nil)
        #expect(root.exportDirectoryURL == nil)
        #expect(PrivacySettingsView.renderedStorePath(nil) == PrivacySettingsView.memoryOnlyStorePath)
        #expect(
            PrivacySettingsView.renderedStorePath(URL(fileURLWithPath: "/owned/a.store"))
                == "/owned/a.store"
        )
    }

    /// The case design QA hit, on an owned copy: a store written by a model Focus does not know.
    /// The root must fall back to memory, **say so**, name the file it could not open on the
    /// sheet, and never treat that file as its own — delete-everything included.
    @Test("an unknown-model store falls back to memory, is reported honestly and is left intact")
    func unknownModelFallsBackWithoutTouchingTheStore() throws {
        let directory = try Self.ownedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "unknown.store")
        try Self.writeStrangerStore(at: url)

        let root = CompositionRootTests.root(storeKind: .temporary(url))
        // Taken after the failed open rather than before it: SQLite may fold the fixture's own
        // write-ahead log into the main file on the way, which moves bytes and loses nothing.
        // That nothing was lost is the read-back at the end.
        let afterOpen = try Self.snapshot(of: url)
        #expect(!afterOpen.isEmpty)
        #expect(!root.storeStatus.isReady, "an unknown model version opened as though it were Focus's")
        #expect(root.requestedStoreKind == .temporary(url))
        #expect(root.storeKind == .inMemory, "the root kept the kind it was asked for, not the one it has")
        #expect(root.activeStoreURL == nil)
        #expect(root.settingsConnection().storeURL == nil)
        #expect(root.exportDirectoryURL == nil)
        // The unavailable-store sheet names the file the person should go and look at.
        #expect(root.priorityHost.state.storeLocation == url.path(percentEncoded: false))
        #expect(!root.priorityHost.state.storeOpened)

        // Delete-everything in this session is about this session's memory, never the file.
        root.relaunch = {}
        root.perform(.deleteEverything)
        #expect(root.hasDeletedEverything)
        #expect(
            try Self.snapshot(of: url) == afterOpen,
            "a memory-only session changed the store on disk"
        )
        // And the store is still the one it was: its own model reads its own row back.
        #expect(try Self.strangerNames(at: url) == ["owned fixture"])
    }

    // MARK: - Fixtures

    static func ownedDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "focus-store-isolation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A real SwiftData store on disk whose only model is `StrangerRecord`, closed before return.
    static func writeStrangerStore(at url: URL) throws {
        let schema = Schema(versionedSchema: StrangerSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        // In a pool of its own, so the container and its connection are gone on return.
        try autoreleasepool {
            let plan = StrangerMigrationPlan.self
            let container = try ModelContainer(for: schema, migrationPlan: plan, configurations: configuration)
            let context = ModelContext(container)
            context.insert(StrangerRecord(name: "owned fixture"))
            try context.save()
        }
    }

    /// The rows a stranger store holds, read through its own plan.
    static func strangerNames(at url: URL) throws -> [String] {
        let schema = Schema(versionedSchema: StrangerSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        let plan = StrangerMigrationPlan.self
        let container = try ModelContainer(for: schema, migrationPlan: plan, configurations: configuration)
        return try ModelContext(container).fetch(FetchDescriptor<StrangerRecord>()).map(\.name)
    }

    /// The bytes of the store and its write-ahead log, keyed by file name; a missing file is
    /// absent. The `-shm` sidecar is left out on purpose: it is SQLite's shared-memory index,
    /// rewritten by any connection that so much as reads the file, and holds no data.
    static func snapshot(of url: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for file in FocusStore.storeFileURLs(for: .temporary(url))
        where !file.lastPathComponent.hasSuffix("-shm")
            && FileManager.default.fileExists(atPath: file.path) {
            files[file.lastPathComponent] = try Data(contentsOf: file)
        }
        return files
    }
}
