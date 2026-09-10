import Foundation
import Testing

@testable import FocusCore

/// The twelve gates, in order — and the assertion that eight of them are e01–e04's code being
/// *wired* rather than re-implemented (R-84, R-85, F-118, F-119, F-35, F-36, F-32).
///
/// Under U-1 the app speaks more, so suppression correctness matters **more**, not less.
@Suite("Suppression stack")
struct SuppressionStackTests {
    // MARK: - A permitting baseline, and one knob per gate

    static let reference = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01T00:00:00Z

    static var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    static let cleared = SensitivityGate().evaluate(
        FrontmostActivation(
            bundleIdentifier: "com.chrismitchelmore.FocusDecoy",
            localizedName: "Focus Decoy",
            pid: 4242,
            at: reference,
            dwellSeconds: 120
        )
    )

    static let blocked = SensitivityGate().evaluate(
        FrontmostActivation(
            bundleIdentifier: "com.apple.keychainaccess",
            localizedName: "Keychain Access",
            pid: 4243,
            at: reference,
            dwellSeconds: 120
        )
    )

    static let presenting = PresentationState(
        signals: PresentationSignals(
            frontmostWindowFillsAScreen: true,
            presentationOptionsSayFullScreen: true,
            menuBarHidden: true
        ),
        isUserExcluded: false,
        isPresenting: true
    )

    /// Every gate open. Each test below closes exactly one and asserts the answer.
    static func evaluate(
        kind: InterruptionKind = .query,
        rung: LadderRung.Kind? = nil,
        hasActivePriority: Bool = true,
        sensingPaused: Bool = false,
        sensitivity: SensitiveScreenDecision = SuppressionStackTests.cleared,
        phase: SessionPhase = .focus,
        idleSeconds: Double = 0,
        idleThresholdSeconds: Double = 180,
        media: MediaActivity = .idle,
        mediaSuppressionEnabled: Bool = true,
        presentation: PresentationState = .notPresenting,
        quietHours: QuietHours = .off,
        now: Date = SuppressionStackTests.reference,
        calendar: Calendar = SuppressionStackTests.londonCalendar,
        interruptionInFlight: Bool = false,
        budgetPermits: Bool = true,
        hasAsked: Bool = false,
        verdictAuthorises: Bool = true
    ) -> SuppressionOutcome {
        SuppressionStack.evaluate(
            kind: kind,
            rung: rung,
            hasActivePriority: hasActivePriority,
            sensingPaused: sensingPaused,
            sensitivity: sensitivity,
            phase: phase,
            idle: IdleReading(hardwareSeconds: idleSeconds, sessionSeconds: idleSeconds),
            idleThresholdSeconds: idleThresholdSeconds,
            media: media,
            mediaSuppressionEnabled: mediaSuppressionEnabled,
            presentation: presentation,
            quietHours: quietHours,
            now: now,
            calendar: calendar,
            interruptionInFlight: interruptionInFlight,
            budgetPermits: budgetPermits,
            hasAsked: hasAsked,
            verdictAuthorises: verdictAuthorises
        )
    }

    // MARK: - Twelve gates, declared in evaluation order

    @Test("there are twelve gates and their declaration order is their evaluation order")
    func twelveGatesInOrder() {
        #expect(NudgeSuppressionReason.allCases.count == 12)
        #expect(
            NudgeSuppressionReason.allCases.map(\.rawValue) == [
                "noActivePriority", "sensingPaused", "sensitiveApplication",
                "sessionPhaseForbids", "userIdle", "mediaInUse", "presentationActive",
                "quietHours", "interruptionInFlight", "budgetExhausted", "alreadyAsked",
                "verdictDoesNotAuthorise"
            ]
        )
        #expect(NudgeSuppressionReason.allCases.map(\.gateNumber) == Array(1...12))
        #expect(NudgeSuppressionReason.alreadyAsked.gateNumber == 11)
        #expect(NudgeSuppressionReason.verdictDoesNotAuthorise.gateNumber == 12)
    }

    @Test("with every gate open the app may speak")
    func baselineIsPermitted() {
        #expect(Self.evaluate() == .permitted)
        #expect(Self.evaluate(kind: .accusation, rung: .panel) == .permitted)
    }

    /// **The ordering contract**: each gate is reached only when every earlier one has cleared.
    ///
    /// Closed one at a time from the bottom up, each closure is added to the ones below it and
    /// the answer must be the **earliest** gate closed — which is the reason a person would
    /// give for the same moment.
    @Test("the reason reported is always the first gate that applied")
    func orderingContract() {
        // Each row closes one gate; rows are applied cumulatively from the bottom.
        var closures: [(String, NudgeSuppressionReason, (inout Knobs) -> Void)] = [
            ("no priority", .noActivePriority, { $0.hasActivePriority = false }),
            ("sensing paused", .sensingPaused, { $0.sensingPaused = true }),
            ("sensitive app", .sensitiveApplication, { $0.sensitivity = Self.blocked }),
            ("phase", .sessionPhaseForbids, { $0.phase = .onBreak }),
            ("idle", .userIdle, { $0.idleSeconds = 600 }),
            ("media", .mediaInUse, { $0.media = MediaActivity(microphoneRunning: true) }),
            ("presentation", .presentationActive, { $0.presentation = Self.presenting }),
            ("quiet hours", .quietHours, { $0.quietHours = Self.allDayQuietHours }),
            ("in flight", .interruptionInFlight, { $0.interruptionInFlight = true }),
            ("budget", .budgetExhausted, { $0.budgetPermits = false }),
            ("asked", .alreadyAsked, { $0.hasAsked = true }),
            ("verdict", .verdictDoesNotAuthorise, { $0.verdictAuthorises = false })
        ]
        #expect(closures.count == NudgeSuppressionReason.allCases.count)

        // Bottom-up: close the last gate, then the last two, and so on. The answer must always
        // be the earliest gate in the closed set.
        for cut in stride(from: closures.count - 1, through: 0, by: -1) {
            var knobs = Knobs()
            for index in cut..<closures.count { closures[index].2(&knobs) }
            let outcome = knobs.evaluate()
            let observed = String(describing: outcome)
            let expected = closures[cut].1.rawValue
            #expect(
                outcome.suppressionReason == closures[cut].1,
                "closing gates \(cut + 1)…12 reported \(observed) rather than \(expected)"
            )
        }

        // And top-down: opening the earliest gate reveals the next one, in order.
        for cut in 0..<closures.count {
            var knobs = Knobs()
            for index in cut..<closures.count { closures[index].2(&knobs) }
            #expect(knobs.evaluate().suppressionReason == closures[cut].1)
        }
    }

    /// A mutable bag of the same defaults, so the ordering test can close gates cumulatively
    /// without a twelve-argument call at every step.
    struct Knobs {
        var kind: InterruptionKind = .query
        var rung: LadderRung.Kind?
        var hasActivePriority = true
        var sensingPaused = false
        var sensitivity: SensitiveScreenDecision = SuppressionStackTests.cleared
        var phase: SessionPhase = .focus
        var idleSeconds: Double = 0
        var media: MediaActivity = .idle
        var presentation: PresentationState = .notPresenting
        var quietHours: QuietHours = .off
        var interruptionInFlight = false
        var budgetPermits = true
        var hasAsked = false
        var verdictAuthorises = true

        func evaluate() -> SuppressionOutcome {
            SuppressionStackTests.evaluate(
                kind: kind, rung: rung, hasActivePriority: hasActivePriority,
                sensingPaused: sensingPaused, sensitivity: sensitivity, phase: phase,
                idleSeconds: idleSeconds, media: media, presentation: presentation,
                quietHours: quietHours, interruptionInFlight: interruptionInFlight,
                budgetPermits: budgetPermits, hasAsked: hasAsked,
                verdictAuthorises: verdictAuthorises
            )
        }
    }

    /// A window covering the whole day in the London calendar, for the ordering test.
    static var allDayQuietHours: QuietHours {
        QuietHours(
            window: QuietHours.window(
                fromHour: 0, minute: 0, toHour: 23, minute: 59, calendar: londonCalendar
            )
        )
    }

    // MARK: - Gates 3–7 are reached through the types that own them

    /// **Nothing here is re-implemented.** Each of the five e03 gates is closed by moving the
    /// *shipped* type's own answer, not by flipping a boolean this module invented — so a
    /// change to `SensitivityGate`'s list, to `SessionPhase.permitsIntervention`, to
    /// `IdleReading.isIdle(threshold:)`, to `MediaActivity.suppressesIntervention` or to
    /// `PresentationState.suppressesOverlays` moves this stack with it.
    @Test("gates 3 to 7 are reached through the e03 types that own them")
    func gatesReachThroughTheirOwners() {
        // 3 — SensitivityGate. The gate's own decision, on a bundle identifier that is on its
        // own built-in list. Nothing here knows what a sensitive application is.
        #expect(Self.blocked.clearedActivation == nil)
        #expect(Self.blocked.suppressionReason != nil)
        #expect(Self.evaluate(sensitivity: Self.blocked).suppressionReason == .sensitiveApplication)
        #expect(Self.cleared.clearedActivation != nil)

        // 4 — SessionPhase.permitsIntervention: `.focus` alone, and every other phase closes.
        for phase in SessionPhase.allCases where phase != .focus {
            #expect(!phase.permitsIntervention)
            #expect(
                Self.evaluate(phase: phase).suppressionReason == .sessionPhaseForbids,
                "\(phase.rawValue) did not close gate 4"
            )
        }
        #expect(SessionPhase.focus.permitsIntervention)

        // 5 — IdleReading.isIdle(threshold:), against the user's own threshold rather than a
        // number this module chose.
        let reading = IdleReading(hardwareSeconds: 600, sessionSeconds: 600)
        #expect(reading.isIdle(threshold: 180))
        #expect(!reading.isIdle(threshold: 900))
        #expect(Self.evaluate(idleSeconds: 600).suppressionReason == .userIdle)
        #expect(Self.evaluate(idleSeconds: 600, idleThresholdSeconds: 900) == .permitted)

        // 6 — MediaActivity.suppressesIntervention, and the user's own switch above it.
        let onACall = MediaActivity(microphoneRunning: true)
        #expect(onACall.suppressesIntervention)
        #expect(Self.evaluate(media: onACall).suppressionReason == .mediaInUse)
        #expect(Self.evaluate(media: onACall, mediaSuppressionEnabled: false) == .permitted)
        #expect(
            Self.evaluate(media: MediaActivity(microphoneRunning: false, cameraRunning: true))
                .suppressionReason == .mediaInUse
        )

        // 7 — PresentationState.suppressesOverlays.
        #expect(Self.presenting.suppressesOverlays)
        #expect(!PresentationState.notPresenting.suppressesOverlays)
        #expect(
            Self.evaluate(presentation: Self.presenting).suppressionReason == .presentationActive
        )
    }

    /// **R-81 in the stack.** The panel and the question are *suppressed* by a presentation;
    /// the silent ambient rung is *deferred*, because the menu bar is hidden (P-131) and an
    /// undeliverable rung is not a delivered rung.
    @Test("a presentation defers the ambient rung and suppresses everything else")
    func presentationDefersTheAmbientRung() {
        let ambient = Self.evaluate(
            kind: .accusation, rung: .ambient, presentation: Self.presenting
        )
        #expect(ambient == .deferred(.menuBarHidden))
        #expect(ambient.suppressionReason == nil, "a deferral was reported as a suppression")
        #expect(ambient.deferralReason == .menuBarHidden)

        for rung in [LadderRung.Kind.panel] {
            #expect(
                Self.evaluate(kind: .accusation, rung: rung, presentation: Self.presenting)
                    == .suppressed(.presentationActive)
            )
        }
        #expect(
            Self.evaluate(kind: .query, presentation: Self.presenting)
                == .suppressed(.presentationActive)
        )
    }

    // MARK: - Gate 11 is the query's alone

    /// Never-ask-twice is a **question's** gate. An accusation passes straight through it: the
    /// app having asked about Safari yesterday says nothing about whether somebody is off task
    /// in it today.
    @Test("gate 11 applies to queries only; an accusation passes straight through")
    func alreadyAskedIsQueryOnly() {
        #expect(Self.evaluate(kind: .query, hasAsked: true).suppressionReason == .alreadyAsked)
        #expect(
            Self.evaluate(kind: .accusation, rung: .panel, hasAsked: true) == .permitted,
            "an accusation was suppressed by a question's receipt"
        )

        #expect(NudgeSuppressionReason.alreadyAsked.appliesTo == [.query])
        for reason in NudgeSuppressionReason.allCases where reason != .alreadyAsked {
            #expect(reason.appliesTo == [.query, .accusation], "\(reason.rawValue) is kind-specific")
        }
    }

    // MARK: - Quiet hours (R-85)

    /// The shipped default is **off**, with no bundled window. A default of 22:00–08:00 would
    /// be the app making a claim about a person's life it has no evidence for.
    @Test("quiet hours ship off and suppress nothing")
    func quietHoursDefaultIsOff() {
        #expect(!QuietHours.off.isEnabled)
        #expect(QuietHours.off.window == nil)
        for hour in 0..<24 {
            let instant = Self.instant(hour: hour, minute: 30)
            #expect(!QuietHours.off.isQuiet(at: instant, calendar: Self.londonCalendar))
        }
        #expect(Self.evaluate(quietHours: .off) == .permitted)
    }

    @Test("a window that does not wrap covers exactly its own hours")
    func windowWithoutWrap() throws {
        let window = try #require(
            QuietHours.window(
                fromHour: 13, minute: 0, toHour: 14, minute: 0, calendar: Self.londonCalendar
            )
        )
        let quiet = QuietHours(window: window)
        #expect(quiet.isQuiet(at: Self.instant(hour: 13, minute: 0), calendar: Self.londonCalendar))
        #expect(quiet.isQuiet(at: Self.instant(hour: 13, minute: 59), calendar: Self.londonCalendar))
        // Half-open: 14:00 is over.
        #expect(!quiet.isQuiet(at: Self.instant(hour: 14, minute: 0), calendar: Self.londonCalendar))
        #expect(!quiet.isQuiet(at: Self.instant(hour: 12, minute: 59), calendar: Self.londonCalendar))
    }

    @Test("a window that wraps midnight covers both sides of it")
    func windowWrapsMidnight() throws {
        let window = try #require(
            QuietHours.window(
                fromHour: 22, minute: 0, toHour: 8, minute: 0, calendar: Self.londonCalendar
            )
        )
        let quiet = QuietHours(window: window)
        for hour in [22, 23, 0, 3, 7] {
            #expect(
                quiet.isQuiet(at: Self.instant(hour: hour, minute: 0), calendar: Self.londonCalendar),
                "\(hour):00 should be inside a 22:00–08:00 window"
            )
        }
        for hour in [8, 12, 18, 21] {
            #expect(
                !quiet.isQuiet(at: Self.instant(hour: hour, minute: 0), calendar: Self.londonCalendar),
                "\(hour):00 should be outside a 22:00–08:00 window"
            )
        }
        #expect(Self.evaluate(
            quietHours: quiet, now: Self.instant(hour: 23, minute: 0)
        ) == .suppressed(.quietHours))
    }

    /// "Quiet from 9 to 9" is a mistake somebody made. Reading it as twenty-four hours of
    /// silence would be the app choosing the most interventionist interpretation of an
    /// ambiguous setting, which is the opposite of what this type is for.
    @Test("an empty window is empty, not all day")
    func emptyWindowIsEmpty() throws {
        let window = try #require(
            QuietHours.window(
                fromHour: 9, minute: 0, toHour: 9, minute: 0, calendar: Self.londonCalendar
            )
        )
        let quiet = QuietHours(window: window)
        for hour in 0..<24 {
            #expect(!quiet.isQuiet(at: Self.instant(hour: hour, minute: 0), calendar: Self.londonCalendar))
        }
    }

    /// **Across a DST transition.** London springs forward at 01:00 UTC on 2026-03-29: the
    /// wall clock jumps 01:00 → 02:00. A window expressed in wall-clock terms must still mean
    /// what it says on that day — which is why membership is read from the `hour` and `minute`
    /// components and never from elapsed minutes since midnight.
    @Test("a window means the same thing on the day the clocks change")
    func windowSurvivesADSTTransition() throws {
        let calendar = Self.londonCalendar
        let window = try #require(
            QuietHours.window(fromHour: 22, minute: 0, toHour: 8, minute: 0, calendar: calendar)
        )
        let quiet = QuietHours(window: window)

        // 2026-03-29, the spring-forward day in Europe/London.
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 29

        func instant(hour: Int, minute: Int) throws -> Date {
            var parts = components
            parts.hour = hour
            parts.minute = minute
            return try #require(calendar.date(from: parts))
        }

        // **The discriminating reading.** On this day the wall clock jumps 01:00 → 02:00, so
        // 08:30 is only *450* minutes after local midnight. Computed as elapsed minutes the
        // window would still be open at 08:30 and the app would stay silent for an hour it was
        // never asked to; read from the wall-clock components — which is what the person set —
        // 08:30 is 510 and the window closed at 08:00.
        #expect(quiet.isQuiet(at: try instant(hour: 0, minute: 30), calendar: calendar))
        #expect(quiet.isQuiet(at: try instant(hour: 7, minute: 30), calendar: calendar))
        #expect(!quiet.isQuiet(at: try instant(hour: 8, minute: 30), calendar: calendar))
        #expect(!quiet.isQuiet(at: try instant(hour: 9, minute: 0), calendar: calendar))

        // The reading that makes the sentence above a measurement rather than a claim: on this
        // day the two definitions of "minute of the day" genuinely disagree.
        let elapsed = calendar.dateComponents(
            [.minute],
            from: calendar.startOfDay(for: try instant(hour: 8, minute: 30)),
            to: try instant(hour: 8, minute: 30)
        ).minute
        #expect(elapsed == 450)
        #expect(
            QuietHours.minuteOfDay(of: try instant(hour: 8, minute: 30), calendar: calendar) == 510
        )

        // …and on the autumn day, when 01:00–02:00 happens twice, both readings agree.
        var autumn = DateComponents()
        autumn.year = 2026
        autumn.month = 10
        autumn.day = 25
        autumn.hour = 1
        autumn.minute = 30
        let ambiguous = try #require(calendar.date(from: autumn))
        #expect(quiet.isQuiet(at: ambiguous, calendar: calendar))
    }

    /// A non-Gregorian calendar keeps the same twenty-four hours of sixty minutes, so a
    /// wall-clock window means the same thing in it — and the arithmetic is taken from the
    /// calendar rather than written down, so a calendar that disagreed would be honoured.
    @Test("a wall-clock window means the same thing in a non-Gregorian calendar")
    func nonGregorianCalendar() throws {
        for identifier in [Calendar.Identifier.hebrew, .islamicUmmAlQura, .japanese, .persian] {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = try #require(TimeZone(identifier: "Asia/Jerusalem"))
            calendar.locale = Locale(identifier: "he_IL")

            let window = try #require(
                QuietHours.window(fromHour: 22, minute: 0, toHour: 8, minute: 0, calendar: calendar)
            )
            #expect(window.startMinuteOfDay == 1320)
            #expect(window.endMinuteOfDay == 480)

            let quiet = QuietHours(window: window)
            var components = calendar.dateComponents(
                [.era, .year, .month, .day], from: Self.reference
            )
            components.hour = 23
            components.minute = 15
            let night = try #require(calendar.date(from: components))
            #expect(quiet.isQuiet(at: night, calendar: calendar))

            components.hour = 10
            let morning = try #require(calendar.date(from: components))
            #expect(!quiet.isQuiet(at: morning, calendar: calendar))
        }
    }

    @Test("a window outside the day is refused rather than wrapped")
    func windowOutsideTheDayIsRefused() {
        #expect(
            QuietHours.window(
                fromHour: 24, minute: 0, toHour: 8, minute: 0, calendar: Self.londonCalendar
            ) == nil
        )
        #expect(
            QuietHours.window(
                fromHour: 22, minute: 0, toHour: 8, minute: 60, calendar: Self.londonCalendar
            ) == nil
        )
    }

    // MARK: - The reasons are keys, not sentences (focus-pzl)

    /// **This suite used to prove the twelve dead sentences resolved**, and that was the whole of
    /// its interest in them: `copyKeys()` asserted the key was spelled `nudge.suppressed.<case>`
    /// and `copyResolves()` asserted the catalogue answered something. Both were green for a
    /// vocabulary no route could draw, which is the shape this repository keeps finding — a proof
    /// written to the known failure.
    ///
    /// What replaces them is the claim that survives the deletion: every reason is a distinct
    /// **key**, usable as a record field and a dictionary key, and nothing here is a sentence.
    @Test("every suppression reason is a distinct, stable raw value")
    func rawValuesAreDistinctAndStable() {
        var seen: Set<String> = []
        for reason in NudgeSuppressionReason.allCases {
            #expect(seen.insert(reason.rawValue).inserted, "duplicate raw value")
            #expect(!reason.rawValue.isEmpty)
            #expect(NudgeSuppressionReason(rawValue: reason.rawValue) == reason)
        }
    }

    // MARK: - Helpers

    /// An instant on 2026-01-01 in the London calendar, at a wall-clock time.
    static func instant(hour: Int, minute: Int) -> Date {
        var components = londonCalendar.dateComponents([.year, .month, .day], from: reference)
        components.hour = hour
        components.minute = minute
        return londonCalendar.date(from: components) ?? reference
    }
}
