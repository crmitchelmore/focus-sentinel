import Foundation
import Testing

@testable import FocusCore

/// The constants, and what each of them owes (R-59, R-74).
///
/// Two different guarantees are asserted here and they are not the same one. The digest is a
/// guard against *silent change*: a threshold cannot move without a version bump and a
/// re-recorded literal. The manifest assertions are the beginning of the stronger property —
/// that the value was right to begin with — which `MutationWitnessTests` (T104a) completes by
/// re-running the corpus against a mutated policy.
@Suite("Relevance policy")
struct RelevancePolicyTests {
    /// The committed digest. **Re-record this only together with a bump to
    /// `EngineStamp.policyVersion`**, and only after the constant that moved has a boundary
    /// triple and a witness that flips.
    static let committedDigest: UInt64 = 0xdfff_9acc_b6fd_410f

    @Test("the policy digest equals its committed literal")
    func digestIsCommitted() {
        #expect(
            RelevancePolicy.digest == Self.committedDigest,
            """
            The relevance policy changed. Encoding was:
            \(RelevancePolicy.canonicalEncoding)
            digest = \(RelevancePolicy.digestHex)

            If that change was intended: bump EngineStamp.policyVersion, re-record this
            literal and EngineStampTests' cacheKey, and make sure the constant that moved
            carries a boundary triple and a mutation witness (R-74.1).
            """
        )
        #expect(RelevancePolicy.digestHex.hasPrefix("0x"))
        #expect(RelevancePolicy.digestHex.count == 18)
    }

    /// The digest is over the manifest, so a constant added to the file but not to the
    /// manifest would be an *undigested* threshold — one that could move without failing
    /// anything. This is the assertion that makes the manifest total.
    @Test("every constant is reachable from the digest, and named exactly once")
    func everyConstantIsDigested() {
        let names = RelevancePolicy.manifest.map(\.name)
        #expect(Set(names).count == names.count, "a constant is named twice in the manifest")
        #expect(names.count == 20, "R-59 commits twenty constants; the manifest has \(names.count)")

        for constant in RelevancePolicy.manifest {
            #expect(!constant.encoded.isEmpty, "\(constant.name) encodes to nothing")
            #expect(!constant.justification.isEmpty, "\(constant.name) names no probe or ruling")
            #expect(
                RelevancePolicy.canonicalEncoding.contains("\(constant.name)=\(constant.encoded)"),
                "\(constant.name) is not in the canonical encoding"
            )
        }
    }

    /// **R-74.1, and the assertion that makes the class column load-bearing rather than
    /// documentation.** A behavioural constant with no witness is a constant the corpus does
    /// not actually test, whatever the digest says about it.
    @Test("every B constant declares a mutation witness and a mutation value")
    func behaviouralConstantsDeclareTheirEvidence() {
        let behavioural = RelevancePolicy.manifest.filter { $0.kind == .behavioural }
        #expect(!behavioural.isEmpty)

        for constant in behavioural {
            #expect(
                !constant.witnesses.isEmpty,
                "B constant \(constant.name) names no corpus case that would notice it moving"
            )
            #expect(
                !constant.mutations.isEmpty,
                "B constant \(constant.name) names no plausible alternative value"
            )
            for witness in constant.witnesses {
                #expect(
                    witness.hasPrefix("gc-") || witness.hasPrefix("seq-"),
                    "\(constant.name) names \(witness), which is not a corpus case id"
                )
            }
        }
    }

    /// The converse: a capacity or structural constant that quietly grew a witness list would
    /// be a constant claiming evidence it does not owe, which is how a class column stops
    /// meaning anything.
    @Test("C and S constants owe a benchmark or an ordering test, not a witness")
    func nonBehaviouralConstantsDeclareNoWitness() {
        for constant in RelevancePolicy.manifest where constant.kind != .behavioural {
            #expect(constant.witnesses.isEmpty, "\(constant.name) is class \(constant.kind.rawValue) but names a witness")
            #expect(constant.mutations.isEmpty, "\(constant.name) is class \(constant.kind.rawValue) but names a mutation")
        }

        let capacity = RelevancePolicy.manifest.filter { $0.kind == .capacity }.map(\.name)
        #expect(Set(capacity) == ["similarityCacheCapacity", "maximumLookBackEvents"])
    }

    /// **Green since T90a (probe P-124) supplied the measurement.**
    ///
    /// R-74.2: `similarityRelevantCeiling` and `languageConfidenceFloor` are *derived, not
    /// chosen*. P-113's sixteen pairs and P-115's four strings cannot fix a float — one
    /// additional unrelated pair below the drafted ceiling would falsify its whole
    /// justification — so the plan commits the derivation **rule** here and defers the value
    /// to a corpus wide enough to fix it. A constant measured after the code that reads it was
    /// written is a constant chosen to keep that code green, and this red gate is what stops
    /// that happening. It cleared when T90a landed the tables and the values —
    /// `similarityRelevantCeiling = 0.97` from 62 labelled pairs, `languageConfidenceFloor =
    /// 0.84` from 42 labelled strings — and `SimilarityCorpusTests` now recomputes both from
    /// the committed tables, so a hand-edited constant against an unchanged table is a red
    /// gate rather than a silent one.
    @Test("the two derived constants are measured, not chosen")
    func derivedConstantsAreMeasured() {
        let pending = [
            ("similarityRelevantCeiling", RelevancePolicy.similarityRelevantCeiling),
            ("languageConfidenceFloor", RelevancePolicy.languageConfidenceFloor)
        ].filter { !$0.1.isMeasured }.map(\.0)

        #expect(
            pending.isEmpty,
            """
            \(pending.joined(separator: ", ")) is still .pendingMeasurement.

            This is the plan's own gate (T83, R-74.2), not a defect in the vocabulary: the
            value may not be written down before probe P-124 measures the corpus that derives
            it — ≥ 60 labelled similarity pairs (≥ 24 unrelated) and ≥ 40 labelled language
            strings, committed raw as corpus resources. T90a supplies both tables, computes
            each constant by the committed derivation rule in its doc comment, bumps
            EngineStamp.policyVersion, and re-records this suite's digest literal.
            """
        )
    }

    /// While a threshold is unmeasured its consumer must be *unable* to use it, rather than
    /// falling back to a number somebody liked. `DerivedThreshold` has no default, so a
    /// pending constant yields `nil` and the similarity signal does not run at all — the
    /// conservative direction, and the same answer the English gate gives for a language this
    /// OS has no embedding for.
    @Test("a pending threshold yields no value at all, rather than a fallback")
    func pendingThresholdHasNoValue() {
        #expect(DerivedThreshold.pendingMeasurement.value == nil)
        #expect(DerivedThreshold.pendingMeasurement.encoded == "pending")
        #expect(DerivedThreshold.measured(1.0).value == 1.0)
        #expect(DerivedThreshold.measured(1.0).encoded == "1.00")
        #expect(DerivedThreshold.measured(0.605).encoded == "0.60")
    }

    @Test("every duration is positive and the ordering invariants hold")
    func durationsAreOrdered() {
        let durations: [(String, Duration)] = [
            ("driftResetGrace", RelevancePolicy.driftResetGrace),
            ("returnAnchorDwell", RelevancePolicy.returnAnchorDwell),
            ("sustainedDriftThreshold", RelevancePolicy.sustainedDriftThreshold),
            ("detourExtension", RelevancePolicy.detourExtension),
            ("lookBackSpan", RelevancePolicy.lookBackSpan),
            ("escalationDwell", RelevancePolicy.escalationDwell),
            ("mandateCooldown", RelevancePolicy.mandateCooldown)
        ]
        for (name, duration) in durations {
            #expect(duration > .zero, "\(name) is not positive")
        }

        #expect(RelevancePolicy.driftResetGrace < RelevancePolicy.sustainedDriftThreshold)
        #expect(RelevancePolicy.sustainedDriftThreshold < RelevancePolicy.escalationDwell)
        #expect(RelevancePolicy.escalationDwell < RelevancePolicy.mandateCooldown)
        #expect(RelevancePolicy.returnAnchorDwell < RelevancePolicy.sustainedDriftThreshold)
    }

    /// The look-back is a **relation**, not a number: it must contain a whole detour and its
    /// anchor. Asserting the relation rather than 180 is what stops the two drifting apart.
    @Test("the look-back span is exactly twice the sustained-drift threshold")
    func lookBackIsTwiceTheThreshold() {
        #expect(RelevancePolicy.lookBackSpan == RelevancePolicy.sustainedDriftThreshold * 2)
    }

    /// The effective threshold for an anchored detour is D-05's own worked example: 90 + 90.
    @Test("an anchored detour gets exactly one more grace period")
    func detourExtensionMatchesTheAnchoredCase() {
        #expect(RelevancePolicy.detourExtension == RelevancePolicy.sustainedDriftThreshold)
        #expect(
            RelevancePolicy.sustainedDriftThreshold + RelevancePolicy.detourExtension
                == .seconds(180)
        )
    }

    @Test("the token-length constants are ordered and the strong one is stricter")
    func tokenLengthsAreOrdered() {
        #expect(RelevancePolicy.minimumTokenLength > 0)
        #expect(RelevancePolicy.minimumStrongTokenLength > RelevancePolicy.minimumTokenLength)
        #expect(RelevancePolicy.minimumOverlapTokens > 0)
        #expect(RelevancePolicy.minimumPriorityContentTokens > 0)
        #expect(RelevancePolicy.maximumExplanationTokens > 0)
    }

    /// R-56.1's structural half: only an identity can be absent in a way that means something.
    /// A `keyword` or a `file` in the basis would silently restore the false accusation from
    /// the other direction.
    @Test("the negative basis admits identities only")
    func negativeBasisAdmitsIdentitiesOnly() {
        #expect(RelevancePolicy.negativeBasisKinds == [.app, .domain])
        #expect(!RelevancePolicy.negativeBasisKinds.contains(.keyword))
        #expect(!RelevancePolicy.negativeBasisKinds.contains(.file))
        #expect(RelevancePolicy.minimumNegativeBasisItems >= 1)
    }

    @Test("FNV-1a is stable across calls and processes, and is not Hasher")
    func digestFunctionIsStable() {
        // The empty-input offset basis, and one known vector, so a mangled implementation
        // fails here rather than silently changing every committed digest at once.
        #expect(FNV1a.hash("") == 0xcbf2_9ce4_8422_2325)
        #expect(FNV1a.hash("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(FNV1a.hash("foobar") == 0x85944171f73967e8)
        #expect(FNV1a.hash("focus") == FNV1a.hash("focus"))
        #expect(FNV1a.hex(0) == "0x0000000000000000")
    }
}
