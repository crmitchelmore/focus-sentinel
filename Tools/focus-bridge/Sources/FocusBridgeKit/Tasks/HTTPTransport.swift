import Foundation

/// **How the bridge talks HTTP**, behind a protocol so the tests answer for the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real transport: an ephemeral `URLSession` (no cookies, no cache on disk).
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 20) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 3
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TaskProviderError.malformedResponse("\(request.url?.host() ?? "the server") did not answer over HTTP")
        }
        return (data, http)
    }
}

/// **Where a GitHub token comes from**, behind a protocol so tests never run `gh`.
public protocol GitHubTokenProviding: Sendable {
    /// A token for `account` (a `gh` login), or for the default account when `nil`.
    func token(account: String?) async throws -> String
}

/// **Tokens from the GitHub CLI.**
///
/// With an account: `gh auth token --user <account>`. Without one: `FOCUS_GITHUB_TOKEN` if set,
/// else `gh auth token`. `GH_TOKEN` and `GITHUB_TOKEN` are removed from `gh`'s environment,
/// because `gh` would otherwise answer with them whichever account was asked for. The token is
/// never logged or written anywhere.
public struct GitHubCLITokenProvider: GitHubTokenProviding {
    public let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func token(account: String?) async throws -> String {
        let account = account?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        if account == nil, let token = environment["FOCUS_GITHUB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return token
        }
        guard let gh = Self.locateGH(environment: environment) else {
            throw TaskProviderError.token(account: account, reason: "the GitHub CLI (gh) is not installed or not on PATH")
        }
        var arguments = ["auth", "token"]
        if let account { arguments += ["--user", account] }
        let (status, output, errorOutput) = try await Self.run(gh, arguments: arguments, environment: Self.childEnvironment(environment))
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0, !token.isEmpty else {
            let reason = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first?.nilIfEmpty
                ?? "gh auth token exited with status \(status)"
            throw TaskProviderError.token(account: account, reason: reason)
        }
        return token
    }

    /// The parent's environment without the variables that would override `--user`.
    public static func childEnvironment(_ environment: [String: String]) -> [String: String] {
        var child = environment
        child["GH_TOKEN"] = nil
        child["GITHUB_TOKEN"] = nil
        child["GH_ENTERPRISE_TOKEN"] = nil
        child["GITHUB_ENTERPRISE_TOKEN"] = nil
        child["GH_PROMPT_DISABLED"] = "1"
        child["NO_COLOR"] = "1"
        return child
    }

    /// `gh` on `PATH`, then where Homebrew puts it: an app launched from the Dock has a short PATH.
    public static func locateGH(environment: [String: String]) -> URL? {
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in path + ["/opt/homebrew/bin", "/usr/local/bin"] where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: directory).appending(path: "gh", directoryHint: .notDirectory)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> (Int32, String, String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: TaskProviderError.token(account: nil, reason: "could not run gh: \(error.localizedDescription)"))
            }
        }
        // `gh auth token` writes a line or two, well inside a pipe's buffer, so reading after exit
        // cannot deadlock.
        let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (status, out, err)
    }
}

/// Remembers each account's token for the life of one process, so a sync of ten pages runs `gh`
/// once. Nothing is written down.
public actor CachedGitHubTokens: GitHubTokenProviding {
    private let base: any GitHubTokenProviding
    private var tokens: [String: String] = [:]

    public init(_ base: any GitHubTokenProviding) {
        self.base = base
    }

    public func token(account: String?) async throws -> String {
        let key = account ?? ""
        if let token = tokens[key] { return token }
        let token = try await base.token(account: account)
        tokens[key] = token
        return token
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
