import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// The verdicts every render is drawn from.
///
/// Constructed rather than measured, and every one of them is a state the engine really
/// produces: the corpus in `FocusClassifyTests` contains a case for each. They are built here
/// out of `FocusCore` values alone, because `FocusUI` may not import `FocusClassify` (the R-14
/// matrix) — which is exactly the property R-53 moved the vocabulary to make true.
enum VerdictFixture {
    /// A token, through the only route in. `NormalisedToken` has no `String` initialiser, so a
    /// fixture cannot smuggle a window title into an explanation any more than the engine can.
    static func token(_ value: String) -> NormalisedToken {
        guard let token = NormalisedToken.normalised(value) else {
            preconditionFailure("\(value) is not a normalised token")
        }
        return token
    }

    static func explanation(
        stage: CascadeStage,
        band: EvidenceBand,
        clauses: [ExplanationClause]
    ) -> Explanation {
        Explanation.make(stage: stage, band: band, clauses: clauses, stamp: .current)
    }

    /// `relevant`, decided by the context pack the person attached — rung 3, band `.high`.
    static let relevant = VerdictSnapshot(
        status: .relevant,
        stage: .contextPack,
        band: .high,
        drift: .aligned,
        eligibility: .suppressed(.verdictRelevant),
        explanation: explanation(
            stage: .contextPack,
            band: .high,
            clauses: [.contextItem(kind: .app, subject: token("com.apple.pages"))]
        ),
        stampKey: EngineStamp.current.withEmbeddingRevision(1).cacheKey
    )

    /// **A mandate, made by the only function that can make one** (focus-lmy).
    ///
    /// `InterventionEligibility.decide(…)` is the single producer of `InterventionMandate` —
    /// its memberwise initialiser is `fileprivate` and R-70b asserts the call site is unique —
    /// so a fixture cannot write `.mandated(…)` and there is no way to fake one. Going through
    /// the real decision is therefore not a nicety here; it is the only route, and it means the
    /// picture below is drawn from an authorisation the engine really issues.
    ///
    /// **The `guard` is the point of this function.** The fixture this replaced was *named*
    /// `unrelatedMandated`, doc-commented "and **mandated** … the pane says so", and set
    /// `.suppressed(.withinMandateCooldown)`. Nothing failed, because nothing checked the name
    /// against the value: `settings.verdict.mandated` therefore had no baseline among 447 and
    /// shipped for the whole of e05 saying the nudge could not exist. A fixture whose name
    /// makes a claim has to assert the claim, or the name is decoration.
    static func mandated(
        band: EvidenceBand,
        drift: DriftState,
        explanation: Explanation
    ) -> InterventionEligibility {
        let eligibility = InterventionEligibility.decide(
            outcome: ClassificationOutcome(
                verdict: .unrelated,
                source: .userRule,
                confidence: 1,
                band: band
            ),
            drift: drift,
            phase: .focus,
            status: .unrelated,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: explanation,
            stamp: .current
        )
        guard eligibility.isMandated else {
            preconditionFailure(
                "the fixture named mandated is \(eligibility) — see focus-lmy"
            )
        }
        return eligibility
    }

    /// The drift and the reasons `unrelatedMandated` and `unrelatedInCooldown` share.
    ///
    /// One subject, dwelt on for three and a half minutes against a global rule the person
    /// wrote. The two fixtures differ in exactly one thing — whether the mandate has already
    /// been spent — which is what makes the pair a picture of the *branch* rather than of two
    /// unrelated screens.
    static let sustainedDrift = DriftState.sustained(
        subject: .single("com.apple.ScreenContinuity"),
        accumulated: .seconds(214),
        isMixed: false
    )

    static let sustainedExplanation = explanation(
        stage: .globalRule,
        band: .high,
        clauses: [
            .userRule(
                authority: .global,
                kind: .app,
                subject: token("com.apple.screencontinuity")
            ),
            .sustainedDwell(seconds: 214)
        ]
    )

    /// `unrelated`, sustained past the threshold, and **mandated** — the one frame in this set
    /// in which the app is about to say something.
    ///
    /// e05 is what consumes this: `RelevanceHost` hands the same eligibility to Settings and to
    /// `NudgeHost`, which folds the mandate into the ladder. So this is the picture a person
    /// sees in Settings ▸ Privacy *while* the ambient signal is on and the panel is coming.
    static let unrelatedMandated = VerdictSnapshot(
        status: .unrelated,
        stage: .globalRule,
        band: .high,
        drift: sustainedDrift,
        eligibility: mandated(
            band: .high,
            drift: sustainedDrift,
            explanation: sustainedExplanation
        ),
        explanation: sustainedExplanation,
        stampKey: EngineStamp.current.withEmbeddingRevision(1).cacheKey
    )

    /// The same drift, one rung later: the mandate was issued, the ladder spent it, and the
    /// engine is in cooldown.
    ///
    /// It exists so that converting `unrelatedMandated` into the mandate its name always
    /// claimed does not cost the vocabulary a picture. `withinMandateCooldown` is the reason a
    /// person is most likely to meet twice in one session, and it had the only baseline it will
    /// ever have under the wrong name.
    static let unrelatedInCooldown = VerdictSnapshot(
        status: .unrelated,
        stage: .globalRule,
        band: .high,
        drift: sustainedDrift,
        eligibility: .suppressed(.withinMandateCooldown),
        explanation: sustainedExplanation,
        stampKey: EngineStamp.current.withEmbeddingRevision(1).cacheKey
    )

    /// `unrelated` inside the grace period — drift accumulating, and the app deliberately
    /// quiet. The frame the live lane reads at its first settle point.
    static let unrelatedInGrace = VerdictSnapshot(
        status: .unrelated,
        stage: .heuristic,
        band: .medium,
        drift: .grace(
            subject: .single("com.apple.ScreenContinuity"),
            since: .seconds(0),
            accumulated: .seconds(41)
        ),
        eligibility: .suppressed(.withinGracePeriod),
        explanation: explanation(
            stage: .heuristic,
            band: .medium,
            clauses: [.sustainedDwell(seconds: 41)]
        ),
        stampKey: EngineStamp.current.withEmbeddingRevision(1).cacheKey
    )

    /// **R-56.1, on the surface.** A productive application whose bundle-identifier tokens
    /// share nothing with the priority, dwelt on well past the threshold — and the answer is
    /// `uncertain`, with the one clause in this epic that carries an *ask*.
    ///
    /// This is the single most important picture in the set: it is what the app looks like
    /// when it declines to accuse somebody who is doing their work.
    static let uncertainNoNegativeBasis = VerdictSnapshot(
        status: .uncertain,
        stage: .heuristic,
        band: nil,
        drift: .aligned,
        eligibility: .suppressed(.verdictUncertain),
        explanation: explanation(
            stage: .heuristic,
            band: .low,
            clauses: [
                .noNegativeBasis,
                .insufficientEvidence(reason: .noNegativeBasis)
            ]
        ),
        stampKey: EngineStamp.current.withEmbeddingRevision(1).cacheKey
    )

    /// The session is not in focus, so nothing on screen is being judged as drift.
    static let onBreak = VerdictSnapshot(
        status: .onBreak,
        stage: .unresolved,
        band: nil,
        drift: .aligned,
        eligibility: .suppressed(.sessionPhaseForbids),
        explanation: explanation(
            stage: .unresolved,
            band: .low,
            clauses: [.insufficientEvidence(reason: .noEvidence)]
        ),
        stampKey: EngineStamp.current.withEmbeddingRevision(1).cacheKey
    )

    /// The person turned observation off. The app has looked at nothing and judged nothing.
    static let paused = VerdictSnapshot(
        status: .paused,
        stage: .unresolved,
        band: nil,
        drift: .aligned,
        eligibility: .suppressed(.noActivePriority),
        explanation: explanation(
            stage: .unresolved,
            band: .low,
            clauses: [.insufficientEvidence(reason: .noEvidence)]
        ),
        stampKey: EngineStamp.current.withEmbeddingRevision(1).cacheKey
    )
}

/// The components the inspector is rendered as.
///
/// Five statuses plus the three states that only a *verdict* can be in — nothing judged yet,
/// drift accumulating inside the grace period, and the same drift once the mandate has been
/// spent — because none of them is a `FocusStatus` of its own and each draws a different
/// sentence in the eligibility row.
///
/// **Both sides of `eligibility(_:)` are drawn here** (focus-lmy). The view's one branch is
/// `suppressionReason == nil`, and until this component list contained a mandated verdict the
/// `else` arm had no baseline among 447 — so the sentence it draws could say anything at all
/// and the snapshot lane would stay green.
enum VerdictComponent: String, CaseIterable, Sendable {
    case verdictNothingJudged
    case verdictRelevant
    case verdictUncertainNoNegativeBasis
    case verdictUnrelatedInGrace
    case verdictUnrelatedMandated
    case verdictUnrelatedInCooldown
    case verdictOnBreak
    case verdictPaused

    var width: CGFloat? { 520 }

    var verdict: VerdictSnapshot? {
        switch self {
        case .verdictNothingJudged: nil
        case .verdictRelevant: VerdictFixture.relevant
        case .verdictUncertainNoNegativeBasis: VerdictFixture.uncertainNoNegativeBasis
        case .verdictUnrelatedInGrace: VerdictFixture.unrelatedInGrace
        case .verdictUnrelatedMandated: VerdictFixture.unrelatedMandated
        case .verdictUnrelatedInCooldown: VerdictFixture.unrelatedInCooldown
        case .verdictOnBreak: VerdictFixture.onBreak
        case .verdictPaused: VerdictFixture.paused
        }
    }

    @MainActor
    var view: AnyView {
        AnyView(VerdictInspectorView(verdict: verdict))
    }
}

/// The appearance variants the inspector commits baselines for.
///
/// Light and dark, as R-71 asks for. The five-variant sweep is exercised in full by the
/// surfaces this one sits beside — the capability matrix immediately above it in the same pane
/// — and every token it draws comes from the same `DesignTokens` those already cover.
enum VerdictAppearance {
    static let baselineVariants = ["light", "dark"]
}

/// **The verdict a person can read, drawn.**
///
/// These baselines are what "restrained" means as a picture: no title, no URL, no path, no
/// number from the similarity signal — the clause list and nothing else. Restraint is about
/// what the pane may *show*, and it never meant that the app stays quiet: since e05 the same
/// eligibility drawn here is the one the ladder raises a rung on, and
/// `verdictUnrelatedMandated` is that frame.
@Suite("Verdict inspector snapshots", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct VerdictInspectorSnapshotTests {
    @Test(
        "every verdict matches its baseline in light and dark",
        arguments: VerdictComponent.allCases, VerdictAppearance.baselineVariants
    )
    func componentMatchesBaseline(component: VerdictComponent, variant: String) throws {
        for size in SnapshotTypeSize.allCases {
            try SnapshotHarness.assertSnapshot(
                component.view,
                component: component.rawValue,
                variant: variant,
                textScale: size.textScale,
                width: component.width
            )
        }
    }

    @Test("light and dark are different pictures", arguments: VerdictComponent.allCases)
    func lightAndDarkDiffer(component: VerdictComponent) throws {
        let light = try render(component, variant: "light")
        let dark = try render(component, variant: "dark")
        #expect(PNGCompare.areDistinct(light.pixels, dark.pixels))
    }

    // MARK: - What the inspector may say

    /// **No raw evidence can reach this surface, and it is unrepresentable rather than
    /// forbidden.**
    ///
    /// The hostile corpus e03 established for `NormalisedDetail` is re-run here against the
    /// values this view can actually draw: a window title, a full URL with a query string and
    /// credentials, a document name and an absolute path, in five languages. Not one of them is
    /// a `NormalisedToken`, so not one of them can become an `ExplanationClause` payload — the
    /// factory returns `nil` and there is no other way in (R-57, R-62).
    ///
    /// **Every entry carries a separator, and that is the honest statement of what this type
    /// guarantees.** Measured while writing this suite: `四半期の提案書を書く` — a whole Japanese
    /// sentence — *is* well-formed by `NormalisedToken`'s rule, because Japanese has no word
    /// separators and every character in it is a letter. That is not a hole in the guard; it is
    /// the boundary of what a guard on *shape* can know. The producer is what draws word
    /// boundaries in a script that does not write them, and the producer is `TokenNormalizer`,
    /// which is the only thing in the programme that can see a language, a lexical class and a
    /// stop list. This type's job is to make a *separator-bearing* string unrepresentable, and
    /// that is what is asserted here — with the CJK entry written the way real captured content
    /// arrives, with the em dash and the company name that a window title actually carries.
    @Test("no window title, URL, document name or path can become an explanation payload")
    func hostileCorpusIsUnrepresentable() {
        let hostile = [
            "Q3 Proposal — Acme.docx",
            "https://user:hunter2@mail.example.com/inbox?user=dana&token=secret#42",
            "/Users/dana/Documents/Payslip March.pdf",
            "Rédiger la proposition trimestrielle",
            "四半期の提案書 — 株式会社アクメ",
            "Quartalsangebot schreiben, streng vertraulich",
            "propuesta del tercer trimestre",
            "Дневник — личное"
        ]
        for candidate in hostile {
            #expect(
                NormalisedToken.normalised(candidate) == nil,
                "\(candidate) became a token the inspector could draw"
            )
        }
    }

    /// Every clause the vocabulary knows draws a row, and every row has words.
    ///
    /// Totality rather than a sample: a clause the engine can emit and the surface cannot draw
    /// is a reason a person would never be given, which is the failure a typed clause list
    /// exists to prevent.
    @Test(
        "every explanation clause kind has copy of its own",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func everyClauseKindIsNamed() {
        let sentences = ExplanationClauseKind.allCases.map {
            String(localized: $0.copyResource)
        }
        for (kind, sentence) in zip(ExplanationClauseKind.allCases, sentences) {
            #expect(!sentence.isEmpty)
            #expect(sentence != kind.copyKey, "\(kind.rawValue) resolved to its own key")
        }
        #expect(Set(sentences).count == sentences.count, "two clauses read the same")
    }

    /// Every suppression reason can be said out loud, so the pane can always answer *why it
    /// stayed silent* rather than only *that it did*.
    @Test(
        "every suppression reason has copy of its own",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func everySuppressionReasonIsNamed() {
        let sentences = SuppressionReason.allCases.map { String(localized: $0.copyResource) }
        for (reason, sentence) in zip(SuppressionReason.allCases, sentences) {
            #expect(!sentence.isEmpty)
            #expect(sentence != reason.copyKey, "\(reason.rawValue) resolved to its own key")
        }
        #expect(Set(sentences).count == sentences.count, "two suppression reasons read the same")
    }

    /// **The similarity signal never surfaces a number.**
    ///
    /// P-113 measured that the related and unrelated classes overlap and that one pair inverts
    /// outright, so a distance shown to a person would not mean what they would take it to
    /// mean. `similarityCorroborated` carries none, and this asserts the row drawn from it
    /// carries none either.
    @Test("the similarity clause draws no number")
    func similarityDrawsNoNumber() {
        #expect(ExplanationClauseRow.evidence(of: .similarityCorroborated) == nil)
        #expect(ExplanationClauseRow.evidence(of: .noNegativeBasis) == nil)
        #expect(
            ExplanationClauseRow.evidence(of: .insufficientEvidence(reason: .noNegativeBasis))
                == nil
        )
    }

    /// A clause's payload is the person's own material and is drawn verbatim.
    @Test("a clause's payload is drawn from its own tokens")
    func payloadComesFromTheClause() {
        let drawn = ExplanationClauseRow.evidence(
            of: .tokenOverlap(tokens: [
                VerdictFixture.token("acme"),
                VerdictFixture.token("proposal")
            ])
        )
        #expect(drawn?.contains("acme") == true)
        #expect(drawn?.contains("proposal") == true)
    }

    /// **`uncertain` carries no band.**
    ///
    /// Declining to decide has no evidence to band, and drawing `low` there would imply a weak
    /// *decision* rather than the absence of one. The engine already refuses to produce one;
    /// this is the surface half of the same statement.
    @Test("an uncertain verdict draws no evidence band")
    func uncertainDrawsNoBand() {
        #expect(VerdictFixture.uncertainNoNegativeBasis.band == nil)
        #expect(VerdictFixture.onBreak.band == nil)
        #expect(VerdictFixture.paused.band == nil)
        #expect(VerdictFixture.relevant.band != nil)
    }

    /// **Every fixture answers the question the view actually asks, and both answers occur.**
    ///
    /// This test used to read `#expect(!verdict.isMandated)` for every component, with the
    /// comment *"nothing in this build is mandated on a surface"*. It was true of e04 and it
    /// became, at e05, a test that **forbade the failing branch from ever being pictured** —
    /// the one branch of `eligibility(_:)` that had no baseline, drawing the one sentence that
    /// was wrong. A proof that cannot fail is counted as coverage, which is worse than no proof.
    ///
    /// So the shape is inverted. `InterventionEligibility` has exactly two cases and the view
    /// switches on exactly that, so what is asserted is the biconditional — a verdict names its
    /// reason for silence or it carries a mandate, never both and never neither — plus the
    /// partition being *inhabited on both sides*. The last two expectations are what make this
    /// unsatisfiable by a fixture set that has quietly drifted back to all-suppressed.
    @Test("every drawn verdict either names its silence or carries a mandate")
    func everyFixtureAnswersTheEligibilityQuestion() {
        var mandated: [String] = []
        var suppressed: [String] = []
        for component in VerdictComponent.allCases {
            guard let verdict = component.verdict else { continue }
            let reason = verdict.eligibility.suppressionReason
            #expect(
                verdict.isMandated == (reason == nil),
                "\(component.rawValue) is neither mandated nor suppressed with a reason"
            )
            if verdict.isMandated {
                mandated.append(component.rawValue)
            } else {
                suppressed.append(component.rawValue)
            }
        }
        #expect(!mandated.isEmpty, "no fixture is mandated: the else branch has no picture")
        #expect(!suppressed.isEmpty, "no fixture is suppressed: the silence row has no picture")
    }

    /// The fixture named `unrelatedMandated` **is** mandated.
    ///
    /// Held as a statement of its own, and not folded into the partition test above, because
    /// this is the exact defect: the name said mandated, the value said
    /// `.suppressed(.withinMandateCooldown)`, and for three rounds every proof in this file
    /// agreed with the value while every reader believed the name.
    @Test("the fixture named mandated is mandated, and the one named cooldown is not")
    func namedFixturesAreWhatTheirNamesSay() {
        #expect(VerdictFixture.unrelatedMandated.isMandated)
        #expect(VerdictFixture.unrelatedMandated.eligibility.mandate?.isMixed == false)
        #expect(!VerdictFixture.unrelatedInCooldown.isMandated)
        #expect(
            VerdictFixture.unrelatedInCooldown.eligibility.suppressionReason
                == .withinMandateCooldown
        )
    }

    /// **The mandated branch draws a sentence, and it is not the suppressed one.**
    ///
    /// The pane has one `if`, and its `else` arm is reached on exactly `.mandated`. Nothing
    /// asserted what that arm said, so `settings.verdict.mandated` shipped reading *"Focus
    /// would speak up now. Nothing in this version can, so it does not."* while the ladder it
    /// denies was raising a rung off the same eligibility.
    ///
    /// Asserted as a property rather than against the sentence's text: a copy edit is somebody's
    /// job to make, and a test that pins the words would fail on one. What may not change is
    /// that the sentence exists, resolves, and is nobody else's.
    @Test(
        "the mandated sentence is real copy, distinct from every reason for silence",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func theMandatedBranchHasCopyOfItsOwn() {
        let mandated = String(localized: ShellStrings.resource(.verdictMandated))
        #expect(!mandated.isEmpty)
        #expect(mandated != ShellStringKey.verdictMandated.rawValue, "the key resolved to itself")
        let silences = SuppressionReason.allCases.map { String(localized: $0.copyResource) }
        #expect(
            !silences.contains(mandated),
            "the mandated branch draws a reason for silence"
        )
    }

    /// The rung a verdict names is one `CascadePrecedence` knows, and it is drawn from the
    /// ladder rather than from a list in the view (R-54).
    @Test("every drawn verdict names a rung the ladder declares")
    func everyRungComesFromTheLadder() {
        for component in VerdictComponent.allCases {
            guard let verdict = component.verdict else { continue }
            let rung = try? #require(verdict.rung)
            #expect(rung?.stage == verdict.stage)
            #expect(rung?.isExecutable == true, "a verdict was decided by an unavailable rung")
        }
    }

    // MARK: -

    private func render(_ component: VerdictComponent, variant: String) throws -> Snapshot {
        try SnapshotHarness.render(
            component.view,
            traits: SnapshotHarness.variantTraits(named: variant),
            width: component.width,
            name: "\(component.rawValue).distinctness.\(variant)"
        )
    }
}
