import FocusCore
import Foundation

/// **The HTTP half of every GitHub provider**: headers, auth, and errors in GitHub's own words.
public struct GitHubClient: Sendable {
    public static let apiBase = URL(string: "https://api.github.com")!
    static let service = "GitHub"

    public let transport: any HTTPTransport
    public let tokens: any GitHubTokenProviding

    public init(transport: any HTTPTransport, tokens: any GitHubTokenProviding) {
        self.transport = transport
        self.tokens = tokens
    }

    /// A REST call. `path` is relative to the API root and may carry a query.
    public func rest(_ method: String, _ path: String, body: [String: Any]? = nil, account: String?) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: Self.apiBase)?.absoluteURL else {
            throw TaskProviderError.invalidSetting("not a GitHub API path: \(path)")
        }
        var request = try await authorised(URLRequest(url: url), account: account)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw TaskProviderError.http(service: Self.service, status: response.statusCode, message: Self.message(in: data))
        }
        return (data, response)
    }

    /// A GraphQL call. Returns `data`; errors in the body are thrown with their GitHub type, unless
    /// `tolerating` names the type (a `user(login:)` lookup on an organisation answers NOT_FOUND).
    public func graphQL(_ query: String, variables: [String: Any], account: String?, tolerating: Set<String> = []) async throws -> [String: Any] {
        var request = try await authorised(URLRequest(url: Self.apiBase.appending(path: "graphql")), account: account)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables], options: [.sortedKeys])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw TaskProviderError.http(service: Self.service, status: response.statusCode, message: Self.message(in: data))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TaskProviderError.malformedResponse("GitHub's GraphQL answer was not JSON")
        }
        let errors = (object["errors"] as? [[String: Any]]) ?? []
        if let first = errors.first(where: { !tolerating.contains(($0["type"] as? String) ?? "") }) {
            throw TaskProviderError.graphQL(type: first["type"] as? String, message: (first["message"] as? String) ?? "an unnamed error")
        }
        return (object["data"] as? [String: Any]) ?? [:]
    }

    private func authorised(_ request: URLRequest, account: String?) async throws -> URLRequest {
        var request = request
        let token = try await tokens.token(account: account)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("focus-bridge", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as TaskProviderError {
            throw error
        } catch {
            throw TaskProviderError.unreachable(service: Self.service, reason: error.localizedDescription)
        }
    }

    /// GitHub's `message`, with the first validation error's detail when there is one.
    static func message(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(decoding: data.prefix(200), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var message = (object["message"] as? String) ?? ""
        if let detail = (object["errors"] as? [[String: Any]])?.first,
           let text = (detail["message"] as? String) ?? (detail["code"] as? String).map({ "\($0) \((detail["field"] as? String) ?? "")" }) {
            message += message.isEmpty ? text : " (\(text.trimmingCharacters(in: .whitespaces)))"
        }
        return message
    }

    /// `owner/name`, checked.
    static func repository(_ source: TaskSourceConfig) throws -> (owner: String, name: String) {
        let text = (source.settings["repository"] ?? "").trimmingCharacters(in: .whitespaces)
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(safe.contains) }) else {
            throw TaskProviderError.invalidSetting("repository must be owner/name, not \"\(text)\"")
        }
        return (parts[0], parts[1])
    }

    /// A title from GitHub as a task carries it: one line, at most the mirror's length.
    static func title(_ text: String) -> String {
        let flat = text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return String((flat.isEmpty ? "(untitled)" : flat).prefix(TaskMirror.maximumTitleLength))
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
