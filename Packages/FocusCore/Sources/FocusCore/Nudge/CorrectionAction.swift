import Foundation

/// **What a correction will be about**, derived from the evidence the judgement actually used.
///
/// "Evidence actually available" is a *type*, not a comment (R-86). There is no initialiser a
/// call site can reach: the memberwise one is `fileprivate` and the only two producers take an
/// `InterventionMandate` or a `QueryWarrant` — the two authorisations — and read the subject
/// out of them. **There is no path by which a correction names a subject the judgement did not
/// use**, and `CorrectionScopeTests` asserts that over every shape the two authorisations can
/// take rather than trusting the sentence.
///
/// The scope is app-wide at baseline and the copy says so ("Answering adds it for this whole
/// app"). e07's origin signal makes `.domain` reachable with no change to this type, to the
/// query, to the ledger or to the metric — only a different `RuleSubjectKind` flowing through
/// the same values.
public struct CorrectionScope: Sendable, Equatable, Hashable {
    /// How narrow the rule will be.
    public let kind: RuleSubjectKind
    /// The bundle identifier or normalised `scheme://host[:port]` origin. Never empty.
    public let subject: String

    /// **Fileprivate on purpose**, with exactly two callers, both in this file.
    fileprivate init(kind: RuleSubjectKind, subject: String) {
        self.kind = kind
        self.subject = subject
    }

    /// The scope a correction on an **accusation** writes.
    ///
    /// `nil` when the mandate is mixed: drift across several unrelated applications has no
    /// single subject, so "this is relevant" has nothing to be about and the surface does not
    /// offer it. Inventing one — taking the last application, say — would be the app writing a
    /// durable rule about something the person never pointed at.
    public static func from(_ mandate: InterventionMandate) -> CorrectionScope? {
        guard !mandate.isMixed else { return nil }
        guard let subject = nameable(mandate.subject) else { return nil }
        return CorrectionScope(kind: kind(of: subject), subject: subject)
    }

    /// The scope a correction on a **question** writes.
    ///
    /// Never optional: a `QueryWarrant` cannot exist without a single nameable subject —
    /// `QuerySubject` has no mixed case and `QueryEligibility.decide(…)` withholds with
    /// `.noSingleSubject` rather than producing one — so the answer is already decided by the
    /// time anybody can click a button.
    public static func from(_ warrant: QueryWarrant) -> CorrectionScope {
        CorrectionScope(kind: warrant.subject.kind, subject: warrant.subject.identifier)
    }

    /// The rule this scope writes at the given verdict.
    ///
    /// One function, so that every correction in the programme produces the same shape of row
    /// and the Rules pane never has to know which surface a rule came from.
    public func rule(
        verdict: PriorityRuleVerdict,
        authority: RuleAuthority,
        at instant: Date,
        id: UUID = UUID()
    ) -> ScopedRuleValue {
        ScopedRuleValue(
            id: id,
            authority: authority,
            subjectKind: kind,
            subject: subject,
            verdict: verdict,
            createdAt: instant
        )
    }

    /// `NudgeSubject.nameable(_:)`'s rule, called rather than restated (focus-7gc). It was the
    /// third byte-identical copy of it in this directory.
    private static func nameable(_ candidate: String) -> String? {
        NudgeSubject.nameable(candidate)
    }

    /// The same discriminator `QuerySubject.kind(of:)` decides `.domain` by, and for the same
    /// reason: `OriginNormalizer` emits `scheme://host[:port]` and nothing else does. Asking
    /// `NudgeSubject` rather than re-writing `contains("://")` is what stops a rule and the
    /// sentence about it disagreeing on what an origin is.
    private static func kind(of subject: String) -> RuleSubjectKind {
        NudgeSubject.isOrigin(subject) ? .domain : .app
    }
}

/// **The three answers a question has, and no fourth.**
///
/// Escape is "Not now" — the same action, because a person who closes a panel has answered it,
/// and treating a dismissal as "nothing happened" is what makes an app ask again tomorrow.
public enum QueryAnswer: String, Sendable, CaseIterable, Codable, Hashable {
    /// "Yes, add it" — a `RuleAuthority.task` rule with verdict `relevant`, plus the receipt.
    /// The next time this subject appears the cascade answers at the `taskRule` rung with band
    /// `.high` and never reaches the heuristic, so no `uncertain` verdict exists and no warrant
    /// can be produced.
    case yesAddIt
    /// "No" — the same pair with verdict `unrelated`.
    ///
    /// Note what this does and does not mean. The *next* appearance of the subject is
    /// `unrelated` because **the user said so** — a `userRule`-sourced verdict at the
    /// `taskRule` rung — and it enters the accusation ladder on that authority. That is not a
    /// query escalating; it is a user-authored rule producing an independent verdict on a later
    /// classification, and `InterventionRecord.originatingAnswer` records which click wrote it.
    case no
    /// "Not now", and Escape. **No rule** — there is no answer to record — but the asking
    /// happened and is remembered, so the question does not return after a relaunch.
    case notNow

    /// What the receipt records.
    public var outcome: AskedQuestionOutcome {
        switch self {
        case .yesAddIt: .answeredRelevant
        case .no: .answeredUnrelated
        case .notNow: .declined
        }
    }

    /// The verdict of the rule this answer writes, or `nil` when it writes none.
    public var ruleVerdict: PriorityRuleVerdict? {
        switch self {
        case .yesAddIt: .relevant
        case .no: .unrelated
        case .notNow: nil
        }
    }

    /// The single transaction this answer performs (R-78).
    ///
    /// **One transaction, two records** for an answer — the visible, deletable rule that is
    /// authoritative for future classification, and the invisible, immutable receipt that is
    /// authoritative for never-ask-twice. Either both commit or neither does, so the app is
    /// never in a state where it has learned the answer but forgotten the asking.
    ///
    /// "Not now" is the one action whose transaction has a single row, because there is no
    /// answer to record.
    public func outcome(
        scope: CorrectionScope,
        at instant: Date,
        id: UUID = UUID()
    ) -> CorrectionOutcome {
        guard let verdict = ruleVerdict else { return .receiptOnly(outcome) }
        return .ruleAndReceipt(
            rule: scope.rule(verdict: verdict, authority: .task, at: instant, id: id),
            receipt: outcome
        )
    }
}

/// **Everything a person can do to a nudge**, and every one of them writes exactly one thing.
///
/// The Court's product boundary is that a nudge you cannot answer back to is an anti-pattern,
/// and D-07's is that there is **zero coercion**: no dimming, no blocking, no quitting, no
/// launch prevention, no friction timers. Every surface, including the top rung, is
/// dismissible — which is why `dismiss` is in this list beside the rest rather than being the
/// absence of an action.
public enum CorrectionAction: String, Sendable, CaseIterable, Codable, Hashable {
    /// "This is relevant" — a `RuleAuthority.task` rule from the evidence actually available.
    /// It removes the subject from the accusable set entirely, which is why **a correction
    /// suppresses harder than an ignore** (R-83): the backoff never has to see it again.
    case thisIsRelevant
    /// "Not this time" — a **session-lived** rule through e04's `SessionRuleBox`, which dies
    /// with the session, the priority change or the process. Never persisted, so it cannot
    /// outlive the afternoon it was about.
    case notThisTime
    /// Subject-scoped, in memory, with a visible menu-bar countdown. Never a global mute, and
    /// it does **not** stop the ambient rung: the glyph still tells the truth (R-87).
    case snooze
    /// Opens e02's quick-capture **confirm surface**. Never a silent replacement (F-142).
    case changePriority
    /// `SessionPhase.paused` through e03's existing `SessionMachine` — not a second pause
    /// concept (F-64).
    case pause
    /// `NSRunningApplication.activate()`, falling back to `NSWorkspace.openApplication`. **Not
    /// offered** when there is no stored target: a "back to work" button with nowhere to go is
    /// a button that lies (R-88).
    case returnToTask
    /// Escape, or the close button. Writes nothing at all, and that is allowed.
    case dismiss

    /// Whether this action ends the ladder outright. Every one of them except `dismiss` does:
    /// de-escalation is immediate and total, and re-entry is always at the ambient rung.
    public var deEscalation: LadderDeEscalation? {
        switch self {
        case .thisIsRelevant: .corrected
        case .notThisTime: .excusedForThisSession
        case .snooze: .snoozed
        case .pause: .paused
        case .changePriority: .priorityChanged
        case .returnToTask: .returnedToTask
        case .dismiss: nil
        }
    }

    /// Whether the surface may offer this action at all with the scope it has.
    ///
    /// The two subject-writing actions need a single named subject; a mixed mandate has none,
    /// and offering "this is relevant" over "several unrelated apps" would write a rule about
    /// something the person never pointed at.
    public var requiresScope: Bool {
        switch self {
        case .thisIsRelevant, .notThisTime, .snooze: true
        case .changePriority, .pause, .returnToTask, .dismiss: false
        }
    }

    /// Whether this action needs an **open session** to write what it promises.
    ///
    /// Two do, and no open session is a supported default working state rather than an
    /// exceptional one: the code says so twice (*"No open session is not a break: the person can
    /// be working with no session started"*, `phase: session?.phase ?? .focus`), and there is no
    /// auto-start — `startSession(` has exactly two shipping call sites and both are clicks. So
    /// the ladder runs, and the panel appears, with only a priority set.
    ///
    /// * `notThisTime` writes a **session-lived** rule through `SessionRuleBox`, which is keyed
    ///   on the session as well as the priority. With no session there is no key, and there is no
    ///   honest wider rule to widen it to: this action's whole meaning is *"until this session
    ///   ends"*.
    /// * `pause` moves e03's `SessionMachine`, which throws `noOpenSession` when there is none.
    ///
    /// The consequence of offering them anyway was not a dropped click. It was a **falsified
    /// one** (focus-rdw): the panel came down, the log recorded `.corrected`, fatigue was spent
    /// and the ladder de-escalated — while nothing was written and nothing was learned, so the
    /// next mandate accused the person about the very thing they had just excused.
    ///
    /// This is R-88's ruling, at a second site. *"A 'back to work' button with nowhere to go is
    /// a button that lies"* is the same sentence as "an excuse with no session to die with", and
    /// `returnTarget == nil` withdraws the action rather than explaining it away.
    public var requiresOpenSession: Bool {
        switch self {
        case .notThisTime, .pause: true
        case .thisIsRelevant, .snooze, .changePriority, .returnToTask, .dismiss: false
        }
    }

    /// The single write this action performs.
    ///
    /// - Parameters:
    ///   - scope: the subject, when the judgement named one. An action that
    ///     `requiresScope` and is given none writes `.nothing`, because there is nothing it
    ///     could honestly write.
    ///   - instant: the wall clock, from an injected `DateProvider`.
    ///   - snoozeDuration: which of `InterventionPolicy.snoozeDurations` the person chose.
    ///     Defaults to the shortest, which is the least presumptuous answer.
    ///   - pausePreset: which of `InterventionPolicy.pauseDurations` they chose.
    public func outcome(
        scope: CorrectionScope?,
        at instant: Date,
        snoozeDuration: Duration? = nil,
        pausePreset: PausePreset? = nil,
        id: UUID = UUID()
    ) -> CorrectionOutcome {
        if requiresScope, scope == nil { return .nothing }

        switch self {
        case .thisIsRelevant:
            guard let scope else { return .nothing }
            return .rule(scope.rule(verdict: .relevant, authority: .task, at: instant, id: id))
        case .notThisTime:
            guard let scope else { return .nothing }
            return .sessionRule(
                scope.rule(verdict: .relevant, authority: .session, at: instant, id: id)
            )
        case .snooze:
            guard let scope else { return .nothing }
            return .snooze(
                subject: scope.subject,
                duration: snoozeDuration ?? InterventionPolicy.snoozeDurations.first ?? .zero
            )
        case .changePriority:
            return .priorityChangeRequested
        case .pause:
            return .pause(pausePreset ?? InterventionPolicy.pauseDurations.first ?? .restOfDay)
        case .returnToTask:
            return .returnToTask
        case .dismiss:
            return .nothing
        }
    }
}

/// **The typed description of what one click wrote.**
///
/// Every action on every surface goes through one function and produces one of these, so that
/// the host, the undo journal (F-93) and the `InterventionRecord` all read the same value
/// rather than each reconstructing what happened from the action name.
public enum CorrectionOutcome: Sendable, Equatable, Hashable {
    /// One persisted scoped rule, visible in the Rules pane immediately, consulted by the very
    /// next classification at the `taskRule` rung, and undoable through the standard command.
    case rule(ScopedRuleValue)
    /// **R-78's atomic pair.** The rule *and* an immutable receipt, committed together or not
    /// at all. The rule is authoritative for classification and is deletable by design; the
    /// receipt is authoritative for never-ask-twice and is not.
    case ruleAndReceipt(rule: ScopedRuleValue, receipt: AskedQuestionOutcome)
    /// A receipt only. "Not now" writes no rule — there is no answer to record — and the
    /// asking is still remembered.
    case receiptOnly(AskedQuestionOutcome)
    /// A session-lived rule through `SessionRuleBox`. Never persisted; it dies on its own.
    case sessionRule(ScopedRuleValue)
    /// A subject-scoped, in-memory snooze with a visible countdown.
    case snooze(subject: String, duration: Duration)
    /// A pause, performed through e03's session machine.
    case pause(PausePreset)
    /// e02's confirm surface is opened. The priority is **not** replaced here.
    case priorityChangeRequested
    /// The stored return target is activated.
    case returnToTask
    /// Nothing was written, and that is a legitimate answer.
    case nothing

    /// The persisted rule this outcome writes, if any. `nil` for a session rule, which is not
    /// persisted, and for everything that writes no rule at all.
    public var persistedRule: ScopedRuleValue? {
        switch self {
        case .rule(let rule): rule
        case .ruleAndReceipt(let rule, _): rule
        case .sessionRule, .receiptOnly, .snooze, .pause, .priorityChangeRequested,
             .returnToTask, .nothing: nil
        }
    }

    /// **The rule the caller must still write**, which is not the same question as
    /// `persistedRule` and must never be confused with it (R-78).
    ///
    /// `persistedRule` answers *"which rule does this outcome describe?"* — it is what
    /// `QueryLedger.answer(…)` reads in order to insert the row inside its own transaction, and
    /// it is non-`nil` for both `.rule` and `.ruleAndReceipt`.
    ///
    /// This answers the different and narrower question *"has anybody written it yet?"*:
    ///
    /// * `.rule` — an accusation-panel correction. **Nothing has been persisted.** The caller
    ///   inserts it, and gets the undo registration for free by going through the rules store.
    /// * `.ruleAndReceipt` — a query answer. **The ledger already committed both rows**, together
    ///   or not at all, and it committed the rule under `rule.id`. A caller that inserted it a
    ///   second time would write a *duplicate* learned rule under a different identifier: two
    ///   chips in the context row, two rows in the Rules pane, and an undo that removes only one
    ///   of them — the exact opposite of §3.B.13's "one store, one truth, one write, two
    ///   renderings, same rule id".
    ///
    /// So this is `nil` for the atomic pair, and that `nil` is the whole point of the property.
    public var ruleAwaitingPersistence: ScopedRuleValue? {
        switch self {
        case .rule(let rule): rule
        // Already committed by `QueryLedger.answer(…)`, inside R-78's one transaction.
        case .ruleAndReceipt: nil
        case .sessionRule, .receiptOnly, .snooze, .pause, .priorityChangeRequested,
             .returnToTask, .nothing: nil
        }
    }

    /// The receipt this outcome writes, if any.
    public var receipt: AskedQuestionOutcome? {
        switch self {
        case .ruleAndReceipt(_, let receipt): receipt
        case .receiptOnly(let receipt): receipt
        case .rule, .sessionRule, .snooze, .pause, .priorityChangeRequested, .returnToTask,
             .nothing: nil
        }
    }

    /// Whether this outcome must be written as **one atomic transaction of two rows**.
    public var isAtomicPair: Bool {
        if case .ruleAndReceipt = self { return true }
        return false
    }
}
