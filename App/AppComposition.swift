import FocusClassify
import FocusCore
import FocusRules
import FocusSensing
import FocusUI
import Foundation
import SwiftData

/// The composition root.
///
/// This is the **only** file in the repository that imports more than one sibling package,
/// and that is the point: the packages know nothing about each other beyond the published
/// import matrix, and the concrete choices — which store, which observer, which classifier
/// — are made here, once, where they can be read in one screen.
///
/// `FocusUI` consumes protocol shapes and value types; it never learns which implementation
/// it was handed. That one-way rule is what keeps the privacy posture checkable at the
/// dependency-graph level instead of by reading code.
@MainActor
final class AppComposition {
    /// The application's one composition root.
    ///
    /// A single instance rather than a `@State` value, for two reasons that both matter. The
    /// quick-capture panel has to be **built at launch** — probe P-57 measured 34 ms from the
    /// hot key to a visible, focused panel, and the only way to lose that is to construct the
    /// window on demand — so the object that owns it must have a lifetime the scene graph
    /// cannot shorten. And `--focus-self-check` has to report on the *live* panel and the
    /// *live* hot-key registration rather than on a second set built for the occasion, or the
    /// report would describe something the user never gets.
    static let shared = AppComposition()

    /// Whether the local data store opened, and why not if it did not.
    ///
    /// The shell shows this rather than hiding a failure: a focus app that silently loses
    /// the user's priority is worse than one that says the store is unavailable.
    enum StoreStatus: Equatable {
        case ready
        case unavailable(String)

        var isReady: Bool { self == .ready }
    }

    let modelContainer: ModelContainer
    let storeStatus: StoreStatus

    /// Wall-clock time. Injected everywhere rather than called directly, so that every
    /// timestamp in the programme is reproducible in a test.
    let dateProvider: any DateProvider

    /// Elapsed time. Deliberately a different protocol returning a different type.
    let monotonicClock: any MonotonicClock

    /// The calendar the daily ritual is keyed through (F-19).
    ///
    /// `autoupdatingCurrent` rather than `current`: the live app must follow the user if they
    /// fly to Auckland mid-morning. It is a *parameter* everywhere downstream — probe P-69
    /// measured that "once per local day" is a function of the calendar, so every test injects
    /// a fixed one, and `check-forbidden.sh` keeps `Calendar.current` out of every file that
    /// is not this composition root's business.
    let calendar: Calendar

    /// The locale the deterministic intent validator is asked about. Outside English it
    /// returns `notAssessable` and the capture surface says **nothing** (R-20).
    let locale: Locale

    /// Seconds since this boot, from `mach_continuous_time()` scaled by the machine's own
    /// timebase. **Not** `MonotonicClock`, whose origin is taken in `init` and therefore moves
    /// on every launch: a restoration anchor has to be comparable across two processes, and
    /// measurement showed that neither `ContinuousClock.Instant` nor `MonotonicClock.elapsed`
    /// can be (probes P-105/P-106).
    let uptimeClock: any UptimeClock

    /// `"<kern.boottime.sec>.<usec>"`, read once at launch. It is what says whether a persisted
    /// uptime anchor belongs to this machine-lifetime or to one that ended in a restart.
    let bootIdentity: String

    /// The local timeline. Normalised evidence only — its `append` takes a `NormalisedDetail`,
    /// which has no `String` initialiser.
    let eventStore: ActivityEventStore

    /// Reads the state of all twelve capabilities, and **never asks for any of them**. In this
    /// epic it could not ask even by accident: every prompting API is banned from the shipping
    /// graph by lint.
    let capabilityProbe: PlatformCapabilityProbe

    /// The session runtime, and the only `SessionActing`-shaped implementation.
    let sessionHost: SessionHost

    /// The observer graph. e01 and e02 shipped `NullActivityObserver` here — an honest source
    /// for a build with no adapters, which reported itself unavailable and finished its stream
    /// immediately. e03 replaces it with the real thing, and every consumer above the seam is
    /// unchanged: they read availability and a `CockpitState`, not an implementation.
    let sensingHost: SensingHost

    /// The relevance runtime: the engine, the snapshot it judges against, and the verdict the
    /// cockpit and the Privacy pane draw.
    ///
    /// **Nothing consumes a mandate in this build.** The nudge is e05's; e04's demonstrable is
    /// the verdict stream and the restrained explanation beside it.
    let relevanceHost: RelevanceHost

    /// The relevance classifier. e01 and e02 shipped `UndecidedClassifier` here — it answers
    /// `uncertain` to everything, and `uncertain` suppresses intervention, so an app built on
    /// it is structurally incapable of nudging. e04 replaces it with the deterministic engine
    /// **before any model exists**, which is what makes the charter's *"heuristic fallback
    /// always present and independently tested"* clause temporally true rather than a promise
    /// about a later epic.
    ///
    /// It is the *same object* `relevanceHost` owns rather than a second one: the answer given
    /// across the seam and the verdict drawn in the inspector must not be two opinions.
    let classifier: any RelevanceClassifier

    /// The rule store. SwiftData-backed from e02, so a rule the user authors in the cockpit
    /// is the same row e04's engine will read.
    let ruleStore: any RuleStore

    /// The global hot-key registrar (F-06). Carbon `RegisterEventHotKey`, proven grant-free on
    /// this Mac (P-56), reached through a `FocusCore` seam so that neither `FocusUI` nor this
    /// file has to know Carbon exists.
    let hotKeyRegistrar: any HotKeyRegistering

    /// The pre-built quick-capture panel. Built here, at launch, and never rebuilt.
    ///
    /// **Not the nudge panel.** This one activates the application on purpose — a capture field
    /// nobody can type into is not capture — and `nudgePanel` must never take anything. They are
    /// two objects rather than one object with a flag, because the safe call and the unsafe call
    /// are one word apart (P-139, R-96m).
    let quickCapturePanel: QuickCapturePanelController

    /// The non-activating nudge panel (R-89), built at launch for the same reason the capture
    /// panel is: showing it is a state change on objects that already exist.
    let nudgePanel: NudgePanelController

    /// The menu-bar command centre. Installed in `start()`, because it touches `NSStatusBar`.
    let menuBar: MenuBarController

    /// The notification boundary. It reads `getNotificationSettings`, which P-134 measured never
    /// prompting, and contains no call that can raise one — the single `requestAuthorization`
    /// call site in the repository is the Intervention settings pane's button (R-96g).
    let notificationDelivery: NotificationDelivery

    /// The nudge loop. **The only thing in the app that turns a judgement into behaviour**, and
    /// it decides nothing itself: `NudgeDecider` decides, and this host presents and records.
    let nudgeHost: NudgeHost

    /// The only `PriorityActing` implementation: the SwiftData ⇄ `CockpitState` bridge.
    let priorityHost: PriorityHost

    /// What the platform said when the app offered it the stored shortcut, kept so that
    /// `--focus-self-check` can report it and the Capture settings tab can explain a refusal
    /// rather than leaving a shortcut that silently does nothing.
    private(set) var hotKeyRegistration: HotKeyRegistration?

    /// The shortcut the app actually asked for.
    private(set) var hotKeySpec: HotKeySpec = .quickCaptureDefault

    private var hasStarted = false

    /// **The menu-bar timer's shape, chosen once per session** (P-133, R-91).
    ///
    /// Held here rather than in the controller because it is a fact about the *session*, not
    /// about the item: the width tracks the digit count, so a timer that grew a field at the
    /// hour mark would move every item beside it. `MenuBarTimerFormat.advanced(elapsed:)` is
    /// monotone, so an open-ended session widens exactly once and never narrows.
    private var menuBarTimerFormat = MenuBarTimerFormat.minuteSecond
    /// The session the format was chosen for. A new session chooses again, from its own plan.
    private var menuBarTimerSessionID: UUID?

    init(
        dateProvider: any DateProvider = SystemDateProvider(),
        monotonicClock: any MonotonicClock = SystemMonotonicClock(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        uptimeClock: any UptimeClock = SystemUptimeClock(),
        hotKeyRegistrar: any HotKeyRegistering = CarbonHotKeyRegistrar(),
        ruleStoreOverride: (any RuleStore)? = nil
    ) {
        self.dateProvider = dateProvider
        self.monotonicClock = monotonicClock
        self.calendar = calendar
        self.locale = locale
        self.uptimeClock = uptimeClock
        self.hotKeyRegistrar = hotKeyRegistrar
        // Read once, at launch. It cannot change while the process lives — a machine that
        // restarts takes the process with it — so re-reading it would be re-asking a question
        // whose answer is fixed.
        self.bootIdentity = BootIdentity.current()

        // Every container in this programme is built through `FocusStore.makeContainer`,
        // which always goes through the migration plan. If the on-disk store cannot be
        // opened we fall back to an in-memory one so the shell still runs and can *report*
        // the failure — never a crash, and never a silent switch the user cannot see.
        let container: ModelContainer
        let status: StoreStatus
        do {
            container = try FocusStore.makeContainer(kind: .applicationSupport)
            status = .ready
        } catch {
            status = .unavailable(error.localizedDescription)
            do {
                container = try FocusStore.makeContainer(kind: .inMemory)
            } catch {
                // An in-memory container cannot fail for any reason the app can recover
                // from: the schema itself would have to be invalid, which is a programming
                // error, not a runtime condition.
                fatalError("the v2 schema does not load: \(error)")
            }
        }
        self.modelContainer = container
        self.storeStatus = status

        let context = container.mainContext
        self.ruleStore = ruleStoreOverride ?? SwiftDataRuleStore(context: context)

        // The seed runs before the gate is built, and it is idempotent across launches: a
        // built-in the person removed is a tombstone row, and the seed refuses to insert a
        // built-in for which any row exists. An app that put a setting back after you changed
        // it is an app that is arguing with you.
        let events = ActivityEventStore(context: context, dateProvider: dateProvider)
        let settings = FocusStore.sensingSettings(in: context)

        let (gate, exclusions) = Self.sensitivityLists(in: context, now: dateProvider.now)

        let probe = PlatformCapabilityProbe()
        let sessions = SessionHost(
            context: context,
            events: events,
            dateProvider: dateProvider,
            uptimeClock: uptimeClock,
            bootIdentity: bootIdentity
        )
        let sensing = SensingHost(
            events: events,
            // The **same** store instance the session host projects from, so a lifecycle pause
            // and the value the cockpit draws can never be two different opinions about one row.
            sessions: sessions.sessionStore,
            settings: settings,
            gate: gate,
            presentationExclusions: exclusions,
            dateProvider: dateProvider,
            monotonicClock: monotonicClock,
            capabilityProbe: probe
        )

        self.eventStore = events
        self.capabilityProbe = probe
        self.sessionHost = sessions
        self.sensingHost = sensing

        // The engine, warmed at construction. P-116 measured a 59.4 ms cold embedding load and
        // a further 57 ms for `NaturalLanguage`'s first tagger; both are paid here, off the
        // classification path, because a stutter that long inside a judgement is a defect a
        // person can feel.
        let relevance = RelevanceHost(
            context: context,
            ruleStore: self.ruleStore,
            monotonicClock: monotonicClock
        )
        self.relevanceHost = relevance
        self.classifier = relevance.engine

        self.priorityHost = PriorityHost(
            context: context,
            dateProvider: dateProvider,
            calendar: calendar,
            locale: locale,
            environment: PriorityHost.Environment(
                // Nothing has been judged yet at this point in construction, so `uncertain` is
                // the honest status: the app is observing and has concluded nothing. It is
                // `paused` when the person has the switch off. `start()` re-projects once the
                // engine has actually looked.
                status: settings.sensingPaused ? .paused : .uncertain,
                storeIsReady: status.isReady,
                isObservingActivity: !settings.sensingPaused,
                session: sessions.snapshot,
                sessionElapsedSeconds: sessions.snapshot?.elapsedWallSeconds(now: dateProvider.now),
                lastActiveBundleID: sensing.lastForeignBundleIdentifier,
                sensing: sensing.summary,
                capabilities: sensing.capabilities
            )
        )

        // The two hosts are one feature seen from two sides: the graph changes the stored
        // session, and the host is what the cockpit draws. Wiring them here is what keeps
        // either of them from having to know about the other's lifetime.
        sessions.sensing = sensing
        sensing.onSessionChanged = { [weak sessions] in sessions?.refresh() }

        // …and the cockpit value follows both of them. Assigned after `self` is fully
        // initialised, in `start()`, because the closure captures the composition root.

        // Built now, with the panel's SwiftUI content and its hosting view, so that `show()`
        // later is nothing but state changes on objects that already exist (P-57).
        self.quickCapturePanel = QuickCapturePanelController()

        // The e05 surfaces, all built before the first frame for the same reason.
        let nudgePanel = NudgePanelController()
        let menuBar = MenuBarController()
        let centre = SystemNotificationCentre()
        let notifications = NotificationDelivery(centre: centre)
        self.nudgePanel = nudgePanel
        self.menuBar = menuBar
        self.notificationDelivery = notifications

        self.nudgeHost = NudgeHost(
            context: context,
            // The **same** box the relevance host reads through, so a "Not this time" written
            // from a panel is a rule the very next classification consults (R-72.2).
            sessionRules: sessions.sessionRuleBox,
            panel: nudgePanel,
            menuBar: menuBar,
            notifications: notifications,
            workspace: SystemReturnWorkspace(),
            monotonicClock: monotonicClock,
            dateProvider: dateProvider,
            calendar: calendar
        )
        centre.onActionIdentifier = { [weak notifications] identifier in
            notifications?.handle(actionIdentifier: identifier)
        }
    }

    /// Seed the sensitive-application list and read both lists back.
    ///
    /// The compiled list is the fallback rather than a silent absence: a store that will not
    /// seed must not become a store that stops standing down for password managers. The
    /// presentation-exclusion list has no compiled fallback because it has no compiled
    /// content — it seeds empty, and seeding it with guesses would be a claim about
    /// applications this programme has not measured.
    private static func sensitivityLists(
        in context: ModelContext,
        now: Date
    ) -> (gate: SensitivityGate, presentationExclusions: Set<String>) {
        do {
            try SensitiveAppSeed.seed(in: context, now: now)
            return (
                try SensitiveAppSeed.gate(in: context),
                try SensitiveAppSeed.activeBundleIDs(.presentationExcluded, in: context)
            )
        } catch {
            return (SensitivityGate(), [])
        }
    }

    /// Register the hot key, restore the session, and start observing.
    ///
    /// Separate from `init` and idempotent, because it is the half that touches AppKit and
    /// the Carbon event target: it must run once the application object exists, and running
    /// it twice would offer the same combination to the platform twice — or, now, attach the
    /// observer graph twice and double every dwell figure.
    ///
    /// `FocusSentinelApp.init()` calls this, which is **before the first frame**: the session
    /// is reconciled and the graph is attached before any surface draws, so the cockpit's first
    /// paint already shows the corrected elapsed time rather than a restarted one.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        quickCapturePanel.onCommit = { [weak self] result in
            guard let self else { return }
            self.priorityHost.setPriority(intent: result.intent, doneWhen: result.doneWhen)
        }

        // The three hosts, joined. Assigned here rather than in `init` because each closure
        // captures the composition root, which does not exist until `init` has returned.
        //
        // The chain is one-way and terminates: the graph changes the stored session, the session
        // host re-projects it, and the projection is pushed into the value the cockpit draws —
        // which is assigned only when it actually differs, so nothing here can oscillate.
        sensingHost.onSessionChanged = { [weak self] in
            self?.sessionHost.refresh()
        }
        sensingHost.onSensingChanged = { [weak self] in
            self?.refreshCockpit()
        }
        sessionHost.onChange = { [weak self] in
            self?.refreshCockpit()
        }

        // The relevance lane, joined to the two things that already happen.
        //
        // `onSnapshotInvalidated` fires on exactly the four events R-65 names — the priority
        // changed, its revision changed, a rule was written, a context item moved — and on
        // nothing else, so the store is read when a person did something rather than every five
        // seconds. The session-rule closure is the only thing this host may ask the session
        // host for: `SessionRuleBox` is the sole owner of the session authority (R-72.2), and a
        // reference to the whole host would be a licence to reach for the rest of it.
        priorityHost.onSnapshotInvalidated = { [weak self] in
            self?.relevanceHost.invalidateSnapshot()
        }
        relevanceHost.sessionRules = { [weak sessionHost] priorityID in
            sessionHost?.sessionRules(forPriority: priorityID) ?? []
        }
        relevanceHost.invalidateSnapshot()

        startNudgeLoop()

        registerHotKey(storedHotKeySpec())

        // Restoration first, so that the graph's first activation is written against the
        // session the person was actually in. `startedAt` is not rewritten here or anywhere,
        // and no timer is started, because there is none to start.
        sessionHost.restore()
        sensingHost.start()

        // One last projection, so the cockpit's first paint already shows the reconciled
        // session, the live observer count and the capability matrix as the probe just read it —
        // rather than the placeholder values `init` could build before any of them existed.
        refreshCockpit()
    }

    /// Join the nudge loop to the three things that already happen.
    ///
    /// **The whole loop is four closures**, and that is the point: the verdict stream drives it,
    /// the sensing types supply the surroundings, one function performs whatever a click decided
    /// to write, and the menu bar is redrawn from the same projection every other surface reads.
    /// Nothing here decides anything; `NudgeDecider` does.
    private func startNudgeLoop() {
        menuBar.install()
        menuBar.onAction = { [weak self] action in self?.perform(action) }
        // Read once at launch, and again whenever the settings pane's one sanctioned request
        // returns. `getNotificationSettings` never prompts (P-134), so this costs no permission.
        notificationDelivery.refresh { [weak self] authorisation in
            self?.nudgeHost.preferences = NudgePreferences(
                voice: self?.nudgeHost.preferences.voice ?? .standard,
                reducedInterruption: self?.nudgeHost.preferences.reducedInterruption ?? false,
                authorisation: authorisation
            )
        }

        nudgeHost.surroundings = { [weak self] in
            self?.nudgeSurroundings() ?? AppComposition.emptySurroundings()
        }
        nudgeHost.currentSessionID = { [weak self] in self?.sessionHost.snapshot?.sessionID }
        nudgeHost.onCorrection = { [weak self] outcome in self?.perform(outcome) }

        relevanceHost.onJudgement = { [weak self] judgement in
            self?.nudgeHost.consider(judgement)
        }

        // Every command reaches the nudge loop as well as the cockpit, through **one** queue in
        // one order (F-145). The cockpit answers the capture and session verbs; the loop answers
        // the four nudge ones and ignores the rest.
        FocusCommandCenter.shared.observe { [weak self] command in
            self?.nudgeHost.perform(command)
        }
    }

    /// Everything the world is doing, as one value.
    ///
    /// Assembled from the types that own each fact — e03's sensing summary, e03's session phase,
    /// e02's calendar, e01's clocks — and **nothing is fetched here**: every field is a reading
    /// somebody else already took, which is what keeps the nudge module free of every sensing
    /// API (R-96k).
    private func nudgeSurroundings() -> NudgeSurroundings {
        let summary = sensingHost.summary
        return NudgeSurroundings(
            hasActivePriority: priorityHost.state.priority != nil,
            sensingPaused: !sensingHost.isRunning,
            sensitivity: sensingHost.sensitivityDecision,
            phase: sessionHost.snapshot?.phase ?? .focus,
            idle: sensingHost.idleReading,
            idleThresholdSeconds: sensingHost.settings.idleThresholdInterval,
            media: sensingHost.mediaActivity,
            mediaSuppressionEnabled: true,
            presentation: sensingHost.presentationState,
            menuBarVisible: !sensingHost.presentationState.suppressesOverlays,
            quietHours: QuietHours.off,
            now: dateProvider.now,
            calendar: calendar,
            monotonic: monotonicClock.elapsed
        )
    }

    /// The value used when the composition root is gone. It has no active priority, so gate 1
    /// suppresses everything — the safest possible reading of "this object is being torn down".
    private static func emptySurroundings() -> NudgeSurroundings {
        NudgeSurroundings(
            hasActivePriority: false,
            // Suppressed, not cleared: an object being torn down has looked at nothing, and
            // "we did not look" must never read as "we looked and it was fine".
            sensitivity: .suppressed(reason: .unbundled),
            idleThresholdSeconds: 0,
            now: Date(timeIntervalSince1970: 0),
            calendar: Calendar(identifier: .gregorian),
            monotonic: .zero
        )
    }

    /// Perform whatever one click decided to write.
    ///
    /// `CorrectionAction.outcome(scope:at:)` decided **what**; this decides **where**, and every
    /// destination is a mechanism that already existed: the rules pane's own writer (with its
    /// undo), e03's session machine, e02's confirm surface.
    private func perform(_ outcome: CorrectionOutcome) {
        switch outcome {
        case .rule(let rule), .ruleAndReceipt(let rule, _):
            guard let taskID = priorityHost.state.priority?.id else { return }
            priorityHost.addRule(
                taskID: taskID,
                scope: rule.subjectKind == .domain ? .domain : .app,
                subject: rule.subject,
                verdict: rule.verdict
            )
        case .pause:
            // e03's own machine, never a second pause concept (F-64). It travels down the same
            // one channel every menu item uses, so a pause from a nudge and a pause from ⌃⌘P are
            // literally the same command.
            FocusCommandCenter.shared.send(.pauseSession)
        case .priorityChangeRequested:
            // e02's confirm surface. **Never** a silent replacement (F-142): the command opens
            // the capture field, and the person types and confirms.
            FocusCommandCenter.shared.send(.newPriority)
        case .sessionRule, .receiptOnly, .snooze, .returnToTask, .nothing:
            break
        }
        refreshCockpit()
    }

    /// A click in the menu bar.
    private func perform(_ action: MenuBarAction) {
        switch action {
        case .openCockpit: FocusCommandCenter.shared.send(.newPriority)
        case .startSession: FocusCommandCenter.shared.send(.startSession)
        case .pauseSession: FocusCommandCenter.shared.send(.pauseSession)
        case .completeSession: FocusCommandCenter.shared.send(.completeSession)
        case .setSensingPaused(let paused): sessionHost.setSensingPaused(paused)
        case .cancelSnooze(let subject): nudgeHost.cancelSnooze(subject: subject)
        case .answerQuery(let answer): nudgeHost.answer(answer)
        }
        refreshCockpit()
    }

    /// Redraw the menu bar from the same projection every other surface reads.
    ///
    /// **This is F-84's cadence, and it is a coalescing rather than a schedule.** It is called
    /// from `refreshCockpit()`, which already runs on every accepted activation and on e03's
    /// five-second corroboration tick, and `MenuBarController.update(_:)` rewrites the item's
    /// title only when the rendered string actually differs — so at `mm:ss` granularity the
    /// title is written once a minute, and there is no timer anywhere for anybody to leak.
    private func refreshMenuBar(session: SessionSnapshot?) {
        chooseMenuBarTimerFormat(for: session)
        menuBar.update(menuBarPresentation())
    }

    /// Choose the timer's shape **once per session**, and widen it at most once thereafter.
    private func chooseMenuBarTimerFormat(for session: SessionSnapshot?) {
        guard let session else {
            menuBarTimerSessionID = nil
            menuBarTimerFormat = .minuteSecond
            return
        }
        if menuBarTimerSessionID != session.sessionID {
            menuBarTimerSessionID = session.sessionID
            menuBarTimerFormat = MenuBarTimerFormat.chosen(
                forPlanned: priorityHost.state.priority?.timeboxSeconds
                    .map { Duration.seconds($0) }
            )
        }
        let elapsed = session.elapsedWallSeconds(now: dateProvider.now)
        menuBarTimerFormat = menuBarTimerFormat.advanced(elapsed: .seconds(Int(elapsed)))
    }

    /// What the menu bar draws, as one value.
    func menuBarPresentation() -> MenuBarPresentation {
        let session = sessionHost.snapshot
        let elapsed = session?.elapsedWallSeconds(now: dateProvider.now)
        return MenuBarPresentation(
            status: currentStatus,
            priorityIntent: priorityHost.state.priority?.intent,
            elapsed: elapsed.map { Duration.seconds(Int($0)) },
            timerFormat: menuBarTimerFormat,
            snoozes: nudgeHost.activeSnoozes(),
            pendingQuery: nudgeHost.pendingPopoverQuery,
            rung: nudgeHost.currentRung,
            band: relevanceHost.verdict?.band,
            sensingPaused: !sensingHost.isRunning
        )
    }

    /// Re-read `getNotificationSettings` after the settings pane's one sanctioned request.
    ///
    /// The pane performs the request; this learns the answer. Nothing here can ask, which is
    /// what keeps the routing path provably prompt-free (R-82.1, R-96g).
    func refreshNotificationAuthorisation() {
        notificationDelivery.refresh { [weak self] authorisation in
            guard let self else { return }
            self.nudgeHost.preferences = NudgePreferences(
                voice: self.nudgeHost.preferences.voice,
                reducedInterruption: self.nudgeHost.preferences.reducedInterruption,
                authorisation: authorisation
            )
        }
    }

    /// Detach the observer graph without pausing the session.
    ///
    /// Quitting is not a pause the person took: a `sensingPaused` row at termination would be a
    /// fact about the app closing rather than about their day.
    func stop() {
        sensingHost.stop()
    }

    /// Offer a shortcut to the platform, recording what it said.
    ///
    /// The registrar consults `HotKeySpec.refusal` *before* calling the API, because the API
    /// will not refuse for us: probe P-55 measured `RegisterEventHotKey` accepting ⌘Space,
    /// returning `noErr`, and quietly taking the key away from Spotlight.
    @discardableResult
    func registerHotKey(_ spec: HotKeySpec) -> HotKeyRegistration {
        hotKeySpec = spec
        let result = hotKeyRegistrar.register(spec) { [weak self] in
            self?.quickCapturePanel.show()
        }
        hotKeyRegistration = result
        return result
    }

    /// The stored shortcut, or the default when nothing has been stored.
    ///
    /// A stored combination that this build would refuse — because it collides with a system
    /// shortcut the API would happily hand over — falls back to the default rather than being
    /// registered: an app must not be able to steal ⌘Space because an old row said so.
    func storedHotKeySpec() -> HotKeySpec {
        guard let row = FocusStore.settingsRow(in: modelContainer.mainContext) else {
            return .quickCaptureDefault
        }
        let stored = HotKeySpec(
            keyCode: row.hotKeyKeyCode,
            modifierFlags: row.hotKeyModifierFlags
        )
        return stored.isRegistrable ? stored : .quickCaptureDefault
    }

    /// The status the cockpit displays.
    ///
    /// `paused` is the truthful answer while nothing is being observed: the app has observed
    /// nothing and therefore judged nothing. Otherwise it is the engine's own answer — and
    /// `uncertain` until there has been one, because an app that drew `relevant` before it had
    /// looked at anything would be inventing a verdict.
    var currentStatus: FocusStatus {
        guard sensingHost.isRunning else { return .paused }
        return relevanceHost.verdict?.status ?? .uncertain
    }

    /// Whether the platform can supply activation events at all.
    ///
    /// Read off the capability matrix the probe produced, so this is the same answer the
    /// Privacy surface shows rather than a second opinion computed here. It is deliberately
    /// **not** the global pause switch: "the person turned observation off" and "this Mac
    /// cannot observe" are different facts and the app must be able to say which one it means.
    /// The switch is `sensingHost.isRunning`, which is what `currentStatus` reads.
    var observationAvailability: ObservationAvailability {
        switch sensingHost.capabilities.state(of: .frontmostApplication) {
        case .available: .available
        case .denied, .restricted: .unavailable(reason: .permissionNotGranted)
        case .unavailable: .unavailable(reason: .unsupportedOnThisMac)
        // Before the first probe. In this epic it never survives launch, because `start()`
        // probes before any surface draws.
        case .notRequested: .unavailable(reason: .notImplemented)
        }
    }

    /// Everything the cockpit draws, as one value.
    ///
    /// The composition root translates the concrete implementations it chose into the plain
    /// value `FocusUI` consumes. That translation happening *here* is what lets `FocusUI`
    /// stay free of any dependency on `FocusSensing` — the UI never learns which observer it
    /// was handed, only what that observer currently reports.
    var cockpitState: CockpitState {
        priorityHost.state
    }

    /// Re-read everything the store knows nothing about and push it into the cockpit value.
    ///
    /// Called whenever the session or the graph changes — a lifecycle pause, a stand-down for a
    /// sensitive application, the global switch, the corroboration tick. **This is the only
    /// place the elapsed figure is read**, from the injected wall clock, at the moment somebody
    /// asked: there is no timer anywhere in this programme, so the number on the screen is the
    /// number as of the last real change rather than a subscription that has to be cancelled.
    ///
    /// Without this the app would have a visible defect rather than a stale one: locking the
    /// screen pauses the session in the store, and the window would keep saying *Focus* until
    /// the person happened to press something.
    func refreshCockpit() {
        let snapshot = sessionHost.snapshot
        judge(in: snapshot)
        refreshMenuBar(session: snapshot)
        priorityHost.update(
            environment: PriorityHost.Environment(
                status: currentStatus,
                storeIsReady: storeStatus.isReady,
                isObservingActivity: sensingHost.isRunning,
                session: snapshot,
                sessionElapsedSeconds: snapshot?.elapsedWallSeconds(now: dateProvider.now),
                lastActiveBundleID: sensingHost.lastForeignBundleIdentifier,
                sensing: sensingHost.summary,
                capabilities: sensingHost.capabilities,
                verdict: relevanceHost.verdict
            )
        )
    }

    /// Hand the engine one observation, if there is anything to observe.
    ///
    /// Called from `refreshCockpit`, which already runs on every accepted activation **and** on
    /// e03's five-second corroboration tick — so the drift clock advances between activations
    /// without this programme acquiring a second timer. An observation at a monotonic reading
    /// the machine has already seen moves nothing: the drift reducer guards on a positive
    /// interval.
    ///
    /// Nothing is judged while sensing is detached. The person turned observation off, and
    /// judging what was frontmost when they did would be reporting on a screen nobody is
    /// watching.
    private func judge(in session: SessionSnapshot?) {
        guard sensingHost.isRunning else { return }
        relevanceHost.observe(
            sensingHost.judgeableSubject,
            // No open session is not a break: the person can be working with no session
            // started, and `.focus` is the phase that says "nothing forbids a judgement here".
            // What forbids an *intervention* is a separate question, answered by
            // `InterventionEligibility.decide` on facts this call also supplies.
            phase: session?.phase ?? .focus,
            isUserIdle: sensingHost.summary.isUserIdle
        )
    }
}
