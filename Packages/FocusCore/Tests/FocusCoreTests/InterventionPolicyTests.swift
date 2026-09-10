import Foundation
import Testing

@testable import FocusCore

/// The nudge's own constants, its own digest, and the relations that stop it drifting away
/// from the engine it sits on top of (R-95, R-59, R-74).
///
/// Two guarantees, and they are not the same one. The digest guards against *silent change*:
/// a threshold cannot move without a version bump and a re-recorded literal. The relations and
/// the ordering invariants guard against something the digest cannot see — a set of constants
/// each of which is defensible on its own and which together produce a cap that never bites, a
/// question that arrives before a look-back can see it, or a shared budget that is not shared.
@Suite("Intervention policy")
struct InterventionPolicyTests {
    /// The committed digest. **Re-record this only together with a row appended to
    /// `InterventionPolicy.revisions`**, and only after the constant that moved has a boundary
    /// triple and a witness that would notice.
    static let committedDigest: UInt64 = 0x7d5b_dfde_c879_8b65

    @Test("the intervention digest equals its committed literal")
    func digestIsCommitted() {
        #expect(
            InterventionPolicy.digest == Self.committedDigest,
            """
            The intervention policy changed. Encoding was:
            \(InterventionPolicy.canonicalEncoding)
            digest = \(InterventionPolicy.digestHex)

            If that change was intended: append a row to InterventionPolicy.revisions saying
            what moved and why, re-record this literal, and make sure the constant that moved
            carries a boundary triple and a mutation witness (R-74.1, R-95).
            """
        )
        #expect(InterventionPolicy.digestHex.hasPrefix("0x"))
        #expect(InterventionPolicy.digestHex.count == 18)
    }

    /// **R-95's whole reason for existing.** The nudge's thresholds must not be able to
    /// invalidate e06's verdict cache, so the two digests are different values computed over
    /// different manifests, and `EngineStamp.cacheKey` carries exactly one of them.
    @Test("the two policies have two digests, and only one of them is in the cache key")
    func theTwoPoliciesAreSeparate() {
        #expect(InterventionPolicy.digest != RelevancePolicy.digest)
        #expect(InterventionPolicy.canonicalEncoding != RelevancePolicy.canonicalEncoding)

        let key = EngineStamp.current.cacheKey
        #expect(!key.contains(InterventionPolicy.digestHex))
        #expect(!key.contains("\(InterventionPolicy.version)i"))

        // And no constant name appears in both manifests: a threshold with two homes is a
        // threshold that can be moved in one of them.
        let engine = Set(RelevancePolicy.manifest.map(\.name))
        let nudge = Set(InterventionPolicy.manifest.map(\.name))
        #expect(engine.intersection(nudge).isEmpty)
    }

    @Test("every constant is reachable from the digest, and named exactly once")
    func everyConstantIsDigested() {
        let names = InterventionPolicy.manifest.map(\.name)
        #expect(Set(names).count == names.count, "a constant is named twice in the manifest")
        #expect(names.count == 15, "R-95 commits fifteen constants; the manifest has \(names.count)")

        for constant in InterventionPolicy.manifest {
            #expect(!constant.encoded.isEmpty, "\(constant.name) encodes to nothing")
            #expect(!constant.justification.isEmpty, "\(constant.name) names no probe or ruling")
            #expect(
                InterventionPolicy.canonicalEncoding
                    .contains("\(constant.name)=\(constant.encoded)"),
                "\(constant.name) is not in the canonical encoding"
            )
        }
    }

    /// R-74.1: a behavioural constant with no witness is a constant no fixture actually tests,
    /// whatever the digest says about it.
    @Test("every B constant declares a mutation witness and a mutation value")
    func behaviouralConstantsDeclareTheirEvidence() {
        let behavioural = InterventionPolicy.manifest.filter { $0.kind == .behavioural }
        #expect(behavioural.count == 9)

        for constant in behavioural {
            #expect(
                !constant.witnesses.isEmpty,
                "B constant \(constant.name) names no fixture that would notice it moving"
            )
            #expect(
                !constant.mutations.isEmpty,
                "B constant \(constant.name) names no plausible alternative value"
            )
            for witness in constant.witnesses {
                #expect(
                    witness.hasPrefix("gc-") || witness.hasPrefix("seq-")
                        || witness.hasPrefix("day-"),
                    "\(constant.name) names \(witness), which is not a fixture id"
                )
            }
        }
    }

    @Test("C and S constants owe an ordering test or a purge test, not a witness")
    func nonBehaviouralConstantsDeclareNoWitness() {
        for constant in InterventionPolicy.manifest where constant.kind != .behavioural {
            #expect(
                constant.witnesses.isEmpty,
                "\(constant.name) is class \(constant.kind.rawValue) but names a witness"
            )
            #expect(
                constant.mutations.isEmpty,
                "\(constant.name) is class \(constant.kind.rawValue) but names a mutation"
            )
        }
    }

    // MARK: - The two relations (R-95)

    /// A question may come at **half** the dwell an accusation needs, because it is cheaper —
    /// one click, a durable rule, and the app never has to ask again. Asserted as a relation
    /// rather than as two independent numbers, so that moving e04's threshold without moving
    /// this one is a red gate rather than a silent change of posture.
    @Test("a question needs exactly half the dwell an accusation needs")
    func queryDwellIsHalfSustainedDrift() {
        #expect(
            InterventionPolicy.queryDwellThreshold * 2 == RelevancePolicy.sustainedDriftThreshold
        )
        #expect(InterventionPolicy.queryDwellThreshold == .seconds(45))
        #expect(InterventionPolicy.queryDwellThreshold > .zero, "a question is never instant")
    }

    /// A question and a look-back must agree on what "just now" means, or the app can ask about
    /// something its own evidence window has already forgotten.
    @Test("the query cooldown is the look-back span")
    func queryCooldownIsTheLookBackSpan() {
        #expect(InterventionPolicy.queryCooldown == RelevancePolicy.lookBackSpan)
        #expect(InterventionPolicy.queryCooldown == .seconds(180))
    }

    /// e04's accusation cooldown is untouched: the ladder adds proportionality *above* the
    /// engine's cooldown and never loosens it.
    @Test("the accusation cooldown is still e04's, unchanged")
    func accusationCooldownIsUnchanged() {
        #expect(RelevancePolicy.mandateCooldown == .seconds(600))
        #expect(InterventionPolicy.queryCooldown < RelevancePolicy.mandateCooldown)
    }

    // MARK: - The budget ordering (R-83)

    /// **"Shared" is a word with consequences or it is not shared.** The budget must be less
    /// than the sum of the two per-kind caps, or the two never compete.
    @Test("the shared budget is smaller than the two caps it arbitrates between")
    func sharedBudgetGenuinelyCompetes() {
        #expect(
            InterventionPolicy.dailyInterruptionCap
                < InterventionPolicy.dailyQueryCap + InterventionPolicy.dailyAccusationCap
        )
        #expect(InterventionPolicy.dailyInterruptionCap == 8)
        #expect(InterventionPolicy.dailyQueryCap == 4)
        #expect(InterventionPolicy.dailyAccusationCap == 6)
    }

    /// **The ordering that makes the day cap bite before the shared budget does.** Without it
    /// the all-priorities cap would be decorative: the shared budget would run out first and
    /// the number a person feels — questions per day — would be set by an arithmetic accident
    /// rather than by a constant somebody chose.
    @Test("the per-priority cap, the day cap and the reserved unit are in order")
    func capsAreOrdered() {
        #expect(InterventionPolicy.dailyQueryCap <= InterventionPolicy.dailyQueryCapAllPriorities)
        #expect(
            InterventionPolicy.dailyQueryCapAllPriorities
                < InterventionPolicy.dailyInterruptionCap
                    - InterventionPolicy.reservedAccusationUnits
        )
        #expect(InterventionPolicy.dailyQueryCapAllPriorities == 5)
        #expect(InterventionPolicy.reservedAccusationUnits == 1)
    }

    /// A query never spends the last unit. Running out of budget on questions and therefore
    /// being unable to say "you are off task" is the failure that defeats the product.
    @Test("at least one unit of the shared budget is reserved for an accusation")
    func oneUnitIsReserved() {
        #expect(InterventionPolicy.reservedAccusationUnits >= 1)
        #expect(InterventionPolicy.reservedAccusationUnits < InterventionPolicy.dailyInterruptionCap)
    }

    // MARK: - The structural sets

    /// D-06's ladder as amended by U-2, as a number. `LadderVocabularyTests` asserts the same
    /// value against `LadderRung.Kind.allCases.count`, so the constant and the enum cannot drift.
    /// The third rung — recommitment — is deferred to focus-5ab.
    @Test("the ladder is two rungs")
    func ladderIsTwoRungs() {
        #expect(InterventionPolicy.ladderRungCount == 2)
    }

    @Test("the snooze durations are F-61's three, shortest first")
    func snoozeDurationsAreOrdered() {
        // One minute, five and twenty since focus-oqsx: the identity round's spans, moved into
        // the policy so the panel and the dials cannot disagree about what a snooze is.
        #expect(
            InterventionPolicy.snoozeDurations == [.seconds(60), .seconds(300), .seconds(1_200)]
        )
        #expect(InterventionPolicy.snoozeDurations == InterventionPolicy.snoozeDurations.sorted())
        #expect(Set(InterventionPolicy.snoozeDurations).count == 3)
    }

    @Test("the pause presets are F-64's three, and one of them is a fixed span")
    func pausePresets() {
        #expect(InterventionPolicy.pauseDurations.count == 3)
        #expect(InterventionPolicy.pauseDurations.first == .fixed(.seconds(900)))
        #expect(InterventionPolicy.pauseDurations.contains(.untilTime))
        #expect(InterventionPolicy.pauseDurations.contains(.restOfDay))
    }

    /// **Quiet hours default to off, with no bundled window.** A default "22:00–08:00" would be
    /// the app making a claim about a person's life it has no evidence for.
    @Test("quiet hours ship off, with no window at all")
    func quietHoursDefaultIsOff() {
        #expect(InterventionPolicy.quietHoursDefault == nil)
        #expect(InterventionPolicy.canonicalEncoding.contains("quietHoursDefault=none"))
    }

    /// **Both backoffs trip at the same count and last the same span** (focus-845, R-83).
    ///
    /// The asymmetry this asserts away was a shipping defect, not an aesthetic one: the query
    /// side armed `queriesSuspendedUntil` and the accusation side armed a `Bool` nothing but a
    /// session end could clear. Since U-2 cut the ladder to two rungs the panel is the only rung
    /// that says anything, so "for the rest of the session" muted the product on two clicks. One
    /// span with two consumers is what makes the two halves unable to drift apart again; a
    /// second constant asserted equal would be a threshold with two homes.
    @Test("the two backoffs are one policy: same count, same hour")
    func theTwoBackoffsAgree() {
        #expect(
            InterventionPolicy.ignoredQueryBackoff
                == InterventionPolicy.ignoredAccusationBackoff
        )
        #expect(InterventionPolicy.backoffSpan == .seconds(3600))
        #expect(InterventionPolicy.backoffSpan > .zero, "a backoff with no span is a mute")

        // Both consumers read the one constant, and the reducer is what proves it: a tripped
        // hold and a tripped suspension name the same instant when they trip together.
        var controller = FatigueController()
        for _ in 0..<InterventionPolicy.ignoredQueryBackoff {
            controller.reduce(.queryResolved(.declined), now: .seconds(7))
        }
        for _ in 0..<InterventionPolicy.ignoredAccusationBackoff {
            controller.reduce(.accusationResolved(.ignored), now: .seconds(7))
        }
        #expect(controller.state.queriesSuspendedUntil == controller.state.accusationsHeldUntil)
        #expect(
            controller.state.accusationsHeldUntil
                == .seconds(7) + InterventionPolicy.backoffSpan
        )
    }

    @Test("the query ledger rides its priority's lifetime")
    func ledgerRetention() {
        #expect(InterventionPolicy.queryLedgerRetention == .withPriority)
    }

    // MARK: - The version

    @Test("the version is the count of revisions, and every revision says what moved")
    func versionTracksTheRevisions() {
        #expect(InterventionPolicy.version == InterventionPolicy.revisions.count)
        #expect(InterventionPolicy.version == 5)
        for revision in InterventionPolicy.revisions {
            #expect(!revision.isEmpty, "a policy revision with no reason is a version churning")
        }
    }

    /// The stamp carries both digests, and the self-check and the evaluation report read this
    /// one from it.
    @Test("the stamp carries the intervention version and digest")
    func stampCarriesTheInterventionPolicy() {
        #expect(EngineStamp.current.interventionVersion == InterventionPolicy.version)
        #expect(EngineStamp.current.interventionDigest == InterventionPolicy.digestHex)
        #expect(
            EngineStamp.current.withEmbeddingRevision(1).interventionDigest
                == InterventionPolicy.digestHex
        )
    }
}
