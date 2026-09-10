import Foundation
import Testing

@testable import FocusCore

/// Askability, and the five silences U-1 does **not** dissolve (R-77, F-46).
///
/// U-1 inverts the default: the app speaks when it cannot tell. This suite is the boundary of
/// that inversion — the mapping from a typed `UncertaintyReason` to a question is total, it is
/// decided in one place, and the five reasons that must stay silent are asserted **by name**
/// rather than by counting, so that moving one of them is a failing test with a sentence in it
/// rather than an arithmetic surprise.
@Suite("Queryable uncertainty")
struct QueryableUncertaintyTests {
    /// The three askable reasons, written out here independently of the switch under test.
    /// Two statements of one contract: if either drifts, this fails and says which case.
    static let askable: Set<UncertaintyReason> = [
        .noNegativeBasis, .mixedUseApplication, .languageNotSupported
    ]

    /// The five unaskable ones, likewise — and each paired with the sentence that says why,
    /// which is what a failure message quotes.
    static let unaskable: [(UncertaintyReason, String)] = [
        (
            .noIdentifiableSubject,
            "there is no subject: a rule cannot be written about a process with no bundle "
                + "identifier, so the question has no answer to store"
        ),
        (
            .noEvidence,
            "the app deliberately did not look — a sensitive application, a private window, a "
                + "suppressed activation. \"We did not look\" must never become \"tell us what "
                + "you were doing.\""
        ),
        (
            .insufficientPriorityEvidence,
            "the priority is \"stuff\": the honest affordance is the refinement strip on the "
                + "capture field, not a per-app question under a sentence about to be rewritten"
        ),
        (
            .conflictingRules,
            "two rules the person already wrote disagree: the affordance is to resolve the "
                + "conflict, not to add a third rule on top of a contradiction"
        ),
        (
            .staleSnapshot,
            "the priority revision moved under the classification. That is our bug, not their "
                + "question"
        )
    ]

    @Test("the mapping is total over every UncertaintyReason")
    func mappingIsTotal() {
        // Every case resolves without trapping, and the two lists above partition the enum.
        var seen: Set<UncertaintyReason> = []
        for reason in UncertaintyReason.allCases {
            seen.insert(reason)
            if Self.askable.contains(reason) {
                #expect(reason.queryable != nil, "\(reason.rawValue) should be askable")
            } else {
                #expect(
                    reason.queryable == nil,
                    "\(reason.rawValue) is not in the askable list but produced a question"
                )
            }
        }
        #expect(seen.count == UncertaintyReason.allCases.count)

        let namedUnaskable = Set(Self.unaskable.map(\.0))
        #expect(
            Self.askable.union(namedUnaskable) == Set(UncertaintyReason.allCases),
            "a reason exists that this suite has not decided the askability of"
        )
        #expect(Self.askable.intersection(namedUnaskable).isEmpty)
    }

    /// **`noEvidence` is unaskable, by name.** The single most important row of R-77's table.
    @Test("noEvidence is unaskable, and the reason is quoted when it is not")
    func noEvidenceIsUnaskable() {
        #expect(
            UncertaintyReason.noEvidence.queryable == nil,
            """
            noEvidence produced a question. The app deliberately did not look — a sensitive \
            application, a private window, an activation the sensitivity gate suppressed \
            before the engine saw it. Asking "is this part of your task?" about a password \
            manager tells the person we noticed. "We did not look" must never become "tell us \
            what you were doing." (R-77, and UncertaintyReason.noEvidence's own doc comment.)
            """
        )
        #expect(UncertaintyReason.noEvidence.isQueryable == false)
    }

    @Test("each of the five unaskable reasons stays silent, and says why")
    func theFiveSilences() {
        for (reason, why) in Self.unaskable {
            #expect(
                reason.queryable == nil,
                "\(reason.rawValue) became askable — \(why)"
            )
            #expect(reason.isQueryable == false)
        }
        #expect(Self.unaskable.count == 5)
    }

    /// P-138's arithmetic, restated as a property of the vocabulary rather than of a spreadsheet.
    @Test("three of the eight reasons are askable")
    func threeOfEight() {
        let askableCount = UncertaintyReason.allCases.filter(\.isQueryable).count
        #expect(UncertaintyReason.allCases.count == 8)
        #expect(askableCount == QueryableUncertainty.allCases.count)
        #expect(askableCount == 3)
    }

    @Test("the two vocabularies round-trip in both directions")
    func roundTrip() {
        for askable in QueryableUncertainty.allCases {
            #expect(askable.reason.queryable == askable)
        }
        for reason in UncertaintyReason.allCases {
            guard let askable = reason.queryable else { continue }
            #expect(askable.reason == reason)
            #expect(askable.rawValue == reason.rawValue)
        }
    }

    @Test("every askable reason has its own copy key")
    func copyKeys() {
        var keys: Set<String> = []
        for askable in QueryableUncertainty.allCases {
            #expect(askable.copyKey == "nudge.query.reason.\(askable.rawValue)")
            #expect(keys.insert(askable.copyKey).inserted, "duplicate copy key")
        }
    }

    /// Gate lane only: `swift test` copies the String Catalog verbatim, so every key resolves
    /// to itself in the inner loop. `xcodebuild test` compiles it, and that is the lane in
    /// which a missing entry is a real failure (e01's `LocalizationLane` doctrine).
    @Test(
        "no query reason resolves to its own key",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func copyResolves() {
        for askable in QueryableUncertainty.allCases {
            let rendered = String(localized: askable.copyResource)
            #expect(rendered != askable.copyKey, "\(askable.copyKey) resolves to its own name")
            #expect(!rendered.isEmpty)
        }
    }

    @Test("QueryableUncertainty round-trips through Codable on its raw value")
    func codableRoundTrip() throws {
        for askable in QueryableUncertainty.allCases {
            let data = try JSONEncoder().encode(askable)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(askable.rawValue)\"")
            #expect(try JSONDecoder().decode(QueryableUncertainty.self, from: data) == askable)
        }
    }
}

/// The subject a question is about, and the two places it is allowed to come from (R-76).
@Suite("Query subject")
struct QuerySubjectTests {
    static let stamp = EngineStamp.current

    static func explanation(_ clauses: [ExplanationClause]) -> Explanation {
        Explanation.make(stage: .heuristic, band: .low, clauses: clauses, stamp: stamp)
    }

    /// The `noNegativeBasis` shape: an explanation that names nothing, and an activation that
    /// names the application in front of the person. This is 32 of the corpus's 72 uncertain
    /// verdicts, so a design in which it produced no subject would produce no questions.
    @Test("a judged activation names the subject when the explanation names none")
    func judgedActivationIsUsed() throws {
        let subject = try #require(
            QuerySubject.derive(
                judgedSubject: "com.apple.Safari",
                explanation: Self.explanation([
                    .noNegativeBasis, .insufficientEvidence(reason: .noNegativeBasis)
                ])
            )
        )
        #expect(subject.identifier == "com.apple.Safari")
        #expect(subject.kind == .app)
        #expect(subject.provenance == .judgedActivation)
        #expect(subject.description == "com.apple.Safari")
    }

    /// The `mixedUseApplication` shape: the seed fallback names its own subject, and that is a
    /// better-evidenced answer than the activation, so it wins.
    @Test("an explanation clause outranks the activation when it names a subject")
    func explanationClauseWins() throws {
        let seed = try #require(NormalisedToken.normalised("com.apple.Safari"))
        let subject = try #require(
            QuerySubject.derive(
                judgedSubject: "com.apple.Safari",
                explanation: Self.explanation([.seedFallbackMixedUse(subject: seed)])
            )
        )
        #expect(subject.identifier == "com.apple.Safari")
        #expect(subject.provenance == .explanationClause)
    }

    /// P-140's finding, as a type-level fact: an askable case with **no bundle identifier**
    /// (`gc-0011`, `gc-0139`) cannot produce a subject, so it cannot produce a question.
    @Test("no identifier, no subject — and therefore no question")
    func noIdentifierYieldsNoSubject() {
        let none = Self.explanation([.insufficientEvidence(reason: .noNegativeBasis)])
        #expect(QuerySubject.derive(judgedSubject: nil, explanation: none) == nil)
        #expect(QuerySubject.derive(judgedSubject: "", explanation: none) == nil)
        #expect(QuerySubject.derive(judgedSubject: "   ", explanation: none) == nil)
        // e04 writes `""` into a mandate's subject when drift is mixed. The same empty string
        // must not become a question about nothing.
        #expect(QuerySubject.derive(judgedSubject: "", explanation: none) == nil)
    }

    /// A subject that is neither named by the explanation nor judged is unrepresentable: the
    /// two branches of `derive` are the only two, and each returns one of its own inputs.
    @Test("a subject is always one of the judgement's own two sources")
    func neverInventsASubject() throws {
        let seed = try #require(NormalisedToken.normalised("com.tinyspeck.slackmacgap"))
        let cases: [(String?, [ExplanationClause])] = [
            ("com.apple.Safari", [.noNegativeBasis]),
            ("com.apple.Safari", [.seedFallbackMixedUse(subject: seed)]),
            ("https://docs.google.com", [.sustainedDwell(seconds: 90)]),
            (nil, [.seedDefault(disposition: .askEachTime, subject: seed)])
        ]
        for (judged, clauses) in cases {
            let explanation = Self.explanation(clauses)
            guard let subject = QuerySubject.derive(
                judgedSubject: judged, explanation: explanation
            ) else { continue }
            let permitted = Set(explanation.tokens.map(\.value) + [judged].compactMap { $0 })
            #expect(
                permitted.contains(subject.identifier),
                "derive() named \(subject.identifier), which the judgement never used"
            )
        }
    }

    /// e07's narrowing, available already: a normalised origin bands as `.domain` without any
    /// change to this type, the query, the ledger or the metric.
    @Test("a normalised origin is a domain subject; everything else is an app subject")
    func kindIsInferredFromTheShape() throws {
        let origin = try #require(
            QuerySubject.derive(
                judgedSubject: "https://docs.google.com",
                explanation: Self.explanation([.noNegativeBasis])
            )
        )
        #expect(origin.kind == .domain)

        let app = try #require(
            QuerySubject.derive(
                judgedSubject: "com.apple.Safari",
                explanation: Self.explanation([.noNegativeBasis])
            )
        )
        #expect(app.kind == .app)
    }

    /// A subject a rule *already* decided is never taken from the explanation. Asking about a
    /// context item or a user rule would be the app failing to read its own notes, which
    /// `nudge.queryOnDecidableCount == 0` gates at exactly zero.
    @Test("a context item or a user rule is never harvested as a query subject")
    func decidedSubjectsAreNotHarvested() throws {
        let named = try #require(NormalisedToken.normalised("com.apple.Notes"))
        let fromContext = QuerySubject.derive(
            judgedSubject: nil,
            explanation: Self.explanation([.contextItem(kind: .app, subject: named)])
        )
        #expect(fromContext == nil)

        let fromRule = QuerySubject.derive(
            judgedSubject: nil,
            explanation: Self.explanation([
                .userRule(authority: .task, kind: .app, subject: named)
            ])
        )
        #expect(fromRule == nil)
    }
}
