import Foundation
import FoundationModels

/// One answer: the probability the window belongs to the task, and what it cost.
struct Answer: Codable, Sendable {
    let relevant: Double
    let label: String
    let latencyMs: Double
    let inputTokens: Int
    let note: String?
}

protocol Judge: Sendable {
    func answer(intent: String, context: String, level: Level) async -> Answer?
}

// MARK: - The on-device model

/// Mirrors `FocusModel/SystemModelPort`: the same four labels, one session per question,
/// greedy sampling. `production` keeps the shipping instructions verbatim and adds one
/// paragraph about window context; `neutral` uses the same wording as the remote judge.
struct LocalJudge: Judge {
    @Generable
    enum Label: String, CaseIterable { case yes, supporting, unsure, unrelated }

    @Generable
    struct Judgement {
        @Guide(description: "How the observed application relates to the stated task.")
        var answer: Label
    }

    enum Variant: String { case production, neutral }
    let variant: Variant

    static let production = """
        You are checking one thing: is this application part of the task the person wrote down, \
        or have they gone off on something else?

        Method. Read the task. Name to yourself the small set of applications somebody doing \
        that exact task would have open. Then check whether the application in front of you is \
        in that set.

        yes — it is in that set, and it is where the task's output is made.
        supporting — it is in that set, and it serves the output rather than making it.
        unrelated — it is NOT in that set. Choose this whenever the application merely could be \
        useful, is a capable tool, or is adjacent to the subject area. Most of the time this is \
        the right answer.
        unsure — the task is too vague for that set to have anything in it.

        Saying "yes" about something that is not the task costs the person the interruption they \
        asked for. Saying "unrelated" about something that turns out to be fine costs them one \
        click. Prefer the cheap mistake.
        """

    static let windowParagraph = """


        You may also be shown what is open in the application right now: its window title, the \
        file or web address, and text read from the window. Judge what is open, not what the \
        application could be used for. Something that only shares a word with the task — a game, \
        film or product named after something in it, or a different project about the same \
        subject — is other work.
        """

    static let neutral = """
        A person wrote down a task. You are shown the one window they have had in front of them \
        for several minutes: the application and, when available, what is open in it. Decide \
        whether working in this window is part of doing that task.

        yes — it is the task's own material: where the task's output is made.
        supporting — it serves this task: material somebody doing exactly this task would need.
        unrelated — it belongs to other work, or could only conceivably be useful.
        unsure — the task is too vague to judge.
        """

    func instructions(level: Level) -> String {
        switch variant {
        case .production: Self.production + (level == .app ? "" : Self.windowParagraph)
        case .neutral: Self.neutral + (level == .app ? "" : Self.windowParagraph)
        }
    }

    func answer(intent: String, context: String, level: Level) async -> Answer? {
        let prompt = "Task: \(intent)\n\(context)\nDoes this application belong to that task?"
        let started = ContinuousClock.now
        do {
            let session = LanguageModelSession(instructions: instructions(level: level))
            let response = try await session.respond(
                to: prompt, generating: Judgement.self, options: GenerationOptions(sampling: .greedy)
            )
            let label = response.content.answer
            return Answer(
                relevant: label == .yes || label == .supporting ? 1 : 0, label: label.rawValue,
                latencyMs: milliseconds(since: started), inputTokens: 0, note: nil
            )
        } catch {
            return Answer(relevant: 0, label: "error", latencyMs: milliseconds(since: started),
                          inputTokens: 0, note: String(describing: error).prefix(160).description)
        }
    }
}

func milliseconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
}

// MARK: - A remote chat model on Azure AI Foundry

/// The DecisionSpike chat question, reworded for a window: one capital letter, so the first
/// token's logprobs are a distribution over the four labels and a threshold can be swept.
struct ChatJudge: Judge {
    let endpoint: URL
    let deployment: String
    let token: String
    let pacer: Pacer

    func system(level: Level) -> String {
        """
        A person wrote down a task. You are shown the one window they have had in front of them \
        for several minutes: the application and, when available, what is open in it — its \
        title, the file or web address, and the text visible in it. Decide whether working in \
        this window is part of doing that task.
        """
        + (level == .app ? "" : """
            \n\nJudge what is open, not what the application could be used for. Something that \
            only shares a word with the task — a game, film or product named after something in \
            it, or a different project about the same subject — is other work.
            """)
        + """
            \n\nReply with exactly one capital letter and nothing else.
            A — it is the task's own material: where the task's output is made.
            B — it serves this task: material somebody doing exactly this task would need.
            C — it belongs to other work, or could only conceivably be useful.
            D — the task is too vague to judge.
            """
    }

    func answer(intent: String, context: String, level: Level) async -> Answer? {
        var body: [String: Any] = [
            "model": deployment,
            "messages": [
                ["role": "system", "content": system(level: level)],
                ["role": "user", "content": "Task: \(intent)\n\(context)"]
            ],
            "logprobs": true,
            "top_logprobs": 5
        ]
        if deployment.hasPrefix("gpt5") {
            body["max_completion_tokens"] = 16
            body["reasoning_effort"] = "none"
        } else {
            body["max_tokens"] = 4
            body["temperature"] = 0
        }
        var request = URLRequest(url: endpoint.appendingPathComponent("openai/v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        for attempt in 0..<8 {
            await pacer.wait()
            let started = ContinuousClock.now
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse
            else { try? await Task.sleep(for: .seconds(2)); continue }
            let latency = milliseconds(since: started)
            if http.statusCode == 429 || http.statusCode >= 500 {
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 0
                try? await Task.sleep(for: .seconds(max(retry, pow(2, Double(attempt)))))
                continue
            }
            guard http.statusCode == 200 else {
                return Answer(relevant: 0, label: "error", latencyMs: latency, inputTokens: 0,
                              note: "http \(http.statusCode): \(String(data: data, encoding: .utf8)?.prefix(160) ?? "")")
            }
            return parse(data, latencyMs: latency)
        }
        return Answer(relevant: 0, label: "error", latencyMs: 0, inputTokens: 0, note: "retries exhausted")
    }

    func parse(_ data: Data, latencyMs: Double) -> Answer {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (root["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any]
        else { return Answer(relevant: 0, label: "error", latencyMs: latencyMs, inputTokens: 0, note: "shape") }
        let inputTokens = (root["usage"] as? [String: Any])?["prompt_tokens"] as? Int ?? 0
        let letters: Set<String> = ["A", "B", "C", "D"]
        func letter(_ entry: [String: Any]) -> String {
            (entry["token"] as? String ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        }
        var mass: [String: Double] = [:]
        if let tokens = (choice["logprobs"] as? [String: Any])?["content"] as? [[String: Any]],
           let first = tokens.first(where: { letters.contains(letter($0)) }) ?? tokens.first,
           let top = first["top_logprobs"] as? [[String: Any]] {
            for entry in top {
                guard letters.contains(letter(entry)), let logprob = entry["logprob"] as? Double else { continue }
                mass[letter(entry), default: 0] += exp(logprob)
            }
        }
        let content = (message["content"] as? String ?? "").uppercased()
        let sampled = content.first(where: { letters.contains(String($0)) }).map(String.init) ?? "D"
        if mass.isEmpty { mass[sampled] = 1 }
        let total = mass.values.reduce(0, +)
        return Answer(
            relevant: ((mass["A"] ?? 0) + (mass["B"] ?? 0)) / total, label: sampled,
            latencyMs: latencyMs, inputTokens: inputTokens, note: nil
        )
    }
}

// MARK: - Microsoft-Decision-1 (MAI "System 1")

/// Decision-1 takes typed questions over a state object rather than a prompt, and returns
/// calibrated probabilities. As in DecisionSpike, the four labels are the options of one
/// `choice` and membership is one `noul`, asked in the same request. `relevant` is
/// direct + supporting from the choice; the `noul` probability is kept in `note` so the
/// two signals can be compared on identical calls.
struct SystemOneJudge: Judge {
    let endpoint: URL
    let deployment: String
    let token: String
    let pacer: Pacer
    /// `CTX_WORK=1`: the app's `RemoteWorkContext` block per task intent, as the shipped judge
    /// sends it once the person opted in (owner's ruling, 20 October 2026).
    var work: [String: String] = [:]

    static let workPreamble = """
         The state may also say more about the person's work: what done looks like, what they \
        attached to the task, their other priorities, tasks on their list and today's busy time. \
        Use it to understand the task. A window that serves only another priority or another \
        task on the list is other work.
        """

    func preamble(level: Level) -> String {
        """
        The state names a task a person wrote down and the one window they have had in front of \
        them for several minutes: the application and, when available, what is open in it — its \
        title, the file or web address, and text read from the window. Decide whether working in \
        this window is part of doing that task.
        """
        + (level == .app ? "" : """
             Judge what is open, not what the application could be used for. Something that only \
            shares a word with the task — a game, film or product named after something in it, or \
            a different project about the same subject — is other work.
            """)
    }

    func answer(intent: String, context: String, level: Level) async -> Answer? {
        let workText = work[intent] ?? ""
        let workPreamble = environment["CTX_WORK_PREAMBLE"].map { " " + $0 } ?? Self.workPreamble
        let preamble = preamble(level: level) + (workText.isEmpty ? "" : workPreamble)
        var state = ["task": intent, "window": context]
        if !workText.isEmpty { state["work"] = workText }
        let body: [String: Any] = [
            "model": deployment,
            "state": state,
            "questions": [
                "fit": [
                    "type": "choice",
                    "instructions": preamble + " Which describes this window?",
                    "criteria": [
                        "direct": "It is the task's own material: where the task's output is made.",
                        "supporting": "It serves this task: material somebody doing exactly this task would need.",
                        "unrelated": "It belongs to other work, or could only conceivably be useful.",
                        "cannot_tell": "The task is too vague to judge."
                    ]
                ],
                "belongs": [
                    "type": "noul",
                    "instructions": preamble + " Is this window part of doing that task?",
                    "criteria": [
                        "true": "It is this task's own material, or material this task needs.",
                        "false": "It belongs to other work, or could only conceivably be useful."
                    ]
                ]
            ]
        ]
        var request = URLRequest(url: endpoint.appendingPathComponent("providers/microsoft/v1/systemone"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        for attempt in 0..<8 {
            await pacer.wait()
            let started = ContinuousClock.now
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse
            else { try? await Task.sleep(for: .seconds(2)); continue }
            let latency = milliseconds(since: started)
            if http.statusCode == 429 || http.statusCode >= 500 {
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 0
                try? await Task.sleep(for: .seconds(max(retry, pow(2, Double(attempt)))))
                continue
            }
            guard http.statusCode == 200 else {
                return Answer(relevant: 0, label: "error", latencyMs: latency, inputTokens: 0,
                              note: "http \(http.statusCode): \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
            }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let answers = root["answers"] as? [String: Any],
                  let probabilities = (answers["fit"] as? [String: Any])?["probabilities"] as? [String: Double],
                  let noul = (answers["belongs"] as? [String: Any])?["noul"] as? Double
            else {
                return Answer(relevant: 0, label: "error", latencyMs: latency, inputTokens: 0,
                              note: "shape: \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
            }
            let usage = root["usage"] as? [String: Any]
            let label = probabilities.max(by: { $0.value < $1.value })?.key ?? "?"
            return Answer(
                relevant: (probabilities["direct"] ?? 0) + (probabilities["supporting"] ?? 0), label: label,
                latencyMs: latency, inputTokens: usage?["input_tokens"] as? Int ?? 0, note: "noul=\(noul)"
            )
        }
        return Answer(relevant: 0, label: "error", latencyMs: 0, inputTokens: 0, note: "retries exhausted")
    }
}

actor Pacer {
    private let interval: Double
    private var next = Date.distantPast
    init(perMinute: Double) { interval = 60 / perMinute }
    func wait() async {
        let now = Date()
        let slot = max(now, next)
        next = slot.addingTimeInterval(interval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
    }
}

func entraToken() -> String {
    if let token = environment["AZURE_ENTRA_TOKEN"], !token.isEmpty { return token }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["az", "account", "get-access-token", "--resource",
                         "https://cognitiveservices.azure.com", "--query", "accessToken", "-o", "tsv"]
    let pipe = Pipe()
    process.standardOutput = pipe
    do { try process.run() } catch { fail("could not run az: \(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !token.isEmpty
    else { fail("az account get-access-token failed") }
    return token
}
