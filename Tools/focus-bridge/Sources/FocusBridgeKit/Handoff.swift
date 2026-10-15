import FocusCore
import Foundation

/// **Propose a priority or its context, and leave the decision with the person.**
///
/// Builds the same `focus://start?task=…&doneWhen=…&context=…` and `focus://context?add=…` URLs
/// the cockpit's handoff accepts, checks them with the app's own parser before anything is
/// opened, and hands them to Launch Services. The app shows a confirmation sheet and changes
/// nothing until the person presses Replace or Add, so an agent can suggest but cannot set.
///
/// Context items are `kind:value` strings: `app:<bundle id>`, `domain:<host or origin>`,
/// `keyword:<text>`. Files are not accepted: a path from a script is not a file the person chose.
public enum Handoff {
    /// RFC 3986 unreserved characters only, so `&`, `=`, `+` and `#` in a title survive the trip.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func url(
        task: String,
        doneWhen: String?,
        context: [String] = [],
        scheme: String = HandoffRequest.scheme
    ) throws -> URL {
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { throw BridgeError("task is empty") }
        let doneWhen = doneWhen?.trimmingCharacters(in: .whitespacesAndNewlines)
        for (name, value) in [("task", task), ("doneWhen", doneWhen ?? "")]
        where value.count > HandoffRequest.maximumFieldLength {
            throw BridgeError("\(name) is longer than \(HandoffRequest.maximumFieldLength) characters")
        }
        var pairs = [("task", task)]
        if let doneWhen, !doneWhen.isEmpty { pairs.append(("doneWhen", doneWhen)) }
        pairs += try checked(context).map { ("context", $0) }
        return try build(scheme: scheme, verb: .start, pairs: pairs)
    }

    /// `focus://context?add=…`: add items to the **current** priority. The app drops it when
    /// there is no current priority, and skips items the priority already holds.
    public static func contextURL(items: [String], scheme: String = HandoffRequest.scheme) throws -> URL {
        let items = try checked(items)
        guard !items.isEmpty else { throw BridgeError("no context items to add") }
        return try build(scheme: scheme, verb: .context, pairs: items.map { ("add", $0) })
    }

    /// Every item must survive the app's parser as given, and there must be no more than it
    /// keeps: an item the app would silently leave out is an error here, named.
    static func checked(_ items: [String]) throws -> [String] {
        var seen = Set<HandoffContextItem>()
        var kept: [String] = []
        for raw in items {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let item = HandoffContextItem.parse(text) else {
                throw BridgeError(
                    "'\(raw)' is not a context item Focus Sentinel accepts; "
                        + "use app:<bundle id>, domain:<host> or keyword:<text>"
                )
            }
            if seen.insert(item).inserted { kept.append(text) }
        }
        guard kept.count <= HandoffRequest.maximumContextItems else {
            throw BridgeError("at most \(HandoffRequest.maximumContextItems) context items per handoff")
        }
        return kept
    }

    private static func build(scheme: String, verb: HandoffVerb, pairs: [(String, String)]) throws -> URL {
        let query = pairs
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")
        guard let url = URL(string: "\(scheme)://\(verb.rawValue)?\(query)") else {
            throw BridgeError("could not build a \(scheme):// URL")
        }
        switch HandoffRequest.parse(url) {
        case .rejected(let rejection):
            throw BridgeError("Focus Sentinel would refuse this handoff: \(rejection)")
        case .confirm(let request) where !request.flags.isEmpty:
            throw BridgeError("Focus Sentinel would alter this handoff: \(request.flags)")
        case .confirm:
            return url
        }
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
