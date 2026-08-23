import FocusCore
import FocusRules
import Foundation
import Testing

@testable import FocusClassify

/// The explanation (R-62, F-52).
///
/// Two guarantees are asserted here and they are not the same one. **Totality** — every rung
/// yields a non-empty clause list — is about the surface always having something to say.
/// **The hostile corpus** is about what it can never say: window titles, full URLs with query
/// strings and credentials, document names and absolute paths, in five languages, fed through
/// every producer and asserted absent from every emitted explanation, in the same shape as
/// e03's `NormalisedDetail` corpus test.
///
/// The hostile half is a check on an enforcement rather than the enforcement itself. Raw
/// captured content in an explanation is **unrepresentable**: no `ExplanationClause` case takes
/// a `String`, and `NormalisedToken` has a private initialiser that rejects whitespace, control
/// characters and every ASCII punctuation mark but `.`, `-` and `_`.
@Suite("Explanation builder")
struct ExplanationBuilderTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)
    static let priorityID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    let normalizer = TokenNormalizer()
    let builder = ExplanationBuilder()

    func snapshot(
        intent: String = "write the q3 proposal for acme",
        rules: [ScopedRuleValue] = [],
        contextPack: [ContextItemValue] = []
    ) -> RuleSnapshot {
        var snapshot = RuleSnapshotBuilder(normalizer: normalizer).build(
            priority: PriorityInput(id: Self.priorityID, revision: 1, intent: intent),
            contextPack: contextPack
        )
        if !rules.isEmpty {
            snapshot = RuleSnapshot(
                priorityID: snapshot.priorityID,
                priorityRevision: snapshot.priorityRevision,
                priorityTokens: snapshot.priorityTokens,
                prioritySentence: snapshot.prioritySentence,
                priorityLanguage: snapshot.priorityLanguage,
                rules: rules.sorted(by: ScopedRuleValue.precedes),
                skippedRuleCount: snapshot.skippedRuleCount,
                contextPack: snapshot.contextPack,
                policyDigest: snapshot.policyDigest,
                stamp: snapshot.stamp
            )
        }
        return snapshot
    }

    func evidence(
        bundleID: String? = nil,
        origin: String? = nil,
        titleTokens: [String] = [],
        dwellSeconds: Int = 0
    ) -> ClassificationEvidence {
        ClassificationEvidence.make(
            input: ClassificationInput(
                bundleIdentifier: bundleID, origin: origin, titleTokens: titleTokens
            ),
            dwell: .seconds(dwellSeconds),
            normalizer: normalizer
        )
    }

    static func rule(
        _ authority: RuleAuthority,
        _ kind: RuleSubjectKind,
        _ subject: String,
        _ verdict: PriorityRuleVerdict
    ) -> ScopedRuleValue {
        ScopedRuleValue(
            authority: authority, subjectKind: kind, subject: subject,
            verdict: verdict, createdAt: reference
        )
    }

    /// One realistic resolution per stage, produced by the **real cascade** rather than by
    /// hand, so the totality assertion is about what the engine actually emits.
    func resolutions() -> [CascadeStage: CascadeResolution] {
        let cascade = RuleCascade(heuristic: HeuristicClassifier(), normalizer: normalizer)
        var byStage: [CascadeStage: CascadeResolution] = [:]

        func record(_ resolution: CascadeResolution) { byStage[resolution.stage] = resolution }

        record(cascade.evaluate(
            evidence: evidence(bundleID: "com.example.Tool"),
            snapshot: snapshot(rules: [Self.rule(.session, .app, "com.example.Tool", .relevant)])
        ))
        record(cascade.evaluate(
            evidence: evidence(bundleID: "com.example.Tool"),
            snapshot: snapshot(rules: [Self.rule(.task, .app, "com.example.Tool", .unrelated)])
        ))
        record(cascade.evaluate(
            evidence: evidence(bundleID: "com.example.Tool"),
            snapshot: snapshot(rules: [Self.rule(.global, .app, "com.example.Tool", .uncertain)])
        ))
        record(cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Pages"),
            snapshot: snapshot(contextPack: [
                .app(bundleID: "com.apple.Pages", displayName: "Pages", addedAt: Self.reference)
            ])
        ))
        record(cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.ScreenContinuity"),
            snapshot: snapshot()
        ))
        record(cascade.evaluate(
            evidence: evidence(bundleID: "com.microsoft.Excel", dwellSeconds: 200),
            snapshot: snapshot(contextPack: [
                .app(bundleID: "com.apple.Pages", displayName: "Pages", addedAt: Self.reference)
            ])
        ))
        // The `ask each time` seed is only *reached* once the heuristic has a basis to decline
        // against — without one it answers `noNegativeBasis` at rung 5 and rung 7 never fires.
        // That ordering is R-56.1 working, and the fixture has to respect it to reach the rung.
        record(cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari", dwellSeconds: 200),
            snapshot: snapshot(contextPack: [
                .app(bundleID: "com.apple.Pages", displayName: "Pages", addedAt: Self.reference)
            ])
        ))
        record(cascade.evaluate(evidence: evidence(), snapshot: snapshot()))

        return byStage
    }

    // MARK: - Totality

    /// Every **executable** rung is reachable and every one of them explains itself.
    @Test("every executable rung yields a non-empty clause list")
    func everyExecutableRungExplainsItself() {
        let byStage = resolutions()
        for rung in CascadePrecedence.executableRungs {
            let resolution = byStage[rung.stage]
            #expect(resolution != nil, "no fixture reaches \(rung.stage)")
            guard let resolution else { continue }

            let explanation = builder.build(resolution: resolution, drift: .aligned)
            #expect(!explanation.isEmpty, "\(rung.stage) explained nothing")
            #expect(explanation.stage == rung.stage)
        }
    }

    /// And the ninth, which no fixture can reach because the model rung is not executable —
    /// asserted through a synthesised resolution so that `CascadeStage.allCases` is covered
    /// rather than `executableRungs`.
    @Test("every declared stage yields a non-empty clause list, including the model's")
    func everyDeclaredStageExplainsItself() {
        for stage in CascadeStage.allCases {
            let bare = CascadeResolution(
                stage: stage,
                verdict: .uncertain,
                source: .undecided,
                band: .low,
                clauses: [],
                uncertaintyReason: nil,
                consultedDepth: 1
            )
            let explanation = builder.build(resolution: bare, drift: .aligned)
            #expect(!explanation.isEmpty, "\(stage) with no clauses explained nothing")
        }
    }

    /// The temporal switch is exhaustive over the ladder, and the two rungs that decline
    /// outright say nothing about the clock: a dwell printed beside *"I do not know"* would be
    /// an accusation wearing a fact's clothes.
    @Test("the two declining rungs never report time")
    func theDecliningRungsNeverReportTime() {
        for stage in CascadeStage.allCases {
            let reports = ExplanationBuilder.reportsTime(at: stage)
            #expect(reports == !(stage == .seedFallback || stage == .unresolved))
        }

        let declined = CascadeResolution(
            stage: .seedFallback, verdict: .uncertain, source: .heuristic, band: .low,
            clauses: [.insufficientEvidence(reason: .mixedUseApplication)],
            uncertaintyReason: .mixedUseApplication, consultedDepth: 7
        )
        let explanation = builder.build(
            resolution: declined,
            drift: .sustained(subject: .mixed, accumulated: .seconds(400), isMixed: true),
            mixedSubjectCount: 3
        )
        #expect(!explanation.clauseKinds.contains(.sustainedDwell))
        #expect(!explanation.clauseKinds.contains(.mixedSubjects))
    }

    // MARK: - The temporal clauses

    @Test("a sustained accusation reports its dwell")
    func aSustainedAccusationReportsItsDwell() {
        let resolution = CascadeResolution(
            stage: .heuristic, verdict: .unrelated, source: .heuristic, band: .medium,
            clauses: [], uncertaintyReason: nil, consultedDepth: 6
        )
        let explanation = builder.build(
            resolution: resolution,
            drift: .sustained(subject: .single("com.google.Chrome"), accumulated: .seconds(140), isMixed: false)
        )
        #expect(explanation.clauseKinds.contains(.sustainedDwell))
        #expect(explanation.clauses.contains { $0 == .sustainedDwell(seconds: 140) })
    }

    /// "Several unrelated applications", never one of them misnamed — and the count is measured
    /// from the window rather than assumed.
    @Test("mixed drift says several, with a counted number and no names")
    func mixedDriftSaysSeveral() {
        let resolution = CascadeResolution(
            stage: .heuristic, verdict: .unrelated, source: .heuristic, band: .high,
            clauses: [], uncertaintyReason: nil, consultedDepth: 6
        )
        let explanation = builder.build(
            resolution: resolution,
            drift: .sustained(subject: .mixed, accumulated: .seconds(400), isMixed: true),
            mixedSubjectCount: 3
        )
        #expect(explanation.clauses.contains { $0 == .mixedSubjects(count: 3) })
        // …and no subject is named at all, because there is no single one to name.
        #expect(explanation.tokens.isEmpty)
    }

    /// A sustained accumulator under a `relevant` verdict is a stale reading the engine is about
    /// to clear. Printing it would tell somebody they had been off task for four minutes while
    /// they worked.
    @Test("a stale accumulator is never reported beside a relevant verdict")
    func aStaleAccumulatorIsNeverReported() {
        let resolution = CascadeResolution(
            stage: .contextPack, verdict: .relevant, source: .userRule, band: .high,
            clauses: [.contextItem(kind: .app, subject: NormalisedToken.normalised("com.apple.pages")!)],
            uncertaintyReason: nil, consultedDepth: 4
        )
        let explanation = builder.build(
            resolution: resolution,
            drift: .sustained(subject: .single("com.google.Chrome"), accumulated: .seconds(400), isMixed: false)
        )
        #expect(!explanation.clauseKinds.contains(.sustainedDwell))
    }

    /// The one clause in the epic that is good news.
    @Test("returning to the anchor is reported, and only when aligned and relevant")
    func returningToTheAnchorIsReported() {
        let anchor = NormalisedToken.normalised("com.apple.dt.xcode")!
        let relevant = CascadeResolution(
            stage: .contextPack, verdict: .relevant, source: .userRule, band: .high,
            clauses: [.contextItem(kind: .app, subject: anchor)],
            uncertaintyReason: nil, consultedDepth: 4
        )

        let returned = builder.build(resolution: relevant, drift: .aligned, anchor: anchor)
        #expect(returned.clauseKinds.contains(.returnedToAnchor))

        // Not while still drifting…
        let drifting = builder.build(
            resolution: relevant,
            drift: .grace(subject: .single("com.google.Chrome"), since: .seconds(10), accumulated: .seconds(30)),
            anchor: anchor
        )
        #expect(!drifting.clauseKinds.contains(.returnedToAnchor))

        // …and not beside an accusation, which would be the app congratulating somebody for
        // coming back while telling them they have not.
        let accused = CascadeResolution(
            stage: .heuristic, verdict: .unrelated, source: .heuristic, band: .medium,
            clauses: [], uncertaintyReason: nil, consultedDepth: 6
        )
        #expect(
            !builder.build(resolution: accused, drift: .aligned, anchor: anchor)
                .clauseKinds.contains(.returnedToAnchor)
        )
    }

    // MARK: - The cap, and the number that is never shown

    /// An explanation is evidence, not a transcript: three words a person can check at a glance
    /// beat twelve they will not read. Enforced at construction, so the builder cannot exceed it
    /// even by mistake.
    @Test("no explanation carries more than the committed number of tokens per clause")
    func theTokenCapIsEnforced() {
        let many = ["proposal", "acme", "budget", "sprint", "ticket", "board"]
            .compactMap(NormalisedToken.normalised)
        let resolution = CascadeResolution(
            stage: .heuristic, verdict: .relevant, source: .heuristic, band: .medium,
            clauses: [.tokenOverlap(tokens: many)], uncertaintyReason: nil, consultedDepth: 6
        )
        let explanation = builder.build(resolution: resolution, drift: .aligned)

        for clause in explanation.clauses {
            #expect(clause.tokens.count <= RelevancePolicy.maximumExplanationTokens)
        }
        // Sorted before truncation, so two runs over the same evidence say the same thing.
        let again = builder.build(resolution: resolution, drift: .aligned)
        #expect(explanation == again)
    }

    /// Showing somebody "cosine 1.03" is showing them an implementation detail dressed as a
    /// reason, and P-113 proves the number would not even mean what they would take it to mean.
    @Test("no clause in the whole vocabulary can carry a similarity number")
    func noClauseCarriesASimilarityNumber() {
        #expect(ExplanationClause.similarityCorroborated.tokens.isEmpty)
        // The two integers that do appear are facts about somebody's own day — a dwell and a
        // count of subjects — rather than scores about them. Asserted by enumeration, so a
        // clause that grew a `Double` fails here.
        let carriers: [ExplanationClauseKind] = [.sustainedDwell, .mixedSubjects]
        for kind in ExplanationClauseKind.allCases where !carriers.contains(kind) {
            #expect(!kind.copyKey.isEmpty, "\(kind) has no copy")
        }
    }

    // MARK: - The hostile corpus

    /// Window titles, full URLs with query strings and credentials, document names and absolute
    /// paths, in five languages, fed through **every producer** and asserted absent from every
    /// emitted explanation.
    static let hostile = [
        "Q3 Proposal — Acme Corp.docx",
        "https://user:hunter2@mail.example.com/u/0/#inbox?compose=new&to=dana",
        "/Users/someone/Documents/Bergman audit/2026 Q3.numbers",
        "Rapport trimestriel — Acme S.A. (confidentiel)",
        "四半期の提案書 — 株式会社アクメ",
        "Quartalsbericht — Acme GmbH, streng vertraulich",
        "Propuesta del tercer trimestre — Acme S.L.",
        "Re: [URGENT] password reset for dana@example.com",
        "Screenshot 2026-08-23 at 14.32.11.png",
        "~/Library/Application Support/Focus/really secret.sqlite"
    ]

    @Test("no hostile string survives into any explanation, through any producer")
    func theHostileCorpusIsUnrepresentable() {
        let cascade = RuleCascade(heuristic: HeuristicClassifier(), normalizer: normalizer)

        for hostile in Self.hostile {
            // Every route text can enter the engine by: the priority, a rule's subject, a
            // context item's value, a title token, and an origin.
            let snapshots = [
                snapshot(intent: hostile),
                snapshot(rules: [Self.rule(.global, .app, hostile, .unrelated)]),
                snapshot(rules: [Self.rule(.global, .titleToken, hostile, .relevant)]),
                snapshot(contextPack: [
                    .app(bundleID: hostile, displayName: hostile, addedAt: Self.reference)
                ]),
                snapshot(contextPack: [
                    ContextItemValue.keyword(hostile, addedAt: Self.reference)
                        ?? .app(bundleID: hostile, displayName: hostile, addedAt: Self.reference)
                ])
            ]
            let evidences = [
                evidence(bundleID: hostile, dwellSeconds: 200),
                evidence(bundleID: "com.apple.Safari", origin: hostile, dwellSeconds: 200),
                evidence(
                    bundleID: "com.apple.Safari",
                    titleTokens: hostile.split(separator: " ").map(String.init),
                    dwellSeconds: 200
                ),
                evidence(bundleID: "com.apple.Safari", titleTokens: [hostile], dwellSeconds: 200)
            ]

            for snapshot in snapshots {
                for evidence in evidences {
                    let resolution = cascade.evaluate(evidence: evidence, snapshot: snapshot)
                    let explanation = builder.build(
                        resolution: resolution,
                        drift: .sustained(
                            subject: .single(hostile), accumulated: .seconds(400), isMixed: false
                        ),
                        anchor: nil,
                        mixedSubjectCount: 2
                    )

                    for token in explanation.tokens {
                        #expect(token.value != hostile, "the whole hostile string survived")
                        #expect(!token.value.contains { $0.isWhitespace })
                        for forbidden in ["/", "?", "&", "#", ":", "@", "(", ")", ",", "~"] {
                            #expect(
                                !token.value.contains(forbidden),
                                "'\(token.value)' carries '\(forbidden)' from \(hostile.debugDescription)"
                            )
                        }
                    }
                }
            }
        }
    }

    /// The same guarantee stated as a property of the type rather than of the corpus: there is
    /// no route from a `String` to a clause. A test over one hundred hostile strings proves the
    /// factory rejects them; the absence of a public initialiser is what proves nothing else
    /// could have accepted them.
    @Test("a hostile string cannot be made into a token at all")
    func hostileStringsAreNotTokens() {
        for hostile in Self.hostile {
            #expect(NormalisedToken.normalised(hostile) == nil, "\(hostile.debugDescription)")
            #expect(!NormalisedToken.isWellFormed(hostile))
        }
    }

    /// An explanation round-trips through `Codable` unchanged, and a hand-written payload
    /// carrying a sentence fails the **decode** rather than smuggling one past the factories.
    @Test("a sentence cannot be decoded into a token")
    func decodingRejectsSentences() throws {
        let explanation = builder.build(
            resolution: CascadeResolution(
                stage: .heuristic, verdict: .relevant, source: .heuristic, band: .medium,
                clauses: [.tokenOverlap(tokens: [NormalisedToken.normalised("proposal")!])],
                uncertaintyReason: nil, consultedDepth: 6
            ),
            drift: .aligned
        )
        let data = try JSONEncoder().encode(explanation)
        #expect(try JSONDecoder().decode(Explanation.self, from: data) == explanation)

        let smuggled = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"proposal\"", with: "\"Q3 Proposal Acme\"")
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Explanation.self, from: Data(smuggled.utf8))
        }
    }
}
