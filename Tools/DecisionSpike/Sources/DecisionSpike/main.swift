import FocusClassify
import FocusCore
import FocusEvaluateCore
import Foundation

// Lane 2, asked of Microsoft-Decision-1 instead of the on-device model.
//
// Environment:
//   DECISION_ENDPOINT    Foundry resource endpoint (required), e.g. https://<name>.services.ai.azure.com
//   DECISION_DEPLOYMENT  deployment name (default "decision-1")
//   DECISION_BACKEND     "systemone" (default, Decision-1's typed-question API) or "chat" (any
//                        Foundry chat-completions deployment; scored from first-token logprobs
//                        when the model returns them, else from the sampled letter)
//   AZURE_ENTRA_TOKEN    bearer token; when unset the spike asks `az account get-access-token`
//   FOCUS_CORPUS_DIR     golden corpus directory (default: the committed one)
//   DECISION_VARIANT     question wording: "method" (default, mirrors the on-device prompt) or "neutral"
//   DECISION_STATE       "tokens" (default, the production shape) or "intent" (diagnostic only)
//   DECISION_RPM         client-side pacing, requests per minute (default 55)
//   DECISION_OUT         where report.json goes (default $TMPDIR/focus-decision-spike)
//
// Only tokens leave the machine: the priority's normalised tokens and the subject token (a
// bundle identifier or a registrable domain) — the same two values the on-device prompt
// interpolates. No title, URL path or document name is reachable from a `ModelRequest`.

// MARK: - Configuration

let environment = ProcessInfo.processInfo.environment

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("DecisionSpike: \(message)\n".utf8))
    exit(1)
}

let endpoint: URL = {
    guard let raw = environment["DECISION_ENDPOINT"],
          let url = URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw)
    else { fail("set DECISION_ENDPOINT to the Foundry resource endpoint") }
    return url
}()
let deployment = environment["DECISION_DEPLOYMENT"] ?? "decision-1"

enum Backend: String { case systemone, chat }
let backend = Backend(rawValue: environment["DECISION_BACKEND"] ?? "") ?? .systemone

func entraToken() -> String {
    if let token = environment["AZURE_ENTRA_TOKEN"], !token.isEmpty { return token }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "az", "account", "get-access-token",
        "--resource", "https://cognitiveservices.azure.com",
        "--query", "accessToken", "-o", "tsv"
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    do { try process.run() } catch { fail("could not run az: \(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !token.isEmpty
    else { fail("az account get-access-token failed; run `az login` or set AZURE_ENTRA_TOKEN") }
    return token
}

let token = entraToken()

// MARK: - The question

/// The wording follows `FocusModel/Prompt.swift` (revision 4): a method, not a definition, and
/// the cost asymmetry stated in the person's currency. Decision-1 takes typed questions with
/// per-option criteria rather than a free-form system prompt, so the four labels become the
/// options of one `choice` and the membership test becomes one `noul`; both are asked in the
/// same request so the sweep can compare the two signals on identical calls.
enum Question {
    /// `method` mirrors the on-device prompt, which leans hard on "unrelated" because a 3B model
    /// with no calibrated output could only be made cautious through its wording. `neutral`
    /// states the membership question plainly and leaves the caution to the threshold, which
    /// is what a calibrated probability is for.
    enum Variant: String { case method, neutral }

    static let variant = Variant(rawValue: environment["DECISION_VARIANT"] ?? "") ?? .method
    static var version: Int { variant == .method ? 1 : 2 }

    static var preamble: String { variant == .method ? method : neutral }

    static let neutral = """
        The state names a task a person wrote down (as keywords, in any language) and the one \
        application (a bundle identifier) or website (a domain) they have had in front of them \
        for several minutes. Decide whether working in this application or site is plausibly \
        part of doing that task.
        """

    static let method = """
        The state names a task a person wrote down and the one application (a bundle \
        identifier) or website (a domain) in front of them. Name to yourself the small set of \
        applications and sites somebody doing exactly that task would have open, then check \
        whether this one is in that set. A tool that merely could be useful, is capable, or is \
        adjacent to the subject is NOT in the set. A false "belongs" costs the person an \
        interruption they asked for; a false "does not belong" costs them one click.
        """

    static func body(for request: ModelRequest) -> [String: Any] {
        [
            "model": deployment,
            "state": [
                "task": taskText(for: request),
                "application_or_site": request.subject.value
            ],
            "questions": [
                "fit": [
                    "type": "choice",
                    "instructions": preamble + " Which describes this application or site?",
                    "criteria": [
                        "direct": "In the set, and it is where the task's output is made.",
                        "supporting": "In the set, and the task cannot be done without it, though it does not make the output.",
                        "unrelated": "Not in the set: a different piece of work, or only plausibly useful.",
                        "cannot_tell": "The task is too vague for the set to contain anything."
                    ]
                ],
                "belongs": [
                    "type": "noul",
                    "instructions": preamble + " Is this application or site in that set?",
                    "criteria": [
                        "true": "Somebody doing exactly this task would have it open.",
                        "false": "It belongs to other work, or is only plausibly useful."
                    ]
                ]
            ]
        ]
    }
}

/// The same question for a chat model: one capital letter, so the first token's logprobs are a
/// distribution over the four labels and a threshold can be swept exactly as for Decision-1.
enum ChatQuestion {
    static var system: String {
        Question.preamble + "\n\n"
            + (titleSet == nil ? "" : """
                A window title may follow the application. It names what is open in it right now: \
                judge that, not what the application could be used for.\n\n
                """)
            + (titleSet == nil || environment["DECISION_TITLE_RULE"] != "strict" ? "" : """
                A title that only shares a word with the task is not evidence: a game, film or \
                product named after something in the task, or a different project about the same \
                subject (building an app about it, designing a screen for it, hiring for it), \
                is other work. Answer A or B only when the open item is this task's own material.\n\n
                """)
            + """
            Reply with exactly one capital letter and nothing else.
            A — it is in that set, and it is where the task's output is made.
            B — it is in that set: somebody doing this task routinely uses it for a necessary \
            part of the work, though the output is made elsewhere.
            C — it is not in that set: it belongs to other work, or could only conceivably be useful.
            D — the task is too vague to judge.
            """
    }

    static func body(for request: ModelRequest) -> [String: Any] {
        var body: [String: Any] = [
            "model": deployment,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": "Task: \(taskText(for: request))\n"
                    + "Application or site: \(request.subject.value)" + titleLine(for: request)]
            ]
        ]
        // Mistral rejects the parameter; grok's logprobs cover hidden preamble tokens, not the letter.
        if !(deployment.hasPrefix("mistral") || deployment.hasPrefix("grok")) {
            body["logprobs"] = true
            body["top_logprobs"] = 5
        }
        if deployment.hasPrefix("gpt5") || deployment.hasPrefix("gpt-5") {
            body["max_completion_tokens"] = 16
            body["reasoning_effort"] = "none"
        } else {
            body["max_tokens"] = 4
            body["temperature"] = 0
        }
        return body
    }
}

/// `tokens` (default) sends what a `ModelRequest` carries — the priority's normalised tokens,
/// the production shape. `intent` sends the person's own sentence instead, looked up from the
/// corpus by cache key: a diagnostic for whether token normalisation is what limits recall.
/// The shipping prompt builder cannot express this (R-116), so it is evidence, not a proposal.
enum StateSource: String { case tokens, intent }
let stateSource = StateSource(rawValue: environment["DECISION_STATE"] ?? "") ?? .tokens
nonisolated(unsafe) var intentsByCacheKey: [String: String] = [:]

/// `DECISION_TITLES=aligned|generic|decoy` adds a window title from `titles.json`, keyed by
/// cell ID. A title is captured prose that `ModelRequest` cannot carry (R-116); this measures
/// what Accessibility-read context would be worth before anybody rules on that data flow.
let titleSet = environment["DECISION_TITLES"].flatMap { $0.isEmpty ? nil : $0 }
nonisolated(unsafe) var titlesByCacheKey: [String: String] = [:]

func titleLine(for request: ModelRequest) -> String {
    guard let title = titlesByCacheKey[request.cacheKey] else { return "" }
    return "\nWindow title: \(title)"
}

func taskText(for request: ModelRequest) -> String {
    if stateSource == .intent, let intent = intentsByCacheKey[request.cacheKey] { return intent }
    return request.priorityTokens.map(\.value).joined(separator: " ")
}

// MARK: - The remote call

struct Probe: Sendable, Codable {
    let direct: Double
    let supporting: Double
    let unrelated: Double
    let cannotTell: Double
    let noul: Double
    let latencyMs: Double
    let inputTokens: Int

    var relevant: Double { direct + supporting }
}

enum ProbeError: Error { case transport(String), http(Int, String), shape(String) }

/// Synchronous on purpose: `ModelLaneJudge.prime` is synchronous, and this runs from `main`,
/// never inside an async context.
func ask(_ request: ModelRequest) -> Result<Probe, ProbeError> {
    let path = backend == .chat ? "openai/v1/chat/completions" : "providers/microsoft/v1/systemone"
    var urlRequest = URLRequest(url: endpoint.appendingPathComponent(path))
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = 30
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    do {
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: backend == .chat ? ChatQuestion.body(for: request) : Question.body(for: request)
        )
    } catch { return .failure(.shape("encode: \(error)")) }

    for attempt in 0..<8 {
        Pacer.shared.wait()
        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        let started = ContinuousClock.now
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            let http = response as? HTTPURLResponse
            box.set(data: data, status: http?.statusCode, error: error,
                    retryAfter: http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
            semaphore.signal()
        }.resume()
        semaphore.wait()
        let elapsed = ContinuousClock.now - started
        let latencyMs = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15

        let (data, status, error, retryAfter) = box.get()
        if let error { return .failure(.transport(error.localizedDescription)) }
        guard let status, let data else { return .failure(.transport("no response")) }
        if status == 429 || status >= 500 {
            Thread.sleep(forTimeInterval: max(retryAfter ?? 0, pow(2, Double(attempt))))
            continue
        }
        guard status == 200 else {
            return .failure(.http(status, String(data: data, encoding: .utf8) ?? ""))
        }
        return backend == .chat ? parseChat(data, latencyMs: latencyMs) : parse(data, latencyMs: latencyMs)
    }
    return .failure(.http(429, "retries exhausted"))
}

final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var status: Int?
    private var error: Error?
    private var retryAfter: Double?
    func set(data: Data?, status: Int?, error: Error?, retryAfter: Double?) {
        lock.withLock {
            self.data = data; self.status = status; self.error = error; self.retryAfter = retryAfter
        }
    }
    func get() -> (Data?, Int?, Error?, Double?) { lock.withLock { (data, status, error, retryAfter) } }
}

/// The deployment's limit is requests per minute (60 at capacity 60), so the spike spaces its
/// calls rather than spending them on 429s. `DECISION_RPM` overrides the pace.
final class Pacer: @unchecked Sendable {
    static let shared = Pacer(perMinute: Double(environment["DECISION_RPM"] ?? "") ?? 55)
    private let lock = NSLock()
    private let interval: Double
    private var next = Date.distantPast
    init(perMinute: Double) { interval = 60 / perMinute }
    func wait() {
        let delay: Double = lock.withLock {
            let now = Date()
            let slot = max(now, next)
            next = slot.addingTimeInterval(interval)
            return slot.timeIntervalSince(now)
        }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
    }
}

func parse(_ data: Data, latencyMs: Double) -> Result<Probe, ProbeError> {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let answers = root["answers"] as? [String: Any],
          let fit = answers["fit"] as? [String: Any],
          let probabilities = fit["probabilities"] as? [String: Double],
          let belongs = answers["belongs"] as? [String: Any],
          let noul = belongs["noul"] as? Double
    else { return .failure(.shape(String(data: data, encoding: .utf8) ?? "")) }
    let usage = root["usage"] as? [String: Any]
    return .success(
        Probe(
            direct: probabilities["direct"] ?? 0,
            supporting: probabilities["supporting"] ?? 0,
            unrelated: probabilities["unrelated"] ?? 0,
            cannotTell: probabilities["cannot_tell"] ?? 0,
            noul: noul,
            latencyMs: latencyMs,
            inputTokens: usage?["input_tokens"] as? Int ?? 0
        )
    )
}

/// Reads the four labels off the first answer token's top logprobs, renormalised over A–D. A
/// model that returns no logprobs is scored by the letter it sampled, so its only signal is a
/// hard 0 or 1 and its run-to-run variation shows up as `unstable`.
func parseChat(_ data: Data, latencyMs: Double) -> Result<Probe, ProbeError> {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choice = (root["choices"] as? [[String: Any]])?.first,
          let message = choice["message"] as? [String: Any]
    else { return .failure(.shape(String(data: data, encoding: .utf8) ?? "")) }
    let usage = root["usage"] as? [String: Any]
    let inputTokens = usage?["prompt_tokens"] as? Int ?? 0

    var mass: [String: Double] = [:]
    let letters: Set<String> = ["A", "B", "C", "D"]
    if let tokens = (choice["logprobs"] as? [String: Any])?["content"] as? [[String: Any]],
       let first = tokens.first(where: {
           letters.contains(($0["token"] as? String ?? "").trimmingCharacters(in: .whitespaces).uppercased())
       }) ?? tokens.first,
       let top = first["top_logprobs"] as? [[String: Any]] {
        for entry in top {
            let letter = (entry["token"] as? String ?? "").trimmingCharacters(in: .whitespaces).uppercased()
            guard letters.contains(letter), let logprob = entry["logprob"] as? Double else { continue }
            mass[letter, default: 0] += exp(logprob)
        }
    }
    if mass.isEmpty {
        let content = (message["content"] as? String ?? "").uppercased()
        let letter = content.first(where: { letters.contains(String($0)) }).map(String.init) ?? "D"
        mass[letter] = 1
    }
    let total = mass.values.reduce(0, +)
    func p(_ letter: String) -> Double { (mass[letter] ?? 0) / total }
    return .success(
        Probe(
            direct: p("A"), supporting: p("B"), unrelated: p("C"), cannotTell: p("D"),
            noul: p("A") + p("B"), latencyMs: latencyMs, inputTokens: inputTokens
        )
    )
}

// MARK: - Recording, so a threshold sweep re-reads the calls rather than re-paying them

/// Every probe the spike ever made, keyed by harness pass and cache key. The harness resets the
/// judge between its three passes so each pass really re-asks; pass *n* of every threshold run
/// reads the same recorded answer, so the sweep compares thresholds on identical calls and the
/// `unstable` count still measures the remote model's own run-to-run variation.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var probes: [String: Probe] = [:]
    private(set) var failures: [String] = []
    private(set) var calls = 0

    func probe(_ request: ModelRequest, pass: Int) -> Probe? {
        let key = "\(pass)|\(request.cacheKey)"
        if let recorded = lock.withLock({ probes[key] }) { return recorded }
        switch ask(request) {
        case .success(let probe):
            lock.withLock { probes[key] = probe; calls += 1 }
            return probe
        case .failure(let error):
            lock.withLock { failures.append("\(request.subject.value): \(error)") }
            return nil
        }
    }

    var all: [Probe] { lock.withLock { Array(probes.values) } }
}

enum Signal: String, CaseIterable, Sendable {
    /// P(direct) + P(supporting) from the four-way choice.
    case choice
    /// P(true) from the yes/no membership question.
    case noul
}

/// A `ModelLaneJudge` over the recorded probes. Above the threshold it answers `.relevant`; below
/// it, it declines — `ModelAnswer` has no `unrelated`, so a remote model can only ever withhold
/// a question, never cause one.
final class RemoteDecisionJudge: ModelLaneJudge, @unchecked Sendable {
    let recorder: Recorder
    let signal: Signal
    let threshold: Double
    private let lock = NSLock()
    private var pass = 0
    private var answers: [String: ModelAnswer] = [:]

    init(recorder: Recorder, signal: Signal, threshold: Double) {
        self.recorder = recorder
        self.signal = signal
        self.threshold = threshold
    }

    func prime(_ request: ModelRequest) -> ModelAnswer {
        let currentPass = lock.withLock { pass }
        let answer: ModelAnswer
        if let probe = recorder.probe(request, pass: currentPass) {
            answer = Self.answer(for: probe, signal: signal, threshold: threshold)
        } else {
            answer = .decline(.notAvailable)
        }
        lock.withLock { answers[request.cacheKey] = answer }
        return answer
    }

    static func answer(for probe: Probe, signal: Signal, threshold: Double) -> ModelAnswer {
        let score = signal == .choice ? probe.relevant : probe.noul
        if score >= threshold {
            return .relevant(probe.direct >= probe.supporting ? .direct : .supporting)
        }
        return probe.unrelated >= probe.cannotTell
            ? .decline(.modelSaidUnrelated) : .decline(.modelSaidUncertain)
    }

    func cachedAnswer(for request: ModelRequest) -> ModelAnswer? {
        lock.withLock { answers[request.cacheKey] }
    }

    func reset() {
        lock.withLock { answers.removeAll(); pass += 1 }
    }

    var promptVersion: Int { Question.version }
    var generationCount: Int { recorder.calls }
}

// MARK: - Run

func defaultCorpusDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // DecisionSpike/
        .deletingLastPathComponent()      // Sources/
        .deletingLastPathComponent()      // Tools/DecisionSpike/
        .deletingLastPathComponent()      // Tools/
        .deletingLastPathComponent()      // repository root
        .appendingPathComponent("Packages/FocusEvaluate/Tests/FocusEvaluateTests/Resources")
        .appendingPathComponent(CorpusLoader.goldenCorpusDirectoryName)
}

let corpusDirectory = environment["FOCUS_CORPUS_DIR"].map(URL.init(fileURLWithPath:))
    ?? defaultCorpusDirectory()
let outputDirectory = URL(
    fileURLWithPath: environment["DECISION_OUT"]
        ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("focus-decision-spike").path
)

let corpus: ModelCorpus
do { corpus = try ModelCorpusLoader.load(goldenCorpusDirectory: corpusDirectory) } catch {
    fail("the model corpus did not load: \(error)")
}

var titleTable: [String: String] = [:]
if let titleSet {
    guard backend == .chat else { fail("DECISION_TITLES needs DECISION_BACKEND=chat") }
    let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("titles.json")
    guard let data = try? Data(contentsOf: file),
          let sets = try? JSONDecoder().decode([String: [String: String]].self, from: data),
          let chosen = sets[titleSet]
    else { fail("no title set '\(titleSet)' in \(file.path)") }
    titleTable = chosen
}

for cell in corpus.cells {
    if let request = ModelCorpusRunner().request(cell, stamp: EngineStamp.current) {
        intentsByCacheKey[request.cacheKey] = cell.priority.intent
        if titleSet != nil {
            guard let title = titleTable[cell.id] else { fail("no title for \(cell.id)") }
            titlesByCacheKey[request.cacheKey] = title
        }
    }
}

let recorder = Recorder()
let generatedAt = EvaluationHarness.timestamp(Date())
let thresholds = [0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.98]

struct SweepRow: Codable {
    let signal: String
    let threshold: Double
    let rescued: Int
    let missedRescue: Int
    let seduced: Int
    let unstable: Int
    let rescueRecall: Double
    let contractHeld: Bool
    let qualityHeld: Bool
    let seducedCells: [String]
    let missedCells: [String]
}

print("DecisionSpike — \(backend == .chat ? "chat deployment" : "Microsoft-Decision-1") through lane 2")
print("endpoint:   \(endpoint.absoluteString)  deployment: \(deployment)  "
    + "question: \(Question.variant.rawValue) v\(Question.version)  state: \(stateSource.rawValue)")
print("corpus:     \(corpusDirectory.path)/\(ModelCorpusLoader.directoryName)")
print("cells:      \(corpus.cellCount) (\(corpus.rescueCount) rescue, \(corpus.holdCount) hold)  "
    + "passes: \(EvaluationPolicy.modelLaneRepeatCount)")
print("")
func pad(_ value: Any, _ width: Int) -> String {
    let text = "\(value)"
    return text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}
func fixed(_ value: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", value) }

print([pad("signal", 7), pad("thr", 5), pad("rescued", 8), pad("missed", 7), pad("seduced", 8),
       pad("unstable", 9), pad("recall", 7), "quality"].joined(separator: " "))

var rows: [SweepRow] = []
var lastReport: ModelEvaluationReport?
for signal in backend == .chat ? [Signal.choice] : Signal.allCases {
    for threshold in thresholds {
        let report = ModelEvaluationHarness(
            corpus: corpus,
            judge: RemoteDecisionJudge(recorder: recorder, signal: signal, threshold: threshold),
            runID: "decision-spike-\(signal.rawValue)-\(threshold)",
            generatedAt: generatedAt
        ).run()
        lastReport = report
        let contract = ModelEvaluationGate.contractChecks(for: report).allSatisfy(\.held)
        let quality = ModelEvaluationGate.qualityHolds(report)
        let row = SweepRow(
            signal: signal.rawValue,
            threshold: threshold,
            rescued: report.buckets[ModelBucket.rescued.rawValue] ?? 0,
            missedRescue: report.buckets[ModelBucket.missedRescue.rawValue] ?? 0,
            seduced: report.seduced,
            unstable: report.unstable.count,
            rescueRecall: report.rescueRecall,
            contractHeld: contract,
            qualityHeld: quality,
            seducedCells: report.cases.filter { $0.bucket == .seduced }.map(\.id),
            missedCells: report.cases.filter { $0.bucket == .missedRescue }.map(\.id)
        )
        rows.append(row)
        print([pad(signal.rawValue, 7), pad(fixed(threshold, 2), 5), pad(row.rescued, 8),
               pad(row.missedRescue, 7), pad(row.seduced, 8), pad(row.unstable, 9),
               pad(fixed(row.rescueRecall, 3), 7),
               (quality ? "EARNED" : "not earned") + (contract ? "" : "  CONTRACT FAIL")]
            .joined(separator: " "))
    }
}

// Per-cell probabilities from every pass, so a reader sees the margin and not only the bucket.
struct CellRow: Codable {
    let id: String
    let expectation: String
    let task: String
    let subject: String
    let pRelevant: [Double]
    let noul: [Double]
}

var cellRows: [CellRow] = []
let runner = ModelCorpusRunner()
for cell in corpus.cells {
    guard let request = runner.request(cell, stamp: EngineStamp.current) else { continue }
    // The harness resets before every pass, so its passes are numbered from one.
    let probes = (1...EvaluationPolicy.modelLaneRepeatCount).compactMap { recorder.probe(request, pass: $0) }
    cellRows.append(
        CellRow(
            id: cell.id,
            expectation: cell.modelExpectation.rawValue,
            task: taskText(for: request),
            subject: request.subject.value,
            pRelevant: probes.map(\.relevant),
            noul: probes.map(\.noul)
        )
    )
}

print("")
print("per cell (pass 1..3):  P(direct+supporting) | P(noul)")
for row in cellRows.sorted(by: { ($0.expectation, -($0.pRelevant.first ?? 0)) < ($1.expectation, -($1.pRelevant.first ?? 0)) }) {
    let rel = row.pRelevant.map { String(format: "%.3f", $0) }.joined(separator: " ")
    let noul = row.noul.map { String(format: "%.3f", $0) }.joined(separator: " ")
    print("  \(row.expectation.padding(toLength: 6, withPad: " ", startingAt: 0)) "
        + "\(row.id.padding(toLength: 10, withPad: " ", startingAt: 0)) "
        + "\(row.subject.padding(toLength: 28, withPad: " ", startingAt: 0)) "
        + "\(rel) | \(noul)  [\(row.task)]")
}

let latencies = recorder.all.map(\.latencyMs).sorted()
let inputTokens = recorder.all.map(\.inputTokens).reduce(0, +)
func percentile(_ p: Double) -> Double {
    latencies.isEmpty ? 0 : latencies[min(latencies.count - 1, Int(Double(latencies.count) * p))]
}
print("")
print(String(format: "calls: %ld  failures: %ld  latency ms p50 %.0f  p95 %.0f  max %.0f  input tokens %ld",
             recorder.calls, recorder.failures.count, percentile(0.5), percentile(0.95),
             latencies.last ?? 0, inputTokens))
for failure in recorder.failures.prefix(5) { print("  failure: \(failure)") }

struct SpikeReport: Codable {
    let generatedAt: String
    let deployment: String
    let questionVersion: Int
    let modelCorpusDigest: String
    let sweep: [SweepRow]
    let cells: [CellRow]
    let latencyMsP50: Double
    let latencyMsP95: Double
    let calls: Int
    let failures: [String]
}

do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let destination = outputDirectory.appendingPathComponent("report-\(deployment)-\(Question.variant.rawValue)-\(stateSource.rawValue)\(titleSet.map { "-titles-\($0)" } ?? "")\(environment["DECISION_TITLE_RULE"].map { "-\($0)" } ?? "").json")
    try encoder.encode(
        SpikeReport(
            generatedAt: generatedAt,
            deployment: deployment,
            questionVersion: Question.version,
            modelCorpusDigest: lastReport?.modelCorpusDigest ?? "",
            sweep: rows,
            cells: cellRows,
            latencyMsP50: percentile(0.5),
            latencyMsP95: percentile(0.95),
            calls: recorder.calls,
            failures: recorder.failures
        )
    ).write(to: destination)
    print("report: \(destination.path)")
} catch {
    fail("could not write the report: \(error)")
}
