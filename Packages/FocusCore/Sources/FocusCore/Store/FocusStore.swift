import Foundation
import SwiftData

/// The one place a `ModelContainer` is ever constructed.
///
/// Every path goes through `makeContainer(kind:)`, and `makeContainer(kind:)` always calls
/// `ModelContainer(for:migrationPlan:configurations:)`. The plan-less initialiser is
/// forbidden repo-wide and the gate fails on it, so no later epic can open the store by a
/// route that skips migration.
public enum FocusStore {
    /// Where a container's data lives.
    public enum Kind: Sendable, Equatable {
        /// Nothing is written to disk. The default for unit tests.
        case inMemory
        /// A store at a caller-chosen URL, normally in a temporary directory. Used by the
        /// fixture tests, which copy the committed v1 store somewhere writable and open the
        /// copy.
        case temporary(URL)
        /// The real store, in the app's Application Support container.
        case applicationSupport
    }

    /// The bundle identifier the store directory is named for. It is stable for the whole
    /// programme: TCC state in later epics keys on it, so it must not change after e01.
    public static let bundleIdentifier = "com.chrismitchelmore.FocusSentinel"

    /// The store file's name. The `-wal` and `-shm` sidecars sit beside it.
    public static let storeFileName = "FocusSentinel.store"

    /// `~/Library/Application Support/com.chrismitchelmore.FocusSentinel`.
    public static var applicationSupportDirectoryURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL.homeDirectory.appending(path: "Library/Application Support")
        return base.appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }

    /// The full path of the live store file. This is what the Privacy settings tab reveals
    /// in the Finder, so the user can see for themselves that their data is one local file.
    public static var applicationSupportURL: URL {
        applicationSupportDirectoryURL.appending(path: storeFileName, directoryHint: .notDirectory)
    }

    /// The schema this build understands.
    ///
    /// v6 since the shell got three facts to remember about itself between launches
    /// (focus-odz.4, focus-odz.6, focus-odz.7). A store written by v1 is brought forward by
    /// `FocusMigrationPlan`'s five stages — the custom v1 → v2 and v5 → v6 ones and the
    /// lightweight three between them — on the way in, and a v5 store by the last alone. This is
    /// the only place the current version is named, so every caller gets the whole chain for free.
    ///
    /// v6 re-declares none of v5's classes (`FocusSchemaV6.models` names them), so every
    /// existing call site keeps fetching the entities it already knew and the version bump
    /// costs the rest of the programme nothing.
    public static var schema: Schema {
        Schema(versionedSchema: FocusSchemaV10.self)
    }

    /// Build a container for the given kind of storage.
    ///
    /// - Throws: whatever SwiftData throws when a store cannot be opened or migrated, and
    ///   any file-system error raised while creating the Application Support directory.
    public static func makeContainer(kind: Kind) throws -> ModelContainer {
        let schema = self.schema
        let configuration: ModelConfiguration

        switch kind {
        case .inMemory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        case .temporary(let url):
            configuration = ModelConfiguration(schema: schema, url: url)

        case .applicationSupport:
            try FileManager.default.createDirectory(
                at: applicationSupportDirectoryURL,
                withIntermediateDirectories: true
            )
            configuration = ModelConfiguration(schema: schema, url: applicationSupportURL)
        }

        return try ModelContainer(for: schema, migrationPlan: FocusMigrationPlan.self, configurations: configuration)
    }

    /// **Every file a store of this kind puts on disk**, or nothing for an in-memory one.
    ///
    /// The database and its two sidecars, resolved against the kind's own URL rather than
    /// against `storeFileName`: a `--focus-store` path is whatever the caller named it, and a
    /// deletion that looked for `FocusSentinel.store-wal` beside `keyboard.store` would leave
    /// the write-ahead log — the file the plaintext is most likely still in — exactly where it
    /// was.
    public static func storeFileURLs(for kind: Kind) -> [URL] {
        let store: URL
        switch kind {
        case .inMemory: return []
        case .temporary(let url): store = url
        case .applicationSupport: store = applicationSupportURL
        }
        return [store, URL(filePath: store.path + "-wal"), URL(filePath: store.path + "-shm")]
    }

    /// **Delete everything, and come back with a store that never held it** (e07a,
    /// focus-6pr.3, e07 S4).
    ///
    /// The store runs SwiftData's defaults — `journal_mode=WAL`, `secure_delete=OFF`,
    /// `auto_vacuum=NONE` — and `ModelConfiguration` exposes no pragma hook, so a logical delete
    /// leaves a person's sentences on the freelist of the main file and in the write-ahead log.
    /// A promise to forget that leaves the bytes on disk is not one. So this is three things in
    /// an order that is load-bearing:
    ///
    /// 1. **Release.** `deleteAllData()` closes the persistent store and destroys it through the
    ///    coordinator — the one door SwiftData offers for giving up the file descriptors. A file
    ///    unlinked under a live connection is a file SQLite goes on writing through, and
    ///    recreates at the next checkpoint (the review's ordering finding).
    /// 2. **Remove.** All three files, by the kind's own URLs, in case the destroy left a
    ///    sidecar behind.
    /// 3. **Rebuild.** A fresh container at the same URL, through the same migration plan every
    ///    container goes through, so the caller is handed a store and not a hole.
    ///
    /// The witness is `DeleteEverythingWitnessTests`: sentinels written through the real write
    /// paths, asserted **present in `-wal` while the connection is open** — the deterministic
    /// non-vacuity control — and then absent from every byte of the directory afterwards.
    ///
    /// Every `ModelContext` built on the old container is dead after this returns; the caller
    /// is responsible for reaching none of them again. The composition root relaunches the
    /// application for exactly that reason.
    public static func deleteEverything(
        _ container: ModelContainer,
        kind: Kind
    ) throws -> ModelContainer {
        container.deleteAllData()
        for url in storeFileURLs(for: kind) where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return try makeContainer(kind: kind)
    }

    /// The file names that together make up a store: the database and its two sidecars.
    ///
    /// Copying a SwiftData store means copying all three. A fixture that ships only the
    /// `.store` file will open, and will be missing whatever was still in the write-ahead
    /// log — which is a silent, intermittent, extremely annoying way to lose test data.
    public static func storeFileNames(for storeName: String = storeFileName) -> [String] {
        [storeName, "\(storeName)-wal", "\(storeName)-shm"]
    }
}
