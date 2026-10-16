import FocusClassify
import FocusCore
import FocusModel
import Foundation
import os

/// **The one file in this application's own code that opens a network connection**, and only
/// when someone switched it on (`RemoteJudgeConfiguration`).
///
/// Microsoft's Decision-1 (System One) answers the model rung's question — *is this window part
/// of the work the person wrote down?* — from the priority sentence and what the frontmost window
/// holds. The ContextSpike (`Tools/ContextSpike/README.md`) measured it against the same
/// forty-five cells the on-device model failed: with the window's content it rescued all fifteen
/// holds and was seduced by none, at about 0.2 s a judgement.
///
/// ## What this does not change
///
/// * **It can only rescue.** `ModelAnswer` has no unrelated case; a low score is a decline,
///   and the deterministic answer stands. The judge cannot make the app speak, only keep it
///   quiet about something the person's own work needs.
/// * **It never reads a window itself.** `RemoteJudgeContextSource` hands it a window only when
///   the frontmost application is the one asked about and e03's `SensitivityGate` cleared it,
///   so a password manager or a private window is never sent.
/// * **It is off the classification path.** `FocusModelRung` calls it from a detached task and
///   caches the answer, per priority revision and per selected page or item, for the session.
///   A failure of any kind is `.refused`, which is silence.
///
/// `check-boundaries.sh` names this file as the single exception to its repo-wide networking
/// scan, so a second file that opens a connection fails the gate.
struct DecisionOneJudge: ModelJudging {
    /// A request that takes longer than this is not worth waiting for: the dwell before the app
    /// would speak is forty-five seconds, and the spike's p95 was under a second.
    static let requestTimeout: TimeInterval = 10

    let configuration: RemoteJudgeConfiguration
    let source: RemoteJudgeContextSource
    let tokens: AzureCLITokenProvider
    private let session: URLSession
    private let logger = Logger(subsystem: FocusStore.bundleIdentifier, category: "RemoteJudge")

    init(
        configuration: RemoteJudgeConfiguration,
        source: RemoteJudgeContextSource,
        tokens: AzureCLITokenProvider = AzureCLITokenProvider()
    ) {
        self.configuration = configuration
        self.source = source
        self.tokens = tokens
        // Ephemeral: no cookie jar, no URL cache, nothing written to disk.
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = Self.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = Self.requestTimeout
        self.session = URLSession(configuration: sessionConfiguration)
    }

    /// Configured is available. Whether a window can be read is decided per request, because
    /// the composition reads availability once, at launch.
    func availability() -> ModelTierAvailability { .available }

    func judge(_ request: ModelRequest) async -> ModelAnswer {
        guard let input = await source.input(for: request) else { return .decline(.refused) }
        guard let body = try? DecisionOneProtocol.body(
            deployment: configuration.deployment,
            task: input.task,
            window: input.window
        ) else { return .decline(.refused) }

        // One retry, and only after a 401 with a refreshed token: an expired token is the one
        // failure a second attempt can repair.
        for attempt in 0..<2 {
            guard let token = await tokens.token(refresh: attempt > 0) else {
                logger.error("no access token: is the Azure CLI installed and signed in?")
                return .decline(.refused)
            }
            var http = URLRequest(url: configuration.endpoint.appending(path: DecisionOneProtocol.path))
            http.httpMethod = "POST"
            http.timeoutInterval = Self.requestTimeout
            http.setValue("application/json", forHTTPHeaderField: "Content-Type")
            http.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            http.httpBody = body

            guard let (data, response) = try? await session.data(for: http),
                  let status = (response as? HTTPURLResponse)?.statusCode
            else {
                logger.error("request failed before a response")
                return .decline(.refused)
            }
            if status == 401, attempt == 0 { continue }
            guard status == 200, let probabilities = DecisionOneProtocol.probabilities(from: data) else {
                logger.error("unexpected response: HTTP \(status, privacy: .public)")
                return .decline(.refused)
            }
            return DecisionOneProtocol.answer(from: probabilities, threshold: configuration.threshold)
        }
        return .decline(.refused)
    }
}

/// A Microsoft Entra access token for Azure AI services, from the signed-in Azure CLI.
///
/// The resource the spike provisioned disables key authentication, and an Entra token is the
/// credential that leaves nothing to store: the CLI holds the sign-in, this asks it for a
/// short-lived token, keeps it in memory, and asks again before it expires or after a 401.
actor AzureCLITokenProvider {
    static let resource = "https://cognitiveservices.azure.com"
    /// Entra tokens live an hour or more; refreshing at forty-five minutes never sends a stale one.
    static let lifetime: Duration = .seconds(45 * 60)
    /// Where Homebrew and the official installer put the CLI. A Finder-launched app has no
    /// shell `PATH`, so the binary is looked for rather than resolved.
    static let candidates = ["/opt/homebrew/bin/az", "/usr/local/bin/az", "/usr/bin/az"]

    private var cached: (token: String, expires: ContinuousClock.Instant)?

    func token(refresh: Bool) async -> String? {
        if !refresh, let cached, ContinuousClock.now < cached.expires { return cached.token }
        guard let fresh = await Self.askTheCLI() else {
            cached = nil
            return nil
        }
        cached = (fresh, ContinuousClock.now + Self.lifetime)
        return fresh
    }

    private static func askTheCLI() async -> String? {
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:))
        else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "account", "get-access-token", "--resource", resource,
            "--query", "accessToken", "--output", "tsv",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let token = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: finished.terminationStatus == 0 && !token.isEmpty ? token : nil)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
    }
}
