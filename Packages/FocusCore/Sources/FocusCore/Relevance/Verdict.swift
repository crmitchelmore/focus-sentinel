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
/// ## Where `permitsIntervention` went, and why it is not coming back
///
/// e01 shipped this enum with a `permitsIntervention: Bool` and a test. That was a correct
/// *statement* and an inadequate *guarantee*: a `Bool` on an enum invites exactly the collapse
/// it forbids, and
///
/// ```swift
/// if outcome.verdict.permitsIntervention || outcome.confidence > 0.9 { … }
/// ```
///
/// compiles. e04 deletes the member and moves the guarantee to `InterventionEligibility`,
/// whose `.mandated` case carries an `InterventionMandate` with no reachable initialiser — so
/// an intervention built from an `uncertain` verdict is not forbidden, it is *unconstructible*
/// (R-55). `check-forbidden.sh` fails on the member name being applied to a `Verdict` anywhere
/// in the repository (R-70a), so it cannot come back by habit.
///
/// `FocusStatus` and `SessionPhase` keep theirs, because those are additional necessary gates
/// and `InterventionEligibility.decide(…)` is the one place all of them are conjoined.
public enum Verdict: String, Sendable, CaseIterable, Codable, Hashable {
    /// The observed context supports the current priority.
    case relevant
    /// The observed context does not support the current priority.
    case unrelated
    /// There is not enough evidence to say. **Suppresses intervention** — via
    /// `InterventionEligibility.decide(…)`, which returns `.suppressed(.verdictUncertain)`
    /// before it reads the band, the drift, the rung or the session phase.
    case uncertain
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
