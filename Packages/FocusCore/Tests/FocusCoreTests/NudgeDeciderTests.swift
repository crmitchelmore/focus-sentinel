import Foundation
import Testing

@testable import FocusCore

/// **U-1's whole truth table, in the one function that decides anything** (R-76, R-83, R-84, U-1).
///
/// | verdict | what must happen |
/// |---|---|
/// | `relevant`, confidently derived | silence — the only thing that buys it |
/// | `uncertain`, askable, unasked, affordable | a question |
/// | `uncertain`, unaskable | silence, with the reason named |
/// | `uncertain`, already asked | silence, **whether or not the rule that answer wrote survives** |
/// | `unrelated`, sustained, banded | the ladder, one rung at a time |
///
/// And the invariant that outranks every other in the epic: **no input ever yields `.accuse` from
/// an `uncertain` verdict.** The guarantee is the types — `.accuse` carries a `LadderRung`, a rung
/// takes a mandate, and e04's sole producer returns before reading anything else on `uncertain` —
/// so the cross-product below is a *check* on the guarantee rather than the guarantee itself.
@Suite("Nudge decider")
struct NudgeDeciderTests {
    static let decoy = "com.chrismitchelmore.FocusDecoy"
    static let neutral = "com.chrismitchelmore.FocusDecoy2"
    static let stamp = EngineStamp.current
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01T00:00:00Z

    static var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    static func sensitivity(_ bundle: String) -> SensitiveScreenDecision {
        SensitivityGate().evaluate(
            FrontmostActivation(
                bundleIdentifier: bundle,
                localizedName: bundle,
                pid: 4242,
                at: reference,
                dwellSeconds: 120
            )
        )
    }

    static let cleared = sensitivity(decoy)
    static let blocked = sensitivity("com.apple.keychainaccess")

    static let presenting = PresentationState(
        signals: PresentationSignals(
            frontmostWindowFillsAScreen: true,
            presentationOptionsSayFullScreen: true,
            menuBarHidden: true
        ),
        isUserExcluded: false,
        isPresenting: true
    )

    // MARK: - Building a judgement

    static func status(for verdict: Verdict) -> FocusStatus {
        switch verdict {
        case .relevant: .relevant
        case .uncertain: .uncertain
        case .unrelated: .unrelated
        }
    }

    static func clauses(for verdict: Verdict, uncertainty: UncertaintyReason?) -> [ExplanationClause] {
        switch verdict {
        case .relevant: [.similarityCorroborated]
        case .unrelated: [.sustainedDwell(seconds: 120)]
        case .uncertain: [.insufficientEvidence(reason: uncertainty ?? .noNegativeBasis)]
        }
    }

    static func judgement(
        verdict: Verdict,
        uncertainty: UncertaintyReason? = nil,
        subject: String? = NudgeDeciderTests.decoy,
        dwelled: Duration = .seconds(120),
        band: EvidenceBand = .high,
        drift: DriftState? = nil,
        status: FocusStatus? = nil,
        phase: SessionPhase = .focus,
        isUserIdle: Bool = false,
        hasActivePriority: Bool = true
    ) -> NudgeJudgement {
        let outcome = ClassificationOutcome(
            verdict: verdict, source: .heuristic, confidence: 1, band: band
        )
        let explanation = Explanation.make(
            stage: .heuristic,
            band: band,
            clauses: clauses(for: verdict, uncertainty: uncertainty),
            stamp: stamp
        )
        let effectiveDrift = drift ?? (
            verdict == .unrelated
                ? .sustained(
                    subject: .single(subject ?? ""), accumulated: dwelled, isMixed: false
                )
                : .aligned
        )
        let effectiveStatus = status ?? Self.status(for: verdict)
        let eligibility = InterventionEligibility.decide(
            outcome: outcome,
            drift: effectiveDrift,
            phase: phase,
            status: effectiveStatus,
            isUserIdle: isUserIdle,
            hasActivePriority: hasActivePriority,
            explanation: explanation,
            stamp: stamp
        )

        return NudgeJudgement(
            outcome: outcome,
            uncertainty: uncertainty,
            subject: subject,
            dwelled: dwelled,
            snapshot: VerdictSnapshot(
                status: effectiveStatus,
                stage: .heuristic,
                band: verdict == .uncertain ? nil : band,
                drift: effectiveDrift,
                eligibility: eligibility,
                explanation: explanation,
                stampKey: stamp.cacheKey
            ),
            stamp: stamp
        )
    }

    /// The one commitment every decider drive runs under. Fixed, so nothing in these suites is a
    /// function of which identifier the run happened to mint.
    static let commitment = ActiveCommitment(
        id: UUID(uuidString: "DEC1DE00-0000-4000-8000-000000000001")!,
        intent: "Write the Q3 proposal for Acme"
    )

    static func surroundings(
        hasActivePriority: Bool = true,
        sensingPaused: Bool = false,
        sensitivity: SensitiveScreenDecision = NudgeDeciderTests.cleared,
        phase: SessionPhase = .focus,
        idleSeconds: Double = 0,
        media: MediaActivity = .idle,
        mediaSuppressionEnabled: Bool = true,
        presentation: PresentationState = .notPresenting,
        menuBarVisible: Bool = true,
        quietHours: QuietHours = .off,
        now: Date = NudgeDeciderTests.reference,
        monotonic: Duration = .seconds(10_000)
    ) -> NudgeSurroundings {
        NudgeSurroundings(
            // Gate 1 is `commitment != nil` and there is no second reading (focus-zrs); the
            // decider never looks at the identifier, so the suite still says "is there one?".
            commitment: hasActivePriority ? NudgeDeciderTests.commitment : nil,
            sensingPaused: sensingPaused,
            sensitivity: sensitivity,
            phase: phase,
            idle: IdleReading(hardwareSeconds: idleSeconds, sessionSeconds: idleSeconds),
            idleThresholdSeconds: 120,
            media: media,
            mediaSuppressionEnabled: mediaSuppressionEnabled,
            presentation: presentation,
            menuBarVisible: menuBarVisible,
            quietHours: quietHours,
            now: now,
            calendar: londonCalendar,
            monotonic: monotonic
        )
    }

    static let exhausted = InterruptionBudget(
        queriesForPriorityToday: InterventionPolicy.dailyQueryCap,
        queriesAllPrioritiesToday: InterventionPolicy.dailyQueryCapAllPriorities,
        accusationsToday: InterventionPolicy.dailyAccusationCap,
        interruptionsToday: InterventionPolicy.dailyInterruptionCap
    )

    static func decide(
        _ judgement: NudgeJudgement,
        surroundings: NudgeSurroundings? = nil,
        memory: NudgeMemory = NudgeMemory(),
        preferences: NudgePreferences = NudgePreferences()
    ) -> NudgeDecision {
        NudgeDecider.decide(
            judgement,
            surroundings: surroundings ?? Self.surroundings(),
            memory: memory,
            preferences: preferences
        )
    }

    // MARK: - The three postures

    @Test("confident relevance is silent, and it is the only thing that buys silence")
    func confidentRelevanceIsSilent() {
        let decision = Self.decide(Self.judgement(verdict: .relevant))

        #expect(decision.isSpeaking == false)
        #expect(decision.silence?.reason == .verdictDoesNotAuthorise)
        #expect(decision.silence?.query == .verdictRelevant)
        #expect(decision.silence?.accusation == .verdictRelevant)
    }

    @Test("an askable uncertainty with a subject, a dwell and a budget asks one question")
    func uncertaintyAsks() {
        let decision = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis, subject: Self.neutral)
        )

        guard case .ask(let warrant, let route) = decision else {
            Issue.record("U-1's central case did not ask: \(decision)")
            return
        }
        #expect(warrant.reason == .noNegativeBasis)
        #expect(warrant.subject.identifier == Self.neutral)
        #expect(warrant.subject.kind == .app)
        #expect(route == .surface(.panel))
        #expect(decision.kind == .query)
    }

    @Test("all three askable uncertainties ask, and the warrant names which")
    func everyAskableReasonAsks() {
        for askable in QueryableUncertainty.allCases {
            let decision = Self.decide(
                Self.judgement(verdict: .uncertain, uncertainty: askable.reason)
            )
            #expect(decision.warrant?.reason == askable, "\(askable)")
        }
    }

    @Test("a sustained, banded, unrelated verdict enters the ladder at the ambient rung")
    func unrelatednessAccuses() {
        let decision = Self.decide(Self.judgement(verdict: .unrelated))

        guard case .accuse(let rung, let route) = decision else {
            Issue.record("a mandate did not reach the ladder: \(decision)")
            return
        }
        #expect(rung.kind == .ambient)
        #expect(rung.mandate.subject == Self.decoy)
        #expect(route == .surface(.menuBar))
        #expect(decision.kind == .accusation)
    }

    // MARK: - The unaskable five

    @Test("noEvidence is unaskable BY NAME: we did not look, so we do not ask what they were doing")
    func noEvidenceIsUnaskable() {
        let decision = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noEvidence)
        )

        #expect(decision.isSpeaking == false)
        #expect(
            decision.silence?.query == .reasonNotAskable,
            """
            `noEvidence` means the app DELIBERATELY DID NOT LOOK — a sensitive application, a \
            private window, an activation e03's gate suppressed before the engine saw it. \
            Asking "is this part of your task?" about a password manager tells the person we \
            noticed. "We did not look" must never become "tell us what you were doing" (R-77).
            """
        )
    }

    @Test("every unaskable reason is silent, and every askable one is not")
    func askabilityDecidesEntirely() {
        for reason in UncertaintyReason.allCases {
            let decision = Self.decide(
                Self.judgement(verdict: .uncertain, uncertainty: reason)
            )
            if reason.isQueryable {
                #expect(decision.warrant != nil, "\(reason) is askable and was not asked")
            } else {
                #expect(decision.warrant == nil, "\(reason) is unaskable and was asked")
                #expect(decision.silence?.query == .reasonNotAskable, "\(reason)")
            }
        }
    }

    @Test("an uncertain verdict with no reason at all is unaskable, because a question needs one")
    func anUnreasonedUncertaintyIsUnaskable() {
        let decision = Self.decide(Self.judgement(verdict: .uncertain, uncertainty: nil))
        #expect(decision.silence?.query == .reasonNotAskable)
    }

    @Test("an activation with no bundle identifier is unaskable: there is nothing to write a rule about")
    func anUnbundledActivationIsUnaskable() {
        let decision = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis, subject: nil)
        )
        #expect(decision.silence?.query == .noSingleSubject)
    }

    @Test("mixed drift has no single subject, so there is no question to ask")
    func mixedDriftHasNoQuestion() {
        let decision = Self.decide(
            Self.judgement(
                verdict: .uncertain,
                uncertainty: .noNegativeBasis,
                drift: .sustained(subject: .mixed, accumulated: .seconds(120), isMixed: true)
            )
        )
        #expect(decision.silence?.query == .noSingleSubject)
    }

    @Test("a question may come at half an accusation's dwell, but never instantly")
    func theQueryDwell() {
        let threshold = InterventionPolicy.queryDwellThreshold
        #expect(threshold * 2 == RelevancePolicy.sustainedDriftThreshold)

        let early = Self.decide(
            Self.judgement(
                verdict: .uncertain, uncertainty: .noNegativeBasis, dwelled: threshold - .seconds(1)
            )
        )
        #expect(early.silence?.query == .withinDwellGrace)

        let due = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis, dwelled: threshold)
        )
        #expect(due.warrant != nil)
    }

    // MARK: - Never twice, and the rule that is allowed to disappear

    @Test("a receipt in the ledger silences the question, and names alreadyAsked")
    func aReceiptSilencesTheQuestion() {
        let decision = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis),
            memory: NudgeMemory(hasAsked: true)
        )

        #expect(decision.warrant == nil)
        #expect(decision.silence?.reason == .alreadyAsked)
        #expect(decision.silence?.query == .alreadyAsked)
    }

    @Test("deleting the rule does not re-open the question")
    func deletingTheRuleDoesNotReOpenTheQuestion() {
        // The sequence finding 3 exposed, as the decider sees it. Answering "Yes" wrote a rule
        // AND a receipt; deleting the rule takes the subject back to `uncertain`, which is
        // exactly the input below. The receipt is the record that has not moved.
        //
        // Note what is NOT among the decider's inputs: a rule. The decider cannot read one, so
        // "whether or not the rule that answer wrote still exists" is not a branch it has — the
        // silence rests on the receipt alone, which is what R-78 requires of an invariant U-1
        // states in absolute terms.
        let afterDeletion = Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis)

        #expect(Self.decide(afterDeletion, memory: NudgeMemory(hasAsked: true)).warrant == nil)
        #expect(
            Self.decide(afterDeletion, memory: NudgeMemory(hasAsked: true)).silence?.reason
                == .alreadyAsked
        )

        // And the counter-check: with no receipt, the very same judgement asks. So the silence
        // above is the receipt's doing and nothing else's.
        #expect(Self.decide(afterDeletion, memory: NudgeMemory(hasAsked: false)).warrant != nil)
    }

    @Test("a receipt never silences an accusation: gate 11 is queries only")
    func aReceiptDoesNotSilenceAnAccusation() {
        let decision = Self.decide(
            Self.judgement(verdict: .unrelated),
            memory: NudgeMemory(hasAsked: true)
        )
        #expect(decision.rung?.kind == .ambient)
    }

    // MARK: - The twelve gates, through the decider

    @Test("gate 1: no active priority, and there is nothing to be off task from")
    func gateOne() {
        for verdict in Verdict.allCases {
            let decision = Self.decide(
                Self.judgement(verdict: verdict, hasActivePriority: false),
                surroundings: Self.surroundings(hasActivePriority: false)
            )
            #expect(decision.silence?.reason == .noActivePriority, "\(verdict)")
        }
    }

    @Test("gate 2: the global pause switch silences both kinds")
    func gateTwo() {
        for verdict in [Verdict.uncertain, .unrelated] {
            let decision = Self.decide(
                Self.judgement(verdict: verdict, uncertainty: .noNegativeBasis),
                surroundings: Self.surroundings(sensingPaused: true)
            )
            #expect(decision.silence?.reason == .sensingPaused, "\(verdict)")
        }
    }

    @Test("gate 3: a sensitive application, and the subject is never named in the answer")
    func gateThree() {
        let decision = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis),
            surroundings: Self.surroundings(sensitivity: Self.blocked)
        )
        #expect(decision.silence?.reason == .sensitiveApplication)
        #expect(decision.warrant == nil)
    }

    @Test("gate 4: any phase but focus silences both kinds")
    func gateFour() {
        for phase in SessionPhase.allCases where phase != .focus {
            let decision = Self.decide(
                Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis, phase: phase),
                surroundings: Self.surroundings(phase: phase)
            )
            #expect(decision.silence?.reason == .sessionPhaseForbids, "\(phase)")
        }
    }

    @Test("gate 5: a person who walked away is not drifting")
    func gateFive() {
        let decision = Self.decide(
            Self.judgement(verdict: .unrelated, isUserIdle: true),
            surroundings: Self.surroundings(idleSeconds: 600)
        )
        #expect(decision.silence?.reason == .userIdle)
    }

    @Test("gate 6: a panel over a call is a panel everybody on the call can see")
    func gateSix() {
        let decision = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis),
            surroundings: Self.surroundings(media: MediaActivity(microphoneRunning: true))
        )
        #expect(decision.silence?.reason == .mediaInUse)

        // And the person's own switch turns it off, without pretending the reading was not taken.
        let allowed = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis),
            surroundings: Self.surroundings(
                media: MediaActivity(microphoneRunning: true), mediaSuppressionEnabled: false
            )
        )
        #expect(allowed.warrant != nil)
    }

    @Test("gate 7: a question is suppressed over a presentation, and the glyph is DEFERRED")
    func gateSeven() {
        let question = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis),
            surroundings: Self.surroundings(presentation: Self.presenting, menuBarVisible: false)
        )
        #expect(question.silence?.reason == .presentationActive)

        // Frame 15's shape. P-131 measured the menu bar hidden during a full-screen space, so
        // the ambient rung is UNDELIVERABLE rather than unwanted: it is deferred, the ladder does
        // not advance, and no cap is spent.
        let glyph = Self.decide(
            Self.judgement(verdict: .unrelated),
            surroundings: Self.surroundings(presentation: Self.presenting, menuBarVisible: false)
        )
        #expect(glyph == .deferred(.menuBarHidden))
        #expect(glyph.isSpeaking == false)
        #expect(glyph.rung == nil, "a deferred rung must not be reported as delivered")
    }

    @Test("gate 8: the person's own quiet hours, which are not the system Focus")
    func gateEight() {
        let window = QuietHours.window(
            fromHour: 22, minute: 0, toHour: 8, minute: 0, calendar: Self.londonCalendar
        )
        let quiet = QuietHours(window: window)
        let midnight = Self.reference   // 2026-01-01T00:00:00Z, inside a 22:00–08:00 window

        for verdict in [Verdict.uncertain, .unrelated] {
            let decision = Self.decide(
                Self.judgement(verdict: verdict, uncertainty: .noNegativeBasis),
                surroundings: Self.surroundings(quietHours: quiet, now: midnight)
            )
            #expect(decision.silence?.reason == .quietHours, "\(verdict)")
        }

        // The shipped default is off, with no bundled window: a default 22:00–08:00 would be the
        // app making a claim about a person's life it has no evidence for (R-85).
        #expect(QuietHours.off.isEnabled == false)
    }

    @Test("gate 9: one open interruption at a time, and a question never takes the slot")
    func gateNine() {
        let held = InterruptionSlot(holder: .accusation(Self.ambientRung()))
        let decision = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis),
            memory: NudgeMemory(slot: held)
        )
        #expect(decision.silence?.reason == .interruptionInFlight)
        #expect(decision.warrant == nil)
    }

    @Test("gate 10: the caps, and the day's spend silences both kinds")
    func gateTen() {
        for verdict in [Verdict.uncertain, .unrelated] {
            let decision = Self.decide(
                Self.judgement(verdict: verdict, uncertainty: .noNegativeBasis),
                memory: NudgeMemory(budget: Self.exhausted)
            )
            #expect(decision.silence?.reason == .budgetExhausted, "\(verdict)")
        }
    }

    @Test("the gates are reported in R-84's order: the first that applied is the one told")
    func theFirstGateIsTheOneReported() {
        // Every gate closed at once. The reason a person is given is the first, which is the one
        // they would give themselves.
        let decision = Self.decide(
            Self.judgement(
                verdict: .uncertain, uncertainty: .noNegativeBasis, hasActivePriority: false
            ),
            surroundings: Self.surroundings(
                hasActivePriority: false,
                sensingPaused: true,
                sensitivity: Self.blocked,
                phase: .paused,
                idleSeconds: 600,
                media: MediaActivity(microphoneRunning: true),
                presentation: Self.presenting
            ),
            memory: NudgeMemory(budget: Self.exhausted, hasAsked: true)
        )
        #expect(decision.silence?.reason == .noActivePriority)
        #expect(NudgeSuppressionReason.noActivePriority.gateNumber == 1)
    }

    // MARK: - The ladder, driven through the decider

    static func ambientRung() -> LadderRung {
        let judgement = judgement(verdict: .unrelated)
        guard let mandate = judgement.eligibility.mandate else {
            preconditionFailure("the mandating cell did not mandate")
        }
        return LadderRung.entry(for: mandate)
    }

    @Test("the ladder climbs through the decider, one delivered rung at a time")
    func theLadderClimbs() {
        var ladder = LadderMachine()
        var at = Duration.seconds(10_000)
        var rungs: [LadderRung.Kind] = []

        for _ in 0..<LadderRung.Kind.allCases.count {
            let decision = Self.decide(
                Self.judgement(verdict: .unrelated),
                surroundings: Self.surroundings(monotonic: at),
                memory: NudgeMemory(ladder: ladder)
            )
            guard let rung = decision.rung else { break }
            rungs.append(rung.kind)

            // The host's own bookkeeping: the machine is offered the rung the decider chose and
            // told what became of it.
            ladder.reduce(.mandate(rung.mandate), now: at)
            ladder.offer(at: at, budgetPermits: true)
            ladder.reduce(.delivery(decision.route?.delivery ?? .suppressed(.budgetExhausted)), now: at)
            at = at + RelevancePolicy.escalationDwell
        }

        #expect(rungs == [.ambient, .panel])
    }

    @Test("a rung nobody could see does not become the rung below it on the next observation")
    func aDeferredRungDoesNotAdvance() {
        var ladder = LadderMachine()
        let at = Duration.seconds(10_000)

        // Rung 1 is deferred over a presentation.
        let deferredDecision = Self.decide(
            Self.judgement(verdict: .unrelated),
            surroundings: Self.surroundings(
                presentation: Self.presenting, menuBarVisible: false, monotonic: at
            ),
            memory: NudgeMemory(ladder: ladder)
        )
        #expect(deferredDecision == .deferred(.menuBarHidden))

        ladder.reduce(.mandate(Self.ambientRung().mandate), now: at)
        ladder.offer(at: at, budgetPermits: true)
        ladder.reduce(.delivery(.deferred(.menuBarHidden)), now: at)

        // An hour later, the presentation over: still the AMBIENT rung, not the panel. The
        // escalation clock never started, which is what `nudge.escalationsFromDeferred == 0`
        // measures.
        let resumed = Self.decide(
            Self.judgement(verdict: .unrelated),
            surroundings: Self.surroundings(monotonic: at + .seconds(3600)),
            memory: NudgeMemory(ladder: ladder)
        )
        #expect(resumed.rung?.kind == .ambient)
    }

    @Test("an engaged ladder inside the escalation dwell says nothing rather than repeating itself")
    func withinTheEscalationDwell() {
        var ladder = LadderMachine()
        let at = Duration.seconds(10_000)
        ladder.reduce(.mandate(Self.ambientRung().mandate), now: at)
        ladder.offer(at: at, budgetPermits: true)
        ladder.reduce(.delivery(.delivered(.menuBar)), now: at)

        let decision = Self.decide(
            Self.judgement(verdict: .unrelated),
            surroundings: Self.surroundings(monotonic: at + .seconds(1)),
            memory: NudgeMemory(ladder: ladder)
        )
        #expect(decision.isSpeaking == false)
        #expect(decision.silence?.reason == .budgetExhausted)
    }

    // MARK: - Neither interruption displaces the other, at the decider's level

    /// **An accusation offered while a question is open is withheld, and waits** (U-2).
    ///
    /// The decider used to answer `.accuse` here, carrying the question it had closed. Preemption
    /// is gone: the slot withholds, the stack reports `interruptionInFlight`, and the ladder is
    /// untouched — so the same rung is offered again on the next judgement, once the person has
    /// dealt with the question in front of them.
    @Test("an accusation raised over an open question is withheld rather than preempting it")
    func anAccusationWaitsForAnOpenQuestion() {
        let asked = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis, subject: Self.neutral)
        )
        guard let warrant = asked.warrant else {
            Issue.record("the question the accusation was supposed to wait for was never asked")
            return
        }

        let decision = Self.decide(
            Self.judgement(verdict: .unrelated),
            memory: NudgeMemory(slot: InterruptionSlot(holder: .query(warrant)))
        )

        #expect(decision.rung == nil, "the accusation was raised over an open question")
        #expect(decision.isSpeaking == false)
        #expect(decision.silence?.reason == .interruptionInFlight)
    }

    /// And with nothing in the slot at all, the very same judgement does speak — so the test
    /// above is about the question and not about a judgement that could never accuse.
    @Test("the same judgement accuses freely once the slot is empty")
    func theSameJudgementAccusesAgainstAnEmptySlot() {
        let decision = Self.decide(Self.judgement(verdict: .unrelated))
        #expect(decision.rung?.kind == .ambient)
        #expect(decision.isSpeaking)
    }

    // MARK: - Voices and surfaces

    @Test("the silent deck renders the panel rung as a glyph without changing the ladder")
    func theSilentDeckRoutesRatherThanSilences() {
        var ladder = LadderMachine()
        let at = Duration.seconds(10_000)
        ladder.reduce(.mandate(Self.ambientRung().mandate), now: at)
        ladder.offer(at: at, budgetPermits: true)
        ladder.reduce(.delivery(.delivered(.menuBar)), now: at)

        let decision = Self.decide(
            Self.judgement(verdict: .unrelated),
            surroundings: Self.surroundings(monotonic: at + RelevancePolicy.escalationDwell),
            memory: NudgeMemory(ladder: ladder),
            preferences: NudgePreferences(voice: .silentVisual)
        )

        // The ladder really escalated — the rung is rung 2 — and it is *rendered* as the glyph.
        #expect(decision.rung?.kind == .panel)
        #expect(decision.route == .surface(.menuBar))
    }

    @Test("reduced interruption moves the question to a badge without withdrawing it")
    func reducedInterruptionRoutesTheQuestion() {
        let decision = Self.decide(
            Self.judgement(verdict: .uncertain, uncertainty: .noNegativeBasis),
            preferences: NudgePreferences(reducedInterruption: true)
        )
        #expect(decision.warrant != nil)
        #expect(decision.route == .surface(.popoverBadge))
    }

    /// **No rung reaches a notification, in any authorisation state** (U-2).
    ///
    /// This used to assert that the top rung went to a notification wherever the system would
    /// carry one. The notification was the recommitment rung's surface and nothing else's, and
    /// that rung is deferred to focus-5ab — so the whole system surface left the ladder with it.
    ///
    /// Asserted across every authorisation value rather than at one point, because that is what
    /// makes R-82.2's *"denied and notRequested behave identically"* true by construction now: the
    /// authorisation cannot change any cell, so the ladder is entirely in-app whatever the person
    /// has or has not granted. That is what discharges standing condition 5.
    @Test("no rung routes to a notification, whatever the authorisation says")
    func noRungReachesANotification() {
        var ladder = LadderMachine()
        var at = Duration.seconds(10_000)
        // One delivered rung, so the next offer is the panel — which is the top of the ladder now.
        ladder.reduce(.mandate(Self.ambientRung().mandate), now: at)
        ladder.offer(at: at, budgetPermits: true)
        ladder.reduce(.delivery(.delivered(.menuBar)), now: at)
        at = at + RelevancePolicy.escalationDwell

        for authorisation in NotificationAuthorisation.allCases {
            let decision = Self.decide(
                Self.judgement(verdict: .unrelated),
                surroundings: Self.surroundings(monotonic: at),
                memory: NudgeMemory(ladder: ladder),
                preferences: NudgePreferences(authorisation: authorisation)
            )
            #expect(decision.rung?.kind == .panel, "\(authorisation)")
            #expect(decision.route?.surface?.isInApp == true, "\(authorisation)")
            #expect(decision.route != .surface(.notification), "\(authorisation)")
        }
    }

    // MARK: - The invariant that outranks every other in the epic

    @Test("no input yields an accusation from an uncertain verdict, and none yields both")
    func theWholeTruthTable() {
        var cells = 0
        var asks = 0
        var accusations = 0

        let reasons: [UncertaintyReason?] = UncertaintyReason.allCases.map { $0 } + [nil]
        let drifts: [DriftState] = [
            .aligned,
            .sustained(subject: .single(Self.decoy), accumulated: .seconds(200), isMixed: false)
        ]
        let budgets = [InterruptionBudget.empty, Self.exhausted]

        for verdict in Verdict.allCases {
            for band in EvidenceBand.allCases {
                for reason in reasons {
                    for phase in SessionPhase.allCases {
                        for status in FocusStatus.allCases {
                            for drift in drifts {
                                for hasAsked in [false, true] {
                                    for budget in budgets {
                                        cells += 1

                                        let decision = Self.decide(
                                            Self.judgement(
                                                verdict: verdict,
                                                uncertainty: reason,
                                                band: band,
                                                drift: drift,
                                                status: status,
                                                phase: phase
                                            ),
                                            surroundings: Self.surroundings(phase: phase),
                                            memory: NudgeMemory(
                                                budget: budget, hasAsked: hasAsked
                                            )
                                        )

                                        switch decision {
                                        case .accuse:
                                            accusations += 1
                                            #expect(
                                                verdict == .unrelated,
                                                "an accusation from \(verdict)/\(String(describing: reason))"
                                            )
                                        case .ask:
                                            asks += 1
                                            #expect(
                                                verdict == .uncertain,
                                                "a question from \(verdict)"
                                            )
                                            #expect(hasAsked == false, "a question that was already asked")
                                        case .silent, .deferred:
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        #expect(cells == 19_440)
        #expect(accusations > 0, "the table never reached an accusation at all")
        #expect(asks > 0, "the table never reached a question at all")
    }

    @Test("the decision is a function of its inputs: two runs give the same answer")
    func theDeciderIsPure() {
        let judgement = Self.judgement(verdict: .uncertain, uncertainty: .mixedUseApplication)
        #expect(Self.decide(judgement) == Self.decide(judgement))

        let mandated = Self.judgement(verdict: .unrelated)
        #expect(Self.decide(mandated) == Self.decide(mandated))
    }
}
