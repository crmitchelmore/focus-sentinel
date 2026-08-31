import Foundation

/// Which kind of interruption is being considered.
///
/// Two kinds, and they are different in kind and identical in cost to the person — which is
/// exactly why they keep separate caps *and* draw on one shared budget (R-83). Declared here,
/// with the stack, because **gate 11 of R-84 is kind-dependent**: never-ask-twice applies to a
/// question and an accusation passes straight through it, so the stack cannot be evaluated
/// without knowing which is being asked for.
public enum InterruptionKind: String, Sendable, CaseIterable, Codable, Hashable {
    /// "Is *{subject}* part of *{task}*?" — U-1's affordance, whose cheapest answer teaches the
    /// app. Cheap, but still an interruption: a person asked ten questions has been interrupted
    /// ten times.
    case query
    /// "Still working on *{task}*?" — the two-rung ladder, reserved for `unrelated`.
    case accusation
}

/// Every reason the app has for staying quiet, **in the order R-84 evaluates them**.
///
/// The order is part of the contract, not a presentation choice: the reason a surface is told
/// is the *first* reason that applied, which is the one a person would give. "I said nothing
/// because you have no priority set" and "I said nothing because I had already asked you about
/// this" are both true of the same moment, and only one of them is the answer.
///
/// Twelve cases. Gate 11 — `alreadyAsked` — is the one adversarial review added (finding 3):
/// never-ask-twice is an explicit, ordered, **named** suppression consulted before a warrant is
/// constructed, not an emergent property of the cascade that a rule deletion could dissolve. It
/// reads the immutable receipt, never the rule.
public enum NudgeSuppressionReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// Gate 1 (e04). There is nothing to be off-task *from*.
    case noActivePriority
    /// Gate 2 (e03, F-119). The one global pause switch is on, or sensing is off. A pause is
    /// not a boolean handlers consult — it detaches every observer — and nothing downstream of
    /// it can speak.
    case sensingPaused
    /// Gate 3 (e03, F-118). A sensitive application is frontmost.
    ///
    /// **The subject is never named in any record**, because e03's gate suppressed the
    /// activation before the engine ever saw it. That is also why `noEvidence` is unaskable:
    /// "we did not look" must never become "tell us what you were doing."
    case sensitiveApplication
    /// Gate 4 (e03, F-99). The session is on a break, a deliberate detour, paused, interrupted
    /// or complete. `SessionPhase.permitsIntervention` is `.focus` alone.
    case sessionPhaseForbids
    /// Gate 5 (e03, F-32). No hardware input for longer than the user's idle threshold.
    case userIdle
    /// Gate 6 (e03, F-36). A microphone or camera is running: the person is on a call, and a
    /// panel over a call is a panel everybody else can see.
    ///
    /// **Subject: the app speaking** (focus-0y6). The sentence above names a panel, and the
    /// glyph is not one. See `subject` below for why this is an exemption and gate 7 is a
    /// deferral — the difference is that during a call the menu bar is still on screen.
    case mediaInUse
    /// Gate 7 (e03, F-35). A presentation or full-screen space is up.
    ///
    /// For the panel and for a question this is a **suppression**. For the silent ambient rung
    /// it is a **deferral** instead (R-81): the menu bar is hidden, so the rung is undeliverable
    /// rather than unwanted, and an undeliverable rung must not advance the ladder or spend a
    /// cap. `SuppressionStack.evaluate(…)` returns `.deferred` for exactly that cell.
    case presentationActive
    /// Gate 8 (e05, R-85). The person's own quiet hours. Not the system Focus, which this app
    /// makes no claim to read (P-137).
    ///
    /// **Subject: the app speaking** (focus-0y6). Somebody who sets quiet hours is asking the
    /// app not to *say* anything between two times, which is the request a snooze makes — and
    /// R-87 already ruled on a snooze: the glyph goes on telling the truth.
    case quietHours
    /// Gate 9 (e05, U-2). One open interruption at a time, **symmetrically**: whatever is
    /// already on screen keeps the slot, and whatever arrives second waits. The gate below is
    /// `guard !interruptionInFlight` for both kinds, with no arm that reads `kind`.
    ///
    /// It used to say that a mandate offered against an open query closed the query as
    /// `declined` and took the slot, and that the reverse never happened. That asymmetry was
    /// preemption, U-2 deleted it, and roughly eleven defects across seven repair rounds had
    /// lived in it. An accusation withheld here is **not lost**: no delivery is recorded and the
    /// escalation clock does not start, so the same rung is offered again on the next judgement.
    ///
    /// **Subject: the app speaking** (focus-0y6), and this is the sharpest of the three. It is an
    /// occupancy rule, and `NudgeSurface.menuBar.holdsTheInterruptionSlot` is `false`: the glyph
    /// was being refused by a rule it is explicitly excluded from — a thing refused on the
    /// grounds of a property it does not have. One open question used to take the status item
    /// with it for as long as it stayed on the screen.
    case interruptionInFlight
    /// Gate 10 (e05, R-83). A cap, a cooldown or a backoff. Queries and accusations keep
    /// separate caps *and* draw on one shared daily budget whose last unit is reserved for an
    /// accusation.
    case budgetExhausted
    /// Gate 11 (e05, R-78). **Queries only.** The immutable receipt says this exact question
    /// was already asked for this priority — and it stays true after the rule that answer wrote
    /// has been deleted, because removing a learned chip means "that is not a fact about my
    /// work", never "ask me again".
    case alreadyAsked
    /// Gate 12 (e04 R-55 / e05 R-76). The verdict itself does not authorise this kind of
    /// interruption. The one gate whose detail lives in a type rather than in this enum:
    /// `InterventionEligibility.decide(…)` for an accusation, `QueryEligibility.decide(…)` for
    /// a question, each returning *before* it reads anything else.
    case verdictDoesNotAuthorise

    /// **What this gate is about, and therefore which rungs it may silence** (focus-0y6,
    /// focus-uru).
    ///
    /// The exhaustive `switch` is the mechanism. `focus-2yy`'s commit message enumerated *"gates
    /// 1, 2 and 3 … gate 5"* and `focus-0y6`'s triage walked twelve gates and ruled on each, and
    /// **both skipped gate 4** — because both swept a closed set by reading prose. A closed set
    /// swept by reading is not swept. A thirteenth gate added below does not compile until it
    /// has been ruled on here.
    ///
    /// The rulings, and the argument for each:
    ///
    /// | gate | subject | why |
    /// |---|---|---|
    /// | 1 `noActivePriority` | legibility | there is nothing to be off task *from*, so there is nothing true for the glyph to say |
    /// | 2 `sensingPaused` | legibility | the observers are detached; the app does not know, and a mark would be a guess |
    /// | 3 `sensitiveApplication` | legibility | the app must say nothing at all about what is on screen — and *"we did not look"* must never become a mark |
    /// | 4 `sessionPhaseForbids` | legibility | on a break there is no drift to be legible about |
    /// | 5 `userIdle` | legibility | nobody is looking at the menu bar either |
    /// | 6 `mediaInUse` | **speaking** | ruled below |
    /// | 7 `presentationActive` | **the surface** | the menu bar is hidden (P-131) — wanted and undeliverable, so a deferral |
    /// | 8 `quietHours` | **speaking** | ruled below |
    /// | 9 `interruptionInFlight` | **speaking** | ruled below |
    /// | 10 `budgetExhausted` | legibility | ruled below — this gate deliberately does **not** classify |
    /// | 11 `alreadyAsked` | speaking | a question is a sentence, and this gate is a question's alone |
    /// | 12 `verdictDoesNotAuthorise` | legibility | the verdict authorises nothing, so there is nothing to mark |
    ///
    /// ## Gate 6, and why it is not gate 7
    ///
    /// F-36's own sentence is *"a microphone or camera is running: the person is on a call, and
    /// **a panel over a call is a panel everybody else can see**"*. The gate is about a window
    /// appearing over a screen share. The glyph is not a window: it is the same status item that
    /// was already there, changing colour, naming nobody, revealing nothing about what the person
    /// is doing that the item was not already free to show.
    ///
    /// The counter-argument is real and was weighed: a person on a call is a person who cannot
    /// *act* on the mark, so a deferral — gate 7's answer — might be more honest than an
    /// exemption. It is not, and the difference is deliverability. Gate 7 defers because the
    /// menu bar is **not on screen**; a rung deferred there reached nobody, so R-81 forbids it
    /// advancing the ladder or spending anything. During a call the menu bar is exactly where it
    /// always is and the person can see it whenever they look up. Recording it as undeliverable
    /// would be recording a falsehood in order to be tidy.
    ///
    /// ## Gates 8 and 9
    ///
    /// Gate 8 is R-85's own quiet hours, default off, and the person who sets them is asking the
    /// app **not to speak** between two times. It is the same request a snooze makes, and R-87
    /// already ruled on a snooze: the glyph goes on telling the truth, because a person who asked
    /// for quiet did not ask for a lie.
    ///
    /// Gate 9 is the sharpest of the three. It is an **occupancy** rule — one open interruption
    /// at a time — and `NudgeSurface.menuBar.holdsTheInterruptionSlot` is `false`, so the glyph
    /// is refused by a rule it is explicitly excluded from. Refusing a thing on the grounds of a
    /// property it does not have.
    ///
    /// ## Gate 10 does not classify, and that is its ruling
    ///
    /// Its detail vocabulary — `FatigueRefusal` — classifies for it, case by case, and one of
    /// those cases is `.corrected`, whose subject is legibility: a subject the person has told us
    /// is real work is a subject the glyph must **stop** marking. Ruling gate 10 as
    /// `.theAppSpeaking` here would pass the glyph over a correction the person made, which is
    /// the one fatigue refusal that must reach it. So the classification happens once, where the
    /// detail is, and this gate takes whatever answer `FatigueController.decide(…)` already gave
    /// for this rung.
    public var subject: SilenceSubject {
        switch self {
        case .noActivePriority, .sensingPaused, .sensitiveApplication, .sessionPhaseForbids,
             .userIdle, .budgetExhausted, .verdictDoesNotAuthorise:
            .anythingToBeLegibleAbout
        case .mediaInUse, .quietHours, .interruptionInFlight, .alreadyAsked:
            .theAppSpeaking
        case .presentationActive:
            .theSurfaceBeingOnScreen(.menuBarHidden)
        }
    }

    /// Where this gate sits in R-84's stack, counting from one — derived from `allCases`, so
    /// the declaration order *is* the evaluation order and no numeric literal appears (R-96j).
    public var gateNumber: Int {
        (Self.allCases.firstIndex(of: self) ?? Self.allCases.count) + 1
    }

    /// Whether this gate applies to both kinds of interruption or to questions alone.
    public var appliesTo: Set<InterruptionKind> {
        self == .alreadyAsked ? [.query] : [.query, .accusation]
    }

    // **This type carried twelve user-visible sentences and no surface could draw one**
    // (focus-pzl). `nudge.suppressed.*` shipped in the compiled catalogue for the whole of e05;
    // `copyResource` had zero call sites outside this package, and the name
    // `NudgeSuppressionReason` appeared nowhere in `FocusUI`, `FocusHost` or `App` at all.
    //
    // The sentences were not deleted for being unused. They were deleted because the app
    // **already has** a drawn vocabulary for "why I stayed quiet" — e04's `SuppressionReason`,
    // rendered by `VerdictInspectorView.eligibility(_:)` under *"Silent because"* — and eight of
    // the twelve gates below share a name with one of its nine cases. Drawing both would have put
    // two differently-worded English sentences about the same silence on one screen, which is
    // focus-doc's defect one pane over.
    //
    // The **type** is untouched and load-bearing: `gateNumber` derives R-84's evaluation order
    // from `allCases`, `appliesTo` carries gate 11's kind-dependence, and the reason is recorded
    // on every `InterventionRecord`. What went is the presentation nobody asked for.
}

/// What the stack concluded.
///
/// Three answers rather than an optional reason, because R-81 needs the middle one: a rung
/// nobody could see is **deferred**, not suppressed, and the difference decides whether the
/// ladder advances and whether a cap is spent. An `Optional<NudgeSuppressionReason>` would have
/// collapsed the two, and the collapse is invisible at a call site.
public enum SuppressionOutcome: Sendable, Equatable, Hashable {
    /// Every gate cleared. The app may speak.
    case permitted
    /// The app chose not to speak, and this is the **first** reason that applied.
    case suppressed(NudgeSuppressionReason)
    /// The app would have spoken and could not be seen. Does not advance the ladder, does not
    /// spend a cap, does not start the escalation clock.
    case deferred(DeferralReason)

    public var isPermitted: Bool { self == .permitted }

    public var suppressionReason: NudgeSuppressionReason? {
        switch self {
        case .suppressed(let reason): reason
        case .permitted, .deferred: nil
        }
    }

    public var deferralReason: DeferralReason? {
        switch self {
        case .deferred(let reason): reason
        case .permitted, .suppressed: nil
        }
    }
}

/// **The one ordered suppression stack**, and both authorisations pass through it.
///
/// Under U-1 the app speaks more, so suppression correctness matters *more*, not less. Gates
/// 1–8 are shipped code from e01–e04 and this function **wires** them: it consumes
/// `SensitiveScreenDecision`, `SessionPhase`, `IdleReading`, `MediaActivity` and
/// `PresentationState` as values produced by the packages that own them, and re-implements
/// none of them. `SuppressionStackTests` asserts each of gates 3–7 is reached through its
/// existing type rather than through a copy, and `check-boundaries.sh` proves on the object
/// that this module could not have gone and fetched them itself (R-96k).
public enum SuppressionStack {
    /// Evaluate the twelve gates in order and return the first answer that is not "permitted".
    ///
    /// - Parameters:
    ///   - kind: which interruption is being considered. Gate 11 is kind-dependent and nothing
    ///     else is.
    ///   - rung: the accusation rung being considered, or `nil` for a question. **Read by every
    ///     gate, through `NudgeSuppressionReason.subject`** (focus-0y6): a gate about the app
    ///     speaking passes over a rung that says nothing, a gate about there being anything to be
    ///     legible about stops every rung, and gate 7 — whose subject is the surface being on
    ///     screen — **defers** rather than suppresses a rung that does not speak, because the
    ///     menu bar is hidden and the rung is undeliverable rather than unwanted (R-81, P-131).
    ///     `nil` speaks: a question is a sentence, and every gate applies to it.
    ///   - hasActivePriority: gate 1.
    ///   - sensingPaused: gate 2 — `AppSettingsRecord.sensingPaused`, F-119's one switch.
    ///   - sensitivity: gate 3 — e03's `SensitivityGate.evaluate(_:)` answer, already made.
    ///   - phase: gate 4 — e03's `SessionPhase`, read through `permitsIntervention`.
    ///   - idle: gate 5 — e03's `IdleReading`, read through `isIdle(threshold:)`.
    ///   - idleThresholdSeconds: the user's own threshold, from settings.
    ///   - media: gate 6 — e03's `MediaActivity`, read through `suppressesIntervention`.
    ///   - mediaSuppressionEnabled: the user's own switch. Off means a running microphone does
    ///     not suppress; the reading is still taken, it is simply not acted on.
    ///   - presentation: gate 7 — e03's `PresentationState`, read through `suppressesOverlays`.
    ///   - quietHours: gate 8 — e05's own window, default off.
    ///   - now: the wall clock, from an injected `DateProvider`. Quiet hours are the only gate
    ///     that reads it.
    ///   - calendar: the user's calendar, injected. Never `Calendar.current`.
    ///   - interruptionInFlight: gate 9.
    ///   - budgetPermits: gate 10 — the caps, the cooldown and the backoff, already computed.
    ///   - hasAsked: gate 11 — the **immutable receipt**, never the rule. Ignored entirely for
    ///     an accusation.
    ///   - verdictAuthorises: gate 12 — whether the kind's own eligibility produced an
    ///     authorisation. `InterventionEligibility` for an accusation, `QueryEligibility` for a
    ///     question; this function never inspects a verdict itself.
    public static func evaluate(
        kind: InterruptionKind,
        rung: LadderRung.Kind?,
        hasActivePriority: Bool,
        sensingPaused: Bool,
        sensitivity: SensitiveScreenDecision,
        phase: SessionPhase,
        idle: IdleReading,
        idleThresholdSeconds: Double,
        media: MediaActivity,
        mediaSuppressionEnabled: Bool,
        presentation: PresentationState,
        quietHours: QuietHours,
        now: Date,
        calendar: Calendar,
        interruptionInFlight: Bool,
        budgetPermits: Bool,
        hasAsked: Bool,
        verdictAuthorises: Bool
    ) -> SuppressionOutcome {
        // **Every gate is asked the same two questions, in this order: is it closed, and is it
        // about a rung like this one?** (focus-0y6, focus-uru).
        //
        // It used to be twelve hand-written `guard`s, and exactly one of them — gate 7 — read
        // the rung. The other eleven refused whatever they were handed, so three gates written
        // about **interrupting somebody** were applied to the ambient glyph, which interrupts
        // nobody: a running microphone, the person's own quiet hours, and an occupancy rule the
        // glyph is explicitly excluded from (`NudgeSurface.menuBar.holdsTheInterruptionSlot` is
        // `false`). The consequence is F-146's *"the state is always legible"* broken by rules
        // aimed at something else — the status item goes dark while somebody is on a call, or
        // after 22:00, or for as long as one question sits on the screen.
        //
        // `closing(_:when:rung:)` is the whole evaluation now. It returns `nil` for a gate that
        // is open **and** for a gate that is not about this rung, which is what makes "pass over
        // it and keep going" the same shape as "it did not close" — and it derives the deferral
        // in gate 7's cell from `NudgeSuppressionReason.subject` rather than from an `if` that
        // names `.ambient`, so that cell is now an instance of the rule instead of the exception
        // that proved it.
        let gates: [(NudgeSuppressionReason, Bool)] = [
            // 1 — no active priority (e04).
            (.noActivePriority, !hasActivePriority),
            // 2 — the global pause switch (e03, F-119).
            (.sensingPaused, sensingPaused),
            // 3 — a sensitive application (e03, F-118). Read through e03's own decision type, so
            // the subject is never named here — the activation was suppressed before the engine
            // saw it, and this function never learns what it was.
            (.sensitiveApplication, sensitivity.clearedActivation == nil),
            // 4 — the session phase (e03, F-99). `.focus` alone.
            (.sessionPhaseForbids, !phase.permitsIntervention),
            // 5 — the person is away (e03, F-32), by the hardware idle source and their threshold.
            (.userIdle, idle.isIdle(threshold: idleThresholdSeconds)),
            // 6 — a microphone or camera is running (e03, F-36), if the user left that switch on.
            (.mediaInUse, mediaSuppressionEnabled && media.suppressesIntervention),
            // 7 — a presentation (e03, F-35). The menu bar is hidden, so a rung that does not
            // speak is DEFERRED here rather than suppressed (R-81, P-131).
            (.presentationActive, presentation.suppressesOverlays),
            // 8 — quiet hours (e05, R-85). Default off.
            (.quietHours, quietHours.isQuiet(at: now, calendar: calendar)),
            // 9 — one open interruption at a time, symmetrically (e05, U-2). No arm reads `kind`:
            // whatever is on screen keeps the slot and whatever arrives second waits.
            (.interruptionInFlight, interruptionInFlight),
            // 10 — the caps, the cooldown and the backoff (e05, R-83). Already computed, and
            // already classified per refusal by `FatigueController.decide(…)` — which is why
            // this gate's own subject is legibility and it never passes a rung over.
            (.budgetExhausted, !budgetPermits),
            // 11 — never twice (e05, R-78). Queries only; an accusation passes straight through,
            // which `appliesTo` says and this conjunct spells.
            (.alreadyAsked, kind == .query && hasAsked),
            // 12 — the verdict gate (e04 R-55 / e05 R-76).
            (.verdictDoesNotAuthorise, !verdictAuthorises)
        ]

        // The declaration order above **is** the evaluation order, and `gateNumber` derives the
        // same order from `allCases`. `SuppressionStackTests.theStackEvaluatesEveryGateInOrder`
        // holds the two together, so a gate added to the enum and forgotten here is red rather
        // than silently skipped.
        for (reason, isClosed) in gates where isClosed {
            switch reason.subject.ruling(for: rung) {
            case .silences: return .suppressed(reason)
            case .defers(let deferral): return .deferred(deferral)
            case .passes: continue
            }
        }

        return .permitted
    }
}
