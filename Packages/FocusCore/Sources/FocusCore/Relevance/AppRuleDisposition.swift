import Foundation

/// What the person has decided about one application — the four the registry names (F-130).
///
/// ## The four cost no schema change
///
/// The shipped rule vocabulary has three verdicts, and the fourth disposition is the *absence
/// of a row*. The mapping is total and reversible, so `FocusSchemaV3` is untouched: no
/// `FocusSchemaV4`, no migration stage, no fixture regeneration (R-64, R-72).
///
/// | disposition | stored as | what the engine does |
/// |---|---|---|
/// | `alwaysRelevant` | `relevant` | decisive `relevant` at the rule's authority rung |
/// | `alwaysDistracting` | `unrelated` | decisive `unrelated` at the rule's authority rung |
/// | `askEachTime` | `uncertain` | decisive `uncertain` — which **is** "ask each time", because e05 offers its one-click rule affordance precisely on an uncertain verdict |
/// | `interpretByContext` | **no row at all** | the cascade falls through to the heuristic, which is exactly what "interpret by context" means |
///
/// The verdict type is `PriorityRuleVerdict` rather than `FocusRules.RuleVerdict` because
/// `FocusCore` may import no sibling package (the R-14 matrix). `PriorityRuleVerdict` is the
/// mirror this package already ships for that reason, its raw values are `RuleVerdict`'s, and
/// `FocusRulesTests` asserts the two vocabularies are the same set of strings.
public enum AppRuleDisposition: String, Sendable, CaseIterable, Codable, Hashable, Identifiable {
    case alwaysRelevant
    case alwaysDistracting
    case askEachTime
    case interpretByContext

    public var id: String { rawValue }

    /// The stored judgement this disposition is, or `nil` for "there is no row".
    public var ruleVerdict: PriorityRuleVerdict? {
        switch self {
        case .alwaysRelevant: .relevant
        case .alwaysDistracting: .unrelated
        case .askEachTime: .uncertain
        case .interpretByContext: nil
        }
    }

    /// The disposition a stored judgement — or its absence — means.
    ///
    /// Total in both directions: `disposition(of:) ∘ ruleVerdict` is the identity on
    /// `allCases`, asserted by `RelevanceSeedTests`, so no disposition can be lost on the way
    /// to the store and none can be invented on the way back.
    public init(ruleVerdict: PriorityRuleVerdict?) {
        switch ruleVerdict {
        case .relevant: self = .alwaysRelevant
        case .unrelated: self = .alwaysDistracting
        case .uncertain: self = .askEachTime
        case nil: self = .interpretByContext
        }
    }

    /// Whether this disposition decides the cascade by itself.
    ///
    /// `askEachTime` **does** decide — it decides to say nothing, which is a decision and
    /// terminates the cascade. Only `interpretByContext` falls through.
    public var isDecisive: Bool { self != .interpretByContext }

    /// The rung a *bundled* default of this disposition answers at (R-54).
    ///
    /// A decisive seed sits above the heuristic, or F-171's iPhone Mirroring row would be
    /// argued out of existence by a token coincidence. An `askEachTime` seed sits **below** it,
    /// or a browser with a genuinely relevant origin would resolve to `uncertain` for ever.
    /// That is the whole reason the ladder has two seed rungs rather than one.
    public var seedStage: CascadeStage? {
        switch self {
        case .alwaysRelevant, .alwaysDistracting: .seedRule
        case .askEachTime: .seedFallback
        case .interpretByContext: nil
        }
    }

    /// The String Catalog key for the picker row's label.
    public var labelKey: String {
        switch self {
        case .alwaysRelevant: "rule.disposition.alwaysRelevant"
        case .alwaysDistracting: "rule.disposition.alwaysDistracting"
        case .askEachTime: "rule.disposition.askEachTime"
        case .interpretByContext: "rule.disposition.interpretByContext"
        }
    }

    public var labelResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(labelKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    /// The SF Symbol the picker draws. Distinct silhouettes, for the same reason every other
    /// token set in this package has them.
    public var symbolName: String {
        switch self {
        case .alwaysRelevant: "checkmark.circle"
        case .alwaysDistracting: "minus.circle"
        case .askEachTime: "questionmark.circle"
        case .interpretByContext: "wand.and.sparkles"
        }
    }
}
