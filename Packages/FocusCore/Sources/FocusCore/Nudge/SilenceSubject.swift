import Foundation

/// **What a reason for silence is ABOUT** — the rule that decides which rungs it may silence
/// (focus-uru, focus-0y6).
///
/// ## Why this type exists rather than a list of gates
///
/// Three separate rounds found the same defect: a gate written about *interrupting somebody* had
/// been applied to a rung that interrupts nobody. Gate 7 of `SuppressionStack` was the first —
/// a presentation defers the ambient rung rather than suppressing it. Gate 5 of
/// `FatigueController` was the second (focus-2yy) — *a rung is refused only by a cap it can
/// spend*. `focus-0y6` then found three more in the stack and this round found a fourth in the
/// fatigue controller, sitting **between two gates that had already been given the exemption**.
///
/// Each of those repairs added one more bespoke `rung != .ambient` to one more gate, and the next
/// gate arrived without one. So the ruling is no longer written per gate. **Every reason the app
/// has for going quiet declares its subject here, the evaluation applies it, and a new reason
/// cannot be added without answering the question** — the `switch`es in
/// `NudgeSuppressionReason.subject` and `FatigueRefusal.Kind.subject` are exhaustive, so a
/// thirteenth gate or a seventh refusal does not compile until somebody has ruled on it.
///
/// ## The rule itself
///
/// **The glyph is a state, not a sentence.** It costs nothing — `InterventionEvent`
/// `.spendsTheInterruptionCap` and `.spendsTheAccusationCap` both answer `false` for it — it
/// holds no slot — `NudgeSurface.menuBar.holdsTheInterruptionSlot` is `false` — and it survives
/// what interruptions are spared, which is R-87's snooze exemption and F-63's backoff retaining
/// the ambient rung. F-146 is the product sentence underneath all of that: *the state is always
/// legible*.
///
/// So a reason about **the app speaking** has nothing to say about a rung that says nothing, and
/// `ruling(for:)` below is where that is decided — once, reading
/// `LadderRung.Kind.makesAnAccusation`, which is the ladder's own derivation of *"does this rung
/// say something a person could answer?"* rather than a second copy of it. A third rung added
/// above the panel inherits the obligation; a rung added below it inherits the exemption.
public enum SilenceSubject: Sendable, Equatable, Hashable {
    /// **The app speaking.** An interruption: a sentence that takes the person's attention, holds
    /// the one interruption slot, costs a unit of their day, and can be answered.
    ///
    /// A reason with this subject stops every rung that speaks and **passes** every rung that
    /// does not. A person who snoozed a panel asked for quiet, not for a lie.
    case theAppSpeaking
    /// **Whether there is anything to be legible about at all.** No commitment, sensing off, a
    /// sensitive application frontmost, a session that is not in focus, nobody at the keyboard, a
    /// verdict that authorises nothing, a subject the person has already told us is real work.
    ///
    /// A reason with this subject stops **every** rung, the glyph included, because a glyph that
    /// went on marking a person as off task under any of these would not be telling the truth —
    /// and the whole argument for exempting it is that it tells the truth.
    case anythingToBeLegibleAbout
    /// **The surface itself is not on screen.** The rung was wanted and could not be delivered.
    ///
    /// A reason with this subject stops every rung, and for a rung that does not speak it stops
    /// it as a **deferral** rather than a suppression (R-81): an undeliverable rung must not
    /// advance the ladder, must not spend a cap and must not start the escalation clock. The
    /// deferral reason is carried in the case, so a gate cannot claim this subject without
    /// naming why nobody could have seen it.
    case theSurfaceBeingOnScreen(DeferralReason)
}

/// **What a reason for silence does to one rung.**
///
/// Three answers rather than a `Bool`, for the reason `SuppressionOutcome` has three: *the app
/// chose not to* and *nobody could have seen it* are different facts with different consequences
/// for the ladder and the day's budget, and a `Bool` collapses them invisibly.
public enum SilenceRuling: Sendable, Equatable, Hashable {
    /// The reason stands and the app is silent by choice.
    case silences
    /// The reason stands and nobody could have seen this rung. Does not advance the ladder, does
    /// not spend a cap, does not start the escalation clock (R-81).
    case defers(DeferralReason)
    /// **The reason is not about a rung like this one.** Evaluation continues to the next gate;
    /// this is never an answer, only a passing over.
    case passes
}

extension SilenceSubject {
    /// **The one application of the rule**, for one rung.
    ///
    /// - Parameter rung: the accusation rung being considered, or `nil` for a **question**. A
    ///   question is always a sentence — U-1 licensed the app to interrupt for exactly one thing
    ///   and this is it — so `nil` speaks, and every gate applies to it.
    public func ruling(for rung: LadderRung.Kind?) -> SilenceRuling {
        // `makesAnAccusation` and not a fresh comparison against `.ambient`: the ladder already
        // owns *"does this rung say something the person could answer?"*, derives it from the
        // rank so a rung added above the panel inherits it, and is what
        // `InterventionEvent.spendsTheAccusationCap` reads to decide the same question about the
        // day's budget. Two derivations of one rule is how the previous three repairs each fixed
        // one gate and left the next.
        let speaks = rung?.makesAnAccusation ?? true
        switch self {
        case .anythingToBeLegibleAbout:
            return .silences
        case .theAppSpeaking:
            return speaks ? .silences : .passes
        case .theSurfaceBeingOnScreen(let reason):
            return speaks ? .silences : .defers(reason)
        }
    }

    /// Whether a reason with this subject stops `rung` at all, whichever way it stops it.
    ///
    /// The shape a caller wants when it has no way to *say* "deferred" — `FatigueDecision` has
    /// two cases and no third, deliberately, because gate 10 of the stack reports one reason and
    /// a deferral is the stack's own answer to give. `FatigueRefusal.Kind.subject` is therefore
    /// never `.theSurfaceBeingOnScreen`, and `SilenceVocabularyTests` holds that.
    public func silences(_ rung: LadderRung.Kind?) -> Bool {
        ruling(for: rung) != .passes
    }
}
