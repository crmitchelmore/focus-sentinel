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

    @Test("no endpoint, or one that is not HTTPS, is off")
    func offWithoutAnHTTPSEndpoint() {
        #expect(RemoteJudgeConfiguration.parse(endpoint: nil, deployment: nil, threshold: nil) == nil)
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

    @Test("an unconfigured defaults domain is off")
    func emptyDefaultsAreOff() throws {
        let suite = "DecisionOneProtocolTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RemoteJudgeConfiguration.read(from: defaults) == nil)
        defaults.set("https://example.com", forKey: RemoteJudgeConfiguration.endpointKey)
        #expect(RemoteJudgeConfiguration.read(from: defaults) != nil)
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

    @Test("with no window offered the judge declines before asking for a token or a connection")
    @MainActor
    func declinesWithoutAWindow() async throws {
        let source = RemoteJudgeContextSource()
        let configuration = try #require(
            RemoteJudgeConfiguration.parse(endpoint: "https://example.invalid", deployment: nil, threshold: nil)
        )
        let judge = DecisionOneJudge(configuration: configuration, source: source)
        let request = ModelRequest(
            cacheKey: "k",
            priorityTokens: [],
            subject: try #require(NormalisedToken.normalised("com.example")),
            priorityRevision: 1
        )
        #expect(await judge.judge(request) == .decline(.refused))

        var asked = 0
        source.provide = { _ in
            asked += 1
            return nil
        }
        #expect(await judge.judge(request) == .decline(.refused))
        #expect(asked == 1)
    }

    @Test("an offered window is read and paired with the task")
    @MainActor
    func sourcePairsTaskAndWindow() async throws {
        let source = RemoteJudgeContextSource()
        let window = RemoteWindowContext(
            applicationName: nil, bundleIdentifier: "com.example", title: nil,
            webAddress: nil, openFile: nil, focused: nil, text: "x"
        )
        source.provide = { _ in .init(task: "Write the report", read: { window }) }
        let request = ModelRequest(
            cacheKey: "k",
            priorityTokens: [],
            subject: try #require(NormalisedToken.normalised("com.example")),
            priorityRevision: 1
        )
        #expect(await source.input(for: request) == RemoteJudgeInput(task: "Write the report", window: window))
    }
}
