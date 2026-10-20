import FocusCore
import Foundation

/// **A GitHub Projects (v2) board as tasks** (`github-project`).
///
/// Settings: `owner` (a user or organisation login), `number` (the project's number), optional
/// `account` (a `gh` login), optional `doneStatus` (default "Done"), optional `reopenStatus`
/// (default an option called "Todo" or "To do", else the first option that is not done), optional
/// `statusField` (default "Status"). The token needs the `read:project` scope to read and
/// `project` to write.
///
/// Items are the board's issues and draft issues; pull requests and archived items are left out.
/// An item is done when its status is the done status or its issue is closed, and done items are
/// kept for three days. Completing sets the status to the done option; reopening sets it back;
/// creating adds a draft issue, which carries no labels.
public struct GitHubProjectProvider: TaskProvider {
    public static let maximumPages = 10
    public static let pageSize = 100
    public static let recentlyDone: TimeInterval = 3 * 24 * 60 * 60

    let client: GitHubClient
    let now: @Sendable () -> Date

    public init(client: GitHubClient, now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    struct Settings {
        let owner: String
        let number: Int
        let account: String?
        let doneStatus: String
        let reopenStatus: String?
        let statusField: String

        init(_ source: TaskSourceConfig) throws {
            let owner = (source.settings["owner"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !owner.isEmpty else { throw TaskProviderError.invalidSetting("a project source needs its owner's login") }
            guard let number = Int((source.settings["number"] ?? "").trimmingCharacters(in: .whitespaces)), number > 0 else {
                throw TaskProviderError.invalidSetting("number must be the project's number, not \"\(source.settings["number"] ?? "")\"")
            }
            self.owner = owner
            self.number = number
            account = source.settings["account"]?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            doneStatus = source.settings["doneStatus"]?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Done"
            reopenStatus = source.settings["reopenStatus"]?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            statusField = source.settings["statusField"]?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Status"
        }
    }

    struct StatusField {
        let id: String
        let options: [(id: String, name: String)]

        func option(named name: String) -> (id: String, name: String)? {
            options.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    struct Project {
        let id: String
        let status: StatusField?
        let raw: [String: Any]
    }

    // MARK: - TaskProvider

    public func fetch(_ source: TaskSourceConfig) async throws -> [MirroredTask] {
        let settings = try Settings(source)
        let cutoff = now().addingTimeInterval(-Self.recentlyDone)
        var tasks: [MirroredTask] = []
        var cursor: String?
        var ownerKind: String?
        for _ in 0..<Self.maximumPages {
            let (project, kind) = try await lookUp(settings, items: true, cursor: cursor, ownerKind: ownerKind)
            ownerKind = kind
            let items = project.raw["items"] as? [String: Any]
            for node in (items?["nodes"] as? [[String: Any]]) ?? [] {
                if let task = Self.task(from: node, doneStatus: settings.doneStatus), task.state == .open || (task.completedAt ?? .distantPast) >= cutoff {
                    tasks.append(task)
                }
            }
            let pageInfo = items?["pageInfo"] as? [String: Any]
            guard pageInfo?["hasNextPage"] as? Bool == true, let next = pageInfo?["endCursor"] as? String else { break }
            cursor = next
        }
        return tasks
    }

    public func complete(_ source: TaskSourceConfig, taskID: String) async throws {
        let settings = try Settings(source)
        let (project, _) = try await lookUp(settings, items: false)
        let status = try Self.status(of: project, settings: settings)
        guard let done = status.option(named: settings.doneStatus) else {
            throw TaskProviderError.invalidSetting("project #\(settings.number)'s \(settings.statusField) field has no option \"\(settings.doneStatus)\"")
        }
        try await setStatus(project: project.id, item: taskID, field: status.id, option: done.id, account: settings.account)
    }

    public func reopen(_ source: TaskSourceConfig, taskID: String) async throws {
        let settings = try Settings(source)
        let (project, _) = try await lookUp(settings, items: false)
        let status = try Self.status(of: project, settings: settings)
        let option: (id: String, name: String)?
        if let named = settings.reopenStatus {
            option = status.option(named: named)
            guard option != nil else {
                throw TaskProviderError.invalidSetting("project #\(settings.number)'s \(settings.statusField) field has no option \"\(named)\"")
            }
        } else {
            option = status.option(named: "Todo") ?? status.option(named: "To do")
                ?? status.options.first { $0.name.caseInsensitiveCompare(settings.doneStatus) != .orderedSame }
        }
        guard let option else {
            throw TaskProviderError.invalidSetting("project #\(settings.number)'s \(settings.statusField) field has no option to reopen to")
        }
        try await setStatus(project: project.id, item: taskID, field: status.id, option: option.id, account: settings.account)
    }

    public func create(_ source: TaskSourceConfig, title: String, tags: [String]) async throws -> MirroredTask {
        let settings = try Settings(source)
        let (project, _) = try await lookUp(settings, items: false)
        let data = try await client.graphQL(
            """
            mutation($project: ID!, $title: String!) {
              addProjectV2DraftIssue(input: {projectId: $project, title: $title}) { projectItem { id } }
            }
            """,
            variables: ["project": project.id, "title": title],
            account: settings.account
        )
        guard let id = ((data["addProjectV2DraftIssue"] as? [String: Any])?["projectItem"] as? [String: Any])?["id"] as? String else {
            throw TaskProviderError.malformedResponse("GitHub did not name the new project item")
        }
        return MirroredTask(id: id, title: GitHubClient.title(title), updatedAt: now())
    }

    // MARK: - GraphQL

    private func setStatus(project: String, item: String, field: String, option: String, account: String?) async throws {
        _ = try await client.graphQL(
            """
            mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
              updateProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item, fieldId: $field, value: {singleSelectOptionId: $option}}) {
                projectV2Item { id }
              }
            }
            """,
            variables: ["project": project, "item": item, "field": field, "option": option],
            account: account
        )
    }

    /// The project, under the owner as a user and then as an organisation (or straight to the
    /// kind an earlier page found).
    private func lookUp(_ settings: Settings, items: Bool, cursor: String? = nil, ownerKind: String? = nil) async throws -> (Project, String) {
        for kind in ownerKind.map({ [$0] }) ?? ["user", "organization"] {
            var variables: [String: Any] = ["login": settings.owner, "number": settings.number, "field": settings.statusField]
            if items { variables["cursor"] = cursor ?? NSNull() }
            let data = try await client.graphQL(
                Self.query(owner: kind, items: items),
                variables: variables,
                account: settings.account,
                tolerating: ["NOT_FOUND"]
            )
            guard let raw = (data[kind] as? [String: Any])?["projectV2"] as? [String: Any], let id = raw["id"] as? String else { continue }
            return (Project(id: id, status: Self.statusField(raw["field"]), raw: raw), kind)
        }
        throw TaskProviderError.invalidSetting(
            "no project #\(settings.number) under \(settings.owner) that this account can see (the token needs the read:project scope)"
        )
    }

    static func query(owner: String, items: Bool) -> String {
        let itemsFragment = items ? """
                items(first: \(pageSize), after: $cursor) {
                  pageInfo { hasNextPage endCursor }
                  nodes {
                    id
                    isArchived
                    updatedAt
                    fieldValueByName(name: $field) { ... on ProjectV2ItemFieldSingleSelectValue { name optionId } }
                    content {
                      __typename
                      ... on Issue {
                        number title url state closedAt updatedAt
                        repository { name }
                        labels(first: 50) { nodes { name } }
                      }
                      ... on DraftIssue { title updatedAt }
                    }
                  }
                }
            """ : ""
        return """
            query($login: String!, $number: Int!, $field: String!\(items ? ", $cursor: String" : "")) {
              \(owner)(login: $login) {
                projectV2(number: $number) {
                  id
                  field(name: $field) { ... on ProjectV2SingleSelectField { id name options { id name } } }
            \(itemsFragment)
                }
              }
            }
            """
    }

    static func statusField(_ raw: Any?) -> StatusField? {
        guard let field = raw as? [String: Any], let id = field["id"] as? String,
              let options = field["options"] as? [[String: Any]] else { return nil }
        return StatusField(id: id, options: options.compactMap { option in
            guard let id = option["id"] as? String, let name = option["name"] as? String else { return nil }
            return (id, name)
        })
    }

    static func status(of project: Project, settings: Settings) throws -> StatusField {
        guard let status = project.status else {
            throw TaskProviderError.invalidSetting("project #\(settings.number) has no single-select field called \"\(settings.statusField)\"")
        }
        return status
    }

    /// One item node as a task, or `nil` for an archived item, a pull request or an item this
    /// account cannot see.
    static func task(from node: [String: Any], doneStatus: String) -> MirroredTask? {
        guard let id = node["id"] as? String, node["isArchived"] as? Bool != true,
              let content = node["content"] as? [String: Any] else { return nil }
        let status = (node["fieldValueByName"] as? [String: Any])?["name"] as? String
        let statusDone = status?.caseInsensitiveCompare(doneStatus) == .orderedSame
        let itemUpdated = date(node["updatedAt"])
        switch content["__typename"] as? String {
        case "Issue":
            guard let title = content["title"] as? String else { return nil }
            let closed = (content["state"] as? String)?.uppercased() == "CLOSED"
            let done = closed || statusDone
            let repository = (content["repository"] as? [String: Any])?["name"] as? String
            let labels = ((content["labels"] as? [String: Any])?["nodes"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let updated = [itemUpdated, date(content["updatedAt"])].compactMap(\.self).max()
            return MirroredTask(
                id: id,
                title: GitHubClient.title(title),
                url: (content["url"] as? String).flatMap(URL.init(string:)),
                reference: (content["number"] as? Int).map { "\(repository ?? "issue")#\($0)" },
                tags: labels,
                state: done ? .done : .open,
                updatedAt: updated,
                completedAt: done ? (closed ? date(content["closedAt"]) : nil) ?? updated : nil
            )
        case "DraftIssue":
            guard let title = content["title"] as? String else { return nil }
            let updated = [itemUpdated, date(content["updatedAt"])].compactMap(\.self).max()
            return MirroredTask(
                id: id,
                title: GitHubClient.title(title),
                state: statusDone ? .done : .open,
                updatedAt: updated,
                completedAt: statusDone ? updated : nil
            )
        default:
            return nil
        }
    }

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}
