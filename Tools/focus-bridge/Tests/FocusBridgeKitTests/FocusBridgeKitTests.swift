import FocusBridgeKit
import FocusCore
import Foundation
import Testing

@MainActor
struct SnapshotTests {
    /// A store written by the app's own verbs, read back through the backup, and left untouched.
    @Test func readsTheActivePriorityWithoutWritingTheSource() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "focus-bridge-test-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appending(path: "source.store")

        let id: UUID = try {
            let container = try FocusStore.makeContainer(kind: .temporary(store))
            return try PriorityStore(context: container.mainContext)
                .setPriority(intent: "#8 Review Sodexo background material", doneWhen: "Notes written")
        }()

        // The database and its write-ahead log. `-shm` is SQLite's shared-memory index, which
        // every reader updates by design; it holds no data and is rebuilt from the WAL.
        let data = Array(FocusStore.storeFileURLs(for: .temporary(store)).prefix(2))
        let before = try data.map { try Data(contentsOf: $0) }

        let reading = try Snapshot.read(store: store)
        #expect(reading.activePriorityID == id.uuidString)

        let status = Summaries.status(reading, now: Date())
        #expect(status.priority?.issue == 8)
        #expect(status.priority?.doneWhen == "Notes written")
        #expect(status.session == nil)

        let after = try data.map { try Data(contentsOf: $0) }
        #expect(before == after)
    }

    @Test func standingPrioritiesComeBackMainFirstWithTheirContext() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "focus-bridge-test-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appending(path: "source.store")

        try {
            let container = try FocusStore.makeContainer(kind: .temporary(store))
            let priorities = PriorityStore(context: container.mainContext)
            let main = try priorities.findOrCreateTask(intent: "#9 Qualify Boulanger", doneWhen: "Go/no-go agreed")
            let second = try priorities.findOrCreateTask(intent: "#62 Fellowship dogfooding", doneWhen: nil)
            _ = try priorities.addContextItem(taskID: main, kindRaw: "keyword", value: "boulanger", displayName: "boulanger")
            try priorities.setStandingPriorities(taskIDs: [main, second])
            try priorities.activate(taskID: second)
        }()

        let status = Summaries.status(try Snapshot.read(store: store), now: Date())
        let standing = try #require(status.standing)
        #expect(standing.map(\.role) == ["main", "secondary"])
        #expect(standing.map(\.priority.issue) == [9, 62])
        #expect(standing.map(\.isCurrent) == [false, true])
        #expect(standing[0].priority.context == ["keyword:boulanger"])
    }

    @Test func aMissingStoreIsANamedError() {
        #expect(throws: BridgeError.self) {
            try Snapshot.read(store: URL(fileURLWithPath: "/nonexistent/FocusSentinel.store"))
        }
    }
}

struct SummariesTests {
    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // swiftlint:disable:next force_try
        return try! decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private func session(start: Date, end: Date?) -> StoreExport.Session {
        var row: [String: Any] = [
            "id": "s", "taskID": "p", "startedAt": iso(start), "phaseRaw": "complete", "kindRaw": "openEnded"
        ]
        if let end { row["endedAt"] = iso(end) }
        return decode(StoreExport.Session.self, row)
    }

    private func transition(_ at: Date, _ from: String, _ to: String) -> StoreExport.SessionTransition {
        decode(StoreExport.SessionTransition.self, [
            "id": UUID().uuidString, "sessionID": "s", "at": iso(at), "fromRaw": from, "toRaw": to,
            "eventRaw": "e", "outcomeRaw": "accepted"
        ])
    }

    @Test func breaksAndPausesAreNotFocusedTime() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let s = session(start: t0, end: t0 + 3_600)
        let rows = [
            transition(t0 + 1_200, "focus", "onBreak"),
            transition(t0 + 1_500, "onBreak", "focus"),
            transition(t0 + 3_000, "focus", "paused"),
            transition(t0 + 3_600, "paused", "complete")
        ]
        #expect(Summaries.focusedSeconds(s, transitions: rows, now: t0 + 9_999) == 2_700)
    }

    @Test func anUnchangedOpenSessionCountsUntilNow() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        #expect(Summaries.focusedSeconds(session(start: t0, end: nil), transitions: [], now: t0 + 600) == 600)
    }

    @Test(arguments: [
        ("#8 Review", 8), ("#123: thing", 123), ("#8", 8),
        ("Review #8", nil), ("#abc", nil), ("#8a thing", nil), ("", nil)
    ] as [(String, Int?)])
    func issueNumbers(intent: String, expected: Int?) {
        #expect(Summaries.issueNumber(in: intent) == expected)
    }
}

struct HandoffTests {
    @Test func reservedCharactersSurviveTheAppsOwnParser() throws {
        let task = "#62 Fix A&B = C + D? 100% (v2) #now"
        let url = try Handoff.url(task: task, doneWhen: "PR merged & deployed", scheme: "focus")
        let request = try #require(HandoffRequest.parse(url).request)
        #expect(request.task == task)
        #expect(request.doneWhen == "PR merged & deployed")
    }

    @Test func overlongFieldsAreRefusedBeforeAnythingOpens() {
        #expect(throws: BridgeError.self) {
            try Handoff.url(task: String(repeating: "x", count: 501), doneWhen: nil, scheme: "focus")
        }
    }

    @Test func contextRidesAlongAndTheAppReadsItBack() throws {
        let url = try Handoff.url(
            task: "#8 Review",
            doneWhen: nil,
            context: ["app:com.microsoft.Outlook", "domain:dev.azure.com", "keyword:Sodexo", "keyword:sodexo"],
            scheme: "focus"
        )
        let request = try #require(HandoffRequest.parse(url).request)
        #expect(request.context.map { "\($0.kind.rawValue):\($0.value)" }
            == ["app:com.microsoft.Outlook", "domain:https://dev.azure.com", "keyword:sodexo"])
        #expect(request.flags.isEmpty)
    }

    @Test(arguments: ["file:/etc/passwd", "nonsense", "app:no dots", "domain:javascript:alert(1)"])
    func itemsTheAppWouldDropAreErrorsHere(_ item: String) {
        #expect(throws: BridgeError.self) {
            try Handoff.contextURL(items: [item], scheme: "focus")
        }
    }

    @Test func standingPrioritiesRoundTripThroughTheAppsParser() throws {
        let url = try Handoff.prioritiesURL(slots: [
            .init(task: "#9 Qualify Boulanger", doneWhen: "Go/no-go agreed", context: ["keyword:boulanger"]),
            .init(task: "#62 Fellowship & dogfooding"),
        ], scheme: "focus")
        let request = try #require(HandoffRequest.parse(url).request)
        #expect(request.verb == .priorities)
        #expect(request.standing.map(\.task) == ["#9 Qualify Boulanger", "#62 Fellowship & dogfooding"])
        #expect(request.standing.map(\.doneWhen) == ["Go/no-go agreed", nil])
        #expect(request.standing[0].context.map(\.value) == ["boulanger"])
        #expect(request.flags.isEmpty)
    }

    @Test func prioritiesNeedAMainOneAndAtMostThree() {
        #expect(throws: BridgeError.self) { try Handoff.prioritiesURL(slots: [], scheme: "focus") }
        #expect(throws: BridgeError.self) {
            try Handoff.prioritiesURL(slots: Array(repeating: .init(task: "x"), count: 4), scheme: "focus")
        }
        #expect(throws: BridgeError.self) {
            try Handoff.prioritiesURL(slots: [.init(task: "x", context: (0..<9).map { "keyword:k\($0)" })], scheme: "focus")
        }
    }

    @Test func aContextURLAddsToTheCurrentPriority() throws {
        let url = try Handoff.contextURL(items: ["app:com.microsoft.teams2"], scheme: "focus")
        #expect(url.absoluteString == "focus://context?add=app%3Acom.microsoft.teams2")
        let request = try #require(HandoffRequest.parse(url).request)
        #expect(request.verb == .context)
        #expect(throws: BridgeError.self) { try Handoff.contextURL(items: [], scheme: "focus") }
    }
}

@MainActor
struct MCPServerTests {
    private func server(
        timeBlocks: URL = FileManager.default.temporaryDirectory.appending(path: "focus-bridge-unused-\(UUID().uuidString)"),
        opened: @escaping (URL) -> Void = { _ in }
    ) -> MCPServer {
        MCPServer(
            read: { throw BridgeError("no store in this test") },
            now: { Date(timeIntervalSince1970: 0) },
            openURL: opened,
            timeBlocks: TimeBlockStore(directory: timeBlocks)
        )
    }

    private func object(_ line: String?) throws -> [String: Any] {
        let data = try #require(line?.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func initializeNegotiatesAVersionAndNamesTheServer() async throws {
        let reply = try await object(server().handle(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#
        ))
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "focus-sentinel")
    }

    @Test func notificationsGetNoReply() async {
        #expect(await server().handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func listsSeventeenTools() async throws {
        let reply = try await object(server().handle(#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#))
        let tools = try #require((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String }
            == ["focus_status", "focus_sessions", "focus_export", "focus_propose_priority", "focus_set_priorities", "focus_add_context",
                "focus_set_time_blocks", "focus_add_time_block", "focus_list_time_blocks", "focus_clear_time_blocks",
                "focus_list_tasks", "focus_create_task", "focus_complete_task", "focus_sync_tasks",
                "focus_list_task_sources", "focus_add_task_source", "focus_remove_task_source"])
        #expect(reply["id"] as? String == "a")
    }

    @Test func aStoreFailureIsAToolErrorNotAProtocolError() async throws {
        let reply = try await object(server().handle(
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"focus_status","arguments":{}}}"#
        ))
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
    }

    @Test func aDryRunProposalOpensNothing() async throws {
        var opened: [URL] = []
        let reply = try await object(server { opened.append($0) }.handle(
            ##"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"focus_propose_priority","arguments":{"task":"#8 Review","dry_run":true}}}"##
        ))
        #expect((reply["result"] as? [String: Any])?["isError"] as? Bool == false)
        #expect(opened.isEmpty)
    }

    @Test func settingPrioritiesOpensOneURLUnlessDry() async throws {
        var opened: [URL] = []
        let call = { (dry: Bool) in
            ##"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"focus_set_priorities","arguments":{"priorities":[{"task":"#9 Boulanger","done_when":"Go/no-go","context":["keyword:boulanger"]},{"task":"#62 Fellowship"}],"dry_run":\##(dry)}}}"##
        }
        let dry = try await object(server { opened.append($0) }.handle(call(true)))
        #expect((dry["result"] as? [String: Any])?["isError"] as? Bool == false)
        #expect(opened.isEmpty)
        let live = try await object(server { opened.append($0) }.handle(call(false)))
        #expect((live["result"] as? [String: Any])?["isError"] as? Bool == false)
        #expect(opened.map(\.host) == ["priorities"])
    }

    @Test func addingContextWithoutAStoreOpensNothing() async throws {
        var opened: [URL] = []
        let dry = try await object(server { opened.append($0) }.handle(
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"focus_add_context","arguments":{"items":["keyword:sodexo"],"dry_run":true}}}"#
        ))
        #expect((dry["result"] as? [String: Any])?["isError"] as? Bool == false)
        let live = try await object(server { opened.append($0) }.handle(
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"focus_add_context","arguments":{"items":["keyword:sodexo"]}}}"#
        ))
        #expect((live["result"] as? [String: Any])?["isError"] as? Bool == true)
        #expect(opened.isEmpty)
    }

    @Test func unknownMethodsAreJSONRPCErrors() async throws {
        let reply = try await object(server().handle(#"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#))
        #expect((reply["error"] as? [String: Any])?["code"] as? Int == -32601)
    }
}

@MainActor
struct TimeBlockTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "focus-time-blocks-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func server(_ directory: URL) -> MCPServer {
        MCPServer(read: { throw BridgeError("no store") }, now: { Self.now }, openURL: { _ in }, timeBlocks: TimeBlockStore(directory: directory))
    }

    private func call(_ server: MCPServer, _ name: String, _ arguments: [String: Any]) async throws -> (isError: Bool, text: String) {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments]]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let data = try #require(await server.handle(line)?.data(using: .utf8))
        let reply = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(reply["result"] as? [String: Any])
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        return (result["isError"] as? Bool ?? true, text)
    }

    @Test func aBlockOfJustKindAndDurationReachesTheAppsReader() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reply = try await call(server(dir), "focus_add_time_block", ["source": "manual", "kind": "away", "duration_minutes": 45])
        #expect(!reply.isError, "\(reply.text)")

        let url = ExternalTimeBlocks.fileURL(for: "manual", in: dir)
        let data = try Data(contentsOf: url)
        let window = DateInterval(start: Self.now, duration: 3_600)
        #expect(ExternalTimeBlocks.busyBlocks(from: data, in: window)
            == [CalendarBusyBlock(start: Self.now, end: Self.now.addingTimeInterval(45 * 60))])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func settingReplacesTheSourcesSetAndDropsWhatHasEnded() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = server(dir)
        let iso = { (offset: TimeInterval) in ISO8601DateFormatter().string(from: Self.now.addingTimeInterval(offset)) }
        _ = try await call(server, "focus_set_time_blocks", ["source": "outlook", "blocks": [
            ["kind": "busy", "start": iso(600), "end": iso(1_800), "title": "1:1", "id": "a"]
        ]])
        let reply = try await call(server, "focus_set_time_blocks", ["source": "outlook", "blocks": [
            ["kind": "busy", "start": iso(-3_600), "end": iso(-1_800)],
            ["kind": "tentative", "start": iso(3_600), "duration_minutes": 30, "detail": "Room 4"],
            ["kind": "focus", "start": iso(7_200), "duration_minutes": 60]
        ]])
        #expect(!reply.isError, "\(reply.text)")
        let files = try TimeBlockStore(directory: dir).list(now: Self.now)
        #expect(files.map(\.source) == ["outlook"])
        #expect(files.first?.blocks.map(\.kind) == [.tentative, .focus])
        #expect(files.first?.blocks.first?.detail == "Room 4")
    }

    @Test func addingWithAnExistingIDReplacesIt() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = server(dir)
        _ = try await call(server, "focus_add_time_block", ["source": "rota", "kind": "busy", "duration_minutes": 30, "id": "x"])
        _ = try await call(server, "focus_add_time_block", ["source": "rota", "kind": "away", "duration_minutes": 10, "id": "x"])
        _ = try await call(server, "focus_add_time_block", ["source": "rota", "kind": "busy", "duration_minutes": 5])
        let blocks = try TimeBlockStore(directory: dir).list(source: "rota", now: Self.now).first?.blocks ?? []
        let kinds: [TimeBlockKind] = blocks.map(\.kind)
        #expect(kinds == [.busy, .away])
    }

    @Test(arguments: [
        ["source": "../etc", "kind": "busy", "duration_minutes": 5],
        ["source": "ok", "kind": "meeting", "duration_minutes": 5],
        ["source": "ok", "kind": "busy"],
        ["source": "ok", "kind": "busy", "duration_minutes": 5, "end": "2030-01-01T00:00:00Z"],
        ["source": "ok", "kind": "busy", "duration_minutes": -5],
        ["source": "ok", "kind": "busy", "start": "next tuesday", "duration_minutes": 5],
        ["source": "ok", "kind": "busy", "duration_minutes": 60 * 24 * 40]
    ] as [[String: any Sendable]])
    func badBlocksAreToolErrorsAndWriteNothing(_ arguments: [String: any Sendable]) async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reply = try await call(server(dir), "focus_add_time_block", arguments)
        #expect(reply.isError)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func clearingOneSourceLeavesTheOthers() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = server(dir)
        _ = try await call(server, "focus_add_time_block", ["source": "a", "kind": "busy", "duration_minutes": 5])
        _ = try await call(server, "focus_add_time_block", ["source": "b", "kind": "busy", "duration_minutes": 5])
        let cleared = try await call(server, "focus_clear_time_blocks", ["source": "a"])
        #expect(cleared.text.contains("\"a\""))
        #expect(try TimeBlockStore(directory: dir).list(now: Self.now).map(\.source) == ["b"])
        _ = try await call(server, "focus_clear_time_blocks", [:])
        #expect(try TimeBlockStore(directory: dir).list(now: Self.now).isEmpty)
    }

    @Test func theDefaultDirectorySitsBesideTheStore() {
        #expect(TimeBlockStore.defaultDirectory(environment: ["FOCUS_STORE": "/tmp/s/FocusSentinel.store"]).path == "/tmp/s/TimeBlocks")
        #expect(TimeBlockStore.defaultDirectory(environment: ["FOCUS_TIME_BLOCKS": "/tmp/tb"]).path == "/tmp/tb")
    }
}
