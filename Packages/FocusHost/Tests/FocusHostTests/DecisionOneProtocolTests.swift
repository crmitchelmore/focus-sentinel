import FocusClassify
import FocusCore
import Foundation
import Testing

@testable import FocusHost

/// **The opt-in remote judge, everything but the network** (Decision-1).
///
/// The exchange itself is not driven here: a test that reached the endpoint would be a test that
/// needs a signed-in Azure CLI and sends a window off the machine. What is pinned is every
/// decision either side of it — when the judge is on, what it would send, how it reads the
/// answer, and that it declines without reading anything when no window is offered.
@Suite("Remote judge (Decision-1)")
struct DecisionOneProtocolTests {
    // MARK: Configuration

    @Test("no endpoint takes the measured one; an endpoint that is not HTTPS is off")
    func offWithoutAnHTTPSEndpoint() {
        #expect(
            RemoteJudgeConfiguration.parse(endpoint: nil, deployment: nil, threshold: nil)?.endpoint
                == RemoteJudgeConfiguration.defaultEndpoint
        )
        #expect(RemoteJudgeConfiguration.parse(endpoint: "", deployment: nil, threshold: nil) == nil)
        #expect(RemoteJudgeConfiguration.parse(endpoint: "http://example.com", deployment: nil, threshold: nil) == nil)
        #expect(RemoteJudgeConfiguration.parse(endpoint: 42, deployment: nil, threshold: nil) == nil)
    }

    @Test("an HTTPS endpoint alone takes the measured deployment and threshold")
    func defaults() throws {
        let configuration = try #require(
            RemoteJudgeConfiguration.parse(endpoint: " https://example.com ", deployment: nil, threshold: nil)
        )
        #expect(configuration.endpoint.absoluteString == "https://example.com")
        #expect(configuration.deployment == "decision-1")
        #expect(configuration.threshold == 0.6)
    }

    @Test("a malformed or out-of-range value turns it off rather than being guessed at")
    func malformedValuesAreOff() {
        let endpoint = "https://example.com"
        #expect(RemoteJudgeConfiguration.parse(endpoint: endpoint, deployment: "", threshold: nil) == nil)
        #expect(RemoteJudgeConfiguration.parse(endpoint: endpoint, deployment: 3, threshold: nil) == nil)
        #expect(RemoteJudgeConfiguration.parse(endpoint: endpoint, deployment: nil, threshold: 0.2) == nil)
        #expect(RemoteJudgeConfiguration.parse(endpoint: endpoint, deployment: nil, threshold: "high") == nil)
        #expect(RemoteJudgeConfiguration.parse(endpoint: endpoint, deployment: nil, threshold: "0.7")?.threshold == 0.7)
        #expect(RemoteJudgeConfiguration.parse(endpoint: endpoint, deployment: "mine", threshold: 0.8)?.deployment == "mine")
    }

    @Test("an unconfigured defaults domain is configured but switched off")
    func emptyDefaultsAreSwitchedOff() throws {
        let suite = "DecisionOneProtocolTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RemoteJudgeConfiguration.read(from: defaults)?.endpoint == RemoteJudgeConfiguration.defaultEndpoint)
        #expect(RemoteJudgeSwitch.read(from: defaults).isOn == false)
        defaults.set(true, forKey: RemoteJudgeConfiguration.enabledKey)
        #expect(RemoteJudgeSwitch.read(from: defaults).isOn)
        defaults.set("http://example.com", forKey: RemoteJudgeConfiguration.endpointKey)
        #expect(RemoteJudgeConfiguration.read(from: defaults) == nil)
    }

    // MARK: Reaching it

    @Test("only a status that says the judge could not be reached starts the quiet minute")
    func unreachableStatuses() {
        for status in [401, 403, 408, 429, 500, 503, 599] {
            #expect(DecisionOneJudge.isUnreachable(status: status), "\(status)")
        }
        for status in [200, 400, 404, 413, 422] {
            #expect(!DecisionOneJudge.isUnreachable(status: status), "\(status)")
        }
    }

    @Test("after an unreachable judge every judgement inside a minute declines; reaching it ends that")
    func backoffIsAMinute() {
        let start = ContinuousClock.now
        let clock = Clock(start)
        let backoff = RemoteJudgeBackoff(now: { clock.now })
        #expect(!backoff.isCoolingDown)
        backoff.noteUnreachable()
        #expect(backoff.isCoolingDown)
        clock.now = start + .seconds(59)
        #expect(backoff.isCoolingDown)
        clock.now = start + .seconds(60)
        #expect(!backoff.isCoolingDown)
        backoff.noteUnreachable()
        #expect(backoff.isCoolingDown)
        backoff.noteReached()
        #expect(!backoff.isCoolingDown)
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var instant: ContinuousClock.Instant
        init(_ instant: ContinuousClock.Instant) { self.instant = instant }
        var now: ContinuousClock.Instant {
            get { lock.withLock { instant } }
            set { lock.withLock { instant = newValue } }
        }
    }

    // MARK: What is sent

    @Test("a web address keeps its host and path and loses credentials, query and fragment")
    func webAddressReduction() {
        #expect(
            RemoteWindowContext.reducedWebAddress("https://user:pw@example.com/a/b?token=x#frag")
                == "https://example.com/a/b"
        )
        #expect(RemoteWindowContext.reducedWebAddress("file:///Users/me/notes.md") == nil)
        #expect(RemoteWindowContext.reducedWebAddress("about:blank") == nil)
        #expect(RemoteWindowContext.reducedWebAddress(nil) == nil)
    }

    @Test("an open file is a file URL's path and nothing else")
    func openFile() {
        #expect(RemoteWindowContext.filePath(fromDocument: "file:///Users/me/My%20Plan.md") == "/Users/me/My Plan.md")
        #expect(RemoteWindowContext.filePath(fromDocument: "https://example.com/a") == nil)
        #expect(RemoteWindowContext.filePath(fromDocument: nil) == nil)
    }

    @Test("the window is stated in the format the evidence was measured on, and bounded")
    func formatted() {
        let long = String(repeating: "a", count: RemoteWindowContext.maximumTextLength + 10)
        let window = RemoteWindowContext(
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            title: "  Pricing  ",
            webAddress: "https://example.com/pricing",
            openFile: nil,
            focused: "AXTextField · Search",
            text: long
        )
        let lines = window.formatted.components(separatedBy: "\n")
        #expect(lines[0] == "Application: Safari (com.apple.Safari)")
        #expect(lines[1] == "Window title: Pricing")
        #expect(lines[2] == "Web address: https://example.com/pricing")
        #expect(lines[3] == "Focused element: AXTextField · Search")
        #expect(lines[4] == "Text in the window, read through Accessibility (truncated):")
        #expect(lines[5].count == RemoteWindowContext.maximumTextLength)

        let bare = RemoteWindowContext(
            applicationName: nil, bundleIdentifier: "com.example", title: nil,
            webAddress: nil, openFile: nil, focused: nil, text: "x"
        )
        #expect(bare.formatted == """
            Application: com.example
            Window title: (none)
            Text in the window, read through Accessibility:
            x
            """)
    }

    @Test("the body is one choice question carrying the task and the window")
    func body() throws {
        let window = RemoteWindowContext(
            applicationName: nil, bundleIdentifier: "com.example", title: "T",
            webAddress: nil, openFile: nil, focused: nil, text: "body text"
        )
        let data = try DecisionOneProtocol.body(deployment: "decision-1", task: "Write the report", window: window)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["model"] as? String == "decision-1")
        let state = try #require(root["state"] as? [String: String])
        #expect(state["task"] == "Write the report")
        #expect(state["window"] == window.formatted)
        let questions = try #require(root["questions"] as? [String: Any])
        #expect(questions.keys.sorted() == ["fit"])
        let fit = try #require(questions["fit"] as? [String: Any])
        #expect(fit["type"] as? String == "choice")
        #expect((fit["criteria"] as? [String: String])?.keys.sorted() == ["cannot_tell", "direct", "supporting", "unrelated"])
    }

    @Test("with nothing more known the body is the measured one: no work key, the measured preamble")
    func bodyWithoutWork() throws {
        let window = RemoteWindowContext(
            applicationName: nil, bundleIdentifier: "com.example", title: "T",
            webAddress: nil, openFile: nil, focused: nil, text: "x"
        )
        let data = try DecisionOneProtocol.body(
            deployment: "d", task: "Write the report", window: window, work: RemoteWorkContext(doneWhen: "  \n ")
        )
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let state = try #require(root["state"] as? [String: String])
        #expect(state.keys.sorted() == ["task", "window"])
        let fit = try #require((root["questions"] as? [String: Any])?["fit"] as? [String: Any])
        #expect(fit["instructions"] as? String == DecisionOneProtocol.preamble + " Which describes this window?")
    }

    @Test("what else the app knows travels as one work block, and the preamble says how to use it")
    func bodyWithWork() throws {
        let window = RemoteWindowContext(
            applicationName: nil, bundleIdentifier: "com.example", title: "T",
            webAddress: nil, openFile: nil, focused: nil, text: "x"
        )
        let work = RemoteWorkContext(
            doneWhen: "Sent to Dana",
            contextItems: ["Keyword: acme"],
            steps: ["Update the pricing table"],
            busyToday: ["09:00–10:00", "14:00–15:30"],
            clock: "11:42"
        )
        #expect(work.formatted == """
            Done when: Sent to Dana
            Attached to this task:
            - Keyword: acme
            Steps of this task:
            - Update the pricing table
            Busy today (it is now 11:42): 09:00–10:00, 14:00–15:30
            """)
        let data = try DecisionOneProtocol.body(deployment: "d", task: "Write the report", window: window, work: work)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let state = try #require(root["state"] as? [String: String])
        #expect(state["work"] == work.formatted)
        let fit = try #require((root["questions"] as? [String: Any])?["fit"] as? [String: Any])
        #expect(fit["instructions"] as? String
            == DecisionOneProtocol.preamble + DecisionOneProtocol.workPreamble + " Which describes this window?")
    }

    @Test("work lists are capped, lines flattened and trimmed, and blank entries dropped")
    func workIsBounded() {
        let many = (1...30).map { "Task \($0)" }
        let work = RemoteWorkContext(steps: ["", "  "] + many + [String(repeating: "a", count: 500)])
        let lines = work.formatted.split(separator: "\n")
        #expect(lines.count == 1 + RemoteWorkContext.maximumItems)
        #expect(lines.last == "- Task 12")
        let long = RemoteWorkContext(doneWhen: "one\ntwo " + String(repeating: "b", count: 500))
        #expect(long.formatted.hasPrefix("Done when: one two "))
        #expect(long.formatted.count == "Done when: ".count + RemoteWorkContext.maximumLineLength + 1)
    }

    @Test("today's busy time reads as clock ranges in the calendar's zone, and unread is nothing")
    func busyToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let midnight = Date(timeIntervalSince1970: 1_760_000_000 - 1_760_000_000.truncatingRemainder(dividingBy: 86_400))
        let day = CalendarDay.read(
            span: DateInterval(start: midnight, duration: 86_400),
            busy: [CalendarBusyBlock(start: midnight.addingTimeInterval(9 * 3600), end: midnight.addingTimeInterval(10.5 * 3600))],
            now: midnight.addingTimeInterval(11 * 3600 + 42 * 60)
        )
        let busy = RemoteWorkContext.busy(day, calendar: calendar)
        #expect(busy.blocks == ["09:00–10:30"])
        #expect(busy.clock == "11:42")
        #expect(RemoteWorkContext.busy(.unread, calendar: calendar).blocks.isEmpty)
    }

    // MARK: How the answer is read

    @Test("the documented response shape gives its probabilities; anything else gives nil")
    func probabilities() {
        let good = Data(#"{"answers":{"fit":{"probabilities":{"direct":0.7,"supporting":0.2,"unrelated":0.1}}}}"#.utf8)
        #expect(DecisionOneProtocol.probabilities(from: good) == ["direct": 0.7, "supporting": 0.2, "unrelated": 0.1])
        #expect(DecisionOneProtocol.probabilities(from: Data("{}".utf8)) == nil)
        #expect(DecisionOneProtocol.probabilities(from: Data("not json".utf8)) == nil)
        let wrongType = Data(#"{"answers":{"fit":{"probabilities":{"direct":"high"}}}}"#.utf8)
        #expect(DecisionOneProtocol.probabilities(from: wrongType) == nil)
    }

    @Test("a score at or above the threshold rescues; below it declines; nothing accuses")
    func answerMapping() {
        #expect(DecisionOneProtocol.answer(from: ["direct": 0.5, "supporting": 0.1], threshold: 0.6) == .relevant(.direct))
        #expect(DecisionOneProtocol.answer(from: ["direct": 0.2, "supporting": 0.4], threshold: 0.6) == .relevant(.supporting))
        #expect(DecisionOneProtocol.answer(from: ["direct": 0.3, "supporting": 0.29], threshold: 0.6) == .decline(.modelSaidUnrelated))
        #expect(DecisionOneProtocol.answer(from: ["unrelated": 1], threshold: 0.6) == .decline(.modelSaidUnrelated))
    }

    // MARK: No window, no request

    @Test("with no window offered the judge declines, uncached, before asking for a token or a connection")
    @MainActor
    func declinesWithoutAWindow() async throws {
        let source = RemoteJudgeContextSource()
        let configuration = try #require(
            RemoteJudgeConfiguration.parse(endpoint: "https://example.invalid", deployment: nil, threshold: nil)
        )
        let judge = DecisionOneJudge(configuration: configuration, source: source, isEnabled: RemoteJudgeSwitch(isOn: true))
        let request = Self.request
        #expect(await judge.judge(request) == .decline(.notAvailable))

        var asked = 0
        source.provide = { _ in
            asked += 1
            return nil
        }
        #expect(await judge.judge(request) == .decline(.notAvailable))
        #expect(asked == 1)
    }

    @Test("switched off, or quiet after a failure, the judge reads no window at all")
    @MainActor
    func offReadsNothing() async throws {
        let source = RemoteJudgeContextSource()
        var asked = 0
        source.provide = { _ in
            asked += 1
            return nil
        }
        let configuration = try #require(
            RemoteJudgeConfiguration.parse(endpoint: "https://example.invalid", deployment: nil, threshold: nil)
        )
        let isEnabled = RemoteJudgeSwitch(isOn: false)
        let backoff = RemoteJudgeBackoff()
        let judge = DecisionOneJudge(configuration: configuration, source: source, isEnabled: isEnabled, backoff: backoff)
        #expect(await judge.judge(Self.request) == .decline(.notAvailable))
        isEnabled.isOn = true
        backoff.noteUnreachable()
        #expect(await judge.judge(Self.request) == .decline(.notAvailable))
        #expect(asked == 0)
    }

    static let request = ModelRequest(
        cacheKey: "k",
        priorityTokens: [],
        subject: NormalisedToken.normalised("com.example")!,
        priorityRevision: 1
    )

    @Test("an offered window is read and paired with the task")
    @MainActor
    func sourcePairsTaskAndWindow() async throws {
        let source = RemoteJudgeContextSource()
        let window = RemoteWindowContext(
            applicationName: nil, bundleIdentifier: "com.example", title: nil,
            webAddress: nil, openFile: nil, focused: nil, text: "x"
        )
        let work = RemoteWorkContext(doneWhen: "Sent", steps: ["Update the pricing table"])
        source.provide = { _ in .init(task: "Write the report", work: work, read: { window }) }
        let request = ModelRequest(
            cacheKey: "k",
            priorityTokens: [],
            subject: try #require(NormalisedToken.normalised("com.example")),
            priorityRevision: 1
        )
        #expect(await source.input(for: request) == RemoteJudgeInput(task: "Write the report", window: window, work: work))
    }
}
