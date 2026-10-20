import Darwin
@testable import FocusBridgeKit
import FocusCore
import Foundation
import Testing

// MARK: - Fakes

/// Answers each request from a handler and remembers what was asked.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { var status: Int; var body: Data }
    typealias Handler = @Sendable (URLRequest) throws -> Reply

    private let lock = NSLock()
    private var handler: Handler
    private var recorded: [URLRequest] = []

    init(_ handler: @escaping Handler) { self.handler = handler }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func respond(_ handler: @escaping Handler) { lock.withLock { self.handler = handler } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let handler = lock.withLock { recorded.append(request); return self.handler }
        let reply = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (reply.body, response)
    }
}

struct FakeTokens: GitHubTokenProviding {
    var refused: Set<String> = []
    func token(account: String?) async throws -> String {
        if let account, refused.contains(account) {
            throw TaskProviderError.token(account: account, reason: "gh has no login for \(account)")
        }
        return "token-\(account ?? "default")"
    }
}

func reply(_ status: Int = 200, _ object: Any) -> FakeTransport.Reply {
    .init(status: status, body: try! JSONSerialization.data(withJSONObject: object))
}

func body(_ request: URLRequest) -> [String: Any] {
    request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
}

func query(_ request: URLRequest, _ name: String) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func iso(_ offset: TimeInterval) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(offset)) }

private func issue(_ number: Int, _ title: String, labels: [String] = [], closedAgo: TimeInterval? = nil, pullRequest: Bool = false) -> [String: Any] {
    var object: [String: Any] = [
        "number": number,
        "title": title,
        "html_url": "https://github.com/octo/work-os/issues/\(number)",
        "state": closedAgo == nil ? "open" : "closed",
        "labels": labels.map { ["name": $0, "color": "ffffff"] },
        "updated_at": iso(-60),
        "closed_at": closedAgo.map { iso(-$0) } ?? NSNull()
    ]
    if pullRequest { object["pull_request"] = ["url": "https://api.github.com/repos/octo/work-os/pulls/\(number)"] }
    return object
}

private func registry(_ transport: FakeTransport, tokens: FakeTokens = FakeTokens()) -> TaskProviderRegistry {
    let client = GitHubClient(transport: transport, tokens: tokens)
    return TaskProviderRegistry(providers: [
        TaskProviderKind.githubIssues.rawValue: GitHubIssuesProvider(client: client, now: { now }),
        TaskProviderKind.githubProject.rawValue: GitHubProjectProvider(client: client, now: { now })
    ])
}

private let workOS = TaskSourceConfig(
    name: "work-os", provider: "github-issues", settings: ["repository": "octo/work-os", "account": "octo"]
)

private func directory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "focus-task-mirror-\(UUID().uuidString)", directoryHint: .isDirectory)
}

// MARK: - GitHub issues

struct GitHubIssuesProviderTests {
    @Test func fetchMapsOpenAndRecentlyClosedIssuesAndSkipsPullRequests() async throws {
        let transport = FakeTransport { request in
            switch query(request, "state") {
            case "open":
                return reply(200, [issue(1, "Book travel", labels: ["cat:travel"]), issue(2, "A pull request", pullRequest: true)])
            default:
                return reply(200, [
                    issue(3, "Closed yesterday", labels: ["cat:hve"], closedAgo: 86_400),
                    issue(4, "Closed last week", closedAgo: 8 * 86_400)
                ])
            }
        }
        let tasks = try await registry(transport).provider(for: workOS).fetch(workOS)

        #expect(tasks.map(\.id) == ["1", "3"])
        let open = try #require(tasks.first)
        #expect(open.title == "Book travel")
        #expect(open.tags == ["cat:travel"])
        #expect(open.reference == "work-os#1")
        #expect(open.url?.absoluteString == "https://github.com/octo/work-os/issues/1")
        #expect(open.state == .open && open.completedAt == nil)
        #expect(tasks[1].state == .done)
        #expect(tasks[1].completedAt == now.addingTimeInterval(-86_400))

        let requests = transport.requests
        #expect(requests.count == 2)
        let first = try #require(requests.first)
        #expect(first.httpMethod == "GET")
        #expect(first.url?.path == "/repos/octo/work-os/issues")
        #expect(query(first, "per_page") == "100" && query(first, "page") == "1")
        #expect(first.value(forHTTPHeaderField: "Authorization") == "Bearer token-octo")
        #expect(first.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(first.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(query(requests[1], "since") == iso(-3 * 86_400))
    }

    @Test func fetchPagesUntilAShortPage() async throws {
        let transport = FakeTransport { request in
            guard query(request, "state") == "open" else { return reply(200, []) }
            let page = Int(query(request, "page") ?? "1") ?? 1
            let count = page == 1 ? 100 : 5
            return reply(200, (0..<count).map { issue((page - 1) * 100 + $0 + 1, "Issue") })
        }
        let tasks = try await registry(transport).provider(for: workOS).fetch(workOS)
        #expect(tasks.count == 105)
        #expect(transport.requests.count == 3)
    }

    @Test func completeReopenAndCreateSendGitHubsShapes() async throws {
        let transport = FakeTransport { request in
            request.httpMethod == "POST" ? reply(201, issue(99, "New one", labels: ["cat:bat"])) : reply(200, issue(7, "Seven"))
        }
        let provider = try registry(transport).provider(for: workOS)
        try await provider.complete(workOS, taskID: "7")
        try await provider.reopen(workOS, taskID: "7")
        let created = try await provider.create(workOS, title: "New one", tags: ["cat:bat"])

        let requests = transport.requests
        #expect(requests.map(\.httpMethod) == ["PATCH", "PATCH", "POST"])
        #expect(requests.map { $0.url?.path } == ["/repos/octo/work-os/issues/7", "/repos/octo/work-os/issues/7", "/repos/octo/work-os/issues"])
        #expect(body(requests[0]) as NSDictionary == ["state": "closed", "state_reason": "completed"])
        #expect(body(requests[1]) as NSDictionary == ["state": "open"])
        #expect(body(requests[2]) as NSDictionary == ["title": "New one", "labels": ["cat:bat"]])
        #expect(created.id == "99" && created.tags == ["cat:bat"] && created.reference == "work-os#99")
    }

    @Test func anErrorCarriesGitHubsWords() async throws {
        let transport = FakeTransport { _ in reply(401, ["message": "Bad credentials"]) }
        await #expect(throws: TaskProviderError.http(service: "GitHub", status: 401, message: "Bad credentials")) {
            try await registry(transport).provider(for: workOS).fetch(workOS)
        }
        #expect(TaskProviderError.http(service: "GitHub", status: 401, message: "Bad credentials").description == "GitHub said 401: Bad credentials")
    }
}

// MARK: - GitHub Projects

struct GitHubProjectProviderTests {
    static let source = TaskSourceConfig(
        name: "board", provider: "github-project", settings: ["owner": "octo-org", "number": "5"]
    )

    static func project(items: [[String: Any]]) -> [String: Any] {
        [
            "id": "PVT_1",
            "field": ["id": "FIELD_status", "name": "Status", "options": [
                ["id": "OPT_todo", "name": "Todo"], ["id": "OPT_doing", "name": "In Progress"], ["id": "OPT_done", "name": "Done"]
            ]],
            "items": ["pageInfo": ["hasNextPage": false, "endCursor": NSNull()], "nodes": items]
        ]
    }

    /// A user lookup that is not found, then an organisation that has the project.
    static func transport(items: [[String: Any]]) -> FakeTransport {
        let found = try! JSONSerialization.data(withJSONObject: ["data": ["organization": ["projectV2": project(items: items)]]])
        return FakeTransport { request in
            let text = body(request)["query"] as? String ?? ""
            if text.contains("mutation") {
                return reply(200, ["data": ["updateProjectV2ItemFieldValue": ["projectV2Item": ["id": "PVTI_x"]]]])
            }
            if text.contains("user(login") {
                return reply(200, ["data": ["user": NSNull()], "errors": [["type": "NOT_FOUND", "message": "Could not resolve to a User"]]])
            }
            return .init(status: 200, body: found)
        }
    }

    @Test func fetchFallsBackToTheOrganisationAndMapsItems() async throws {
        let transport = Self.transport(items: [
            ["id": "PVTI_issue", "isArchived": false, "updatedAt": iso(-60), "fieldValueByName": ["name": "In Progress", "optionId": "OPT_doing"],
             "content": ["__typename": "Issue", "number": 12, "title": "Ship it", "url": "https://github.com/octo-org/app/issues/12",
                         "state": "OPEN", "closedAt": NSNull(), "updatedAt": iso(-120), "repository": ["name": "app"],
                         "labels": ["nodes": [["name": "cat:hve"]]]]],
            ["id": "PVTI_draft", "isArchived": false, "updatedAt": iso(-300), "fieldValueByName": ["name": "done", "optionId": "OPT_done"],
             "content": ["__typename": "DraftIssue", "title": "Draft idea", "updatedAt": iso(-400)]],
            ["id": "PVTI_archived", "isArchived": true, "content": ["__typename": "DraftIssue", "title": "Old"]],
            ["id": "PVTI_pr", "isArchived": false, "content": ["__typename": "PullRequest", "title": "PR"]],
            ["id": "PVTI_closed", "isArchived": false, "fieldValueByName": NSNull(),
             "content": ["__typename": "Issue", "number": 3, "title": "Long closed", "state": "CLOSED", "closedAt": iso(-10 * 86_400),
                         "repository": ["name": "app"], "labels": ["nodes": []]]]
        ])
        let tasks = try await registry(transport).provider(for: Self.source).fetch(Self.source)

        #expect(tasks.map(\.id) == ["PVTI_issue", "PVTI_draft"])
        #expect(tasks[0].reference == "app#12" && tasks[0].tags == ["cat:hve"] && tasks[0].state == .open)
        #expect(tasks[0].url?.absoluteString == "https://github.com/octo-org/app/issues/12")
        #expect(tasks[1].state == .done && tasks[1].url == nil)

        let queries = transport.requests.map { body($0)["query"] as? String ?? "" }
        #expect(queries.count == 2)
        #expect(queries[0].contains("user(login: $login)"))
        #expect(queries[1].contains("organization(login: $login)"))
        let variables = try #require(body(transport.requests[1])["variables"] as? [String: Any])
        #expect(variables["login"] as? String == "octo-org" && variables["number"] as? Int == 5 && variables["field"] as? String == "Status")
    }

    @Test func completeSetsTheDoneOptionAndReopenTheTodoOne() async throws {
        let transport = Self.transport(items: [])
        let provider = try registry(transport).provider(for: Self.source)
        try await provider.complete(Self.source, taskID: "PVTI_issue")
        try await provider.reopen(Self.source, taskID: "PVTI_issue")

        let mutations = transport.requests.filter { (body($0)["query"] as? String ?? "").contains("mutation") }
        #expect(mutations.count == 2)
        let done = try #require(body(mutations[0])["variables"] as? [String: Any])
        #expect(done as NSDictionary == ["project": "PVT_1", "item": "PVTI_issue", "field": "FIELD_status", "option": "OPT_done"])
        #expect((body(mutations[1])["variables"] as? [String: Any])?["option"] as? String == "OPT_todo")
        #expect((body(mutations[0])["query"] as? String ?? "").contains("updateProjectV2ItemFieldValue"))
    }

    @Test func aMissingDoneOptionIsNamed() async throws {
        var source = Self.source
        source.settings["doneStatus"] = "Shipped"
        let provider = try registry(Self.transport(items: [])).provider(for: source)
        await #expect(throws: TaskProviderError.self) { try await provider.complete(source, taskID: "PVTI_issue") }
    }

    @Test func createAddsADraftIssue() async throws {
        let transport = FakeTransport { request in
            let text = body(request)["query"] as? String ?? ""
            if text.contains("addProjectV2DraftIssue") {
                return reply(200, ["data": ["addProjectV2DraftIssue": ["projectItem": ["id": "PVTI_new"]]]])
            }
            return reply(200, ["data": ["user": ["projectV2": Self.project(items: [])]]])
        }
        let task = try await registry(transport).provider(for: Self.source).create(Self.source, title: "Draft", tags: [])
        #expect(task.id == "PVTI_new" && task.title == "Draft" && task.state == .open)
        #expect(transport.requests.count == 2)
        #expect((body(transport.requests[1])["variables"] as? [String: Any])?["project"] as? String == "PVT_1")
    }
}

// MARK: - Sync

struct TaskSyncTests {
    private func setUp(sources: [TaskSourceConfig] = [workOS], seed: [MirroredTask]? = nil) throws -> TaskMirrorFiles {
        let files = TaskMirrorFiles(directory: directory())
        try files.saveConfig(TaskMirrorConfig(sources: sources))
        if let seed {
            try files.writeSourceFile(TaskSourceFile(
                source: workOS.name, provider: workOS.provider, syncedAt: now.addingTimeInterval(-3_600), tasks: seed
            ))
        }
        return files
    }

    /// GitHub with issue 7 open (or closed once a PATCH closed it) and anything POSTed.
    private func github(patch: Int = 200) -> FakeTransport {
        FakeTransport { request in
            switch request.httpMethod {
            case "PATCH":
                if patch == 200 { return reply(200, issue(7, "Seven")) }
                return reply(patch, ["message": "Validation Failed"])
            case "POST":
                return reply(201, issue(99, "Created", labels: ["cat:bat"]))
            default:
                guard query(request, "state") == "open" else { return reply(200, [Any]()) }
                return reply(200, [issue(7, "Seven"), issue(99, "Created", labels: ["cat:bat"])])
            }
        }
    }

    @Test func aCompletedActionIsSentAndRemoved() async throws {
        let files = try setUp(seed: [MirroredTask(id: "7", title: "Seven")])
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let action = TaskAction(kind: .complete, source: workOS.name, taskID: "7", createdAt: now)
        try files.enqueue(action)
        let transport = github()

        let summary = try await TaskSync(files: files, registry: registry(transport), now: { now }).run()

        #expect(summary.actions.map(\.outcome) == [.applied])
        #expect(files.loadOutbox().isEmpty)
        #expect(transport.requests.first?.httpMethod == "PATCH")
        #expect(summary.sources == [.init(name: "work-os", provider: "github-issues", tasks: 2, error: nil)])
        #expect(summary.ok)
        let file = try #require(files.loadSourceFile(workOS.name))
        #expect(file.syncedAt == now && file.lastError == nil)
    }

    @Test func aRefusedActionIsDroppedAndAFailingOneKept() async throws {
        for (status, outcome) in [(422, TaskSyncSummary.Outcome.dropped), (404, .dropped), (500, .kept)] {
            let files = try setUp(seed: [MirroredTask(id: "7", title: "Seven")])
            defer { try? FileManager.default.removeItem(at: files.directory) }
            try files.enqueue(TaskAction(kind: .complete, source: workOS.name, taskID: "7", createdAt: now))

            let summary = try await TaskSync(files: files, registry: registry(github(patch: status)), now: { now }).run()

            #expect(summary.actions.map(\.outcome) == [outcome], "HTTP \(status)")
            #expect(files.loadOutbox().count == (outcome == .kept ? 1 : 0), "HTTP \(status)")
            #expect(summary.actions.first?.error?.hasPrefix("GitHub said \(status)") == true)
            #expect(!summary.ok)
        }
    }

    @Test func anActionOlderThanAWeekIsDroppedEvenIfTheFailureIsPassing() async throws {
        let files = try setUp(seed: [MirroredTask(id: "7", title: "Seven")])
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try files.enqueue(TaskAction(kind: .complete, source: workOS.name, taskID: "7", createdAt: now.addingTimeInterval(-8 * 86_400)))
        let summary = try await TaskSync(files: files, registry: registry(github(patch: 503)), now: { now }).run()
        #expect(summary.actions.map(\.outcome) == [.dropped])
        #expect(files.loadOutbox().isEmpty)
    }

    @Test func aCreatedTaskTakesThePinItsActionAskedFor() async throws {
        let files = try setUp()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let priority = UUID()
        let action = TaskAction(kind: .create, source: workOS.name, title: "Created", tags: ["cat:bat"], pinTo: priority, createdAt: now)
        try files.enqueue(action)
        let transport = github()

        let summary = try await TaskSync(files: files, registry: registry(transport), now: { now }).run()

        #expect(summary.actions.first?.key == TaskKey(source: "work-os", id: "99"))
        #expect(files.loadPins().pins == [TaskKey(source: "work-os", id: "99"): priority])
        #expect(body(try #require(transport.requests.first)) as NSDictionary == ["title": "Created", "labels": ["cat:bat"]])
        #expect(files.board().items.contains { $0.key.id == "99" && $0.pinnedTo == priority && $0.pending == nil })
    }

    @Test func aPinOnThePendingKeyMovesToTheCreatedTask() async throws {
        let files = try setUp()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let priority = UUID()
        let action = TaskAction(kind: .create, source: workOS.name, title: "Created", createdAt: now)
        try files.enqueue(action)
        try files.pin(action.pendingKey, to: priority)

        _ = try await TaskSync(files: files, registry: registry(github()), now: { now }).run()

        #expect(files.loadPins().pins == [TaskKey(source: "work-os", id: "99"): priority])
    }

    @Test func aFailedFetchKeepsTheLastTasksAndSaysWhy() async throws {
        let seeded = [MirroredTask(id: "7", title: "Seven"), MirroredTask(id: "8", title: "Eight")]
        let files = try setUp(seed: seeded)
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let transport = FakeTransport { _ in reply(401, ["message": "Bad credentials"]) }

        let summary = try await TaskSync(files: files, registry: registry(transport), now: { now }).run()

        #expect(summary.sources.first?.error == "GitHub said 401: Bad credentials")
        let file = try #require(files.loadSourceFile(workOS.name))
        #expect(file.tasks == seeded)
        #expect(file.lastError == "GitHub said 401: Bad credentials")
        #expect(file.syncedAt == now.addingTimeInterval(-3_600))
    }

    @Test func aMissingTokenIsNamedAndAFirstFailureWritesAnEmptyFile() async throws {
        let files = try setUp()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let transport = github()
        let summary = try await TaskSync(
            files: files, registry: registry(transport, tokens: FakeTokens(refused: ["octo"])), now: { now }
        ).run()
        #expect(summary.sources.first?.error == "could not get a token for account octo: gh has no login for octo")
        #expect(transport.requests.isEmpty)
        let file = try #require(files.loadSourceFile(workOS.name))
        #expect(file.tasks.isEmpty && file.lastError != nil)
    }

    @Test func localActionsApplyWithoutAProvider() async throws {
        let files = try setUp(sources: [])
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let existing = try files.addLocal(title: "Existing", tags: [], now: now)
        let priority = UUID()
        let create = TaskAction(kind: .create, source: TaskMirror.localSource, title: "From the app", tags: ["home"], pinTo: priority, createdAt: now)
        try files.enqueue(create)
        try files.enqueue(TaskAction(kind: .complete, source: TaskMirror.localSource, taskID: existing.id, createdAt: now.addingTimeInterval(1)))

        let summary = try await TaskSync(files: files, registry: TaskProviderRegistry(providers: [:]), now: { now }).run()

        #expect(summary.actions.map(\.outcome) == [.applied, .applied])
        #expect(files.loadOutbox().isEmpty)
        let local = files.loadLocal().tasks
        #expect(local.first { $0.id == existing.id }?.state == .done)
        let created = try #require(local.first { $0.title == "From the app" })
        #expect(created.tags == ["home"])
        #expect(files.loadPins().pins[TaskKey(source: "local", id: created.id)] == priority)
    }

    @Test func localTasksDoneOverAWeekAgoArePruned() async throws {
        let files = try setUp(sources: [])
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let old = try files.addLocal(title: "Old", tags: [], now: now)
        try files.setLocal(id: old.id, state: .done, now: now.addingTimeInterval(-8 * 86_400))
        let recent = try files.addLocal(title: "Recent", tags: [], now: now)
        try files.setLocal(id: recent.id, state: .done, now: now.addingTimeInterval(-86_400))
        _ = try await TaskSync(files: files, registry: TaskProviderRegistry(providers: [:]), now: { now }).run()
        #expect(files.loadLocal().tasks.map(\.title) == ["Recent"])
    }

    @Test func aSecondSyncReturnsAtOnceWhileTheLockIsHeld() async throws {
        let files = try setUp()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let path = files.directory.appending(path: TaskSync.lockName).path
        let descriptor = open(path, O_CREAT | O_RDWR, 0o600)
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        let transport = github()

        let summary = try await TaskSync(files: files, registry: registry(transport), now: { now }).run()

        #expect(summary.alreadyRunning)
        #expect(transport.requests.isEmpty)
    }

    @Test func oneSourceCanBeSyncedAlone() async throws {
        let other = TaskSourceConfig(name: "other", provider: "github-issues", settings: ["repository": "octo/other"])
        let files = try setUp(sources: [workOS, other])
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let transport = github()
        let summary = try await TaskSync(files: files, registry: registry(transport), now: { now }).run(source: "work-os")
        #expect(summary.sources.map(\.name) == ["work-os"])
        #expect(transport.requests.allSatisfy { $0.url?.path.hasPrefix("/repos/octo/work-os/") == true })
    }
}

// MARK: - The bridge's verbs, through MCP

@MainActor
struct TaskToolTests {
    private func call(_ server: MCPServer, _ name: String, _ arguments: [String: Any] = [:]) async throws -> (isError: Bool, json: Any) {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments]]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let data = try #require(await server.handle(line)?.data(using: .utf8))
        let reply = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try #require(reply["result"] as? [String: Any])
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        let isError = result["isError"] as? Bool ?? true
        return (isError, isError ? text : try JSONSerialization.jsonObject(with: Data(text.utf8)))
    }

    private func server(_ directory: URL, transport: FakeTransport = FakeTransport { _ in reply(500, [:]) }, priority: UUID? = nil) -> MCPServer {
        MCPServer(
            read: {
                guard let priority else { throw BridgeError("no store") }
                return StoreReading(document: Self.emptyDocument, activePriorityID: priority.uuidString, standingPriorityIDs: [])
            },
            now: { now },
            openURL: { _ in },
            timeBlocks: TimeBlockStore(directory: directory.appending(path: "blocks")),
            tasks: TaskBridge(directory: directory, registry: registry(transport), now: { now }, lockWait: 0)
        )
    }

    private static var emptyDocument: StoreExport.Document {
        let json = #"""
        {"manifest": {"format": "focus-sentinel.data", "version": 1, "generatedAt": 0, "schemaVersion": 1, "fields": {}},
         "priorities": [], "contextItems": [], "rules": [], "sessions": [], "sessionTransitions": [],
         "activityEvents": [], "interventions": [], "questions": []}
        """#
        return try! JSONDecoder().decode(StoreExport.Document.self, from: Data(json.utf8))
    }

    @Test func aLocalTaskRoundTrips() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = server(dir)

        let created = try await call(server, "focus_create_task", ["title": "  Write the tests  ", "tags": ["home"]])
        #expect(!created.isError, "\(created.json)")
        let key = try #require((created.json as? [String: Any])?["key"] as? String)
        #expect(key.hasPrefix("local/"))

        let listed = try await call(server, "focus_list_tasks", ["tags": ["HOME"]])
        let items = try #require((listed.json as? [String: Any])?["items"] as? [[String: Any]])
        #expect(items.map { $0["title"] as? String } == ["Write the tests"])
        #expect(items.first?["key"] as? String == key)
        #expect(items.first?["pinned"] as? Bool == false)

        let completed = try await call(server, "focus_complete_task", ["key": key])
        #expect(!completed.isError, "\(completed.json)")
        let open = try await call(server, "focus_list_tasks")
        #expect(((open.json as? [String: Any])?["items"] as? [Any])?.isEmpty == true)
        let all = try await call(server, "focus_list_tasks", ["include_done": true])
        #expect(((all.json as? [String: Any])?["items"] as? [[String: Any]])?.first?["state"] as? String == "done")
    }

    @Test func pinningToTheCurrentPriorityNeedsOne() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let refused = try await call(server(dir), "focus_create_task", ["title": "x", "pin_to_current_priority": true])
        #expect(refused.isError)

        let priority = UUID()
        let pinned = server(dir, priority: priority)
        let created = try await call(pinned, "focus_create_task", ["title": "Subtask", "pin_to_current_priority": true])
        #expect(!created.isError, "\(created.json)")
        let listed = try await call(pinned, "focus_list_tasks", ["pinned_only": true])
        let items = try #require((listed.json as? [String: Any])?["items"] as? [[String: Any]])
        #expect(items.map { $0["title"] as? String } == ["Subtask"])
        #expect(items.first?["pinnedToCurrentPriority"] as? Bool == true)
    }

    @Test func aDefaultSourceTakesNewTasksAndCompletingReachesGitHub() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let transport = FakeTransport { request in
            switch request.httpMethod {
            case "POST": return reply(201, issue(99, "Upstream"))
            case "PATCH": return reply(200, issue(99, "Upstream", closedAgo: 0))
            default: return reply(200, query(request, "state") == "open" ? [issue(99, "Upstream")] : [])
            }
        }
        let server = server(dir, transport: transport)

        let added = try await call(server, "focus_add_task_source", [
            "name": "work-os", "provider": "github-issues", "settings": ["repository": "octo/work-os"], "make_default": true
        ])
        #expect(!added.isError, "\(added.json)")
        let sources = try #require(try await call(server, "focus_list_task_sources").json as? [[String: Any]])
        #expect(sources.first?["isDefaultForCreate"] as? Bool == true)

        let created = try await call(server, "focus_create_task", ["title": "Upstream"])
        #expect((created.json as? [String: Any])?["key"] as? String == "work-os/99")
        #expect((created.json as? [String: Any])?["pending"] as? Bool == false)

        let completed = try await call(server, "focus_complete_task", ["key": "work-os/99"])
        #expect((completed.json as? [String: Any])?["pending"] as? Bool == false, "\(completed.json)")
        let patch = try #require(transport.requests.first { $0.httpMethod == "PATCH" })
        #expect(patch.url?.path == "/repos/octo/work-os/issues/99")

        let removed = try await call(server, "focus_remove_task_source", ["name": "work-os"])
        #expect(!removed.isError)
        let after = try await call(server, "focus_create_task", ["title": "Back to local"])
        #expect(((after.json as? [String: Any])?["key"] as? String)?.hasPrefix("local/") == true)
    }

    @Test func anUnreachableSourceQueuesTheChange() async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = server(dir) // every request answers 500
        _ = try await call(server, "focus_add_task_source", ["name": "work-os", "provider": "github-issues", "settings": ["repository": "octo/work-os"]])
        let created = try await call(server, "focus_create_task", ["title": "Later", "source": "work-os"])
        let json = try #require(created.json as? [String: Any])
        #expect(json["pending"] as? Bool == true)
        #expect((json["key"] as? String)?.hasPrefix("work-os/pending-") == true)
        #expect(TaskMirrorFiles(directory: dir).loadOutbox().count == 1)
        let listed = try await call(server, "focus_list_tasks")
        #expect(((listed.json as? [String: Any])?["items"] as? [[String: Any]])?.first?["pending"] as? String == "create")
    }

    @Test(arguments: [
        ["name": "x", "provider": "github-issues", "settings": ["repository": "not-a-repo"]],
        ["name": "x", "provider": "github-project", "settings": ["owner": "octo"]],
        ["name": "x", "provider": "jira", "settings": [:] as [String: String]],
        ["name": "local", "provider": "github-issues", "settings": ["repository": "a/b"]]
    ] as [[String: any Sendable]])
    func badSourcesAreRefused(_ arguments: [String: any Sendable]) async throws {
        let dir = directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reply = try await call(server(dir), "focus_add_task_source", arguments)
        #expect(reply.isError)
        #expect(TaskMirrorFiles(directory: dir).loadConfig().sources.isEmpty)
    }

    @Test func theDefaultDirectorySitsBesideTheStore() {
        #expect(TaskBridge.defaultDirectory(environment: ["FOCUS_STORE": "/tmp/s/FocusSentinel.store"]).path == "/tmp/s/TaskMirror")
        #expect(TaskBridge.defaultDirectory(environment: ["FOCUS_TASK_MIRROR": "/tmp/tm"]).path == "/tmp/tm")
    }
}
