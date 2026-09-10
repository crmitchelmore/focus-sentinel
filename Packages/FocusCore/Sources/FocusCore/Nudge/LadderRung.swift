import Foundation

/// **One rung of the accusation ladder**, and the type that makes "a query cannot escalate
/// into an accusation" a fact rather than a promise.
///
/// The Court ruled three stages (D-06) and e05 shipped three. **U-2 amended that ruling to two**:
/// the ambient glyph and a single panel nudge. The third rung — explicit recommitment, and the
/// escalation from the panel to it — is deferred to epic focus-5ab, to be designed cleanly rather
/// than repaired, and is removed from the shipping product rather than left behind a flag.
///
/// What makes this type load-bearing is not the count but the **provenance**: a rung is the
/// accusation's unit of escalation, so where a rung can come from *is* the no-escalation
/// invariant.
///
/// * The memberwise initialiser is `fileprivate`, and this file holds exactly two producers —
///   `entry(for:)` and `escalated(for:)` — both of which start from an `InterventionMandate`.
/// * There is **no overload taking a `QueryWarrant`, a `Verdict` or a `Bool`.** A question
///   carries no band and no stage, which the ladder requires, so an adapter could not be
///   written without inventing evidence — and inventing evidence is visible in a diff.
/// * `check-forbidden.sh` asserts (R-96c) that `LadderRung(` appears in exactly one source
///   file, that the file names `InterventionMandate`, and that it does **not** name
///   `QueryWarrant`.
///
/// Together with `QueryWarrant`'s own single producer and the ban on a shared protocol
/// (R-96d), that is the third of R-76's four structural facts.
public struct LadderRung: Sendable, Equatable, Hashable {
    /// The two stages, in escalation order.
    ///
    /// Rank is derived from `allCases`, exactly as `CascadeStage.rank` and `EvidenceBand.rank`
    /// are, so the order is a property of the declaration and no numeric literal appears
    /// (R-96j).
    public enum Kind: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
        /// Rank 0. The menu-bar glyph changes to `unrelated`, and nothing else happens: no
        /// panel, no sound, no motion. Under Reduce Motion it is a shape and label change
        /// only. e08 adds the notch as a second renderer of this same rung.
        case ambient
        /// Rank 1. The non-activating `NSPanel` with the full correction economy — the first
        /// thing that asks for attention, and now the last. The ladder tops out here.
        case panel

        /// **Whether this rung says something to the person that they could answer** (focus-uru).
        ///
        /// The glyph does not. It changes colour and shape and it accuses nobody: R-87 keeps it
        /// on through a snooze precisely because it is a *state*, not a sentence, and there is
        /// nothing on it a person could be asked to press. Every rung above it makes an
        /// accusation, and an accusation must land somewhere the person can answer back.
        ///
        /// Derived from the rank rather than written out, so a third rung added above the panel
        /// inherits the obligation instead of quietly escaping it — which is what the
        /// recommitment rung deferred to focus-5ab will do when it returns.
        public var makesAnAccusation: Bool { rank > 0 }

        /// Where this rung sits. 0, 1 — derived, never written down.
        public var rank: Int {
            Self.allCases.firstIndex(of: self) ?? Self.allCases.count
        }

        /// The rung above this one, or `nil` at the top. The ladder tops out at the panel; the
        /// recommitment rung above it is deferred to focus-5ab, and there was never any coercion
        /// above that either (D-07, R-99).
        public var next: Kind? {
            let index = rank + 1
            return index < Self.allCases.count ? Self.allCases[index] : nil
        }

        /// The String Catalog key for this rung's label. `check-strings.sh` asserts the
        /// bijection with `nudge.rung.*` in both directions (R-96l).
        ///
        /// **A rung's label names the rung, never the surface it lands on** (focus-91d). The
        /// Intervention pane draws this beside `SurfaceRouter`'s own route, one column each, and
        /// `.panel` read *"A small panel you can answer"* — so under the Silent-and-visual deck
        /// the row said **"A small panel you can answer │ Menu bar"**, and under reduced
        /// interruption every deck said it beside "The menu-bar popover". The same resource is
        /// the popover's *"Current nudge: …"* row, which has no second column to correct it.
        ///
        /// **That row's own label was wrong in the other direction** (focus-7to). It read
        /// *"Next nudge"* over `LadderState.rung`, which is the rung currently occupied — so the
        /// popover named a scheduled step beside a rung already on screen, and the ladder
        /// schedules nothing: `escalated(for:)` below says only what the next rung *would be*, and
        /// four further facts decide whether it is ever reached.
        ///
        /// A rung is one step of the ladder; where it appears is the router's answer and changes
        /// with the deck, the flag, a running microphone and a hidden menu bar.
        /// `InterventionSettingsTests.noRungIsNamedForASurface` holds the two vocabularies apart
        /// over every deck and both flags.
        public var copyKey: String {
            switch self {
            case .ambient: "nudge.rung.ambient"
            case .panel: "nudge.rung.panel"
            }
        }

        public var copyResource: LocalizedStringResource {
            LocalizedStringResource(
                String.LocalizationValue(copyKey),
                bundle: .atURL(Bundle.module.bundleURL)
            )
        }

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rank < rhs.rank }
    }

    /// Which stage this is.
    public let kind: Kind
    /// **The authorisation this rung exists on.** Not a `Verdict`, not a `Bool`, not a
    /// `QueryWarrant`: the one type e04 made unconstructible from an `uncertain` verdict.
    public let mandate: InterventionMandate

    /// **Fileprivate on purpose**, with exactly two callers, both in this file.
    fileprivate init(kind: Kind, mandate: InterventionMandate) {
        self.kind = kind
        self.mandate = mandate
    }

    /// The rung a ladder enters at, for a fresh mandate.
    ///
    /// **Always `.ambient`.** The ladder never re-enters at the rung it left: a person who came
    /// back and drifted again starts at the silent glyph, because starting at the notification
    /// would punish them for having complied once (R-80).
    public static func entry(for mandate: InterventionMandate) -> LadderRung {
        LadderRung(kind: Kind.allCases[0], mandate: mandate)
    }

    /// The next rung up, **for the mandate the ladder is climbing on now**, or `nil` at the top.
    ///
    /// Whether escalation is *permitted* is `LadderMachine`'s question and needs three more
    /// facts — a still-live mandate, a **delivered** previous rung (R-81) whose delivery is still
    /// the ladder's business, and budget (R-83). This function only says what the next rung
    /// would be.
    ///
    /// **The mandate is a parameter, and that is the whole of focus-f2a's second half.** It read
    /// `self.mandate` — the authorisation the rung *below* was raised on — which was sound only
    /// because `LadderMachine` refused to escalate unless the live mandate named the same subject.
    /// The ruling that a subject change continues the climb removes that guarantee, and a rung
    /// built from the old mandate would be a panel naming the application the person has already
    /// left: `AccusationPanelView` draws `rung.subject`, and the correction it offers is scoped by
    /// `CorrectionScope.from(rung.mandate)`, so the sentence *and* the rule would both be about
    /// the wrong thing. Asking the caller for the mandate makes that a question the compiler puts,
    /// once, at every site that can produce a rung.
    public func escalated(for mandate: InterventionMandate) -> LadderRung? {
        guard let next = kind.next else { return nil }
        return LadderRung(kind: next, mandate: mandate)
    }

    /// The subject this rung is about, or `nil` when drift accumulated across several and a
    /// surface must say "several unrelated apps" rather than misnaming one of them.
    public var subject: String? {
        mandate.isMixed || mandate.subject.isEmpty ? nil : mandate.subject
    }
}

/// Where the ladder has got to.
///
/// A value, reduced by a pure function on an injected `MonotonicClock` reading — e03's R-46
/// doctrine and e04's `DriftState`, applied to the third state machine that needed it. There is
/// no timer object anywhere in the nudge, and R-96i is the lint that keeps it that way; that is
/// what makes every sequence fixture an exact assertion rather than a flaky one.
public enum LadderState: Sendable, Equatable, Hashable {
    /// Nothing is escalating. The state a correction, a snooze, a pause, a priority change, a
    /// return to task, a phase change out of `.focus` or a `relevant` verdict resets to —
    /// immediately and totally (R-80).
    case idle
    /// A rung has been **delivered** and the ladder is waiting.
    ///
    /// - Parameters:
    ///   - rung: what was delivered.
    ///   - deliveredAt: the monotonic reading of that delivery. `escalationDwell` is measured
    ///     from here, which is why a `.deferred` rung must never write it (R-81).
    ///   - consecutiveIgnored: delivered rungs since the last correction, snooze, pause or
    ///     return. At `InterventionPolicy.ignoredAccusationBackoff` the ladder holds.
    case engaged(rung: LadderRung, deliveredAt: Duration, consecutiveIgnored: Int)
    /// The person has ignored `ignoredAccusationBackoff` rungs in a row, so the ladder has
    /// dropped back to the ambient rung and holds there for the rest of the session.
    ///
    /// It does **not** go fully silent: the glyph still tells the truth, because that is the
    /// one channel the person has not objected to and F-146's whole point is that the state is
    /// always legible.
    case heldAtAmbient(rung: LadderRung, since: Duration)

    /// The rung currently occupied, if any.
    public var rung: LadderRung? {
        switch self {
        case .idle: nil
        case .engaged(let rung, _, _): rung
        case .heldAtAmbient(let rung, _): rung
        }
    }

    /// How many delivered rungs have gone unanswered.
    public var consecutiveIgnored: Int {
        switch self {
        case .idle, .heldAtAmbient: 0
        case .engaged(_, _, let count): count
        }
    }

    /// **The closed set of ladder states, payloads discarded** (focus-628, focus-1ua).
    ///
    /// `LadderState` carries a rung, a monotonic reading and a run count, so it cannot be
    /// `CaseIterable` itself — which is exactly the position `FatigueRefusal` was in one round
    /// ago, and for six rounds that meant the one answer to *"why did the app go quiet?"* nothing
    /// could fold over was the one accumulating defects. `FatigueRefusal.Kind` is the shape that
    /// ended it and this is the same shape: `allCases` is what `LadderSilenceTests` walks, so a
    /// fourth state cannot reach a person without a witness row driving it.
    public enum Kind: String, Sendable, CaseIterable, Codable, Hashable {
        case idle
        case engaged
        case heldAtAmbient
    }

    /// Which state this is, payload discarded.
    public var kind: Kind {
        switch self {
        case .idle: .idle
        case .engaged: .engaged
        case .heldAtAmbient: .heldAtAmbient
        }
    }

    /// **The rung the ladder has DELIVERED and is still standing on**, if any (focus-50m).
    ///
    /// Not `rung`, and the difference is the whole of this round. `.heldAtAmbient` *occupies* the
    /// ambient rung — `rung` answers it — but that rung was never delivered: `ignore(now:)` puts
    /// the ladder down onto a rung built from the mandate, and nothing has shown it to anybody.
    /// So a caller asking *"is there something on screen the person can see?"* must ask this and
    /// not `rung`, and the hold's answer is `nil`: the mark is still owed.
    public var deliveredRung: LadderRung? {
        switch self {
        case .idle, .heldAtAmbient: nil
        case .engaged(let rung, _, _): rung
        }
    }

    /// **The hold, with its expiry applied** (focus-50m, focus-845).
    ///
    /// `FatigueController`'s twin hold was time-bounded to `InterventionPolicy.backoffSpan` by
    /// focus-845, on the argument that *"a backoff this app imposes lasts an hour, whichever kind
    /// of interruption tripped it"* — and the ladder's own hold, the one whose case name that
    /// refusal borrows, was left with no expiry at all. Two ignored rungs held it **for the rest
    /// of the session**, which is a sentence no other backoff in this app is allowed to say.
    ///
    /// A pure function of an injected reading rather than a mutation on a timer (R-96i), so a
    /// replayed transcript expires the hold at the same instant twice.
    public func afterTheHoldExpires(at now: Duration, tunings: PolicyTunings = .shipped) -> LadderState {
        guard case .heldAtAmbient(_, let since) = self else { return self }
        return now - since >= tunings.duration(.backoffSpan) ? .idle : self
    }
}

/// **Why the ladder had nothing to climb to** — the fourth answer to *"why did the app go
/// quiet?"*, and the one that had no vocabulary (focus-628, focus-50m, focus-1ua).
///
/// ## The defect this type is
///
/// `SilenceSubject`'s own doc states the rule absolutely: *"every reason the app has for going
/// quiet declares its subject here, the evaluation applies it, and a new reason cannot be added
/// without answering the question"*, and it names the two exhaustive switches that enforce it —
/// `NudgeSuppressionReason.subject` and `FatigueRefusal.Kind.subject`. **`LadderMachine` was the
/// third and it was in neither.** It silenced by *arithmetic* rather than by a gate:
/// `candidate(at:budgetPermits:)` answered `nil`, `NudgeDecider.accuse(…)` turned that `nil` into
/// `.silent(.budgetExhausted)`, and **the glyph went with it** — the one channel R-87, F-63 and
/// F-146 all exempt by name, lost to a missing case rather than to any ruling.
///
/// This is `FatigueRefusal`'s position one round ago exactly, same table row with a new occupant,
/// and it had already produced its first defect (focus-fzf) before it was folded.
///
/// ## The two facts each case declares, and the one derivation
///
/// * `subject` — what the silence is **about**, in `SilenceSubject`'s vocabulary. Four of the
///   five are about the app *speaking*; the fifth is about there being anything to be legible
///   about at all.
/// * `refusesTheClimb` — whether something **stopped** the ladder, or whether the ladder is
///   simply pacing itself. A refusal is somebody else's answer — a hold, a cap, a mandate that
///   does not exist — and the rung the ladder last delivered may be long gone. The dwell is not:
///   the rung it delivered a moment ago is still standing, still true, and re-delivering it would
///   restart the very clock the dwell measures, so a ladder that "retained" its glyph through a
///   dwell would never climb again.
///
/// `retainsTheAmbientRung` is the two of them put together, once, and it is the answer the
/// decider reads instead of collapsing a `nil`.
public enum LadderSilence: String, Sendable, CaseIterable, Codable, Hashable {
    /// No mandate is live. The ladder is climbing for nobody.
    case noLiveMandate
    /// `RelevancePolicy.escalationDwell` has not elapsed since the last **delivery**. The ladder
    /// has already said what it has to say for now, and the rung that said it is still standing.
    case escalationDwell
    /// The budget refused the escalation (fact 4). Read only when a caller asks with
    /// `budgetPermits: false`; `NudgeDecider` asks with `true` and reads the refusal itself, so
    /// that the *reason* reaches the log rather than a `Bool`.
    case budgetRefused
    /// The ladder is standing on the loudest rung it has and there is nothing above it (U-2).
    case toppedOut
    /// `InterventionPolicy.ignoredAccusationBackoff` rungs went unanswered, so the ladder came
    /// **down** to the ambient rung and holds there until `InterventionPolicy.backoffSpan`.
    ///
    /// It does not go silent, and until focus-50m it did: the rung it came down to was never
    /// delivered, `candidate(at:budgetPermits:)` answered `nil`, and the state the app calls
    /// *"the glyph still tells the truth"* showed the person nothing at all.
    case heldAtAmbient

    /// **What this silence is about, and therefore which rungs it may silence** (focus-uru,
    /// focus-628).
    ///
    /// Four of the five are about the app **speaking**: an escalation delayed, an escalation
    /// refused, an escalation that does not exist, and a ladder held below the rung that speaks.
    /// None of them is a reason to stop marking somebody who is off task, which is what
    /// `SilenceSubject.ruling(for:)` says for them and what the arithmetic said the opposite of.
    ///
    /// `noLiveMandate` is the fifth and it is the one legibility case: with no mandate there is
    /// nothing to be off task **about**, so a glyph that went on marking would not be telling the
    /// truth — and the whole argument for exempting it is that it tells the truth.
    public var subject: SilenceSubject {
        switch self {
        case .noLiveMandate: .anythingToBeLegibleAbout
        case .escalationDwell, .budgetRefused, .toppedOut, .heldAtAmbient: .theAppSpeaking
        }
    }

    /// **Whether something stopped the ladder, or the ladder is pacing itself.**
    ///
    /// The distinction decides whether the app still owes the person a mark, and it is not
    /// derivable from the subject: `escalationDwell` and `heldAtAmbient` are both about the app
    /// speaking and only one of them leaves the person unmarked.
    ///
    /// * `noLiveMandate` — the climb has no subject. A refusal, and the strongest one: its
    ///   subject stops every rung, which is why this property alone is not the answer.
    /// * `budgetRefused`, `heldAtAmbient` — a cap, a cooldown or a backoff said no. The rung the
    ///   ladder last delivered may have ended an hour ago; the person is still drifting.
    /// * `escalationDwell`, `toppedOut` — the ladder's own pacing, and in both the rung it
    ///   delivered is **still standing**: the glyph within the dwell, the panel at the top. There
    ///   is nothing new to show, and showing it again would take a sentence down to replace it
    ///   with a mark.
    public var refusesTheClimb: Bool {
        switch self {
        case .noLiveMandate, .budgetRefused, .heldAtAmbient: true
        case .escalationDwell, .toppedOut: false
        }
    }

    /// **Whether the app still owes the person the rung that says nothing.**
    ///
    /// The two facts above put together, in one place, exactly as `SilenceSubject.ruling(for:)`
    /// is the one application of its own rule. `true` for `budgetRefused` and `heldAtAmbient`;
    /// `false` for `noLiveMandate`, whose subject stops every rung, and for the two where the
    /// ladder's own delivery is still on screen.
    public var retainsTheAmbientRung: Bool {
        refusesTheClimb && subject.ruling(for: .ambient) == .passes
    }
}

/// **What the ladder would do now**: climb to a rung, or go quiet for a reason it can name.
///
/// The type that replaces `LadderRung?`. A `nil` candidate was four different facts collapsed
/// into one, and the collapse is what let `NudgeDecider.accuse(…)` report every one of them as
/// `.budgetExhausted` and take the glyph with it.
public enum LadderOffer: Sendable, Equatable, Hashable {
    case rung(LadderRung)
    case silent(LadderSilence)

    /// The rung, or `nil`. The shape `candidate(at:budgetPermits:)` keeps for callers that only
    /// want to know whether there is one.
    public var rung: LadderRung? {
        switch self {
        case .rung(let rung): rung
        case .silent: nil
        }
    }

    public var silence: LadderSilence? {
        switch self {
        case .rung: nil
        case .silent(let silence): silence
        }
    }
}

/// The things that end a ladder outright.
///
/// De-escalation is **immediate and total** (R-80): any one of these resets the state to
/// `.idle`, and re-entry is at the ambient rung. There is no partial climb-down, because a
/// ladder that remembered where it was would punish somebody for having complied.
public enum LadderDeEscalation: String, Sendable, CaseIterable, Codable, Hashable {
    /// "This is relevant" — the correction that removes the subject from the accusable set
    /// entirely, and therefore suppresses harder than any ignore (R-83).
    case corrected
    /// "Not this time" — a session-lived rule through e04's `SessionRuleBox`.
    case excusedForThisSession
    case snoozed
    case paused
    case priorityChanged
    case returnedToTask
    /// The session left `.focus` — a break, a deliberate detour, an interruption, completion.
    case phaseLeftFocus
    /// The engine now says this is real work.
    case verdictRelevant
    case sessionEnded
}

/// What the ladder's reducer consumes.
///
/// Declared here, with the rest of the vocabulary, so that `LadderMachine` (T129) is a pure
/// function over values that already exist rather than a machine that invents its own inputs.
public enum LadderEvent: Sendable, Equatable, Hashable {
    /// A live mandate for a subject was observed.
    case mandate(InterventionMandate)
    /// What actually happened when the app tried to speak. **`.deferred` does not advance the
    /// ladder, does not spend either cap and does not start the escalation clock** (R-81).
    case delivery(RungDelivery)
    /// A delivered rung went unanswered — no correction, snooze, pause or return.
    case rungIgnored
    /// Something happened that ends the ladder.
    case deEscalated(LadderDeEscalation)
    /// Time passed and nothing else did. Carries the monotonic reading, so a replay is exact.
    case tick(Duration)
}
