import Foundation
import Testing

@testable import FocusCore

/// Security-scoped bookmarks, against real files on this disk.
///
/// Nothing here asserts that `startAccessingSecurityScopedResource()` *granted* anything. This
/// app is not sandboxed (e01 R-04), so that call returns `true` regardless and a test reading
/// it as evidence of access would be measuring nothing at all (probe P-58). What is asserted
/// is what actually matters to the feature: a bookmark round-trips, a moved file is followed
/// and re-bookmarked, and a deleted file becomes a *missing* chip rather than a crash or a
/// silent removal.
@Suite("Security-scoped bookmarks")
struct BookmarkTests {
    /// A directory that cleans itself up, and a file inside it.
    private func makeTemporaryFile(
        named name: String = "notes.md",
        contents: String = "the one thing\n"
    ) throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "focus-bookmarks-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: name, directoryHint: .notDirectory)
        try Data(contents.utf8).write(to: file)
        return (directory, file)
    }

    @Test("create, resolve, and read the file back through the scope")
    func createResolveRead() throws {
        let (directory, file) = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bookmark = try SecurityScopedBookmark.create(for: file)
        #expect(!bookmark.isEmpty)

        let resolution = SecurityScopedBookmark.resolve(bookmark)
        let url = try #require(resolution.url, "a bookmark to an existing file must resolve")
        #expect(url.lastPathComponent == "notes.md")
        #expect(resolution.isStale == false)

        let contents = try SecurityScopedBookmark.withAccess(to: url) { scoped in
            try String(contentsOf: scoped, encoding: .utf8)
        }
        #expect(contents == "the one thing\n")
    }

    @Test("withAccess returns what its body returns, and survives a throwing body")
    func withAccessIsTransparent() throws {
        let (directory, file) = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }

        let length = SecurityScopedBookmark.withAccess(to: file) { $0.lastPathComponent.count }
        #expect(length == "notes.md".count)

        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try SecurityScopedBookmark.withAccess(to: file) { _ in throw Boom() }
        }
    }

    /// The user moved their file. They should not have to care.
    @Test("a moved file resolves stale, follows the move, and can be re-bookmarked")
    func movedFileResolvesStaleAndIsReBookmarked() throws {
        let (directory, file) = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bookmark = try SecurityScopedBookmark.create(for: file)

        let renamed = directory.appending(path: "renamed.md", directoryHint: .notDirectory)
        try FileManager.default.moveItem(at: file, to: renamed)

        let resolution = SecurityScopedBookmark.resolve(bookmark)
        let url = try #require(resolution.url, "a renamed file must still resolve")
        #expect(url.lastPathComponent == "renamed.md", "the bookmark did not follow the rename")
        #expect(resolution.isStale, "a followed rename must report the bookmark as stale")

        // Silently re-created, and the replacement is no longer stale.
        let refreshed = try SecurityScopedBookmark.create(for: url)
        #expect(SecurityScopedBookmark.resolve(refreshed).isStale == false)

        let contents = try SecurityScopedBookmark.withAccess(to: url) { scoped in
            try String(contentsOf: scoped, encoding: .utf8)
        }
        #expect(contents == "the one thing\n")
    }

    /// The user unplugged a disk, or emptied the trash. Deleting their context for them would
    /// be a bug, not tidiness.
    @Test("a deleted file resolves as missing — never a crash, never an auto-removal")
    func deletedFileIsMissing() throws {
        let (directory, file) = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bookmark = try SecurityScopedBookmark.create(for: file)
        let item = ContextItemValue.file(
            url: file,
            bookmark: bookmark,
            addedAt: FixedDateProvider.reference.now
        )

        try FileManager.default.removeItem(at: file)

        let resolution = SecurityScopedBookmark.resolve(bookmark)
        #expect(resolution.isMissing)
        #expect(resolution.url == nil)

        // The item itself is untouched: only its *availability* changes, and the surface
        // renders a missing chip with a Locate… action.
        var stillHeld = item
        stillHeld.availability = .missing
        #expect(stillHeld.id == item.id)
        #expect(stillHeld.value == item.value)
        #expect(stillHeld.displayName == "notes.md")
        #expect(stillHeld.bookmark == bookmark)
        #expect(stillHeld.availability == .missing)
    }

    @Test("withResolvedAccess reports nothing for a bookmark whose file is gone")
    func withResolvedAccessOnAMissingFile() throws {
        let (directory, file) = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bookmark = try SecurityScopedBookmark.create(for: file)
        try FileManager.default.removeItem(at: file)

        let outcome = SecurityScopedBookmark.withResolvedAccess(bookmark) { $0.lastPathComponent }
        #expect(outcome == nil)
    }

    @Test("withResolvedAccess hands back a refreshed bookmark when the old one went stale")
    func withResolvedAccessRefreshesAStaleBookmark() throws {
        let (directory, file) = try makeTemporaryFile()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bookmark = try SecurityScopedBookmark.create(for: file)
        let renamed = directory.appending(path: "moved.md", directoryHint: .notDirectory)
        try FileManager.default.moveItem(at: file, to: renamed)

        let outcome = try #require(
            SecurityScopedBookmark.withResolvedAccess(bookmark) { $0.lastPathComponent }
        )
        #expect(outcome.result == "moved.md")
        let refreshed = try #require(outcome.refreshed, "a stale bookmark must be re-created")
        #expect(SecurityScopedBookmark.resolve(refreshed).isStale == false)
    }

    @Test("garbage is a failure, not a crash and not a missing file")
    func garbageBookmarkDataFails() {
        let resolution = SecurityScopedBookmark.resolve(Data([0xDE, 0xAD, 0xBE, 0xEF]))
        switch resolution {
        case .failed:
            break  // the expected shape
        case .missing:
            Issue.record("corrupt bookmark data reported a missing file, which it is not")
        case .resolved:
            Issue.record("corrupt bookmark data resolved to a URL")
        }
    }
}
