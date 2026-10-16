import Foundation
import SwiftData
import Testing

@testable import FocusCore

@Suite("Browser content, not the application")
struct BrowserPageTests {
    @Test("only a normalised HTTP path survives; private URL components never do")
    func normalisation() throws {
        let page = try #require(BrowserPage("https://user:password@Docs.Example.com:8443/Team/Plan?token=secret#private"))
        #expect(page.identifier == "https://docs.example.com:8443/Team/Plan")
        #expect(page.origin == "https://docs.example.com:8443")
        #expect(page.path == "/Team/Plan")
        #expect(BrowserPage(page.identifier) == page)
        #expect(BrowserPage("https://example.com")?.identifier == "https://example.com/")
        #expect(BrowserPage("https://example.com/a*b")?.identifier == "https://example.com/a%2Ab")
        for input in ["file:///private/file", "mailto:person@example.com", "about:blank", "/tmp/page",
                      "example.com/page", "https://example.com/\nsecret", "https://example.com/" + String(repeating: "x", count: 2048)] {
            #expect(BrowserPage(input) == nil)
        }
    }

    @Test("the exact page, each enclosing path, and the domain are separate choices")
    func choices() throws {
        let page = try #require(BrowserPage("https://example.com/teams/alpha/plan"))
        #expect(page.answerSubjects == [
            "https://example.com/teams/alpha/plan",
            "https://example.com/teams/alpha/plan/*",
            "https://example.com/teams/alpha/*",
            "https://example.com/teams/*",
            "https://example.com",
        ])
        #expect(BrowserPage("https://example.com/")?.answerSubjects == [
            "https://example.com/", "https://example.com",
        ])
        for path in ["/teams/alpha/", "/teams//alpha", "/Team%20One/plan", "//", "/a///"] {
            let page = try #require(BrowserPage("https://example.com" + path))
            #expect(page.answerSubjects.allSatisfy(page.matches))
        }
        #expect(BrowserPage("https://example.com/teams//alpha")?.answerSubjects == [
            "https://example.com/teams//alpha", "https://example.com/teams//alpha/*",
            "https://example.com/teams//*", "https://example.com/teams/*", "https://example.com",
        ])
    }

    @Test("path matching respects path segments, case, scheme, port and host boundaries")
    func matching() throws {
        let page = try #require(BrowserPage("https://example.com/teams/alpha/plan"))
        for subject in page.answerSubjects { #expect(page.matches(subject)) }
        for subject in [
            "https://example.com/team/*", "https://example.com/Teams/*",
            "https://example.com/teams/beta/*", "http://example.com/teams/*",
            "https://example.com:8443/teams/*", "https://other.example.com/teams/*",
            "https://example.com/teams/alpha", "https://example.com/teams/alpha/plan/",
        ] {
            #expect(!page.matches(subject), "\(subject)")
        }
        #expect(BrowserPage.specificity(of: page.identifier) > BrowserPage.specificity(of: "https://example.com/teams/*"))
        #expect(BrowserPage.specificity(of: "https://example.com/teams/alpha/*") > BrowserPage.specificity(of: "https://example.com/teams/*"))
    }

    @Test("a browser item has an untruncated page identity and exports no path")
    func itemIdentity() throws {
        let page = try #require(BrowserPage("https://example.com/" + String(repeating: "a", count: 100)))
        let item = try #require(SelectedItem(bundleIdentifier: "com.apple.Safari", browserPage: page))
        #expect(item.subject == page.identifier)
        #expect(item.label.count <= SelectedItem.maximumLabelLength)
        #expect(SelectedItem.exportedSubject(item.subject) == page.origin)
        #expect(SelectedItem.exportedSubject(page.origin + "/teams/*") == page.origin)
        #expect(try JSONDecoder().decode(SelectedItem.self, from: JSONEncoder().encode(item)) == item)
        let subject = try #require(QuerySubject.derive(
            judgedSubject: item.bundleIdentifier,
            explanation: CorrectionScopeTests.explanation([.noNegativeBasis]),
            selectedItem: item,
            allowsApplicationScope: false
        ))
        #expect(subject.identifier == page.identifier)
        #expect(subject.kind == .domain)
        #expect(subject.provenance == .selectedItem)
        #expect(NudgeSubject.of(subject).displayName == "example.com/" + String(repeating: "a", count: 100))
        let seedSubject = QuerySubject.derive(
            judgedSubject: item.bundleIdentifier,
            explanation: CorrectionScopeTests.explanation([.seedFallbackMixedUse(
                subject: try #require(NormalisedToken.normalised("com.apple.safari"))
            )]),
            selectedItem: item,
            allowsApplicationScope: false
        )
        #expect(seedSubject?.identifier == page.identifier)
        let other = QuerySubject.derive(
            judgedSubject: "com.google.Chrome",
            explanation: CorrectionScopeTests.explanation([.seedFallbackMixedUse(
                subject: try #require(NormalisedToken.normalised("com.apple.safari"))
            )]),
            selectedItem: item,
            allowsApplicationScope: false
        )
        #expect(other == nil)
    }

    @Test("a missing content reading cannot turn into an application-wide question")
    func noApplicationFallback() throws {
        for bundle in ["com.apple.Safari", "com.github.githubapp", "com.microsoft.VSCode", "com.example.Unknown"] {
            let explanation = CorrectionScopeTests.explanation([.seedFallbackMixedUse(
                subject: try #require(NormalisedToken.normalised(bundle.lowercased()))
            )])
            #expect(QuerySubject.derive(
                judgedSubject: bundle, explanation: explanation, allowsApplicationScope: false
            ) == nil)
            #expect(QueryEligibility.decide(
                outcome: ClassificationOutcome(verdict: .uncertain, source: .heuristic, confidence: 0, band: .low),
                uncertainty: .noNegativeBasis, drift: .aligned, dwelled: .seconds(60),
                dwellSatisfied: true, phase: .focus, status: .uncertain, isUserIdle: false,
                hasActivePriority: true, hasAsked: false, budgetPermits: true,
                interruptionInFlight: false, judgedSubject: bundle, allowsApplicationScope: false,
                explanation: explanation, stamp: .current
            ) == .withheld(.noSingleSubject))
        }
    }

    @Test("the active web document supplies the URL; links and page text never do")
    func browserSearch() throws {
        typealias Node = SelectedItemTests.Node
        let link = Node(text: "https://wrong.example/page", url: "https://wrong.example/page")
        let active = Node(kind: .webArea, nodes: [link], url: "https://example.com/active?secret=x")
        #expect(SelectedItemSearch.browserPage(from: Node(nodes: [link, active]), shouldStop: { false })?.identifier
                == "https://example.com/active")
        #expect(SelectedItemSearch.browserPage(
            from: Node(kind: .webArea, nodes: [link]), shouldStop: { false }
        ) == nil)
        #expect(SelectedItemSearch.browserPage(from: active, shouldStop: { true }) == nil)
    }

    @Test("the ledger learns the chosen scope but settles the question about the exact page",
          arguments: [QueryAnswer.yesAddIt, .no, .notNow])
    @MainActor
    func scopedAnswer(_ answer: QueryAnswer) throws {
        let (ledger, context, task, container) = try QueryLedgerTests.makeLedger()
        defer { withExtendedLifetime(container) {} }
        let pageScope = CorrectionScope.from(CorrectionScopeTests.warrant(subject: "https://example.com/teams/plan"))
        let pathScope = try #require(pageScope.answerScopes.first { $0.subject == "https://example.com/teams/*" })
        let result = try ledger.answer(
            answer, priorityID: task.id, task: task, scope: pathScope, questionScope: pageScope, reason: .noNegativeBasis
        )
        if answer == .notNow {
            #expect(result.persistedRule == nil)
        } else {
            #expect(result.persistedRule?.subject == pathScope.subject)
            #expect(result.persistedRule?.verdict == (answer == .yesAddIt ? .relevant : .unrelated))
        }
        #expect(try ledger.isSettled(priorityID: task.id, subjectKind: .domain, subject: pageScope.subject))
        #expect(try !ledger.isSettled(priorityID: task.id, subjectKind: .domain, subject: pathScope.subject))
        #expect(try context.fetchCount(FetchDescriptor<FocusSchemaV3.RelevanceRule>()) == (answer == .notNow ? 0 : 1))
    }

    @Test("an answer cannot learn an unrelated page or a wider application scope")
    @MainActor
    func invalidScopeIsRefused() throws {
        let (ledger, context, task, container) = try QueryLedgerTests.makeLedger()
        defer { withExtendedLifetime(container) {} }
        let question = CorrectionScope.from(CorrectionScopeTests.warrant(subject: "https://example.com/work/plan"))
        for subject in ["https://other.example.com/work/*", "https://example.com/holiday/*", "com.apple.Safari"] {
            let other = CorrectionScope.from(CorrectionScopeTests.warrant(subject: subject))
            #expect(throws: QueryLedgerError.scopeOutsideQuestion) {
                try ledger.answer(
                    .yesAddIt, priorityID: task.id, task: task, scope: other,
                    questionScope: question, reason: .noNegativeBasis
                )
            }
        }
        #expect(try ledger.count() == 0)
        #expect(try context.fetchCount(FetchDescriptor<FocusSchemaV3.RelevanceRule>()) == 0)
    }
}
