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

    @Test("an application not on the list is never reduced, whatever its title says")
    func unlistedApplications() {
        for bundle in ["com.apple.Safari", "com.apple.mail", "com.apple.MobileSMS", "com.google.Chrome"] {
            #expect(!SelectedItem.isReadable(bundle))
            #expect(
                SelectedItem.normalise(
                    title: "Quarterly plan — Inbox",
                    applicationName: nil,
                    bundleIdentifier: bundle
                ) == nil
            )
        }
        #expect(SelectedItem.isReadable(Self.copilot))
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
