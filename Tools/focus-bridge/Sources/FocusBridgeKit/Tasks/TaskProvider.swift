import FocusCore
import Foundation

/// **One to-do system the bridge can mirror** (task mirror).
///
/// A provider is stateless: every call is given the source's config, so one instance serves every
/// source that names it and nothing is cached between processes. Adding a system is one type that
/// conforms to this and one line in `TaskProviderRegistry.standard`; `TaskProviderKind` in
/// FocusCore lists the names the app's Settings pane offers.
public protocol TaskProvider: Sendable {
    /// Every task the source holds that the board should show: the open ones, and those finished
    /// recently enough that a person may want to see or reopen them.
    func fetch(_ source: TaskSourceConfig) async throws -> [MirroredTask]
    func complete(_ source: TaskSourceConfig, taskID: String) async throws
    func reopen(_ source: TaskSourceConfig, taskID: String) async throws
    /// Creates a task upstream and returns it as the source now names it.
    func create(_ source: TaskSourceConfig, title: String, tags: [String]) async throws -> MirroredTask
}

/// **The providers this bridge knows, by the name a source's config gives.**
public struct TaskProviderRegistry: Sendable {
    public var providers: [String: any TaskProvider]

    public init(providers: [String: any TaskProvider]) {
        self.providers = providers
    }

    /// The shipping set: GitHub issues and GitHub Projects (v2), sharing one transport and one
    /// token lookup (which remembers a token for the life of this process only).
    public static func standard(
        transport: any HTTPTransport = URLSessionTransport(),
        tokens: any GitHubTokenProviding = GitHubCLITokenProvider()
    ) -> TaskProviderRegistry {
        let client = GitHubClient(transport: transport, tokens: CachedGitHubTokens(tokens))
        return TaskProviderRegistry(providers: [
            TaskProviderKind.githubIssues.rawValue: GitHubIssuesProvider(client: client),
            TaskProviderKind.githubProject.rawValue: GitHubProjectProvider(client: client)
        ])
    }

    public func provider(for source: TaskSourceConfig) throws -> any TaskProvider {
        guard let provider = providers[source.provider] else {
            throw TaskProviderError.unknownProvider(source.provider)
        }
        return provider
    }
}

/// Why a provider could not do what it was asked, in words the board can show.
public enum TaskProviderError: Error, Equatable, CustomStringConvertible, Sendable {
    /// The service answered with an HTTP error.
    case http(service: String, status: Int, message: String)
    /// The service answered 200 with errors in the body (GraphQL), by error type.
    case graphQL(type: String?, message: String)
    case token(account: String?, reason: String)
    case unreachable(service: String, reason: String)
    case notFound(String)
    case invalidSetting(String)
    case unknownProvider(String)
    case malformedResponse(String)

    public var description: String {
        switch self {
        case .http(let service, let status, let message):
            message.isEmpty ? "\(service) said \(status)" : "\(service) said \(status): \(message)"
        case .graphQL(_, let message):
            "GitHub said: \(message)"
        case .token(let account, let reason):
            if let account { "could not get a token for account \(account): \(reason)" } else { "could not get a GitHub token: \(reason)" }
        case .unreachable(let service, let reason):
            "could not reach \(service): \(reason)"
        case .notFound(let message), .invalidSetting(let message), .malformedResponse(let message):
            message
        case .unknownProvider(let provider):
            TaskMirrorError.unknownProvider(provider).description
        }
    }

    /// Whether retrying can never succeed, so an outbox action asking for it is dropped: the task
    /// is gone (404, 410) or the request will never be accepted (422).
    public var isPermanent: Bool {
        switch self {
        case .http(_, let status, _): [404, 410, 422].contains(status)
        case .graphQL(let type, _): type == "NOT_FOUND" || type == "UNPROCESSABLE"
        case .notFound: true
        default: false
        }
    }

    /// Any error, as a short sentence for a source file's `lastError`.
    public static func describe(_ error: any Error) -> String {
        if let error = error as? TaskProviderError { return error.description }
        if let error = error as? TaskMirrorError { return error.description }
        if let error = error as? BridgeError { return error.description }
        return error.localizedDescription
    }

    public static func isPermanent(_ error: any Error) -> Bool {
        (error as? TaskProviderError)?.isPermanent ?? false
    }
}
