import Foundation
import Testing

@testable import FocusCore

/// **The second most important test in the epic**, and the one that says U-1 did not weaken
/// the first (R-76, F-46, U-1).
///
/// The guarantee is the type: `QueryWarrant` has a `fileprivate` initialiser and one producer,
/// so a question that did not come through `decide(…)` cannot be constructed. This suite is the
/// *check* on the guarantee — the full cross-product of the inputs that function reads,
/// asserting that `.warranted` appears **only** where the verdict is `uncertain`, that
/// `.mandated` appears only where it is `unrelated`, and that **no input yields both**.
///
///     Verdict (3) × EvidenceBand (3) × DriftState (4) × SessionPhase (6) × FocusStatus (5)
///         × UncertaintyReason? (9) × ledger (2) × budget (2) = 38 880
@Suite("The query invariant")
struct QueryInvariantTests {
    /// One value of each `DriftState` case, plus the mixed shape a question has no form for.
    static let driftStates: [DriftState] = [
        .aligned,
        .grace(subject: .single("com.apple.Safari"), since: .seconds(10), accumulated: .seconds(30)),
        .sustained(subject: .single("com.apple.Safari"), accumulated: .seconds(60), isMixed: false),
        .cooldown(subject: .single("com.apple.Safari"), until: .seconds(700))
    ]

    static let mixedDrift = DriftState.sustained(
        subject: .mixed, accumulated: .seconds(60), isMixed: true
    )

    static let stamp = EngineStamp.current
    static let judged = "com.apple.Safari"
    static let dwelled = Duration.seconds(60)

    static func explanation(_ band: EvidenceBand) -> Explanation {
        Explanation.make(
            stage: .heuristic,
            band: band,
            clauses: [.noNegativeBasis, .insufficientEvidence(reason: .noNegativeBasis)],
            stamp: stamp
        )
    }

    /// The reason the guard sequence in `decide(…)` predicts, written out independently of that
    /// function. Two implementations of one contract: if either drifts, the cross-product below
    /// fails and says which cell.
    static func expectedReason(
        verdict: Verdict,
        drift: DriftState,
        phase: SessionPhase,
        status: FocusStatus,
        reason: UncertaintyReason?,
        isUserIdle: Bool,
        hasActivePriority: Bool,
        hasAsked: Bool,
        budgetPermits: Bool,
        interruptionInFlight: Bool,
        dwellSatisfied: Bool,
        judgedSubject: String?
    ) -> QueryWithholdingReason? {
        if verdict == .relevant { return .verdictRelevant }
        if verdict == .unrelated { return .verdictUnrelated }
        if !hasActivePriority { return .noActivePriority }
        if isUserIdle { return .userIdle }
        if phase != .focus { return .sessionPhaseForbids }
        if status != .uncertain { return .statusForbids }
        if interruptionInFlight { return .interruptionInFlight }
        if !budgetPermits { return .budgetExhausted }
        if hasAsked { return .alreadyAsked }
        if reason?.queryable == nil { return .reasonNotAskable }
        if drift.isMixed { return .noSingleSubject }
        if !dwellSatisfied { return .withinDwellGrace }
        if (judgedSubject ?? "").isEmpty { return .noSingleSubject }
        return nil                                  // the one cell that warrants
    }

    /// The full cross-product, and the invariant that ties the two authorisations together.
    @Test("38 880 combinations: a warrant only from uncertain, a mandate only from unrelated, never both")
    func theWholeCrossProduct() {
        var combinations = 0
        var warrants = 0
        var mandates = 0

        // Held constant here and exercised one at a time below, so that the axes in this loop
        // are exactly the ones R-76's cross-product names.
        let isUserIdle = false
        let hasActivePriority = true
        let interruptionInFlight = false
        let dwellSatisfied = true

        let reasons: [UncertaintyReason?] = UncertaintyReason.allCases.map { $0 } + [nil]

        for verdict in Verdict.allCases {
            for band in EvidenceBand.allCases {
                for drift in Self.driftStates {
                    for phase in SessionPhase.allCases {
                        for status in FocusStatus.allCases {
                            for reason in reasons {
                                for hasAsked in [false, true] {
                                    for budgetPermits in [false, true] {
                                        combinations += 1

                                        let outcome = ClassificationOutcome(
                                            verdict: verdict,
                                            source: .heuristic,
                                            // Deliberately maximal: neither confidence nor
                                            // band is read by `decide(…)`, and a cell that
                                            // changed answer when either moved would be the
                                            // collapse R-56 forbids.
                                            confidence: 1,
                                            band: band
                                        )

                                        let eligibility = QueryEligibility.decide(
                                            outcome: outcome,
                                            uncertainty: reason,
                                            drift: drift,
                                            dwelled: Self.dwelled,
                                            dwellSatisfied: dwellSatisfied,
                                            phase: phase,
                                            status: status,
                                            isUserIdle: isUserIdle,
                                            hasActivePriority: hasActivePriority,
                                            hasAsked: hasAsked,
                                            budgetPermits: budgetPermits,
                                            interruptionInFlight: interruptionInFlight,
                                            judgedSubject: Self.judged,
                                            explanation: Self.explanation(band),
                                            stamp: Self.stamp
                                        )

                                        // e04's producer, on the same inputs. The invariant is
                                        // not "each is right" but "the two are never both".
                                        let mandate = InterventionEligibility.decide(
                                            outcome: outcome,
                                            drift: drift,
                                            phase: phase,
                                            status: status,
                                            isUserIdle: isUserIdle,
                                            hasActivePriority: hasActivePriority,
                                            explanation: Self.explanation(band),
                                            stamp: Self.stamp
                                        )

                                        let expected = Self.expectedReason(
                                            verdict: verdict, drift: drift, phase: phase,
                                            status: status, reason: reason,
                                            isUserIdle: isUserIdle,
                                            hasActivePriority: hasActivePriority,
                                            hasAsked: hasAsked,
                                            budgetPermits: budgetPermits,
                                            interruptionInFlight: interruptionInFlight,
                                            dwellSatisfied: dwellSatisfied,
                                            judgedSubject: Self.judged
                                        )

                                        let cell = """
                                            verdict=\(verdict.rawValue) band=\(band.rawValue) \
                                            drift=\(drift) phase=\(phase.rawValue) \
                                            status=\(status.rawValue) \
                                            reason=\(reason?.rawValue ?? "none") \
                                            asked=\(hasAsked) budget=\(budgetPermits)
                                            """

                                        #expect(
                                            !(eligibility.isWarranted && mandate.isMandated),
                                            "both a warrant and a mandate: \(cell)"
                                        )

                                        switch eligibility {
                                        case .warranted(let warrant):
                                            warrants += 1
                                            #expect(expected == nil, "unexpected warrant: \(cell)")
                                            // The one cell, restated positively.
                                            #expect(verdict == .uncertain, "warranted on \(cell)")
                                            #expect(phase == .focus, "warranted outside focus: \(cell)")
                                            #expect(status == .uncertain, "warranted on \(cell)")
                                            #expect(!hasAsked, "warranted after asking: \(cell)")
                                            #expect(budgetPermits, "warranted with no budget: \(cell)")
                                            #expect(!drift.isMixed, "warranted on mixed drift: \(cell)")
                                            #expect(warrant.reason.reason == reason, "wrong reason: \(cell)")
                                            #expect(warrant.subject.identifier == Self.judged)
                                            #expect(warrant.dwelled == Self.dwelled)
                                        case .withheld(let withheld):
                                            #expect(expected == withheld, "wrong reason for \(cell)")
                                        }

                                        if mandate.isMandated {
                                            mandates += 1
                                            #expect(verdict == .unrelated, "mandated on \(cell)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        #expect(combinations == 38_880)
        #expect(warrants > 0, "no cell warranted a question — the test proves nothing")
        #expect(mandates > 0, "no cell mandated — e04's producer is not being exercised")
    }

    /// **The invariant, stated the other way round.** No `uncertain` verdict produces a
    /// mandate, and no `unrelated` verdict produces a warrant — whatever else is true.
    @Test("an uncertain verdict never mandates and an unrelated verdict never warrants")
    func neitherVerdictCrossesOver() {
        for band in EvidenceBand.allCases {
            for drift in Self.driftStates + [Self.mixedDrift] {
                for reason in UncertaintyReason.allCases {
                    let uncertain = ClassificationOutcome(
                        verdict: .uncertain, source: .heuristic, confidence: 1, band: band
                    )
                    let mandate = InterventionEligibility.decide(
                        outcome: uncertain, drift: drift, phase: .focus, status: .unrelated,
                        isUserIdle: false, hasActivePriority: true,
                        explanation: Self.explanation(band), stamp: Self.stamp
                    )
                    #expect(mandate.suppressionReason == .verdictUncertain)

                    let unrelated = ClassificationOutcome(
                        verdict: .unrelated, source: .heuristic, confidence: 1, band: band
                    )
                    let warrant = QueryEligibility.decide(
                        outcome: unrelated, uncertainty: reason, drift: drift,
                        dwelled: Self.dwelled, dwellSatisfied: true, phase: .focus,
                        status: .uncertain, isUserIdle: false, hasActivePriority: true,
                        hasAsked: false, budgetPermits: true, interruptionInFlight: false,
                        judgedSubject: Self.judged, explanation: Self.explanation(band),
                        stamp: Self.stamp
                    )
                    #expect(warrant.withholdingReason == .verdictUnrelated)
                }
            }
        }
    }

    /// A mixed drift state has no question in it, at every band, phase-permitting state and
    /// askable reason. *"Is something part of your task?"* is not a question.
    @Test("a mixed drift subject always withholds")
    func mixedDriftAlwaysWithholds() {
        for band in EvidenceBand.allCases {
            for askable in QueryableUncertainty.allCases {
                let eligibility = QueryEligibility.decide(
                    outcome: ClassificationOutcome(
                        verdict: .uncertain, source: .heuristic, confidence: 1, band: band
                    ),
                    uncertainty: askable.reason,
                    drift: Self.mixedDrift,
                    dwelled: Self.dwelled,
                    dwellSatisfied: true,
                    phase: .focus,
                    status: .uncertain,
                    isUserIdle: false,
                    hasActivePriority: true,
                    hasAsked: false,
                    budgetPermits: true,
                    interruptionInFlight: false,
                    judgedSubject: Self.judged,
                    explanation: Self.explanation(band),
                    stamp: Self.stamp
                )
                #expect(eligibility.withholdingReason == .noSingleSubject)
            }
        }
    }

    /// The four gates held constant in the cross-product, each exercised on its own against an
    /// otherwise-warranting cell.
    @Test("idle, no priority, an occupied slot and a short dwell each withhold on their own")
    func theFourHeldGates() {
        func decide(
            isUserIdle: Bool = false,
            hasActivePriority: Bool = true,
            interruptionInFlight: Bool = false,
            dwellSatisfied: Bool = true,
            judgedSubject: String? = QueryInvariantTests.judged
        ) -> QueryEligibility {
            QueryEligibility.decide(
                outcome: ClassificationOutcome(
                    verdict: .uncertain, source: .heuristic, confidence: 0, band: .low
                ),
                uncertainty: .noNegativeBasis,
                drift: Self.driftStates[2],
                dwelled: Self.dwelled,
                dwellSatisfied: dwellSatisfied,
                phase: .focus,
                status: .uncertain,
                isUserIdle: isUserIdle,
                hasActivePriority: hasActivePriority,
                hasAsked: false,
                budgetPermits: true,
                interruptionInFlight: interruptionInFlight,
                judgedSubject: judgedSubject,
                explanation: Self.explanation(.low),
                stamp: Self.stamp
            )
        }

        #expect(decide().isWarranted)
        #expect(decide(isUserIdle: true).withholdingReason == .userIdle)
        #expect(decide(hasActivePriority: false).withholdingReason == .noActivePriority)
        #expect(decide(interruptionInFlight: true).withholdingReason == .interruptionInFlight)
        #expect(decide(dwellSatisfied: false).withholdingReason == .withinDwellGrace)
        #expect(decide(judgedSubject: nil).withholdingReason == .noSingleSubject)
        #expect(decide(judgedSubject: "").withholdingReason == .noSingleSubject)
    }

    /// A question is not banded. An accusation needs `interventionBandFloor` because it makes a
    /// claim about somebody; a question says *we do not know*, so pricing it by confidence
    /// would be a confidence this function does not have.
    @Test("neither the band nor the confidence changes a query answer")
    func bandAndConfidenceAreNeverRead() {
        var answers: Set<QueryWithholdingReason?> = []
        var warranted = 0
        for band in EvidenceBand.allCases {
            for confidence in [0.0, 0.5, 1.0] {
                let eligibility = QueryEligibility.decide(
                    outcome: ClassificationOutcome(
                        verdict: .uncertain, source: .heuristic,
                        confidence: confidence, band: band
                    ),
                    uncertainty: .noNegativeBasis,
                    drift: Self.driftStates[2],
                    dwelled: Self.dwelled,
                    dwellSatisfied: true,
                    phase: .focus,
                    status: .uncertain,
                    isUserIdle: false,
                    hasActivePriority: true,
                    hasAsked: false,
                    budgetPermits: true,
                    interruptionInFlight: false,
                    judgedSubject: Self.judged,
                    explanation: Self.explanation(band),
                    stamp: Self.stamp
                )
                answers.insert(eligibility.withholdingReason)
                if eligibility.isWarranted { warranted += 1 }
            }
        }
        #expect(answers == [nil])
        #expect(warranted == EvidenceBand.allCases.count * 3)
    }

    /// The receipt outranks everything below it, and it is consulted **before** a warrant is
    /// constructed rather than after — which is what makes `nudge.repeatQueryCount == 0` an
    /// ordered suppression rather than an emergent property (R-78, R-84 gate 11).
    @Test("an existing receipt withholds every question, at every askable reason")
    func alreadyAskedOutranksTheAskableReasons() {
        for askable in QueryableUncertainty.allCases {
            let eligibility = QueryEligibility.decide(
                outcome: ClassificationOutcome(
                    verdict: .uncertain, source: .heuristic, confidence: 0, band: .low
                ),
                uncertainty: askable.reason,
                drift: Self.driftStates[2],
                dwelled: Self.dwelled,
                dwellSatisfied: true,
                phase: .focus,
                status: .uncertain,
                isUserIdle: false,
                hasActivePriority: true,
                hasAsked: true,
                budgetPermits: true,
                interruptionInFlight: false,
                judgedSubject: Self.judged,
                explanation: Self.explanation(.low),
                stamp: Self.stamp
            )
            #expect(eligibility.withholdingReason == .alreadyAsked)
        }
    }

    /// The five unaskable reasons never produce a question, and `noEvidence` is named.
    @Test("an unaskable uncertainty withholds with reasonNotAskable")
    func unaskableReasonsWithhold() {
        for reason in UncertaintyReason.allCases where !reason.isQueryable {
            let eligibility = QueryEligibility.decide(
                outcome: ClassificationOutcome(
                    verdict: .uncertain, source: .heuristic, confidence: 0, band: .low
                ),
                uncertainty: reason,
                drift: Self.driftStates[2],
                dwelled: Self.dwelled,
                dwellSatisfied: true,
                phase: .focus,
                status: .uncertain,
                isUserIdle: false,
                hasActivePriority: true,
                hasAsked: false,
                budgetPermits: true,
                interruptionInFlight: false,
                judgedSubject: Self.judged,
                explanation: Self.explanation(.low),
                stamp: Self.stamp
            )
            #expect(
                eligibility.withholdingReason == .reasonNotAskable,
                "\(reason.rawValue) produced a question"
            )
        }
    }

    @Test("every withholding reason has its own copy key")
    func withholdingReasonsHaveCopy() {
        var keys: Set<String> = []
        for reason in QueryWithholdingReason.allCases {
            #expect(reason.copyKey == "nudge.withheld.\(reason.rawValue)")
            #expect(keys.insert(reason.copyKey).inserted, "duplicate copy key")
        }
        #expect(QueryWithholdingReason.allCases.count == 12)
    }

    @Test(
        "no withholding reason resolves to its own key",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func withholdingCopyResolves() {
        for reason in QueryWithholdingReason.allCases {
            let rendered = String(localized: reason.copyResource)
            #expect(rendered != reason.copyKey, "\(reason.copyKey) resolves to its own name")
            #expect(!rendered.isEmpty)
        }
    }
}
