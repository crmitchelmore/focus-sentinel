import FocusCore
import Foundation

/// **A GitHub repository's issues as tasks** (`github-issues`).
///
/// Settings: `repository` (`owner/name`), optional `account` (a `gh` login). Fetches the open
/// issues and those closed in the last three days, leaving pull requests out. Completing closes
/// the issue as completed; reopening opens it; creating files a new issue with the given labels.
public struct GitHubIssuesProvider: TaskProvider {
    public static let maximumPages = 10
    public static let pageSize = 100
    public static let recentlyClosed: TimeInterval = 3 * 24 * 60 * 60

    let client: GitHubClient
    let now: @Sendable () -> Date

    public init(client: GitHubClient, now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func fetch(_ source: TaskSourceConfig) async throws -> [MirroredTask] {
        let repository = try GitHubClient.repository(source)
        let base = "/repos/\(repository.owner)/\(repository.name)/issues"
        let open = try await pages(base + "?state=open", account: source.settings["account"])
        let cutoff = now().addingTimeInterval(-Self.recentlyClosed)
        let since = ISO8601DateFormatter().string(from: cutoff)
        let closed = try await pages(base + "?state=closed&since=\(since)", account: source.settings["account"])
            .filter { ($0.closedAt ?? .distantPast) >= cutoff }
        var seen = Set<Int>()
        return (open + closed).compactMap { issue -> MirroredTask? in
            guard !issue.isPullRequest, seen.insert(issue.number).inserted else { return nil }
            return issue.task(repository: repository.name)
        }
    }

    public func complete(_ source: TaskSourceConfig, taskID: String) async throws {
        try await patch(source, taskID: taskID, body: ["state": "closed", "state_reason": "completed"])
    }

    public func reopen(_ source: TaskSourceConfig, taskID: String) async throws {
        try await patch(source, taskID: taskID, body: ["state": "open"])
    }

    public func create(_ source: TaskSourceConfig, title: String, tags: [String]) async throws -> MirroredTask {
        let repository = try GitHubClient.repository(source)
        var body: [String: Any] = ["title": title]
        if !tags.isEmpty { body["labels"] = tags }
        let (data, _) = try await client.rest(
            "POST", "/repos/\(repository.owner)/\(repository.name)/issues", body: body, account: source.settings["account"]
        )
        guard let issue = try? GitHubClient.decoder().decode(Issue.self, from: data) else {
            throw TaskProviderError.malformedResponse("GitHub's answer to creating an issue was not an issue")
        }
        return issue.task(repository: repository.name)
    }

    private func patch(_ source: TaskSourceConfig, taskID: String, body: [String: Any]) async throws {
        let repository = try GitHubClient.repository(source)
        guard let number = Int(taskID), number > 0 else { throw TaskProviderError.notFound("\"\(taskID)\" is not an issue number") }
        _ = try await client.rest(
            "PATCH", "/repos/\(repository.owner)/\(repository.name)/issues/\(number)", body: body, account: source.settings["account"]
        )
    }

    private func pages(_ path: String, account: String?) async throws -> [Issue] {
        var issues: [Issue] = []
        for page in 1...Self.maximumPages {
            let (data, _) = try await client.rest("GET", "\(path)&per_page=\(Self.pageSize)&page=\(page)", account: account)
            guard let batch = try? GitHubClient.decoder().decode([Issue].self, from: data) else {
                throw TaskProviderError.malformedResponse("GitHub's issue list was not a list of issues")
            }
            issues += batch
            if batch.count < Self.pageSize { break }
        }
        return issues
    }

    struct Issue: Decodable {
        struct Label: Decodable { let name: String }
        let number: Int
        let title: String
        let htmlURL: URL?
        let state: String
        let labels: [Label]
        let updatedAt: Date?
        let closedAt: Date?
        let isPullRequest: Bool

        enum CodingKeys: String, CodingKey {
            case number, title, state, labels
            case htmlURL = "html_url"
            case updatedAt = "updated_at"
            case closedAt = "closed_at"
            case pullRequest = "pull_request"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            number = try container.decode(Int.self, forKey: .number)
            title = try container.decode(String.self, forKey: .title)
            htmlURL = try container.decodeIfPresent(URL.self, forKey: .htmlURL)
            state = try container.decode(String.self, forKey: .state)
            labels = (try? container.decodeIfPresent([Label].self, forKey: .labels)) ?? []
            updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt)
            closedAt = try? container.decodeIfPresent(Date.self, forKey: .closedAt)
            isPullRequest = container.contains(.pullRequest) && !((try? container.decodeNil(forKey: .pullRequest)) ?? true)
        }

        func task(repository: String) -> MirroredTask {
            let done = state == "closed"
            return MirroredTask(
                id: String(number),
                title: GitHubClient.title(title),
                url: htmlURL,
                reference: "\(repository)#\(number)",
                tags: labels.map(\.name),
                state: done ? .done : .open,
                updatedAt: updatedAt,
                completedAt: done ? closedAt : nil
            )
        }
    }
}
