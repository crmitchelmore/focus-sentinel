import Darwin
import FocusCore
import Foundation

/// Writes the full export to a file the caller names.
///
/// The export carries the activity log, so the file is `0600` from the moment it exists, like the
/// rest of the bridge's data. A caller (often an agent) names the path, so an existing file is
/// replaced only when it is itself a `focus-sentinel.data` export; anything else is refused rather
/// than overwritten.
public enum ExportFile {
    public static func write(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try refuseUnlessReplaceable(url)

        let directory = url.deletingLastPathComponent().path
        var template = Array("\(directory)/.\(url.lastPathComponent).XXXXXX".utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw BridgeError("cannot create a file in \(directory): \(String(cString: strerror(errno)))") }
        let temporary = String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        var renamed = false
        defer {
            close(fd)
            if !renamed { unlink(temporary) }
        }
        guard fchmod(fd, 0o600) == 0 else { throw BridgeError("cannot set permissions on \(temporary)") }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
        guard fsync(fd) == 0 else { throw BridgeError("cannot flush \(temporary)") }
        guard rename(temporary, path) == 0 else {
            throw BridgeError("cannot write \(path): \(String(cString: strerror(errno)))")
        }
        renamed = true
    }

    private static func refuseUnlessReplaceable(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFREG,
              let existing = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: existing) as? [String: Any],
              let manifest = object["manifest"] as? [String: Any],
              manifest["format"] as? String == StoreExport.formatName
        else {
            throw BridgeError("\(url.path) already exists and is not a focus-sentinel export; choose a new path")
        }
    }
}
