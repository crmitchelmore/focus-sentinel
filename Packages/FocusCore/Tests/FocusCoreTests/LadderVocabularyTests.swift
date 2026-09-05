import Foundation
import Testing

@testable import FocusCore

/// The ladder's vocabulary: **two** rungs, one provenance, and a delivery result that is not a
/// `Bool` (R-80, R-81, D-06 as amended by U-2, F-57).
///
/// The bijection below is re-pointed at the new count rather than relaxed. It still fails on drift
/// in both directions — a rung added without amending the policy constant, or the constant moved
/// without the enum — which is the whole reason it was written. What U-2 changed is which number
/// is correct, not whether the number is checked.
@Suite("Ladder vocabulary")
struct LadderVocabularyTests {
    static let stamp = EngineStamp.current

    /// A real mandate, built through e04's one producer. There is no other way to obtain one,
    /// which is the point.
    static func mandate(
        subject: String = "com.chrismitchelmore.FocusDecoy",
        isMixed: Bool = false
    ) -> InterventionMandate {
        let explanation = Explanation.make(
            stage: .heuristic,
            band: .medium,
            clauses: [.sustainedDwell(seconds: 120)],
            stamp: stamp
        )
        let eligibility = InterventionEligibility.decide(
            outcome: ClassificationOutcome(
                verdict: .unrelated, source: .heuristic, confidence: 1, band: .medium
            ),
            drift: .sustained(
                subject: isMixed ? .mixed : .single(subject),
                accumulated: .seconds(120),
                isMixed: isMixed
            ),
            phase: .focus,
            status: .unrelated,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: explanation,
            stamp: stamp
        )
        guard let mandate = eligibility.mandate else {
            fatalError("e04's producer refused to mandate on inputs that must mandate")
        }
        return mandate
    }

    // MARK: - Two rungs, ranked 0…1, exactly once each

    @Test("there are exactly two rungs, ranked 0 and 1, each once")
    func twoRanksExactlyOnce() {
        #expect(LadderRung.Kind.allCases.count == 2)
        #expect(
            LadderRung.Kind.allCases.count == InterventionPolicy.ladderRungCount,
            "the enum and the policy constant have drifted apart"
        )

        let ranks = LadderRung.Kind.allCases.map(\.rank)
        #expect(ranks == [0, 1])
        #expect(Set(ranks).count == ranks.count, "two rungs share a rank")

        #expect(LadderRung.Kind.ambient.rank == 0)
        #expect(LadderRung.Kind.panel.rank == 1)
        #expect(LadderRung.Kind.ambient < LadderRung.Kind.panel)
    }

    /// The ladder tops out at the panel. The recommitment rung above it is deferred to focus-5ab,
    /// and there was never anything above *that* either — no dimming, no blocking, no quitting, no
    /// friction timer (D-07, R-99).
    @Test("the rungs form one chain that ends at the panel")
    func rungsFormOneChain() {
        #expect(LadderRung.Kind.ambient.next == .panel)
        #expect(LadderRung.Kind.panel.next == nil)
    }

    // MARK: - Provenance: a rung comes from a mandate and from nothing else

    /// **R-76's third structural fact.** The only two producers of a rung both start from an
    /// `InterventionMandate`; there is no overload taking a `QueryWarrant`, a `Verdict` or a
    /// `Bool`, and `check-forbidden.sh` (R-96c) asserts that `LadderRung(` appears in exactly
    /// one source file, that the file names `InterventionMandate`, and that it does not name
    /// `QueryWarrant`.
    ///
    /// What this test can assert is the other half: whatever route a rung took, the mandate it
    /// arrived with is the one it carries — so a rung can always be traced back to the
    /// `unrelated` verdict that authorised it.
    @Test("every rung carries the mandate it was built from, at every stage")
    func everyRungCarriesItsMandate() {
        let mandate = Self.mandate()
        var rung = LadderRung.entry(for: mandate)
        var visited: [LadderRung.Kind] = []

        while true {
            #expect(rung.mandate == mandate, "a rung lost its authorisation on the way up")
            #expect(rung.mandate.band >= RelevancePolicy.interventionBandFloor)
            visited.append(rung.kind)
            guard let next = rung.escalated(for: mandate) else { break }
            #expect(next.kind.rank == rung.kind.rank + 1, "escalation skipped a rung")
            rung = next
        }

        #expect(visited == [.ambient, .panel])
    }

    /// **The ladder never re-enters at the rung it left.** A person who came back and drifted
    /// again starts at the silent glyph, because starting at the panel would punish them for
    /// having complied once.
    @Test("a fresh mandate always enters at the ambient rung")
    func entryIsAlwaysAmbient() {
        for subject in ["com.apple.Safari", "com.chrismitchelmore.FocusDecoy"] {
            #expect(LadderRung.entry(for: Self.mandate(subject: subject)).kind == .ambient)
        }
        // Including after a full climb: a new entry starts over, it does not resume.
        let mandate = Self.mandate()
        let top = LadderRung.entry(for: mandate).escalated(for: mandate)
        #expect(top?.kind == .panel)
        #expect(top?.escalated(for: mandate) == nil, "the ladder climbed past the panel")
        #expect(LadderRung.entry(for: mandate).kind == .ambient)
    }

    /// A mixed mandate has no single subject to name, and the rung says so rather than
    /// misnaming one of several applications.
    @Test("a mixed mandate's rung names nobody")
    func mixedMandateNamesNobody() {
        #expect(LadderRung.entry(for: Self.mandate()).subject == "com.chrismitchelmore.FocusDecoy")
        #expect(LadderRung.entry(for: Self.mandate(isMixed: true)).subject == nil)
    }

    // MARK: - RungDelivery is three answers, not a Bool

    /// **R-81, as a property of the type.** `RungDelivery` exposes three *optional payload*
    /// accessors and no `Bool`: there is no `isDelivered`, no `succeeded`, no `asBool`. A
    /// `Bool` is exactly the collapse this type exists to prevent — `if delivered { escalate()
    /// }` would treat a deferral as a delivery the first time somebody wrote it that way, and
    /// the line would read correctly in review.
    ///
    /// The absence is held by the declaration and by the compiler; what this asserts is that
    /// every accessor is a payload, that exactly one of the three is non-`nil` for any value,
    /// and that a deferral and a delivery are never equal.
    @Test("RungDelivery has no Bool projection: three optional payloads, exactly one non-nil")
    func rungDeliveryIsNotABool() {
        let values: [RungDelivery] = [
            .delivered(.menuBar), .delivered(.panel), .delivered(.notification),
            .delivered(.popoverBadge)
        ]
            + DeferralReason.allCases.map { RungDelivery.deferred($0) }
            + NudgeSuppressionReason.allCases.map { RungDelivery.suppressed($0) }

        for value in values {
            let present = [
                value.surface != nil,
                value.deferralReason != nil,
                value.suppressionReason != nil
            ].filter { $0 }
            #expect(present.count == 1, "\(value) answered more or fewer than one question")
        }

        // A deferral is not a delivery, in the only sense the type offers: equality.
        #expect(RungDelivery.deferred(.menuBarHidden) != RungDelivery.delivered(.menuBar))
        #expect(RungDelivery.deferred(.menuBarHidden) != RungDelivery.deferred(.presentationActive))
        #expect(RungDelivery.delivered(.panel) == RungDelivery.delivered(.panel))
    }

    /// P-131's ways a rung can fail to be seen, each named and each distinct.
    ///
    /// It asserted a `nudge.deferred.*` copy key per case until focus-pzl deleted the four
    /// sentences: a deferral is a moment defined by nobody being able to see the surface, so
    /// there was no screen on which any of them could be read.
    ///
    /// **Five since focus-6pr.4**, and the fifth is the one a person *can* see: an accusation
    /// drawn in a popover that is also carrying a question is drawn beside the pinned decision
    /// and offers nothing, so nobody could answer it. The count is exact rather than a floor for
    /// `rungExitsDeclared`'s reason — a floor cannot see a reason being removed.
    @Test("every deferral reason is named and distinct")
    func deferralReasons() {
        #expect(DeferralReason.allCases.count == 5)
        var seen: Set<String> = []
        for reason in DeferralReason.allCases {
            #expect(seen.insert(reason.rawValue).inserted, "duplicate raw value")
            #expect(DeferralReason(rawValue: reason.rawValue) == reason)
        }
        #expect(DeferralReason.allCases.contains(.menuBarHidden))
        #expect(DeferralReason.allCases.contains(.presentationActive))
        #expect(DeferralReason.allCases.contains(.notificationDeliveryFailed))
        #expect(DeferralReason.allCases.contains(.noSurfaceAvailable))
        #expect(DeferralReason.allCases.contains(.questionPinned))
    }

    @Test("every rung has its own copy key")
    func rungCopyKeys() {
        var keys: Set<String> = []
        for kind in LadderRung.Kind.allCases {
            #expect(kind.copyKey == "nudge.rung.\(kind.rawValue)")
            #expect(keys.insert(kind.copyKey).inserted, "duplicate copy key")
        }
    }

    @Test(
        "no rung copy resolves to its own key",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func copyResolves() {
        for kind in LadderRung.Kind.allCases {
            #expect(String(localized: kind.copyResource) != kind.copyKey)
        }
    }

    // MARK: - The state and the events

    @Test("an idle ladder occupies no rung and has ignored nothing")
    func idleState() {
        #expect(LadderState.idle.rung == nil)
        #expect(LadderState.idle.consecutiveIgnored == 0)
    }

    @Test("an engaged ladder reports its rung and its ignore count")
    func engagedState() {
        let rung = LadderRung.entry(for: Self.mandate())
        let engaged = LadderState.engaged(
            rung: rung, deliveredAt: .seconds(300), consecutiveIgnored: 2
        )
        #expect(engaged.rung == rung)
        #expect(engaged.consecutiveIgnored == 2)

        // The backoff hold keeps the glyph honest: it still occupies the ambient rung.
        let held = LadderState.heldAtAmbient(rung: rung, since: .seconds(900))
        #expect(held.rung?.kind == .ambient)
        #expect(held.consecutiveIgnored == 0)
    }

    /// De-escalation is total: every one of these ends the ladder, and R-80 lists them all.
    @Test("every de-escalation the ruling names is in the vocabulary")
    func deEscalationsAreComplete() {
        let named: Set<LadderDeEscalation> = [
            .corrected, .excusedForThisSession, .snoozed, .paused, .priorityChanged,
            .returnedToTask, .phaseLeftFocus, .verdictRelevant, .sessionEnded
        ]
        #expect(Set(LadderDeEscalation.allCases) == named)
        #expect(LadderDeEscalation.allCases.count == 9)
    }

    @Test("a delivery event carries the whole three-way result, not a flag")
    func eventsCarryTheResult() {
        let delivered = LadderEvent.delivery(.delivered(.panel))
        let deferred = LadderEvent.delivery(.deferred(.presentationActive))
        #expect(delivered != deferred)

        if case .delivery(let result) = deferred {
            #expect(result.deferralReason == .presentationActive)
            #expect(result.surface == nil)
        } else {
            Issue.record("a delivery event stopped carrying its result")
        }

        #expect(LadderEvent.tick(.seconds(60)) != LadderEvent.tick(.seconds(61)))
        #expect(LadderEvent.deEscalated(.corrected) != LadderEvent.deEscalated(.snoozed))
    }
}
