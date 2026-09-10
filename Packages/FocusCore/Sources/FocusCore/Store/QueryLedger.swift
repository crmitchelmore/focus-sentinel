import Foundation
import SwiftData

/// What can go wrong when a question is written down.
///
/// Each case is a **caller bug**, not a user-facing condition, and each is thrown rather than
/// swallowed: a ledger that quietly did nothing when asked to record a second receipt would
/// make `nudge.repeatQueryCount == 0` a statement about the store's silence rather than about
/// the app's behaviour.
public enum QueryLedgerError: Error, Equatable, Sendable {
    /// A receipt already exists for `(priorityID, subjectKind, subject)`. Gate 11 of R-84's
    /// suppression stack exists precisely so this never happens, and this is the assertion that
    /// says so when it does.
    case alreadyAsked(subject: String)
    /// An answer that writes a rule was offered with no priority to scope the rule to. A
    /// task-authority rule without a task is not a narrower rule, it is a global one.
    case noPriorityToScopeTo
    /// The priority handed in is not the one the receipt is keyed on. Writing the rule under
    /// one commitment and the receipt under another would leave the app able to learn an answer
    /// and forget the asking — the exact state R-78's transaction exists to make impossible.
    case priorityMismatch
    /// The way the question ended and the outcome the receipt would carry disagree about
    /// whether the asking is over (focus-qds). Gate 11 reads the *stored outcome*, so a receipt
    /// whose row says "settled" written from an ending the policy refused to settle would burn
    /// the question anyway — and one written the other way would re-ask an answered question.
    case endingContradictsOutcome(ending: QuestionEnding, outcome: AskedQuestionOutcome)
}

/// **The record of every question this app has asked, and the reason it is separate from the
/// rules store** (R-78, U-1).
///
/// Answering a question performs **one atomic transaction that writes two records**:
///
/// | record | what it is | authority over | lifetime |
/// |---|---|---|---|
/// | the **rule** — a `ScopedRuleValue` at `RuleAuthority.task` | visible, editable, deletable, undoable | **future classification**: the cascade answers at the `taskRule` rung and no `uncertain` verdict is produced | until the user deletes it or the priority dies |
/// | the **receipt** — an `AskedQuestion` row | invisible, **immutable**, never user-editable | **never-ask-twice**: `isSettled(…)` is consulted *before* any warrant is offered | dies with its priority, and with nothing else |
///
/// ## Why two records and not one
///
/// An earlier draft said answering writes *exactly one thing* — the rule — and that
/// never-ask-twice was a consequence of the cascade. That is elegant and it is wrong in one
/// specific and reachable way: **the rule is deletable by design.** Every learned chip and
/// every Rules-pane row has a remove affordance (R-86) and an undo (F-93). The moment the rule
/// is gone the subject classifies `uncertain` again, a warrant becomes constructible, and the
/// person is asked a question they already answered. U-1 calls that a defect, so it cannot rest
/// on a record one click removes.
///
/// **Deleting the rule does not re-open the question, and that is the humane reading.** Removing
/// a learned chip means "that is not a fact about my work", not "ask me again". After the
/// deletion the subject returns to being uncertain-and-already-asked: silent, unaccused, and
/// available for the person to name themselves from the context pack whenever they choose.
///
/// ## Write-once
///
/// There is **no API on this type that edits or deletes a row except `purge(priorityID:)`**.
/// A receipt is written when a question is resolved — answered, declined or expired — and
/// never touched again. That is what makes it something the never-ask-twice invariant can rest
/// on: an immutable record has no state for a later bug to move.
///
/// ## What a receipt settles, and what it merely records (focus-qds, U-1)
///
/// Immutability is what makes the *settling* row safe, and it is also what made the old reading
/// of these rows dangerous. `hasAsked(…)` was `receipt(…) != nil` — any row, whatever it said —
/// so the row written when somebody went for lunch with a question on screen silenced the
/// subject exactly as hard as an answer did, for the life of the commitment, with no way back.
/// That path had no callers until this epic wired `sessionEnded()`, `phaseLeftFocus()` and
/// `priorityChanged()`, at which point taking a break became the most ordinary way a question
/// ends.
///
/// So the two jobs are separated. **Every asking that reached somebody is written down** — it
/// happened, and `askedCount(…)` and `receipts(priorityID:)` are facts about the day. **Only an
/// outcome the person produced ends the asking**: `AskedQuestionOutcome.settlesTheQuestion`, read
/// by `isSettled(…)`, which is what gate 11 consults. One key may therefore carry several rows,
/// of which at most one settles it, and `refuseIfSettled(…)` is what keeps that "at most one"
/// true.
///
/// ## The key
///
/// `(priorityID, subjectKind, subject)` — **priority**, not session, because U-1 says "for this
/// task". Changing the priority legitimately re-opens every question: a new commitment makes
/// old answers irrelevant. A **revision bump on the same priority id does not**, because
/// editing the wording of a commitment is not making a new one.
@MainActor
public final class QueryLedger {
    private let context: ModelContext
    private let dateProvider: any DateProvider

    /// A hook the atomicity test injects a failure into, between the rule write and the
    /// receipt write.
    ///
    /// Internal rather than public, and `nil` in every shipping path. A transaction whose
    /// atomicity is only asserted by reading the code is a transaction nobody has tested; this
    /// is the seam that lets a test tear it in half and check that neither half survived.
    var failureBetweenWrites: (() throws -> Void)?

    public init(context: ModelContext, dateProvider: some DateProvider = SystemDateProvider()) {
        self.context = context
        self.dateProvider = dateProvider
    }

    /// **How many times anything in this process has written a receipt** (focus-tzj.2).
    ///
    /// Every insert and every purge below bumps it, and this file is the only writer of an
    /// `AskedQuestion` row in the programme. Process-wide rather than per-instance, for
    /// `PriorityStore.mutationCount`'s reason: the question is about the rows.
    public private(set) static var writeCount = 0

    /// Gate 11's last answers, and the write count they were true at.
    ///
    /// **A receipt is immutable and settling is monotone**: a question that has been answered
    /// stays answered until the row is purged, and the only thing that can change an answer here
    /// is a write. So an unchanged `writeCount` is an unchanged verdict, and gate 11 stops being
    /// a store round trip on every five-second corroboration tick — which is what it was, for a
    /// question the app had already decided it would not ask.
    private var settledCache: [SettledKey: Bool] = [:]
    private var settledCacheWrites = 0

    /// The three things gate 11 is a question about.
    private struct SettledKey: Hashable {
        let priorityID: UUID
        let subjectKindRaw: String
        let subject: String
    }

    /// How many gate-11 reads this ledger answered without going to the store.
    public private(set) var settledCacheHits = 0

    /// How long a receipt lives: with its priority, and with nothing else (F-115/F-116).
    public static var retention: NudgeRetentionRule { InterventionPolicy.queryLedgerRetention }

    // MARK: - Reading

    /// **Gate 11 of R-84's suppression stack.** Whether this exact question has been asked for
    /// this priority **and settled**.
    ///
    /// Consulted **before a warrant is constructed**, and it reads the **receipt** — never the
    /// rule. Whatever the person answered, and whether or not the rule that answer wrote still
    /// exists, the question is not asked again.
    ///
    /// ## Why this reads the outcome, and used to not (focus-qds, U-1)
    ///
    /// It was `receipt(…) != nil`: any row at all, whatever it recorded. Under that reading a
    /// receipt written because somebody went to lunch with a question on screen was
    /// indistinguishable from one written because they answered it — and since a receipt is
    /// immutable and this is gate 11, taking a break permanently silenced the subject for the
    /// life of the commitment. That channel became the *ordinary* one the moment
    /// `sessionEnded()`, `phaseLeftFocus()` and `priorityChanged()` acquired callers.
    ///
    /// Never-ask-twice was a promise about **answered** questions, so this asks whether one of
    /// the receipts on file answers it: `AskedQuestionOutcome.settlesTheQuestion`. The asking is
    /// still remembered — `askedCount(…)` and `receipts(priorityID:)` see every row — and the
    /// question comes back, which is what the person was owed.
    public func isSettled(
        priorityID: UUID,
        subjectKind: RuleSubjectKind,
        subject: String
    ) throws -> Bool {
        // **Cached against the write count, never against the clock** (focus-tzj.2). See
        // `settledCache`: the rows this reads are immutable, so the only thing that can move the
        // answer is a write, and a tick is not one.
        if settledCacheWrites != Self.writeCount {
            settledCache.removeAll(keepingCapacity: true)
            settledCacheWrites = Self.writeCount
        }
        let key = SettledKey(
            priorityID: priorityID,
            subjectKindRaw: subjectKind.rawValue,
            subject: subject
        )
        if let cached = settledCache[key] {
            settledCacheHits += 1
            return cached
        }
        let settled = try settledReceipt(
            priorityID: priorityID, subjectKind: subjectKind, subject: subject
        ) != nil
        settledCache[key] = settled
        return settled
    }

    /// Every receipt on file for one question, oldest first.
    ///
    /// **More than one is legal now, and at most one of them settles.** A question the world
    /// interrupted is written down without being settled, so it may legitimately be asked — and
    /// written down — again. `refuseIfSettled(…)` is what keeps the settling row unique.
    public func receipts(
        priorityID: UUID,
        subjectKind: RuleSubjectKind,
        subject: String
    ) throws -> [FocusSchemaV4.AskedQuestion] {
        let kindRaw = subjectKind.rawValue
        let descriptor = FetchDescriptor<FocusSchemaV4.AskedQuestion>(
            predicate: #Predicate {
                $0.priorityID == priorityID
                    && $0.subjectKindRaw == kindRaw
                    && $0.subject == subject
            }
        )
        return try context.countedFetch(descriptor).sorted(by: Self.chronological)
    }

    /// The receipt that **ended** this question, if one has.
    public func settledReceipt(
        priorityID: UUID,
        subjectKind: RuleSubjectKind,
        subject: String
    ) throws -> FocusSchemaV4.AskedQuestion? {
        try receipts(priorityID: priorityID, subjectKind: subjectKind, subject: subject)
            .first { $0.outcome.settlesTheQuestion }
    }

    /// The receipt for one question, if it has been asked.
    ///
    /// The **settling** one when there is one, because that is the row every caller of this
    /// method is actually asking about; otherwise the most recent asking. Picking whichever row
    /// the store returned first would make "what happened to this question?" a different answer
    /// on different runs.
    public func receipt(
        priorityID: UUID,
        subjectKind: RuleSubjectKind,
        subject: String
    ) throws -> FocusSchemaV4.AskedQuestion? {
        let rows = try receipts(
            priorityID: priorityID, subjectKind: subjectKind, subject: subject
        )
        return rows.first { $0.outcome.settlesTheQuestion } ?? rows.last
    }

    /// Every receipt for one priority, oldest first.
    public func receipts(priorityID: UUID) throws -> [FocusSchemaV4.AskedQuestion] {
        let descriptor = FetchDescriptor<FocusSchemaV4.AskedQuestion>(
            predicate: #Predicate { $0.priorityID == priorityID }
        )
        return try context.countedFetch(descriptor).sorted(by: Self.chronological)
    }

    /// Every receipt in the store, oldest first.
    public func all() throws -> [FocusSchemaV4.AskedQuestion] {
        try context.countedFetch(FetchDescriptor<FocusSchemaV4.AskedQuestion>())
            .sorted(by: Self.chronological)
    }

    public func count() throws -> Int {
        try context.countedFetchCount(FetchDescriptor<FocusSchemaV4.AskedQuestion>())
    }

    /// How many questions have been asked for one priority today, in the user's own calendar.
    /// What `dailyQueryCap` reads.
    public func askedCount(priorityID: UUID, on day: LocalDay, calendar: Calendar) throws -> Int {
        try receipts(priorityID: priorityID)
            .count { LocalDay.containing($0.askedAt, calendar: calendar) == day }
    }

    // MARK: - Writing

    /// Record a question that produced **no answer** — "Not now", Escape, an expiry, or a
    /// surface that went out of reach. Those are `QuestionExit`'s whole list; the preemption
    /// this line used to name is not on it, because U-2 deleted the mechanism.
    ///
    /// One row, because there is no answer to record. The asking still happened and is still
    /// remembered, which is what stops the question coming back after a relaunch.
    ///
    /// - Throws: `QueryLedgerError.alreadyAsked` if a receipt already exists. Gate 11 exists so
    ///   that never happens; this is what says so out loud when it does.
    @discardableResult
    public func record(
        priorityID: UUID,
        subjectKind: RuleSubjectKind,
        subject: String,
        reason: QueryableUncertainty,
        outcome: AskedQuestionOutcome,
        askedAt: Date? = nil,
        at instant: Date? = nil
    ) throws -> UUID {
        guard !outcome.wroteRule else {
            // An outcome that writes a rule must go through `answer(…)`, or the two records
            // would not be one transaction.
            throw QueryLedgerError.noPriorityToScopeTo
        }
        try refuseIfSettled(priorityID: priorityID, subjectKind: subjectKind, subject: subject)

        let now = instant ?? dateProvider.now
        let receipt = FocusSchemaV4.AskedQuestion(
            priorityID: priorityID,
            subjectKindRaw: subjectKind.rawValue,
            subject: subject,
            reasonRaw: reason.rawValue,
            askedAt: askedAt ?? now,
            outcomeRaw: outcome.rawValue,
            answeredAt: nil
        )
        context.insert(receipt)
        try context.save()
        Self.writeCount += 1
        return receipt.id
    }

    /// **The only way an unanswered question is ever written down** (U-1, focus-kby).
    ///
    /// `record(…)` above writes whatever it is handed. This asks `QuestionLedgerPolicy` first,
    /// and writes only when the policy says the question reached somebody — so the guard is
    /// inside the object that owns the immutable row rather than being an `if` in a caller no
    /// test can import. A host that wants to record an expiry or an out-of-reach surface has to say which
    /// surface carried the question and what that surface could be proven to show, and if it
    /// cannot prove it, nothing is written and the question stays askable.
    ///
    /// - Returns: what was decided, so the caller can log the refusal rather than guess at it.
    ///   `.writeReceipt` means a row was inserted.
    @discardableResult
    public func recordResolution(
        priorityID: UUID,
        subjectKind: RuleSubjectKind,
        subject: String,
        reason: QueryableUncertainty,
        outcome: AskedQuestionOutcome,
        askedAt: Date? = nil,
        at instant: Date? = nil,
        surface: NudgeSurface?,
        readingAtAsk: SurfaceReadability,
        readingNow: SurfaceReadability,
        ending: QuestionEnding
    ) throws -> QuestionLedgerAction {
        let action = QuestionLedgerPolicy.decide(
            surface: surface,
            readingAtAsk: readingAtAsk,
            readingNow: readingNow,
            ending: ending
        )
        guard action.writesAReceipt else { return action }
        // **The row and the ruling must agree** (focus-qds). Gate 11 reads the stored outcome,
        // not the code path that produced it, so a caller that ended a question one way and
        // labelled the receipt another would settle a question the policy just refused to settle
        // — or the reverse. That is a caller bug and it is thrown, in the shape every other error
        // on this type has.
        guard action.settlesTheQuestion == outcome.settlesTheQuestion else {
            throw QueryLedgerError.endingContradictsOutcome(
                ending: ending, outcome: outcome
            )
        }

        try record(
            priorityID: priorityID,
            subjectKind: subjectKind,
            subject: subject,
            reason: reason,
            outcome: outcome,
            askedAt: askedAt,
            at: instant
        )
        return action
    }

    /// **R-78's atomic answer.** Either both rows commit or neither does.
    ///
    /// "Yes, add it" and "No" each write a `RuleAuthority.task` rule *and* an immutable
    /// receipt; "Not now" writes the receipt alone, because there is no answer to record. The
    /// two inserts share one `ModelContext` and one `save()`, and a failure anywhere between
    /// them rolls the context back — so there is no interval in which the app has learned the
    /// answer but forgotten the asking, or vice versa.
    ///
    /// - Parameters:
    ///   - answer: what the person clicked. Escape is `.notNow`.
    ///   - priorityID: the ledger key's first component.
    ///   - task: the priority row the rule is scoped to. Required for an answer that writes a
    ///     rule; ignored for "Not now".
    ///   - scope: the subject, derived from the warrant by `CorrectionScope.from(_:)`, so a
    ///     correction can never name a subject the judgement did not use.
    ///   - reason: which answerable uncertainty produced the question.
    ///   - askedAt: when the question went on screen. Defaults to now, for a question answered
    ///     the instant it appeared.
    /// - Returns: the typed description of what was written.
    /// - Throws: `QueryLedgerError`, or whatever the store throws.
    @discardableResult
    public func answer(
        _ answer: QueryAnswer,
        priorityID: UUID,
        task: FocusSchemaV3.PriorityTask?,
        scope: CorrectionScope,
        reason: QueryableUncertainty,
        askedAt: Date? = nil,
        at instant: Date? = nil,
        ruleID: UUID = UUID()
    ) throws -> CorrectionOutcome {
        // Refused only when an **answer** is already on file. A question the world interrupted
        // left an unsettled receipt behind and legitimately came back; answering it now is the
        // whole point, and it writes the settling row beside the record of the earlier asking
        // (focus-qds).
        try refuseIfSettled(
            priorityID: priorityID, subjectKind: scope.kind, subject: scope.subject
        )

        let now = instant ?? dateProvider.now
        let outcome = answer.outcome(scope: scope, at: now, id: ruleID)

        // Everything this transaction inserted, so a failure can withdraw exactly those rows
        // and nothing else.
        //
        // Deliberately **not** `ModelContext.rollback()`. That discards every unsaved change in
        // the context and destroys the caller's live model instances with it — a ledger whose
        // failure path invalidates the priority object the host is holding has traded one bug
        // for a worse one. Withdrawing the rows this function inserted is the narrower and
        // truer statement of "neither row commits".
        var inserted: [any PersistentModel] = []

        if let rule = outcome.persistedRule {
            guard let task else { throw QueryLedgerError.noPriorityToScopeTo }
            guard task.id == priorityID else { throw QueryLedgerError.priorityMismatch }

            let row = FocusSchemaV3.RelevanceRule(
                id: rule.id,
                scopeRaw: rule.subjectKind.rawValue,
                subject: rule.subject,
                verdictRaw: rule.verdict.rawValue,
                createdAt: rule.createdAt,
                task: task
            )
            context.insert(row)
            inserted.append(row)
        }

        do {
            // The seam the atomicity test tears the transaction in half at. `nil` in every
            // shipping path.
            try failureBetweenWrites?()

            let receipt = FocusSchemaV4.AskedQuestion(
                priorityID: priorityID,
                subjectKindRaw: scope.kind.rawValue,
                subject: scope.subject,
                reasonRaw: reason.rawValue,
                askedAt: askedAt ?? now,
                outcomeRaw: answer.outcome.rawValue,
                answeredAt: now
            )
            context.insert(receipt)
            inserted.append(receipt)
            try context.save()
            Self.writeCount += 1
        } catch {
            for row in inserted { context.delete(row) }
            // Best effort: the rows were never saved, so the store already agrees. This makes
            // the in-memory context agree too, and a second failure here must not mask the
            // first — the original error is what the caller needs to see.
            try? context.save()
            throw error
        }

        return outcome
    }

    // MARK: - Retention (F-115, F-116)

    /// Delete every receipt for one priority. **The only route by which a row is ever
    /// removed**, and the reason the type can otherwise claim to be write-once.
    ///
    /// Called when a priority is deleted. The key is a plain `UUID` rather than a relationship
    /// precisely so this is one predicate rather than a cascade the store performs for us.
    @discardableResult
    public func purge(priorityID: UUID) throws -> Int {
        let doomed = try receipts(priorityID: priorityID)
        for receipt in doomed { context.delete(receipt) }
        if !doomed.isEmpty {
            try context.save()
            Self.writeCount += 1
        }
        return doomed.count
    }

    /// F-116's delete-everything path.
    @discardableResult
    public func purgeAll() throws -> Int {
        let doomed = try all()
        for receipt in doomed { context.delete(receipt) }
        if !doomed.isEmpty {
            try context.save()
            Self.writeCount += 1
        }
        return doomed.count
    }

    /// **Delete the old receipts of priorities that are themselves old** (focus-tzj.3, F-115).
    ///
    /// ## Why this is not `purge(before:)`
    ///
    /// A receipt is the never-ask-twice memory: gate 11 reads it, and deleting one puts a
    /// question the person has already answered back on the ladder. A retention window is a
    /// promise about how long the app *remembers a day*, and it must not become a mechanism for
    /// re-asking. So age alone is not enough — a receipt written ninety-one days ago about the
    /// commitment somebody is working on **this morning** stays, because that priority is still
    /// live and the promise made about it was permanent.
    ///
    /// Both conditions, therefore: the row is older than the window **and** the priority it
    /// belongs to is not in `livingPriorityIDs`. The caller decides what "living" means —
    /// `RetentionSweep` counts a priority as living if it was created or last activated inside
    /// the same window — which keeps this function a set operation rather than a second opinion
    /// about a table it does not own.
    ///
    /// - Returns: how many receipts went.
    @discardableResult
    public func purge(before cutoff: Date, livingPriorityIDs: Set<UUID>) throws -> Int {
        let doomed = try all().filter {
            $0.askedAt < cutoff && !livingPriorityIDs.contains($0.priorityID)
        }
        for receipt in doomed { context.delete(receipt) }
        if !doomed.isEmpty {
            try context.save()
            Self.writeCount += 1
        }
        return doomed.count
    }

    /// Delete every receipt whose priority no longer exists.
    ///
    /// The completeness half of the retention contract: a row whose priority was deleted by a
    /// path that forgot to call `purge(priorityID:)` is a row that would outlive the commitment
    /// it was about, and F-115's promise is that it does not.
    @discardableResult
    public func purgeOrphans(livingPriorityIDs: Set<UUID>) throws -> Int {
        let doomed = try all().filter { !livingPriorityIDs.contains($0.priorityID) }
        for receipt in doomed { context.delete(receipt) }
        if !doomed.isEmpty {
            try context.save()
            Self.writeCount += 1
        }
        return doomed.count
    }

    // MARK: - Helpers

    /// Refuse a second **settling** receipt for one question.
    ///
    /// The uniqueness the never-ask-twice invariant needs is uniqueness of the *answer*, not of
    /// the row: a question that expired unanswered is written down and asked again, so a key
    /// may legitimately carry several rows of which at most one settles it (focus-qds).
    private func refuseIfSettled(
        priorityID: UUID,
        subjectKind: RuleSubjectKind,
        subject: String
    ) throws {
        if try isSettled(priorityID: priorityID, subjectKind: subjectKind, subject: subject) {
            throw QueryLedgerError.alreadyAsked(subject: subject)
        }
    }

    /// Oldest first, tie-broken by identifier so two receipts stamped at the same instant read
    /// back in one stable order rather than in whatever order the store felt like.
    private static func chronological(
        _ lhs: FocusSchemaV4.AskedQuestion,
        _ rhs: FocusSchemaV4.AskedQuestion
    ) -> Bool {
        lhs.askedAt == rhs.askedAt
            ? lhs.id.uuidString < rhs.id.uuidString
            : lhs.askedAt < rhs.askedAt
    }
}
