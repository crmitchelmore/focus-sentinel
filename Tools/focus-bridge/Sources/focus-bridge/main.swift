import FocusBridgeKit
import Foundation

let usage = """
    focus-bridge — read Focus Sentinel's data and propose priorities, for scripts and agents.

    USAGE
      focus-bridge status                                   current priority, running session, today
      focus-bridge sessions [--since YYYY-MM-DD] [--issue N] [--limit N]
      focus-bridge export [--out FILE]                      full 'Export My Data' JSON (stdout by default)
      focus-bridge propose --task TEXT [--done-when TEXT] [--context ITEM]... [--dry-run]
      focus-bridge add-context --item ITEM [--item ITEM]... [--dry-run]
      focus-bridge mcp                                      Model Context Protocol server on stdio

    ITEM is app:<bundle id>, domain:<host> or keyword:<text>, e.g. app:com.microsoft.Outlook,
    domain:dev.azure.com, keyword:sodexo. add-context adds to the current priority.

    The store is read through a private SQLite backup and never opened in place. Set FOCUS_STORE
    to read another store file. `propose` opens focus://start and `add-context` opens
    focus://context; Focus Sentinel changes nothing until you press Replace or Add.
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

MainActor.assumeIsolated { main() }
