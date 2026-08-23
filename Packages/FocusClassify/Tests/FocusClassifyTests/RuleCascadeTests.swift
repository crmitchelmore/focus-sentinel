import FocusCore
import FocusRules
import Foundation
import Testing

@testable import FocusClassify

/// The ladder, walked (R-54, R-64, F-42, F-130, F-171).
///
/// The suite is organised around the three things that can go wrong with a precedence ladder:
/// a rung that out-ranks one it should not; a conflict resolved by picking a winner; and a
/// bundled opinion that survives the person's own words. Each has its own section, and each
/// asserts the *rung* as well as the verdict — a case that passes on the verdict but reaches it
/// by the wrong rung is a case that will stop catching its bug the next time somebody touches
/// the ladder.
@Suite("Rule cascade")
struct RuleCascadeTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)
    static let priorityID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    let normalizer = TokenNormalizer()
    let cascade = RuleCascade()

    func snapshot(
        intent: String = "write the q3 proposal for acme",
        rules: [ScopedRuleValue] = [],
        contextPack: [ContextItemValue] = []
    ) -> RuleSnapshot {
        RuleSnapshot(
            priorityID: Self.priorityID,
            priorityRevision: 1,
            priorityTokens: normalizer.tokens(fromProse: intent),
            prioritySentence: nil,
            priorityLanguage: normalizer.tokens(fromProse: intent).language,
            rules: rules.sorted(by: ScopedRuleValue.precedes),
            skippedRuleCount: 0,
            contextPack: contextPack,
            policyDigest: RelevancePolicy.digest,
            stamp: .current
        )
    }

    func evidence(
        bundleID: String? = nil,
        origin: String? = nil,
        titleTokens: [String] = [],
        dwell: Duration = .zero
    ) -> ClassificationEvidence {
        ClassificationEvidence.make(
            input: ClassificationInput(
                bundleIdentifier: bundleID, origin: origin, titleTokens: titleTokens
            ),
            dwell: dwell,
            normalizer: normalizer
        )
    }

    static func rule(
        _ authority: RuleAuthority,
        _ kind: RuleSubjectKind,
        _ subject: String,
        _ verdict: PriorityRuleVerdict,
        age: Double = 0
    ) -> ScopedRuleValue {
        ScopedRuleValue(
            authority: authority,
            subjectKind: kind,
            subject: subject,
            verdict: verdict,
            createdAt: reference.addingTimeInterval(age)
        )
    }

    // MARK: - The ladder itself

    /// R-54's three lengths, as the cascade sees them. The model rung is not skipped by a
    /// special case: it is **not in the sequence being walked**.
    @Test("the cascade walks the executable rungs only, and always reaches a decision")
    func theLadderIsTheSequence() {
        #expect(CascadePrecedence.rungs.count == 9)
        #expect(CascadePrecedence.executableRungs.count == 8)

        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.example.Unknown"),
            snapshot: snapshot()
        )
        #expect(resolution.stage == .unresolved)
        #expect(resolution.consultedDepth == CascadePrecedence.executableRungs.count)
        #expect((1...CascadePrecedence.executableRungs.count).contains(resolution.consultedDepth))
    }

    /// The model rung is declared and never consulted, in this build. Asserted through the
    /// per-stage answer rather than by inspecting a flag, so a rung that quietly became
    /// executable would fail here rather than in the evidence six stages later.
    @Test("the on-device model rung answers nothing in this build")
    func theModelRungIsSilent() {
        #expect(
            cascade.answer(
                at: .onDeviceModel,
                evidence: evidence(bundleID: "com.apple.Safari"),
                snapshot: snapshot()
            ) == nil
        )
        #expect(CascadePrecedence.rung(for: .onDeviceModel)?.isExecutable == false)
        #expect(
            CascadePrecedence.rungs.filter { !$0.isExecutable }.map(\.stage) == [.onDeviceModel]
        )
    }

    /// Every executable rung is reachable, and every one reports the depth its rank implies.
    /// A rung nothing can reach is a rung the metric will never see.
    @Test("every executable rung can decide, at the depth its rank implies")
    func everyExecutableRungIsReachable() {
        let cases: [(CascadeStage, CascadeResolution)] = [
            (.sessionRule, cascade.evaluate(
                evidence: evidence(bundleID: "com.example.Tool"),
                snapshot: snapshot(rules: [Self.rule(.session, .app, "com.example.Tool", .relevant)])
            )),
            (.taskRule, cascade.evaluate(
                evidence: evidence(bundleID: "com.example.Tool"),
                snapshot: snapshot(rules: [Self.rule(.task, .app, "com.example.Tool", .relevant)])
            )),
            (.globalRule, cascade.evaluate(
                evidence: evidence(bundleID: "com.example.Tool"),
                snapshot: snapshot(rules: [Self.rule(.global, .app, "com.example.Tool", .relevant)])
            )),
            (.contextPack, cascade.evaluate(
                evidence: evidence(bundleID: "com.apple.Pages"),
                snapshot: snapshot(contextPack: [
                    ContextItemValue.app(
                        bundleID: "com.apple.Pages", displayName: "Pages", addedAt: Self.reference
                    )
                ])
            )),
            (.seedRule, cascade.evaluate(
                evidence: evidence(bundleID: "com.apple.ScreenContinuity"),
                snapshot: snapshot()
            )),
            (.seedFallback, cascade.evaluate(
                evidence: evidence(bundleID: "com.apple.Safari"),
                snapshot: snapshot()
            )),
            (.unresolved, cascade.evaluate(
                evidence: evidence(bundleID: "com.example.Unknown"),
                snapshot: snapshot()
            ))
        ]

        for (stage, resolution) in cases {
            #expect(resolution.stage == stage, "expected \(stage), got \(resolution.stage)")
            let rank = CascadePrecedence.executableRungs.firstIndex { $0.stage == stage }
            #expect(resolution.consultedDepth == (rank ?? -1) + 1)
        }
    }

    // MARK: - Authority: every co-firing pair, in both orders

    /// A user rule outranks the context pack, the seed list and the heuristic, at **every**
    /// authority. Written as the full cross-product of the three authorities against the three
    /// lower rungs that can co-fire with them, in both directions of verdict, so a re-ordering
    /// of the ladder cannot pass by agreeing with one row.
    @Test(
        "a user rule at any authority outranks every lower rung that co-fires",
        arguments: [RuleAuthority.session, .task, .global]
    )
    func userRulesOutrankLowerRungs(authority: RuleAuthority) {
        // …against the context pack.
        let againstPack = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Pages"),
            snapshot: snapshot(
                rules: [Self.rule(authority, .app, "com.apple.Pages", .unrelated)],
                contextPack: [
                    ContextItemValue.app(
                        bundleID: "com.apple.Pages", displayName: "Pages", addedAt: Self.reference
                    )
                ]
            )
        )
        #expect(againstPack.stage == authority.stage)
        #expect(againstPack.verdict == .unrelated)

        // …against the decisive seed, in the direction that matters: the person says the one
        // opinion this app ships is wrong, and the person wins.
        let againstSeed = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.ScreenContinuity"),
            snapshot: snapshot(
                rules: [Self.rule(authority, .app, "com.apple.ScreenContinuity", .relevant)]
            )
        )
        #expect(againstSeed.stage == authority.stage)
        #expect(againstSeed.verdict == .relevant)

        // …against the `ask each time` seed, which the person has now answered once and for all.
        let againstFallback = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari"),
            snapshot: snapshot(rules: [Self.rule(authority, .app, "com.apple.Safari", .relevant)])
        )
        #expect(againstFallback.stage == authority.stage)
        #expect(againstFallback.verdict == .relevant)
    }

    /// The authorities themselves, in order: session over task over global, whichever way round
    /// the rules were written.
    @Test("session outranks task outranks global, in both orders")
    func authoritiesAreOrdered() {
        let all = [
            Self.rule(.global, .app, "com.example.Tool", .unrelated),
            Self.rule(.task, .app, "com.example.Tool", .uncertain),
            Self.rule(.session, .app, "com.example.Tool", .relevant)
        ]

        for arrangement in [all, all.reversed()] {
            let resolution = cascade.evaluate(
                evidence: evidence(bundleID: "com.example.Tool"),
                snapshot: snapshot(rules: Array(arrangement))
            )
            #expect(resolution.stage == .sessionRule)
            #expect(resolution.verdict == .relevant)
        }

        // Remove the session rule and the task rule takes over; remove that and the global one
        // does. Three rungs, asserted by removal rather than by three separate fixtures.
        let withoutSession = cascade.evaluate(
            evidence: evidence(bundleID: "com.example.Tool"),
            snapshot: snapshot(rules: Array(all.dropLast()))
        )
        #expect(withoutSession.stage == .taskRule)
        #expect(withoutSession.verdict == .uncertain)

        let globalOnly = cascade.evaluate(
            evidence: evidence(bundleID: "com.example.Tool"),
            snapshot: snapshot(rules: [all[0]])
        )
        #expect(globalOnly.stage == .globalRule)
        #expect(globalOnly.verdict == .unrelated)
    }

    // MARK: - Specificity: narrower wins, within one authority

    /// A `docs.google.com` rule beats a `com.apple.Safari` rule at the same authority, because
    /// the person who wrote the narrower rule meant it as the exception. Asserted in both
    /// orders, so the answer does not depend on how the store happened to return the rows.
    @Test("narrower wins within one authority, in both orders")
    func narrowerWinsWithinAnAuthority() {
        let rules = [
            Self.rule(.global, .app, "com.apple.Safari", .unrelated),
            Self.rule(.global, .domain, "https://docs.google.com", .relevant)
        ]

        for arrangement in [rules, rules.reversed()] {
            let resolution = cascade.evaluate(
                evidence: evidence(
                    bundleID: "com.apple.Safari", origin: "https://docs.google.com"
                ),
                snapshot: snapshot(rules: Array(arrangement))
            )
            #expect(resolution.stage == .globalRule)
            #expect(resolution.verdict == .relevant, "the domain rule is the narrower one")
        }
    }

    /// And the narrowest of the three: a title token beats a domain beats an app.
    @Test("the specificity axis is titleToken over domain over app")
    func theSpecificityAxisIsTotal() {
        let resolution = cascade.evaluate(
            evidence: evidence(
                bundleID: "com.apple.Safari",
                origin: "https://docs.google.com",
                titleTokens: ["proposal"]
            ),
            snapshot: snapshot(rules: [
                Self.rule(.global, .app, "com.apple.Safari", .unrelated),
                Self.rule(.global, .domain, "https://docs.google.com", .uncertain),
                Self.rule(.global, .titleToken, "proposal", .relevant)
            ])
        )
        #expect(resolution.stage == .globalRule)
        #expect(resolution.verdict == .relevant)
        #expect(RuleSubjectKind.allCases.map(\.rank) == [0, 1, 2])
    }

    // MARK: - Conflict declines to decide

    /// Same authority, same narrowness, disagreeing. **Never recency, never `unrelated`.**
    @Test("a same-cell conflict yields uncertain with both subjects named")
    func conflictYieldsUncertain() {
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari", titleTokens: ["proposal", "acme"]),
            snapshot: snapshot(rules: [
                Self.rule(.global, .titleToken, "proposal", .relevant, age: 0),
                Self.rule(.global, .titleToken, "acme", .unrelated, age: 60)
            ])
        )

        #expect(resolution.stage == .globalRule)
        #expect(resolution.verdict == .uncertain)
        #expect(resolution.uncertaintyReason == .conflictingRules)
        #expect(resolution.clauses.contains { $0.kind == .conflictingRules })

        let named = resolution.clauses.flatMap(\.tokens).map(\.value)
        #expect(Set(named) == ["proposal", "acme"], "both subjects must be named, neither wins")
    }

    /// A conflict across *different* narrowness is not a conflict: it is an exception and the
    /// general case, which is what the person meant by writing both.
    @Test("a disagreement across narrowness is an exception, not a conflict")
    func crossNarrownessIsNotAConflict() {
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari", origin: "https://docs.google.com"),
            snapshot: snapshot(rules: [
                Self.rule(.global, .app, "com.apple.Safari", .unrelated),
                Self.rule(.global, .domain, "https://docs.google.com", .relevant)
            ])
        )
        #expect(resolution.verdict == .relevant)
        #expect(resolution.uncertaintyReason == nil)
    }

    /// A conflict at one authority is not resolved by a rule at a *lower* one — the higher rung
    /// already answered, and its answer was "I decline".
    @Test("a conflict terminates the cascade rather than falling through")
    func conflictTerminatesTheCascade() {
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari", titleTokens: ["proposal", "acme"]),
            snapshot: snapshot(rules: [
                Self.rule(.task, .titleToken, "proposal", .relevant),
                Self.rule(.task, .titleToken, "acme", .unrelated),
                Self.rule(.global, .app, "com.apple.Safari", .relevant)
            ])
        )
        #expect(resolution.stage == .taskRule)
        #expect(resolution.verdict == .uncertain)
    }

    // MARK: - The context pack (rung 3)

    @Test("an app identity in the pack resolves relevant at high band")
    func appIdentityResolves() {
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Pages"),
            snapshot: snapshot(contextPack: [
                ContextItemValue.app(
                    bundleID: "com.apple.Pages", displayName: "Pages", addedAt: Self.reference
                )
            ])
        )
        #expect(resolution.stage == .contextPack)
        #expect(resolution.verdict == .relevant)
        #expect(resolution.band == .high)
        #expect(resolution.clauses.contains { $0.kind == .contextItem })
    }

    @Test("a domain identity in the pack resolves relevant at high band")
    func domainIdentityResolves() {
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari", origin: "https://docs.google.com"),
            snapshot: snapshot(contextPack: [
                ContextItemValue.domain(origin: "https://docs.google.com", addedAt: Self.reference)!
            ])
        )
        #expect(resolution.stage == .contextPack)
        #expect(resolution.verdict == .relevant)
        #expect(resolution.band == .high)
    }

    /// A word the person chose, matched by lemma. Strong, not exact — so `.medium`, and the
    /// clause names the overlap so an explanation can say *which* word.
    @Test("a keyword in the pack matches by lemma and bands medium")
    func keywordMatchesByLemma() {
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari", titleTokens: ["proposals", "draft"]),
            snapshot: snapshot(contextPack: [
                ContextItemValue.keyword("proposal", addedAt: Self.reference)!
            ])
        )
        #expect(resolution.stage == .contextPack)
        #expect(resolution.verdict == .relevant)
        #expect(resolution.band == .medium)
        #expect(resolution.clauses.contains { $0.kind == .tokenOverlap })
    }

    /// At zero grants the engine cannot see which file is open, so a `file` item can neither
    /// match nor fail to match — it is not evidence in either direction (R-56.1).
    @Test("a file item never matches, and never blocks a lower rung")
    func fileItemsNeverMatch() {
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Numbers"),
            snapshot: snapshot(contextPack: [
                ContextItemValue.file(
                    url: URL(fileURLWithPath: "/Users/someone/Q3.numbers"),
                    bookmark: nil,
                    addedAt: Self.reference
                )
            ])
        )
        #expect(resolution.stage != .contextPack)
    }

    /// A context pack says what the work looks like; it never says what it does not. Only
    /// `relevant` is reachable from this rung, at any kind.
    @Test("the context pack can only ever produce relevant")
    func theContextPackNeverAccuses() {
        for item in [
            ContextItemValue.app(bundleID: "com.apple.Pages", displayName: "Pages", addedAt: Self.reference),
            ContextItemValue.domain(origin: "https://docs.google.com", addedAt: Self.reference)!,
            ContextItemValue.keyword("proposal", addedAt: Self.reference)!
        ] {
            let answer = cascade.contextAnswer(
                evidence: evidence(
                    bundleID: "com.apple.Pages",
                    origin: "https://docs.google.com",
                    titleTokens: ["proposal"]
                ),
                snapshot: snapshot(contextPack: [item])
            )
            #expect(answer?.verdict == .relevant)
        }
    }

    // MARK: - The seeds (rungs 4 and 7)

    /// F-171's row: the single opinion this app ships, at the rung that can actually mandate.
    @Test("the one decisive seed decides, at medium band")
    func theDecisiveSeedDecides() {
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.ScreenContinuity"),
            snapshot: snapshot()
        )
        #expect(resolution.stage == .seedRule)
        #expect(resolution.verdict == .unrelated)
        #expect(resolution.band == .medium)
        #expect(resolution.band >= RelevancePolicy.interventionBandFloor)
        #expect(resolution.clauses.contains { $0.kind == .seedDefault })
    }

    /// An `ask each time` seed sits **below** the heuristic, or a browser with a genuinely
    /// relevant origin would resolve to `uncertain` for ever. It bands `.low` and suppresses.
    @Test("an ask-each-time seed declines, below the heuristic")
    func theFallbackSeedDeclines() {
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari"),
            snapshot: snapshot()
        )
        #expect(resolution.stage == .seedFallback)
        #expect(resolution.verdict == .uncertain)
        #expect(resolution.uncertaintyReason == .mixedUseApplication)
        #expect(resolution.band < RelevancePolicy.interventionBandFloor)
        #expect(
            CascadeStage.seedFallback.rank > CascadeStage.heuristic.rank,
            "the fallback seed must sit below the heuristic or a browser can never be relevant"
        )
    }

    // MARK: - The seed-override guard (family 3)

    /// **The Court's own worked example.** A person whose priority is *"record the iPhone
    /// Mirroring demo"* must not be nudged by a bundled default about iPhone Mirroring: a
    /// bundled default is the app's opinion, and the person's own words outrank it.
    @Test("the priority's own words downgrade a decisive seed to uncertain")
    func theSeedOverrideGuardFires() {
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.ScreenContinuity"),
            snapshot: snapshot(intent: "record the iPhone Mirroring demo")
        )
        #expect(resolution.stage == .seedRule)
        #expect(resolution.verdict == .uncertain)
        #expect(resolution.uncertaintyReason == .mixedUseApplication)
        #expect(resolution.band < RelevancePolicy.interventionBandFloor)
    }

    /// The guard fires **downward only**. There is no priority wording that can turn a seed
    /// into an accusation it does not already make — which is why the guard lives inside the
    /// `unrelated` branch and not outside it.
    @Test("the guard can never turn a seed relevant into unrelated")
    func theGuardFiresDownwardOnly() {
        // There is no `alwaysRelevant` seed to test against — asserted, because the table's
        // shape is what makes the claim total rather than incidental.
        #expect(!RelevanceSeed.defaults.values.contains(.alwaysRelevant))

        // And a priority that names the app does not *strengthen* the decisive seed either:
        // the only reachable answers from that branch are `unrelated` and `uncertain`.
        for intent in ["record the iPhone Mirroring demo", "write the q3 proposal for acme"] {
            let answer = cascade.seedAnswer(
                evidence: evidence(bundleID: "com.apple.ScreenContinuity"),
                snapshot: snapshot(intent: intent),
                decisive: true
            )
            #expect(answer?.verdict != .relevant)
        }
    }

    /// A priority that says nothing about the application leaves the seed standing.
    @Test("an unrelated priority does not fire the guard")
    func theGuardDoesNotFireOnUnrelatedWords() {
        #expect(
            !cascade.overrides(
                seed: "com.apple.ScreenContinuity",
                priorityTokens: normalizer.tokens(fromProse: "write the q3 proposal for acme")
            )
        )
        #expect(
            cascade.overrides(
                seed: "com.apple.ScreenContinuity",
                priorityTokens: normalizer.tokens(fromProse: "record the iPhone Mirroring demo")
            )
        )
    }

    /// The guard needs the application's **name**, not only its identifier: `ScreenContinuity`
    /// decomposes to `apple`, `screen`, `continuity`, none of which anybody writes in a
    /// priority. Every decisive seed must therefore carry a name, or the guard is unfireable
    /// for it — asserted here so a second decisive row cannot ship without one.
    @Test("every decisive seed carries the name a person would write")
    func everyDecisiveSeedHasAName() {
        for identifier in RelevanceSeed.decisiveSeeds.keys {
            #expect(
                SeedSubjectNames.names[identifier] != nil,
                "\(identifier) is decisive but has no name, so the override guard cannot fire"
            )
        }
        // The identifier alone genuinely is not enough — the reason the table exists.
        #expect(
            normalizer.tokens(fromIdentifier: "com.apple.ScreenContinuity").values
                .isDisjoint(with: normalizer.tokens(fromProse: "record the iPhone Mirroring demo").values)
        )
    }

    // MARK: - Rung 8

    /// There is nothing to write a rule *about* an unbundled process, so there is nothing to
    /// conclude (family 7; e03's P-83 measured six of ninety-two).
    @Test("an unbundled process reaches unresolved with no identifiable subject")
    func unbundledProcessesAreUnidentifiable() {
        let resolution = cascade.evaluate(evidence: evidence(), snapshot: snapshot())
        #expect(resolution.stage == .unresolved)
        #expect(resolution.verdict == .uncertain)
        #expect(resolution.uncertaintyReason == .noIdentifiableSubject)
    }

    /// The terminal rung always answers, which is what makes the consulted depth `1…8` rather
    /// than `0…8`.
    @Test("the terminal rung always answers")
    func theTerminalRungAlwaysAnswers() {
        for evidence in [
            evidence(),
            evidence(bundleID: "com.example.Unknown"),
            evidence(origin: "https://example.com"),
            evidence(bundleID: "com.example.Unknown", titleTokens: ["something"])
        ] {
            #expect(cascade.unresolvedAnswer(evidence: evidence, snapshot: snapshot()) != nil)
        }
    }

    // MARK: - The heuristic seam

    /// The cascade is written, read and tested without a heuristic; supplying one changes which
    /// rung answers and nothing else. This is also the assertion that e06's rung plugs into a
    /// shape that already exists.
    @Test("a supplied heuristic answers at rung 5, and its absence falls through")
    func theHeuristicSeamIsARung() {
        struct AlwaysRelevant: HeuristicRung {
            func judge(evidence: ClassificationEvidence, snapshot: RuleSnapshot) -> RungAnswer? {
                RungAnswer(
                    verdict: .relevant, source: .heuristic, band: .medium,
                    clauses: [.similarityCorroborated]
                )
            }
        }

        let without = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari"), snapshot: snapshot()
        )
        #expect(without.stage == .seedFallback)

        let with = RuleCascade(heuristic: AlwaysRelevant()).evaluate(
            evidence: evidence(bundleID: "com.apple.Safari"), snapshot: snapshot()
        )
        #expect(with.stage == .heuristic)
        #expect(with.verdict == .relevant)
        #expect(with.consultedDepth < without.consultedDepth)
    }

    // MARK: - F-130's four dispositions, end to end

    /// The four dispositions map onto the shipped vocabulary with **no schema change**, and
    /// each produces the cascade behaviour its name promises.
    @Test("the four dispositions behave as their names say")
    func theFourDispositionsBehave() {
        for disposition in AppRuleDisposition.allCases {
            let rules = disposition.ruleVerdict.map {
                [Self.rule(.global, .app, "com.example.Tool", $0)]
            } ?? []
            let resolution = cascade.evaluate(
                evidence: evidence(bundleID: "com.example.Tool"),
                snapshot: snapshot(rules: rules)
            )

            switch disposition {
            case .alwaysRelevant:
                #expect(resolution.stage == .globalRule)
                #expect(resolution.verdict == .relevant)
            case .alwaysDistracting:
                #expect(resolution.stage == .globalRule)
                #expect(resolution.verdict == .unrelated)
            case .askEachTime:
                #expect(resolution.stage == .globalRule)
                #expect(resolution.verdict == .uncertain)
            case .interpretByContext:
                // No row at all, so the cascade falls through — which is exactly what
                // "interpret by context" means.
                #expect(resolution.stage != .globalRule)
            }
        }
    }

    /// A legacy `.session`-scoped row reaches no rung, and it is **not** a conflicting one: a
    /// skipped row is not a contradicting row, and the verdict is whatever the remaining rungs
    /// say (R-72.3).
    @Test("a skipped legacy row is not a conflict")
    func aSkippedRowIsNotAConflict() {
        let built = RuleSnapshotBuilder().build(
            priority: PriorityInput(id: Self.priorityID, revision: 1, intent: "write the q3 proposal for acme"),
            storedRules: [
                StoredRuleRow(
                    rule: RelevanceRuleValue(
                        scope: .session, subject: "com.apple.Safari", verdict: .relevant,
                        createdAt: Self.reference
                    ),
                    isTaskScoped: false
                ),
                StoredRuleRow(
                    rule: RelevanceRuleValue(
                        scope: .app, subject: "com.apple.Safari", verdict: .unrelated,
                        createdAt: Self.reference
                    ),
                    isTaskScoped: false
                )
            ]
        )

        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari"), snapshot: built
        )
        #expect(built.skippedRuleCount == 1)
        #expect(resolution.stage == .globalRule)
        #expect(resolution.verdict == .unrelated)
        #expect(resolution.uncertaintyReason != .conflictingRules)
    }
}
