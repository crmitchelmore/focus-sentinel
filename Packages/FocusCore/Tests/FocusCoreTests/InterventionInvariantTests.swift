import Foundation
import Testing

@testable import FocusCore

/// **The single most important test in the epic** (R-55, standing condition 6, F-46).
///
/// The guarantee is the type: `InterventionMandate` has a `fileprivate` initialiser and one
/// producer, so an intervention that did not come through `decide(…)` cannot be constructed.
/// This suite is the *check* on the guarantee — the full cross-product of every input that
/// function reads, asserting that `.mandated` appears only in the one cell it is allowed to,
/// and that every other cell is `.suppressed` with the reason the guard order predicts.
///
///     Verdict (3) × EvidenceBand (3) × DriftState (4) × SessionPhase (6)
///         × FocusStatus (5) × idle (2) × hasPriority (2) = 4 320
@Suite("The intervention invariant")
struct InterventionInvariantTests {
    /// One value of each `DriftState` case. The payloads are the ones a real run would carry:
    /// a subject, a duration, and — for `sustained` — an explicit mixed flag.
    private static let driftStates: [DriftState] = [
        .aligned,
        .grace(subject: .single("com.apple.Safari"), since: .seconds(10), accumulated: .seconds(30)),
        .sustained(subject: .single("com.apple.Safari"), accumulated: .seconds(120), isMixed: false),
        .cooldown(subject: .single("com.apple.Safari"), until: .seconds(700))
    ]

    private static let stamp = EngineStamp.current

    private static func explanation(_ band: EvidenceBand) -> Explanation {
        Explanation.make(
            stage: .heuristic,
            band: band,
            clauses: [.sustainedDwell(seconds: 120)],
            stamp: stamp
        )
    }

    /// The reason the guard sequence in `decide(…)` predicts, written out independently of
    /// that function. Two implementations of one contract: if either drifts, the cross-product
    /// below fails and says which cell.
    private static func expectedReason(
        verdict: Verdict,
        band: EvidenceBand,
        drift: DriftState,
        phase: SessionPhase,
        status: FocusStatus,
        isUserIdle: Bool,
        hasActivePriority: Bool
    ) -> SuppressionReason? {
        if verdict == .relevant { return .verdictRelevant }
        if verdict == .uncertain { return .verdictUncertain }
        if !hasActivePriority { return .noActivePriority }
        if isUserIdle { return .userIdle }
        if phase != .focus { return .sessionPhaseForbids }
        if status != .unrelated { return .statusForbids }
        if band < .medium { return .evidenceBandTooLow }
        switch drift {
        case .aligned, .grace: return .withinGracePeriod
        case .cooldown: return .withinMandateCooldown
        case .sustained: return nil            // the one cell that mandates
        }
    }

    @Test("the cross-product is 4 320 combinations and every one resolves as the guards predict")
    func theWholeCrossProduct() {
        var combinations = 0
        var mandates = 0

        for verdict in Verdict.allCases {
            for band in EvidenceBand.allCases {
                for drift in Self.driftStates {
                    for phase in SessionPhase.allCases {
                        for status in FocusStatus.allCases {
                            for isUserIdle in [false, true] {
                                for hasActivePriority in [false, true] {
                                    combinations += 1

                                    let outcome = ClassificationOutcome(
                                        verdict: verdict,
                                        source: .heuristic,
                                        // Deliberately maximal: `confidence` is never read by
                                        // `decide(…)`, and a cell that changed answer when it
                                        // moved would be the collapse R-56 forbids.
                                        confidence: 1,
                                        band: band
                                    )
                                    let eligibility = InterventionEligibility.decide(
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
                                        verdict: verdict, band: band, drift: drift,
                                        phase: phase, status: status,
                                        isUserIdle: isUserIdle,
                                        hasActivePriority: hasActivePriority
                                    )

                                    let cell = """
                                        verdict=\(verdict.rawValue) band=\(band.rawValue) \
                                        drift=\(drift) phase=\(phase.rawValue) \
                                        status=\(status.rawValue) idle=\(isUserIdle) \
                                        priority=\(hasActivePriority)
                                        """

                                    switch eligibility {
                                    case .mandated(let mandate):
                                        mandates += 1
                                        #expect(expected == nil, "unexpected mandate: \(cell)")
                                        // The one cell, restated positively.
                                        #expect(verdict == .unrelated, "mandated on \(cell)")
                                        #expect(band >= .medium, "mandated below the floor: \(cell)")
                                        #expect(phase == .focus, "mandated outside focus: \(cell)")
                                        #expect(status == .unrelated, "mandated on \(cell)")
                                        #expect(!isUserIdle, "mandated while idle: \(cell)")
                                        #expect(hasActivePriority, "mandated with no priority: \(cell)")
                                        if case .sustained = drift {} else {
                                            Issue.record("mandated without sustained drift: \(cell)")
                                        }
                                        #expect(mandate.sustainedFor == .seconds(120))
                                        #expect(mandate.band == band)
                                        #expect(mandate.isMixed == false)
                                        #expect(mandate.subject == "com.apple.Safari")
                                    case .suppressed(let reason):
                                        #expect(expected == reason, "wrong reason for \(cell)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        #expect(combinations == 4320)
        // unrelated × {medium, high} × sustained × focus × unrelated × ¬idle × priority
        #expect(mandates == 2)
    }

    /// Standing condition 6, stated on its own so a failure names it rather than being one
    /// line of a 4 320-cell sweep: **every** uncertain verdict suppresses, at every band, every
    /// drift state, every phase, every status.
    @Test("an uncertain verdict suppresses at every band, dwell, phase and status")
    func uncertainAlwaysSuppresses() {
        for band in EvidenceBand.allCases {
            for drift in Self.driftStates {
                for phase in SessionPhase.allCases {
                    for status in FocusStatus.allCases {
                        let eligibility = InterventionEligibility.decide(
                            outcome: ClassificationOutcome(
                                verdict: .uncertain, source: .userRule,
                                confidence: 1, band: band
                            ),
                            drift: drift,
                            phase: phase,
                            status: status,
                            isUserIdle: false,
                            hasActivePriority: true,
                            explanation: Self.explanation(band),
                            stamp: Self.stamp
                        )
                        #expect(eligibility == .suppressed(.verdictUncertain))
                        #expect(eligibility.mandate == nil)
                    }
                }
            }
        }
    }

    /// `confidence` is not an input to this decision, and this is the assertion that says so
    /// in the one place it would matter: an `uncertain` verdict at confidence 1.0 and at 0.0
    /// produce the identical answer, and so does an `unrelated` one.
    @Test("confidence changes nothing, in either direction")
    func confidenceIsNotConsulted() {
        for verdict in Verdict.allCases {
            let low = InterventionEligibility.decide(
                outcome: ClassificationOutcome(verdict: verdict, source: .heuristic, confidence: 0, band: .high),
                drift: Self.driftStates[2], phase: .focus, status: .unrelated,
                isUserIdle: false, hasActivePriority: true,
                explanation: Self.explanation(.high), stamp: Self.stamp
            )
            let high = InterventionEligibility.decide(
                outcome: ClassificationOutcome(verdict: verdict, source: .heuristic, confidence: 1, band: .high),
                drift: Self.driftStates[2], phase: .focus, status: .unrelated,
                isUserIdle: false, hasActivePriority: true,
                explanation: Self.explanation(.high), stamp: Self.stamp
            )
            #expect(low == high, "confidence changed the answer for \(verdict.rawValue)")
        }
    }

    /// Drift across several subjects mandates with `isMixed` set and no subject named, so a
    /// surface says "several unrelated apps" rather than misnaming the last one (R-60).
    @Test("mixed drift mandates without naming a subject")
    func mixedDriftNamesNobody() {
        let eligibility = InterventionEligibility.decide(
            outcome: ClassificationOutcome(verdict: .unrelated, source: .heuristic, confidence: 0.5, band: .medium),
            drift: .sustained(subject: .mixed, accumulated: .seconds(200), isMixed: true),
            phase: .focus,
            status: .unrelated,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: Self.explanation(.medium),
            stamp: Self.stamp
        )

        let mandate = eligibility.mandate
        #expect(mandate != nil)
        #expect(mandate?.isMixed == true)
        #expect(mandate?.subject.isEmpty == true, "a mixed mandate must name nobody")
        #expect(mandate?.sustainedFor == .seconds(200))
    }

    /// The band floor is the constant, not a literal here: if `interventionBandFloor` ever
    /// moved, this would follow it rather than silently disagreeing with the engine.
    @Test("the band floor is the committed constant, and low is below it")
    func bandFloorIsTheCommittedConstant() {
        #expect(RelevancePolicy.interventionBandFloor == .medium)
        #expect(EvidenceBand.low < RelevancePolicy.interventionBandFloor)

        let lowBand = InterventionEligibility.decide(
            outcome: ClassificationOutcome(verdict: .unrelated, source: .heuristic, confidence: 1, band: .low),
            drift: Self.driftStates[2], phase: .focus, status: .unrelated,
            isUserIdle: false, hasActivePriority: true,
            explanation: Self.explanation(.low), stamp: Self.stamp
        )
        #expect(lowBand == .suppressed(.evidenceBandTooLow))
    }

    /// Every suppression reason the guard sequence can produce is actually produced by some
    /// cell of the cross-product. A reason no input can reach is copy for a state that cannot
    /// happen, and a surface that promised to explain it would be lying.
    @Test("every suppression reason is reachable")
    func everyReasonIsReachable() {
        var seen: Set<SuppressionReason> = []

        for verdict in Verdict.allCases {
            for band in EvidenceBand.allCases {
                for drift in Self.driftStates {
                    for phase in SessionPhase.allCases {
                        for status in FocusStatus.allCases {
                            for isUserIdle in [false, true] {
                                for hasActivePriority in [false, true] {
                                    let eligibility = InterventionEligibility.decide(
                                        outcome: ClassificationOutcome(
                                            verdict: verdict, source: .heuristic,
                                            confidence: 0.5, band: band
                                        ),
                                        drift: drift, phase: phase, status: status,
                                        isUserIdle: isUserIdle,
                                        hasActivePriority: hasActivePriority,
                                        explanation: Self.explanation(band), stamp: Self.stamp
                                    )
                                    if let reason = eligibility.suppressionReason {
                                        seen.insert(reason)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        #expect(seen == Set(SuppressionReason.allCases))
    }
}
