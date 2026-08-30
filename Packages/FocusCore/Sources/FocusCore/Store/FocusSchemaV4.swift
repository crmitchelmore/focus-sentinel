import Foundation
import SwiftData

/// Schema version 4 of the Focus Sentinel store.
///
/// Two facts have to survive a relaunch and neither has a home in v3: **which questions have
/// been asked** (R-78) and **how many interruptions today** (R-83, F-107). v4 adds one entity
/// for each and changes nothing else.
///
/// ## Why this schema declares two models and reuses ten
///
/// v1 → v2 → v3 each re-declared every `@Model` class, because each of them *changed* one: v2
/// removed `PriorityTask.isActive` and added a pointer row, v3 grew the session runtime. A
/// version that re-declares a class it did not change would fork the type — every call site in
/// the programme would have to be moved to the new namespace, and two identical declarations
/// would exist for a reviewer to keep in step by hand.
///
/// v4 changes **nothing**. It is purely additive, so `models` names v3's ten classes and adds
/// two of its own, and every existing call site — `PriorityStore`, `SessionStore`,
/// `ActivityEventStore`, the cockpit, the rules pane — keeps working against exactly the
/// entities it already knew. That is what makes the stage below a *lightweight* one honestly
/// rather than by assertion: there is no attribute to carry, no column removed, no rename, and
/// e02's probe P-51 measured that to be exactly the condition SwiftData needs.
///
/// ## Why the query ledger and the intervention log are not `ActivityEvent` rows
///
/// e04's `ActivityEventStore` records what the **person and the machine** did. An intervention
/// is what the **app** did. Mixing them would make F-115's retention policy delete the app's
/// own accountability alongside the observations, and would make the daily-cap predicate a
/// scan over the largest table in the store (R-79).
///
/// Enum-backed fields remain `String` raw values (e01's R-05), and every one of them is read
/// through an exhaustive `switch` at the foot of this file — never `init(rawValue:)`, which
/// reordering an enum could silently reinterpret and which the lint bans outright.
public enum FocusSchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        FocusSchemaV3.models + [AskedQuestion.self, InterventionRecord.self]
    }

    /// **The receipt.** One row per question the app has asked, for ever.
    ///
    /// This is the record R-78 makes authoritative for never-ask-twice, and its two properties
    /// are the whole of the ruling:
    ///
    /// * **It is immutable.** `QueryLedger` exposes no API that edits or deletes a row except
    ///   `purge(priorityID:)`. The *rule* an answer writes is visible, editable and deletable
    ///   by design — every learned chip and every Rules-pane row has a remove affordance and an
    ///   undo — and the moment it is gone the subject classifies `uncertain` again and a warrant
    ///   becomes constructible. An invariant U-1 states in absolute terms cannot rest on a
    ///   record one click removes, so it rests on this one instead.
    /// * **`priorityID` is a plain `UUID`, never a relationship.** A relationship would make
    ///   deleting a priority a cascade the store performs for us — which sounds convenient
    ///   until the retention policy needs to purge one priority's rows in a single predicate,
    ///   and until a receipt outlives the object graph it was attached to. The key is the
    ///   identifier, and `purge(priorityID:)` is one `#Predicate`.
    ///
    /// The ledger key is `(priorityID, subjectKind, subject)` — *priority*, not session,
    /// because U-1 says "for this task". A **revision bump on the same priority id does not**
    /// re-open a question: editing the wording of a commitment is not making a new one. A new
    /// priority legitimately does, and that is correct.
    @Model
    public final class AskedQuestion {
        public var id: UUID
        /// The ledger key's first component. Never a relationship — see the type's note.
        public var priorityID: UUID
        /// `RuleSubjectKind` raw value: `app` at baseline, `domain` once e07 lands.
        public var subjectKindRaw: String
        /// The bundle identifier or normalised `scheme://host[:port]` origin.
        public var subject: String
        /// `QueryableUncertainty` raw value — which of the three answerable uncertainties
        /// produced the question. Recorded so `byQueryReason` is a fact rather than a guess.
        public var reasonRaw: String
        public var askedAt: Date
        /// `AskedQuestionOutcome` raw value: answered relevant, answered unrelated, declined
        /// or expired.
        public var outcomeRaw: String
        /// When the person answered, or `nil` while the question is still on screen.
        public var answeredAt: Date?

        public init(
            id: UUID = UUID(),
            priorityID: UUID,
            subjectKindRaw: String,
            subject: String,
            reasonRaw: String,
            askedAt: Date,
            outcomeRaw: String,
            answeredAt: Date? = nil
        ) {
            self.id = id
            self.priorityID = priorityID
            self.subjectKindRaw = subjectKindRaw
            self.subject = subject
            self.reasonRaw = reasonRaw
            self.askedAt = askedAt
            self.outcomeRaw = outcomeRaw
            self.answeredAt = answeredAt
        }
    }

    /// **One thing the app said**, with what became of it.
    ///
    /// `localDayKey` is e02's `LocalDay` key — a local day through an injected calendar, never
    /// a UTC day — so a daily cap is a `#Predicate` rather than a scan, and the caps survive a
    /// relaunch because the controller is a pure function of these rows plus a clock reading.
    ///
    /// There is **no causal field** and nowhere for one to be added: no "effectiveness", no
    /// "helped", no streak (R-93, D-01). What the app may record is what it did and what the
    /// person did next, as two facts rather than as one conclusion.
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
        /// `RuleSubjectKind` raw value.
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
            originatingAnswerRaw: String? = nil
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
        }
    }
}

// MARK: - The decoders
//
// Every raw-value column is read through an **exhaustive switch over string literals**, using
// no `RawRepresentable` initialiser anywhere — e03's R-49 doctrine, which `SessionPhase.decode`
// exemplifies and `check-forbidden.sh` enforces for the two phases it names. Writing the cases
// out is what makes the ban total rather than aspirational: a decoder that reached for
// `init(rawValue:)` internally would be the same hazard wearing a sanctioned name.
//
// **Every default is stated, and every one is chosen to make the app quieter rather than
// louder.** A row this build cannot interpret is a row written by a build that knew something
// this one does not, and the honest response to that is to keep the person's peace, not to
// guess in the direction that produces another interruption.

extension RuleSubjectKind {
    /// Unreadable ⇒ `.app`, the widest scope and the baseline one.
    ///
    /// On a receipt the subject kind is part of the ledger key, so a wrong answer here is
    /// either a question the app already asked (silence) or a question asked twice (a defect
    /// U-1 gates at zero). `.app` is the answer that matches more rows, so it errs towards
    /// silence.
    public static func decode(_ raw: String) -> RuleSubjectKind {
        switch raw {
        case "titleToken": .titleToken
        case "domain": .domain
        case "app": .app
        default: .app
        }
    }
}

extension QueryableUncertainty {
    /// Unreadable ⇒ `.noNegativeBasis`, the reason 32 of the corpus's 72 uncertain verdicts
    /// carry (P-138). It affects only what a surface *says about* a question already asked,
    /// never whether one is asked.
    public static func decode(_ raw: String) -> QueryableUncertainty {
        switch raw {
        case "noNegativeBasis": .noNegativeBasis
        case "mixedUseApplication": .mixedUseApplication
        case "languageNotSupported": .languageNotSupported
        default: .noNegativeBasis
        }
    }
}

extension AskedQuestionOutcome {
    /// Unreadable ⇒ `.declined`: the outcome that writes no rule and **still** stops the
    /// question being asked again. A question this build cannot interpret was still asked.
    public static func decode(_ raw: String) -> AskedQuestionOutcome {
        switch raw {
        case "answeredRelevant": .answeredRelevant
        case "answeredUnrelated": .answeredUnrelated
        case "declined": .declined
        case "expired": .expired
        default: .declined
        }
    }
}

extension InterruptionKind {
    /// Unreadable ⇒ `.accusation`.
    ///
    /// Both kinds spend the shared budget, so either answer counts the interruption. Charging
    /// it to the accusation column additionally consumes `dailyAccusationCap`, which means an
    /// unreadable row can never *buy the app extra questions* — and U-1's failure mode is a
    /// barrage of questions, not a shortage of them.
    public static func decode(_ raw: String) -> InterruptionKind {
        switch raw {
        case "query": .query
        case "accusation": .accusation
        default: .accusation
        }
    }
}

extension LadderRung.Kind {
    /// Unreadable ⇒ `.ambient`, the quietest rung. A ladder position this build cannot read
    /// resumes at the silent glyph, which is also where de-escalation always re-enters (R-80).
    ///
    /// **This is also the migration for U-2's scope cut**, and it needs no new code. A row written
    /// by an earlier build with `"recommitment"` falls through to `default` and resumes at the
    /// ambient glyph — which is exactly what the rule above already promised for a rung this build
    /// cannot read, and the quiet direction to fail in. When focus-5ab restores the rung, old rows
    /// start decoding again on their own.
    public static func decode(_ raw: String) -> LadderRung.Kind {
        switch raw {
        case "ambient": .ambient
        case "panel": .panel
        default: .ambient
        }
    }
}

extension NudgeSurface {
    /// Unreadable ⇒ `.menuBar`, the quietest surface.
    public static func decode(_ raw: String) -> NudgeSurface {
        switch raw {
        case "menuBar": .menuBar
        case "panel": .panel
        case "notification": .notification
        case "popoverBadge": .popoverBadge
        default: .menuBar
        }
    }
}

extension InterventionDisposition {
    /// Unreadable ⇒ `.delivered`.
    ///
    /// The opposite direction to every other default here, and deliberately: a row this build
    /// cannot read still happened to somebody, and **counting** it is the answer that cannot
    /// make the app chattier. Reading it as suppressed would free a unit of the day's budget
    /// that a person had already spent.
    public static func decode(_ raw: String) -> InterventionDisposition {
        switch raw {
        case "delivered": .delivered
        case "deferred": .deferred
        case "unopened": .unopened
        case "suppressed": .suppressed
        default: .delivered
        }
    }
}

extension InterventionOutcome {
    /// Unreadable ⇒ `.ignored`: the outcome that writes nothing and counts towards a backoff,
    /// so an unreadable row makes the app quieter rather than louder.
    public static func decode(_ raw: String) -> InterventionOutcome {
        switch raw {
        case "dismissed": .dismissed
        case "corrected": .corrected
        case "snoozed": .snoozed
        case "returned": .returned
        case "pausedSession": .pausedSession
        case "priorityChanged": .priorityChanged
        case "answered": .answered
        case "ignored": .ignored
        default: .ignored
        }
    }
}

extension QueryAnswer {
    /// Unreadable ⇒ `.notNow`, the answer that writes no rule.
    public static func decode(_ raw: String) -> QueryAnswer {
        switch raw {
        case "yesAddIt": .yesAddIt
        case "no": .no
        case "notNow": .notNow
        default: .notNow
        }
    }
}

// MARK: - Typed accessors
//
// Every stored column read through its decoder, and written through its raw value. No call
// site touches a `…Raw` string directly, so the doctrine holds without anybody remembering it.

extension FocusSchemaV4.AskedQuestion {
    public var subjectKind: RuleSubjectKind {
        get { RuleSubjectKind.decode(subjectKindRaw) }
        set { subjectKindRaw = newValue.rawValue }
    }

    public var reason: QueryableUncertainty {
        get { QueryableUncertainty.decode(reasonRaw) }
        set { reasonRaw = newValue.rawValue }
    }

    public var outcome: AskedQuestionOutcome {
        get { AskedQuestionOutcome.decode(outcomeRaw) }
        set { outcomeRaw = newValue.rawValue }
    }
}

extension FocusSchemaV4.InterventionRecord {
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

    /// Whether this row spends a unit of the day's budget. **Only a delivery does** (R-81).
    public var spendsBudget: Bool { disposition == .delivered }
}
