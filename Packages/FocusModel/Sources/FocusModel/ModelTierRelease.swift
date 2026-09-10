import Foundation

/// **Whether this build composes the model rung into the ladder — and it does not.**
///
/// This is a measurement, not caution, and it is the honest outcome of e06 rather than a
/// failure of it. The mechanism is built, linted, bounded and measured; the *rescuer* has not
/// earned its place, and the number that says so is the one the plan gave a budget of zero.
///
/// ## What was measured
///
/// `FocusEvaluate --model` over the committed 45-cell grid, three passes each, on macOS
/// 26.5.2 with `SystemLanguageModel.default.availability == .available` and
/// `GenerationOptions(sampling: .greedy)`:
///
/// | prompt form | `rescued` | `missedRescue` | **`seduced`** | `declined` | `rescueRecall` |
/// |---|---|---|---|---|---|
/// | 1 · four labels, "prefer unsure" |  9 | 6 | **14** | 16 | 0.60 |
/// | 2 · `unrelated` named as the commonest answer | 14 | 1 | **20** | 10 | 0.93 |
/// | 3 · a method: name the set, then check membership | 11 | 4 | **15** | 15 | 0.73 |
///
/// The budget for `seduced` is **zero**, and R-111 is explicit that *"a seduction is a prompt
/// defect and the remedy is the prompt, never the threshold"*. Three forms were written and
/// measured; the best of them still went quiet about fifteen of the thirty cells the grid
/// committed as holds. Narrowing the prompt raised recall and made the seductions **worse**,
/// which is the shape of the finding: a 3B on-device model handed a reverse-DNS identifier and
/// a task reads capability as relevance, and it does so consistently — `unstable` was empty
/// across all three passes of all three forms, so this is not noise that a fourth run would
/// wash out.
///
/// ## Why that decides the composition rather than only the report
///
/// A seduction is the app **going quiet** about something the person's own evidence said to
/// hold. Under U-1 silence is earned by confident relevance and by nothing else, and a
/// question costs one click while a wrongly-earned silence costs the interruption the person
/// asked for. Composing a rung that is wrong fifteen times in thirty on the very cases it
/// exists to judge would trade the cheap mistake for the expensive one.
///
/// So `RelevanceHost` composes `.deterministic` whatever this Mac's availability says, the
/// ladder stays eight rungs, `byStage.onDeviceModel` stays zero, and the app is exactly the app
/// e05 shipped. Everything else e06 built stands: the package, the port, the finality
/// distinction that makes rank 6 reachable at all, the deferral fix, the grid, and a lane that
/// re-measures this decision on demand and would flip it.
///
/// **What it would take to flip.** One green quality half — `seduced == 0`,
/// `rescueRecall >= modelRescueRecallFloor`, `unstable` empty — archived under
/// `.agents/evidence/e06/`, and this constant becomes `true` in the same commit as the prompt
/// revision that earned it. The lint that keeps `promptRevisions` a list rather than a digit is
/// what makes that a reviewed act.
public enum ModelTierRelease {
    /// `false`. See the type note for the measurement and for what would change it.
    public static let composesTheRung = false

    /// The reason, in one line, for a self-check reading and a Settings caption to draw from a
    /// single place rather than each restating it.
    public static let reason = "measured: seduced 15 of 30 hold cells, budget 0"
}
