import Foundation
import Testing
@testable import FocusCore

/// **A window title becomes a short name, and the title is forgotten** (issue #24).
///
/// The reduction is the privacy promise: what leaves `normalise` is the only part of a title
/// anything keeps. So these tests are about what does *not* survive as much as what does.
@Suite("A selected item is reduced from a title, and nothing else of the title survives")
struct SelectedItemTests {
    static let copilot = "com.github.githubapp"
    static let code = "com.microsoft.VSCode"
    static let terminal = "com.apple.Terminal"

    // MARK: - Reduction

    @Test("a Copilot chat title keeps the chat's name and drops the application's")
    func copilotChat() throws {
        let item = try #require(
            SelectedItem.normalise(
                title: "Fix the login race — GitHub Copilot",
                applicationName: "GitHub Copilot",
                bundleIdentifier: Self.copilot
            )
        )
        #expect(item.label == "Fix the login race")
        #expect(item.bundleIdentifier == Self.copilot)
        #expect(item.subject == "com.github.githubapp::Fix the login race")
    }

    @Test("an editor names the folder, which is the last segment, not the open file")
    func editorFolder() throws {
        let item = try #require(
            SelectedItem.normalise(
                title: "RuleCascade.swift — focus-sentinel — Visual Studio Code",
                applicationName: "Visual Studio Code",
                bundleIdentifier: Self.code
            )
        )
        #expect(item.label == "focus-sentinel")
    }

    @Test("a terminal's shell and size are not an item; its folder is, by last component")
    func terminalFolder() throws {
        let item = try #require(
            SelectedItem.normalise(
                title: "~/Code/focus-sentinel — -zsh — 120×40",
                applicationName: "Terminal",
                bundleIdentifier: Self.terminal
            )
        )
        #expect(item.label == "focus-sentinel")
        #expect(
            SelectedItem.normalise(
                title: "~ — -zsh — 80×24",
                applicationName: "Terminal",
                bundleIdentifier: Self.terminal
            ) == nil
        )
    }

    @Test("a title that is only the application's name, or a placeholder, names nothing")
    func uninformative() {
        for title in ["GitHub Copilot", "New chat — GitHub Copilot", "", "   "] {
            #expect(
                SelectedItem.normalise(
                    title: title,
                    applicationName: "GitHub Copilot",
                    bundleIdentifier: Self.copilot
                ) == nil,
                "\(title)"
            )
        }
        #expect(
            SelectedItem.normalise(title: nil, applicationName: nil, bundleIdentifier: Self.copilot) == nil
        )
    }

    @Test("every application is read, and only editors take the item from the end of the title")
    func everyApplication() throws {
        for bundle in ["com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS", "com.google.Chrome"] {
            #expect(SelectedItem.segment(for: bundle) == .first)
            let item = try #require(
                SelectedItem.normalise(
                    title: "Quarterly plan — Inbox",
                    applicationName: nil,
                    bundleIdentifier: bundle
                )
            )
            #expect(item.label == "Quarterly plan")
            #expect(item.bundleIdentifier == bundle)
        }
        for bundle in SelectedItem.lastSegmentApplications {
            #expect(SelectedItem.segment(for: bundle) == .last)
        }
        #expect(SelectedItem.segment(for: Self.copilot) == .first)
    }

    @Test("punctuation is dropped and a long title is capped on a word boundary")
    func sanitisedAndCapped() throws {
        let item = try #require(
            SelectedItem.normalise(
                title: "Refactor: the <relevance> engine's \"cascade\" (part 2)!? "
                    + String(repeating: "and more words ", count: 10),
                applicationName: nil,
                bundleIdentifier: Self.copilot
            )
        )
        #expect(item.label.count <= SelectedItem.maximumLabelLength)
        #expect(item.label.allSatisfy { $0.isLetter || $0.isNumber || " -_.".contains($0) })
        #expect(item.label.hasPrefix("Refactor the relevance engine s cascade part 2"))
        #expect(!item.label.hasSuffix(" "))
    }

    @Test("sanitising is idempotent, so a stored label parses back to itself")
    func idempotent() throws {
        let titles = [
            "Fix the login race", "a/b/c", "émigré café — notes", "x::y", "https://example.com",
            "...dots...", "tab\tseparated", String(repeating: "x", count: 90),
        ]
        for title in titles {
            guard let label = SelectedItem.sanitise(title) else { continue }
            #expect(SelectedItem.sanitise(label) == label, "\(title)")
            let item = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: label))
            #expect(SelectedItem.parse(item.subject) == item)
        }
    }

    // MARK: - Text inside the window (issue #26)

    @Test("a heading's one-word caption is dropped, and only its first sentence and line are kept")
    func elementText() throws {
        let session = try #require(
            SelectedItem.normalise(
                elementText: "Session: fix the login race",
                applicationName: "GitHub Copilot",
                bundleIdentifier: Self.copilot
            )
        )
        #expect(session.label == "fix the login race")

        let prose = try #require(
            SelectedItem.normalise(
                elementText: "Plan the release. Then ship it.\nSecond line",
                applicationName: nil,
                bundleIdentifier: Self.copilot
            )
        )
        #expect(prose.label == "Plan the release")

        // A caption that is not one word is part of the name.
        let scoped = try #require(
            SelectedItem.normalise(
                elementText: "fix(mac): the build",
                applicationName: nil,
                bundleIdentifier: Self.copilot
            )
        )
        #expect(scoped.label == "fix mac the build")
    }

    @Test("element text that is the application's name, a placeholder or empty names nothing")
    func uninformativeElementText() {
        for text in ["GitHub Copilot", "Chats", "New chat", "Session: GitHub Copilot", "", "  ", nil] {
            #expect(
                SelectedItem.normalise(
                    elementText: text,
                    applicationName: "GitHub Copilot",
                    bundleIdentifier: Self.copilot
                ) == nil,
                "\(text ?? "nil")"
            )
        }
    }

    // MARK: - The search below the title

    /// A window tree as the search sees it, counting how many elements it read.
    final class Reads { var count = 0 }

    struct Node: SelectedItemNode {
        var kind: SelectedItemNodeKind = .other
        var text: String?
        var nodes: [Node] = []
        var selected: [Node] = []
        var reads: Reads?
        var url: String?

        var children: [Node] { reads?.count += 1; return nodes }
        var selectedRows: [Node] { kind == .collection ? selected : [] }
        var documentURL: String? { url }
    }

    static func search(_ window: Node, stop: @escaping () -> Bool = { false }) -> SelectedItemSearch.Outcome {
        SelectedItemSearch.search(
            from: window,
            applicationName: "GitHub Copilot",
            bundleIdentifier: Self.copilot,
            shouldStop: stop
        )
    }

    @Test("a native sidebar's selected row names the item, through its cell's text")
    func selectedRow() throws {
        let row = Node(nodes: [Node(nodes: [Node(text: "Focus Sentinel")])])
        let sidebar = Node(kind: .collection, nodes: [row], selected: [row])
        let window = Node(nodes: [Node(nodes: [sidebar])])
        let item = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "Focus Sentinel"))
        #expect(Self.search(window) == .found(item))
    }

    @Test("a web sidebar with no selection falls back to the main region's first heading")
    func mainHeading() throws {
        let sidebar = Node(kind: .collection, text: "Sessions", nodes: [Node(text: "Other chat")])
        let stray = Node(kind: .heading, text: "Not in main")
        let main = Node(kind: .mainRegion, nodes: [
            Node(nodes: [Node(kind: .heading, text: "Session: fix the build")]),
            Node(kind: .heading, text: "Second heading"),
        ])
        let window = Node(nodes: [stray, sidebar, main])
        let item = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "fix the build"))
        #expect(Self.search(window) == .found(item))
    }

    @Test("a tree that names nothing says so; one cut short by its budget says it could not tell")
    func budgets() {
        #expect(Self.search(Node(nodes: [Node(), Node(kind: .collection)])) == .nothing)
        #expect(Self.search(Node(nodes: [Node()]), stop: { true }) == .exhausted)

        // A tree far wider than the element budget is read no further than the budget.
        let reads = Reads()
        let leaves = Array(repeating: Node(reads: reads), count: SelectedItemSearch.maximumElements * 3)
        let wide = Node(nodes: leaves, reads: reads)
        #expect(Self.search(wide) == .exhausted)
        #expect(reads.count <= SelectedItemSearch.maximumElements)
    }

    // MARK: - The grace for a failed read (issue #27)

    @Test("a failed read keeps the last item for the same process, briefly; an empty read clears it")
    func grace() throws {
        let item = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "Fix the race"))
        var grace = SelectedItemGrace()
        #expect(grace.resolve(.item(item), pid: 7, now: .seconds(100)) == item)
        #expect(grace.resolve(.failed, pid: 7, now: .seconds(105)) == item)
        #expect(grace.resolve(.failed, pid: 7, now: .seconds(100) + SelectedItemGrace.holdFor) == item)
        // Failures never extend the hold: it is measured from the last read that succeeded.
        #expect(grace.resolve(.failed, pid: 7, now: .seconds(113)) == nil)

        #expect(grace.resolve(.item(item), pid: 7, now: .seconds(200)) == item)
        #expect(grace.resolve(.failed, pid: 8, now: .seconds(201)) == nil)

        #expect(grace.resolve(.item(item), pid: 7, now: .seconds(300)) == item)
        #expect(grace.resolve(.nothing, pid: 7, now: .seconds(301)) == nil)
        #expect(grace.resolve(.failed, pid: 7, now: .seconds(302)) == nil)

        #expect(grace.resolve(.item(item), pid: 7, now: .seconds(400)) == item)
        grace.clear()
        #expect(grace.resolve(.failed, pid: 7, now: .seconds(401)) == nil)
    }

    // MARK: - The stored form

    @Test("a legacy title word, an app and an origin are not item subjects")
    func parseIsStrict() {
        for subject in [
            "proposal", "com.github.githubapp", "https://docs.google.com",
            "com.github.githubapp::", "::label", "com.github.githubapp::Fix: the race",
            "com github::label",
        ] {
            #expect(!SelectedItem.isItemSubject(subject), "\(subject)")
        }
        #expect(SelectedItem.isItemSubject("com.github.githubapp::Fix the login race"))
    }

    @Test("the same item matches across case, and another app's item never does")
    func matching() throws {
        let one = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "Fix the race"))
        let upper = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "FIX THE RACE"))
        let elsewhere = try #require(SelectedItem(bundleIdentifier: Self.code, label: "Fix the race"))
        let other = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "Write the docs"))
        #expect(one.matches(upper))
        #expect(!one.matches(elsewhere))
        #expect(!one.matches(other))
    }

    @Test("decoding re-validates, so a stored value cannot smuggle a raw title")
    func codable() throws {
        let item = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "Fix the race"))
        let data = try JSONEncoder().encode(item)
        #expect(try JSONDecoder().decode(SelectedItem.self, from: data) == item)

        let raw = Data(#"{"bundleIdentifier":"com.github.githubapp","label":"Fix: the race — GitHub Copilot"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(SelectedItem.self, from: raw) }
    }

    // MARK: - The question narrows to the item

    static func explanation() -> Explanation {
        Explanation.make(
            stage: .heuristic,
            band: .low,
            clauses: [.insufficientEvidence(reason: .noNegativeBasis)],
            stamp: .current
        )
    }

    @Test("an item read from the judged application narrows the question to the item")
    func derivesItemSubject() throws {
        let item = try #require(SelectedItem(bundleIdentifier: Self.copilot, label: "Fix the race"))
        let subject = try #require(
            QuerySubject.derive(judgedSubject: Self.copilot, explanation: Self.explanation(), selectedItem: item)
        )
        #expect(subject.kind == .titleToken)
        #expect(subject.identifier == item.subject)
        #expect(subject.provenance == .selectedItem)

        let named = NudgeSubject.of(subject, runningName: "GitHub Copilot")
        #expect(named.displayName == "Fix the race")
        #expect(named.isSelectedItem)
        #expect(NudgeSubject.applicationIdentifier(of: subject.identifier) == Self.copilot)
    }

    @Test("an item from another application, or no item, leaves the question about the app")
    func doesNotNarrowAcrossApplications() throws {
        let item = try #require(SelectedItem(bundleIdentifier: Self.code, label: "focus-sentinel"))
        let subject = try #require(
            QuerySubject.derive(judgedSubject: Self.copilot, explanation: Self.explanation(), selectedItem: item)
        )
        #expect(subject.kind == .app)
        #expect(subject.identifier == Self.copilot)
        #expect(subject.provenance != .selectedItem)

        let plain = try #require(QuerySubject.derive(judgedSubject: Self.copilot, explanation: Self.explanation()))
        #expect(plain.kind == .app)
        #expect(!NudgeSubject.of(plain, runningName: "GitHub Copilot").isSelectedItem)
    }
}
