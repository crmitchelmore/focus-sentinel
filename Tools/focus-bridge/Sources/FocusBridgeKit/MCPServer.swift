import FocusCore
import Foundation

/// **A Model Context Protocol server over stdio.**
///
/// One JSON-RPC 2.0 message per line in, one per line out, nothing else on stdout. No socket is
/// opened: the client starts this process and owns both ends of the pipe. Four tools, three of
/// which only read a snapshot; the fourth proposes a priority the person still has to accept.
@MainActor
public final class MCPServer {
    public typealias Reader = @MainActor () throws -> StoreReading

    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let serverVersion = "0.1.0"

    private let read: Reader
    private let now: () -> Date
    private let openURL: (URL) throws -> Void

    public init(
        read: @escaping Reader,
        now: @escaping () -> Date = Date.init,
        openURL: @escaping (URL) throws -> Void = Handoff.open
    ) {
        self.read = read
        self.now = now
        self.openURL = openURL
    }

    /// Serve until stdin closes.
    public func run() {
        while let line = readLine(strippingNewline: true) {
            guard let reply = handle(line) else { continue }
            FileHandle.standardOutput.write(Data((reply + "\n").utf8))
        }
    }

    /// Answer one line. `nil` for a notification, which gets no reply.
    public func handle(_ line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
        }
        guard let method = message["method"] as? String else {
            return nil // a response to something we never asked; ignore it
        }
        let id = message["id"]
        guard id != nil else { return nil } // notification: initialized, cancelled, …
        let params = message["params"] as? [String: Any] ?? [:]

        let result: [String: Any]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            result = [
                "protocolVersion": Self.supportedProtocolVersions.contains(requested)
                    ? requested : Self.supportedProtocolVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "focus-sentinel", "version": Self.serverVersion],
                "instructions": Self.instructions
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": Self.tools]
        case "tools/call":
            guard let name = params["name"] as? String else {
                return error(id, code: -32602, "tools/call needs a tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard Self.tools.contains(where: { $0["name"] as? String == name }) else {
                return error(id, code: -32602, "unknown tool: \(name)")
            }
            result = call(name, arguments)
        default:
            return error(id, code: -32601, "method not found: \(method)")
        }
        return encode(["jsonrpc": "2.0", "id": id!, "result": result])
    }

    // MARK: - Tools

    static let instructions = """
        Focus Sentinel is the person's local macOS focus app. It holds ONE current priority and \
        times focus sessions on it. Use focus_status to see what they are focused on now, \
        focus_sessions to read time spent per priority (priorities named '#<n> …' are work-os \
        issues), and focus_propose_priority to suggest a new priority: the app asks the person \
        to confirm, so never claim the priority was set.
        """

    static var tools: [[String: Any]] {
        [
            [
                "name": "focus_status",
                "title": "Current focus",
                "description": "The current priority (with its work-os issue number when it has one), the session running now if any, and today's session count and focused seconds.",
                "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
                "annotations": ["readOnlyHint": true, "openWorldHint": false]
            ],
            [
                "name": "focus_sessions",
                "title": "Focus sessions",
                "description": "Focus sessions, oldest first, with the priority each ran under and the seconds spent in the focus phase (breaks, pauses and detours excluded).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "since": ["type": "string", "description": "YYYY-MM-DD (local) or an ISO 8601 instant; omit for all"],
                        "issue": ["type": "integer", "description": "Only sessions whose priority is work-os issue #<issue>"],
                        "limit": ["type": "integer", "description": "Return only the most recent N"]
                    ],
                    "additionalProperties": false
                ],
                "annotations": ["readOnlyHint": true, "openWorldHint": false]
            ],
            [
                "name": "focus_export",
                "title": "Export my data",
                "description": "Write the full 'Export My Data' document (focus-sentinel.data v1, including the activity log) to a local file. Returns the path and size, not the contents.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["path": ["type": "string", "description": "Absolute path of the JSON file to write"]],
                    "required": ["path"],
                    "additionalProperties": false
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "openWorldHint": false]
            ],
            [
                "name": "focus_propose_priority",
                "title": "Propose a priority",
                "description": "Ask Focus Sentinel to make this the current priority. The app shows a confirmation sheet and changes nothing until the person presses Replace. Prefix the task with '#<issue> ' to link it to a work-os issue.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task": ["type": "string", "description": "The priority, at most 500 characters"],
                        "done_when": ["type": "string", "description": "How the person will know it is done, at most 500 characters"],
                        "dry_run": ["type": "boolean", "description": "Return the focus:// URL without opening it"]
                    ],
                    "required": ["task"],
                    "additionalProperties": false
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false]
            ]
        ]
    }

    private func call(_ name: String, _ arguments: [String: Any]) -> [String: Any] {
        do {
            switch name {
            case "focus_status":
                return try text(Summaries.status(read(), now: now()))
            case "focus_sessions":
                let since = try (arguments["since"] as? String).map(Self.parseSince)
                var sessions = try Summaries.sessions(
                    in: read().document, since: since, issue: Self.int(arguments["issue"]), now: now()
                )
                if let limit = Self.int(arguments["limit"]), limit >= 0 { sessions = Array(sessions.suffix(limit)) }
                return try text(sessions)
            case "focus_export":
                guard let raw = arguments["path"] as? String, !raw.isEmpty else { throw BridgeError("path is required") }
                let path = (raw as NSString).expandingTildeInPath
                guard path.hasPrefix("/") else { throw BridgeError("path must be absolute") }
                let document = try read().document
                let data = try Summaries.encoder().encode(document)
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                return try text(ExportReceipt(
                    path: path, bytes: data.count,
                    priorities: document.priorities.count, sessions: document.sessions.count
                ))
            case "focus_propose_priority":
                guard let task = arguments["task"] as? String else { throw BridgeError("task is required") }
                let url = try Handoff.url(task: task, doneWhen: arguments["done_when"] as? String)
                let dryRun = arguments["dry_run"] as? Bool ?? false
                if !dryRun { try openURL(url) }
                return try text(ProposalReceipt(
                    url: url.absoluteString,
                    opened: !dryRun,
                    note: dryRun
                        ? "Not opened (dry run)."
                        : "Focus Sentinel is showing a confirmation sheet. Nothing changes until the person presses Replace."
                ))
            default:
                throw BridgeError("unknown tool: \(name)")
            }
        } catch {
            return ["content": [["type": "text", "text": "\(error)"]], "isError": true]
        }
    }

    // MARK: - Helpers

    struct ExportReceipt: Encodable { let path: String; let bytes: Int; let priorities: Int; let sessions: Int }
    struct ProposalReceipt: Encodable { let url: String; let opened: Bool; let note: String }

    private func text(_ value: some Encodable) throws -> [String: Any] {
        let data = try Summaries.encoder().encode(value)
        return ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]], "isError": false]
    }

    private func error(_ id: Any?, code: Int, _ message: String) -> String {
        encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"internal error"}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let s = value as? String { return Int(s) }
        return nil
    }

    /// `YYYY-MM-DD` is the start of that local day; anything else must be an ISO 8601 instant.
    public static func parseSince(_ text: String) throws -> Date {
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = .current
        day.dateFormat = "yyyy-MM-dd"
        if let date = day.date(from: text) { return date }
        if let date = ISO8601DateFormatter().date(from: text) { return date }
        throw BridgeError("since must be YYYY-MM-DD or an ISO 8601 instant, not '\(text)'")
    }
}
