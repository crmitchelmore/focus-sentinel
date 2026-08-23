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
    /// v3 since e03. A store written by v1 is brought forward by `FocusMigrationPlan`'s two
    /// stages — the custom v1 → v2 one and the lightweight v2 → v3 one — on the way in, and a
    /// v2 store by the second alone. This is the only place the current version is named, so
    /// every caller gets the whole chain for free.
    public static var schema: Schema {
        Schema(versionedSchema: FocusSchemaV3.self)
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

    /// The file names that together make up a store: the database and its two sidecars.
    ///
    /// Copying a SwiftData store means copying all three. A fixture that ships only the
    /// `.store` file will open, and will be missing whatever was still in the write-ahead
    /// log — which is a silent, intermittent, extremely annoying way to lose test data.
    public static func storeFileNames(for storeName: String = storeFileName) -> [String] {
        [storeName, "\(storeName)-wal", "\(storeName)-shm"]
    }
}
