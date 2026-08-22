import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The hostile corpus.
///
/// Every one of these was fed to the **real app** through the real `.onOpenURL` path in probe
/// P-61 and measured to arrive verbatim: nothing upstream sanitises anything. That is why the
/// parser owns every bound, and why this suite is the place those bounds are proved.
enum HandoffCorpus {
    /// P-61's 5,019-character URL.
    static let overlongTask = String(repeating: "a", count: 5_000)
    static let overlongURL = "focus://start?task=\(overlongTask)"

    /// Every string in the corpus. Some are not valid URLs at all, which is itself an input.
    static let strings: [String] = [
        // --- the measured inputs ---------------------------------------------------------
        "focus://start?task=Finish%20the%20proposal",
        "focus://start?task=Finish%20the%20proposal&doneWhen=It%20is%20submitted",
        overlongURL,
        "focus://start?task=a%00b",                       // an embedded NUL
        "focus://start?task=x&task=y",                    // duplicate keys
        "focus://complete?task=x",                        // an unknown verb
        "focus://start?task=%E2%9C%93",                   // ✓
        "focus://start?task=a/b",
        "focus://start?task=a%3Fb",
        "focus://start?task=a%23b",
        "focus://start?task=%25ZZ",                       // a mis-escape, as `open` delivers it

        // --- the rest of the hostile set ---------------------------------------------------
        "focus://start",
        "focus://start?task=",
        "focus://start?task=%20%20%20",
        "focus://start?task=%01%02%03",                   // control characters only
        "focus://start?doneWhen=It%20is%20submitted",
        "focus://start?task=ok&doneWhen=",
        "focus://start?task=ok&doneWhen=%00",
        "focus://start?task=ok&unknown=1&other=2",
        "focus://start?task=ok&task=second&doneWhen=a&doneWhen=b",
        "focus://START?task=ok",
        "FOCUS://start?task=ok",
        "focus://Start?task=ok",
        "focus://replace?task=ok",
        "focus://start/extra?task=ok",
        "focus://?task=ok",
        "focus:start?task=ok",
        "https://start?task=ok",
        "http://example.com/?task=ok",
        "file:///tmp/x",
        "javascript:alert(1)",
        "focus://start?task=%F0%9F%92%A3",                // 💣
        "focus://start?task=%D9%85%D8%B1%D8%AD%D8%A8%D8%A7",  // Arabic
        "focus://start?task=%E2%80%AAoverride%E2%80%AC",  // bidi format characters
        "focus://start?task=line%0Abreak",
        "focus://start?task=tab%09separated",
        "focus://start?task=%27%3B%20DROP%20TABLE%20tasks%3B--",
        "focus://start?task=..%2F..%2F..%2Fetc%2Fpasswd",
        "focus://start?task=ok#fragment",
        "focus://start?task=ok&doneWhen=\(String(repeating: "d", count: 800))",
        "focus://start?task=\(String(repeating: "b", count: 600))"
    ]

    /// The subset that `URL` will accept, as URLs.
    static var urls: [URL] { strings.compactMap(URL.init(string:)) }
}

@Suite("focus:// handoff parsing")
struct HandoffRequestTests {
    // MARK: - The measured inputs, one assertion each

    @Test("a well-formed handoff produces a confirmation request")
    func wellFormed() throws {
        let parse = HandoffRequest.parse(
            "focus://start?task=Finish%20the%20proposal&doneWhen=It%20is%20submitted"
        )
        let request = try #require(parse.request)
        #expect(request.verb == .start)
        #expect(request.task == "Finish the proposal")
        #expect(request.doneWhen == "It is submitted")
        #expect(request.flags.isEmpty)
    }

    @Test("the 5,019-character URL is refused by the cap, before anything is decoded")
    func theOverlongURL() {
        #expect(HandoffCorpus.overlongURL.count > HandoffRequest.maximumURLLength)
        #expect(HandoffRequest.parse(HandoffCorpus.overlongURL) == .rejected(.tooLong))
    }

    @Test("a task under the URL cap but over the field cap is truncated and flagged")
    func fieldCapTruncatesAndFlags() throws {
        let long = String(repeating: "b", count: 600)
        let request = try #require(HandoffRequest.parse("focus://start?task=\(long)").request)
        #expect(request.task.count == HandoffRequest.maximumFieldLength)
        #expect(request.flags.contains(.taskTruncated(originalLength: 600)))
    }

    @Test("an embedded NUL is stripped and disclosed")
    func embeddedNUL() throws {
        let request = try #require(HandoffRequest.parse("focus://start?task=a%00b").request)
        #expect(request.task == "ab")
        #expect(!request.task.unicodeScalars.contains { $0.value == 0 })
        #expect(request.flags.contains(.controlCharactersStripped))
    }

    @Test("bidirectional format characters are stripped too")
    func formatCharactersAreStripped() throws {
        let request = try #require(
            HandoffRequest.parse("focus://start?task=%E2%80%AAoverride%E2%80%AC").request
        )
        #expect(request.task == "override")
        #expect(request.flags.contains(.controlCharactersStripped))
    }

    @Test("duplicate keys: the first wins, and the surface is told")
    func duplicateKeysFirstWins() throws {
        let request = try #require(HandoffRequest.parse("focus://start?task=x&task=y").request)
        #expect(request.task == "x")
        #expect(request.flags.contains(.duplicateKeysIgnored(["task"])))

        let both = try #require(
            HandoffRequest.parse("focus://start?task=a&task=b&doneWhen=c&doneWhen=d").request
        )
        #expect(both.task == "a")
        #expect(both.doneWhen == "c")
        #expect(both.flags.contains(.duplicateKeysIgnored(["task", "doneWhen"])))
    }

    @Test("unknown query items are ignored and named")
    func unknownQueryItemsAreNamed() throws {
        let request = try #require(
            HandoffRequest.parse("focus://start?task=ok&unknown=1&other=2").request
        )
        #expect(request.task == "ok")
        #expect(request.flags.contains(.unknownQueryItems(["unknown", "other"])))
    }

    @Test(
        "an unknown verb is rejected with the verb named",
        arguments: [
            ("focus://complete?task=x", "complete"),
            ("focus://replace?task=ok", "replace"),
            ("focus://?task=ok", ""),
            ("focus:start?task=ok", "")
        ]
    )
    func unknownVerbs(_ input: String, _ named: String) {
        #expect(HandoffRequest.parse(input) == .rejected(.unknownVerb(named)))
    }

    @Test(
        "anything that is not a focus:// URL is rejected on the scheme",
        arguments: [
            "https://start?task=ok",
            "http://example.com/?task=ok",
            "file:///tmp/x",
            "javascript:alert(1)"
        ]
    )
    func foreignSchemes(_ input: String) {
        #expect(HandoffRequest.parse(input) == .rejected(.scheme))
    }

    @Test("the scheme and the verb are matched case-insensitively")
    func caseInsensitivity() throws {
        for input in ["focus://START?task=ok", "FOCUS://start?task=ok", "focus://Start?task=ok"] {
            let request = try #require(HandoffRequest.parse(input).request, "\(input) was rejected")
            #expect(request.verb == .start)
            #expect(request.task == "ok")
        }
    }

    @Test(
        "a task that is absent, empty, whitespace or only control characters is rejected",
        arguments: [
            "focus://start",
            "focus://start?task=",
            "focus://start?task=%20%20%20",
            "focus://start?task=%01%02%03",
            "focus://doneWhen=x",
            "focus://start?doneWhen=It%20is%20submitted"
        ]
    )
    func missingTask(_ input: String) {
        let parse = HandoffRequest.parse(input)
        // Either the verb never resolved, or the task was empty. Both are rejections, and
        // neither is something the app can act on.
        #expect(parse.request == nil, "‘\(input)’ produced an actionable request")
    }

    @Test("an empty definition of done is no definition of done")
    func emptyDoneWhen() throws {
        for input in ["focus://start?task=ok&doneWhen=", "focus://start?task=ok&doneWhen=%00"] {
            let request = try #require(HandoffRequest.parse(input).request)
            #expect(request.doneWhen == nil, "‘\(input)’ stored an empty done-when")
        }
    }

    @Test(
        "punctuation and unicode inside a value survive intact",
        arguments: [
            ("focus://start?task=a/b", "a/b"),
            ("focus://start?task=a%3Fb", "a?b"),
            ("focus://start?task=a%23b", "a#b"),
            ("focus://start?task=%25ZZ", "%ZZ"),
            ("focus://start?task=%E2%9C%93", "✓"),
            ("focus://start?task=%F0%9F%92%A3", "💣"),
            ("focus://start?task=%27%3B%20DROP%20TABLE%20tasks%3B--", "'; DROP TABLE tasks;--"),
            ("focus://start?task=..%2F..%2F..%2Fetc%2Fpasswd", "../../../etc/passwd")
        ]
    )
    func valuesSurviveIntact(_ input: String, _ expected: String) throws {
        let request = try #require(HandoffRequest.parse(input).request, "‘\(input)’ was rejected")
        #expect(request.task == expected)
    }

    @Test("a fragment is not part of the task")
    func fragmentsAreNotContent() throws {
        let request = try #require(HandoffRequest.parse("focus://start?task=ok#fragment").request)
        #expect(request.task == "ok")
    }

    // MARK: - Properties over the whole corpus

    @Test("every input in the corpus produces a confirm or a rejection, and never a mutation")
    func everyResultIsConfirmOrRejected() {
        #expect(HandoffCorpus.strings.count >= 40, "the corpus is too small to mean anything")

        for input in HandoffCorpus.strings {
            let parse = HandoffRequest.parse(input)
            switch parse {
            case .confirm(let request):
                // A confirm is a *request to ask a person*, and it is always within bounds.
                #expect(!request.task.isEmpty, "‘\(input)’ confirmed an empty task")
                #expect(request.task.count <= HandoffRequest.maximumFieldLength)
                #expect((request.doneWhen?.count ?? 0) <= HandoffRequest.maximumFieldLength)
                #expect(request.doneWhen?.isEmpty != true)
                #expect(
                    !request.task.unicodeScalars.contains {
                        CharacterSet.controlCharacters.contains($0)
                    },
                    "‘\(input)’ let a control character through"
                )
                #expect(
                    !(request.doneWhen ?? "").unicodeScalars.contains {
                        CharacterSet.controlCharacters.contains($0)
                    }
                )
            case .rejected:
                break
            }
        }
    }

    /// The generated half: the same shapes, at every length around each cap.
    @Test("generated lengths around both caps")
    func generatedLengths() {
        for length in [0, 1, 499, 500, 501, 4_000, 4_075, 4_076, 4_077, 5_000] {
            let task = String(repeating: "z", count: length)
            let input = "focus://start?task=\(task)"
            let parse = HandoffRequest.parse(input)

            if input.count > HandoffRequest.maximumURLLength {
                #expect(parse == .rejected(.tooLong), "length \(length) should exceed the URL cap")
            } else if length == 0 {
                #expect(parse == .rejected(.missingTask))
            } else {
                let request = parse.request
                #expect(request != nil, "length \(length) was rejected unexpectedly")
                #expect(
                    (request?.task.count ?? 0) == min(length, HandoffRequest.maximumFieldLength)
                )
            }
        }
    }

    @Test("parsing is a pure function: same URL, same answer, no clock")
    func parsingIsPure() {
        for input in HandoffCorpus.strings {
            #expect(HandoffRequest.parse(input) == HandoffRequest.parse(input))
        }
    }

    /// The store-level postcondition, at the level Phase A can assert it: the parser has no
    /// store access at all, so feeding it the whole hostile corpus while a priority is set
    /// leaves every row exactly as it was. The app-level half — no path from `.onOpenURL` to a
    /// mutation without a person pressing Replace — is asserted once `PriorityHost` exists.
    @Test("feeding the whole corpus through the parser leaves the store untouched")
    @MainActor
    func theStoreIsUnchangedByParsing() throws {
        let harness = try PriorityStoreHarness()
        let id = try harness.store.setPriority(intent: "Ship the native shell", doneWhen: "Gate is green")
        try harness.store.addContextItem(
            taskID: id,
            kindRaw: "app",
            value: "com.apple.dt.Xcode",
            displayName: "Xcode"
        )
        try harness.store.addRule(
            taskID: id,
            scopeRaw: "domain",
            subject: "news.example",
            verdictRaw: "unrelated"
        )

        let before = try snapshot(harness)

        for input in HandoffCorpus.strings {
            _ = HandoffRequest.parse(input)
        }

        #expect(try snapshot(harness) == before, "parsing a URL changed the store")
        #expect(try harness.store.activeTask()?.id == id)
        #expect(try harness.store.activeTask()?.intent == "Ship the native shell")
    }

    /// Everything about the store that a handoff could conceivably have touched.
    @MainActor
    private func snapshot(_ harness: PriorityStoreHarness) throws -> [String] {
        var lines: [String] = []
        for task in try harness.store.recentTasks() {
            lines.append(
                "task \(task.id) \(task.intent) \(task.doneWhen ?? "-") \(task.revision) "
                    + "\(task.isActive) \(String(describing: task.completedAt))"
            )
        }
        for item in try harness.contextItems().sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            lines.append("item \(item.id) \(item.kindRaw) \(item.value) \(item.displayName)")
        }
        for rule in try harness.rules().sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            lines.append("rule \(rule.id) \(rule.scopeRaw) \(rule.subject) \(rule.verdictRaw)")
        }
        lines.append("pointers \(try harness.store.activePointerCount())")
        return lines
    }
}
