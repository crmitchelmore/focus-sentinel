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
}

@MainActor
struct MCPServerTests {
    private func server(opened: @escaping (URL) -> Void = { _ in }) -> MCPServer {
        MCPServer(
            read: { throw BridgeError("no store in this test") },
            now: { Date(timeIntervalSince1970: 0) },
            openURL: opened
        )
    }

    private func object(_ line: String?) throws -> [String: Any] {
        let data = try #require(line?.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func initializeNegotiatesAVersionAndNamesTheServer() throws {
        let reply = try object(server().handle(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#
        ))
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "focus-sentinel")
    }

    @Test func notificationsGetNoReply() {
        #expect(server().handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func listsFourTools() throws {
        let reply = try object(server().handle(#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#))
        let tools = try #require((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String }
            == ["focus_status", "focus_sessions", "focus_export", "focus_propose_priority"])
        #expect(reply["id"] as? String == "a")
    }

    @Test func aStoreFailureIsAToolErrorNotAProtocolError() throws {
        let reply = try object(server().handle(
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"focus_status","arguments":{}}}"#
        ))
        let result = try #require(reply["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
    }

    @Test func aDryRunProposalOpensNothing() throws {
        var opened: [URL] = []
        let reply = try object(server { opened.append($0) }.handle(
            ##"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"focus_propose_priority","arguments":{"task":"#8 Review","dry_run":true}}}"##
        ))
        #expect((reply["result"] as? [String: Any])?["isError"] as? Bool == false)
        #expect(opened.isEmpty)
    }

    @Test func unknownMethodsAreJSONRPCErrors() throws {
        let reply = try object(server().handle(#"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#))
        #expect((reply["error"] as? [String: Any])?["code"] as? Int == -32601)
    }
}
