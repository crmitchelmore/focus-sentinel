import FocusBridgeKit
import FocusCore
import Foundation

let usage = """
    focus-bridge — read Focus Sentinel's data and propose priorities, for scripts and agents.

    USAGE
      focus-bridge status                                   current priority, running session, today
      focus-bridge sessions [--since YYYY-MM-DD] [--issue N] [--limit N]
      focus-bridge export [--out FILE]                      full 'Export My Data' JSON (stdout by default)
      focus-bridge propose --task TEXT [--done-when TEXT] [--context ITEM]... [--dry-run]
      focus-bridge add-context --item ITEM [--item ITEM]... [--dry-run]
      focus-bridge set-priorities --slot TEXT [--done-when TEXT] [--context ITEM]...
                                  [--slot TEXT ...]... [--dry-run]
      focus-bridge time-blocks add --source NAME --kind KIND [--start TIME]
                                   (--end TIME | --minutes N) [--title TEXT] [--detail TEXT] [--id ID]
      focus-bridge time-blocks set --source NAME [--file FILE]   replace NAME's blocks (JSON on stdin by default)
      focus-bridge time-blocks list [--source NAME]
      focus-bridge time-blocks clear (--source NAME | --all)
      focus-bridge mcp                                      Model Context Protocol server on stdio

    ITEM is app:<bundle id>, domain:<host> or keyword:<text>, e.g. app:com.microsoft.Outlook,
    domain:dev.azure.com, keyword:sodexo. add-context adds to the current priority.

    set-priorities sets one main and up to two secondary standing priorities: each --slot starts
    one (main first), and the --done-when and --context after it belong to it.

    time-blocks lets another source mark time the app cannot see. KIND is busy, away or
    tentative (the app stays quiet and refuses a focus block that would run into it) or focus or
    free (recorded, no effect). TIME is ISO 8601, e.g. 2026-10-16T14:00:00+01:00; without an
    offset it is local; --start defaults to now. `set` reads a JSON array of
    {kind, start, end | duration_minutes, title?, detail?, id?}. Blocks are written to
    TimeBlocks/<NAME>.json beside the store (or FOCUS_TIME_BLOCKS) and take effect without
    confirmation; titles and details stay there and never enter the app's data.

    The store is read through a private SQLite backup and never opened in place. Set FOCUS_STORE
    to read another store file. `propose`, `add-context` and `set-priorities` open focus://start,
    focus://context and focus://priorities; Focus Sentinel changes nothing until you press
    Replace, Add or Set Priorities.
    """

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("focus-bridge: \(message)\n".utf8))
    exit(code)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count else { fail("\(name) needs a value", code: 2) }
    return args[i + 1]
}

func options(_ name: String, in args: [String]) -> [String] {
    var values: [String] = []
    var i = 0
    while i < args.count {
        if args[i] == name {
            guard i + 1 < args.count else { fail("\(name) needs a value", code: 2) }
            values.append(args[i + 1])
            i += 2
        } else {
            i += 1
        }
    }
    return values
}

/// `--slot A --done-when X --context c1 --slot B …`: each `--slot` opens a slot and the options
/// after it fill that slot.
func slots(in args: [String]) -> [Handoff.Slot] {
    var slots: [Handoff.Slot] = []
    var i = 0
    while i < args.count {
        let name = args[i]
        guard ["--slot", "--done-when", "--context"].contains(name) else { i += 1; continue }
        guard i + 1 < args.count else { fail("\(name) needs a value", code: 2) }
        let value = args[i + 1]
        switch name {
        case "--slot":
            slots.append(Handoff.Slot(task: value))
        case "--done-when":
            guard !slots.isEmpty else { fail("--done-when must follow a --slot", code: 2) }
            slots[slots.count - 1].doneWhen = value
        default:
            guard !slots.isEmpty else { fail("--context must follow a --slot", code: 2) }
            slots[slots.count - 1].context.append(value)
        }
        i += 2
    }
    return slots
}

func emit(_ value: some Encodable) throws {
    FileHandle.standardOutput.write(try Summaries.encoder().encode(value) + Data("\n".utf8))
}

@MainActor
func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { print(usage); return }
    let rest = Array(args.dropFirst())
    let store = Snapshot.defaultStoreURL()
    let now = Date()
    do {
        switch command {
        case "status":
            try emit(Summaries.status(Snapshot.read(store: store, now: now), now: now))
        case "sessions":
            let since = try option("--since", in: rest).map(MCPServer.parseSince)
            let issue = option("--issue", in: rest).map { text -> Int in
                guard let n = Int(text) else { fail("--issue must be a number", code: 2) }
                return n
            }
            var sessions = try Summaries.sessions(
                in: Snapshot.read(store: store, now: now).document, since: since, issue: issue, now: now
            )
            if let limit = option("--limit", in: rest).flatMap(Int.init) { sessions = Array(sessions.suffix(limit)) }
            try emit(sessions)
        case "export":
            let data = try Summaries.encoder().encode(Snapshot.read(store: store, now: now).document)
            if let out = option("--out", in: rest) {
                try data.write(to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath), options: .atomic)
                FileHandle.standardError.write(Data("wrote \(data.count) bytes to \(out)\n".utf8))
            } else {
                FileHandle.standardOutput.write(data + Data("\n".utf8))
            }
        case "propose":
            guard let task = option("--task", in: rest) else { fail("propose needs --task", code: 2) }
            let url = try Handoff.url(
                task: task,
                doneWhen: option("--done-when", in: rest),
                context: options("--context", in: rest)
            )
            print(url.absoluteString)
            if !rest.contains("--dry-run") {
                try Handoff.open(url)
                FileHandle.standardError.write(Data("Sent. Press Replace in Focus Sentinel to accept it.\n".utf8))
            }
        case "add-context":
            let url = try Handoff.contextURL(items: options("--item", in: rest))
            print(url.absoluteString)
            if !rest.contains("--dry-run") {
                guard try Snapshot.read(store: store, now: now).activePriorityID != nil else {
                    fail("there is no current priority to add context to; propose one first")
                }
                try Handoff.open(url)
                FileHandle.standardError.write(Data("Sent. Press Add in Focus Sentinel to accept it.\n".utf8))
            }
        case "set-priorities":
            let url = try Handoff.prioritiesURL(slots: slots(in: rest))
            print(url.absoluteString)
            if !rest.contains("--dry-run") {
                try Handoff.open(url)
                FileHandle.standardError.write(Data("Sent. Press Set Priorities in Focus Sentinel to accept them.\n".utf8))
            }
        case "time-blocks":
            try timeBlocks(Array(rest), now: now)
        case "mcp":
            MCPServer(read: { try Snapshot.read(store: store) }).run()
        case "-h", "--help", "help":
            print(usage)
        default:
            fail("unknown command '\(command)'\n\n\(usage)", code: 2)
        }
    } catch {
        fail("\(error)")
    }
}

func timeBlocks(_ args: [String], now: Date) throws {
    let blocks = TimeBlockStore(directory: TimeBlockStore.defaultDirectory())
    guard let verb = args.first else { fail("time-blocks needs add, set, list or clear", code: 2) }
    let rest = Array(args.dropFirst())
    switch verb {
    case "add":
        guard let source = option("--source", in: rest) else { fail("time-blocks add needs --source", code: 2) }
        var arguments: [String: Any] = [:]
        for (flag, key) in [("--kind", "kind"), ("--start", "start"), ("--end", "end"), ("--minutes", "duration_minutes"),
                            ("--title", "title"), ("--detail", "detail"), ("--id", "id")] {
            if let value = option(flag, in: rest) { arguments[key] = value }
        }
        let block = try TimeBlockStore.block(from: arguments, now: now)
        let file = try blocks.add(source: try TimeBlockStore.source(source), block: block, now: now)
        FileHandle.standardError.write(Data("\(file.blocks.count) block(s) for \(source) in \(blocks.directory.path)\n".utf8))
    case "set":
        guard let source = option("--source", in: rest) else { fail("time-blocks set needs --source", code: 2) }
        let data: Data
        if let path = option("--file", in: rest), path != "-" {
            data = try Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        } else {
            data = FileHandle.standardInput.readDataToEndOfFile()
        }
        let json = try JSONSerialization.jsonObject(with: data)
        guard let raw = (json as? [Any]) ?? ((json as? [String: Any])?["blocks"] as? [Any]) else {
            fail("time-blocks set reads a JSON array of blocks, or an object with a blocks array", code: 2)
        }
        let parsed = try raw.map { item -> TimeBlock in
            guard let object = item as? [String: Any] else { throw BridgeError("each block must be an object") }
            return try TimeBlockStore.block(from: object, now: now)
        }
        let file = try blocks.set(source: try TimeBlockStore.source(source), blocks: parsed, now: now)
        FileHandle.standardError.write(Data("\(file.blocks.count) block(s) for \(source) in \(blocks.directory.path)\n".utf8))
    case "list":
        try emit(blocks.list(source: try option("--source", in: rest).map(TimeBlockStore.source), now: now))
    case "clear":
        if let source = option("--source", in: rest) {
            try emit(blocks.clear(source: try TimeBlockStore.source(source)))
        } else if rest.contains("--all") {
            try emit(blocks.clear())
        } else {
            fail("time-blocks clear needs --source NAME or --all", code: 2)
        }
    default:
        fail("time-blocks needs add, set, list or clear, not '\(verb)'", code: 2)
    }
}

MainActor.assumeIsolated { main() }
