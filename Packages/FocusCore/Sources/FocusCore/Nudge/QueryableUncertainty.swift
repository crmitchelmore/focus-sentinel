import Foundation

/// The uncertainties a person can actually answer.
///
/// U-1 says the app speaks when it is uncertain. It does **not** say the app may ask a
/// question with no answer, and e04 already named every route to `uncertain` as a typed
/// `UncertaintyReason` — so askability is decided **once**, in one total switch, and a ninth
/// reason cannot be added without deciding whether it is answerable (R-77).
///
/// Three cases, and each is here for a reason that is about the *person*, not about the
/// engine:
///
/// | reason | why it is askable |
/// |---|---|
/// | `noNegativeBasis` | there is a real application in front of the person and the app genuinely does not know. U-1's central case, and 32 of the corpus's 72 uncertain verdicts (P-138) |
/// | `mixedUseApplication` | a browser or a chat client. The answer is coarse at baseline — it is about the whole app — and the copy says so, because a correction writes a rule from the evidence actually available (F-60) |
/// | `languageNotSupported` | the *engine* cannot judge, but the *person* can. The subject is nameable and the answer is durable |
///
/// The five that are **not** here are the substance of the ruling; see
/// `UncertaintyReason.queryable` below, where each is refused by name.
public enum QueryableUncertainty: String, Sendable, CaseIterable, Codable, Hashable {
    /// The priority names no application or site the engine could find this one absent from.
    case noNegativeBasis
    /// A bundled `askEachTime` default: a browser, a chat client, a media player.
    case mixedUseApplication
    /// Neither side of the comparison is in a language this OS can embed.
    case languageNotSupported

    /// The `UncertaintyReason` this askable case came from.
    ///
    /// Written out rather than derived from the raw value, so that the two vocabularies are
    /// joined by a switch the compiler checks rather than by a string that happens to match.
    /// `QueryableUncertaintyTests` asserts the round trip in both directions.
    public var reason: UncertaintyReason {
        switch self {
        case .noNegativeBasis: .noNegativeBasis
        case .mixedUseApplication: .mixedUseApplication
        case .languageNotSupported: .languageNotSupported
        }
    }

    /// The String Catalog key for the line a query draws under its question, explaining why
    /// the app is asking. `check-strings.sh` asserts the bijection with `nudge.query.reason.*`
    /// (R-96l).
    public var copyKey: String {
        switch self {
        case .noNegativeBasis: "nudge.query.reason.noNegativeBasis"
        case .mixedUseApplication: "nudge.query.reason.mixedUseApplication"
        case .languageNotSupported: "nudge.query.reason.languageNotSupported"
        }
    }

    public var copyResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(copyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}

extension UncertaintyReason {
    /// Whether this reason produces a question, and which one.
    ///
    /// **Total by construction**: the switch has no `default`, so adding a ninth
    /// `UncertaintyReason` without deciding its askability is a compile error rather than a
    /// silent `nil`. That is the whole mechanism — a reason that arrived without a decision
    /// would default to silence, which is the pre-U-1 posture creeping back in one case at a
    /// time.
    ///
    /// The five refusals, each by name, because each is a different kind of harm:
    ///
    /// * **`noIdentifiableSubject`** — there is no subject. A rule cannot be written about a
    ///   process with no bundle identifier (e03's P-83 measured six in ninety-two), so the
    ///   question has no answer to store.
    /// * **`noEvidence`** — the app *deliberately did not look*: a sensitive application, a
    ///   private window, an activation e03's gate suppressed before the engine saw it. Asking
    ///   "is this part of your task?" about a password manager tells the person we noticed.
    ///   **"We did not look" must never become "tell us what you were doing."** This is the
    ///   same inversion `UncertaintyReason.noEvidence`'s own doc comment forbids, at the other
    ///   end of the pipeline, and `nudge.queryOnUnaskableCount == 0` gates it at zero.
    /// * **`insufficientPriorityEvidence`** — the priority is "stuff". The honest affordance
    ///   is e02's refinement strip on the capture field, not a per-app question that would
    ///   write a rule under a sentence the person is about to rewrite.
    /// * **`conflictingRules`** — two rules the person already wrote disagree. The affordance
    ///   is *resolve the conflict*, in the Rules pane, with both rules shown. Asking again
    ///   would produce a third rule on top of a contradiction.
    /// * **`staleSnapshot`** — the priority revision moved under the classification. That is
    ///   our bug, not their question.
    ///
    /// Twenty-five of seventy-two uncertain verdicts therefore stay silent (34.7 %, P-138),
    /// and that share carries a **floor** in the release gate — `unaskableUncertaintyShare ≥
    /// 0.34` — because the cheapest way to make the app look less chatty would be to quietly
    /// move one of the five above into `QueryableUncertainty`.
    public var queryable: QueryableUncertainty? {
        switch self {
        case .noNegativeBasis: .noNegativeBasis
        case .mixedUseApplication: .mixedUseApplication
        case .languageNotSupported: .languageNotSupported
        case .noIdentifiableSubject: nil
        case .noEvidence: nil
        case .insufficientPriorityEvidence: nil
        case .conflictingRules: nil
        case .staleSnapshot: nil
        }
    }

    /// Whether a question may be formed from this reason at all.
    public var isQueryable: Bool { queryable != nil }
}
