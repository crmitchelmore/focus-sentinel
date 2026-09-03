import Foundation

/// Whether a rung's answer is a **decision** or an admission that it ran out of instrument.
///
/// ## Why the distinction had to exist before a model could
///
/// `CascadePrecedence`'s doc comment said e06 *"flips one flag and supplies an
/// implementation"*. It cannot, and reading the shipped code rather than the shipped comment is
/// what found it. The heuristic at rank 5 **answers** `uncertain(.noNegativeBasis)` and
/// `uncertain(.languageNotSupported)`, and an `uncertain` answer **terminates** the cascade
/// (R-64). So the walk never reaches rank 6 for the thirty-seven cases the model exists to
/// help, and a model rung inserted as that comment describes would have been consulted on
/// `mixedUseApplication` — which §2.3 forbids — and on nothing else. Flipping the flag would
/// have shipped a model that judges only the cases it must not judge.
///
/// R-64's ruling is that *"'ask each time' is a decision, and it decides to say nothing"*. A
/// `seedFallback` `uncertain` really is a decision. `noNegativeBasis` and `languageNotSupported`
/// are not: they are the engine saying **"I lack the instrument"**. It terminated on them
/// because no lower rung could help. One now can.
///
/// ## What `reviewable(by:)` buys that "keep walking" would not
///
/// It names **one** reviewer. A general fall-through would let a rung *below* the model
/// overturn a provisional answer — a browser with no negative basis would newly resolve at
/// `seedFallback`, and thirty-three committed corpus expectations would change stage for a
/// reason nobody ruled on. Naming the reviewer makes that unrepresentable rather than merely
/// unlikely.
///
/// And in the deterministic composition the named reviewer is not in `executableRungs`, so the
/// reviewable answer stands immediately and the transcript is what e05 shipped — which is a
/// property the evaluation lane measures rather than a claim this comment makes.
public enum RungFinality: Sendable, Equatable, Hashable {
    /// The rung decided. Nothing below it may speak.
    case decided
    /// The rung ran out of instrument. **Exactly one** rung may review it, and only that one.
    case reviewable(by: CascadeStage)

    /// The reviewer, where there is one.
    public var reviewer: CascadeStage? {
        switch self {
        case .decided: nil
        case .reviewable(let stage): stage
        }
    }
}
