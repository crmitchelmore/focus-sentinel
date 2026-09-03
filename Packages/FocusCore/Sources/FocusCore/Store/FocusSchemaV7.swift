import Foundation
import SwiftData

/// Schema version 7 of the Focus Sentinel store.
///
/// **One fact the app had and threw away: why it said what it said** (focus-tee.3).
///
/// An `InterventionRecord` says what the app did — the kind, the rung, the surface, the
/// disposition, what the person did next. It says nothing about *why*, because the verdict's
/// `Explanation` was built, rendered and dropped. A question already carries its reason
/// (`AskedQuestion.reasonRaw` is a stored `QueryableUncertainty`); an accusation and a
/// suppression carried none, so History could say *what happened* and never *what the app was
/// going on*.
///
/// v7 adds **one optional column** to that one entity:
/// `InterventionRecord.explanationKindsRaw` — the comma-joined raw values of the
/// `ExplanationClauseKind`s the verdict carried, in the order the engine found them.
///
/// ## Why this column is not a new observation about a person
///
/// `ExplanationClauseKind` is a **closed `String` `CaseIterable` enum with no payload**. Each
/// case is bound to exactly one `explanation.clause.*` String Catalog key by a bijection
/// `check-strings.sh` asserts in both directions, so the vocabulary cannot grow without a
/// reviewer seeing it. No `NormalisedToken` reaches it, no subject, no number, no similarity
/// distance — `tokenOverlap` stores the word *tokenOverlap* and never the tokens.
///
/// And it goes on **rows the app already writes**. A row exists only where the app spoke or
/// actively stayed quiet, so this is not the per-minute record of conclusions the epic plan's
/// §4 was refused for. It says strictly less about a person than the `subject` column already
/// sitting beside it.
///
/// ## Why v7 re-declares one class where v4, v5 and v6 re-declared none
///
/// Those three were purely additive — a new entity apiece and no existing one touched — so each
/// could name its predecessor's classes and keep every call site fetching the type it already
/// knew. v7 cannot: the column belongs on `InterventionRecord`, and `InterventionRecord` is
/// declared by v4.
///
/// Editing v4's declaration is the thing this store's migration doctrine forbids, and
/// `MigrationV4Tests` says why in as many words: v1…v6 are the stores earlier builds actually
/// wrote, and a source you have edited is not a source. So v7 re-declares that **one** class,
/// names v6's other thirteen, and every reference to `FocusSchemaV4.InterventionRecord` in the
/// programme moves here. `MigrationV7Tests` asserts the delta is exactly one class and exactly
/// one property, which is the narrower form of the invariant v4, v5 and v6 each keep unchanged
/// for themselves.
///
/// ## Why the v6 → v7 stage is lightweight
///
/// The added property is optional and every other column is byte-identical to v4's, which is
/// precisely the condition probe P-51 measured for a stage with no code in it. An old row
/// arrives with `explanationKindsRaw == nil`, and that is the honest value: the app really did
/// not record why, and `nil` says so where an empty string would claim the verdict carried no
/// clauses at all.
public enum FocusSchemaV7: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(7, 0, 0)
    }

    /// v6's fourteen, with `InterventionRecord` replaced by this version's declaration.
    ///
    /// Built by filtering rather than by re-listing the other thirteen: a list written out by
    /// hand is a list that silently loses an entity when v6 gains one, and the whole reason this
    /// store has a migration plan is that silent loss is the failure mode.
    public static var models: [any PersistentModel.Type] {
        FocusSchemaV6.models.filter { $0 != FocusSchemaV4.InterventionRecord.self }
            + [InterventionRecord.self]
    }

    /// **One thing the app said**, with what became of it — and, from v7, the shape of the
    /// reason it had.
    ///
    /// Byte-identical to `FocusSchemaV4.InterventionRecord` but for the last column. It is
    /// re-declared rather than edited because v4 is a migration source; see the note above.
    ///
    /// There is still **no causal field** and nowhere for one to be added: no "effectiveness",
    /// no "helped", no streak (R-93, D-01). What the app may record is what it did, what the
    /// person did next, and the vocabulary of the reason — three facts, never one conclusion.
    @Model
    public final class InterventionRecord {
        public var id: UUID
        public var at: Date
        /// e02's `LocalDay.key` — `yyyy-MM-dd` in the user's own calendar.
        public var localDayKey: String
        /// `InterruptionKind` raw value: `query` or `accusation`.
        public var kindRaw: String
        /// `LadderRung.Kind` raw value. Accusations only; `nil` for a question, which has no
        /// ladder and cannot acquire one.
        public var rungRaw: String?
        /// The bundle identifier or origin. Empty for a mixed accusation, which names nobody —
        /// and empty for a suppression at the sensitive-application gate, where e03 suppressed
        /// the activation before the engine ever saw the subject.
        public var subject: String
        /// `RuleSubjectKind` raw value, read off the subject by `InterventionLog.subjectKind(of:)`
        /// rather than assumed (focus-tee.2).
        public var subjectKindRaw: String
        /// The priority this happened under. Optional because a suppression at gate 1 is
        /// precisely the case where there is none.
        public var priorityID: UUID?
        /// `NudgeSurface` raw value, or **the empty string when it reached none** — which is
        /// every deferral and every suppression. Read through `surface`, which decodes the
        /// empty string as `nil` rather than inventing a surface nobody saw.
        public var surfaceRaw: String
        /// `InterventionDisposition` raw value: delivered, deferred, unopened or suppressed.
        /// **Only a delivery spends a cap** (R-81).
        public var dispositionRaw: String
        /// `InterventionOutcome` raw value, or `nil` while it is still on screen.
        public var outcomeRaw: String?
        /// `QueryAnswer` raw value: which click wrote the rule this record's verdict rests on.
        ///
        /// The column that keeps R-78's distinction visible in the data. A later `unrelated`
        /// verdict sourced from a rule the person wrote by answering "No" is a **user-authored**
        /// verdict at the `taskRule` rung, not a query that escalated — and the Rules pane and
        /// the judgment inspector can both show them exactly what their click did.
        public var originatingAnswerRaw: String?
        /// **The shape of the reason, and nothing of its content** (v7, focus-tee.3).
        ///
        /// The comma-joined `ExplanationClauseKind` raw values the verdict carried, in the order
        /// the engine found them. `nil` means *the app did not record why* — every row written
        /// before v7, and every row written where no explanation existed to record — which is a
        /// different fact from an empty list and is stored differently for that reason.
        ///
        /// Read through `explanationKinds`, never split by hand.
        public var explanationKindsRaw: String?

        public init(
            id: UUID = UUID(),
            at: Date,
            localDayKey: String,
            kindRaw: String,
            rungRaw: String? = nil,
            subject: String,
            subjectKindRaw: String,
            priorityID: UUID? = nil,
            surfaceRaw: String,
            dispositionRaw: String,
            outcomeRaw: String? = nil,
            originatingAnswerRaw: String? = nil,
            explanationKindsRaw: String? = nil
        ) {
            self.id = id
            self.at = at
            self.localDayKey = localDayKey
            self.kindRaw = kindRaw
            self.rungRaw = rungRaw
            self.subject = subject
            self.subjectKindRaw = subjectKindRaw
            self.priorityID = priorityID
            self.surfaceRaw = surfaceRaw
            self.dispositionRaw = dispositionRaw
            self.outcomeRaw = outcomeRaw
            self.originatingAnswerRaw = originatingAnswerRaw
            self.explanationKindsRaw = explanationKindsRaw
        }
    }
}

// MARK: - Typed accessors
//
// The same rule every enum-backed column in this store already follows: read and written through
// a decoder, so no call site joins or splits a string by hand. v4's accessors are re-stated here
// against the re-declared class — the decoders themselves are v4's and are not duplicated.

extension FocusSchemaV7.InterventionRecord {
    public var kind: InterruptionKind {
        get { InterruptionKind.decode(kindRaw) }
        set { kindRaw = newValue.rawValue }
    }

    /// The rung, for an accusation. `nil` for a question, which has no ladder.
    public var rung: LadderRung.Kind? {
        get { rungRaw.map { LadderRung.Kind.decode($0) } }
        set { rungRaw = newValue?.rawValue }
    }

    public var subjectKind: RuleSubjectKind {
        get { RuleSubjectKind.decode(subjectKindRaw) }
        set { subjectKindRaw = newValue.rawValue }
    }

    /// The surface that took it, or `nil` when it reached none.
    ///
    /// The empty string means "no surface", which is what every deferral and every suppression
    /// stores. Decoding it as a surface would be the record claiming somebody saw something.
    public var surface: NudgeSurface? {
        get { surfaceRaw.isEmpty ? nil : NudgeSurface.decode(surfaceRaw) }
        set { surfaceRaw = newValue?.rawValue ?? "" }
    }

    public var disposition: InterventionDisposition {
        get { InterventionDisposition.decode(dispositionRaw) }
        set { dispositionRaw = newValue.rawValue }
    }

    public var outcome: InterventionOutcome? {
        get { outcomeRaw.map { InterventionOutcome.decode($0) } }
        set { outcomeRaw = newValue?.rawValue }
    }

    public var originatingAnswer: QueryAnswer? {
        get { originatingAnswerRaw.map { QueryAnswer.decode($0) } }
        set { originatingAnswerRaw = newValue?.rawValue }
    }

    /// **The clause kinds the verdict carried, or `nil` when the app did not record why.**
    ///
    /// `nil` and `[]` are two different facts and survive a round trip as two different values,
    /// for `ShellStateRecord.openWindowsAtLastQuit`'s reason: *"nothing was recorded"* is a row
    /// from before v7 or from a path that had no explanation to hand, and *"an explanation with
    /// no clauses"* would be a claim about the verdict. History says "not recorded" for the
    /// first and would say "no reasons given" for the second, and it must not confuse them.
    ///
    /// A raw value this build cannot read is **dropped rather than guessed**: the vocabulary is
    /// closed and bound to the catalog in both directions, so an unknown case is a row written
    /// by a later build, and inventing a clause for it would put a sentence in front of somebody
    /// that no build ever meant.
    /// Whether this row spends a unit of the day's budget. **Only a delivery does** (R-81).
    public var spendsBudget: Bool { disposition == .delivered }

    /// **This row as the value the two cap predicates are asked of** (focus-ndh, focus-d6r).
    ///
    /// One reconstruction rather than one per predicate, so a third cap cannot be given a
    /// differently-built event to answer about. The columns it reads — the disposition, the kind
    /// and the rung — are the ones R-79 commits.
    public var budgetEvent: InterventionEvent {
        InterventionEvent(
            kind: kind,
            rung: rung,
            subject: subject,
            surface: surface,
            disposition: disposition
        )
    }

    /// **Whether this row spends one of the day's six accusations** (focus-ndh).
    ///
    /// Delegated to `InterventionEvent.spendsTheAccusationCap` rather than restated here: the
    /// rule is *"a rung that accuses nobody spends no accusation"*, it is derived from
    /// `LadderRung.Kind.makesAnAccusation`, and a second copy of it on the stored row is a second
    /// place for it to be got wrong.
    public var spendsTheAccusationCap: Bool { budgetEvent.spendsTheAccusationCap }

    /// **Whether this row spends one of the day's eight interruptions** (focus-d6r).
    ///
    /// The twin the row was not given. `spendsTheAccusationCap` above was delegated here in
    /// focus-ndh and its sibling was left as `spendsBudget` at the one call site that sums the
    /// shared budget, which is how eight glyph landings came to silence the panel rung on a day
    /// the app had accused nobody. Delegated for the same reason and by the same route: a rule
    /// with two homes is a rule that can be moved in one of them.
    public var spendsTheInterruptionCap: Bool { budgetEvent.spendsTheInterruptionCap }

    public var explanationKinds: [ExplanationClauseKind]? {
        get {
            guard let raw = explanationKindsRaw else { return nil }
            if raw.isEmpty { return [] }
            return raw.split(separator: ",").compactMap {
                ExplanationClauseKind.decodeIfKnown(String($0))
            }
        }
        set {
            explanationKindsRaw = newValue.map {
                $0.map(\.rawValue).joined(separator: ",")
            }
        }
    }
}

extension ExplanationClauseKind {
    /// The one decoder, written as an **exhaustive switch over string literals** rather than
    /// `init(rawValue:)` — R-49's doctrine, which `check-forbidden.sh` enforces.
    ///
    /// It answers `nil` rather than a default, because unlike every other column in this store
    /// there is no safe default clause: the quiet answer is to say nothing at all about a reason
    /// this build does not have a sentence for.
    static func decodeIfKnown(_ raw: String) -> ExplanationClauseKind? {
        switch raw {
        case "userRule": .userRule
        case "contextItem": .contextItem
        case "seedDefault": .seedDefault
        case "tokenOverlap": .tokenOverlap
        case "similarityCorroborated": .similarityCorroborated
        case "sustainedDwell": .sustainedDwell
        case "returnedToAnchor": .returnedToAnchor
        case "mixedSubjects": .mixedSubjects
        case "conflictingRules": .conflictingRules
        case "insufficientEvidence": .insufficientEvidence
        case "languageNotSupported": .languageNotSupported
        case "seedFallbackMixedUse": .seedFallbackMixedUse
        case "noNegativeBasis": .noNegativeBasis
        case "modelDirect": .modelDirect
        case "modelSupporting": .modelSupporting
        default: nil
        }
    }
}
