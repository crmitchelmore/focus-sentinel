import FocusCore
import Foundation

extension RuleVerdict {
    /// The verdict a stored user rule implies. A user's explicit `uncertain` stays
    /// `uncertain` — declining to decide is preserved, never upgraded.
    ///
    /// This lived in `FocusClassify` until e04 (R-53). It belongs here now: it is an
    /// extension *on a rule*, and once `Verdict` lives in `FocusCore` it needs no engine
    /// package at all to be written. `FocusRules` already imports `FocusCore`, so the R-14
    /// matrix is unchanged — no new edge and no new package.
    public var classificationVerdict: Verdict {
        switch self {
        case .relevant: .relevant
        case .unrelated: .unrelated
        case .uncertain: .uncertain
        }
    }
}
