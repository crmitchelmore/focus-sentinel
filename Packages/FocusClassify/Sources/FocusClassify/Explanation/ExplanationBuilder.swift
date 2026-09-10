import FocusCore
import Foundation

/// Assembles the typed clause list a person reads (R-62, F-52).
///
/// ## There is no prose here, and there cannot be
///
/// The builder never concatenates, never formats and never writes a sentence. It selects
/// `ExplanationClause` values, and every textual payload a clause can carry is a
/// `NormalisedToken` — a type with a private initialiser that rejects whitespace, control
/// characters and every ASCII punctuation mark except `.`, `-` and `_`. A window title, a full
/// URL, a document name and an absolute path are therefore **unrepresentable** in an
/// explanation rather than forbidden in one, and `ExplanationBuilderTests`' hostile corpus is a
/// check on the enforcement rather than the enforcement itself.
///
/// `FocusUI` maps each clause to a String Catalog key and substitutes the typed values. There
/// is **no runtime model-authored prose** — there is no model in this build at all — so D-11
/// and standing condition 4 are structurally satisfied rather than observed.
///
/// ## Total over the ladder
///
/// The temporal switch below is exhaustive over `CascadeStage`, so a tenth rung is a compile
/// error here rather than a rung whose explanations quietly lose their clock. And every stage
/// yields a **non-empty** clause list: an explanation nobody can read is an explanation that
/// will be deleted the first time somebody tidies up.
public struct ExplanationBuilder: Sendable {
    /// The dials the builder reads (focus-exdi): the words an explanation may spend.
    public var tunings: PolicyTunings

    public init(tunings: PolicyTunings = .shipped) {
        self.tunings = tunings
    }

    /// - Parameter mixedSubjectCount: how many *distinct* unrelated subjects the drift
    ///   accumulated across, counted by the caller from the transition window. `DriftSubject`
    ///   deliberately carries no list — three unrelated applications in ninety seconds is one
    ///   fact about somebody's afternoon, not three names to read back to them, and a mandate
    ///   that named the last of them would be the app misdescribing what they did — so the
    ///   count is measured rather than assumed, and the copy says *several unrelated
    ///   applications* rather than enumerating any.
    public func build(
        resolution: CascadeResolution,
        drift: DriftState,
        anchor: NormalisedToken? = nil,
        mixedSubjectCount: Int = 0,
        stamp: EngineStamp = .current
    ) -> Explanation {
        var clauses = resolution.clauses

        if Self.reportsTime(at: resolution.stage) {
            clauses += temporalClauses(
                resolution: resolution,
                drift: drift,
                anchor: anchor,
                mixedSubjectCount: mixedSubjectCount
            )
        }

        if clauses.isEmpty {
            // Unreachable through the shipping cascade, every rung of which emits at least one
            // clause — asserted directly by `ExplanationBuilderTests`. Kept because an empty
            // explanation is worse than a modest one: a surface that can draw the rung but not
            // a single reason is a surface that says "you are off task" and nothing else, and
            // a decision whose evidence cannot be rendered is one a person should be told is
            // thin rather than shown as bare.
            clauses = [.insufficientEvidence(reason: resolution.uncertaintyReason ?? .noEvidence)]
        }

        return Explanation.make(
            stage: resolution.stage,
            band: resolution.band,
            clauses: clauses,
            stamp: stamp,
            tunings: tunings
        )
    }

    /// Whether a rung's explanation may talk about the clock.
    ///
    /// **Exhaustive over `CascadeStage`**, which is R-54's second reader of the ladder. The two
    /// rungs that decline outright say nothing about time, because the engine that has nothing
    /// to say about *what* somebody is doing has nothing to say about how long they have been
    /// doing it either — reporting a dwell beside "I do not know" would be an accusation
    /// wearing a fact's clothes.
    static func reportsTime(at stage: CascadeStage) -> Bool {
        switch stage {
        case .sessionRule, .taskRule, .globalRule, .contextPack, .seedRule, .heuristic,
             .onDeviceModel:
            true
        case .seedFallback, .unresolved:
            false
        }
    }

    /// The clock's clauses: how long, across how many subjects, and whether they came back.
    func temporalClauses(
        resolution: CascadeResolution,
        drift: DriftState,
        anchor: NormalisedToken?,
        mixedSubjectCount: Int
    ) -> [ExplanationClause] {
        var clauses: [ExplanationClause] = []

        switch drift {
        case .sustained(let subject, let accumulated, let isMixed):
            // Only ever beside an accusation. A sustained accumulator under a `relevant`
            // verdict is a stale reading the engine is about to clear, and printing it would
            // tell somebody they had been off task for four minutes while they worked.
            if resolution.verdict == .unrelated {
                if !resolution.clauses.contains(where: { $0.kind == .sustainedDwell }) {
                    clauses.append(.sustainedDwell(seconds: Int(accumulated.components.seconds)))
                }
                if isMixed || subject.isMixed, mixedSubjectCount > 1 {
                    // "Several unrelated applications", never one of them misnamed.
                    clauses.append(.mixedSubjects(count: mixedSubjectCount))
                }
            }

        case .aligned:
            // They went back to where they were working. The one clause in the epic that is
            // good news.
            if let anchor, resolution.verdict == .relevant {
                clauses.append(.returnedToAnchor(subject: anchor))
            }

        case .grace, .cooldown:
            break
        }

        return clauses
    }
}
