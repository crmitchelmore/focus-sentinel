import Foundation

struct Corpus: Codable {
    struct Window: Codable {
        let id: String
        let bundleID: String
        let app: String
        let open: String?
        let url: String?
        let match: String
    }
    struct Task: Codable {
        let id: String
        let intent: String
        let rescue: [String]
        let hold: [String]
    }
    let windows: [Window]
    let tasks: [Task]

    struct Case {
        let id: String
        let intent: String
        let window: String
        let rescue: Bool
    }

    var cases: [Case] {
        tasks.flatMap { task in
            task.rescue.map { Case(id: "\(task.id)/\($0)", intent: task.intent, window: $0, rescue: true) }
                + task.hold.map { Case(id: "\(task.id)/\($0)", intent: task.intent, window: $0, rescue: false) }
        }
    }
}

let environment = ProcessInfo.processInfo.environment

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

/// The package root, so the tool finds `corpus.json` wherever it is run from.
let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

let outputDirectory = URL(fileURLWithPath: environment["CTX_OUT"]
    ?? (NSTemporaryDirectory() + "focus-context-spike"))

func loadCorpus() -> Corpus {
    do {
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: packageRoot.appendingPathComponent("corpus.json")))
    } catch { fail("corpus.json: \(error)") }
}

func loadCaptures() -> [String: WindowCapture] {
    do {
        return try JSONDecoder().decode(
            [String: WindowCapture].self,
            from: Data(contentsOf: outputDirectory.appendingPathComponent("captures.json"))
        )
    } catch { fail("captures.json (run `capture` first): \(error)") }
}

/// How much of the window the question carries. Each level includes the ones before it.
enum Level: String, CaseIterable, Comparable {
    case app, title, meta, full
    static func < (a: Level, b: Level) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
}

func context(for capture: WindowCapture, level: Level, chars: Int) -> String {
    var lines = ["Application: \(capture.app) (\(capture.bundleID))"]
    if level >= .title {
        lines.append("Window title: \(capture.title.isEmpty ? "(none)" : capture.title)")
    }
    if level >= .meta {
        if let url = capture.url { lines.append("Web address: \(url)") }
        if let document = capture.document, let path = URL(string: document)?.path(percentEncoded: false) {
            lines.append("Open file: \(path)")
        }
    }
    if level >= .full {
        if let focused = capture.focused { lines.append("Focused element: \(focused)") }
        let text = String(capture.text.prefix(chars))
        lines.append("Text in the window, read through Accessibility\(capture.text.count > chars ? " (truncated)" : ""):\n\(text)")
    }
    return lines.joined(separator: "\n")
}
