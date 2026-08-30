import FocusCore
import Foundation
import Testing

@testable import FocusUI

/// **Every list draws the name; every key stays a key** (focus-7zr).
///
/// The suite is written about the whole table rather than about the rows the bead happened to
/// name, for the reason `SubjectSentenceTests` gives: the defect it repairs shipped with proofs
/// standing over it, and every one of those proofs was about a single cell.
///
/// Two rules it keeps:
///
/// * **the lookup is recorded, not just stubbed.** "It drew the host for an origin" is satisfied
///   by an implementation that asked LaunchServices what application owns `https://example.com`
///   and ignored the answer. The count is what says it never asked.
/// * **every assertion is a pair.** The name is asserted present *and* the key absent, because a
///   row reading `Safari (com.apple.Safari)` contains the name too.
@Suite("What a stored subject is called on screen")
@MainActor
struct SubjectDisplayTests {
    /// A workspace lookup that answers from a table and remembers every question.
    final class Lookup {
        var names: [String: String] = ["com.apple.Safari": "Safari", "com.figma.Desktop": "Figma"]
        private(set) var asked: [String] = []

        func name(_ identifier: String) -> String? {
            asked.append(identifier)
            return names[identifier]
        }
    }

    // MARK: - The rules list, over every scope it can hold

    /// One row of the table: a scope, a subject, what the row must read, and whether the disk
    /// should have been consulted at all.
    struct RuleCase: Sendable, CustomStringConvertible {
        let scope: PriorityRuleScope
        let subject: String
        let expected: String
        let asks: Bool

        var description: String { "\(scope.rawValue) \(subject)" }
    }

    nonisolated static let ruleCases: [RuleCase] = [
        // An application. The row read the identifier, three feet from a chip reading the name.
        RuleCase(scope: .app, subject: "com.apple.Safari", expected: "Safari", asks: true),
        // An application nothing on this Mac answers to. The key is the last resort and stays.
        RuleCase(
            scope: .app, subject: "com.example.Gone", expected: "com.example.Gone", asks: true
        ),
        // An origin. `ContextItemValue.displayName(forOrigin:)` exists precisely to strip the
        // scheme, and the rules list rendered `https://news.example.com` without it.
        RuleCase(
            scope: .domain, subject: "https://news.example.com",
            expected: "news.example.com", asks: false
        ),
        // An origin with a port keeps it: the port is part of what a person recognises the thing
        // by, and `displayName(forOrigin:)` says so.
        RuleCase(
            scope: .domain, subject: "http://localhost:8080", expected: "localhost:8080",
            asks: false
        ),
        // A domain rule that failed normalisation is stored as typed and drawn as typed.
        RuleCase(
            scope: .domain, subject: "news.example.com", expected: "news.example.com", asks: false
        ),
        // A word the person typed. There is nothing to look up and no lookup is made.
        RuleCase(scope: .titleToken, subject: "proposal", expected: "proposal", asks: false)
        // **`.session` is deliberately absent, and that is R-70n rather than an omission.**
        // A persisted row scoped `.session` is the ambiguous legacy shape — it names no subject
        // kind — and `check-forbidden.sh` bans constructing one outside four named files, so a
        // row here would have had to widen that allow-list to make a test pass. The arm is
        // covered instead by `everyScopeDeclaresWhatItIs` below, which asks the policy directly
        // and is total over the enum, and by the shape cases in `originsAreRefusedByShape` and
        // `applicationListsDrawNames`, which are what that arm delegates to.
    ]

    @Test("a rule row draws the name for its scope, and asks the disk only when there is a bundle",
          arguments: ruleCases)
    func ruleRowsDrawNames(row: RuleCase) {
        let lookup = Lookup()
        let rule = PriorityRuleValue(
            id: UUID(), scope: row.scope, subject: row.subject,
            verdict: .relevant, createdAt: Date(timeIntervalSince1970: 0)
        )

        let drawn = SubjectDisplay.name(of: rule, installedName: lookup.name)

        #expect(drawn == row.expected)
        // The pair. A row that read `Safari (com.apple.Safari)` would satisfy the line above.
        if drawn != row.subject {
            #expect(!drawn.contains(row.subject), "\(row) still draws its key: \(drawn)")
        }
        #expect(lookup.asked == (row.asks ? [row.subject] : []), "\(row) asked: \(lookup.asked)")
        // **The key is untouched.** Every rule, receipt, snooze and budget row is filed under
        // this, and a naming change that moved it would be a data defect wearing a copy fix.
        #expect(rule.subject == row.subject)
    }

    /// **Totality over the scope enum, and the one arm the table above cannot reach.**
    ///
    /// `SubjectDisplay.resolvesApplication(_:)` is the whole scope policy, and asking it directly
    /// covers `.session` — which no test may construct a rule for (R-70n) — without planting the
    /// ambiguous row. A fifth scope has to be given an answer here before this compiles, and a
    /// scope that changed sides shows up as a changed expectation rather than as a picture.
    @Test("every scope the cockpit can hold declares whether it names an application")
    func everyScopeDeclaresWhatItIs() {
        let expected: [PriorityRuleScope: Bool] = [
            .app: true,
            // Says how long the rule lives, not what it is about. Asking is the honest default:
            // the shape check inside `name(of:resolvingApplication:)` still refuses an origin,
            // so the worst case is one LaunchServices lookup that answers nothing.
            .session: true,
            .domain: false,
            .titleToken: false
        ]
        #expect(Set(expected.keys) == Set(PriorityRuleScope.allCases))
        for scope in PriorityRuleScope.allCases {
            #expect(SubjectDisplay.resolvesApplication(scope) == expected[scope])
        }

        // The rows above cover every scope this suite is permitted to build a rule for, so a
        // new constructible scope cannot slip past the table either.
        let constructible = Set(PriorityRuleScope.allCases).subtracting([.session])
        #expect(Set(Self.ruleCases.map(\.scope)) == constructible)
    }

    // MARK: - The exclusions list and the interruption sheet, which are always applications

    @Test(
        "an application list draws the name and falls back to the key",
        arguments: [
            ("com.apple.Safari", "Safari"),
            ("com.example.Deck", "com.example.Deck")
        ]
    )
    func applicationListsDrawNames(subject: String, expected: String) {
        let lookup = Lookup()
        #expect(
            SubjectDisplay.name(
                of: subject, resolvingApplication: true, installedName: lookup.name
            ) == expected
        )
        #expect(lookup.asked == [subject])
    }

    /// The measured whitespace case, at this seam too: `FileManager.displayName` answers `"   "`
    /// for a bundle called `   .app`, and a row that drew it would be an empty row with a
    /// remove button beside it and nothing to say what removing it would remove.
    @Test("a bundle whose name is whitespace draws its key", arguments: ["", "   ", "\n\t"])
    func whitespaceNamesFallBackToTheKey(blank: String) {
        let lookup = Lookup()
        lookup.names["com.example.Blank"] = blank
        #expect(
            SubjectDisplay.name(
                of: "com.example.Blank", resolvingApplication: true, installedName: lookup.name
            ) == "com.example.Blank"
        )
    }

    /// An origin never reaches LaunchServices even when the caller asks for an application name:
    /// no application owns a website, so the only answer available would be a browser's.
    @Test("an origin is refused by shape, whatever the caller said")
    func originsAreRefusedByShape() {
        let lookup = Lookup()
        #expect(
            SubjectDisplay.name(
                of: "https://docs.example.com", resolvingApplication: true,
                installedName: lookup.name
            ) == "docs.example.com"
        )
        #expect(lookup.asked.isEmpty)
    }
}
