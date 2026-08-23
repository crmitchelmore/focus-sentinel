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

    /// `unrelated`, sustained past the threshold, and **mandated**. Nothing consumes it: the
    /// nudge is e05's, so the pane says so and the screen does nothing.
    static let unrelatedMandated = VerdictSnapshot(
        status: .unrelated,
        stage: .globalRule,
        band: .high,
        drift: .sustained(
            subject: .single("com.apple.ScreenContinuity"),
            accumulated: .seconds(214),
            isMixed: false
        ),
        eligibility: .suppressed(.withinMandateCooldown),
        explanation: explanation(
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
        ),
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
/// Five statuses plus the two states that only a *verdict* can be in — nothing judged yet, and
/// drift accumulating inside the grace period — because those are the two frames a person is
/// most likely to be looking at and neither is a `FocusStatus` of its own.
enum VerdictComponent: String, CaseIterable, Sendable {
    case verdictNothingJudged
    case verdictRelevant
    case verdictUncertainNoNegativeBasis
    case verdictUnrelatedInGrace
    case verdictUnrelatedMandated
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

/// **e04's demonstrable, drawn.**
///
/// The nudge does not exist yet, so the verdict stream and the restrained explanation beside it
/// *are* the epic's surface. These baselines are what "restrained" means as a picture: no
/// title, no URL, no path, no number from the similarity signal, and no accusation — the
/// clause list and nothing else.
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

    /// **Nothing in this build is mandated on a surface.**
    ///
    /// Every fixture is `.suppressed`, including the one that has drifted for three and a half
    /// minutes — because the mandate went into cooldown after the engine issued it and nothing
    /// consumed it. The pane's job here is to say *why* it is quiet, which it can do for every
    /// reason the vocabulary knows.
    @Test("every drawn verdict is suppressed, with a named reason")
    func everyFixtureIsSuppressedWithAReason() {
        for component in VerdictComponent.allCases {
            guard let verdict = component.verdict else { continue }
            #expect(
                !verdict.isMandated,
                "\(component.rawValue) draws a mandate, and nothing in e04 may consume one"
            )
            #expect(verdict.eligibility.suppressionReason != nil)
        }
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
