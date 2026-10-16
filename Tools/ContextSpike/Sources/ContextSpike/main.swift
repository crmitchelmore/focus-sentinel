import Foundation

// ContextSpike — what is window content worth to the lane 2 question?
//
//   capture   read every corpus window through Accessibility into $CTX_OUT/captures.json
//             (run stage.sh first so the windows exist)
//   show      print the context each level sends for one window: `show <window-id> <level>`
//   judge     score every case. Environment:
//               CTX_BACKEND     local (default, the on-device model) or chat (Azure AI Foundry)
//               CTX_LEVEL       app | title | meta | full (default full)
//               CTX_VARIANT     local only: production (default) or neutral
//               CTX_CHARS       window text cap for `full` (default 6000)
//               CTX_PASSES      passes per case (default 3)
//               DECISION_ENDPOINT, CTX_DEPLOYMENT, CTX_RPM, AZURE_ENTRA_TOKEN   chat only

let arguments = CommandLine.arguments.dropFirst()
let corpus = loadCorpus()
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

switch arguments.first {
case "capture":
    capture(corpus: corpus, to: outputDirectory.appendingPathComponent("captures.json"))
case "show":
    let captures = loadCaptures()
    let rest = Array(arguments.dropFirst())
    guard rest.count == 2, let capture = captures[rest[0]], let level = Level(rawValue: rest[1])
    else { fail("usage: show <window-id> <level>") }
    print(context(for: capture, level: level, chars: Int(environment["CTX_CHARS"] ?? "") ?? 6000))
case "judge":
    await judge()
default:
    fail("usage: ContextSpike capture | show <window-id> <level> | judge")
}

struct CaseResult: Codable {
    let id: String
    let rescue: Bool
    let answers: [Answer]
}

struct SweepRow: Codable {
    let threshold: Double
    let rescued: Int
    let seduced: Int
    let unstable: Int
    let recall: Double
    let seducedCases: [String]
    let missedCases: [String]
    let unstableCases: [String]
    var meetsBar: Bool { seduced == 0 && unstable == 0 && recall >= 0.75 }
}

struct Report: Codable {
    let backend: String
    let model: String
    let level: String
    let variant: String
    let chars: Int
    let passes: Int
    let cases: [CaseResult]
    let sweep: [SweepRow]
    let p50LatencyMs: Double
    let meanInputTokens: Double
    let errors: Int
}

func judge() async {
    let captures = loadCaptures()
    let backendName = environment["CTX_BACKEND"] ?? "local"
    let level = Level(rawValue: environment["CTX_LEVEL"] ?? "full") ?? .full
    let chars = Int(environment["CTX_CHARS"] ?? "") ?? 6000
    let passes = Int(environment["CTX_PASSES"] ?? "") ?? 3
    let cases = corpus.cases.filter { captures[$0.window] != nil }
    let skipped = corpus.cases.count - cases.count
    if skipped > 0 { print("skipping \(skipped) cases whose window was not captured") }

    let judge: Judge
    let model: String
    let variant: String
    switch backendName {
    case "local":
        let v = LocalJudge.Variant(rawValue: environment["CTX_VARIANT"] ?? "") ?? .production
        judge = LocalJudge(variant: v)
        model = "apple-on-device"
        variant = v.rawValue
    case "chat":
        guard let raw = environment["DECISION_ENDPOINT"], let endpoint = URL(string: raw) else {
            fail("set DECISION_ENDPOINT")
        }
        model = environment["CTX_DEPLOYMENT"] ?? "gpt41"
        judge = ChatJudge(endpoint: endpoint, deployment: model, token: entraToken(),
                          pacer: Pacer(perMinute: Double(environment["CTX_RPM"] ?? "") ?? 90))
        variant = "window"
    case "systemone":
        guard let raw = environment["DECISION_ENDPOINT"], let endpoint = URL(string: raw) else {
            fail("set DECISION_ENDPOINT")
        }
        model = environment["CTX_DEPLOYMENT"] ?? "decision-1"
        judge = SystemOneJudge(endpoint: endpoint, deployment: model, token: entraToken(),
                               pacer: Pacer(perMinute: Double(environment["CTX_RPM"] ?? "") ?? 55))
        variant = "window"
    default:
        fail("CTX_BACKEND must be local, chat or systemone")
    }

    // Local runs one question at a time; remote runs a few in flight under the pacer.
    let width = backendName == "local" ? 1 : 4
    var answers: [String: [Answer]] = [:]
    for pass in 0..<passes {
        await withTaskGroup(of: (String, Answer?).self) { group in
            var iterator = cases.makeIterator()
            func enqueue() {
                guard let item = iterator.next() else { return }
                let text = context(for: captures[item.window]!, level: level, chars: chars)
                group.addTask { (item.id, await judge.answer(intent: item.intent, context: text, level: level)) }
            }
            for _ in 0..<width { enqueue() }
            while let (id, answer) = await group.next() {
                if let answer { answers[id, default: []].append(answer) }
                enqueue()
            }
        }
        print("pass \(pass + 1)/\(passes) done")
    }

    let results = cases.map { CaseResult(id: $0.id, rescue: $0.rescue, answers: answers[$0.id] ?? []) }
    let rescues = results.filter(\.rescue).count
    let thresholds = backendName == "local" ? [0.5] : [0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.98]
    let sweep = thresholds.map { threshold -> SweepRow in
        var rescued = 0, seducedCases: [String] = [], missed: [String] = [], unstable: [String] = []
        for result in results {
            let votes = result.answers.map { $0.relevant >= threshold }
            if Set(votes).count > 1 { unstable.append(result.id) }
            if result.rescue {
                if !votes.isEmpty, votes.allSatisfy({ $0 }) { rescued += 1 } else { missed.append(result.id) }
            } else if votes.contains(true) {
                seducedCases.append(result.id)
            }
        }
        return SweepRow(threshold: threshold, rescued: rescued, seduced: seducedCases.count,
                        unstable: unstable.count, recall: Double(rescued) / Double(max(rescues, 1)),
                        seducedCases: seducedCases, missedCases: missed, unstableCases: unstable)
    }
    let all = results.flatMap(\.answers)
    let latencies = all.map(\.latencyMs).sorted()
    let report = Report(
        backend: backendName, model: model, level: level.rawValue, variant: variant, chars: chars,
        passes: passes, cases: results, sweep: sweep,
        p50LatencyMs: latencies.isEmpty ? 0 : latencies[latencies.count / 2],
        meanInputTokens: all.isEmpty ? 0 : Double(all.map(\.inputTokens).reduce(0, +)) / Double(all.count),
        errors: all.filter { $0.label == "error" }.count
    )

    print("\(model) \(variant) level=\(level.rawValue) chars=\(chars): \(results.count) cases, \(rescues) rescue")
    for row in sweep {
        print("  t=\(row.threshold) rescued \(row.rescued)/\(rescues) seduced \(row.seduced) unstable \(row.unstable)"
              + (row.meetsBar ? "  ✓" : "") + "  seduced: \(row.seducedCases.joined(separator: ","))"
              + "  missed: \(row.missedCases.joined(separator: ","))")
    }
    print("  p50 \(Int(report.p50LatencyMs)) ms, mean input \(Int(report.meanInputTokens)) tokens, errors \(report.errors)")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let name = "report-\(backendName)-\(model)-\(variant)-\(level.rawValue)\(chars == 6000 ? "" : "-\(chars)").json"
    try? encoder.encode(report).write(to: outputDirectory.appendingPathComponent(name))
}
