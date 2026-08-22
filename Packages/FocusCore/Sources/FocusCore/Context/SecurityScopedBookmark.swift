import Foundation

/// The one place in the programme that creates, resolves and opens a security-scoped
/// bookmark.
///
/// `scripts/check-forbidden.sh` fails the gate on any call to
/// `startAccessingSecurityScopedResource()` or `stopAccessingSecurityScopedResource()` outside
/// this file. That is not ceremony: an unbalanced pair leaks a scope for the life of the
/// process, and the only reliable way to keep them balanced is to have exactly one place where
/// they appear at all — `withAccess(to:perform:)`, where the `defer` is written once.
///
/// ## What was measured, and what it does not prove
///
/// This app is **not** sandboxed (e01 R-04, `app-sandbox = false`, ad-hoc signed). Probe P-58
/// measured that `.withSecurityScope` bookmarks are created and resolved correctly anyway,
/// that a renamed file resolves stale and follows the rename, and that a deleted file makes
/// resolution throw. The scoped form is chosen over the plain one because it is the form that
/// keeps working if the app is ever sandboxed, and it costs nothing here.
///
/// **`startAccessingSecurityScopedResource()` returning `true` in a non-sandboxed app proves
/// nothing about entitlements**, so no test may read it as evidence that access was granted.
public enum SecurityScopedBookmark {
    /// What resolving a stored bookmark produced.
    public enum Resolution {
        /// The file was found. `isStale` means it moved and the bookmark should be re-created.
        case resolved(URL, isStale: Bool)
        /// The file is gone — unplugged, deleted, or on a volume that is not mounted.
        ///
        /// The item is **never** removed automatically for this. Deleting a person's context
        /// because a disk was unplugged is a bug, not tidiness: the chip renders as *missing*
        /// with a Locate… action and waits.
        case missing
        /// Something else went wrong, carried verbatim so the surface can say what.
        case failed(any Error)

        public var url: URL? {
            if case .resolved(let url, _) = self { return url }
            return nil
        }

        public var isMissing: Bool {
            if case .missing = self { return true }
            return false
        }

        public var isStale: Bool {
            if case .resolved(_, let stale) = self { return stale }
            return false
        }
    }

    /// Create a security-scoped bookmark for a file the user chose, dropped or pasted.
    public static func create(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolve a stored bookmark.
    ///
    /// Never throws: a missing file is an ordinary state of the world, not an exceptional one,
    /// and a caller that has to `try?` its way past it will end up treating every failure the
    /// same way.
    public static func resolve(_ data: Data) -> Resolution {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            // A bookmark can resolve to a path that no longer holds a file. Reporting that as
            // "resolved" would put a chip on screen that opens nothing.
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                return .missing
            }
            return .resolved(url, isStale: isStale)
        } catch let error as CocoaError where error.isFileNotFound {
            return .missing
        } catch {
            return .failed(error)
        }
    }

    /// Run `perform` with the security scope open, and close it afterwards — always.
    ///
    /// The `defer` is the whole point of this function existing. `stop` is called only when
    /// `start` actually returned `true`, which is what the platform asks for.
    public static func withAccess<T>(to url: URL, perform: (URL) throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        return try perform(url)
    }

    /// Resolve, open the scope, and hand the caller the file — the shape almost every caller
    /// actually wants.
    ///
    /// A stale bookmark is silently re-created and handed back through `refreshed`, because a
    /// user who moved a file should not have to care that they did.
    public static func withResolvedAccess<T>(
        _ data: Data,
        perform: (URL) throws -> T
    ) rethrows -> (result: T, refreshed: Data?)? {
        guard case .resolved(let url, let isStale) = resolve(data) else { return nil }
        let result = try withAccess(to: url) { try perform($0) }
        let refreshed = isStale ? try? create(for: url) : nil
        return (result, refreshed)
    }
}

extension CocoaError {
    /// The two Cocoa codes that mean "there is no file there".
    var isFileNotFound: Bool {
        code == .fileNoSuchFile || code == .fileReadNoSuchFile
    }
}
