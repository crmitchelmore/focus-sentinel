import FocusCore
import Foundation

/// One activation, normalised — everything a rung is allowed to look at.
///
/// Built once per classification and handed to every rung, so no rung can normalise the same
/// string twice or normalise it differently. `origin` and `titleTokens` are **plumbed and
/// exercised by the golden corpus, and empty in every shipping code path in e04** (F-03 is
/// baseline-only); e07 turns them on by supplying a capability probe and a reader, and nothing
/// in this type changes when it does. `selectedItem` is the exception (issue #24): an
/// already-normalised label read through Accessibility, opt-in, and matched only by equality.
///
/// The two kinds of token are kept apart here as well as at the normaliser (R-57): `identifier`
/// and `originHost` may only ever be compared for equality, while `title` is prose and is the
/// only side the similarity signal can be handed.
public struct ClassificationEvidence: Sendable, Equatable {
    public let bundleIdentifier: String?
    public let origin: String?
    /// Tokens decomposed from the bundle identifier. **Never reach a similarity function.**
    public let identifier: IdentifierTokenSet
    /// Tokens decomposed from the origin's host. Never reach a similarity function either.
    public let originHost: IdentifierTokenSet
    /// The window or tab title, as prose. Empty in every shipping path in this epic.
    public let title: ProseTokenSet
    /// How long this subject has held, from the monotonic clock.
    public let dwell: Duration
    /// The item selected inside a mixed-use application, already reduced to a label (issue #24).
    /// Matched by item rules only, and never handed to a similarity function: it is a name the
    /// person chose, compared for equality like an identifier.
    public let selectedItem: SelectedItem?

    public init(
        bundleIdentifier: String?,
        origin: String?,
        identifier: IdentifierTokenSet,
        originHost: IdentifierTokenSet,
        title: ProseTokenSet,
        dwell: Duration,
        selectedItem: SelectedItem? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.origin = origin
        self.identifier = identifier
        self.originHost = originHost
        self.title = title
        self.dwell = dwell
        self.selectedItem = selectedItem
    }

    /// Normalise an input once, for every rung.
    public static func make(
        input: ClassificationInput,
        dwell: Duration,
        normalizer: TokenNormalizer
    ) -> ClassificationEvidence {
        ClassificationEvidence(
            bundleIdentifier: input.bundleIdentifier,
            origin: input.origin,
            identifier: input.bundleIdentifier.map(normalizer.tokens(fromIdentifier:)) ?? .empty,
            originHost: input.origin.map(normalizer.tokens(fromOrigin:)) ?? .empty,
            title: input.titleTokens.isEmpty
                ? .empty
                : normalizer.tokens(fromProse: input.titleTokens.joined(separator: " ")),
            dwell: dwell,
            selectedItem: input.selectedItem
        )
    }

    /// What a rule, a drift state and a mandate call this activation.
    ///
    /// The bundle identifier where there is one, else the normalised origin. `nil` when there
    /// is neither — six of ninety-two processes on this Mac had no bundle identifier (e03's
    /// P-83), and there is nothing to write a rule *about* one of those.
    public var subject: String? { bundleIdentifier ?? origin }

    /// Every token this activation produced, of both kinds, for equality comparison only.
    public var comparableTokens: [NormalisedToken] {
        identifier.tokens + originHost.tokens + title.tokens
    }

    /// True when nothing at all was observed — a private-browsing window with no origin and no
    /// title, or an activation e03's sensitivity gate suppressed before the engine saw it.
    public var isEmpty: Bool {
        bundleIdentifier == nil && origin == nil && title.tokens.isEmpty
    }
}

/// What one rung concluded, before the cascade decides whether to stop.
///
/// `nil` from a rung means *"I have nothing to say"*, which is different from `uncertain`:
/// silence falls through to the next rung, `uncertain` **terminates** the cascade. That
/// distinction is the whole of R-64's `askEachTime` ruling — "ask each time" is a decision,
/// and it decides to say nothing.
public struct RungAnswer: Sendable, Equatable {
    public let verdict: Verdict
    public let source: VerdictSource
    public let band: EvidenceBand
    public let clauses: [ExplanationClause]
    public let uncertaintyReason: UncertaintyReason?
    /// Whether this rung decided, or ran out of instrument and named its reviewer (e06, R-102).
    ///
    /// **Defaulted, so every existing construction site is unchanged.** Two answers in
    /// `HeuristicClassifier` pass `.reviewable(by: .onDeviceModel)`; everything else in this
    /// repository still reads exactly as it did.
    public let finality: RungFinality

    public init(
        verdict: Verdict,
        source: VerdictSource,
        band: EvidenceBand,
        clauses: [ExplanationClause],
        uncertaintyReason: UncertaintyReason? = nil,
        finality: RungFinality = .decided
    ) {
        self.verdict = verdict
        self.source = source
        self.band = band
        self.clauses = clauses
        self.uncertaintyReason = uncertaintyReason
        self.finality = finality
    }
}

/// The heuristic rung, as a seam.
///
/// Declared here rather than in the heuristic's own file so that `RuleCascade` can be written,
/// read and tested without one — and so that e06's model rung, when it arrives, plugs into a
/// shape that already exists rather than into one invented for it.
public protocol HeuristicRung: Sendable {
    func judge(evidence: ClassificationEvidence, snapshot: RuleSnapshot) -> RungAnswer?
}

/// Which rung answered, what it said, and how far down the ladder the engine had to go.
public struct CascadeResolution: Sendable, Equatable {
    public let stage: CascadeStage
    public let verdict: Verdict
    public let source: VerdictSource
    public let band: EvidenceBand
    public let clauses: [ExplanationClause]
    public let uncertaintyReason: UncertaintyReason?
    /// **Executable** rungs consulted before a decision, `1…8` (R-54).
    ///
    /// Never `0`, because `unresolved` is itself a rung and always answers; never `9`, because
    /// `onDeviceModel` is not in the sequence this cascade walks.
    public let consultedDepth: Int

    public var outcome: ClassificationOutcome {
        ClassificationOutcome(
            verdict: verdict,
            source: source,
            confidence: 0,
            band: band
        )
    }
}

/// **The ladder, walked.**
///
/// `evaluate` iterates `CascadePrecedence.executableRungs` and stops at the first rung with
/// something to say. There is **no `switch` on rung order** anywhere: a rung the ladder does
/// not contain cannot be consulted, and a rung the ladder marks non-executable is *not in the
/// sequence being walked* rather than skipped by a special case. e06 flips one flag and
/// supplies an implementation; it neither re-ranks the ladder nor renumbers anything (R-54).
///
/// ## The two axes
///
/// *Authority* — who said it — is the outer axis and is the rung itself. *Specificity* — how
/// narrowly the matched subject identifies the thing — is the inner axis, applied **within**
/// one authority: a `docs.google.com` rule beats a `com.apple.Safari` rule at the same
/// authority, because the person who wrote the narrower rule meant it as the exception.
///
/// ## Conflict is `uncertain`, never a winner
///
/// Two matches at the *same* authority **and** the same subject kind that disagree resolve to
/// `uncertain`, source `.userRule`, with both subjects named. It does **not** resolve by
/// recency and it does **not** resolve to `unrelated`. A nudger that fires on contradictory
/// evidence is the failure this whole epic exists to prevent.
public struct RuleCascade: Sendable {
    private let heuristic: (any HeuristicRung)?
    /// e06's rung, or `nil`. With `nil` the ladder is `.deterministic` and every byte of this
    /// type's behaviour is what e05 shipped.
    private let model: (any ModelRung)?
    private let ladder: CascadeLadder
    private let normalizer: TokenNormalizer

    public init(
        heuristic: (any HeuristicRung)? = nil,
        model: (any ModelRung)? = nil,
        ladder: CascadeLadder = .deterministic,
        normalizer: TokenNormalizer = TokenNormalizer()
    ) {
        self.heuristic = heuristic
        self.model = model
        self.ladder = ladder
        self.normalizer = normalizer
    }

    /// The composed ladder this cascade walks, for the report and the self-check to read.
    public var composedLadder: CascadeLadder { ladder }

    public func evaluate(
        evidence: ClassificationEvidence,
        snapshot: RuleSnapshot
    ) -> CascadeResolution {
        var depth = 0
        for rung in ladder.executableRungs {
            depth += 1
            guard let answer = answer(at: rung.stage, evidence: evidence, snapshot: snapshot) else {
                continue
            }

            // **The review (R-102), and it is six lines.**
            //
            // A rung that ran out of instrument names exactly ONE reviewer. If this
            // composition can execute that reviewer, it is consulted and nothing else is:
            // a provisional answer can never be overturned by a rung *below* the named one,
            // which is what stops a naive fall-through moving thirty committed corpus
            // expectations to `seedFallback`. If the reviewer has nothing to say, or is not in
            // this ladder at all, the provisional answer stands — and in the deterministic
            // composition the reviewer is never in the ladder, so this branch is inert and the
            // transcript is byte-identical to e05's.
            if let reviewer = answer.finality.reviewer,
               ladder.canExecute(reviewer),
               let reviewed = self.answer(at: reviewer, evidence: evidence, snapshot: snapshot) {
                return CascadeResolution(
                    stage: reviewer,
                    verdict: reviewed.verdict,
                    source: reviewed.source,
                    band: reviewed.band,
                    clauses: reviewed.clauses,
                    uncertaintyReason: reviewed.uncertaintyReason,
                    consultedDepth: depth + 1
                )
            }

            return CascadeResolution(
                stage: rung.stage,
                verdict: answer.verdict,
                source: answer.source,
                band: answer.band,
                clauses: answer.clauses,
                uncertaintyReason: answer.uncertaintyReason,
                consultedDepth: depth
            )
        }

        // Unreachable while `unresolved` is executable and always answers, which
        // `RuleCascadeTests` asserts directly. Kept as the honest answer rather than as a
        // `fatalError`: an engine that crashed rather than declining would be the one failure
        // mode worse than a false nudge.
        return CascadeResolution(
            stage: .unresolved,
            verdict: .uncertain,
            source: .undecided,
            band: .low,
            clauses: [.insufficientEvidence(reason: .noEvidence)],
            uncertaintyReason: .noEvidence,
            consultedDepth: depth
        )
    }

    /// One rung's answer. Exhaustive over `CascadeStage`, so a tenth stage is a compile error
    /// here rather than a rung that silently never fires.
    func answer(
        at stage: CascadeStage,
        evidence: ClassificationEvidence,
        snapshot: RuleSnapshot
    ) -> RungAnswer? {
        switch stage {
        case .sessionRule: ruleAnswer(at: .session, evidence: evidence, snapshot: snapshot)
        case .taskRule: ruleAnswer(at: .task, evidence: evidence, snapshot: snapshot)
        case .globalRule: ruleAnswer(at: .global, evidence: evidence, snapshot: snapshot)
        case .contextPack: contextAnswer(evidence: evidence, snapshot: snapshot)
        case .seedRule: seedAnswer(evidence: evidence, snapshot: snapshot, decisive: true)
        case .heuristic: heuristic?.judge(evidence: evidence, snapshot: snapshot)
        case .onDeviceModel: modelAnswer(evidence: evidence, snapshot: snapshot)
        case .seedFallback: seedAnswer(evidence: evidence, snapshot: snapshot, decisive: false)
        case .unresolved: unresolvedAnswer(evidence: evidence, snapshot: snapshot)
        }
    }

    // MARK: - Rung 6 · the on-device model

    /// **A cache read, and nothing else.** This is on the classification path (R-103).
    ///
    /// A hit answers at rank 6. A miss enqueues the ask and returns `nil`, which leaves the
    /// deterministic answer standing — exactly the behaviour of a build with no model at all —
    /// and the next judgement of the same subject reads the cache. e03's activation stream and
    /// dwell ticks re-judge the frontmost subject repeatedly, long before the forty-five-second
    /// query dwell elapses, so the answer arrives before the app would have spoken and never
    /// after it already has.
    ///
    /// Reached only through a `RungFinality.reviewable(by: .onDeviceModel)` answer, so the
    /// walk never falls into it: rank 6 has exactly two doors, and `RungFinalityTests`
    /// enumerates them by running the whole corpus rather than by reading this file.
    func modelAnswer(
        evidence: ClassificationEvidence,
        snapshot: RuleSnapshot
    ) -> RungAnswer? {
        guard let model,
              let subject = evidence.subject,
              let subjectToken = NormalisedToken.normalised(subject.lowercased()),
              let priorityID = snapshot.priorityID
        else { return nil }

        let request = ModelRequest(
            cacheKey: snapshot.stamp.verdictCacheKey(
                priorityID: priorityID,
                priorityRevision: snapshot.priorityRevision,
                evidenceKey: "\(Self.osVersionKey)|\(subject)"
            ),
            priorityTokens: snapshot.priorityTokens.tokens,
            subject: subjectToken,
            priorityRevision: snapshot.priorityRevision
        )

        guard let answer = model.cachedAnswer(for: request) else {
            // Returns immediately. Never awaited by a classification (R-117f).
            model.request(request)
            return nil
        }

        switch answer {
        case .relevant(let relevance):
            return RungAnswer(
                verdict: .relevant,
                source: .heuristic,
                // R-109. Corroboration only, the same class as the similarity signal: a
                // `relevant` suppresses regardless of band, so this changes no behaviour — it is
                // what the inspector draws, and drawing `.high` for a guess would be a lie a
                // person could read.
                band: .low,
                clauses: [
                    relevance == .direct
                        ? .modelDirect(subject: subjectToken)
                        : .modelSupporting(subject: subjectToken)
                ]
            )
        case .decline:
            // **Every decline is silence.** There is no `ModelAnswer` case that could reach
            // `unrelated`, so the deterministic `uncertain` stands and the app asks its
            // question — which is what it would have done with no model at all.
            return nil
        }
    }

    /// R-104's fallback. No model identity or revision appears on any public surface (P-152
    /// looked; the version strings exist only in `modelmanagerd`'s logs), so the coarser fact is
    /// used: a point release that ships a new asset moves this string and invalidates every
    /// entry, and one that does not costs a session's worth of re-asking.
    public static let osVersionKey = ProcessInfo.processInfo.operatingSystemVersionString

    // MARK: - Rungs 0–2 · the user's own rules

    func ruleAnswer(
        at authority: RuleAuthority,
        evidence: ClassificationEvidence,
        snapshot: RuleSnapshot
    ) -> RungAnswer? {
        let matched = snapshot.rules(at: authority).filter { matches($0, evidence: evidence) }
        guard !matched.isEmpty else { return nil }

        // The inner axis: narrower wins. Only the narrowest kind that matched is consulted, so
        // a domain rule and an app rule that disagree are not a conflict — they are an
        // exception and the general case, which is what the person meant by writing both.
        guard let narrowest = matched.map(\.subjectKind).min() else { return nil }
        let cell = matched.filter { $0.subjectKind == narrowest }

        let verdicts = Set(cell.map(\.verdict))
        guard verdicts.count == 1, let decided = verdicts.first else {
            // Same authority, same narrowness, disagreeing. Never recency, never `unrelated`.
            return RungAnswer(
                verdict: .uncertain,
                source: .userRule,
                band: .low,
                clauses: [
                    .conflictingRules(subjects: cell.compactMap { subjectToken(for: $0) }),
                    .insufficientEvidence(reason: .conflictingRules)
                ],
                uncertaintyReason: .conflictingRules
            )
        }

        let verdict = Self.verdict(of: decided)
        return RungAnswer(
            verdict: verdict,
            source: .userRule,
            // R-56's band table, first row: a user rule that *decides* bands `.high` — the
            // person said so, and nothing outranks that. A rule that declines to decide bands
            // `.low`, because there is no evidence to band: "ask each time" is a decision about
            // what the app should do, not a strong statement about the application. Either way
            // `decide` returns on the verdict before it reads a band, so the band on an
            // `uncertain` cannot rescue it.
            band: verdict == .uncertain ? .low : .high,
            clauses: cell.compactMap { rule in
                subjectToken(for: rule).map {
                    ExplanationClause.userRule(
                        authority: rule.authority, kind: rule.subjectKind, subject: $0
                    )
                }
            },
            uncertaintyReason: verdict == .uncertain ? .mixedUseApplication : nil
        )
    }

    func matches(_ rule: ScopedRuleValue, evidence: ClassificationEvidence) -> Bool {
        switch rule.subjectKind {
        case .app:
            return rule.subject == evidence.bundleIdentifier
        case .domain:
            return rule.subject == evidence.origin
        case .titleToken:
            // An item rule (issue #24) names one selected item inside one application, and
            // matches that item and nothing else: the same application with another chat open
            // is a different subject.
            if let item = SelectedItem.parse(rule.subject) {
                return evidence.selectedItem.map(item.matches) ?? false
            }
            // A legacy word. Empty in every shipping path (F-03 is baseline-only), and
            // exercised by the corpus so that a reader turns a capability on rather than
            // writing a rung.
            return evidence.title.values.contains(rule.subject.lowercased())
        }
    }

    /// A rule's subject, as something an explanation may carry.
    ///
    /// A bundle identifier and a title token are already tokens. An origin is **not** — it
    /// carries a scheme and a `//`, neither of which `NormalisedToken` will accept — so the
    /// host is taken, which is the part a person recognises the site by anyway. The clause list
    /// is allowed to come back short; `ExplanationBuilder` is what guarantees it is never
    /// empty.
    func subjectToken(for rule: ScopedRuleValue) -> NormalisedToken? {
        switch rule.subjectKind {
        case .titleToken:
            SelectedItem.parse(rule.subject)?.slug
                ?? NormalisedToken.normalised(rule.subject.lowercased())
        case .app: NormalisedToken.normalised(rule.subject.lowercased())
        case .domain: NormalisedToken.normalised(TokenNormalizer.host(of: rule.subject).lowercased())
        }
    }

    static func verdict(of stored: PriorityRuleVerdict) -> Verdict {
        switch stored {
        case .relevant: .relevant
        case .unrelated: .unrelated
        case .uncertain: .uncertain
        }
    }

    // MARK: - Rung 3 · the context pack

    /// An identity the person attached to *this* priority.
    ///
    /// Only `relevant` is reachable from here, at any kind. A context pack says what the work
    /// looks like; it never says what it does not, and reading an absence from it is R-56.1's
    /// job at the rung below.
    func contextAnswer(
        evidence: ClassificationEvidence,
        snapshot: RuleSnapshot
    ) -> RungAnswer? {
        for item in snapshot.contextPack {
            switch item.kind {
            case .app where item.value == evidence.bundleIdentifier,
                 .domain where item.value == evidence.origin:
                // An exact identity the person attached to this priority.
                guard let subject = contextToken(for: item) else { continue }
                return RungAnswer(
                    verdict: .relevant,
                    source: .userRule,
                    band: .high,
                    clauses: [.contextItem(kind: item.kind, subject: subject)]
                )
            case .keyword:
                // A word they chose, matched by lemma. Strong, not exact — so `.medium`.
                let keyword = normalizer.tokens(fromProse: item.value)
                let shared = TokenOverlap.shared(keyword.tokens, evidence.comparableTokens)
                guard !shared.isEmpty, let subject = contextToken(for: item) else { continue }
                return RungAnswer(
                    verdict: .relevant,
                    source: .userRule,
                    band: .medium,
                    clauses: [
                        .contextItem(kind: item.kind, subject: subject),
                        .tokenOverlap(tokens: shared)
                    ]
                )
            default:
                // A `file` item cannot be observed at zero grants — the engine cannot see which
                // file is open, so the item can neither match nor fail to match — and an
                // `unknown` kind is a row a later build wrote that this one will not guess at.
                continue
            }
        }
        return nil
    }

    func contextToken(for item: ContextItemValue) -> NormalisedToken? {
        switch item.kind {
        case .domain: NormalisedToken.normalised(TokenNormalizer.host(of: item.value).lowercased())
        default: NormalisedToken.normalised(item.value.lowercased())
        }
    }

    // MARK: - Rungs 4 and 7 · the bundled defaults

    /// The app's own opinion — one decisive row, and a set of `ask each time` rows.
    ///
    /// Two rungs rather than one, because an `askEachTime` default on a mixed-use application
    /// must **not** out-rank the heuristic — a browser with a genuinely relevant origin would
    /// resolve to `uncertain` for ever — while a decisive default must, or F-171's iPhone
    /// Mirroring row would be argued out of existence by a token coincidence.
    func seedAnswer(
        evidence: ClassificationEvidence,
        snapshot: RuleSnapshot,
        decisive: Bool
    ) -> RungAnswer? {
        guard let bundleIdentifier = evidence.bundleIdentifier,
              let disposition = RelevanceSeed.disposition(for: bundleIdentifier),
              disposition.seedStage == (decisive ? .seedRule : .seedFallback),
              let subject = NormalisedToken.normalised(bundleIdentifier.lowercased())
        else { return nil }

        guard decisive else {
            return RungAnswer(
                verdict: .uncertain,
                source: .heuristic,
                band: .low,
                clauses: [
                    .seedFallbackMixedUse(subject: subject),
                    .insufficientEvidence(reason: .mixedUseApplication)
                ],
                uncertaintyReason: .mixedUseApplication
            )
        }

        guard let stored = disposition.ruleVerdict else { return nil }
        let verdict = Self.verdict(of: stored)

        // **The seed-override guard.** A bundled default is the app's opinion; the person's own
        // words outrank it. A priority that names this application — *"record the iPhone
        // Mirroring demo"* — downgrades a shipped `unrelated` to `uncertain`, so the one
        // opinion this app ships can never accuse somebody of being distracted by the very
        // thing they wrote down. It fires **downward only**: it can never turn a seed
        // `relevant` into `unrelated`, which is why the guard is inside this branch and not
        // outside it (R-64, adversarial family 3).
        if verdict == .unrelated,
           overrides(seed: bundleIdentifier, priorityTokens: snapshot.priorityTokens) {
            return RungAnswer(
                verdict: .uncertain,
                source: .heuristic,
                band: .low,
                clauses: [
                    .seedDefault(disposition: disposition, subject: subject),
                    .insufficientEvidence(reason: .mixedUseApplication)
                ],
                uncertaintyReason: .mixedUseApplication
            )
        }

        return RungAnswer(
            verdict: verdict,
            source: .heuristic,
            // R-56: the app's own opinion, deliberately below the user's. `.medium` is at the
            // intervention floor, so a decisive seed *can* mandate — which is exactly what
            // F-171's row is for — and one click of a user rule outranks it.
            band: .medium,
            clauses: [.seedDefault(disposition: disposition, subject: subject)]
        )
    }

    /// Whether the priority's own words are about the seeded application.
    ///
    /// Compared against both the identifier's tokens and the application's **name**, because
    /// the two are not the same words and the name is the one a person writes down.
    /// `com.apple.ScreenContinuity` decomposes to `apple`, `screen`, `continuity` — none of
    /// which appears in *"record the iPhone Mirroring demo"* — while the application is called
    /// iPhone Mirroring, which is exactly what they wrote.
    func overrides(seed bundleIdentifier: String, priorityTokens: ProseTokenSet) -> Bool {
        guard !priorityTokens.tokens.isEmpty else { return false }
        var seedTokens = normalizer.tokens(fromIdentifier: bundleIdentifier).tokens
        if let name = SeedSubjectNames.names[bundleIdentifier] {
            seedTokens += normalizer.tokens(fromProse: name).tokens
        }
        return !TokenOverlap.shared(priorityTokens.tokens, seedTokens).isEmpty
    }

    // MARK: - Rung 8 · nothing matched

    /// The terminal rung. It **always** answers, which is what makes the consulted depth
    /// `1…8` rather than `0…8`, and what makes "the engine declined" a named route rather than
    /// a fall off the end of a list.
    func unresolvedAnswer(
        evidence: ClassificationEvidence,
        snapshot: RuleSnapshot
    ) -> RungAnswer? {
        let reason: UncertaintyReason =
            evidence.subject == nil ? .noIdentifiableSubject : .noEvidence
        return RungAnswer(
            verdict: .uncertain,
            source: .undecided,
            band: .low,
            clauses: [.insufficientEvidence(reason: reason)],
            uncertaintyReason: reason
        )
    }
}

/// The names people use for the applications this app ships a **decisive** opinion about.
///
/// Part of the e04 lexicon, versioned by `EngineStamp.lexiconVersion` alongside the stop lists,
/// the reverse-DNS head list and the seed table.
///
/// It exists because a reverse-DNS identifier and an application's name are different words.
/// `com.apple.ScreenContinuity` decomposes to `apple`, `screen`, `continuity`; the application
/// on the Dock says **iPhone Mirroring**, and that is what somebody writes in a priority. Without
/// this row the seed-override guard could not fire on the Court's own worked example, and the
/// single opinion this app ships would be able to accuse a person of being distracted by the
/// exact thing they wrote down.
///
/// Only decisive seeds need a row: an `askEachTime` seed already resolves to `uncertain`, so
/// there is nothing for an override to protect against. `RuleCascadeTests` asserts that every
/// decisive seed has one, so a second decisive row cannot ship without its name.
public enum SeedSubjectNames {
    public static let names: [String: String] = [
        // Verified present on this Mac at /System/Applications/iPhone Mirroring.app, whose
        // Info.plist reports CFBundleIdentifier com.apple.ScreenContinuity (P-122).
        "com.apple.ScreenContinuity": "iPhone Mirroring"
    ]
}
