import FocusCore
import Foundation

/// The classification vocabulary, re-exported under the names e01 shipped.
///
/// `Verdict`, `VerdictSource`, `ClassificationOutcome` and `ClassificationInput` moved to
/// `FocusCore` in e04 (R-53), because `FocusUI` may not import this package and yet has to
/// render a verdict, and because the type that authorises an interruption must be declared
/// beside them. The aliases are the same technique `FocusSensing` used when `ActivityEventKind`
/// moved for the same reason: every existing call site — including e01's shipped tests —
/// compiles unchanged, and there is exactly one vocabulary rather than two that could drift.
public typealias Verdict = FocusCore.Verdict
public typealias VerdictSource = FocusCore.VerdictSource
public typealias ClassificationOutcome = FocusCore.ClassificationOutcome
public typealias ClassificationInput = FocusCore.ClassificationInput

/// The classification seam.
///
/// e04 supplies the deterministic rule/heuristic engine and e06 the on-device model behind
/// this same protocol. Nothing above this seam ever learns which one answered, except
/// through `ClassificationOutcome.source`.
public protocol RelevanceClassifier: Sendable {
    func classify(_ input: ClassificationInput) -> ClassificationOutcome
}

/// The classifier e01 ships: it has no rule engine and no model, so it declines to decide.
///
/// This is not a stub standing in for a real implementation — it is the honest answer for a
/// build that has no evidence source yet, and it is the behaviour every later engine must
/// fall back to. Because `uncertain` suppresses intervention, an app running on this
/// classifier is guaranteed never to nudge, which is exactly the right failure mode.
public struct UndecidedClassifier: RelevanceClassifier {
    public init() {}

    public func classify(_ input: ClassificationInput) -> ClassificationOutcome {
        _ = input
        return .undecided
    }
}
