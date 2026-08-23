import Foundation

/// One rung of the relevance cascade: **who** got to answer.
///
/// Nine stages, integer ranks `0…8`, no gaps and no fractions. The rank is not written down
/// anywhere — it is the case's position in `allCases`, so "the ranks are `0…n-1`, each exactly
/// once" is a property of the declaration rather than of somebody's arithmetic, and a
/// fractional rank is unrepresentable rather than merely discouraged (D-e04-5).
///
/// | rank | stage | decisive? | executable in this build? |
/// |---|---|---|---|
/// | 0 | `sessionRule` | yes | yes |
/// | 1 | `taskRule` | yes | yes |
/// | 2 | `globalRule` | yes | yes |
/// | 3 | `contextPack` | yes | yes |
/// | 4 | `seedRule` | yes | yes |
/// | 5 | `heuristic` | yes | yes |
/// | 6 | `onDeviceModel` | yes, from e06 | **no** |
/// | 7 | `seedFallback` | `uncertain` only | yes |
/// | 8 | `unresolved` | `uncertain` only | yes |
///
/// `seedRule` and `seedFallback` are two rungs rather than one because a bundled
/// `askEachTime` default on a mixed-use application must **not** out-rank the heuristic — or a
/// browser with a genuinely relevant origin would resolve to `uncertain` for ever — while a
/// bundled *decisive* default must, or F-171's iPhone Mirroring row would be argued out of
/// existence by a token coincidence. Splitting the rung keeps one total order and needs no
/// special case anywhere.
public enum CascadeStage: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
    /// A rule that lives until this focus session ends (`RuleAuthority.session`).
    case sessionRule
    /// A rule the user scoped to this priority (`FocusSchemaV3.RelevanceRule.task != nil`).
    case taskRule
    /// A rule the user scoped to no priority (`task == nil`).
    case globalRule
    /// An item in *this* priority's context pack (F-09).
    case contextPack
    /// A bundled **decisive** default — `alwaysRelevant` / `alwaysDistracting` (R-64).
    case seedRule
    /// Token normalisation, overlap, similarity and dwell.
    case heuristic
    /// e06's on-device model. **Declared here, consulted nowhere in this build.**
    case onDeviceModel
    /// A bundled `askEachTime` default: a mixed-use application. `uncertain` only.
    case seedFallback
    /// Nothing matched. `uncertain` only.
    case unresolved

    /// Where this rung sits in the ladder. Lower binds harder.
    ///
    /// Derived from `allCases` rather than declared, which is what makes the strict total
    /// order over `0…8` structural. It is also why no numeric literal appears in this file
    /// (R-70f): a precedence rank has no business living in `RelevancePolicy.swift`, and the
    /// only way to have both properties is to not write the numbers at all.
    public var rank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    public static func < (lhs: CascadeStage, rhs: CascadeStage) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// One rung, with everything the four readers of the ladder need.
///
/// The four readers are the runtime (`RuleCascade` iterates `executableRungs`), the
/// explanation builder (switches exhaustively over `CascadeStage`), the Settings precedence
/// pane (renders `CascadePrecedence.rungs` in rank order) and the String Catalog (a lint
/// asserts a bijection with the `cascade.rung.*` keys). Three of the four are mechanically
/// checked, and there is no fifth place a rung order can be written down (R-54).
public struct CascadeRung: Sendable, Equatable, Hashable, Identifiable, Codable {
    public let stage: CascadeStage
    /// The stage's position in the ladder, `0…8`.
    public let rank: Int
    /// Whether **this build** can consult the rung.
    ///
    /// A stored property, not a `switch` somewhere: `RuleCascade` iterates
    /// `executableRungs`, so an unavailable rung is *not in the sequence being walked* rather
    /// than skipped by a special case. e06 flips this one flag and supplies an
    /// implementation; it neither re-ranks the ladder nor renumbers anything.
    public let isExecutable: Bool
    /// The String Catalog key for the phrase an explanation uses when this rung decided.
    public let explanationKey: String
    /// The String Catalog key for the precedence pane's row label.
    public let settingsCopyKey: String

    public var id: CascadeStage { stage }

    public init(
        stage: CascadeStage,
        isExecutable: Bool,
        explanationKey: String,
        settingsCopyKey: String
    ) {
        self.stage = stage
        self.rank = stage.rank
        self.isExecutable = isExecutable
        self.explanationKey = explanationKey
        self.settingsCopyKey = settingsCopyKey
    }

    /// The row label, localised against `FocusCore`'s own catalog.
    ///
    /// Exposed as a resource rather than as a key so that `FocusUI` renders the ladder without
    /// writing a single string of its own — the same technique `FocusStatus.shortLabelResource`
    /// already uses, and the reason the precedence pane can hold no literal list.
    public var settingsCopyResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(settingsCopyKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    /// The explanation phrase, localised against `FocusCore`'s own catalog.
    public var explanationResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(explanationKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}

/// **The** ordered list of cascade rungs. There is no other one in this repository.
///
/// The roadmap names the risk precisely: *"Rule precedence is a product contract and must not
/// drift between Settings copy, the explanation builder and the runtime."* A comment saying so
/// is not a mechanism; this list, read by all four, is (R-54).
///
/// Three different lengths, named separately because conflating them is how a depth metric
/// goes wrong:
///
/// * **declared** — `CascadeStage.allCases.count` = 9. Every rung the vocabulary knows.
/// * **executable** — `executableRungs.count` = 8. The rungs this build can consult.
/// * **consulted depth** — `1…8` per classification. Never 0, because `unresolved` is itself
///   a rung, and never 9, because the model is not in the sequence walked.
public enum CascadePrecedence {
    /// Every rung, in rank order, including the one e06 fills.
    ///
    /// `onDeviceModel` is listed — and drawn by the precedence pane in a secondary style —
    /// because the *placement* of the model below every user rule and below the deterministic
    /// heuristic is precisely the contract that pane exists to show.
    public static let rungs: [CascadeRung] = [
        CascadeRung(
            stage: .sessionRule,
            isExecutable: true,
            explanationKey: "explanation.stage.sessionRule",
            settingsCopyKey: "cascade.rung.sessionRule"
        ),
        CascadeRung(
            stage: .taskRule,
            isExecutable: true,
            explanationKey: "explanation.stage.taskRule",
            settingsCopyKey: "cascade.rung.taskRule"
        ),
        CascadeRung(
            stage: .globalRule,
            isExecutable: true,
            explanationKey: "explanation.stage.globalRule",
            settingsCopyKey: "cascade.rung.globalRule"
        ),
        CascadeRung(
            stage: .contextPack,
            isExecutable: true,
            explanationKey: "explanation.stage.contextPack",
            settingsCopyKey: "cascade.rung.contextPack"
        ),
        CascadeRung(
            stage: .seedRule,
            isExecutable: true,
            explanationKey: "explanation.stage.seedRule",
            settingsCopyKey: "cascade.rung.seedRule"
        ),
        CascadeRung(
            stage: .heuristic,
            isExecutable: true,
            explanationKey: "explanation.stage.heuristic",
            settingsCopyKey: "cascade.rung.heuristic"
        ),
        CascadeRung(
            stage: .onDeviceModel,
            isExecutable: false,
            explanationKey: "explanation.stage.onDeviceModel",
            settingsCopyKey: "cascade.rung.onDeviceModel"
        ),
        CascadeRung(
            stage: .seedFallback,
            isExecutable: true,
            explanationKey: "explanation.stage.seedFallback",
            settingsCopyKey: "cascade.rung.seedFallback"
        ),
        CascadeRung(
            stage: .unresolved,
            isExecutable: true,
            explanationKey: "explanation.stage.unresolved",
            settingsCopyKey: "cascade.rung.unresolved"
        )
    ]

    /// The rungs this build can actually consult, in rank order. Computed once.
    public static let executableRungs: [CascadeRung] = rungs.filter(\.isExecutable)

    /// The caption the precedence pane draws beside a rung this build cannot consult.
    public static let unavailableCaptionKey = "cascade.rung.unavailable"

    /// The precedence pane's heading.
    public static let headingKey = "cascade.precedence.heading"

    /// The precedence pane's footnote: your own rules always win.
    public static let footnoteKey = "cascade.precedence.footnote"

    /// The rung for a stage. Total, because `rungs` covers `CascadeStage.allCases` — asserted
    /// by `CascadePrecedenceTests`, so a tenth stage added without a rung fails the suite
    /// rather than returning `nil` somewhere at runtime.
    public static func rung(for stage: CascadeStage) -> CascadeRung? {
        rungs.first { $0.stage == stage }
    }

    public static var unavailableCaptionResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(unavailableCaptionKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    public static var headingResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(headingKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    public static var footnoteResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(footnoteKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }
}
