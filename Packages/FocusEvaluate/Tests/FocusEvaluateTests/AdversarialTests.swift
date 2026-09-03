import FocusCore
import FocusEvaluateCore
import Foundation
import Testing

@testable import FocusClassify

/// The eleven ambiguity families (R-68, F-153).
///
/// Ten of them put a *plausible distraction* in front of the engine and ask it to decline. The
/// eleventh puts the person's actual work in front of it and asks the same, because the first
/// ten shared a blind spot: none of them could fail on the engine's most damaging output, which
/// is an accusation levelled at somebody doing their job. A suite that cannot fail on that is a
/// suite that certifies it.
///
/// Two properties are asserted here that the corpus's own expectations cannot state:
///
/// * **Coverage, family by family.** Each family meets *its own* floor, so a family cannot be
///   padded by another's cases — thirty productive-tool cases would otherwise stand in for two
///   multilingual ones and the suite would look complete.
/// * **Discrimination.** Every non-control case declines and **every declared control
///   resolves**. Without the second half the suite would be satisfied by an engine that says
///   `uncertain` to everything, which is safe and useless.
@Suite("Adversarial ambiguity families")
struct AdversarialTests {
    static func adversarialCases() throws -> [CorpusCase] {
        try CorpusFixtures.loaded().adversarial
    }

    // MARK: - Coverage

    @Test("all eleven families are present and each meets its own floor")
    func everyFamilyMeetsItsFloor() throws {
        let cases = try Self.adversarialCases()
        for family in EvaluationPolicy.families {
            let members = cases.filter { $0.families.contains(family.name) }
            let detail = "\(family.name) has \(members.count) cases, floor \(family.floor) "
                + "— mechanism: \(family.mechanism)"
            #expect(members.count >= family.floor, "\(detail)")
        }
        #expect(
            EvaluationPolicy.families.count == EvaluationPolicy.declaredFamilyCount,
            "R-68 declares eleven families"
        )
    }

    @Test("the adversarial subset meets its committed floor")
    func theSubsetMeetsItsFloor() throws {
        let cases = try Self.adversarialCases()
        #expect(cases.count >= EvaluationPolicy.adversarialFloor)
    }

    /// The one family whose floor is not the common one. Three subjects × three dwell points is
    /// the minimum shape, and R-68 adds the negative controls and the kind coverage on top.
    @Test("family 11 carries at least nine cases")
    func theProductiveToolFamilyIsLargeEnough() throws {
        let members = try Self.adversarialCases()
            .filter { $0.families.contains(EvaluationPolicy.productiveToolFamily) }
        #expect(members.count >= EvaluationPolicy.productiveToolFamilyFloor)
    }

    // MARK: - Every adversarial case declines, unless it is a declared control

    @Test("every adversarial case is uncertain unless it is a declared negative control")
    func adversarialCasesDecline() throws {
        for testCase in try Self.adversarialCases() where !testCase.isNegativeControl {
            let detail = "\(testCase.id) (\(testCase.families.joined(separator: ", "))) expects "
                + "\(testCase.expect.verdict.rawValue) and is not a declared control"
            #expect(testCase.expect.verdict == .uncertain, "\(detail)")
            #expect(
                testCase.expect.eligibility == .suppressed(.verdictUncertain),
                "\(testCase.id) does not suppress by the verdict route"
            )
        }
    }

    /// The half that stops the suite being satisfied by timidity. Every family has at least one
    /// case that resolves, and every declared control does resolve.
    @Test("every family carries a control, and every control resolves")
    func everyFamilyDiscriminates() throws {
        let cases = try Self.adversarialCases()
        for family in EvaluationPolicy.families {
            let controls = cases.filter {
                $0.families.contains(family.name) && $0.isNegativeControl
            }
            #expect(!controls.isEmpty, "\(family.name) has no negative control")
        }
        for control in cases where control.isNegativeControl {
            #expect(
                control.expect.verdict != .uncertain,
                "\(control.id) is declared a negative control but does not resolve"
            )
        }
    }

    /// **Family 11's first obligation.** Dwell alone must not be able to walk a case across the
    /// line, and the only way to prove that is to put a case on each side of it. Every
    /// non-control member of the family is checked against all three dwell points to make sure
    /// the triple is actually present rather than merely claimed.
    @Test("family 11 brackets the sustained-drift threshold on both sides")
    func theProductiveToolFamilyBracketsTheThreshold() throws {
        let members = try Self.adversarialCases()
            .filter { $0.families.contains(EvaluationPolicy.productiveToolFamily) }
        let threshold = Int(RelevancePolicy.sustainedDriftThreshold.components.seconds)
        let declining = members.filter { !$0.isNegativeControl }
        let dwells = Set(declining.map(\.dwellSeconds))

        #expect(dwells.contains(threshold - 1), "no case one second below the threshold")
        #expect(dwells.contains(threshold), "no case exactly on the threshold")
        #expect(dwells.contains(threshold + 1), "no case one second above the threshold")

        for testCase in declining {
            #expect(
                testCase.expect.verdict == .uncertain,
                "\(testCase.id) at \(testCase.dwellSeconds)s is not uncertain"
            )
        }
    }

    /// **Family 11's second obligation**, and the more consequential half. One control resolves
    /// `relevant` through the context pack; one resolves `unrelated` through a user rule. The
    /// second matters more: it proves the engine is *capable* of the accusation and is declining
    /// it for a reason, rather than being structurally unable to make it.
    @Test("family 11 carries a resolving control in each direction")
    func theProductiveToolFamilyResolvesBothWays() throws {
        let controls = try Self.adversarialCases().filter {
            $0.families.contains(EvaluationPolicy.productiveToolFamily) && $0.isNegativeControl
        }
        #expect(
            controls.contains { $0.expect.verdict == .relevant },
            "no control resolves relevant"
        )
        let accusing = controls.filter { $0.expect.verdict == .unrelated }
        #expect(!accusing.isEmpty, "no control resolves unrelated — the engine is never shown to be capable of the accusation it declines")
        #expect(
            accusing.contains { $0.expect.eligibility == .mandated },
            "no control actually mandates"
        )
        #expect(
            accusing.contains { $0.rules.contains { $0.verdict == .unrelated } },
            "no control reaches unrelated through a user rule"
        )
    }

    /// **Family 11's third obligation.** One case where the pack holds only an `app` identity
    /// and one where it holds only a `domain`, so the gate cannot pass by accident on a single
    /// kind — and one where it holds only a `keyword` and one only a `file`, which must **still**
    /// be uncertain, because R-56.1 excludes both from the basis.
    @Test("family 11 covers both basis kinds and both excluded kinds")
    func theProductiveToolFamilyCoversEveryContextKind() throws {
        let members = try Self.adversarialCases()
            .filter { $0.families.contains(EvaluationPolicy.productiveToolFamily) }

        func soleKind(_ kind: ContextItemKind) -> [CorpusCase] {
            members.filter { $0.contextPack.count == 1 && $0.contextPack.first?.kind == kind }
        }

        for kind in RelevancePolicy.negativeBasisKinds {
            let resolving = soleKind(kind).filter { $0.expect.verdict == .unrelated }
            #expect(!resolving.isEmpty, "no \(kind.rawValue)-only case resolves unrelated")
        }
        for kind in [ContextItemKind.keyword, .file] {
            let cases = soleKind(kind)
            #expect(!cases.isEmpty, "no \(kind.rawValue)-only case at all")
            for testCase in cases {
                #expect(
                    testCase.expect.verdict == .uncertain,
                    "\(testCase.id): a \(kind.rawValue)-only pack was treated as a negative basis"
                )
                #expect(testCase.expect.uncertaintyReason == .noNegativeBasis)
            }
        }
    }

    // MARK: - The engine actually does it

    /// The expectations above are statements about the corpus. This runs it.
    @Test("the engine declines every adversarial case it is supposed to")
    func theEngineDeclines() throws {
        let runner = CorpusFixtures.runner
        var wrong: [String] = []
        for testCase in try Self.adversarialCases() {
            let outcome = runner.run(testCase)
            if let mismatch = runner.compare(testCase, to: outcome) {
                wrong.append(mismatch.description)
            }
            if !testCase.isNegativeControl, outcome.verdict != .uncertain {
                wrong.append("\(testCase.id) resolved \(outcome.verdict.rawValue) and is not a control")
            }
            if outcome.isMandated, testCase.expect.eligibility != .mandated {
                wrong.append("\(testCase.id) MANDATED and was not expected to — a false nudge")
            }
        }
        #expect(wrong.isEmpty, "\(wrong.joined(separator: "\n"))")
    }

    /// **`falseNudgeRate == 0.0` on the adversarial subset, stated directly.** Not "small": every
    /// case here is one somebody wrote deliberately with an expectation, and a single false
    /// nudge on a case somebody thought about is a product defect.
    @Test("no adversarial case produces an unexpected mandate")
    func noAdversarialFalseNudge() throws {
        let runner = CorpusFixtures.runner
        let offenders = try Self.adversarialCases()
            .filter { runner.run($0).isMandated && $0.expect.eligibility != .mandated }
            .map(\.id)
        #expect(offenders.isEmpty, "false nudges on \(offenders.joined(separator: ", "))")
    }

    /// R-68's negative-control accounting: the uncertainty rate the gate reads is computed over
    /// `caseCount − negativeControlCount`, so a declared control cannot dilute it. Asserted here
    /// as well as in the harness, because the denominator is the part of a rate that goes wrong
    /// quietly.
    @Test("the uncertainty rate excludes declared controls and clears its floor")
    func theUncertaintyRateIsComputedOverDecliningCasesOnly() throws {
        let cases = try Self.adversarialCases()
        let declining = cases.filter { !$0.isNegativeControl }
        #expect(!declining.isEmpty)

        let runner = CorpusFixtures.runner
        let uncertain = declining.filter { runner.run($0).verdict == .uncertain }.count
        let rate = Double(uncertain) / Double(declining.count)
        #expect(rate >= 0.90, "adversarial uncertainty rate \(rate) over \(declining.count) cases")
    }
}
