import FocusClassify
import Foundation

/// What one remote judgement is shown: the person's own priority sentence and what the
/// frontmost window holds, read once through Accessibility from an activation e03's
/// `SensitivityGate` already cleared.
///
/// Raw, and transient: built on the main actor immediately before a request, handed to
/// `DecisionOneJudge`, and dropped when the request returns. Never logged, stored or exported.
struct RemoteWindowContext: Sendable, Equatable {
    var applicationName: String?
    var bundleIdentifier: String
    var title: String?
    /// The web area's address, reduced by `reducedWebAddress` to scheme, host and path.
    var webAddress: String?
    /// The focused window's `AXDocument` file path, when it names a local file.
    var openFile: String?
    /// The focused element, only when it sits in the focused window.
    var focused: String?
    /// The window's text, content first, control labels dropped.
    var text: String

    /// The most window text a request carries: the ContextSpike's `full` level, where the
    /// evidence for this judge was measured.
    static let maximumTextLength = 6_000

    /// An HTTP(S) address with its user, password, query and fragment removed. A query string
    /// is where tokens, search terms and session identifiers live; the host and path are what
    /// the spike's judgements turned on.
    static func reducedWebAddress(_ raw: String?) -> String? {
        guard let raw, var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              components.host?.isEmpty == false
        else { return nil }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string
    }

    /// A local file path from an `AXDocument` value, or nil when it is not a file URL.
    static func filePath(fromDocument raw: String?) -> String? {
        guard let raw, let url = URL(string: raw), url.isFileURL else { return nil }
        let path = url.path(percentEncoded: false)
        return path.isEmpty ? nil : path
    }

    /// The window as the request states it — the ContextSpike's `full` format, line for line,
    /// because that is the format the evidence was measured on.
    var formatted: String {
        let name = applicationName.map { "\($0) (\(bundleIdentifier))" } ?? bundleIdentifier
        var lines = ["Application: \(name)"]
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lines.append("Window title: \(trimmedTitle.isEmpty ? "(none)" : trimmedTitle)")
        if let webAddress { lines.append("Web address: \(webAddress)") }
        if let openFile { lines.append("Open file: \(openFile)") }
        if let focused, !focused.isEmpty { lines.append("Focused element: \(focused)") }
        let truncated = text.count > Self.maximumTextLength
        let body = String(text.prefix(Self.maximumTextLength))
        lines.append(
            "Text in the window, read through Accessibility\(truncated ? " (truncated)" : ""):\n\(body)"
        )
        return lines.joined(separator: "\n")
    }
}

/// Everything about a Decision-1 exchange except the exchange: the body sent, the reading of
/// the body returned, and the mapping onto the rung's rescue-only answer. Pure, so
/// `DecisionOneProtocolTests` pins it without a network.
enum DecisionOneProtocol {
    /// The path below the resource endpoint.
    static let path = "providers/microsoft/v1/systemone"

    /// The preamble the ContextSpike measured at `meta` and `full`.
    static let preamble = """
        The state names a task a person wrote down and the one window they have had in front of \
        them for several minutes: the application and, when available, what is open in it — its \
        title, the file or web address, and text read from the window. Decide whether working in \
        this window is part of doing that task. Judge what is open, not what the application \
        could be used for. Something that only shares a word with the task — a game, film or \
        product named after something in it, or a different project about the same subject — is \
        other work.
        """

    /// The four options of the one `choice` question, in the spike's words.
    static let criteria: [String: String] = [
        "direct": "It is the task's own material: where the task's output is made.",
        "supporting": "It serves this task: material somebody doing exactly this task would need.",
        "unrelated": "It belongs to other work, or could only conceivably be useful.",
        "cannot_tell": "The task is too vague to judge.",
    ]

    static func body(deployment: String, task: String, window: RemoteWindowContext) throws -> Data {
        let body: [String: Any] = [
            "model": deployment,
            "state": ["task": task, "window": window.formatted],
            "questions": [
                "fit": [
                    "type": "choice",
                    "instructions": preamble + " Which describes this window?",
                    "criteria": criteria,
                ] as [String: Any],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// The `fit` probabilities, or nil when the response is not the documented shape.
    static func probabilities(from data: Data) -> [String: Double]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = root["answers"] as? [String: Any],
              let fit = answers["fit"] as? [String: Any],
              let raw = fit["probabilities"] as? [String: Any]
        else { return nil }
        var probabilities: [String: Double] = [:]
        for (label, value) in raw {
            guard let number = value as? NSNumber else { return nil }
            probabilities[label] = number.doubleValue
        }
        return probabilities.isEmpty ? nil : probabilities
    }

    /// **Rescue or silence, never an accusation.** Relevance is `p(direct) + p(supporting)`;
    /// at or above the threshold the window is part of the work, and whichever of the two is
    /// larger names how. Anything below is the model's `unrelated` — a decline, which leaves the
    /// deterministic answer standing and the person's own question to ask.
    static func answer(from probabilities: [String: Double], threshold: Double) -> ModelAnswer {
        let direct = probabilities["direct"] ?? 0
        let supporting = probabilities["supporting"] ?? 0
        guard direct + supporting >= threshold else { return .decline(.modelSaidUnrelated) }
        return .relevant(direct >= supporting ? .direct : .supporting)
    }
}
