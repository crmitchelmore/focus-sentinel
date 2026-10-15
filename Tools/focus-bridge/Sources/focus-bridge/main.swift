import FocusBridgeKit
import Foundation

let usage = """
    focus-bridge — read Focus Sentinel's data and propose priorities, for scripts and agents.

    USAGE
      focus-bridge status                                   current priority, running session, today
      focus-bridge sessions [--since YYYY-MM-DD] [--issue N] [--limit N]
      focus-bridge export [--out FILE]                      full 'Export My Data' JSON (stdout by default)
      focus-bridge propose --task TEXT [--done-when TEXT] [--dry-run]
      focus-bridge mcp                                      Model Context Protocol server on stdio

    The store is read through a private SQLite backup and never opened in place. Set FOCUS_STORE
    to read another store file. `propose` opens focus://start; Focus Sentinel changes nothing
    until you press Replace.
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
            let url = try Handoff.url(task: task, doneWhen: option("--done-when", in: rest))
            print(url.absoluteString)
            if !rest.contains("--dry-run") {
                try Handoff.open(url)
                FileHandle.standardError.write(Data("Sent. Press Replace in Focus Sentinel to accept it.\n".utf8))
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
