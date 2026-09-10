import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// **Delete everything leaves no byte behind** (e07a, focus-6pr.3, e07 S4).
///
/// The store runs SwiftData's defaults — WAL journaling, `secure_delete` off, no auto-vacuum —
/// so a logical delete leaves a person's sentences on the freelist and in the write-ahead log.
/// This is the byte scan the review asked for, made deterministic the way it asked: sentinels
/// written through the **real** write paths, asserted present in `-wal` **while the connection
/// is open** (the non-vacuity control — a scan that never saw the bytes proves nothing), and then
/// absent from every byte of every file in the directory once `FocusStore.deleteEverything` has
/// released, removed and rebuilt.
///
/// Red before this round: `FocusStore.deleteEverything` did not exist, and no path in the
/// application removed the three files.
@Suite("Delete everything")
@MainActor
struct DeleteEverythingWitnessTests {
    static let intentSentinel = "SENTINEL-INTENT-5f0e3c9b7a"
    static let contextSentinel = "SENTINEL-CONTEXT-2d8b41ce6f"
    static let ruleSentinel = "com.sentinel.rule.9a1c7d3e"

    @Test("sentinels written through the real paths are in the write-ahead log while the store is open, and nowhere after")
    func noByteSurvives() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "focus-delete-everything-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "FocusSentinel.store", directoryHint: .notDirectory)
        let kind = FocusStore.Kind.temporary(url)

        var container: ModelContainer? = try FocusStore.makeContainer(kind: kind)
        let context = try #require(container).mainContext
        let priorities = PriorityStore(context: context, dateProvider: FixedDates())
        let taskID = try priorities.setPriority(intent: Self.intentSentinel)
        _ = try priorities.addContextItem(
            taskID: taskID, kindRaw: "keyword", value: Self.contextSentinel, displayName: Self.contextSentinel
        )
        _ = try priorities.addRule(
            taskID: taskID, scopeRaw: "app", subject: Self.ruleSentinel, verdictRaw: "relevant"
        )

        // The non-vacuity control: with the connection still open, the sentinel is in the WAL.
        // A test that only scanned after deleting could pass over a checkpoint that happened to
        // land first, which is the nondeterminism the review named.
        let walURL = URL(filePath: url.path + "-wal")
        let wal = try Data(contentsOf: walURL)
        #expect(Self.contains(wal, Self.intentSentinel), "the intent never reached -wal, so the scan below would prove nothing")
        #expect(Self.bytesInDirectory(directory).contains { Self.contains($0.data, Self.contextSentinel) })
        #expect(Self.bytesInDirectory(directory).contains { Self.contains($0.data, Self.ruleSentinel) })

        // Release, remove, rebuild.
        let rebuilt = try FocusStore.deleteEverything(try #require(container), kind: kind)
        container = nil

        // The rebuilt store is a store, and an empty one.
        let after = PriorityStore(context: rebuilt.mainContext, dateProvider: FixedDates())
        #expect(try after.activeTask() == nil)
        #expect(try after.recentTasks().isEmpty)

        // And every byte of the directory — the database, its sidecars, anything else — is
        // clean of all three sentinels.
        for file in Self.bytesInDirectory(directory) {
            for sentinel in [Self.intentSentinel, Self.contextSentinel, Self.ruleSentinel] {
                #expect(
                    !Self.contains(file.data, sentinel),
                    "\(sentinel) survived in \(file.name) after delete everything"
                )
            }
        }
        #expect(FileManager.default.fileExists(atPath: url.path), "the rebuilt store is not on disk")
    }

    /// The three URLs a temporary kind owns are the file and its two sidecars, by the caller's
    /// own name — not `FocusSentinel.store-wal` beside `keyboard.store`.
    @Test("the files a store owns are named from the kind's own URL")
    func storeFilesFollowTheKind() {
        let url = URL(filePath: "/tmp/anywhere/keyboard.store")
        #expect(
            FocusStore.storeFileURLs(for: .temporary(url)).map(\.lastPathComponent)
                == ["keyboard.store", "keyboard.store-wal", "keyboard.store-shm"]
        )
        #expect(FocusStore.storeFileURLs(for: .inMemory).isEmpty)
        #expect(
            FocusStore.storeFileURLs(for: .applicationSupport).map(\.lastPathComponent)
                == FocusStore.storeFileNames()
        )
    }

    static func contains(_ data: Data, _ sentinel: String) -> Bool {
        data.range(of: Data(sentinel.utf8)) != nil
    }

    static func bytesInDirectory(_ directory: URL) -> [(name: String, data: Data)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            let url = directory.appending(path: name, directoryHint: .notDirectory)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return (name, data)
        }
    }

    struct FixedDates: DateProvider {
        var now: Date { Date(timeIntervalSince1970: 1_767_225_600) }
    }
}
