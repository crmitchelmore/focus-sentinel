import FocusClassify
import Foundation

/// **Where the remote judge is, and how sure it must be.** Whether it runs at all is
/// `RemoteJudgeSwitch`, which the person sets in Settings ▸ Privacy and which is off by default.
///
/// The endpoint defaults to the Azure AI Foundry resource the spike provisioned; a developer can
/// point it elsewhere from a terminal:
///
///     defaults write com.chrismitchelmore.FocusSentinel FocusRemoteJudgeEndpoint https://<resource>.services.ai.azure.com
///
/// A self-check or test composition never builds a judge (see `AppComposition`), so no gate run
/// can open a socket because of a value on the machine running the gate.
struct RemoteJudgeConfiguration: Sendable, Equatable {
    static let endpointKey = "FocusRemoteJudgeEndpoint"
    static let deploymentKey = "FocusRemoteJudgeDeployment"
    static let thresholdKey = "FocusRemoteJudgeThreshold"
    /// The person's switch, written by the Privacy pane. Absent is off.
    static let enabledKey = "FocusRemoteJudgeEnabled"

    // swiftlint:disable:next force_unwrapping
    static let defaultEndpoint = URL(string: "https://focus-sentinel-decision-spike.services.ai.azure.com")!

    static let defaultDeployment = "decision-1"
    /// Relevance at or above which the window is part of the work. The ContextSpike measured
    /// Decision-1 rescuing 15/15 with no seduction at 0.5–0.8 on full window context, and 0.6
    /// as the one value that also held when only the title, file and address were readable.
    static let defaultThreshold = 0.6
    /// Thresholds outside this range were not measured, so they are refused rather than obeyed.
    static let thresholdRange = 0.5...0.95

    let endpoint: URL
    let deployment: String
    let threshold: Double

    /// The configuration these values describe, or nil — no judge — when a value is given and
    /// malformed: an endpoint that is not HTTPS, an empty deployment, an unmeasured threshold.
    /// An absent value takes its default. Off is the answer to every doubt.
    static func parse(endpoint: Any?, deployment: Any?, threshold: Any?) -> RemoteJudgeConfiguration? {
        var url = defaultEndpoint
        if let endpoint {
            guard let raw = (endpoint as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let given = URL(string: raw), given.scheme?.lowercased() == "https",
                  given.host?.isEmpty == false
            else { return nil }
            url = given
        }
        var name = defaultDeployment
        if let deployment {
            guard let given = (deployment as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !given.isEmpty
            else { return nil }
            name = given
        }
        var bar = defaultThreshold
        if let threshold {
            guard let number = (threshold as? NSNumber)?.doubleValue
                    ?? (threshold as? String).flatMap(Double.init),
                  thresholdRange.contains(number)
            else { return nil }
            bar = number
        }
        return RemoteJudgeConfiguration(endpoint: url, deployment: name, threshold: bar)
    }

    static func read(from defaults: UserDefaults = .standard) -> RemoteJudgeConfiguration? {
        parse(
            endpoint: defaults.object(forKey: endpointKey),
            deployment: defaults.object(forKey: deploymentKey),
            threshold: defaults.object(forKey: thresholdKey)
        )
    }
}

/// **The person's switch for the remote judge**, read by the judge before anything else.
///
/// Held by reference so the Privacy pane can turn the judge off under a rung that is already
/// composed: the rung reads availability once, at launch, so the judge is always composed in
/// the shipping app and declines `.notAvailable` — uncached, no window read, no socket — while
/// this is off.
final class RemoteJudgeSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var on: Bool

    init(isOn: Bool) { on = isOn }

    var isOn: Bool {
        get { lock.withLock { on } }
        set { lock.withLock { on = newValue } }
    }

    static func read(from defaults: UserDefaults = .standard) -> RemoteJudgeSwitch {
        RemoteJudgeSwitch(isOn: defaults.bool(forKey: RemoteJudgeConfiguration.enabledKey))
    }
}

/// **A quiet minute after the judge could not be reached.**
///
/// An unreachable judge answers `.notAvailable`, which the rung does not cache, so the next
/// judgement asks again. Without this a machine offline would read the frontmost window and try
/// the network on every dwell tick; with it, every judgement inside the minute declines at once.
/// A clock read, not a timer: nothing is scheduled.
final class RemoteJudgeBackoff: @unchecked Sendable {
    static let cooldown: Duration = .seconds(60)

    private let lock = NSLock()
    private let now: @Sendable () -> ContinuousClock.Instant
    private var retryNotBefore: ContinuousClock.Instant?

    init(now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    var isCoolingDown: Bool {
        lock.withLock { retryNotBefore.map { now() < $0 } ?? false }
    }

    func noteUnreachable() {
        lock.withLock { retryNotBefore = now() + Self.cooldown }
    }

    func noteReached() {
        lock.withLock { retryNotBefore = nil }
    }
}

/// What a remote judgement needs that a `ModelRequest` deliberately does not carry: the
/// priority sentence as written, and the window as read.
struct RemoteJudgeInput: Sendable, Equatable {
    var task: String
    var window: RemoteWindowContext
}

/// **Where the remote judge gets its input, and the only way it can.**
///
/// The composition root installs `provide`, which answers only while the frontmost application
/// is the one the request names, its activation was cleared by e03's `SensitivityGate`, and the
/// active priority is still the revision the request was made under. Anything else is nil, and
/// nil is a decline: the judge never reads a window on its own.
@MainActor
final class RemoteJudgeContextSource {
    /// The checks pass on the main actor; the window is read after, off it, by `read`.
    struct Pending: Sendable {
        var task: String
        var read: @Sendable () -> RemoteWindowContext?
    }

    var provide: ((ModelRequest) -> Pending?)?

    func pending(for request: ModelRequest) -> Pending? {
        provide?(request)
    }

    /// The checks on the main actor, then the bounded Accessibility walk on a utility thread.
    nonisolated func input(for request: ModelRequest) async -> RemoteJudgeInput? {
        guard let pending = await pending(for: request) else { return nil }
        let window = await Task.detached(priority: .utility) { pending.read() }.value
        return window.map { RemoteJudgeInput(task: pending.task, window: $0) }
    }
}
