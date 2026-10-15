import FocusCore
import Foundation

/// **Propose a priority, and leave the decision with the person.**
///
/// Builds the same `focus://start?task=…&doneWhen=…` URL the cockpit's handoff accepts, checks it
/// with the app's own parser before anything is opened, and hands it to Launch Services. The
/// app shows a confirmation sheet and changes nothing until the person presses Replace, so an
/// agent calling this can suggest a priority but cannot set one.
public enum Handoff {
    /// RFC 3986 unreserved characters only, so `&`, `=`, `+` and `#` in a title survive the trip.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func url(task: String, doneWhen: String?, scheme: String = HandoffRequest.scheme) throws -> URL {
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { throw BridgeError("task is empty") }
        let doneWhen = doneWhen?.trimmingCharacters(in: .whitespacesAndNewlines)
        for (name, value) in [("task", task), ("doneWhen", doneWhen ?? "")]
        where value.count > HandoffRequest.maximumFieldLength {
            throw BridgeError("\(name) is longer than \(HandoffRequest.maximumFieldLength) characters")
        }
        var pairs = [("task", task)]
        if let doneWhen, !doneWhen.isEmpty { pairs.append(("doneWhen", doneWhen)) }
        let query = pairs
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")
        guard let url = URL(string: "\(scheme)://start?\(query)") else {
            throw BridgeError("could not build a \(scheme):// URL")
        }
        if let rejection = HandoffRequest.parse(url).rejection {
            throw BridgeError("Focus Sentinel would refuse this handoff: \(rejection)")
        }
        return url
    }

    /// Open the URL with `/usr/bin/open`. Throws if no app has claimed the scheme.
    public static func open(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw BridgeError("could not open \(url.scheme ?? "focus"):// (is Focus Sentinel installed?) \(detail)")
        }
    }
}
