import Foundation
import SwiftData

/// What `SessionStore` can refuse to do.
///
/// Named refusals, for the same reason `PriorityStoreError`'s are named: a facade that throws
/// "something went wrong" is a facade whose caller has to guess.
public enum SessionStoreError: Error, Sendable, Equatable, Hashable {
    /// There is no open session to offer this event to. Starting one is not an event on an
    /// existing state — it *creates* one — so this is a caller mistake rather than a rejection.
    case noOpenSession
    /// No `FocusSessionRecord` with that identifier is in the store.
    case sessionNotFound(UUID)
    /// A session is already open. There is one at a time, for the same reason there is one
    /// priority at a time.
    case sessionAlreadyOpen(UUID)
}

extension SessionStoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noOpenSession: "There is no open focus session"
        case .sessionNotFound(let id): "No focus session with id \(id)"
        case .sessionAlreadyOpen(let id): "A focus session is already open (\(id))"
        }
    }
}

/// The single mutation facade for the session runtime.
///
/// ## What it is, in one line
///
/// A thin, `@MainActor` shell around `SessionMachine` — which is pure — that persists what the
/// machine accepted and **nothing** of what it rejected.
///
/// ## The three things it is careful about
///
/// **Rejected transitions write nothing at all.** Not a row saying "somebody tried", not a log
/// line in the timeline. A timeline that records what a caller attempted rather than what
/// happened is a timeline that lies to the person reading it, and a rejection means what they
/// asked for was already true.
///
/// **The two cause-set outcomes are recorded, and are distinguishable.** A `causeAdded` or
/// `causeRemoved` row carries `fromRaw == toRaw` and its own `outcomeRaw`, and it does **not**
/// move `phaseChangedAt` — because it is not a phase change, and pretending it was one would
/// restart the staleness clock every time the screen locked.
///
/// **Only user-initiated operations are undoable.** An auto-pause is not something a person
/// meant to do, and offering to undo it would be offering to undo the world. `SessionEvent`
/// answers this itself through `isUserInitiated`, so the rule is one line here rather than a
/// judgement at each call site.
///
/// ## Why the anchor is written on every phase change
///
/// `uptimeAnchorSeconds` and `bootIdentity` are stamped whenever `phaseChangedAt` moves,
/// because they are a fact *about that instant*: the reconciler compares the wall-clock and
/// uptime views of the **current phase**, and an anchor from three phases ago would be
/// comparing two different intervals. The two travel together and are written together.
///
/// ## Why there is no timer
///
/// There is none anywhere in this programme. Every elapsed figure is computed on demand from
/// `startedAt` and an injected wall clock, which is the strongest available form of the Court's
/// condition that a restored session must never blindly restart its timer.
@MainActor
public final class SessionStore {
    private let context: ModelContext
    private let dateProvider: any DateProvider
    private let uptimeClock: any UptimeClock
    private let bootIdentity: String

    /// - Parameters:
    ///   - uptimeClock: seconds since boot, from `FocusSensing`'s `mach_continuous_time`
    ///     implementation. **Not** `MonotonicClock`, whose origin is per-process and could
    ///     never span two launches.
    ///   - bootIdentity: `"<kern.boottime.sec>.<usec>"`, likewise from `FocusSensing`. Passed
    ///     in as a `String` so that `FocusCore`'s import row stays three words long.
    public init(
        context: ModelContext,
        dateProvider: some DateProvider = SystemDateProvider(),
        uptimeClock: some UptimeClock = TestUptimeClock(),
        bootIdentity: String = ""
    ) {
        self.context = context
        self.dateProvider = dateProvider
        self.uptimeClock = uptimeClock
        self.bootIdentity = bootIdentity
    }

    // MARK: - Reads

    /// The session that is still running, if there is one.
    ///
    /// "Open" means `endedAt == nil`. Newest first, so a store that somehow acquired two open
    /// rows converges on the later one instead of flip-flopping — the same convergence rule the
    /// settings row uses, and for the same reason.
    public func openSession() throws -> FocusSchemaV3.FocusSessionRecord? {
        var descriptor = FetchDescriptor<FocusSchemaV3.FocusSessionRecord>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func session(id: UUID) throws -> FocusSchemaV3.FocusSessionRecord? {
        let descriptor = FetchDescriptor<FocusSchemaV3.FocusSessionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// Every transition of one session, oldest first.
    ///
    /// Ordered by `at` and then by insertion, so two transitions stamped at the same instant —
    /// which the "end the detour, then start the break" path produces — read back in the order
    /// they happened rather than in whatever order the store felt like.
    public func transitions(of record: FocusSchemaV3.FocusSessionRecord) -> [FocusSchemaV3.SessionTransitionRecord] {
        record.transitions.sorted { lhs, rhs in
            if lhs.at != rhs.at { return lhs.at < rhs.at }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// The machine's view of a stored row.
    ///
    /// `phaseChangedAt` falls back to `startedAt` for a row written before the column existed:
    /// a v1 session's phase last changed when it began, which is the truth rather than a
    /// default.
    public func state(of record: FocusSchemaV3.FocusSessionRecord) -> SessionState {
        SessionState(
            phase: record.phase,
            pauseCauses: record.pauseCauses,
            resumeTo: record.resumeTo,
            phaseChangedAt: record.phaseChangedAt ?? record.startedAt,
            endedAt: record.endedAt
        )
    }

    /// The whole of a session as a value a surface can render. Carries no clock: every elapsed
    /// figure is a function of an injected `now`.
    public func snapshot(of record: FocusSchemaV3.FocusSessionRecord) -> SessionSnapshot {
        SessionSnapshot(
            sessionID: record.id,
            taskID: record.taskID,
            phase: record.phase,
            pauseCauses: record.pauseCauses,
            resumeTo: record.resumeTo,
            kind: SessionKind.decode(record.kindRaw),
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            plannedSeconds: record.plannedSeconds,
            deadlineAt: record.deadlineAt,
            notes: restorationNotes
        )
    }

    /// The open session as a snapshot, or `nil` when there is none.
    public func openSnapshot() throws -> SessionSnapshot? {
        try openSession().map(snapshot(of:))
    }

    /// What the last `restore()` had to say. Carried on every snapshot until the session ends,
    /// so the cockpit can show "the clock changed while this ran" for as long as it is true.
    public private(set) var restorationNotes: Set<RestoredSession.ReconciliationNote> = []

    // MARK: - Starting

    /// Begin a session. **User-initiated**, therefore undoable.
    ///
    /// Starting is not an event on an existing state — it produces the first one, in `.focus`.
    /// That is why there are eight events and not nine.
    @discardableResult
    public func start(
        taskID: UUID? = nil,
        kind: SessionKind = .openEnded,
        plannedSeconds: Int? = nil,
        deadlineAt: Date? = nil,
        undo: UndoManager? = nil,
        actionName: String? = nil
    ) throws -> UUID {
        if let open = try openSession() {
            throw SessionStoreError.sessionAlreadyOpen(open.id)
        }

        let now = dateProvider.now
        let newID = UUID()

        try journal(undo: undo, actionName: actionName, undoable: true) {
            let record = FocusSchemaV3.FocusSessionRecord(
                id: newID,
                taskID: taskID,
                startedAt: now,
                phaseRaw: SessionPhase.focus.rawValue,
                phaseChangedAt: now,
                kindRaw: kind.rawValue,
                plannedSeconds: plannedSeconds,
                deadlineAt: deadlineAt,
                uptimeAnchorSeconds: uptimeClock.uptimeSeconds,
                bootIdentity: bootIdentity.isEmpty ? nil : bootIdentity
            )
            context.insert(record)
        } inverse: { store, undo in
            try? store.deleteSession(id: newID, undo: undo)
        }

        restorationNotes = []
        return newID
    }

    /// The inverse of `start`: the row goes, and with it its transitions, by cascade.
    private func deleteSession(id: UUID, undo: UndoManager?) throws {
        guard let record = try session(id: id) else { throw SessionStoreError.sessionNotFound(id) }
        try journal(undo: undo, actionName: nil, undoable: true) {
            context.delete(record)
        } inverse: { _, _ in
            // Deliberately terminal. Re-creating a deleted session would mean re-creating its
            // whole transition log from values captured before the delete, and a redo that
            // restored a session with a *different* history would be worse than no redo at
            // all. Undo of a start is a start that never happened.
        }
    }

    // MARK: - Applying an event

    /// Offer an event to the open session.
    ///
    /// The machine decides; this persists what it accepted. A rejection is returned as a value
    /// and writes nothing — the caller records it and the UI does nothing, because a rejected
    /// transition means what the user asked for was already true.
    @discardableResult
    public func apply(
        _ event: SessionEvent,
        undo: UndoManager? = nil,
        actionName: String? = nil
    ) throws -> SessionTransition {
        guard let record = try openSession() else { throw SessionStoreError.noOpenSession }
        return try apply(event, to: record, undo: undo, actionName: actionName)
    }

    @discardableResult
    public func apply(
        _ event: SessionEvent,
        to record: FocusSchemaV3.FocusSessionRecord,
        undo: UndoManager? = nil,
        actionName: String? = nil
    ) throws -> SessionTransition {
        let now = dateProvider.now
        let transition = SessionMachine.apply(event, to: state(of: record), at: now)

        switch transition {
        case .rejected:
            // Nothing is written. Not a row, not a timestamp, not a log line.
            return transition

        case .accepted(let next, let value), .causeChanged(let next, let value):
            try write(next, value, to: record, undoable: event.isUserInitiated, undo: undo, actionName: actionName)
            return transition
        }
    }

    /// Persist one accepted outcome, and register its inverse when a person asked for it.
    ///
    /// `alsoMutating` exists for one caller: interrupting writes the phase change **and** the
    /// three capture fields, and it must be **one** undo entry. A person who presses Stop, fills
    /// in a note and then presses ⌘Z expects one undo to take them back to where they were, not
    /// two — the same ruling e02 made for capturing a priority.
    private func write(
        _ next: SessionState,
        _ value: SessionTransitionValue,
        to record: FocusSchemaV3.FocusSessionRecord,
        undoable: Bool,
        undo: UndoManager?,
        actionName: String?,
        alsoMutating alsoMutate: (@MainActor (FocusSchemaV3.FocusSessionRecord) -> Void)? = nil
    ) throws {
        let sessionID = record.id
        let before = StoredPhase(record)
        let transitionID = UUID()

        try journal(undo: undo, actionName: actionName, undoable: undoable) {
            record.phase = next.phase
            record.pauseCauses = next.pauseCauses
            record.resumeTo = next.resumeTo

            if value.changesPhase {
                // A phase change moves the clock and re-stamps the anchor, because the anchor
                // is a fact about *this* phase's start. A cause-set change moves neither.
                record.phaseChangedAt = value.at
                record.uptimeAnchorSeconds = uptimeClock.uptimeSeconds
                record.bootIdentity = bootIdentity.isEmpty ? nil : bootIdentity
            }

            // Terminal is where the row closes. `endedAt` is the store's act rather than the
            // machine's — the machine treats it as an input it respects and never assigns —
            // and it happens in the same save as the terminal transition record, so a session
            // can never be found terminal-but-open.
            if next.phase.isTerminal {
                record.endedAt = value.at
            }

            let row = FocusSchemaV3.SessionTransitionRecord(
                id: transitionID,
                at: value.at,
                fromRaw: value.from.rawValue,
                toRaw: value.to.rawValue,
                eventRaw: value.event.rawValue,
                reasonRaw: value.reasonRaw,
                outcomeRaw: value.outcome.rawValue,
                session: record
            )
            context.insert(row)
            alsoMutate?(record)
        } inverse: { store, undo in
            try? store.revert(sessionID: sessionID, to: before, transitionID: transitionID, undo: undo)
        }
    }

    /// The undoable slice of a session row, captured as **plain values** before a mutation.
    ///
    /// Plain values rather than a reference, because e02's journal ruling is that a reference
    /// to a row that is about to change is a trap — and here it would also be a reference to a
    /// row whose relationship is about to gain a child.
    ///
    /// It carries the interruption capture as well as the phase, so that one undo of Stop puts
    /// back both the phase and the words the person typed. `startedAt` is deliberately **not**
    /// here: it is never rewritten, so there is nothing to put back.
    private struct StoredPhase {
        let phaseRaw: String
        let phaseChangedAt: Date?
        let resumeToRaw: String?
        let pauseCausesRaw: String?
        let uptimeAnchorSeconds: Double?
        let bootIdentity: String?
        let endedAt: Date?
        let interruptionReasonRaw: String?
        let restartPointNote: String?
        let lastActiveBundleID: String?

        init(_ record: FocusSchemaV3.FocusSessionRecord) {
            self.phaseRaw = record.phaseRaw
            self.phaseChangedAt = record.phaseChangedAt
            self.resumeToRaw = record.resumeToRaw
            self.pauseCausesRaw = record.pauseCausesRaw
            self.uptimeAnchorSeconds = record.uptimeAnchorSeconds
            self.bootIdentity = record.bootIdentity
            self.endedAt = record.endedAt
            self.interruptionReasonRaw = record.interruptionReasonRaw
            self.restartPointNote = record.restartPointNote
            self.lastActiveBundleID = record.lastActiveBundleID
        }

        @MainActor
        func apply(to record: FocusSchemaV3.FocusSessionRecord) {
            record.phaseRaw = phaseRaw
            record.phaseChangedAt = phaseChangedAt
            record.resumeToRaw = resumeToRaw
            record.pauseCausesRaw = pauseCausesRaw
            record.uptimeAnchorSeconds = uptimeAnchorSeconds
            record.bootIdentity = bootIdentity
            record.endedAt = endedAt
            record.interruptionReasonRaw = interruptionReasonRaw
            record.restartPointNote = restartPointNote
            record.lastActiveBundleID = lastActiveBundleID
        }
    }

    /// Put a session back exactly as it was, and take the transition row with it.
    ///
    /// Removing the row is the point: undo is not another thing that happened, so leaving the
    /// transition in the log would make the timeline claim a pause the person took back.
    private func revert(
        sessionID: UUID,
        to before: StoredPhase,
        transitionID: UUID,
        undo: UndoManager?
    ) throws {
        guard let record = try session(id: sessionID) else {
            throw SessionStoreError.sessionNotFound(sessionID)
        }
        let after = StoredPhase(record)

        try journal(undo: undo, actionName: nil, undoable: true) {
            before.apply(to: record)

            if let row = record.transitions.first(where: { $0.id == transitionID }) {
                context.delete(row)
            }
        } inverse: { store, undo in
            // Redo is free: performing the inverse registers the original in its turn. The
            // transition row is not resurrected, because its identity died with it; what redo
            // restores is the *state*, which is what the person is looking at.
            try? store.revert(sessionID: sessionID, to: after, transitionID: UUID(), undo: undo)
        }
    }

    // MARK: - The two terminal verbs

    /// Stop a session and capture why (F-101). **User-initiated**, therefore undoable.
    ///
    /// The last-active context is a **bundle identifier and nothing else** — never a window
    /// title, never a document. The reason picker and the restart-point note are the person's
    /// own words, both optional, and Complete is enabled with every field empty: reflection is
    /// offered, never extracted.
    @discardableResult
    public func interrupt(
        reason: InterruptionReason = .user,
        note: String? = nil,
        lastActiveBundleID: String? = nil,
        undo: UndoManager? = nil,
        actionName: String? = nil
    ) throws -> SessionTransition {
        guard let record = try openSession() else { throw SessionStoreError.noOpenSession }

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedNote = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote

        let now = dateProvider.now
        let transition = SessionMachine.apply(
            .interrupted(reason: reason),
            to: state(of: record),
            at: now
        )
        guard case .accepted(let next, let value) = transition else { return transition }

        // One journal entry for the phase change **and** the capture: one Stop, one ⌘Z.
        try write(
            next,
            value,
            to: record,
            undoable: true,
            undo: undo,
            actionName: actionName
        ) { record in
            record.interruptionReasonRaw = reason.rawValue
            record.restartPointNote = storedNote
            // A bundle identifier and nothing else — never a window title, never a document.
            record.lastActiveBundleID = lastActiveBundleID
        }

        return transition
    }

    /// Finish a session. **User-initiated**, therefore undoable.
    @discardableResult
    public func complete(
        undo: UndoManager? = nil,
        actionName: String? = nil
    ) throws -> SessionTransition {
        guard let record = try openSession() else { throw SessionStoreError.noOpenSession }
        return try apply(.completed, to: record, undo: undo, actionName: actionName)
    }

    // MARK: - Restoration (F-97)

    /// Reconcile the stored session against the world as it is now, and persist the result.
    ///
    /// `startedAt` is **never** rewritten — not here, not anywhere. What may change is the
    /// phase and the cause set, and only in the two cases the reconciler names: a different
    /// boot identity, and more than `staleAfter` since the last phase change.
    ///
    /// No timer is started, because there is none to start.
    @discardableResult
    public func restore(
        staleAfter: Duration = SessionRestoration.defaultStaleAfter,
        driftTolerance: Duration = SessionRestoration.defaultDriftTolerance
    ) throws -> RestoredSession? {
        guard let record = try openSession() else {
            restorationNotes = []
            return nil
        }

        let startedAt = record.startedAt
        let restored = SessionRestoration.reconcile(
            record: SessionRestoration.StoredSession(
                sessionID: record.id,
                startedAt: startedAt,
                endedAt: record.endedAt,
                phase: record.phase,
                phaseChangedAt: record.phaseChangedAt ?? startedAt,
                resumeTo: record.resumeTo,
                pauseCauses: record.pauseCauses,
                uptimeAnchorSeconds: record.uptimeAnchorSeconds,
                bootIdentity: record.bootIdentity
            ),
            now: dateProvider.now,
            nowUptimeSeconds: uptimeClock.uptimeSeconds,
            bootIdentity: bootIdentity,
            staleAfter: staleAfter,
            driftTolerance: driftTolerance
        )

        restorationNotes = restored.notes

        // The reconciler is pure and does not know what was on disk; only actually-changed
        // fields are written, so a fresh relaunch touches nothing at all.
        let phaseChanged = record.phase != restored.phase
            || record.pauseCauses != restored.pauseCauses
            || record.resumeTo != restored.resumeTo

        guard phaseChanged else { return restored }

        let previous = record.phase
        record.phase = restored.phase
        record.pauseCauses = restored.pauseCauses
        record.resumeTo = restored.resumeTo
        // The anchor now belongs to this launch, whatever it belonged to before — which is
        // exactly what makes a reboot's discarded anchor stop being compared against.
        record.uptimeAnchorSeconds = uptimeClock.uptimeSeconds
        record.bootIdentity = bootIdentity.isEmpty ? nil : bootIdentity

        // One row per restoration pause, carrying the cause a single matching `resumed(cause:)`
        // will clear. A restoration is emphatically **not** undoable: it is the app catching
        // up with the world, not something a person did.
        // Which cause the restoration itself added, read off the notes rather than by
        // differencing two sets — the session may have been holding causes of its own before
        // the relaunch, and it comes back holding those **and** this one. A reboot wins over
        // staleness, exactly as the reconciler decides it.
        let cause: PauseReason? = if restored.notes.contains(.rebootedDuringSession) {
            .systemRestart
        } else if restored.notes.contains(.restoredStale) {
            .relaunch
        } else {
            nil
        }

        context.insert(
            FocusSchemaV3.SessionTransitionRecord(
                at: dateProvider.now,
                fromRaw: previous.rawValue,
                toRaw: restored.phase.rawValue,
                eventRaw: SessionEventKind.paused.rawValue,
                reasonRaw: cause?.rawValue,
                outcomeRaw: SessionTransitionOutcome.accepted.rawValue,
                session: record
            )
        )
        try context.save()
        return restored
    }

    // MARK: - The journal

    /// Open a group, mutate, save, and register the inverse when the operation was a person's.
    ///
    /// The grouping lives here rather than at the call site so that the identical code is
    /// correct in the app (`groupsByEvent == true`) and in a headless test (`false`, where an
    /// unwrapped registration raises `NSInternalInconsistencyException`).
    ///
    /// ## Why the action name arrives as a parameter
    ///
    /// `FocusCore` owns no user-visible text (R-52): the session machine returns typed values
    /// and the labels for them live in `FocusUI`, where every other string a person can read
    /// lives. So the host passes an already-localised name down rather than this package
    /// growing a catalog key for the Edit menu. `nil` is a perfectly good answer and leaves the
    /// menu item reading plain "Undo".
    ///
    /// ## Why `undoable` is a parameter rather than a rule remembered here
    ///
    /// Because the answer belongs to the event: `SessionEvent.isUserInitiated` knows that a
    /// `.user` pause is a person's act and a `.screenLocked` one is the world's. A store that
    /// re-derived it would be a second place to get it wrong.
    private func journal(
        undo: UndoManager?,
        actionName: String?,
        undoable: Bool,
        mutate: () throws -> Void,
        inverse: @escaping @MainActor (SessionStore, UndoManager?) -> Void
    ) throws {
        let manager = undoable ? undo : nil
        manager?.beginUndoGrouping()
        defer { manager?.endUndoGrouping() }
        if let actionName { manager?.setActionName(actionName) }

        try mutate()
        try context.save()

        manager?.registerUndo(withTarget: self) { store in
            // `UndoManager` runs a registered handler synchronously on the thread that called
            // `undo()`, and the only caller is the responder chain's Edit ▸ Undo, on main.
            MainActor.assumeIsolated {
                inverse(store, manager)
            }
        }
    }
}
