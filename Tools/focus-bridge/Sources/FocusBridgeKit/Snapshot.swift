import FocusCore
import Foundation
import SQLite3
import SwiftData

public struct BridgeError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// **A private, consistent copy of the person's store, and what it says.**
///
/// The running app holds the live store open in WAL mode. Opening that file with SwiftData from a
/// second process would run the migration plan against it and could write; copying the three
/// files by hand could tear a write. SQLite's online backup API does neither: it reads the live
/// database through an ordinary read-only connection and restarts by itself if the app writes
/// part-way through. The copy goes in a directory only this user can read, is opened by
/// `FocusStore.makeContainer`, the same and only route the app uses, and is deleted before this returns.
public struct StoreReading: Sendable {
    public let document: StoreExport.Document
    /// The priority the app's `ActivePriority` pointer names. The export carries every priority
    /// but not the pointer, so it is read alongside.
    public let activePriorityID: String?
    /// The standing priorities' task ids, main first. Also not in the export.
    public var standingPriorityIDs: [String] = []
}

public enum Snapshot {
    /// The store the installed Stable app writes, unless `FOCUS_STORE` names another.
    public static func defaultStoreURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["FOCUS_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FocusStore.applicationSupportURL
    }

    @MainActor
    public static func read(store: URL, now: Date = Date()) throws -> StoreReading {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "focus-bridge-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let copy = directory.appending(path: "snapshot.store", directoryHint: .notDirectory)
        try backup(from: store, to: copy)
        let container = try FocusStore.makeContainer(kind: .temporary(copy))
        let context = container.mainContext
        let document = try StoreExport.document(in: context, generatedAt: now)
        let store = PriorityStore(context: context)
        let active = try store.activeTask()?.id.uuidString
        let standing = try store.standingPriorities().map { $0.task.id.uuidString }
        return StoreReading(document: document, activePriorityID: active, standingPriorityIDs: standing)
    }

    /// Copy `source` to `destination` with `sqlite3_backup_*`, opening the source read-only.
    public static func backup(from source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw BridgeError("no Focus Sentinel store at \(source.path); has the app been run?")
        }
        var src: OpaquePointer?
        var dst: OpaquePointer?
        defer {
            sqlite3_close(src)
            sqlite3_close(dst)
        }
        guard sqlite3_open_v2(source.path, &src, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw BridgeError("could not open the store read-only: \(message(src))")
        }
        sqlite3_busy_timeout(src, 5_000)
        guard sqlite3_open_v2(destination.path, &dst, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw BridgeError("could not create the snapshot: \(message(dst))")
        }
        guard let backup = sqlite3_backup_init(dst, "main", src, "main") else {
            throw BridgeError("could not start the snapshot: \(message(dst))")
        }
        var rc = sqlite3_backup_step(backup, -1)
        var attempts = 0
        while rc == SQLITE_BUSY || rc == SQLITE_LOCKED || rc == SQLITE_OK, attempts < 100 {
            attempts += 1
            sqlite3_sleep(50)
            rc = sqlite3_backup_step(backup, -1)
        }
        sqlite3_backup_finish(backup)
        guard rc == SQLITE_DONE else {
            throw BridgeError("the snapshot did not complete (sqlite \(rc)): \(message(dst))")
        }
    }

    private static func message(_ db: OpaquePointer?) -> String {
        db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
    }
}
