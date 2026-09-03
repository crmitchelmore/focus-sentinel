import Foundation
import SwiftData

/// **A subject History can offer a correction about**, and there is no way to make one from a
/// string.
///
/// `CorrectionScope`'s memberwise initialiser is `fileprivate` and its producers take an
/// `InterventionMandate` or a `QueryWarrant` — the two authorisations — so that no correction can
/// ever name a subject the judgement did not use (R-86). History has neither authorisation: the
/// judgement it is correcting happened hours ago and its authorisation is gone. What it has is
/// the app's own **record** of that judgement, which is the same fact written down.
///
/// So this is the third thing a `CorrectionScope` can be made from, and R-86 is kept in the shape
/// e05 already established for `QueryWarrant`: **`HistorySubject(` appears in exactly one file in
/// the shipping graph** — this one — and `DayHistory.build(…)` is its only caller, which reads
/// every value it makes straight off a stored row. `check-forbidden.sh` asserts that as R-119,
/// the same way R-96a pins the warrant's single producer.
///
/// The initialiser is `public` rather than `internal` because the rendering lane has to build a
/// day without a store: `FocusUI` holds no SwiftData, so a snapshot of the correctable row would
/// otherwise be a snapshot of the withdrawn one. Access control would not have been the guarantee
/// anyway — a second producer inside `FocusCore` would have compiled — so the guarantee is the
/// lint, which is the same reasoning e05 wrote down for the two authorisations.
public struct HistorySubject: Sendable, Equatable, Hashable {
    /// The bundle identifier or normalised `scheme://host[:port]` origin, exactly as filed.
    public let identifier: String
    /// What kind of thing it is, from the stored column rather than re-derived — which is only
    /// honest since focus-tee.2 made that column a fact rather than the literal `app`.
    public let kind: RuleSubjectKind

    public init(identifier: String, kind: RuleSubjectKind) {
        self.identifier = identifier
        self.kind = kind
    }
}

/// **Why an affordance is not being offered**, said out loud rather than by its absence.
///
/// R-88's rule: a button with nowhere to go is a button that lies. History withdraws the
/// correction rather than greying it out silently, and every withdrawal names its reason so the
/// surface can draw a sentence instead of a disabled control nobody can account for.
public enum HistoryWithdrawal: String, Sendable, CaseIterable, Hashable, Codable {
    /// The priority this judgement ran under has been deleted. The rule would have nowhere to be
    /// scoped, and promoting it to a global rule would be the app widening a correction the
    /// person never made (R-88).
    case priorityDeleted
    /// The judgement ran under no priority at all — a suppression at the sensitive-application
    /// gate, which happens before the engine sees a subject.
    case noPriority
    /// An origin subject. An origin judgement is unreplayable — `ActivityEvent` has no origin
    /// column — and before focus-tee.2 it was mis-stored as an application judgement, so a
    /// correction written from one could be about a thing the app never actually judged.
    case originSubject
    /// The row names nobody: a mixed accusation, or a gate-1 suppression. There is no subject to
    /// write a rule about, and inventing one would be the app writing a durable rule about
    /// something the person never pointed at.
    case noSubject
}

/// Whether History may offer *"this was a distraction"* about a row, and if not, why not.
public enum HistoryCorrectability: Sendable, Equatable, Hashable {
    case offered(HistorySubject, priorityID: UUID)
    case withdrawn(HistoryWithdrawal)

    public var isOffered: Bool {
        if case .offered = self { return true }
        return false
    }

    public var withdrawal: HistoryWithdrawal? {
        if case .withdrawn(let reason) = self { return reason }
        return nil
    }
}

/// One thing the app said, as History draws it.
public struct HistoryIntervention: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let at: Date
    public let kind: InterruptionKind
    public let rung: LadderRung.Kind?
    public let subject: String
    public let subjectKind: RuleSubjectKind
    public let surface: NudgeSurface?
    public let disposition: InterventionDisposition
    public let outcome: InterventionOutcome?
    /// Which click wrote the rule this verdict rested on, when one did. The column
    /// `originatingAnswerRaw` has carried since v4 and nothing read until now.
    public let originatingAnswer: QueryAnswer?
    /// The shape of the reason the verdict carried. `nil` for every row written before schema
    /// v7, and for every path that had no explanation to hand — which History says as *"not
    /// recorded"* and never as *"no reasons"*.
    public let explanationKinds: [ExplanationClauseKind]?
    public let priorityID: UUID?

    public init(
        id: UUID,
        at: Date,
        kind: InterruptionKind,
        rung: LadderRung.Kind?,
        subject: String,
        subjectKind: RuleSubjectKind,
        surface: NudgeSurface?,
        disposition: InterventionDisposition,
        outcome: InterventionOutcome?,
        originatingAnswer: QueryAnswer?,
        explanationKinds: [ExplanationClauseKind]?,
        priorityID: UUID?
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.rung = rung
        self.subject = subject
        self.subjectKind = subjectKind
        self.surface = surface
        self.disposition = disposition
        self.outcome = outcome
        self.originatingAnswer = originatingAnswer
        self.explanationKinds = explanationKinds
        self.priorityID = priorityID
    }
}

/// One question the app asked, with the person's own answer and the app's reason for asking.
public struct HistoryQuestion: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let askedAt: Date
    public let answeredAt: Date?
    public let subject: String
    public let subjectKind: RuleSubjectKind
    /// **The app's reason for asking, stored since v4.** The one place in the ledger where the
    /// *why* was written down at the time rather than reconstructed.
    public let reason: QueryableUncertainty
    public let outcome: AskedQuestionOutcome
    public let priorityID: UUID

    public init(
        id: UUID,
        askedAt: Date,
        answeredAt: Date?,
        subject: String,
        subjectKind: RuleSubjectKind,
        reason: QueryableUncertainty,
        outcome: AskedQuestionOutcome,
        priorityID: UUID
    ) {
        self.id = id
        self.askedAt = askedAt
        self.answeredAt = answeredAt
        self.subject = subject
        self.subjectKind = subjectKind
        self.reason = reason
        self.outcome = outcome
        self.priorityID = priorityID
    }
}

/// One session, and the phase changes inside it.
public struct HistorySession: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let kind: SessionKind
    public let phase: SessionPhase
    public let priorityID: UUID?
    /// The phase changes, oldest first, as `(at, from, to)`.
    public let transitions: [HistoryTransition]

    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        kind: SessionKind,
        phase: SessionPhase,
        priorityID: UUID?,
        transitions: [HistoryTransition]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.kind = kind
        self.phase = phase
        self.priorityID = priorityID
        self.transitions = transitions
    }
}

public struct HistoryTransition: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let at: Date
    public let from: SessionPhase
    public let to: SessionPhase

    public init(id: UUID, at: Date, from: SessionPhase, to: SessionPhase) {
        self.id = id
        self.at = at
        self.from = from
        self.to = to
    }
}

/// **An interval the app said nothing about**, and the row D1 exists for.
///
/// A day with no interruption at all must still yield rows carrying *"this was a distraction"* —
/// otherwise the one thing nothing else in the app can do, saying *you were wrong to stay quiet*,
/// would be reachable only on days the app had already spoken.
public struct HistorySilence: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let at: Date
    public let subject: String
    public let subjectKind: RuleSubjectKind
    /// How long it was frontmost, when the observation carried a dwell.
    public let dwellSeconds: Double?
    public let priorityID: UUID?
    public let correction: HistoryCorrectability

    public init(
        id: UUID,
        at: Date,
        subject: String,
        subjectKind: RuleSubjectKind,
        dwellSeconds: Double?,
        priorityID: UUID?,
        correction: HistoryCorrectability
    ) {
        self.id = id
        self.at = at
        self.subject = subject
        self.subjectKind = subjectKind
        self.dwellSeconds = dwellSeconds
        self.priorityID = priorityID
        self.correction = correction
    }
}

/// One row of the day, in the order it happened.
public enum HistoryEntry: Sendable, Equatable, Hashable, Identifiable {
    case intervention(HistoryIntervention)
    case question(HistoryQuestion)
    case session(HistorySession)
    case silence(HistorySilence)

    public var id: UUID {
        switch self {
        case .intervention(let value): value.id
        case .question(let value): value.id
        case .session(let value): value.id
        case .silence(let value): value.id
        }
    }

    /// When it happened. The one ordering key, so four row types make one list.
    public var at: Date {
        switch self {
        case .intervention(let value): value.at
        case .question(let value): value.askedAt
        case .session(let value): value.startedAt
        case .silence(let value): value.at
        }
    }
}

/// **What the app did today and why it said so, row by row** (F-104, focus-tee.5).
///
/// ## What this is not
///
/// It is not a timeline and it is not a scoreboard. There is **no score, no streak, no total
/// distracted time and no per-day tally** anywhere in this type or on the surface that draws it,
/// and there is nowhere for one to be added: ruling D-01 settled that outcome analytics is the
/// sole analytics philosophy, and a count of a person's day is a number they can be judged by
/// whatever it is called. What History has instead is one entry per thing that happened.
///
/// It is also not a replay. Every field here is a **stored** fact — a row the app wrote when it
/// spoke, asked, or observed — never a verdict recomputed today and presented as the reason at
/// the time. The measurement of what replay could and could not reproduce is published in the
/// self-check as `historyReplay`, deliberately outside the gate.
///
/// ## The wording is today's, and the surface says so
///
/// `PriorityTask.revision` counts edits and keeps no prior text, so a priority's words at the
/// moment of a judgement are gone. `priorityWording` is what the store holds **now**, and the
/// surface labels it as such rather than implying the person was told these words at the time.
public struct DayHistory: Sendable, Equatable {
    public let day: LocalDay
    /// The day's rows, **oldest first**. A surface may reverse them; the value keeps the order
    /// the day happened in, because that is the order the causes run in.
    public let entries: [HistoryEntry]
    /// Each priority named by a row, in the wording the store holds **today**.
    public let priorityWording: [UUID: String]

    public init(day: LocalDay, entries: [HistoryEntry], priorityWording: [UUID: String]) {
        self.day = day
        self.entries = entries.sorted { lhs, rhs in
            // A total order: two rows stamped at the same instant — which a corroboration tick
            // produces several at a time — read back in one stable order rather than in whatever
            // order the store felt like.
            (lhs.at, lhs.id.uuidString) < (rhs.at, rhs.id.uuidString)
        }
        self.priorityWording = priorityWording
    }

    /// How many entries of each kind. **For the self-check, never for the surface** — it is
    /// published so a gate can say the ledger is not empty, and drawing it would be the per-day
    /// tally D-01 forbids.
    public var countsByKind: [String: Int] {
        var counts = ["intervention": 0, "question": 0, "session": 0, "silence": 0]
        for entry in entries {
            switch entry {
            case .intervention: counts["intervention", default: 0] += 1
            case .question: counts["question", default: 0] += 1
            case .session: counts["session", default: 0] += 1
            case .silence: counts["silence", default: 0] += 1
            }
        }
        return counts
    }
}

// MARK: - Building it from the stores

extension DayHistory {
    /// Read one local day out of the stores.
    ///
    /// Every store is passed in rather than reached for, so the same function builds the app's
    /// History and the self-check's seeded one. **There is no `QueryLedger` parameter for
    /// writing**: the ledger is read for the day's questions and nothing here can write to it,
    /// which is the structural half of *"a correction is never a re-ask"* (D3).
    @MainActor
    public static func build(
        day: LocalDay,
        log: InterventionLog,
        ledger: QueryLedger,
        events: ActivityEventStore,
        sessions: SessionStore,
        priorities: PriorityStore,
        calendar: Calendar
    ) throws -> DayHistory {
        var entries: [HistoryEntry] = []
        var priorityIDs: Set<UUID> = []

        func isToday(_ instant: Date) -> Bool {
            LocalDay.containing(instant, calendar: calendar) == day
        }

        // --- what the app said ------------------------------------------------------------
        for row in try log.records(on: day) {
            if let priorityID = row.priorityID { priorityIDs.insert(priorityID) }
            entries.append(
                .intervention(
                    HistoryIntervention(
                        id: row.id,
                        at: row.at,
                        kind: row.kind,
                        rung: row.rung,
                        subject: row.subject,
                        subjectKind: row.subjectKind,
                        surface: row.surface,
                        disposition: row.disposition,
                        outcome: row.outcome,
                        originatingAnswer: row.originatingAnswer,
                        explanationKinds: row.explanationKinds,
                        priorityID: row.priorityID
                    )
                )
            )
        }

        // --- what it asked ----------------------------------------------------------------
        for receipt in try ledger.all() where isToday(receipt.askedAt) {
            priorityIDs.insert(receipt.priorityID)
            entries.append(
                .question(
                    HistoryQuestion(
                        id: receipt.id,
                        askedAt: receipt.askedAt,
                        answeredAt: receipt.answeredAt,
                        subject: receipt.subject,
                        subjectKind: receipt.subjectKind,
                        reason: receipt.reason,
                        outcome: receipt.outcome,
                        priorityID: receipt.priorityID
                    )
                )
            )
        }

        // --- the day's sessions -----------------------------------------------------------
        for record in try sessions.sessions(startedOn: day, calendar: calendar) {
            if let taskID = record.taskID { priorityIDs.insert(taskID) }
            entries.append(
                .session(
                    HistorySession(
                        id: record.id,
                        startedAt: record.startedAt,
                        endedAt: record.endedAt,
                        kind: SessionKind.decode(record.kindRaw),
                        phase: record.phase,
                        priorityID: record.taskID,
                        transitions: sessions.transitions(of: record).map {
                            HistoryTransition(
                                id: $0.id,
                                at: $0.at,
                                from: SessionPhase.decode($0.fromRaw),
                                to: SessionPhase.decode($0.toRaw)
                            )
                        }
                    )
                )
            )
        }

        // --- and the intervals it said nothing about --------------------------------------
        //
        // D1's teeth. The rows the app *did not* write are the ones the correction exists for,
        // and a day of perfect silence must still yield them or "you were wrong to stay quiet"
        // would be reachable only on days the app had already spoken.
        //
        // One row per contiguous run of the same subject, so an application somebody returned to
        // twice is two intervals rather than one, and a tick that re-observed the same subject is
        // neither.
        let spoken = Set(
            entries.compactMap { entry -> String? in
                switch entry {
                case .intervention(let value): value.subject
                case .question(let value): value.subject
                case .session, .silence: nil
                }
            }
        )
        var previousSubject: String?
        for row in try events.all() where isToday(row.at) {
            guard ActivityEventKind.decode(row.kindRaw) == .frontmostApplicationChanged,
                  let bundleID = row.bundleID,
                  !bundleID.isEmpty
            else {
                // Anything that is not an application coming forward breaks the run: an idle
                // span between two visits to the same app is two visits, not one.
                previousSubject = nil
                continue
            }
            defer { previousSubject = bundleID }
            guard bundleID != previousSubject else { continue }
            // A subject the app already spoke or asked about today has its own row above, and a
            // second row saying "and here it said nothing" would be the same interval twice.
            guard !spoken.contains(bundleID) else { continue }

            let priorityID = try activePriority(at: row.at, priorities: priorities)
            if let priorityID { priorityIDs.insert(priorityID) }
            entries.append(
                .silence(
                    HistorySilence(
                        id: row.id,
                        at: row.at,
                        subject: bundleID,
                        subjectKind: InterventionLog.subjectKind(of: bundleID),
                        dwellSeconds: row.dwellSeconds,
                        priorityID: priorityID,
                        correction: correctability(
                            subject: bundleID,
                            priorityID: priorityID,
                            priorities: priorities
                        )
                    )
                )
            )
        }

        var wording: [UUID: String] = [:]
        for id in priorityIDs {
            if let task = try priorities.task(id: id) { wording[id] = task.intent }
        }

        return DayHistory(day: day, entries: entries, priorityWording: wording)
    }

    /// **Which commitment an observation ran under**, and the honest answer is "the one that is
    /// active now, if it was already active then".
    ///
    /// The store keeps `ActivePriority` and `PriorityTask.lastActivatedAt` and no history of when
    /// a commitment changed, so an observation before the current activation belongs to a
    /// priority nobody can name. This returns `nil` there rather than attributing the interval to
    /// a commitment the person had not made yet — the same refusal `RelevanceHost` makes when it
    /// declines to infer a task association from the shape of a subject.
    @MainActor
    private static func activePriority(
        at instant: Date,
        priorities: PriorityStore
    ) throws -> UUID? {
        guard let task = try priorities.activeTask() else { return nil }
        guard let activatedAt = task.lastActivatedAt, activatedAt <= instant else { return nil }
        return task.id
    }

    /// Whether *"this was a distraction"* may be offered about one silent interval.
    ///
    /// Four answers and no fifth, and each withdrawal names a reason the surface draws as a
    /// sentence. R-88: a button with nowhere to go is a button that lies.
    @MainActor
    static func correctability(
        subject: String,
        priorityID: UUID?,
        priorities: PriorityStore
    ) -> HistoryCorrectability {
        guard NudgeSubject.nameable(subject) != nil else { return .withdrawn(.noSubject) }
        // An origin judgement is unreplayable and, before focus-tee.2, was mis-stored as an
        // application judgement — so a correction written from one could be about a thing the
        // app never judged. Withdrawn until the origin question is answered, never promoted.
        guard !NudgeSubject.isOrigin(subject) else { return .withdrawn(.originSubject) }
        guard let priorityID else { return .withdrawn(.noPriority) }
        // A deleted priority is the case R-88 is really about. The rule would have nowhere to be
        // scoped, and writing it at `global` instead would be the app widening a correction the
        // person never made.
        guard (try? priorities.task(id: priorityID)) ?? nil != nil else {
            return .withdrawn(.priorityDeleted)
        }
        return .offered(
            HistorySubject(identifier: subject, kind: InterventionLog.subjectKind(of: subject)),
            priorityID: priorityID
        )
    }
}
