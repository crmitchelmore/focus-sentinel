import Foundation

/// The classifier's conclusion.
///
/// `uncertain` is a first-class case and is **intervention-suppressing**: when the answer
/// is `uncertain` the app does not nudge, does not warn and does not escalate. This is
/// standing condition 6, and every consumer must handle it explicitly; there is deliberately
/// no default and no `Bool` projection that would let a call site collapse three cases into
/// two.
///
/// ## Why this lives in `FocusCore` from e04
///
/// It shipped in `FocusClassify` in e01, where the engine lives. That was the wrong home for
/// one boundary reason and one type reason (R-53):
///
/// * `FocusUI` may not import `FocusClassify` (the R-14 matrix, enforced by lint), and the
///   verdict inspector — and, in e05, the whole nudge surface — has to render a verdict. The
///   shipped precedent is exact: `PriorityRuleScope` lives here *because* `FocusUI` may not
///   import `FocusRules`.
/// * `InterventionMandate`'s sole producer must be able to see a `Verdict`, the mandate has to
///   be renderable by `FocusUI`, and therefore both live here.
///
/// `FocusClassify` keeps every name as a `typealias`, exactly as `FocusSensing` kept
/// `ActivityEventKind` when e03 moved it for the same reason — so every existing call site is
/// untouched and there is still exactly one vocabulary rather than two that could drift.
public enum Verdict: String, Sendable, CaseIterable, Codable, Hashable {
    /// The observed context supports the current priority.
    case relevant
    /// The observed context does not support the current priority.
    case unrelated
    /// There is not enough evidence to say. **Suppresses intervention.**
    case uncertain

    /// Whether a verdict permits the app to interrupt the user.
    ///
    /// Only `unrelated` does. `relevant` has no reason to, and `uncertain` is forbidden to.
    public var permitsIntervention: Bool {
        switch self {
        case .unrelated: true
        case .relevant, .uncertain: false
        }
    }
}

/// Where a verdict came from. Recorded so that a later epic can tell a user-authored rule
/// from an inference, and so the verdict cache can be invalidated by source.
public enum VerdictSource: String, Sendable, CaseIterable, Codable, Hashable {
    /// A rule the user wrote.
    case userRule
    /// A deterministic heuristic.
    case heuristic
    /// The on-device language model (arrives in e06).
    case onDeviceModel
    /// No source could decide.
    case undecided
}
