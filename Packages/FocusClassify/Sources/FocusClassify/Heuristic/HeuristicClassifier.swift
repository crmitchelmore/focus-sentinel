import FocusCore
import Foundation

/// Rung 5: overlap first, similarity second, and an accusation only behind the negative basis.
///
/// ## The order, and why each step is where it is
///
/// | # | route | answer |
/// |---|---|---|
/// | 1 | exact token overlap | `relevant`, `.medium` on a strong token and `.low` otherwise |
/// | 2 | the priority is not English | `uncertain(.languageNotSupported)` |
/// | 3 | too few content tokens in the priority | `uncertain(.insufficientPriorityEvidence)` |
/// | 4 | similarity inside the ceiling | `relevant`, `.low` — corroboration only |
/// | 5a | the subject is one the priority named | *decline* — rung 3 already answered |
/// | 5b | the subject carries an `ask each time` seed | *decline* — rung 7 answers |
/// | 6 | **no `app`/`domain` context identity** | `uncertain(.noNegativeBasis)`, **reviewable** |
/// | 7 | drift not yet sustained | `uncertain(.noEvidence)` |
/// | 8 | absence, sustained, behind the basis | `unrelated`, `.medium`, or `.high` past `escalationDwell` |
///
/// Overlap comes first because P-114 measured it as the **precision** instrument: unrelated
/// Jaccard was `0.000` on all eight measured pairs, without exception, against roughly half
/// misses. Similarity comes fourth because P-113 and P-124 both measured it as the **recall**
/// instrument with no clean threshold — real central tendency, overlapping classes — so it may
/// corroborate `relevant` and may never accuse (R-58).
///
/// ## R-56.1 — the negative basis, and the false accusation it exists to prevent
///
/// **Absence of lexical evidence may never, on its own, produce `unrelated`.** The draft this
/// replaces gated the accusation on *"content tokens or ≥ 1 context item"*, and that gate is
/// passed by *"Write the Q3 proposal for Acme"*. Put `com.microsoft.Excel` in front of it:
/// identifier tokens are `microsoft`, `excel`; overlap is empty; similarity may never say
/// `unrelated` and never sees identifier tokens anyway; so the engine reaches absence-plus-dwell,
/// dwells past ninety seconds — which is what *building a budget in Excel is* — and returns
/// `unrelated` at `.medium`, which is exactly the intervention floor, which mandates. **The app
/// accuses a person of slacking off for doing the work.**
///
/// The root error is a category mistake: *no lexical overlap with the priority* and *unrelated
/// to the priority* are different propositions, and the gap between them is the whole set of
/// productive tools whose reverse-DNS name says nothing about the work — Excel, Numbers, Pages,
/// Keynote, Preview, Xcode, Terminal, Figma, and every domain tool anybody has ever installed.
/// A bundle identifier is not evidence of irrelevance.
///
/// So all four conditions must hold, and a failure of any one yields `uncertain` **at every
/// dwell**: the priority carries at least `minimumPriorityContentTokens` content tokens; its
/// context pack carries at least `minimumNegativeBasisItems` item whose kind is in
/// `negativeBasisKinds` — an *identity*, not a keyword and not a file; the observed subject
/// matches none of them; and dwell has passed `sustainedDriftThreshold`.
///
/// What it costs is the nudge on a person who set a priority and named no context. What it buys
/// is that **every `unrelated` this rung ever produces is grounded in something the person
/// themselves typed** — the same principle the seed table already obeys, applied one rung down.
public struct HeuristicClassifier: HeuristicRung {
    private let scorer: SimilarityScorer?

    /// The scorer is optional because the similarity signal is a corroborator and never a
    /// decider: an engine built without one produces strictly fewer `relevant` verdicts and
    /// exactly the same `unrelated` ones.
    public init(scorer: SimilarityScorer? = nil) {
        self.scorer = scorer
    }

    public func judge(
        evidence: ClassificationEvidence,
        snapshot: RuleSnapshot
    ) -> RungAnswer? {
        // Nothing was observed at all — a private-browsing window with no origin and no title,
        // or an activation e03's sensitivity gate suppressed before the engine saw it. **"We
        // did not look" must never become "you are distracted"**, so this rung declines and the
        // terminal one names the absence.
        guard !evidence.isEmpty else { return nil }

        // 1 — overlap, the precision instrument (P-114).
        let shared = TokenOverlap.shared(snapshot.priorityTokens.tokens, evidence.comparableTokens)
        if let band = TokenOverlap.band(for: shared) {
            return RungAnswer(
                verdict: .relevant,
                source: .heuristic,
                band: band,
                clauses: [.tokenOverlap(tokens: shared)]
            )
        }

        // 2 — the language gate, from the priority side (P-111). `NLEmbedding` is `nil` for
        // `fr`, `de`, `ja`, `zh-Hans` and `es` — word and sentence, every one — so for a
        // non-English priority there is no instrument at all, and an engine with no instrument
        // must not proceed to an accusation. It is checked *first* because it is a fact about
        // the input rather than about our tokenisation: `四半期の提案書を書く` yields no content
        // token this normaliser can use either, and reporting that as *"too vague"* would blame
        // the person for writing in their own language.
        //
        // Note what this reads and what it does not. The gate here is the **dominant
        // language**; `languageConfidenceFloor` is not consulted, because that constant gates
        // the *similarity signal* and nothing else (R-58) — and P-124 measured it overlapping
        // the fragment class, so using it here would have declined real English work.
        if let language = snapshot.priorityLanguage, language.tag != Self.englishTag {
            return RungAnswer(
                verdict: .uncertain,
                source: .heuristic,
                band: .low,
                clauses: [
                    .languageNotSupported(BCP47: NormalisedToken.normalised(language.tag)),
                    .insufficientEvidence(reason: .languageNotSupported)
                ],
                uncertaintyReason: .languageNotSupported
            )
        }

        // 3 — R-56.1's first condition. *"stuff"*, *"work"*, *"catch up"* and the empty
        // priority sit below this floor, and so does the absence of a priority altogether.
        guard snapshot.hasJudgeablePriority else {
            return declined(.insufficientPriorityEvidence)
        }

        // 4 — similarity, the recall instrument. Corroboration only, and never a number a
        // person is shown.
        if let scorer,
           scorer.corroboration(
               priorityVector: snapshot.prioritySentence,
               priorityLanguage: snapshot.priorityLanguage,
               evidence: evidence.title
           ).corroborates {
            return RungAnswer(
                verdict: .relevant,
                source: .heuristic,
                band: SimilarityScorer.corroborationBand,
                clauses: [.similarityCorroborated]
            )
        }

        // 5 — **the two declines, hoisted above the negative basis (e06).**
        //
        // These were steps 6 and 5b, *below* the `hasNegativeBasis` guard. The adversarial
        // review of the e06 plan found the ordering by reading this code rather than its
        // comments: a priority with no identity in its context pack, with a browser in front
        // of it, answered `uncertain(.noNegativeBasis)` here and terminated the cascade.
        //
        // That was wrong twice over, and only one of the two is about e06.
        //
        // The half that is not: this app ships an opinion about Safari — *"ask each time"* —
        // and that opinion is a better account of why the engine declined than *"you named no
        // app or site"*. A person reading the inspector was told to go and attach context when
        // the engine would have declined about a browser whatever they attached. The engine
        // already behaved correctly when the priority *had* a basis; the answer differed only
        // in the one case where the person had least to go on.
        //
        // The half that is: `noNegativeBasis` is the answer e06 marks
        // `.reviewable(by: .onDeviceModel)`, and §2.3 declares a mixed-use application
        // non-consultable. Left in the old order, the deferral would have handed the model
        // exactly the subjects it must not judge — a browser, whose identity is known to be
        // uninformative — and nothing else.
        //
        // Swapping steps 5 and 6 wholesale was the other candidate fix and is not what
        // happened: it would move lane-1 uncertainty reasons for cases that *do* have a basis
        // and change thirty-three committed corpus expectations. Hoisting the two **declines**
        // changes the answer for exactly one shape of input and leaves every answering route
        // where it was.

        // 5a — the basis-identity check, from the rung above. The context rung would already
        // have answered `relevant` on a match; asserting it again costs one comparison and
        // makes this rung correct in isolation.
        guard !matchesAnyBasisIdentity(evidence: evidence, snapshot: snapshot) else {
            return nil
        }

        // 5b — a subject this app itself ships an *"ask each time"* opinion about is a subject
        // whose identity is **known to be uninformative**: a browser, a chat client, a media
        // player. That is R-56.1's own principle — an absence is only informative when there is
        // something for it to be an absence of — so the accusation route declines and rung 7
        // answers `uncertain(.mixedUseApplication)`. The *relevant* routes above were reached
        // first, so a browser showing a genuinely on-topic page still resolves.
        if let bundleIdentifier = evidence.bundleIdentifier,
           RelevanceSeed.disposition(for: bundleIdentifier)?.seedStage == .seedFallback {
            return nil
        }

        // 6 — **the negative basis.** The only clause in this epic whose copy carries an *ask*:
        // name one application or site you expect to be looking at, and the engine gains
        // something an absence can be an absence *of*.
        //
        // e06 marks this answer `.reviewable(by: .onDeviceModel)`. It is not a decision; it is
        // the engine saying it lacks the instrument, and one rung below it now has one. The
        // two declines above are what make that marking safe: by the time this line is
        // reached, the subject is not a mixed-use application and not one the person named.
        guard snapshot.hasNegativeBasis else {
            return RungAnswer(
                verdict: .uncertain,
                source: .heuristic,
                band: .low,
                clauses: [.noNegativeBasis, .insufficientEvidence(reason: .noNegativeBasis)],
                uncertaintyReason: .noNegativeBasis
            )
        }

        // 7 — the absence is real but not yet sustained. Time is the evidence, and there has
        // not been enough of it.
        guard evidence.dwell > RelevancePolicy.sustainedDriftThreshold else {
            return declined(.noEvidence)
        }

        // 8 — an absence of something the person named, held past the threshold.
        let seconds = Int(evidence.dwell.components.seconds)
        return RungAnswer(
            verdict: .unrelated,
            source: .heuristic,
            band: evidence.dwell > RelevancePolicy.escalationDwell ? .high : .medium,
            clauses: [.sustainedDwell(seconds: seconds)]
        )
    }

    /// Whether the observed subject is one of the identities the priority named.
    ///
    /// Compared by exact equality, never by prefix and never fuzzily: `com.apple.Safari` and
    /// `com.apple.SafariTechnologyPreview` are different applications, and a match that guessed
    /// between them would be a claim the engine never measured.
    func matchesAnyBasisIdentity(
        evidence: ClassificationEvidence,
        snapshot: RuleSnapshot
    ) -> Bool {
        snapshot.negativeBasisItems.contains { item in
            switch item.kind {
            case .app: item.value == evidence.bundleIdentifier
            case .domain: item.value == evidence.origin
            default: false
            }
        }
    }

    /// The one language this OS has an embedding for (P-111), as `NLLanguage.english`'s raw
    /// value. A string rather than an `NLLanguage` because the reading crossed a package
    /// boundary to get here and `LanguageReading` carries a BCP-47 tag, which is the form an
    /// explanation clause renders anyway.
    static let englishTag = "en"

    /// The shape every declining route takes: `uncertain`, at the band that cannot mandate,
    /// carrying the named reason rather than a shrug.
    func declined(_ reason: UncertaintyReason) -> RungAnswer {
        RungAnswer(
            verdict: .uncertain,
            source: .heuristic,
            band: .low,
            clauses: [.insufficientEvidence(reason: reason)],
            uncertaintyReason: reason
        )
    }
}
