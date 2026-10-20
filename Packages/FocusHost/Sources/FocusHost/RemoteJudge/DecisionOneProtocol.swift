import FocusClassify
import FocusCore
import Foundation

/// The window half of what one remote judgement is shown (the work half is
/// `RemoteWorkContext`): what the frontmost window holds, read once through Accessibility from
/// an activation e03's `SensitivityGate` already cleared.
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

/// What else the app knows about the task, sent beside the window once the person opted in to
/// the remote judge (owner's ruling, 20 October 2026: local first, opt in for more).
///
/// Only this task's own facts. Privacy would allow the person's other priorities and other tasks
/// too, but measured at threshold 0.6 they made the judge worse: a window for other work the
/// person also has read as this task (`Tools/ContextSpike/README.md`, 20 October 2026).
///
/// Transient, like `RemoteWindowContext`: built for one request and dropped when it returns.
/// Every list and line is capped, so a long shortlist or a busy mirror cannot swamp the window.
struct RemoteWorkContext: Sendable, Equatable {
    /// The active priority's definition of done.
    var doneWhen: String?
    /// The active priority's context pack, in chip order, each as `Kind: name (value)`.
    var contextItems: [String] = []
    /// The task mirror's open tasks pinned to this priority, its own steps.
    var steps: [String] = []
    /// Today's busy time, calendar and outside sources merged, as `HH:mm–HH:mm`.
    var busyToday: [String] = []
    /// The local time the busy blocks are read against, as `HH:mm`.
    var clock: String?

    static let maximumItems = 12
    static let maximumLineLength = 200

    init(
        doneWhen: String? = nil,
        contextItems: [String] = [],
        steps: [String] = [],
        busyToday: [String] = [],
        clock: String? = nil
    ) {
        self.doneWhen = doneWhen
        self.contextItems = contextItems
        self.steps = steps
        self.busyToday = busyToday
        self.clock = clock
    }

    var isEmpty: Bool { formatted.isEmpty }

    /// One labelled block per fact the app holds, and nothing for a fact it does not.
    var formatted: String {
        var lines: [String] = []
        if let done = Self.line(doneWhen) { lines.append("Done when: \(done)") }
        func section(_ heading: String, _ items: [String]) {
            let kept = items.compactMap(Self.line).prefix(Self.maximumItems)
            guard !kept.isEmpty else { return }
            lines.append(heading + "\n" + kept.map { "- \($0)" }.joined(separator: "\n"))
        }
        section("Attached to this task:", contextItems)
        section("Steps of this task:", steps)
        let busy = busyToday.compactMap(Self.line).prefix(Self.maximumItems)
        if !busy.isEmpty {
            let now = clock.map { " (it is now \($0))" } ?? ""
            lines.append("Busy today\(now): " + busy.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private static func line(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let flattened = raw.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !flattened.isEmpty else { return nil }
        return flattened.count > maximumLineLength
            ? String(flattened.prefix(maximumLineLength)) + "…"
            : flattened
    }

    /// A context item as the judge reads it.
    static func describe(_ item: ContextItemValue) -> String {
        let kind: String
        switch item.kind {
        case .app: kind = "App"
        case .domain: kind = "Site"
        case .keyword: kind = "Keyword"
        case .file: kind = "File"
        default: kind = "Item"
        }
        let name = item.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == item.value { return "\(kind): \(item.value)" }
        return "\(kind): \(name) (\(item.value))"
    }

    /// Today's busy blocks as clock ranges in `calendar`'s zone, and the clock now.
    static func busy(_ day: CalendarDay, calendar: Calendar) -> (blocks: [String], clock: String?) {
        guard case .read(_, let blocks, let now) = day, !blocks.isEmpty else { return ([], nil) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return (
            blocks.map { "\(formatter.string(from: $0.start))–\(formatter.string(from: $0.end))" },
            formatter.string(from: now)
        )
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

    /// Added to the preamble only when the state carries `work`, so a request with nothing more
    /// to say is byte for byte the one the ContextSpike measured. The ContextSpike's preamble C,
    /// word for word: 15/15 rescued, 0 seduced, 0 unstable over five passes at 0.5–0.7. "Use it
    /// to understand the task" let a same-client window through, and a sentence naming shared
    /// names lost a rescue; neither is safe to reword without measuring again.
    static let workPreamble = """
         Judge only the task named in the state's task. The state's work says more about it — \
        what done looks like, what the person attached to it, its own steps — and about the rest \
        of their day. A window that belongs to the other work listed there is other work, even \
        though it is the person's.
        """

    static func body(
        deployment: String,
        task: String,
        window: RemoteWindowContext,
        work: RemoteWorkContext = RemoteWorkContext()
    ) throws -> Data {
        var state = ["task": task, "window": window.formatted]
        let workText = work.formatted
        if !workText.isEmpty { state["work"] = workText }
        let body: [String: Any] = [
            "model": deployment,
            "state": state,
            "questions": [
                "fit": [
                    "type": "choice",
                    "instructions": preamble + (workText.isEmpty ? "" : workPreamble)
                        + " Which describes this window?",
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
