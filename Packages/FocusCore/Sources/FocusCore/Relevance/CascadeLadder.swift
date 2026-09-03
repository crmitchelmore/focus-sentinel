import Foundation

/// **The ladder a particular composition walks.**
///
/// `CascadePrecedence.rungs` stays exactly as declared, with `onDeviceModel.isExecutable ==
/// false`: *that list is the declaration of the ladder, and the deterministic ladder is what it
/// declares.* What e06 adds is not a second declaration but a composed value — which list you
/// got is a property of what you assembled, not of what the build constant says (R-101).
///
/// The model rung's executability is a **runtime** fact — availability, thermal state, Low
/// Power Mode — so it cannot be a `static let`, and it must not become a `switch` inside
/// `RuleCascade`: that is precisely the special case `CascadePrecedence`'s own doc comment
/// forbids. There are now two lists instead of one, and no `switch` on rung order anywhere.
///
/// `.deterministic` is what every composition with no model port gets, and every byte of its
/// behaviour is what e05 shipped.
public struct CascadeLadder: Sendable, Equatable, Hashable {
    /// Every rung the vocabulary knows, in rank order. Always nine.
    public let rungs: [CascadeRung]
    /// The rungs this composition can consult, in rank order. Eight without a model port, nine
    /// with one.
    public let executableRungs: [CascadeRung]

    public init(modelAvailable: Bool) {
        let composed = CascadePrecedence.rungs.map { rung in
            rung.stage == .onDeviceModel
                ? CascadeRung(
                    stage: rung.stage,
                    isExecutable: modelAvailable,
                    settingsCopyKey: rung.settingsCopyKey
                )
                : rung
        }
        self.rungs = composed
        self.executableRungs = composed.filter(\.isExecutable)
    }

    /// The ladder with no model port. Identical, rung for rung, to what
    /// `CascadePrecedence.executableRungs` has always been.
    public static let deterministic = CascadeLadder(modelAvailable: false)

    /// Whether this composition may consult a named stage.
    ///
    /// The one question `RuleCascade` asks of a `RungFinality.reviewable(by:)` answer, so the
    /// reviewer is looked up in the composed ladder rather than assumed from the build.
    public func canExecute(_ stage: CascadeStage) -> Bool {
        executableRungs.contains { $0.stage == stage }
    }
}
