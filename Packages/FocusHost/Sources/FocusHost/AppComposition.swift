import FocusClassify
import FocusCore
import FocusRules
import FocusSensing
import FocusUI
import Foundation
import SwiftData
import os

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
public final class AppComposition {
    /// The application's one composition root.
    ///
    /// A single instance rather than a `@State` value, for two reasons that both matter. The
    /// quick-capture panel has to be **built at launch** — probe P-57 measured 34 ms from the
    /// hot key to a visible, focused panel, and the only way to lose that is to construct the
    /// window on demand — so the object that owns it must have a lifetime the scene graph
    /// cannot shorten. And `--focus-self-check` has to report on the *live* panel and the
    /// *live* hot-key registration rather than on a second set built for the occasion, or the
    /// report would describe something the user never gets.
    ///
    /// `storeKind` is `.applicationSupport` in every ordinary launch — `--focus-store` is the
    /// only thing that changes it, and nothing but the self-check lane passes it. It exists
    /// because one boundary value, the session's elapsed figure, cannot be observed in a launch
    /// with no session: the mutation that guts it writes `nil`, a Mac with no session hands the
    /// window `nil` too, and the two programs are then identical. Running the check against a
    /// store somebody seeded is the only way to make that value exist without writing a session
    /// into the person's own store — a fact about their day that never happened (focus-h7h).
    public static let shared = AppComposition(storeKind: SelfCheck.requestedStoreKind)

    private let logger = Logger(
        subsystem: FocusStore.bundleIdentifier,
        category: "AppComposition"
    )

    /// Whether the local data store opened, and why not if it did not.
    ///
    /// The shell shows this rather than hiding a failure: a focus app that silently loses
    /// the user's priority is worse than one that says the store is unavailable.
    enum StoreStatus: Equatable {
        case ready
        case unavailable(String)

        var isReady: Bool { self == .ready }
    }

    public let modelContainer: ModelContainer
    let storeStatus: StoreStatus

    /// Wall-clock time. Injected everywhere rather than called directly, so that every
    /// timestamp in the programme is reproducible in a test.
    public let dateProvider: any DateProvider

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

    /// **The Mac's live appearance and accessibility settings, as a value** (focus-2er).
    ///
    /// Owned here rather than by the `App` struct. It used to be a `@State` value in `App/`,
    /// which is not a package — so the object that decides whether the whole shell honours dark
    /// mode, Increase Contrast, Reduce Transparency, Reduce Motion and Differentiate Without
    /// Colour had no test anywhere in the programme. It is still held in `@State` by the scene,
    /// because SwiftUI's observation is what redraws the windows when it republishes; the
    /// *instance* is this one.
    public let appearance = AppearanceObserver()

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

    /// **The three transitions that end an open nudge** (focus-d0a).
    ///
    /// `NudgeHost.sessionEnded()`, `phaseLeftFocus()` and `priorityChanged()` had no caller
    /// anywhere in the shipping graph, so the loop was never told any of them and an open
    /// question stayed live and answerable long after the situation it was about had gone. The
    /// facts arrive here as a level and the loop needs an edge; the watch is what turns one into
    /// the other, and it is a value so that a test can drive it.
    private var lifecycle = NudgeLifecycleWatch()

    /// - Parameter storeKind: where the data lives. `applicationSupport` is the application's
    ///   own store and is the default; the unit lane passes `inMemory`, because a test that
    ///   opened the real store would be a test that could change what the person sees. It is a
    ///   parameter rather than a branch on a build flag so that the composition the tests build
    ///   is the composition that ships, with one value different.
    init(
        dateProvider: any DateProvider = SystemDateProvider(),
        monotonicClock: any MonotonicClock = SystemMonotonicClock(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        uptimeClock: any UptimeClock = SystemUptimeClock(),
        hotKeyRegistrar: any HotKeyRegistering = CarbonHotKeyRegistrar(),
        storeKind: FocusStore.Kind = .applicationSupport,
        notificationCentre: (any NotificationCentring)? = nil,
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
            container = try FocusStore.makeContainer(kind: storeKind)
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
        // **The system centre is constructed only when nobody supplied one.**
        // `UNUserNotificationCenter.current()` traps in a process with no bundle proxy, which is
        // every unit-test process, so the seam is a parameter rather than a branch on a build
        // flag: the composition the tests build is the composition that ships, with one value
        // different.
        // Qualified: `FocusSensing` declares a `SystemNotificationCentre` of its own, for
        // `NSWorkspace` notifications, and the two names would otherwise be ambiguous here.
        let centre = notificationCentre ?? FocusUI.SystemNotificationCentre()
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
        // One click on a notification's own button. Only the system centre has one; a supplied
        // centre delivers its actions however it likes and this wire has nothing to say about it.
        (centre as? FocusUI.SystemNotificationCentre)?.onActionIdentifier = { [weak notifications] identifier in
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
    public func start() {
        guard !hasStarted else { return }
        hasStarted = true

        quickCapturePanel.onCommit = { [weak self] result in
            guard let self else { return }
            self.priorityHost.setPriority(intent: result.intent, doneWhen: result.doneWhen)
        }

        joinHosts()
        relevanceHost.invalidateSnapshot()

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

    /// **Every host joined to every other, and nothing started.**
    ///
    /// Assigned here rather than in `init` because each closure captures the composition root,
    /// which does not exist until `init` has returned — and separate from the rest of `start()`
    /// because the rest of `start()` registers a global hot key and attaches the observer graph,
    /// which a test process has no business doing. `CompositionRootTests` calls this, so the
    /// wires it drives are the shipping wires rather than closures a test installed.
    ///
    /// The chain is one-way and terminates: the graph changes the stored session, the session
    /// host re-projects it, and the projection is pushed into the value the cockpit draws —
    /// which is assigned only when it actually differs, so nothing here can oscillate.
    func joinHosts() {
        sensingHost.onSessionChanged = { [weak self] in
            self?.sessionHost.refresh()
        }
        sensingHost.onSensingChanged = { [weak self] in
            self?.refreshCockpit()
        }
        // Every session verb funnels through `SessionHost.refresh()`, so this is the one wire
        // that carries a session ending and a phase leaving focus into the nudge loop
        // (focus-d0a).
        sessionHost.onChange = { [weak self] in
            self?.refreshCockpit()
        }

        // The nudge lane, joined before the relevance lane: it owns
        // `priorityHost.onSnapshotInvalidated`, which the relevance lane rides on, and a second
        // assignment would silently replace it.
        startNudgeLoop()

        // The session-rule closure is the only thing the relevance host may ask the session host
        // for: `SessionRuleBox` is the sole owner of the session authority (R-72.2), and a
        // reference to the whole host would be a licence to reach for the rest of it.
        relevanceHost.sessionRules = { [weak sessionHost] priorityID in
            sessionHost?.sessionRules(forPriority: priorityID) ?? []
        }
    }

    /// Join the nudge loop to the three things that already happen.
    ///
    /// **The whole loop is four closures**, and that is the point: the verdict stream drives it,
    /// the sensing types supply the surroundings, one function performs whatever a click decided
    /// to write, and the menu bar is redrawn from the same projection every other surface reads.
    /// Nothing here decides anything; `NudgeDecider` does.
    /// Internal rather than private so the unit lane can join the loop without also
    /// registering a global hot key and attaching the observer graph, which `start()` does and
    /// which a test process has no business doing.
    func startNudgeLoop() {
        menuBar.install()
        menuBar.onAction = { [weak self] action in self?.perform(action) }
        // **A badge question is asked at the moment the popover opens, not before** (focus-kby).
        //
        // The popover opens only on a human click, and the menu bar is the only object that
        // knows the click happened. This is the one wire that lets the nudge loop tell the
        // difference between a question somebody read and a question sitting behind a click.
        menuBar.onPopoverDidShow = { [weak self] in self?.nudgeHost.popoverPresentedTheQuestion() }
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
        nudgeHost.onCorrection = { [weak self] outcome, priorityID in
            self?.perform(outcome, priorityID: priorityID)
        }

        relevanceHost.onJudgement = { [weak self] judgement in
            self?.nudgeHost.consider(judgement)
        }

        // **The loop is told when the world it was speaking about ends** (focus-d0a).
        //
        // `onSnapshotInvalidated` fires on exactly the four events R-65 names — the priority
        // changed, its revision changed, a rule was written, a context item moved — and on
        // nothing else, so the store is read when a person did something rather than every five
        // seconds. It is the nudge lane's route to a priority change as well as the relevance
        // lane's route to a stale snapshot, and it fires *before* `CockpitState` is reassigned,
        // which is why the reading below is taken from `snapshotKey` rather than from `state`.
        priorityHost.onSnapshotInvalidated = { [weak self] in
            guard let self else { return }
            self.relevanceHost.invalidateSnapshot()
            self.noticeLifecycleTransitions()
        }

        // Every command reaches the nudge loop as well as the cockpit, through **one** queue in
        // one order (F-145). The cockpit answers the capture and session verbs; the loop answers
        // the four nudge ones and ignores the rest.
        FocusCommandCenter.shared.observe { [weak self] command in
            self?.nudgeHost.perform(command)
        }
    }

    /// **Tell the loop about anything that ended what it was speaking about** (focus-d0a).
    ///
    /// Called from `refreshCockpit()` — which already runs on every accepted activation, e03's
    /// five-second corroboration tick and every session verb — and from
    /// `priorityHost.onSnapshotInvalidated`, which is the only moment a priority change is
    /// observable before the next tick. Under U-1 that difference is the whole point: the panel
    /// is sticky, so between the commitment and the tick a person can answer a question about a
    /// priority they have already left.
    ///
    /// Internal rather than private so `CompositionRootTests` can drive the real closure's far
    /// end without also starting the observer graph.
    func noticeLifecycleTransitions() {
        let snapshot = sessionHost.snapshot
        let transitions = lifecycle.observe(
            sessionID: snapshot?.sessionID,
            phase: snapshot?.phase,
            // Read from the snapshot key rather than from `CockpitState`: `PriorityHost` fires
            // `onSnapshotInvalidated` after moving the key and *before* assigning the state, so
            // the state still describes the commitment that has just been replaced.
            priorityID: priorityHost.snapshotKey.priorityID
        )
        for transition in transitions {
            switch transition {
            case .sessionEnded: nudgeHost.sessionEnded()
            case .phaseLeftFocus: nudgeHost.phaseLeftFocus()
            case .priorityChanged: nudgeHost.priorityChanged()
            }
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
    /// Internal rather than private for the reason `startNudgeLoop()` is: this is the function
    /// the duplicate-learned-rule regression lived in, and the only honest test of it is one
    /// that calls it with a real `CorrectionOutcome` and counts the rows afterwards.
    ///
    /// - Parameter priorityID: **the commitment the nudge was raised under**, captured by
    ///   `NudgeHost` when the panel went up and carried here (focus-lmo, U-1). It used to be
    ///   read *here*, live, from `priorityHost.state.priority?.id` — and the panel is
    ///   deliberately sticky (`hidesOnDeactivate` is `false`, R-89), so a person can commit to
    ///   something new and then press "this is relevant" on an accusation about the commitment
    ///   they have left. The row that wrote was a `RuleAuthority.task` rule under the *new*
    ///   task: the app learned a fact about work it was never told, and learned nothing about
    ///   the work it was actually shown. That is the rule half of the same ruling whose receipt
    ///   half `openQuestionPriorityID` fixed, and it is the half that survived.
    func perform(_ outcome: CorrectionOutcome, priorityID: UUID?) {
        switch outcome {
        case .rule, .ruleAndReceipt:
            // **Who writes the row is decided by the outcome, not by this switch** (R-78).
            //
            // An accusation-panel correction (`.rule`) has been written by nobody, so this is the
            // write, and going through the rules store is also what gives it its undo (F-93).
            //
            // A query answer (`.ruleAndReceipt`) has **already** been written: the ledger
            // committed the rule and its immutable receipt as one transaction, under `rule.id`.
            // Inserting it again here would write a *second* learned rule under a different
            // identifier — two chips in the context row, two rows in the Rules pane, and an undo
            // that removed only one of them. `ruleAwaitingPersistence` is `nil` for exactly that
            // case, so the only thing still owed is the undo the ledger's transaction had no
            // journal to register with.
            if let pending = outcome.ruleAwaitingPersistence {
                // The nudge's own key. A correction with no commitment to scope to is not a
                // narrower rule, it is a global one, and it is refused rather than widened.
                guard let taskID = priorityID else { return }
                priorityHost.addRule(
                    taskID: taskID,
                    scope: pending.subjectKind == .domain ? .domain : .app,
                    subject: pending.subject,
                    verdict: pending.verdict
                )
            } else if let committed = outcome.persistedRule {
                priorityHost.registerLearnedRuleUndo(id: committed.id)
            }
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
    public func refreshNotificationAuthorisation() {
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
    public func stop() {
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
    public var cockpitState: CockpitState {
        priorityHost.state
    }

    // MARK: - The surface the app target reaches this package through
    //
    // **Deliberately narrow, and narrower than it was.** When these objects lived in the
    // application target the scenes reached straight into `composition.priorityHost.state`,
    // `composition.sensingHost.summary` and `composition.nudgeHost.preferences` — three hosts'
    // internals read and, in the nudge's case, written from inside a `View`. The hosts are
    // `internal` to this package now, so a scene can only ask the composition root, which is
    // the one object whose job is to know them all.
    //
    // Every member below is a projection or a verb that already existed; none of them decides
    // anything, and there is still exactly one place a click becomes a write.

    /// The cockpit's mutation host. `PriorityHost` is the app's only `PriorityActing`.
    public var cockpitActions: any PriorityActing { priorityHost }

    /// The session controls' host. `SessionHost` is the app's only `SessionActing`, and it is
    /// what the four session menu commands and the cockpit's buttons both call.
    public var sessionActions: any SessionActing { sessionHost }

    /// How long the open session has been running, read from the injected wall clock at the
    /// moment somebody asked. `nil` when there is no session.
    public var sessionElapsedSeconds: Double? {
        sessionHost.snapshot.map { $0.elapsedWallSeconds(now: dateProvider.now) }
    }

    /// The last application the observer graph saw that was not this one.
    public var lastActiveBundleID: String? { sensingHost.lastForeignBundleIdentifier }

    /// What is being watched, for the Privacy pane and the cockpit's status line — one answer
    /// rather than two opinions.
    public var sensingSummary: SensingSummary { sensingHost.summary }

    /// What this Mac lets the app do, as the probe read it.
    public var capabilities: CapabilityMatrix { sensingHost.capabilities }

    /// What the engine actually concluded, for the verdict inspector (R-71).
    public var verdict: VerdictSnapshot? { relevanceHost.verdict }

    // MARK: - The three wires that live in `App/` (focus-cp2)
    //
    // `App/` is not a package, so nothing in the unit lane can reach a closure in the scene
    // graph — and four no-op mutations to those closures survived the whole nineteen-stage gate.
    // The self-check is the only lane that runs the shipping scene graph in the shipping
    // process, so each wire is given a name it says when it fires, and the report carries both
    // the names heard and the effects they were supposed to have.
    //
    // The scene calls exactly one of these per wire. That is deliberate: a scene that called
    // `adoptUndoManager` and `updateCapturePanelTraits` directly, from an `.onAppear` and again
    // from an `.onChange`, was four statements with two effects — and no report could tell them
    // apart, which is how the wires became invisible in the first place.

    /// Which of the shell's wires have fired in this process, ever.
    ///
    /// Read by `--focus-self-check`. Not cleared: a wire that fires once has been proved to
    /// exist, and there is no question this answers that a *current* reading would answer better.
    public private(set) var shellWires: Set<ShellWire> = []

    // MARK: - What each window drew, beside what it was handed (focus-h7h)
    //
    // The receipts above say **which** wire fired. They were measured to say nothing about what
    // travelled down it: an eight-part mutation that kept every receipt firing and replaced every
    // value with a constant passed the whole nineteen-stage gate, 262 ok-assertions against 262,
    // with an empty diff between the clean run's list and the mutant's. The cockpit showed a
    // frozen placeholder, the session timer read nothing, the Privacy pane always said nothing
    // was watched, three windows ignored dark mode and every accessibility setting, and the
    // Keyboard Shortcuts window was empty.
    //
    // So each window reports the values it put on the screen, through the preference channel
    // `ShellRenderedValuesKey` — `DecisionSurfaceReachability`'s mechanism, pointed at the
    // windows — and this is where they arrive. Beside them is what **this object put into the
    // connection**, recorded at the moment it built it.
    //
    // The expectation is recorded here rather than re-derived at the reading, and that is not an
    // optimisation. A comparison against a fresh read would be two reads taken a second apart,
    // and the session's elapsed figure moves between them: it would fail on the passage of time
    // rather than on a defect. What is asserted is exactly *what I handed you* against *what you
    // drew*, and `generation` is what keeps the two the same issue.

    /// What each window says it drew, latest report per surface.
    public private(set) var shellRenderings: [ShellThemedSurface: ShellRenderedValues] = [:]

    /// What this object handed that window, recorded when it handed it over.
    private var shellExpectations: [ShellThemedSurface: [ShellRenderedField: String]] = [:]

    /// How many connections this object has issued for each window. Stamped into the connection,
    /// carried back in every reported value, and compared: a report from an older issue is a
    /// window drawing from something this object has already replaced.
    private var shellGenerations: [ShellThemedSurface: Int] = [:]

    /// The issue number a window's report must carry to be current.
    public func shellGeneration(of surface: ShellThemedSurface) -> Int {
        shellGenerations[surface] ?? 0
    }

    /// **The reading for one window**: what it drew, held up beside what it was handed.
    ///
    /// The whole of focus-h7h's acceptance in one value. `drewWhatTheAppKnows` is false for a
    /// window that reported nothing, for one drawing from a replaced connection, and for one that
    /// drew a constant where a live value was handed to it — three different defects, named
    /// separately, because a caller that could not tell them apart would report "wrong" for all
    /// of them.
    public func shellRenderReading(of surface: ShellThemedSurface) -> ShellRenderReading {
        ShellRenderFidelity.evaluate(
            surface: surface.rawValue,
            rendered: shellRenderings[surface] ?? .nothing,
            expected: shellExpectations[surface] ?? [:],
            expectedGeneration: shellGeneration(of: surface)
        )
    }

    /// One window's report, as it arrived from the preference channel.
    ///
    /// Late reports are kept rather than dropped: the reading compares the generation itself, so
    /// a stale one has to survive to be reported as stale. Dropping it here would turn "drawing
    /// from a replaced connection" back into "reported nothing", which is a different defect.
    private func record(_ values: ShellRenderedValues, for surface: ShellThemedSurface) {
        shellRenderings[surface] = values
    }

    /// Take the next issue number for a window.
    ///
    /// It deliberately does **not** clear that window's expectations. The traits injection and
    /// the connection are two separate wires evaluated at two separate moments of one pass —
    /// `.appearanceTraits(composition.appearanceTraits(for: .cockpit))` is an argument to a scene
    /// modifier and runs first, `CockpitHost.body` calls `cockpitConnection()` and runs second —
    /// so clearing here would throw away the traits this object had just recorded handing over.
    /// Every field is overwritten by the pass that hands it over again, which is what keeps the
    /// dictionary current without a reset that races the scene.
    private func nextGeneration(for surface: ShellThemedSurface) -> Int {
        let next = shellGeneration(of: surface) + 1
        shellGenerations[surface] = next
        return next
    }

    /// Record one value this object is handing to a window.
    ///
    /// Additive, because the traits injection and the connection are two separate wires evaluated
    /// at two separate moments in one pass of the scene's body: the traits arrive first, the
    /// connection second, and a recording that replaced the dictionary would drop whichever came
    /// before it.
    private func expect(_ field: ShellRenderedField, _ value: String, for surface: ShellThemedSurface) {
        shellExpectations[surface, default: [:]][field] = value
    }

    /// **Everything the cockpit window draws, as one value the scene cannot fabricate**
    /// (focus-2er).
    ///
    /// The scene used to read five properties off this object and pass them as five arguments,
    /// each of which was a compiling one-line no-op away from a frozen placeholder in a file no
    /// test bundle can import. Now it asks once. The five reads are here, where
    /// `AppCompositionConnectionTests` asserts every one of them against the live host, and the
    /// call itself is recorded — so a scene that stops asking fails the gate by name.
    public func cockpitConnection() -> CockpitConnection {
        shellWires.insert(.cockpitConnected)

        // Read once, into local values, and hand the **same** values to the window and to the
        // expectation (focus-h7h). Reading them twice — once for the connection and once for the
        // record — would make the comparison a race: `sessionElapsedSeconds` is taken from the
        // wall clock at the moment somebody asks, so two reads a few microseconds apart can
        // differ by a whole second at a boundary, and the gate would fail on the passage of time.
        let state = cockpitState
        let elapsed = sessionElapsedSeconds
        let actions = cockpitActions
        // The session host is the app's only `SessionActing`, and it is what the cockpit's
        // session controls and the four e03 menu commands both call — one code path for a click
        // and for a key equivalent.
        let sessions = sessionActions
        let generation = nextGeneration(for: .cockpit)

        expect(.priorityIntent, state.priority?.intent ?? "", for: .cockpit)
        expect(.status, state.status.rawValue, for: .cockpit)
        expect(.recentCount, String(state.recent.count), for: .cockpit)
        expect(.handoffTask, state.pendingHandoff?.task ?? "", for: .cockpit)
        expect(.sessionPhase, state.session?.phase.rawValue ?? "none", for: .cockpit)
        expect(
            .sessionElapsedSeconds,
            elapsed.map { String(Int($0)) } ?? "none",
            for: .cockpit
        )
        expect(.capabilityStates, state.capabilities.renderedDescription, for: .cockpit)
        expect(
            .sensingSummary,
            SensingStatusView.renderedDescription(
                summary: state.sensing,
                capabilities: state.capabilities,
                showsReducedCapabilities: true
            ),
            for: .cockpit
        )
        // Both hosts are handed over, always. A cockpit given neither draws every control
        // disabled and no capture field at all — a window that looks finished and does nothing.
        expect(.mutationHostsAttached, "priority/session", for: .cockpit)

        return CockpitConnection(
            state: state,
            actions: actions,
            sessionActions: sessions,
            sessionElapsedSeconds: elapsed,
            lastActiveBundleID: lastActiveBundleID,
            generation: generation,
            didRender: { [weak self] in self?.shellWires.insert(.cockpitRendered) },
            didDraw: { [weak self] values in self?.record(values, for: .cockpit) }
        )
    }

    /// **Everything the Settings window draws and every verb it can perform**, in the same shape
    /// and for the same reason (focus-2er).
    ///
    /// Two of the epic's four acceptance mutations lived in the arguments this replaces:
    /// `onInterventionAction` gutted to `{ _ in }`, which under U-1 is what decides whether the
    /// app may speak, and the appearance store write deleted from a `Binding`'s setter written
    /// by hand in a scene body. Both are verbs on this object now.
    public func settingsConnection() -> ShellSettingsConnection {
        shellWires.insert(.settingsConnected)

        // The same values into the window and into the record, for the reason
        // `cockpitConnection()` reads its own once (focus-h7h).
        let preference = appearance.preference
        // What is being watched, and what this Mac lets the app do — read from the graph rather
        // than probed again for the occasion, so the Privacy pane and the cockpit's status line
        // are one answer rather than two opinions.
        let summary = sensingSummary
        let matrix = capabilities
        let currentVerdict = verdict
        let intervention = interventionSettings
        let generation = nextGeneration(for: .settings)

        expect(.appearancePreference, preference.rawValue, for: .settings)
        expect(.privacyCapabilities, matrix.renderedDescription, for: .settings)
        expect(.verdictBand, currentVerdict?.band?.rawValue ?? "none", for: .settings)
        expect(.interventionVoice, intervention.voice.rawValue, for: .settings)
        expect(
            .reducedInterruption,
            intervention.reducedInterruption ? "on" : "off",
            for: .settings
        )
        // The Privacy pane draws the working as well as the sentence, which is what
        // `showsDetail` turns on — and it is what tells this field apart from the cockpit's.
        expect(
            .privacySummary,
            SensingStatusView.renderedDescription(
                summary: summary,
                capabilities: matrix,
                showsReducedCapabilities: false
            ),
            for: .settings
        )

        return ShellSettingsConnection(
            preference: preference,
            setPreference: { [weak self] preference in
                self?.applyAppearancePreference(preference)
            },
            storeURL: FocusStore.applicationSupportURL,
            summary: summary,
            capabilities: matrix,
            verdict: currentVerdict,
            intervention: intervention,
            onInterventionAction: { [weak self] action in self?.perform(action) },
            generation: generation,
            didRender: { [weak self] in self?.shellWires.insert(.settingsRendered) },
            didDraw: { [weak self] rendering in
                guard let self else { return }
                self.record(rendering.values, for: .settings)
                // **The two sinks the pane is actually holding**, kept so the self-check can
                // drive them and watch this object's own graph move. They cannot be pressed:
                // no lane in this programme holds the Accessibility grant it would take to
                // click a picker, which is exactly why `{ _ in }` in their place survived two
                // rounds of gates.
                self.settingsSinks = rendering
            }
        )
    }

    /// **What the Settings window's controls will actually reach**, as the window handed it back
    /// (focus-h7h).
    ///
    /// `nil` until the window has drawn once. Read by `--focus-self-check`, which drives both
    /// sinks with a probe value and puts the world back, because the alternative — asserting that
    /// the closure *is* the right one — is not something anything can check about a closure.
    public private(set) var settingsSinks: ShellSettingsRendering?

    /// **The Keyboard Shortcuts window drew its reference.**
    ///
    /// The window has no connection to carry a receipt, because it reads nothing from the graph
    /// — it renders `CommandRegistry.shell`, a committed value. So the receipt is a verb the
    /// view calls from its body, which is the one thing that distinguishes the shipping window
    /// from a correctly titled empty one.
    public func helpWindowRendered(_ values: ShellRenderedValues) {
        shellWires.insert(.helpRendered)
        record(values, for: .help)
        // **The one issue.** The reference reads nothing from the graph, so there is no
        // connection for it to draw from and nothing for it to become stale against: it draws
        // `CommandRegistry.shell`, which cannot change while the process lives. The expectation
        // is therefore the committed table's own row count, counted through the same function the
        // window draws from — one derivation, two consumers, rather than a number written twice.
        shellGenerations[.help] = ShellRenderedValues.singleIssue
        expect(
            .shortcutRowCount,
            String(
                ShortcutsHelpView.groups(for: .shell).reduce(0) { $0 + $1.rows.count }
            ),
            for: .help
        )
    }

    /// **The live traits, for one named window's environment** (focus-2er).
    ///
    /// Three scenes inject `AppearanceTraits`, and each injection is its own wire: a shell that
    /// stopped theming its Settings window while still theming its cockpit is a real, shippable
    /// defect, and one shared receipt would hide it. The surface says which window is asking.
    public func appearanceTraits(for surface: ShellThemedSurface) -> AppearanceTraits {
        shellWires.insert(surface.wire)
        let traits = appearance.traits
        // **What is handed over is recorded, and the window reports what it resolved**
        // (focus-h7h). The receipt says the injection ran; this says which traits arrived. A
        // scene that asked for the live traits and then injected `AppearanceTraits.systemDefault`
        // fires the receipt and leaves the window ignoring dark mode and every accessibility
        // setting — which is precisely one of the eight mutations that survived the last gate.
        expect(.appearanceTraits, traits.renderedDescription, for: surface)
        return traits
    }

    /// **The Settings window appeared.**
    ///
    /// It may be opened long after launch, so the stored preference is re-read rather than
    /// assumed to still match what the observer was built with. The read *and* the assignment
    /// are here: the scene's `.task` used to perform the assignment itself, which is a statement
    /// in `App/` that nothing could observe.
    public func settingsWindowAppeared() {
        shellWires.insert(.settingsAppeared)
        appearance.preference = storedAppearancePreference()
    }

    /// **The person chose an appearance.** Update the observer, then persist it.
    ///
    /// The observer first, so the shell re-renders immediately even if the write fails: a store
    /// that cannot be written is a reason to tell the user, never a reason to ignore what they
    /// just chose. Both halves are here rather than in a `Binding` setter in `App/`, which is
    /// where the write was when deleting it left the whole gate green (focus-cp2 M4).
    public func applyAppearancePreference(_ preference: AppearancePreference) {
        appearance.preference = preference
        setAppearancePreference(preference)
    }

    /// **The window's undo manager arrived, or changed.**
    ///
    /// `@Environment(\.undoManager)` is `nil` until there is a window, so the scene watches it
    /// with `initial: true` and this is called both at the first draw and whenever it moves.
    public func undoManagerChanged(_ manager: UndoManager?) {
        shellWires.insert(.undoManagerChanged)
        adoptUndoManager(manager)
    }

    /// **The Mac's appearance changed**, or the person chose a different one in Settings.
    public func appearanceChanged(_ traits: AppearanceTraits) {
        shellWires.insert(.appearanceChanged)
        updateCapturePanelTraits(traits)
    }

    /// The window's own `UndoManager`, handed to both journals.
    ///
    /// One call rather than two, because the two journals drive one Edit menu and a scene that
    /// could adopt into one of them and forget the other is a scene with a half-working ⌘Z.
    public func adoptUndoManager(_ manager: UndoManager?) {
        priorityHost.adoptUndoManager(manager)
        // Only the operations a *person* performed reach it: an auto-pause for a screen lock
        // is not something they meant to do, and offering to undo it would be offering to undo
        // the world.
        sessionHost.adoptUndoManager(manager)
    }

    /// An incoming `focus://` handoff. It parses and **shows**; there is no route from here to
    /// a store mutation that does not pass through a person pressing Replace (F-142).
    ///
    /// Reached from two places on purpose. `FocusAppDelegate.application(_:open:)` is the AppKit
    /// route and lives in this package, where `FocusHostTests` drives it; the cockpit scene's
    /// `.onOpenURL` is the SwiftUI route and is kept because which of the two AppKit dispatches
    /// to is Apple's decision rather than this programme's, and a handoff that depended on
    /// guessing right would be a handoff that silently stopped working. Arriving twice costs
    /// nothing: the parse is pure and the result is the same value assigned to the same field.
    public func receive(_ url: URL) {
        shellWires.insert(.handoffReceived)
        priorityHost.receive(url)
    }

    // MARK: - The Settings scene's two stored facts (focus-cp2)
    //
    // Both of these used to be written out inside the Settings scene's own view body, in `App/`,
    // where no test bundle can reach them and where the self-check cannot drive them either —
    // the pane's controls need a click, and this programme's gate holds no Accessibility grant.
    // What can be fixed is that there is no longer any *logic* there to rot: the scene reads one
    // value and calls one verb, and both verbs are here, under `AppCompositionSettingsTests`.

    /// The appearance the person last chose, read from the store.
    ///
    /// The Settings window may be opened long after launch, so the stored value is read when the
    /// pane appears rather than assumed to still match what the observer was built with.
    public func storedAppearancePreference() -> AppearancePreference {
        FocusStore.appearancePreference(in: modelContainer.mainContext)
    }

    /// Persist the appearance the person just chose.
    ///
    /// The observer is updated by the caller *first*, so the shell re-renders immediately even if
    /// this write fails: a store that cannot be written is a reason to tell the user, never a
    /// reason to ignore what they just chose.
    public func setAppearancePreference(_ preference: AppearancePreference) {
        do {
            try FocusStore.setAppearancePreference(
                preference,
                in: modelContainer.mainContext,
                now: dateProvider.now
            )
        } catch {
            logger.error(
                "the store refused an appearance preference: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Re-theme the pre-built quick-capture panel when the appearance preference changes.
    public func updateCapturePanelTraits(_ traits: AppearanceTraits) {
        quickCapturePanel.update(traits: traits)
    }

    /// What the Intervention pane draws, read from the live loop rather than assembled for the
    /// occasion.
    public var interventionSettings: InterventionSettings {
        InterventionSettings(
            voice: nudgeHost.preferences.voice,
            reducedInterruption: nudgeHost.preferences.reducedInterruption,
            quietHours: InterventionPolicy.quietHoursDefault,
            authorisation: nudgeHost.notificationAuthorisation,
            usage: nudgeHost.todaysUsage(),
            presentationExclusions: sensingHost.presentationExclusions.sorted()
        )
    }

    /// What the Intervention pane asked for.
    ///
    /// The one thing it is **not** allowed to do is ask for a permission: that call lives in
    /// the pane's own file and nowhere else (R-96g), and this handler only learns that the
    /// answer changed and re-reads it from `getNotificationSettings`, which never prompts.
    public func perform(_ action: InterventionSettingsAction) {
        switch action {
        case .setVoice(let voice):
            nudgeHost.preferences = NudgePreferences(
                voice: voice,
                reducedInterruption: nudgeHost.preferences.reducedInterruption,
                authorisation: nudgeHost.preferences.authorisation
            )
        case .setReducedInterruption(let reduced):
            nudgeHost.preferences = NudgePreferences(
                voice: nudgeHost.preferences.voice,
                reducedInterruption: reduced,
                authorisation: nudgeHost.preferences.authorisation
            )
        case .setQuietHours, .removePresentationExclusion:
            // Both are stored settings e05 does not yet persist a row for; the pane reports the
            // request and the store lands in a later task rather than being faked here.
            break
        case .notificationAuthorisationChanged:
            refreshNotificationAuthorisation()
        }
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
    public func refreshCockpit() {
        let snapshot = sessionHost.snapshot
        // Before the judgement, so a question that belongs to a session which has just ended is
        // written down and taken off screen rather than left standing for the next one to
        // inherit (focus-d0a).
        noticeLifecycleTransitions()
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
