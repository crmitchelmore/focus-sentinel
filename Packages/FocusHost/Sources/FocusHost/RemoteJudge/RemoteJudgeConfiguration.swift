import FocusClassify
import Foundation

/// **The remote judge's switch, and it is off** unless someone sets an endpoint.
///
/// Read once at launch from the app's own defaults domain, because there is no Settings control
/// for it yet: the Privacy pane still promises a default install never connects, and on a
/// default install that stays true. Turning it on is a deliberate act at a terminal:
///
///     defaults write com.chrismitchelmore.FocusSentinel FocusRemoteJudgeEndpoint https://<resource>.services.ai.azure.com
///
/// A self-check or test composition never reads it (see `AppComposition`), so no gate run can
/// open a socket because of a value on the machine running the gate.
struct RemoteJudgeConfiguration: Sendable, Equatable {
    static let endpointKey = "FocusRemoteJudgeEndpoint"
    static let deploymentKey = "FocusRemoteJudgeDeployment"
    static let thresholdKey = "FocusRemoteJudgeThreshold"

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

    /// The configuration these values describe, or nil — off — when there is no endpoint, the
    /// endpoint is not HTTPS, or a value is malformed. Off is the answer to every doubt.
    static func parse(endpoint: Any?, deployment: Any?, threshold: Any?) -> RemoteJudgeConfiguration? {
        guard let raw = (endpoint as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host?.isEmpty == false
        else { return nil }
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
