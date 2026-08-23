import FocusCore
import Foundation
import Testing

@testable import FocusClassify

/// Rung 5 (R-56, R-56.1, R-57, R-58, F-44).
///
/// The section that matters most is **the negative basis**. Every other assertion here is about
/// the engine finding relevance; those are about the engine *declining to accuse*, and they are
/// the unit-level half of adversarial family 11. The defect they guard is the worst output this
/// product has: telling somebody they are slacking off while they do the work.
@Suite("Heuristic classifier")
struct HeuristicClassifierTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)
    static let priorityID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    let normalizer = TokenNormalizer()

    /// The productive tools whose reverse-DNS names say nothing about anybody's work. R-56.1's
    /// whole subject, and adversarial family 11's fixture set.
    static let lexicallySilentTools = [
        "com.microsoft.Excel",
        "com.apple.iWork.Numbers",
        "com.apple.iWork.Pages",
        "com.apple.iWork.Keynote",
        "com.apple.Preview",
        "com.apple.dt.Xcode",
        "com.figma.Desktop",
        "com.omnigroup.OmniGraffle"
    ]

    static let realPriorities = [
        "write the q3 proposal for acme",
        "close the bergman audit",
        "ship the release notes for the 2.4 update"
    ]

    func snapshot(
        intent: String = "write the q3 proposal for acme",
        contextPack: [ContextItemValue] = [],
        scorer: SimilarityScorer? = nil
    ) -> RuleSnapshot {
        RuleSnapshotBuilder(normalizer: normalizer, scorer: scorer).build(
            priority: PriorityInput(id: Self.priorityID, revision: 1, intent: intent),
            contextPack: contextPack
        )
    }

    func evidence(
        bundleID: String? = nil,
        origin: String? = nil,
        titleTokens: [String] = [],
        dwellSeconds: Int
    ) -> ClassificationEvidence {
        ClassificationEvidence.make(
            input: ClassificationInput(
                bundleIdentifier: bundleID, origin: origin, titleTokens: titleTokens
            ),
            dwell: .seconds(dwellSeconds),
            normalizer: normalizer
        )
    }

    static func appIdentity(_ bundleID: String) -> ContextItemValue {
        .app(bundleID: bundleID, displayName: bundleID, addedAt: reference)
    }

    static func domainIdentity(_ origin: String) -> ContextItemValue {
        .domain(origin: origin, addedAt: reference)!
    }

    // MARK: - THE NEGATIVE BASIS (R-56.1) — the family-11 defect, at the unit level

    /// **The assertion this ruling exists for.** A well-specified priority, a genuinely
    /// productive application whose tokens share nothing with it, and dwell on **both sides of
    /// the threshold** — including far past it. All `uncertain`, every time.
    ///
    /// Dwell alone must not be able to walk a case across the line, and the only way to prove
    /// that is to put a case on each side of it.
    @Test(
        "a productive tool with a lexically silent name is never unrelated without a basis",
        arguments: lexicallySilentTools, [89, 90, 91, 300, 301, 3_600]
    )
    func aLexicallySilentToolIsNeverAccusedWithoutABasis(bundleID: String, dwell: Int) {
        for intent in Self.realPriorities {
            let answer = HeuristicClassifier().judge(
                evidence: evidence(bundleID: bundleID, dwellSeconds: dwell),
                snapshot: snapshot(intent: intent)
            )
            #expect(answer?.verdict == .uncertain, "\(bundleID) at \(dwell)s under '\(intent)'")
            #expect(answer?.uncertaintyReason == .noNegativeBasis)
            #expect(answer?.band == .low, "a declining answer can never reach the floor")
        }
    }

    /// The discrimination proof: **the same case flips** the moment the person names one thing
    /// they expect to be looking at. The engine is capable of the accusation and is declining
    /// it for a reason, rather than being structurally unable to make it.
    @Test("adding one app identity flips the same case to unrelated past the threshold")
    func oneIdentityFlipsTheSameCase() {
        let subject = "com.microsoft.Excel"
        let without = HeuristicClassifier().judge(
            evidence: evidence(bundleID: subject, dwellSeconds: 91),
            snapshot: snapshot()
        )
        #expect(without?.verdict == .uncertain)
        #expect(without?.uncertaintyReason == .noNegativeBasis)

        let with = HeuristicClassifier().judge(
            evidence: evidence(bundleID: subject, dwellSeconds: 91),
            snapshot: snapshot(contextPack: [Self.appIdentity("com.apple.Pages")])
        )
        #expect(with?.verdict == .unrelated)
        #expect(with?.band == .medium)
        #expect(with?.band ?? .low >= RelevancePolicy.interventionBandFloor)
    }

    /// One case per `negativeBasisKinds` member, so the gate cannot pass by accident on a
    /// single kind.
    @Test("a domain identity is a basis, exactly as an app identity is")
    func aDomainIdentityIsABasis() {
        let answer = HeuristicClassifier().judge(
            evidence: evidence(bundleID: "com.microsoft.Excel", dwellSeconds: 91),
            snapshot: snapshot(contextPack: [Self.domainIdentity("https://docs.google.com")])
        )
        #expect(answer?.verdict == .unrelated)
    }

    /// And one case per **excluded** kind, which must still be `uncertain`. A `keyword` can
    /// only ever match positively, so its absence is the same absence the overlap stage already
    /// declined to conclude from; a `file` cannot be observed at zero grants at all.
    @Test(
        "a keyword-only or file-only pack is not a negative basis, at any dwell",
        arguments: [89, 90, 91, 600]
    )
    func excludedKindsAreNotABasis(dwell: Int) {
        let keywordOnly = HeuristicClassifier().judge(
            evidence: evidence(bundleID: "com.microsoft.Excel", dwellSeconds: dwell),
            snapshot: snapshot(contextPack: [
                ContextItemValue.keyword("proposal", addedAt: Self.reference)!,
                ContextItemValue.keyword("acme", addedAt: Self.reference)!
            ])
        )
        #expect(keywordOnly?.verdict == .uncertain)
        #expect(keywordOnly?.uncertaintyReason == .noNegativeBasis)

        let fileOnly = HeuristicClassifier().judge(
            evidence: evidence(bundleID: "com.microsoft.Excel", dwellSeconds: dwell),
            snapshot: snapshot(contextPack: [
                ContextItemValue.file(
                    url: URL(fileURLWithPath: "/Users/someone/Q3.numbers"),
                    bookmark: nil,
                    addedAt: Self.reference
                )
            ])
        )
        #expect(fileOnly?.verdict == .uncertain)
        #expect(fileOnly?.uncertaintyReason == .noNegativeBasis)
    }

    /// The subject the person *did* name is never accused of being an absence of itself.
    @Test("a subject that is itself in the basis is not accused")
    func aBasisIdentityIsNotAccusedOfItsOwnAbsence() {
        let answer = HeuristicClassifier().judge(
            evidence: evidence(bundleID: "com.apple.Pages", dwellSeconds: 600),
            snapshot: snapshot(contextPack: [Self.appIdentity("com.apple.Pages")])
        )
        #expect(answer?.verdict != .unrelated)
    }

    // MARK: - The dwell boundary (R-74.1's triple, at the unit level)

    /// 89 / 90 / 91. The threshold is crossed at the first observation **after** it, so 90
    /// exactly does not accuse — the inclusive side stated once, here, and enforced by the
    /// fixture rather than by the comment.
    @Test("the sustained-drift boundary is strict: 89 no, 90 no, 91 yes")
    func theDwellBoundaryIsStrict() {
        let pack = [Self.appIdentity("com.apple.Pages")]
        func verdict(_ seconds: Int) -> Verdict? {
            HeuristicClassifier().judge(
                evidence: evidence(bundleID: "com.microsoft.Excel", dwellSeconds: seconds),
                snapshot: snapshot(contextPack: pack)
            )?.verdict
        }

        #expect(verdict(89) == .uncertain)
        #expect(verdict(90) == .uncertain, "the threshold itself does not accuse")
        #expect(verdict(91) == .unrelated)
    }

    /// 299 / 300 / 301. Past five minutes a person is not glancing, and the band rises.
    @Test("the escalation boundary is strict: 299 medium, 300 medium, 301 high")
    func theEscalationBoundaryIsStrict() {
        let pack = [Self.appIdentity("com.apple.Pages")]
        func band(_ seconds: Int) -> EvidenceBand? {
            HeuristicClassifier().judge(
                evidence: evidence(bundleID: "com.microsoft.Excel", dwellSeconds: seconds),
                snapshot: snapshot(contextPack: pack)
            )?.band
        }

        #expect(band(299) == .medium)
        #expect(band(300) == .medium)
        #expect(band(301) == .high)
    }

    // MARK: - Vague priorities (family 8)

    /// R-56.1's first condition failing, at every dwell. P-124 corroborates from the other
    /// side: *"stuff"* scores English at 0.54 and *"work"* produces no content token at all.
    @Test(
        "a vague priority never yields unrelated, at any dwell",
        arguments: ["stuff", "work", "catch up", ""]
    )
    func vaguePrioritiesNeverAccuse(intent: String) {
        for dwell in [0, 89, 91, 3_600] {
            let answer = HeuristicClassifier().judge(
                evidence: evidence(bundleID: "com.microsoft.Excel", dwellSeconds: dwell),
                snapshot: snapshot(
                    intent: intent, contextPack: [Self.appIdentity("com.apple.Pages")]
                )
            )
            #expect(answer?.verdict == .uncertain, "'\(intent)' at \(dwell)s")
            #expect(answer?.uncertaintyReason == .insufficientPriorityEvidence)
        }
    }

    // MARK: - Multilingual (family 4)

    /// P-111: `NLEmbedding` is `nil` for every non-English language on this OS, so there is no
    /// instrument — and an engine with no instrument must not proceed to an accusation.
    @Test(
        "a non-English priority never yields unrelated, at any dwell",
        arguments: [
            "rédiger la proposition trimestrielle pour acme",
            "Quartalsbericht für Acme schreiben",
            "四半期の提案書を書く",
            "redactar la propuesta del tercer trimestre"
        ]
    )
    func nonEnglishPrioritiesNeverAccuse(intent: String) {
        for dwell in [91, 3_600] {
            let answer = HeuristicClassifier().judge(
                evidence: evidence(bundleID: "com.microsoft.Excel", dwellSeconds: dwell),
                snapshot: snapshot(
                    intent: intent, contextPack: [Self.appIdentity("com.apple.Pages")]
                )
            )
            #expect(answer?.verdict == .uncertain, "'\(intent)' at \(dwell)s")
            #expect(answer?.uncertaintyReason == .languageNotSupported)
            #expect(answer?.clauses.contains { $0.kind == .languageNotSupported } == true)
        }
    }

    // MARK: - Mixed-use applications (families 1 and 5)

    /// A subject this app itself calls *"ask each time"* is a subject whose identity is known to
    /// be uninformative. The accusation route declines so rung 7 can answer — which is what
    /// keeps a private-browsing window `uncertain` rather than turning "we did not look" into
    /// "you are distracted".
    @Test(
        "a mixed-use application is never accused on absence, at any dwell",
        arguments: ["com.apple.Safari", "com.google.Chrome", "com.hnc.Discord", "com.apple.Music"]
    )
    func mixedUseApplicationsAreNeverAccusedOnAbsence(bundleID: String) {
        for dwell in [91, 3_600] {
            let answer = HeuristicClassifier().judge(
                evidence: evidence(bundleID: bundleID, dwellSeconds: dwell),
                snapshot: snapshot(contextPack: [Self.appIdentity("com.apple.Pages")])
            )
            #expect(answer == nil, "\(bundleID) at \(dwell)s must fall through to the seed rung")
        }
    }

    /// …but a browser showing a genuinely on-topic page still resolves, because the *relevant*
    /// routes are reached first. That is the whole reason the `ask each time` seed sits below
    /// the heuristic rather than above it.
    @Test("a mixed-use application showing on-topic evidence still resolves relevant")
    func aMixedUseApplicationCanStillBeRelevant() {
        let answer = HeuristicClassifier().judge(
            evidence: evidence(
                bundleID: "com.apple.Safari",
                origin: "https://docs.google.com",
                titleTokens: ["q3", "proposal", "acme"],
                dwellSeconds: 600
            ),
            snapshot: snapshot(contextPack: [Self.appIdentity("com.apple.Pages")])
        )
        #expect(answer?.verdict == .relevant)
    }

    // MARK: - Overlap (the precision instrument)

    /// P-114: every true overlap token in the measured corpus is five characters or more, so an
    /// overlap of at least `minimumStrongTokenLength` bands `.medium` and a shorter one bands
    /// `.low` — which is below the intervention floor and therefore cannot mandate.
    @Test("a strong overlap bands medium and a short one bands low")
    func overlapBanding() {
        let strong = HeuristicClassifier().judge(
            evidence: evidence(bundleID: "com.apple.Safari", titleTokens: ["proposal"], dwellSeconds: 0),
            snapshot: snapshot()
        )
        #expect(strong?.verdict == .relevant)
        #expect(strong?.band == .medium)
        #expect(strong?.clauses.contains { $0.kind == .tokenOverlap } == true)

        let short = HeuristicClassifier().judge(
            evidence: evidence(bundleID: "com.apple.Safari", titleTokens: ["ios"], dwellSeconds: 0),
            snapshot: snapshot(intent: "fix the login bug in the ios app")
        )
        #expect(short?.verdict == .relevant)
        #expect(short?.band == .low)
        #expect(short?.band ?? .high < RelevancePolicy.interventionBandFloor)
    }

    /// Overlap can find relevance in an identifier, and that is the *only* thing identifier
    /// tokens are ever used for: equality. They can reach no similarity function at all, which
    /// is a compile-time property rather than a checked one (R-57, P-112).
    @Test("an identifier token can corroborate relevance by equality alone")
    func identifierTokensMatchByEqualityOnly() {
        let answer = HeuristicClassifier().judge(
            evidence: evidence(bundleID: "com.figma.Desktop", dwellSeconds: 0),
            snapshot: snapshot(intent: "finish the figma wireframes")
        )
        #expect(answer?.verdict == .relevant)
        #expect(answer?.clauses.flatMap(\.tokens).map(\.value).contains("figma") == true)
    }

    // MARK: - Similarity (the recall instrument)

    /// Similarity may corroborate `relevant` and may **never** accuse. Asserted from the rung
    /// rather than from the scorer: no route through this classifier maps a distance to
    /// `unrelated`, at any distance and any dwell.
    @Test("similarity alone bands low, and never accuses")
    func similarityCorroboratesOnly() throws {
        let scorer = SimilarityScorer()
        scorer.warmUp()
        let classifier = HeuristicClassifier(scorer: scorer)

        // A related pair from P-124's committed table (sp-45, distance 0.8227), chosen because
        // the two sides share **no token at all** — so the only route to a `relevant` verdict
        // is the similarity signal, and the assertion is about that rather than about overlap
        // wearing similarity's clothes.
        let corroborated = classifier.judge(
            evidence: evidence(
                bundleID: "com.apple.Safari",
                titleTokens: ["refund", "flow", "api", "documentation"],
                dwellSeconds: 0
            ),
            snapshot: snapshot(
                intent: "review the pull request for the payments service", scorer: scorer
            )
        )
        #expect(corroborated?.verdict == .relevant)
        #expect(corroborated?.band == .low)
        #expect(corroborated?.band ?? .high < RelevancePolicy.interventionBandFloor)
        #expect(corroborated?.clauses.contains { $0.kind == .similarityCorroborated } == true)

        // …and no evidence, however distant, produces an accusation through this route.
        for title in [
            ["funny", "cat", "compilation"],
            ["premier", "league", "highlights"],
            ["cheap", "flights", "to", "lisbon"]
        ] {
            let answer = classifier.judge(
                evidence: evidence(
                    bundleID: "com.microsoft.Excel", titleTokens: title, dwellSeconds: 0
                ),
                snapshot: snapshot(scorer: scorer)
            )
            #expect(answer?.verdict != .unrelated, "\(title) produced an accusation on distance")
        }
    }

    /// An explanation never carries the number. Showing somebody "cosine 1.03" is showing them
    /// an implementation detail dressed as a reason, and P-113 proves it would not even mean
    /// what they would take it to mean.
    @Test("the corroboration clause carries no number")
    func theCorroborationClauseCarriesNoNumber() {
        #expect(ExplanationClause.similarityCorroborated.tokens.isEmpty)
    }

    // MARK: - Silence

    /// An engine that saw nothing declines rather than concluding. **"We did not look" must
    /// never become "you are distracted."**
    @Test("an empty observation is declined rather than judged")
    func anEmptyObservationIsDeclined() {
        #expect(
            HeuristicClassifier().judge(
                evidence: evidence(dwellSeconds: 3_600),
                snapshot: snapshot(contextPack: [Self.appIdentity("com.apple.Pages")])
            ) == nil
        )
    }

    /// The engine can never accuse without both a judgeable priority and a named identity, and
    /// this asserts it as a **property over the whole reachable input space** of this rung
    /// rather than case by case: every combination of the eight silent tools, the four dwell
    /// points and the four context-pack shapes that are not a basis.
    @Test("no combination without a basis ever produces unrelated")
    func noCombinationWithoutABasisAccuses() {
        let packs: [[ContextItemValue]] = [
            [],
            [ContextItemValue.keyword("proposal", addedAt: Self.reference)!],
            [ContextItemValue.file(
                url: URL(fileURLWithPath: "/Users/someone/Q3.numbers"),
                bookmark: nil, addedAt: Self.reference
            )],
            [
                ContextItemValue.keyword("acme", addedAt: Self.reference)!,
                ContextItemValue.file(
                    url: URL(fileURLWithPath: "/Users/someone/audit.pdf"),
                    bookmark: nil, addedAt: Self.reference
                )
            ]
        ]

        var judged = 0
        for tool in Self.lexicallySilentTools {
            for dwell in [0, 90, 91, 7_200] {
                for pack in packs {
                    for intent in Self.realPriorities {
                        let answer = HeuristicClassifier().judge(
                            evidence: evidence(bundleID: tool, dwellSeconds: dwell),
                            snapshot: snapshot(intent: intent, contextPack: pack)
                        )
                        judged += 1
                        #expect(
                            answer?.verdict != .unrelated,
                            "\(tool) at \(dwell)s with \(pack.count) items under '\(intent)'"
                        )
                    }
                }
            }
        }
        #expect(judged == Self.lexicallySilentTools.count * 4 * packs.count * Self.realPriorities.count)
    }
}
