import Foundation

/// How much the app has to go on. **Ordinal, never numeric.**
///
/// The Feasibility Court cut statistical calibration and kept ordinal bands, and the
/// distinction is not cosmetic: a `Double` invites arithmetic, arithmetic invites a
/// threshold, and a threshold on a number nobody calibrated is a confidence claim this app
/// cannot support. Three bands, comparable, and no case carries a number.
///
/// `.low` can never mandate an intervention — `RelevancePolicy.interventionBandFloor` is
/// `.medium` — which is what makes the similarity signal structurally incapable of causing a
/// nudge on its own (R-56, and the conclusion probe P-113 forces).
public enum EvidenceBand: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
    /// Real signal, no precision. Similarity below the ceiling with no overlap; an overlap on
    /// short tokens only.
    case low
    /// Something exact matched, or time has done the work: a strong token overlap, a keyword
    /// the user chose, a bundled decisive default, sustained dwell behind the negative basis.
    case medium
    /// The user said so, or an identity they attached matched exactly. Nothing outranks it.
    case high

    /// Where this band sits. Derived from `allCases` for the same reason `CascadeStage.rank`
    /// is: the order is a property of the declaration, and no numeric literal appears (R-70f).
    public var rank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    /// The String Catalog key for this band's label.
    public var labelKey: String {
        switch self {
        case .low: "evidence.band.low"
        case .medium: "evidence.band.medium"
        case .high: "evidence.band.high"
        }
    }

    public var labelResource: LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(labelKey),
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    public static func < (lhs: EvidenceBand, rhs: EvidenceBand) -> Bool {
        lhs.rank < rhs.rank
    }
}
