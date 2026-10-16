import FocusCore
import Foundation

/// **A Model Context Protocol server over stdio.**
///
/// One JSON-RPC 2.0 message per line in, one per line out, nothing else on stdout. No socket is
/// opened: the client starts this process and owns both ends of the pipe. Three tools only read
/// a snapshot; three propose a priority, context or standing priorities that the person still
/// has to accept; four let an outside source mark time — a meeting, time away — that the app
/// then keeps quiet through (focus-ext).
@MainActor
public final class MCPServer {
    public typealias Reader = @MainActor () throws -> StoreReading

    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let serverVersion = "0.4.0"

    private let read: Reader
    private let now: () -> Date
    private let openURL: (URL) throws -> Void
    private let timeBlocks: TimeBlockStore

    public init(
        read: @escaping Reader,
        now: @escaping () -> Date = Date.init,
        openURL: @escaping (URL) throws -> Void = Handoff.open,
        timeBlocks: TimeBlockStore = TimeBlockStore(directory: TimeBlockStore.defaultDirectory())
    ) {
        self.read = read
        self.now = now
        self.openURL = openURL
        self.timeBlocks = timeBlocks
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
        issues), focus_propose_priority to suggest a new priority with its context (apps, \
        sites, keywords that belong to the work), focus_add_context to add context to the \
        current priority, and focus_set_priorities to set their standing main and secondary \
        priorities (shown in the app as one-press starting points). The app asks the person to \
        confirm each, so never claim anything was set or added. \
        Time blocks are different: focus_set_time_blocks, focus_add_time_block, \
        focus_list_time_blocks and focus_clear_time_blocks let a source (an Outlook or other \
        calendar, a rota, a script) mark time the app cannot see. They take effect without \
        confirmation. Kinds busy, away and tentative make the app stay quiet and refuse a focus \
        block that would run into them; focus and free are recorded and change nothing. A block \
        can be just a kind, a start and a duration; a title and detail are optional and stay \
        with the source, never in the app's data. Use one stable source name per provider, and \
        prefer focus_set_time_blocks to replace that source's whole set when syncing.
        """

    static let contextSchema: [String: Any] = [
        "type": "array",
        "items": ["type": "string"],
        "maxItems": HandoffRequest.maximumContextItems,
        "description": "Apps, sites and keywords that belong to this work, as 'app:<bundle id>' "
            + "(e.g. app:com.microsoft.Outlook), 'domain:<host>' (e.g. domain:dev.azure.com) or "
            + "'keyword:<text>'. Files are not accepted."
    ]

    static let timeBlockProperties: [String: Any] = [
        "kind": [
            "type": "string",
            "enum": TimeBlockKind.allCases.map(\.rawValue),
            "description": "busy, away and tentative silence the app and block focus sessions across them; focus and free change nothing"
        ],
        "start": ["type": "string", "description": "ISO 8601 start, e.g. 2026-10-16T14:00:00+01:00 (a time without an offset is local). Defaults to now."],
        "end": ["type": "string", "description": "ISO 8601 end. Give this or duration_minutes."],
        "duration_minutes": ["type": "number", "description": "Length in minutes. Give this or end."],
        "title": ["type": "string", "description": "Optional, at most \(ExternalTimeBlocks.maximumTitleLength) characters. Kept with the source; the app never stores it."],
        "detail": ["type": "string", "description": "Optional, at most \(ExternalTimeBlocks.maximumDetailLength) characters. Kept with the source; the app never stores it."],
        "id": ["type": "string", "description": "Optional stable id from the source; adding a block with an existing id replaces it."]
    ]

    static let sourceSchema: [String: Any] = [
        "type": "string",
        "pattern": "^[a-z0-9_-][a-z0-9._-]{0,63}$",
        "description": "Stable name for the provider, e.g. 'outlook' or 'rota'. Each source owns its own set of blocks."
    ]

    static var slotContextSchema: [String: Any] {
        var schema = contextSchema
        schema["maxItems"] = HandoffRequest.maximumContextItemsPerSlot
        return schema
    }

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
                        "context": contextSchema,
                        "dry_run": ["type": "boolean", "description": "Return the focus:// URL without opening it"]
                    ],
                    "required": ["task"],
                    "additionalProperties": false
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false]
            ],
            [
                "name": "focus_set_priorities",
                "title": "Set standing priorities",
                "description": "Ask Focus Sentinel to set the person's standing priorities: one main and up to two secondary, each with its own context. The app lists them as one-press starting points for a focus block and does not change the current priority. It shows a confirmation sheet and sets nothing until the person presses Set Priorities. Sending the same set again reuses the stored tasks.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "priorities": [
                            "type": "array",
                            "minItems": 1,
                            "maxItems": HandoffStandingSlot.keyPrefixes.count,
                            "description": "Main first, then the secondaries",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "task": ["type": "string", "description": "The priority, at most 500 characters"],
                                    "done_when": ["type": "string", "description": "How the person will know it is done"],
                                    "context": slotContextSchema
                                ],
                                "required": ["task"],
                                "additionalProperties": false
                            ]
                        ],
                        "dry_run": ["type": "boolean", "description": "Return the focus:// URL without opening it"]
                    ],
                    "required": ["priorities"],
                    "additionalProperties": false
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false]
            ],
            [
                "name": "focus_add_context",
                "title": "Add context to the current priority",
                "description": "Ask Focus Sentinel to add apps, sites or keywords to the CURRENT priority's context pack, so it can tell on-task from off-task. The app shows a confirmation sheet and adds nothing until the person presses Add; items already there are skipped. Check focus_status first: with no current priority the app ignores this.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "items": contextSchema,
                        "dry_run": ["type": "boolean", "description": "Return the focus:// URL without opening it"]
                    ],
                    "required": ["items"],
                    "additionalProperties": false
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false]
            ],
            [
                "name": "focus_set_time_blocks",
                "title": "Replace a source's time blocks",
                "description": "Replace every time block from one source with this set (an empty list clears it). Use it to sync a calendar: send the source's busy time for the coming hours or days. Takes effect within seconds, without confirmation. Blocks that have already ended are dropped.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "source": sourceSchema,
                        "blocks": [
                            "type": "array",
                            "maxItems": ExternalTimeBlocks.maximumBlocksPerSource,
                            "items": [
                                "type": "object",
                                "properties": timeBlockProperties,
                                "required": ["kind"],
                                "additionalProperties": false
                            ]
                        ]
                    ],
                    "required": ["source", "blocks"],
                    "additionalProperties": false
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": true, "openWorldHint": false]
            ],
            [
                "name": "focus_add_time_block",
                "title": "Add a time block",
                "description": "Add one time block for a source, e.g. {source:'manual', kind:'away', duration_minutes:45}. Replaces a block with the same id. Takes effect within seconds, without confirmation.",
                "inputSchema": [
                    "type": "object",
                    "properties": timeBlockProperties.merging(["source": sourceSchema]) { a, _ in a },
                    "required": ["source", "kind"],
                    "additionalProperties": false
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false]
            ],
            [
                "name": "focus_list_time_blocks",
                "title": "List time blocks",
                "description": "The time blocks sources have sent that have not yet ended, per source, with their titles and details.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["source": sourceSchema],
                    "additionalProperties": false
                ],
                "annotations": ["readOnlyHint": true, "openWorldHint": false]
            ],
            [
                "name": "focus_clear_time_blocks",
                "title": "Clear time blocks",
                "description": "Remove every time block from one source, or from every source when source is omitted.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["source": sourceSchema],
                    "additionalProperties": false
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": true, "openWorldHint": false]
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
                let url = try Handoff.url(
                    task: task,
                    doneWhen: arguments["done_when"] as? String,
                    context: try Self.strings(arguments["context"], name: "context")
                )
                let dryRun = arguments["dry_run"] as? Bool ?? false
                if !dryRun { try openURL(url) }
                return try text(ProposalReceipt(
                    url: url.absoluteString,
                    opened: !dryRun,
                    note: dryRun
                        ? "Not opened (dry run)."
                        : "Focus Sentinel is showing a confirmation sheet. Nothing changes until the person presses Replace."
                ))
            case "focus_set_priorities":
                guard let raw = arguments["priorities"] as? [Any] else { throw BridgeError("priorities is required") }
                let slots = try raw.map { item -> Handoff.Slot in
                    guard let object = item as? [String: Any], let task = object["task"] as? String else {
                        throw BridgeError("each priority needs a task")
                    }
                    return Handoff.Slot(
                        task: task,
                        doneWhen: object["done_when"] as? String,
                        context: try Self.strings(object["context"], name: "context")
                    )
                }
                let url = try Handoff.prioritiesURL(slots: slots)
                let dryRun = arguments["dry_run"] as? Bool ?? false
                if !dryRun { try openURL(url) }
                return try text(ProposalReceipt(
                    url: url.absoluteString,
                    opened: !dryRun,
                    note: dryRun
                        ? "Not opened (dry run)."
                        : "Focus Sentinel is showing a confirmation sheet. Nothing is set until the person presses Set Priorities."
                ))
            case "focus_add_context":
                let url = try Handoff.contextURL(items: Self.strings(arguments["items"], name: "items"))
                let dryRun = arguments["dry_run"] as? Bool ?? false
                if !dryRun {
                    guard try read().activePriorityID != nil else {
                        throw BridgeError("there is no current priority to add context to; propose one first")
                    }
                    try openURL(url)
                }
                return try text(ProposalReceipt(
                    url: url.absoluteString,
                    opened: !dryRun,
                    note: dryRun
                        ? "Not opened (dry run)."
                        : "Focus Sentinel is showing a confirmation sheet. Nothing is added until the person presses Add."
                ))
            case "focus_set_time_blocks":
                let source = try TimeBlockStore.source(arguments["source"])
                guard let raw = arguments["blocks"] as? [Any] else { throw BridgeError("blocks must be an array") }
                let at = now()
                let blocks = try raw.map { item -> TimeBlock in
                    guard let object = item as? [String: Any] else { throw BridgeError("each block must be an object") }
                    return try TimeBlockStore.block(from: object, now: at)
                }
                return try text(TimeBlockReceipt(timeBlocks.set(source: source, blocks: blocks, now: at)))
            case "focus_add_time_block":
                let source = try TimeBlockStore.source(arguments["source"])
                let at = now()
                let block = try TimeBlockStore.block(from: arguments, now: at)
                return try text(TimeBlockReceipt(timeBlocks.add(source: source, block: block, now: at)))
            case "focus_list_time_blocks":
                let source = try arguments["source"].map(TimeBlockStore.source)
                return try text(timeBlocks.list(source: source, now: now()))
            case "focus_clear_time_blocks":
                let source = try arguments["source"].map(TimeBlockStore.source)
                return try text(ClearReceipt(cleared: timeBlocks.clear(source: source)))
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
    struct ClearReceipt: Encodable { let cleared: [String] }
    struct TimeBlockReceipt: Encodable {
        let source: String
        let blocks: Int
        let holdingTheQuestion: Int
        let note: String

        init(_ file: TimeBlockFile) {
            source = file.source
            blocks = file.blocks.count
            holdingTheQuestion = file.blocks.filter(\.kind.holdsTheQuestion).count
            note = "Focus Sentinel reads these within seconds. Busy, away and tentative time keeps it quiet and blocks focus sessions across it."
        }
    }


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

    static func strings(_ value: Any?, name: String) throws -> [String] {
        guard let value else { return [] }
        guard let array = value as? [Any], array.allSatisfy({ $0 is String }) else {
            throw BridgeError("\(name) must be an array of strings")
        }
        return array.compactMap { $0 as? String }
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
