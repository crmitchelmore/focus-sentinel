import FocusCore
import Foundation
import Testing

@testable import FocusClassify

/// **The deferral, and the case it used to answer wrongly.**
///
/// The adversarial review of the e06 plan found this by reading the shipped code rather than
/// the shipped comments. `HeuristicClassifier`'s step 5 — `guard snapshot.hasNegativeBasis` —
/// fired **before** step 6, the `askEachTime` seed check. So a priority with no identity in its
/// context pack, with Safari in front of it, answered `uncertain(.noNegativeBasis)` at rung 5
/// and the cascade terminated there.
///
/// Two things are wrong with that, and only one of them is about e06.
///
/// The one that is about e06: `noNegativeBasis` is the answer e06 marks
/// `.reviewable(by: .onDeviceModel)`, and §2.3 declares a mixed-use application
/// **non-consultable** — asking a model whether "Safari" is the work is asking it to guess at a
/// browser, which is the one subject whose identity is known to be uninformative. The deferral
/// as the plan first specified it would have handed the model exactly the cases it must not
/// judge.
///
/// The one that is not: even with no model in the build, the *reason* was wrong. This app ships
/// an opinion about Safari — "ask each time" — and that opinion is a better account of why the
/// engine declined than "you named no app or site". A person reading the inspector was told to
/// go and add context when the engine would have declined about a browser regardless.
///
/// The fix is an ordering, not a new rung: step 6 and the basis-identity check are hoisted
/// above step 5's guard, so a `seedFallback` subject declines out of the heuristic and rung 7
/// answers `mixedUseApplication` — which is what the ladder always said should happen and what
/// it already did whenever the priority *had* a basis.
///
/// **This suite is red at HEAD before that hoist.** The first test reads `.noNegativeBasis`.
@Suite("Heuristic deferral order")
struct HeuristicDeferralTests {
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)
    static let priorityID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")!

    let normalizer = TokenNormalizer()

    /// Every bundled `askEachTime` seed — the mixed-use applications. Read from the seed table
    /// rather than listed, so a seed added later is covered without an edit here.
    static var mixedUseSubjects: [String] {
        RelevanceSeed.fallbackSeeds.keys.sorted()
    }

    func snapshot(
        intent: String = "write the q3 proposal for acme",
        contextPack: [ContextItemValue] = []
    ) -> RuleSnapshot {
        RuleSnapshotBuilder(normalizer: normalizer).build(
            priority: PriorityInput(id: Self.priorityID, revision: 1, intent: intent),
            contextPack: contextPack
        )
    }

    func evidence(bundleID: String, dwellSeconds: Int) -> ClassificationEvidence {
        ClassificationEvidence.make(
            input: ClassificationInput(bundleIdentifier: bundleID, origin: nil, titleTokens: []),
            dwell: .seconds(dwellSeconds),
            normalizer: normalizer
        )
    }

    /// **The red-at-HEAD assertion.** Safari, a real priority, and an identity-free context
    /// pack: the heuristic must decline so that rung 7 can say what it has always said about a
    /// browser.
    @Test("a browser with no identity context is a mixed-use decline, not a missing basis")
    func safariWithoutABasisDeclinesToTheSeedRung() {
        let cascade = RuleCascade(heuristic: HeuristicClassifier())
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari", dwellSeconds: 300),
            snapshot: snapshot()
        )

        #expect(resolution.uncertaintyReason == .mixedUseApplication)
        #expect(resolution.stage == .seedFallback)
        #expect(resolution.verdict == .uncertain)
    }

    /// And the heuristic itself declines rather than answering — the same fact one rung down,
    /// so a change that moved the answer somewhere else would still be caught.
    @Test("the heuristic returns nothing at all for a mixed-use subject with no basis")
    func theHeuristicDeclines() {
        for subject in Self.mixedUseSubjects {
            let answer = HeuristicClassifier().judge(
                evidence: evidence(bundleID: subject, dwellSeconds: 300),
                snapshot: snapshot()
            )
            #expect(answer == nil, "\(subject) with no negative basis")
        }
    }

    /// The half that must not move: a mixed-use subject with a basis behaved correctly before
    /// this fix and behaves identically after it. The hoist changes the answer for one shape of
    /// input; asserting the other shape is what makes that claim narrow rather than hopeful.
    @Test("a browser WITH identity context still answers mixed-use, unchanged")
    func safariWithABasisIsUnchanged() {
        let pack = [
            ContextItemValue.app(
                bundleID: "com.microsoft.Excel", displayName: "Excel", addedAt: Self.reference
            )
        ]
        let cascade = RuleCascade(heuristic: HeuristicClassifier())
        let resolution = cascade.evaluate(
            evidence: evidence(bundleID: "com.apple.Safari", dwellSeconds: 300),
            snapshot: snapshot(contextPack: pack)
        )

        #expect(resolution.uncertaintyReason == .mixedUseApplication)
        #expect(resolution.stage == .seedFallback)
    }

    /// A subject that is **not** seeded still reports the missing basis, at every dwell. The
    /// hoist must not have turned `noNegativeBasis` into a reason nothing can reach — a clause
    /// whose copy carries the epic's only ask is worth an assertion that it is still asked.
    @Test("a lexically silent tool with no basis still names the missing basis")
    func anUnseededToolStillNamesTheBasis() {
        for dwell in [0, 90, 300, 3_600] {
            let answer = HeuristicClassifier().judge(
                evidence: evidence(bundleID: "com.microsoft.Excel", dwellSeconds: dwell),
                snapshot: snapshot()
            )
            #expect(answer?.uncertaintyReason == .noNegativeBasis, "at \(dwell)s")
            #expect(answer?.verdict == .uncertain)
        }
    }

    /// And the invariant the whole ordering exists under: **no route through this rung reaches
    /// `unrelated` for a mixed-use subject**, whatever the dwell and whatever the context pack.
    @Test("no mixed-use subject is ever accused, at any dwell, with or without a basis")
    func noMixedUseSubjectIsEverAccused() {
        let packs: [[ContextItemValue]] = [
            [],
            [.app(bundleID: "com.microsoft.Excel", displayName: "Excel", addedAt: Self.reference)],
            [.keyword("acme", addedAt: Self.reference)!]
        ]
        let cascade = RuleCascade(heuristic: HeuristicClassifier())
        var judged = 0
        for subject in Self.mixedUseSubjects {
            for dwell in [0, 90, 300, 7_200] {
                for pack in packs {
                    let resolution = cascade.evaluate(
                        evidence: evidence(bundleID: subject, dwellSeconds: dwell),
                        snapshot: snapshot(contextPack: pack)
                    )
                    judged += 1
                    #expect(resolution.verdict != .unrelated, "\(subject) at \(dwell)s")
                }
            }
        }
        #expect(judged == Self.mixedUseSubjects.count * 4 * packs.count)
    }
}
