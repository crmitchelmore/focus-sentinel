import FocusClassify
import FocusCore
import FocusModel
import FocusRules
import FocusSensing
import FocusUI
import Foundation
import SwiftData
import os

/// The composition root.
///
/// `FocusHost` is the **only** module permitted to import more than one sibling package —
/// `check-boundaries.sh`'s matrix says so, and it is the row with every sibling in it — and this
/// is the file the concrete choices are made in: which store, which observer, which classifier,
/// once, where they can be read in one screen. The packages know nothing about each other beyond
/// the published import matrix.
///
/// The claim used to be about this **file** rather than about the module, and it had not been
/// true for some time: `SelfCheck.swift` reads three siblings to report on them, and the two
/// files this object's own code was split into read two apiece (focus-tzj.6). What the boundary
/// check enforces is the module, and that is what this now says.
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

    /// **Whether `start()` has run**, readable without forcing `shared` into existence
    /// (focus-gmr). See the note at the assignment in `start()`.
    public private(set) static var isRunning = false

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
    /// Where `modelContainer` lives, kept so delete-everything can name every file it owns.
    let storeKind: FocusStore.Kind
    let storeStatus: StoreStatus

    /// **The one thing that ever shortens this app's memory** (F-115, focus-tzj.3).
    ///
    /// Held here rather than on a host because it is about the store rather than about any one
    /// surface, and because the two moments it runs at — the launch, and the first tick of a new
    /// local day — are both this object's.
    private let retentionSweep: RetentionSweep

    /// What the last sweep did, or `nil` before one has run. Read by the self-check, so "old
    /// rows are removed" is a number rather than a promise.
    private(set) var lastRetentionSweep: RetentionSweep.Result?
    /// **What the last export or import did** (F-110, F-134, focus-ix9). Held so the gate can
    /// read what the shipping verbs actually produced, and so a refusal is a value rather than a
    /// line in a log nobody opens.
    public internal(set) var lastPortabilityOutcome: DataPortabilityOutcome = .none

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
    /// **The mandate this host issues is what the ladder climbs.** The same eligibility reaches
    /// the Privacy pane's inspector and `NudgeHost`, so the verdict a person reads is the one
    /// the app acted on (focus-lmy).
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
    ///
    /// **Declared without an initialiser, and that is the repair** (focus-8ry). It was
    /// `= AppearanceObserver()`, a stored-property initialiser, which can name no argument
    /// because `self` does not exist yet — so it took the type's `.matchSystem` default and the
    /// person's stored choice was read by nothing at launch. A stored-property initialiser is
    /// the *shape* of the defect, not an instance of it: it is the one form of construction that
    /// structurally cannot consult the store. `init` assigns it beside every other read-back, so
    /// there is no longer a place where a launch-time setting could be given a default without
    /// somebody writing that default down.
    public let appearance: AppearanceObserver

    /// The menu-bar command centre. Installed in `start()`, because it touches `NSStatusBar`.
    let menuBar: MenuBarController

    /// **Every renderer of the ambient rung, named** (e08a).
    ///
    /// Two, and the list is the claim rather than the count: the status item, whose write is the
    /// receipt every ambient charge rests on, and the notch companion, which draws a strip under
    /// the housing of a built-in notched display and nothing else. A third name here without a
    /// third `PerceptionChannel` beside it would be a surface pretending to be a renderer, which
    /// is the thing this whole epic is arranged not to be — so the self-check publishes the list
    /// and the gate pins it, exactly as it pins `surfacesARungCanReach`.
    static let ambientRungRenderers = ["menuBarItem", "notchCompanion"]

    /// **The second renderer of the ambient rung** (e08a). It draws a hairline under the housing
    /// of a built-in notched display and nothing else, from the same presentation the item above
    /// is handed — which is what makes it a renderer rather than a surface. On this Mac it never
    /// draws at all, and `SelfCheck.notchReport()` publishes both the counter and the named reason.
    let notchCompanion: NotchCompanionController

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

    /// **This app's login-item registration, as something that can be doubled** (D-12,
    /// focus-odz.4). The shipping value is `SMAppServiceLoginItem`; no test and no gate stage
    /// ever holds the real one, because registering writes into the person's Login Items.
    let loginItem: any LoginItemControlling

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
        ruleStoreOverride: (any RuleStore)? = nil,
        loginItem: (any LoginItemControlling)? = nil
    ) {
        // **Injectable, and every lane in this programme injects** (D-12, focus-odz.4).
        //
        // `SMAppService.register()` writes into the person's Login Items, so a test suite or a
        // gate stage that called it would be changing the machine it is measuring. The shipping
        // adapter is the default; a double is what every test uses, which is the whole reason
        // `LoginItemControlling` is a protocol.
        self.loginItem = loginItem ?? SMAppServiceLoginItem()
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
        self.storeKind = storeKind

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

        // **The appearance the person last chose, read here — beside the sensing settings, and
        // for the same reason** (focus-8ry).
        //
        // Measured before this line existed: a store whose `ZAPPEARANCEPREFERENCERAW` was
        // `light` produced `storedAppearancePreference = light` and
        // `appearancePreference = matchSystem` on the same launch, and the whole shell — cockpit,
        // menu-bar glyph, nudge panel, quick-capture panel — drew in the system scheme until the
        // person happened to press Cmd-comma, at which point it flipped underneath them. The
        // only two writes to `appearance.preference` were a click on the picker and the Settings
        // window appearing, and a person who never opens Settings never gets their own setting.
        //
        // `ZSENSINGPAUSED` came back correctly on that same launch, because the line above reads
        // it. Two stored settings, one read, one not — so the repair is to read this one where
        // that one is read rather than at some later moment that would have to be remembered.
        self.appearance = AppearanceObserver(
            preference: FocusStore.appearancePreference(in: context)
        )

        let (gate, exclusions) = Self.sensitivityLists(in: context, now: dateProvider.now)

        // **One rung, read once, handed to two readers** (e06). The capability matrix and the
        // relevance engine must never take their own answer about the model tier: two readings
        // could disagree, and the Privacy pane would then be describing a build that is not
        // running. The same argument the scorer already makes one paragraph down.
        let modelRung = FocusModelRung()
        let probe = PlatformCapabilityProbe(
            onDeviceModel: modelRung.availability.capabilityState
        )
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
            monotonicClock: monotonicClock,
            modelRung: modelRung
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
                storeOpened: status.isReady,
                isObservingActivity: !settings.sensingPaused,
                session: sessions.snapshot,
                sensing: sensing.summary,
                capabilities: sensing.capabilities
            )
        )

        // The two hosts are one feature seen from two sides: the graph changes the stored
        // session, and the host is what the cockpit draws. Wiring them here is what keeps
        // either of them from having to know about the other's lifetime.
        sessions.sensing = sensing

        // **`sensing.onSessionChanged` is NOT assigned here** (focus-w3f), and the omission is
        // the point rather than an oversight. It was, on this line — and `sensing` is
        // `sensingHost` and `sessions` is `sessionHost`, both assigned twenty lines above, so
        // `joinHosts()` reassigned the very same property on the very same object ninety lines
        // later and this one never survived to fire. Two spellings of one wire, the second
        // silently replacing the first, which is exactly the hazard `startNudgeLoop()`'s own
        // comment warns about for `onSnapshotInvalidated`.
        //
        // It was found by replacing it with a no-op and watching all 176 tests pass — which they
        // did because there was nothing there to break. A dead assignment that reads as a live
        // wire is worse than a missing one: it answers the question "is this joined up?" with a
        // yes that is not true.

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
        self.notchCompanion = NotchCompanionController()
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
        // **Retention, built here and run from `start()`** (focus-tzj.3). Its four stores are
        // fresh handles over the same context, exactly as every host's are: a store object is a
        // facade over the one `ModelContext`, and sharing an instance would be sharing a cache
        // rather than sharing rows.
        self.retentionSweep = RetentionSweep(
            context: context,
            events: events,
            log: InterventionLog(
                context: context,
                dateProvider: dateProvider,
                calendar: calendar
            ),
            ledger: QueryLedger(context: context, dateProvider: dateProvider),
            priorities: PriorityStore(context: context, dateProvider: dateProvider),
            calendar: calendar,
            dateProvider: dateProvider
        )

        // One click on a notification's own button. Only the system centre has one; a supplied
        // centre delivers its actions however it likes and this wire has nothing to say about it.
        (centre as? FocusUI.SystemNotificationCentre)?.onAction = {
            [weak notifications] identifier, request in
            // Both halves cross the boundary: which button, and which banner (focus-zrs). The
            // second is what lets the loop refuse a press on a rung that is over.
            notifications?.handle(actionIdentifier: identifier, requestIdentifier: request)
        }

        // **The switches, read before anything can be drawn** (focus-exdi.4). Here rather than in
        // `startNudgeLoop()`, because the capability table is read by the settings window and the
        // popover, which a person can open before a loop is running — and a table that said
        // "not asked for" about a grant they gave would be the app forgetting an answer.
        applyStoredGrantOptIns()
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
        // **Readable without creating one** (focus-gmr). `FocusAppDelegate` asks this before it
        // touches `shared` at quit: `shared` is a `static let`, so reading it in
        // `applicationWillTerminate` would *build* a whole composition root — a store, a graph,
        // an observer set — in the reduced self-check modes that never started one, at the exact
        // moment the process is trying to leave. A separate flag costs nothing and is the only
        // reading that can be taken safely there.
        Self.isRunning = true

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

        // **Once at launch, after the store has opened** (focus-tzj.3). Here rather than in
        // `init` for `start()`'s own reason: `init` builds the graph and a test process builds
        // one on every suite, and a sweep is a write. It is deliberately before the first
        // projection below, so the cockpit's first paint already draws the history the app is
        // keeping rather than one that is about to be shortened.
        sweepRetentionIfDue()

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
        // **The offer's first reading, at launch** (D-12, focus-odz.4). One of the three moments
        // it can move; the other two are a session's state changing and the offer being answered.
        refreshLaunchAtLoginOffer()
        // **And whether this launch owes the first-run explanation** (focus-odz.7). Once, here,
        // for the same reason: the answer changes once in the life of a store and the projection
        // that would otherwise ask it runs every five seconds.
        decideFirstRunScreen()
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
            // **One of the three moments the launch-at-login offer can move** (focus-odz.4). A
            // session finishing is the signal D-12 says the offer waits for, and this is where the
            // root learns a session's state changed. Recomputed here rather than in
            // `cockpitState`, which is projected on every five-second tick.
            self?.refreshLaunchAtLoginOffer()
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
        // **The engine builds its snapshot for the commitment the app is acting under**
        // (focus-zrs), rather than opening `PriorityStore` and deciding for itself which task is
        // active — which was a fourth independent read of the fact gate 1 is decided by.
        relevanceHost.activeCommitment = { [weak priorityHost] in priorityHost?.activeCommitment }

        // **One projection at the end**, so the two facts read at the top of this function reach
        // the value the cockpit draws (focus-odz.4, focus-odz.7). They travel through
        // `PriorityHost.Environment` rather than being patched on to the projection afterwards —
        // see that type for the measurement — which means the projection has to be rebuilt once
        // after they are read. Last, so every wire above is in place before anything is pushed
        // through them.
        refreshCockpit()
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
        // **A badge nudge is delivered at the moment the popover opens, not before** (focus-kby,
        // focus-xix).
        //
        // The popover opens only on a human click, and the menu bar is the only object that
        // knows the click happened. This is the one wire that lets the nudge loop tell the
        // difference between a nudge somebody read and a nudge sitting behind a click — and it is
        // **one** wire for both kinds: it was `popoverPresentedTheQuestion()`, so the accusation
        // half of the badge had no moment at which it could learn it had been looked at.
        menuBar.onPopoverDidShow = { [weak self] in self?.nudgeHost.popoverPresented() }
        // **The charge is a consequence of the write** (focus-1b5, focus-nrl).
        //
        // The third wire, and the one whose absence is the shape three rounds of this defect
        // kept: the loop asked for a redraw and then charged on the assumption that one happened.
        // Measured on the shipping loop, the assumption is false twice over — the request is
        // coalesced away when two consecutive rungs compose the same picture, and the picture is
        // the badge's rather than the rung's whenever a badge nudge is pending. Only the object
        // that makes the assignment knows the difference, so it is the object that says so.
        menuBar.onGlyphWritten = { [weak self] in self?.nudgeHost.menuBarItemRedrawn() }
        // Read once at launch, and again whenever the settings pane's one sanctioned request
        // returns. `getNotificationSettings` never prompts (P-134), so this costs no permission.
        //
        // **Nothing is copied out of it** (focus-zrs). This used to write the answer into
        // `nudgeHost.preferences`, which meant the router read a copy that no delivery failure
        // could update; the loop reads the boundary's own value now.
        notificationDelivery.refresh()

        nudgeHost.surroundings = { [weak self] in
            self?.nudgeSurroundings() ?? AppComposition.emptySurroundings()
        }
        // The appearance the nudge surfaces are drawn in, read at the moment one is raised
        // rather than captured once (focus-pq8). A person can switch to dark mode between two
        // nudges, and the panel is sticky enough to still be up when they do.
        nudgeHost.appearanceTraits = { [weak self] in
            self?.appearance.traits ?? .systemDefault
        }
        // **Reduce Motion, read at launch** (focus-w7v). The scene's
        // `.onChange(of:initial:)` keeps it current from the first frame onward, and this is
        // what the loop reads before there is a frame: a nudge raised between `start()` and the
        // cockpit's first paint would otherwise be decided against a stale `false`, for the one
        // person the setting exists for.
        nudgeHost.observe(reduceMotion: appearance.traits.reduceMotion)
        // **And what the person set, read at launch too** (focus-z7g). Same moment, same reason.
        applyStoredInterventionPreferences()
        applyStoredPolicyTunings()
        nudgeHost.currentSessionID = { [weak self] in self?.sessionHost.snapshot?.sessionID }
        nudgeHost.onCorrection = { [weak self] outcome, priorityID in
            self?.perform(outcome, priorityID: priorityID)
        }

        // **A question that has left the loop leaves the menu bar with it** (focus-v0u).
        //
        // The popover on screen is an `NSHostingController` built from the presentation the menu
        // bar was last handed, and it does not rebuild itself: without this, a badge question the
        // loop had ended went on offering three answers that `answer(_:)` would drop in a
        // `guard`. This object is the only one that knows the menu bar and the nudge loop both
        // exist, which is why the redraw is wired from here rather than reached for from there.
        nudgeHost.onQuestionSurfacesChanged = { [weak self] in
            guard let self else { return }
            self.refreshMenuBar(session: self.sessionHost.snapshot)
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

        // **The three File-menu portability items reach the same sink the Privacy pane's buttons
        // do** (F-110, F-134, focus-ix9). One vocabulary, two routes, one implementation: a menu
        // item that carried its own copy of the export would be a second exporter to keep honest.
        FocusCommandCenter.shared.registerPrivacyPerformer { [weak self] action in
            self?.perform(action)
        }

        // **And the menu bar asks whether a command would do anything before offering it**
        // (focus-6uf).
        //
        // All thirteen of the app's own items were permanently enabled, and six of them were
        // guarded no-ops in the state a person is in the first time they open the menu — measured
        // in the running binary, in the same report where AppKit's Edit menu correctly reported
        // Undo, Cut and Paste disabled.
        //
        // This is the only object that holds all three facts at once, which is why the world is
        // assembled here and nowhere else: the commitment is the priority host's, the phase is
        // the session host's, and whether a nudge is on screen is the loop's. The **closure** is
        // what makes it live: `ShellActionButton` calls it inside its own body, so SwiftUI's
        // observation follows the reads into these three `@Observable` hosts and the menu is
        // rebuilt whenever any of them moves. Nothing has to remember to push anything.
        FocusCommandCenter.shared.provideWorld { [weak self] in
            guard let self else { return .nothingIsCommitted }
            return ShellCommandWorld(
                hasPriority: priorityHost.state.priority != nil,
                sessionPhase: sessionHost.snapshot?.phase,
                hasOpenNudge: nudgeHost.hasOpenNudge,
                // The question's own fact, beside the accusation's (e07a). The loop keeps the
                // two nudges apart, and so does the menu.
                hasOpenQuestion: nudgeHost.hasOpenQuestion
            )
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
            // **The same value gate 1 is decided by** (focus-zrs). This used to read
            // `snapshotKey.priorityID` — deliberately, because `PriorityHost` fired
            // `onSnapshotInvalidated` between moving the key and assigning the state, so the two
            // disagreed for the length of the callback and this was a rule for choosing between
            // them. `PriorityHost` now assigns everything before it announces anything, and states
            // the commitment once; both readers take it from there.
            priorityID: priorityHost.activeCommitment?.id
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
    /// Internal rather than private, for the reason `startNudgeLoop()` is: the self-check reads
    /// **the value the gates are actually handed**, so a setting that reaches the loop's own
    /// field but never reaches the suppression stack is visible as a failing reading rather than
    /// as a green one (focus-z7g).
    /// **The router's own menu-bar reading, in one place** (focus-zeq, P-131, e08a).
    ///
    /// Extracted rather than duplicated when the notch companion became a second reader of it: the
    /// companion must be absent in exactly the states the ambient rung defers in, and two
    /// expressions of "is the menu bar there" would be two things to keep in step — which is the
    /// shape of the defect the whole visibility conjunct exists to prevent. It is deliberately not
    /// a store read, so the tick path's fetch budget is untouched by having a second caller.
    func menuBarIsVisible() -> Bool {
        menuBar.isInstalled && !sensingHost.presentationState.suppressesOverlays
    }

    func nudgeSurroundings() -> NudgeSurroundings {
        NudgeSurroundings(
            // **Gate 1 and the key are the same value** (focus-zrs). This was
            // `hasActivePriority: priorityHost.state.priority != nil` — a `Bool`, while the loop
            // opened `PriorityStore` itself to decide what the interruption it admitted was
            // *about*. The commitment travels whole, from the object that owns the projection, so
            // the app can no longer speak about one thing and write about another.
            commitment: priorityHost.activeCommitment,
            sensingPaused: !sensingHost.isRunning,
            sensitivity: sensingHost.sensitivityDecision,
            phase: sessionHost.snapshot?.phase ?? .focus,
            idle: sensingHost.idleReading,
            idleThresholdSeconds: sensingHost.settings.idleThresholdInterval,
            media: sensingHost.mediaActivity,
            mediaSuppressionEnabled: sensingHost.settings.mediaSuppressionEnabled,
            presentation: sensingHost.presentationState,
            // **Two facts, and the second one had no reading at all** (focus-zeq, P-131).
            //
            // This was `!presentationState.suppressesOverlays` alone: the full-screen space that
            // collapses the menu-bar layer's owners from eleven to one while our own item stays
            // *listed*. An item the app never installed — or one `MenuBarController.remove()`
            // took out — is the same fact from the other direction, and the router could not see
            // it: the rung landed on `.menuBar`, the ladder advanced, `redraw(force:)` correctly
            // refused to write to an item nobody can see (F-163), the seam could prove nothing,
            // and the loop said **nothing at all** about why. `DeferralReason.menuBarHidden` is
            // the honest vocabulary for it and was already there.
            //
            // `isInstalled` and deliberately not `isItemVisible`: that property's own doc is that
            // a status-item window stays listed when nobody can see it, so it is the wrong
            // reading in the direction that matters — over-permissive — and the reading that
            // catches the case it is right about is `suppressesOverlays` beside it.
            menuBarVisible: menuBarIsVisible(),
            // **The person's own window, not the constant** (focus-z7g). This was
            // `QuietHours.off` unconditionally, which made gate 8 of the twelve-gate suppression
            // stack dead code in the shipping app: `evaluation.json` reported
            // `bySuppressionReason.quietHours == 0` in every run because no run could ever
            // produce one. The gate was implemented, tested and unreachable.
            quietHours: nudgeHost.quietHours,
            now: dateProvider.now,
            calendar: calendar,
            monotonic: monotonicClock.elapsed
        )
    }

    /// The value used when the composition root is gone. It has no active priority, so gate 1
    /// suppresses everything — the safest possible reading of "this object is being torn down".
    private static func emptySurroundings() -> NudgeSurroundings {
        NudgeSurroundings(
            commitment: nil,
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
        // **R-105's third invalidation, at the one place a rule is written about a subject.**
        //
        // The rule outranks rank 6 anyway — rungs 0–2 answer long before the heuristic is
        // reached — so nothing the engine decides changes here. What changes is the verdict
        // inspector: without this it could show a stale model rationale beside a rule that
        // already settled the question, which is the app disagreeing with itself in public.
        if let subject = outcome.correctedSubject {
            relevanceHost.engine.forgetModelAnswers(about: subject)
        }

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
            // **e03's own machine, reached directly** (F-64, focus-mwm).
            //
            // This was `FocusCommandCenter.shared.send(.pauseSession)`, on the argument that a
            // pause from a nudge and a pause from ⌃⌘P should be *the same command*. What they
            // have to be the same is the same **destination**, and the channel was the wrong
            // thing to share: the cockpit's registered handler is the only thing that answers a
            // command, the handler is registered by `CockpitView.onAppear` and unregistered by
            // its `onDisappear`, and a nudge panel appears by construction while the person is
            // working in another application — so the cockpit being closed is the common case
            // here, not the corner. Measured: with the window shut, Pause wrote a completed
            // correction, spent fatigue, de-escalated the ladder, took the panel down, and the
            // session kept running.
            //
            // `SessionHost` is the app's only `SessionActing` and it is what the cockpit's own
            // handler calls, so this is the same code path with one fewer window in it. No guard,
            // because the machine is the authority: a pause of an already-paused session is
            // rejected `alreadyInPhase` and recorded, which is a truthful outcome rather than a
            // silent one.
            sessionHost.pauseSession()
        case .priorityChangeRequested:
            // **e02's confirm surface — the one this action's own documentation names**
            // (F-142, focus-mwm).
            //
            // `CorrectionAction.changePriority` is documented as *"Opens e02's quick-capture
            // confirm surface"*, and it did not: it sent `.newPriority` to the cockpit, which
            // with the window closed opened nothing at all. The quick-capture panel is the
            // surface that works from anywhere — it is built at launch, it activates because the
            // person asked for a field to type in, and it is the same panel the global hot key
            // raises. **Never** a silent replacement: it opens the capture field, and the person
            // types and confirms.
            quickCapturePanel.show()
        case .sessionRule, .receiptOnly, .snooze, .returnToTask, .nothing:
            break
        }
        refreshCockpit()
    }

    /// A click in the menu bar.
    ///
    /// Internal rather than private, for the reason `perform(_ outcome:priorityID:)` is
    /// (focus-mwm). It had **zero** references anywhere in `Packages/FocusHost/Tests` and no
    /// self-check probe drove one either, so the four buttons that reached nothing when the
    /// cockpit was closed were covered only by `MenuBarTests.popoverReportsActions` — a test
    /// titled *"every popover control reports its own typed request"* whose body calls the
    /// closure the test itself injected. It observes no effect, and there was none to observe.
    func perform(_ action: MenuBarAction) {
        switch action {
        // **Four buttons that did nothing whenever the cockpit was closed** (focus-mwm).
        //
        // All four were `FocusCommandCenter.shared.send(…)`, and the centre delivers to the
        // cockpit's registered handler or to nothing. A menu-bar app whose command centre stops
        // working when its main window is shut has it exactly backwards: the popover is the
        // surface that exists *for* that state.
        //
        // `setSensingPaused` below was already right, and it is the pattern the other four now
        // follow — the host, directly, with no window in the path. The one that genuinely needs
        // a window asks for one by name.
        case .openCockpit:
            // The button's string is `shell.menuBar.openCockpit` — "Open Focus Sentinel",
            // comment *"Popover action: bring the main window forward"*. It sent `.newPriority`,
            // which with the cockpit closed opened nothing and with the cockpit open behind
            // another application set `isCapturing` on a window the person could not see.
            FocusCommandCenter.shared.requestCockpit()
        case .startSession:
            // No guard: `SessionStore.start` throws `sessionAlreadyOpen`, which is recorded.
            sessionHost.startSession(kind: .openEnded, plannedSeconds: nil, deadlineAt: nil)
        case .pauseSession: sessionHost.pauseSession()
        case .completeSession: sessionHost.completeSession()
        case .setSensingPaused(let paused): sessionHost.setSensingPaused(paused)
        case .cancelSnooze(let subject): nudgeHost.cancelSnooze(subject: subject.identifier)
        case .answerQuery(let answer): nudgeHost.answer(answer)
        // **The same entry point the panel's buttons use** (focus-uru). The popover performs
        // nothing and decides nothing: a correction pressed on the badge is the identical call
        // `AccusationPanelView` makes on the panel, so one click has one meaning and
        // `CorrectionAction.outcome(scope:at:)` stays the single place a click becomes a write.
        case .correct(let action, let span):
            nudgeHost.resolve(action, snoozeDuration: span)
        // **The two the status item's secondary menu adds** (focus-odz.2). Both are app-level
        // verbs rather than host ones, so both are recorded as well as performed: a menu item
        // that reached nothing is the defect this whole channel was rebuilt to make visible.
        case .openSettings:
            settingsOpenRequests += 1
            settingsMenuItemFound = ShellSettingsMenu.open()
        case .quit:
            quitRequests += 1
            terminate()
        }
        refreshCockpit()
    }

    /// **How many times something asked for the Settings window**, and whether the last ask found
    /// an item to perform (focus-odz.2).
    ///
    /// Two facts because they are two: a request is observable in any process, and whether the
    /// app menu was holding a ⌘, item is a fact only a launch with a scene graph has. The
    /// self-check reads the second; the unit lane drives the first.
    public private(set) var settingsOpenRequests = 0
    public private(set) var settingsMenuItemFound = false

    /// How many times the app has been asked to leave.
    public private(set) var quitRequests = 0

    /// **What leaving actually does.**
    ///
    /// A property rather than a call to `NSApp.terminate(nil)` inline, and the reason is that the
    /// totality suite drives *every* `MenuBarAction` through the wire the status item calls — so
    /// an inline terminate would take the test runner down with it, and the alternative (leaving
    /// Quit out of the fold) is exactly the hole `MenuBarActionTotalityTests` exists to close. The
    /// shipping value is the real one; a test replaces it and asserts `quitRequests` instead.
    ///
    /// `applicationWillTerminate` still runs, which is where the nudge loop writes the outcome of
    /// anything that was on screen (focus-gmr): quitting from this menu is the same exit as
    /// quitting from anywhere else.
    var terminate: @MainActor () -> Void = ShellApplicationExit.terminate

    /// Redraw the menu bar from the same projection every other surface reads.
    ///
    /// **This is F-84's cadence, and it is a coalescing rather than a schedule.** It is called
    /// from `refreshCockpit()`, which already runs on every accepted activation and on e03's
    /// five-second corroboration tick, and `MenuBarController.update(_:)` rewrites the item's
    /// title only when the rendered string actually differs — so at `mm:ss` granularity the
    /// title is written once a minute, and there is no timer anywhere for anybody to leak.
    private func refreshMenuBar(session: SessionSnapshot?) {
        chooseMenuBarTimerFormat(for: session)
        let presentation = menuBarPresentation()
        menuBar.update(presentation, traits: appearance.traits)
        // **The same presentation, in the same breath** (e08a). A second call that built its own
        // value would be a second state; this is one state drawn twice, which is the whole of what
        // "second renderer" means. The two visibility readings are deliberately different
        // questions: `nudgeSurroundings().menuBarVisible` is the router's own — the item installed
        // and no presentation claiming the screen — and `isItemVisible` is the overflow case the
        // review's §3 is about, which nothing else in the app had ever read for this purpose.
        notchCompanion.update(
            presentation: presentation,
            menuBarVisible: menuBarIsVisible(),
            itemVisible: menuBar.isItemVisible
        )
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
            // The commitment's own sentence, from the one place that states it (focus-zrs). It
            // was `state.priority?.intent` — a second reading of the same fact, drawn beside a
            // nudge whose receipt is keyed to the first.
            priorityIntent: priorityHost.activeCommitment?.intent,
            elapsed: elapsed.map { Duration.seconds(Int($0)) },
            timerFormat: menuBarTimerFormat,
            snoozes: nudgeHost.activeSnoozes(),
            pendingQuery: nudgeHost.pendingPopoverQuery,
            // **The rung's answers, not just its name** (focus-uru). `rung` below is a label in
            // the belief row; this is the decision surface, and without it a top rung routed to
            // the badge under Reduce Motion was a sentence with nothing to press.
            pendingAccusation: nudgeHost.pendingPopoverAccusation,
            rung: nudgeHost.currentRung,
            // **Where that rung actually is** (focus-mkk). Without it the item was a function of
            // the status and the timer alone, so the ambient rung — which *is* the item — changed
            // nothing at all while being charged as a delivery: measured at six accusation rows
            // and one write to the menu bar, made before the first rung existed.
            rungSurface: nudgeHost.landedRungSurface,
            band: relevanceHost.verdict?.band,
            sensingPaused: !sensingHost.isRunning,
            // **F-67's cue** (focus-2w1). Assembled here because this is the only object that
            // holds all three facts: the phase is the session host's, the moment the break ended
            // is the session host's memory of an accepted transition, and whether the person is
            // back on the thing they committed to is the relevance host's verdict.
            //
            // `.relevant` and nothing else counts as back. Under U-1 an `uncertain` verdict is
            // the app not knowing, and treating not-knowing as *"they are back"* would silence
            // the cue exactly where it is most likely to be right.
            restartCue: RestartCue.state(
                phase: sessionHost.snapshot?.phase,
                sinceBreakEnded: sessionHost.breakEndedAt.map {
                    .seconds(Int(dateProvider.now.timeIntervalSince($0)))
                },
                isBackOnTask: relevanceHost.verdict?.status == .relevant
            ),
            // **F-146's channel, actually connected** (focus-pq8). This argument was never passed,
            // so it took its default of `false` and the status item never drew the short label
            // beside the glyph — for a person who has turned Differentiate Without Colour on, the
            // menu bar was telling them the app's state in hue alone, which is the one thing that
            // setting exists to stop.
            differentiateWithoutColor: appearance.traits.differentiateWithoutColor
        )
    }

    /// Read `getNotificationSettings`, once, at launch.
    ///
    /// It never prompts (P-134), and since focus-wy0 nothing in this app decides on the answer:
    /// no rung routes to a notification and no pane offers to change it. What the reading is for
    /// is the `notification-denied` gate stage, which prints the grant state this Mac was
    /// actually in while every rung still landed on an in-app surface.
    public func refreshNotificationAuthorisation() {
        notificationDelivery.refresh()
    }

    /// Detach the observer graph without pausing the session.
    ///
    /// Quitting is not a pause the person took: a `sensingPaused` row at termination would be a
    /// fact about the app closing rather than about their day.
    public func stop() {
        sensingHost.stop()
        // The strip goes with the graph that fed it. A borderless window left on screen after the
        // app stopped watching is the picture of a claim the app is no longer making.
        notchCompanion.remove()
    }

    // MARK: - The first-run explanation (focus-odz.7)

    /// **Whether this launch owes the person the one screen that says what the app looks at.**
    ///
    /// Decided **once, at launch**, and held — not asked on every projection of the cockpit state,
    /// which runs on every corroboration tick and would put a store read in the tick path for a
    /// fact that changes once in the life of a store (focus-tzj.2, `TickFetchBudgetTests`).
    ///
    /// The showing is recorded at the moment the app decides to show it rather than when the sheet
    /// is dismissed, and that is a decision: the alternative shows it again to somebody who quit
    /// with it on screen, and this app's rule is that it explains itself once and then gets out of
    /// the way. Dismissal takes it off *this* launch's screen and writes nothing further.
    private(set) var showsFirstRunExplanation = false

    /// Read the store once and, if the explanation is owed, mark it shown and put it on screen.
    ///
    /// Idempotent: a second call in the same launch finds the store already stamped and answers
    /// `false`, so a delegate notification arriving twice cannot raise a second sheet.
    func decideFirstRunScreen() {
        let state = FocusStore.shellState(in: modelContainer.mainContext)
        guard state.owesFirstRunExplanation else {
            showsFirstRunExplanation = false
            return
        }
        showsFirstRunExplanation = true
        try? FocusStore.recordFirstRunExplanationShown(
            in: modelContainer.mainContext,
            now: dateProvider.now
        )
    }

    /// The sheet's one button — and every other route out of it, which the window's binding sends
    /// here too.
    public func dismissFirstRunScreen() {
        showsFirstRunExplanation = false
        // The projection has to be rebuilt for the window to stop drawing the sheet: the flag
        // travels through `PriorityHost.Environment`, and this is what pushes it.
        refreshCockpit()
    }

    // MARK: - Opening at login (D-12, focus-odz.4)

    /// **What the launch-at-login controls perform.**
    ///
    /// Two verbs, and the important half is what is *not* here: nothing reads back a stored flag.
    /// The switch's position comes from `loginItem.status` every time a connection is built, so a
    /// person who removed the app from Login Items in System Settings sees the switch move on
    /// their next visit to the pane rather than a remembered answer.
    /// **What the Privacy pane asked for** (e07a, focus-6pr.3).
    ///
    /// `.deleteEverything` is the one verb in the application whose effect cannot be observed
    /// in the same process that performed it, and that is by design rather than by shortcut.
    /// Every host in this object holds a `ModelContext` on `modelContainer` as a `let`; a store
    /// destroyed under them is a store they would go on writing through, and the review's
    /// ordering finding is that a SQLite file unlinked under a live connection is recreated at
    /// the next checkpoint with the plaintext still in it. So the order is: detach the observer
    /// graph, destroy and rebuild the store through `FocusStore.deleteEverything` (which releases
    /// the descriptors and removes all three files), and **relaunch** — the new process opens the
    /// rebuilt, empty store, and nothing in this one touches a context again. The termination
    /// hooks read `hasDeletedEverything` and write nothing.
    public func perform(_ action: PrivacySettingsAction) {
        switch action {
        case .deleteEverything:
            deleteEverythingAndRelaunch()
        case .setRetentionWindow(let window):
            setRetentionWindow(window)
        case .exportData, .exportSettings, .importSettings:
            performPortability(action)
        case .setSensingPaused(let paused):
            sessionHost.setSensingPaused(paused)
        case .setIdleThreshold(let seconds):
            updateSensingSettings { $0.idleThresholdSeconds = seconds }
        case .setMediaSuppression(let enabled):
            updateSensingSettings { $0.mediaSuppressionEnabled = enabled }
        case .setLaunchContextOnSessionStart(let enabled):
            updateSensingSettings { $0.launchContextOnSessionStart = enabled }
        case .setGrantOptIn(let grant, let isEnabled):
            setGrantOptIn(grant, to: isEnabled)
        }
    }

    /// **Switch one grant's ask on or off** (focus-exdi.4).
    ///
    /// The row first, then the ask: a switch that failed to store must not leave a Mac holding a
    /// grant the app has no record of having been given permission to want. Switching on asks
    /// once, here, so the person sees macOS's dialog as the answer to the switch they just
    /// operated rather than at some later moment they cannot connect to anything.
    private func setGrantOptIn(_ grant: GrantOptIn, to isEnabled: Bool) {
        do {
            try FocusStore.setGrantOptIn(
                grant,
                to: isEnabled,
                in: modelContainer.mainContext,
                now: dateProvider.now
            )
        } catch {
            logger.error("a grant switch could not be stored: \(error, privacy: .public)")
            return
        }
        applyStoredGrantOptIns()
        if isEnabled {
            GrantGate.request(grant, optIns: grantOptIns, using: grantRequester)
        }
        refreshCockpit()
    }

    /// **One observer setting changed** (focus-exdi.3): the row first, then the running host,
    /// so a write that fails leaves the host on what the store still says.
    private func updateSensingSettings(_ change: (inout SensingSettingsValue) -> Void) {
        var settings = sensingHost.settings
        change(&settings)
        do {
            try FocusStore.setSensingSettings(settings, in: modelContainer.mainContext, now: dateProvider.now)
        } catch {
            logger.error("an observer setting could not be stored: \(error, privacy: .public)")
            return
        }
        sensingHost.update(settings: settings)
        refreshCockpit()
    }

    /// **Write the window, and sweep to it now** (F-115, focus-l7n).
    ///
    /// Writing alone would be a promise with a delay in it: somebody who shortens the window to
    /// seven days because they are about to hand the Mac over would have three months of rows on
    /// disk until the next local day turned. So the day marker is cleared and the sweep is run,
    /// which is the same call the tick makes and reads the value that was just written.
    ///
    /// Lengthening the window sweeps too, and removes nothing — the sweep is not a deletion verb,
    /// it is the window being applied, and running it in one direction only would be a second
    /// code path to get wrong.
    func setRetentionWindow(_ window: RetentionWindow) {
        do {
            try FocusStore.setRetentionWindow(
                window,
                in: modelContainer.mainContext,
                now: dateProvider.now
            )
        } catch {
            logger.error(
                "the retention window could not be stored: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        lastRetentionSweep = nil
        sweepRetentionIfDue()
    }

    /// Set the moment the store is destroyed, and read by every write that runs at termination.
    public private(set) var hasDeletedEverything = false

    private func deleteEverythingAndRelaunch() {
        stop()
        hasDeletedEverything = true
        do {
            _ = try FocusStore.deleteEverything(modelContainer, kind: storeKind)
        } catch {
            logger.error(
                "delete everything could not rebuild the store: \(error.localizedDescription, privacy: .public)"
            )
        }
        relaunch()
    }

    /// How the process is replaced. Installed by the app delegate, which is the file that
    /// imports AppKit; a unit process has none and a call to delete everything there ends with
    /// the rebuilt store and no relaunch — which is also what the witness measures.
    public var relaunch: () -> Void = {}

    /// **The General pane's two capture controls** (focus-d3g, focus-tee.6).
    ///
    /// One `perform` in the shape every other settings sink has, so the closure the pane holds is
    /// the closure the self-check drives — and a `{ _ in }` in its place reaches nothing that
    /// moves this object's graph.
    public func perform(_ action: CaptureSettingsAction) {
        switch action {
        case .setRitualEnabled(let isEnabled):
            // The state they asked **for**, not a toggle: a pane built a moment ago cannot invert
            // it, which is the rule `setSensingPaused` and the launch-at-login switch both state.
            setRitualEnabled(isEnabled)
        case .setQuickCaptureShortcut(let spec):
            setQuickCaptureShortcut(spec)
        }
    }

    public func perform(_ action: LaunchAtLoginAction) {
        switch action {
        case .setEnabled(let enabled):
            // The state they asked **for**, not a toggle: a pane built a moment ago cannot invert
            // it, which is the same rule `setSensingPaused` states.
            loginItem.setEnabled(enabled)
            // Asking at all settles the offer. Somebody who found the switch and turned it on
            // must not then be asked in the footer whether they would like to.
            noteLaunchAtLoginOffered()
        case .openSystemSettings:
            loginItem.openSystemSettings()
        }
        refreshLaunchAtLoginOffer()
        refreshCockpit()
    }

    /// **The footer's one-time offer, answered.**
    ///
    /// Both arms record the asking, which is the whole of D-12's *"offered once"*: the app asks,
    /// it does not nag, and *"not now"* is an answer rather than a postponement.
    public func perform(_ action: LaunchAtLoginOfferAction) {
        switch action {
        case .accept: loginItem.setEnabled(true)
        case .dismiss: break
        }
        noteLaunchAtLoginOffered()
        refreshLaunchAtLoginOffer()
        refreshCockpit()
    }

    /// Write down that the offer has been made, and stop making it in this process.
    ///
    /// Both halves, because they answer different readers: the store is what the *next* launch
    /// reads, and the in-memory flag is what stops the row being redrawn on the very next tick of
    /// this one — a person who pressed *Not Now* must see it go, not see it go at the next store
    /// read.
    func noteLaunchAtLoginOffered() {
        hasOfferedLaunchAtLogin = true
        try? FocusStore.recordLaunchAtLoginOffered(
            in: modelContainer.mainContext,
            now: dateProvider.now
        )
    }

    /// **Whether the cockpit's footer is making the offer right now** (D-12, focus-odz.4).
    ///
    /// **A stored answer, recomputed at the moments that can change it, and that is a measured
    /// decision rather than a cache for tidiness.** The decision reads two things out of the
    /// store — how many sessions have been finished, and whether the offer has been made — and
    /// `cockpitState` is projected on **every corroboration tick**. Computing it there would put
    /// two SwiftData fetches into the five-second tick for a number that changes about twice in
    /// the life of a store, which is precisely the shape focus-tzj.2 took out of the tick path and
    /// which `TickFetchBudgetTests` pins.
    ///
    /// So it is recomputed exactly where it can move: at launch, when a session's state changes,
    /// and when the offer is answered from either surface. Anything that could change it and does
    /// not call `refreshLaunchAtLoginOffer()` is a bug in this list rather than in the rule, which
    /// is why the list is short and written down.
    private(set) var showsLaunchAtLoginOffer = false

    /// Recompute the offer from the three facts it turns on.
    ///
    /// The two store reads happen here and nowhere else. `loginItem.status` is not a store read at
    /// all — it asks the system service, which is what D-12 requires and what makes a person who
    /// removed the app from Login Items in System Settings see the row come back.
    func refreshLaunchAtLoginOffer() {
        showsLaunchAtLoginOffer = LaunchAtLoginOffer.shouldOffer(
            status: loginItem.status,
            completedSessions: finishedSessionCount,
            alreadyOffered: hasOfferedLaunchAtLogin
                || FocusStore.shellState(in: modelContainer.mainContext).hasOfferedLaunchAtLogin
        )
    }

    /// Whether this process has already made the offer. See `noteLaunchAtLoginOffered()`.
    private var hasOfferedLaunchAtLogin = false

    // MARK: - Which windows were open, across a relaunch (focus-odz.6)

    /// **Write down which of the app's declared scenes are on screen.**
    ///
    /// Called at termination. AppKit restores a window's *frame* by itself and does not restore
    /// whether a SwiftUI `Window(id:)` scene exists at all — measured in this app's own
    /// self-check, where a launch that inherits a closed cockpit has no `NSWindow` for it in
    /// `NSApp.windows` — so the existence half is recorded here and asked for again at launch.
    ///
    /// The ids come from the caller rather than from `NSApp.windows` read here, because this
    /// object does not import AppKit: `FocusAppDelegate` reads the window list, and
    /// `ShellWindowRestoration.recordable(_:)` narrows whatever it saw down to scenes this app
    /// can ask for again.
    ///
    /// A failed write is swallowed, and that is deliberate: this runs while the process is trying
    /// to leave, and a store error at that moment must not stop somebody quitting. What it costs
    /// is one relaunch that does not restore, which is what the app did before this existed.
    @discardableResult
    public func recordOpenWindows(_ identifiers: [String]) -> [String] {
        let recordable = ShellWindowRestoration.recordable(identifiers)
        lastRecordedOpenWindows = recordable
        try? FocusStore.recordOpenWindows(
            recordable,
            in: modelContainer.mainContext,
            now: dateProvider.now
        )
        return recordable
    }

    /// What the last call to `recordOpenWindows(_:)` wrote. Read by the self-check.
    public private(set) var lastRecordedOpenWindows: [String] = []

    /// **Ask for the scenes that were open at the last quit and are not open now.**
    ///
    /// Idempotent: it runs once per launch and records that it did, so a second call — a scene
    /// graph rebuilt, a delegate notification arriving twice — cannot re-open a window somebody
    /// has just closed.
    ///
    /// It is additive only. A person who quit with the cockpit shut gets it back, because
    /// SwiftUI's `Window` scene opens itself and an app that closed its main window a moment after
    /// launch would be a window vanishing for a reason nobody can see. The whole argument is at
    /// `ShellWindowRestoration`.
    @discardableResult
    public func restoreWindows(alreadyOpen: [String]) -> [String] {
        guard !hasRestoredWindows else { return [] }
        hasRestoredWindows = true

        let recorded = FocusStore.shellState(in: modelContainer.mainContext).openWindowsAtLastQuit
        restorationRecord = recorded
        let wanted = ShellWindowRestoration.windowsToReopen(
            recorded: recorded,
            alreadyOpen: alreadyOpen
        )
        // **Only what really opened is recorded as restored.** `open(_:)` answers `false` when no
        // scene graph installed an opener — a reduced self-check mode, a unit process — and a
        // restoration that counted a refusal as a success would be reporting a window nobody has.
        let opened = wanted.filter { FocusCommandCenter.shared.open($0) }
        restoredWindows = opened.map(\.id)
        return restoredWindows
    }

    /// Whether this launch has already restored. One launch, one restoration.
    public private(set) var hasRestoredWindows = false
    /// What the store said was open at the last quit, as the restoration read it.
    public private(set) var restorationRecord: [String]?
    /// The scene ids this launch actually asked for and got a route to.
    public private(set) var restoredWindows: [String] = []

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

    // MARK: - The two facts the launch read and nothing could write (focus-d3g, focus-tee.6)

    /// Whether the daily ritual banner may be offered at all, as the store holds it.
    public var ritualEnabled: Bool {
        FocusStore.ritualEnabled(in: modelContainer.mainContext)
    }

    /// Turn the daily ritual banner on or off.
    ///
    /// The cockpit's projection is refreshed afterwards, because `shouldPromptRitual()` is read
    /// when `PriorityHost` builds its state and nothing else would ask it again: a switch that
    /// took effect on the next launch is a switch that looks broken.
    public func setRitualEnabled(_ isEnabled: Bool) {
        do {
            try FocusStore.setRitualEnabled(
                isEnabled,
                in: modelContainer.mainContext,
                now: dateProvider.now
            )
            refreshCockpit()
        } catch {
            logger.error(
                """
                the store refused the ritual switch: \
                \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }

    /// **Store a quick-capture shortcut and bind it in the same breath.**
    ///
    /// The two halves are one verb because they were never separable: a stored row the platform
    /// has not been told about is a setting that takes effect next launch, and a registration
    /// nothing stored is one that is lost at quit. P-55 measured the reason it matters —
    /// `RegisterEventHotKey` hands over a combination another application already owns without
    /// complaint — so somebody whose Mac binds the default needs a route to a different one, and
    /// the route has to work now rather than tomorrow.
    ///
    /// - Returns: what the platform said, or `nil` when the store refused the combination before
    ///   the platform was asked. Returned rather than swallowed because the surface has to tell
    ///   the person which of the two happened.
    @discardableResult
    public func setQuickCaptureShortcut(_ spec: HotKeySpec) -> HotKeyRegistration? {
        do {
            try FocusStore.setHotKeySpec(
                spec,
                in: modelContainer.mainContext,
                now: dateProvider.now
            )
        } catch {
            logger.error(
                """
                the store refused a quick-capture shortcut: \
                \(error.localizedDescription, privacy: .public)
                """
            )
            return nil
        }
        // Through the same route the launch takes, so a shortcut set in Settings and one restored
        // at launch are bound by one function rather than by two that have to agree.
        return registerHotKey(spec)
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
    /// The cockpit's whole projection, as the priority host holds it.
    ///
    /// **The two facts the priority host cannot decide for itself reach it through the
    /// environment** (focus-odz.4, focus-odz.7) rather than being patched on here. Whether the
    /// launch-at-login offer is on screen turns on the login-item service and the store's whole
    /// session history, and whether the first-run explanation is owed turns on a row the shell
    /// writes — neither is the priority host's business, and both are the root's. But a value
    /// patched on *after* `refresh()` built the projection is a value SwiftUI never hears about:
    /// this object is a plain `final class`, so writing a property on it invalidates no body. See
    /// `PriorityHost.Environment`, which carries the measurement.
    public var cockpitState: CockpitState { priorityHost.state }

    /// **How many sessions this store has ever finished** (D-12, focus-odz.4).
    ///
    /// The signal the offer waits for. A finished session is `endedAt != nil`, which is
    /// `SessionStore`'s own definition of "not open", so this asks the same question the session
    /// runtime answers rather than inventing a second one.
    var finishedSessionCount: Int {
        (try? sessionHost.finishedSessionCount()) ?? 0
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

    /// **Every fact this app holds in two places at once, and whether the two agree** — and it is
    /// always empty (focus-zrs).
    ///
    /// The sweep this round is really about found three pairs here that are *push projections*
    /// rather than duplicate sources: `SensingHost` owns what is being watched and what this Mac
    /// permits, `RelevanceHost` owns the snapshot the engine reasons from, and each is copied into
    /// a value some window draws. Every copy has a wire that refreshes it when the source moves —
    /// `onSensingChanged → refreshCockpit()`, `onSnapshotInvalidated → invalidateSnapshot()`.
    ///
    /// **Two of the three wires are synchronous. The third is not, and this used to say they all
    /// were** (focus-37b's record, corrected). The two sensing projections are refreshed inside
    /// the call that moved the source, so a reader between them is impossible. The engine's
    /// snapshot is rebuilt from the rule *store*, asynchronously, so there is a real window
    /// between a commitment changing and the snapshot catching up — as the third bullet below
    /// has always said. A blanket "synchronously" is the kind of sentence that makes the third
    /// check look like an invariant when it is a race with a settle point in front of it, and
    /// commit 33fb0df reasoned from the blanket form.
    ///
    /// "Should" is the word six rounds of this epic have been spent on. Each line below is a
    /// disagreement that cannot be argued about, and the gate reads them:
    ///
    /// * **the two windows** — the cockpit draws `state.sensing` / `state.capabilities` (the
    ///   projection), the Privacy pane draws `sensingSummary` / `capabilities` (the source). A
    ///   difference means the app told the truth in one window and something else in the other,
    ///   which is a real, shippable defect.
    /// * **the engine and the loop** — `RelevanceHost` builds its snapshot for one commitment and
    ///   `NudgeHost` writes its receipts under another. The rebuild is asynchronous (it reads the
    ///   rule store), so there is a genuine window here between a commitment changing and the
    ///   snapshot catching up; what the identity fix removed is the *second opinion about which
    ///   commitment*, not the latency of the rebuild. See the note on
    ///   `RelevanceHost.activeCommitment`.
    public var projectionDisagreements: [String] {
        var disagreements: [String] = []
        if cockpitState.sensing != sensingSummary {
            disagreements.append("cockpit's sensing projection ≠ the graph's own summary")
        }
        if cockpitState.capabilities != capabilities {
            disagreements.append("cockpit's capability projection ≠ the probe's own matrix")
        }
        if relevanceHost.snapshot.priorityID != priorityHost.activeCommitment?.id {
            disagreements.append(
                "the engine's snapshot is for \(relevanceHost.snapshot.priorityID?.uuidString ?? "none") "
                    + "and the app is acting under "
                    + "\(priorityHost.activeCommitment?.id.uuidString ?? "none")"
            )
        }
        return disagreements
    }

    /// **The one object allowed to ask macOS for a grant** (focus-exdi.4). Reached only through
    /// `GrantGate`, which refuses unless the person switched that ask on.
    let grantRequester = SystemGrantRequester()

    /// **Which grants the person switched on**, held rather than re-read.
    ///
    /// A stored property, not a computed one: `capabilities` is read by the cockpit, the popover
    /// and the settings window, and a SwiftData fetch on every read is a fetch on every frame
    /// those surfaces draw. Loaded at launch and rewritten by the switch, which are the only two
    /// moments it can change — the same shape `applyStoredPolicyTunings()` uses.
    public private(set) var grantOptIns: GrantOptIns = .none

    /// Read the switches from the store. At launch, and after one is operated.
    func applyStoredGrantOptIns() {
        grantOptIns = FocusStore.grantOptIns(in: modelContainer.mainContext)
    }

    /// What this Mac lets the app do, as the probe read it — with the two opt-in capabilities
    /// answered by the gate rather than by the probe (focus-exdi.4). With nothing switched on
    /// they read `notRequested`, which is exactly what the probe said before this existed.
    public var capabilities: CapabilityMatrix {
        let probed = sensingHost.capabilities
        let optIns = grantOptIns
        guard !optIns.asksForNothing else { return probed }
        var matrix = probed
        let now = dateProvider.now
        for grant in GrantOptIn.allCases where optIns.isEnabled(grant) {
            matrix = matrix.recording(
                grant.capability,
                as: GrantGate.state(of: grant, optIns: optIns, using: grantRequester),
                at: now
            )
        }
        return matrix
    }

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

    /// **A wire fired**, for the one caller that is this object's own code in another file.
    ///
    /// `shellWires`' setter stays private: the receipts are this object's account of itself, and
    /// a verb the module can call is a narrower door than a settable property (focus-tzj.6).
    func note(_ wire: ShellWire) {
        shellWires.insert(wire)
    }

    /// Which of the shell's wires have fired in this process, ever.
    ///
    /// Read by `--focus-self-check`. Not cleared: a wire that fires once has been proved to
    /// exist, and there is no question this answers that a *current* reading would answer better.
    public private(set) var shellWires: Set<ShellWire> = []

    // MARK: - What each window drew, beside what it was handed (focus-h7h, focus-7ow)

    /// **The ledger of what was handed to each window and what came back** (focus-tzj.6).
    ///
    /// Four dictionaries and six verbs, in `ShellRenderAudit`, where they can be read and driven
    /// without a composition root. This object owns one and forwards the four readings the
    /// self-check and the test lane take, so nothing outside moves.
    private let shellRenderAudit = ShellRenderAudit()

    /// What each window says it drew, latest report per surface.
    public var shellRenderings: [ShellThemedSurface: ShellRenderedValues] {
        shellRenderAudit.renderings
    }

    /// The issue number a window's report must carry to be current.
    public func shellGeneration(of surface: ShellThemedSurface) -> Int {
        shellRenderAudit.generation(of: surface)
    }

    /// **The reading for one window**: what it drew, held up beside what it was handed.
    public func shellRenderReading(of surface: ShellThemedSurface) -> ShellRenderReading {
        shellRenderAudit.renderReading(of: surface)
    }

    /// **Whether the receipts for this window's connection are total** (focus-7ow).
    public func shellTotalityReading(of surface: ShellThemedSurface) -> ShellTotalityReading {
        shellRenderAudit.totalityReading(of: surface)
    }

    /// One window's report, as it arrived from the preference channel.
    func record(_ values: ShellRenderedValues, for surface: ShellThemedSurface) {
        shellRenderAudit.record(values, for: surface)
    }

    /// Walk the connection this object has just built, against the expectations it has just
    /// recorded.
    func audit<Connection: ShellDrawnConnection>(
        _ connection: Connection,
        for surface: ShellThemedSurface
    ) {
        shellRenderAudit.audit(connection, for: surface)
    }

    /// Take the next issue number for a window.
    func nextGeneration(for surface: ShellThemedSurface) -> Int {
        shellRenderAudit.nextGeneration(for: surface)
    }

    /// Record one value this object is handing to a window.
    func expect(_ field: ShellRenderedField, _ value: String, for surface: ShellThemedSurface) {
        shellRenderAudit.expect(field, value, for: surface)
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
        ShellConnectionFactory.cockpit(for: self)
    }

    /// **Everything the Settings window draws and every verb it can perform**, in the same shape
    /// and for the same reason (focus-2er).
    ///
    /// Two of the epic's four acceptance mutations lived in the arguments this replaces:
    /// `onInterventionAction` gutted to `{ _ in }`, which under U-1 is what decides whether the
    /// app may speak, and the appearance store write deleted from a `Binding`'s setter written
    /// by hand in a scene body. Both are verbs on this object now.
    public func settingsConnection() -> ShellSettingsConnection {
        ShellConnectionFactory.settings(for: self)
    }

    /// **Which Settings pane is on screen** (focus-7ow).
    ///
    /// Held here rather than as a `@State` in the window, for the reason the appearance
    /// preference is: a macOS `TabView` builds only the selected pane, so before this existed
    /// every receipt inside an unselected pane simply never arrived — measured, on the first run
    /// of the render receipts: the Privacy pane's stamps were absent because nobody had clicked
    /// Privacy. A defect inside an unselected pane was invisible to every lane in the programme.
    /// The self-check walks all three.
    /// An `@Observable` box rather than a stored property, and that is a measurement: this object
    /// is a plain `final class`, so writing a property on it invalidates no SwiftUI body. Driven
    /// from a stored property here, all three tabs moved and the window went on reporting the
    /// General pane's one value. See `SettingsTabSelection`.
    public let settingsTabSelection = SettingsTabSelection()

    public var settingsTab: SettingsTab { settingsTabSelection.tab }

    /// A tab was chosen — by a person clicking it, or by the self-check walking the panes.
    public func selectSettingsTab(_ tab: SettingsTab) {
        settingsTabSelection.tab = tab
        expect(.settingsTab, tab.rawValue, for: .settings)
    }

    /// **The Settings window handed its sinks back** — `settingsSinks`' one writer, for the
    /// reason `note(_:)` exists (focus-tzj.6).
    func noteSettingsRendering(_ rendering: ShellSettingsRendering) {
        settingsSinks = rendering
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
    // MARK: - History (e09a, focus-tee.5)

    /// The silent intervals a correction has already been written for, so the button becomes a
    /// sentence rather than staying live and inviting a second identical rule.
    ///
    /// In memory and not in the store on purpose. The rule itself is the durable record — it is
    /// in the Rules pane, deletable and undoable like any other — and a second stored fact
    /// saying *"and History has drawn a tick for this"* would be a row whose only reader is a
    /// window's appearance.
    public private(set) var correctedHistoryRows: Set<UUID> = []

    /// **Today's ledger**, read fresh every time the window draws it.
    ///
    /// Fresh store handles over the one `ModelContext`, exactly as `RetentionSweep`'s are: a
    /// store object is a facade over the context, and holding one for the life of the app would
    /// be holding a cache rather than holding rows.
    ///
    /// Returns an empty day rather than throwing. A window that cannot open because a fetch
    /// failed is worse than one that says nothing happened, and the failure is logged where the
    /// other store refusals in this object are.
    public func todaysHistory() -> DayHistory {
        let context = modelContainer.mainContext
        do {
            return try DayHistory.build(
                day: LocalDay.today(calendar: calendar, dateProvider: dateProvider),
                log: InterventionLog(
                    context: context,
                    dateProvider: dateProvider,
                    calendar: calendar
                ),
                ledger: QueryLedger(context: context, dateProvider: dateProvider),
                events: ActivityEventStore(context: context, dateProvider: dateProvider),
                sessions: SessionStore(
                    context: context,
                    dateProvider: dateProvider,
                    uptimeClock: uptimeClock,
                    bootIdentity: bootIdentity
                ),
                priorities: PriorityStore(context: context, dateProvider: dateProvider),
                calendar: calendar
            )
        } catch {
            logger.error(
                "the store refused a history read: \(error.localizedDescription, privacy: .public)"
            )
            return DayHistory(
                day: LocalDay.today(calendar: calendar, dateProvider: dateProvider),
                entries: [],
                priorityWording: [:]
            )
        }
    }

    /// **"This was a distraction"** — the person disagreeing with a silence.
    ///
    /// Writes one task-authority rule through `HistoryCorrection`, which is constructed with no
    /// `QueryLedger` at all: a correction here can never settle or re-open a question. A refusal
    /// — a priority deleted while the window was open — is logged and drawn as nothing, because
    /// the affordance the person clicked is withdrawn on the next read with its reason.
    public func correctHistorySilence(_ silence: HistorySilence, undo: UndoManager? = nil) {
        let context = modelContainer.mainContext
        do {
            _ = try HistoryCorrection.markAsDistraction(
                silence.correction,
                priorities: PriorityStore(context: context, dateProvider: dateProvider),
                at: dateProvider.now,
                undo: undo
            )
            correctedHistoryRows.insert(silence.id)
            // The engine holds a snapshot built before this rule existed; without this the next
            // judgement about the same subject would still answer from the old one.
            relevanceHost.invalidateSnapshot()
        } catch {
            logger.error(
                """
                the store refused a history correction: \
                \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }

    public func helpWindowRendered(_ values: ShellRenderedValues) {
        shellWires.insert(.helpRendered)
        record(values, for: .help)
        // **The one issue.** The reference reads nothing from the graph, so there is no
        // connection for it to draw from and nothing for it to become stale against: it draws
        // `CommandRegistry.shell`, which cannot change while the process lives. The expectation
        // is therefore the committed table's own row count, counted through the same function the
        // window draws from — one derivation, two consumers, rather than a number written twice.
        shellRenderAudit.pinGeneration(ShellRenderedValues.singleIssue, for: .help)
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
        // **Reduce Motion reaches the nudge loop, and until focus-w7v it reached nothing.** Six
        // places in this repository said it did. This wire re-themed the capture panel, the nudge
        // panel and the menu bar, and never touched `nudgeHost` — so `reducedInterruption` was
        // only ever the pane's own checkbox, a Reduce Motion user got a full animated `NSPanel`,
        // and `settings.intervention.reduced.forced` — *"Reduce Motion is on, so this stays
        // on."* — was a shipped string with no code path that could draw it.
        //
        // It costs no authorisation: `NSWorkspace` answers the accessibility flags at zero
        // grants, which is why this is a wire rather than a deletion of the claims.
        nudgeHost.observe(reduceMotion: traits.reduceMotion)
        // **The nudge surfaces are shell surfaces too** (focus-pq8). This wire reached the quick
        // capture panel and nothing else, so the two surfaces a person meets *because the app
        // interrupted them* — the nudge panel and the menu-bar popover — kept
        // `AppearanceTraits.systemDefault` for the life of the process. Light, with every
        // accessibility setting off, whatever the Mac was actually set to: the app drew the wrong
        // thing in dark mode, and `differentiateWithoutColor` never reached the status item at all.
        nudgePanel.update(traits: traits)
        menuBar.update(menuBarPresentation(), traits: traits)
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

    /// Persist all three of the Intervention pane's settings, as the loop now holds them.
    ///
    /// The loop has already been moved by the caller, so the shell and the next judgement act on
    /// the new setting immediately even if this write fails: a store that cannot be written is a
    /// reason to tell the user, never a reason to ignore what they just chose. That is the same
    /// order — and the same reason — `setAppearancePreference(_:)` records.
    ///
    /// **One writer, and it writes the whole value** (`nudgeHost.chosen`), rather than three
    /// writers each carrying one field. A partial write from a caller that had read only its own
    /// field is the shape that resets the other two to whatever that caller last saw, which is
    /// exactly why `setSensingPaused(_:in:now:)` exists as a named verb rather than as a
    /// read-modify-write at each call site.
    /// **Every dial, read from the store and handed to both engines** (focus-exdi). At launch
    /// and after every turn of a dial; the shipped constants when no row exists.
    func applyStoredPolicyTunings() {
        let tunings = FocusStore.policyTunings(in: modelContainer.mainContext)
        relevanceHost.adopt(tunings)
        nudgeHost.tunings = tunings
    }

    private func persistInterventionPreferences() {
        do {
            try FocusStore.setInterventionPreferences(
                nudgeHost.chosen,
                in: modelContainer.mainContext,
                now: dateProvider.now
            )
        } catch {
            logger.error(
                "the store refused an intervention preference: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// **What the person set last time, read back into the loop at launch** (focus-z7g,
    /// focus-40i).
    ///
    /// Without this the store write above would be a write nobody reads, which is a defect of
    /// exactly the shape this repair exists to end. Called from `startNudgeLoop()`, beside the
    /// Reduce Motion reading, and for the same reason it is there: a nudge raised before the
    /// cockpit's first paint must be decided against the person's real settings rather than
    /// against the defaults this object was constructed with.
    func applyStoredInterventionPreferences() {
        let stored = FocusStore.interventionPreferences(in: modelContainer.mainContext)
        // **An uninterpretable deck is said out loud, and the app still opens** (D4, focus-0nm).
        // The row is not corrupt and nothing is lost by reading it as the shipped deck — the
        // likely cause is a downgrade after a newer build wrote a raw value this one has never
        // heard of. What would be a defect is doing it silently, which is what the decoder did
        // before it carried `wasRecognised`: the person's chosen voice would have become
        // `neutral` with no line in any log and no reading in the self-check.
        if !stored.storedVoiceWasRecognised {
            logger.fault(
                """
                the stored intervention deck is not one this build can read; \
                speaking in \(NudgeVoice.standard.rawValue, privacy: .public) \
                and leaving the row alone
                """
            )
        }
        nudgeHost.adopt(stored)
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
            // **Built without this, so the flag took its `false` default** (focus-w7v). The pane
            // draws a disabled switch and *"Reduce Motion is on, so this stays on."* from it, and
            // neither could ever appear: the value the router routes on and the value the pane
            // explains itself with came from two different places, and one of them was a
            // literal. Both are the loop's now.
            reducedInterruptionIsForced: nudgeHost.systemForcesReducedInterruption,
            // **The live window, not the constant the pane's own proof compared against**
            // (focus-z7g). This was `InterventionPolicy.quietHoursDefault` — `nil`, for ever —
            // so the pane redrew *"Set a window / Off"* whatever the person pressed, the four
            // boundary buttons were unreachable in the product, and the settings connection's
            // `expect(.quietHours, …)` audit compared the drawn row against the very same
            // hardcoded constant that filled it. The proof agreed with itself.
            quietHours: nudgeHost.quietHours.window,
            usage: nudgeHost.todaysUsage(),
            // **The geometry's own answer, taken from the renderer** (e08a). Not a preference and
            // not a constant: the row a person reads is the reason the companion is or is not
            // drawing, computed from the same `NotchLanding` the strip is placed from.
            notchRefusal: notchCompanion.landing().refusal,
            // **The list, and what could be added to it** (F-121, focus-62o, focus-u3w). Read
            // from the store and from the workspace every time this value is built, for
            // `quietHours`' reason: a pane answering from its own memory would go on showing a
            // row somebody had just removed, and a list of running applications is out of date
            // the moment an app quits.
            presentationExclusions: presentationExclusions(),
            addableApplications: addablePresentationExclusions(),
            tunings: nudgeHost.tunings
        )
    }

    /// The presentation-exclusion list, resolved to names a person recognises.
    ///
    /// The store keeps identifiers; the name comes from the workspace where the application is
    /// running and from the identifier itself where it is not. An application that is not open
    /// still belongs on the list — the person put it there — so a row that cannot be named is
    /// drawn under its identifier rather than dropped.
    func presentationExclusions() -> [PresentationExclusion] {
        let rows = (try? SensitiveAppSeed.rows(in: modelContainer.mainContext)) ?? []
        let names = Dictionary(
            RunningApplications.choices().map { ($0.bundleID, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        return rows
            .filter { $0.kind?.list == .presentationExcluded && ($0.kind?.isActive ?? false) }
            .map {
                PresentationExclusion(
                    bundleID: $0.bundleID,
                    displayName: names[$0.bundleID] ?? $0.bundleID
                )
            }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    /// What is running that is not already on the list. Offering an application a second time
    /// would be offering a button that does nothing.
    func addablePresentationExclusions() -> [PresentationExclusion] {
        let already = Set(presentationExclusions().map(\.bundleID))
        return RunningApplications.choices().filter { !already.contains($0.bundleID) }
    }

    /// What the Intervention pane asked for.
    ///
    /// The one thing it **cannot** ask for is a permission. It used to: a
    /// `notificationAuthorisationChanged` case reported that the pane's own `requestAuthorization`
    /// had returned, and this re-read the answer. Both are gone (focus-wy0) — this app posts no
    /// notifications, so there is no permission for a person to grant it here and nothing to
    /// re-read when they do.
    public func perform(_ action: InterventionSettingsAction) {
        switch action {
        case .setVoice(let voice):
            // **The loop and the row, for the reason the window below gets both** (focus-40i).
            // These were `nudgeHost.choose(…)` alone: a plain in-memory property, no column and
            // no `UserDefaults` key anywhere in the repository, so a person who picked *Warm* or
            // asked to be interrupted less got `neutral` and full panels back on the next
            // launch. Reduced interruption decides **where** a nudge lands, so the setting that
            // read as cosmetic was the one that silently restored the panel for somebody who had
            // asked for quiet.
            nudgeHost.choose(voice: voice)
            persistInterventionPreferences()
        case .setReducedInterruption(let reduced):
            nudgeHost.choose(reducedInterruption: reduced)
            persistInterventionPreferences()
        case .setQuietHours(let window):
            // **Both halves, in this order** (focus-z7g). The loop first, so the very next
            // judgement is decided against the window the person just set even if the write
            // below fails; then the row, so it is still set after they quit. A control that
            // moved one and not the other is the defect this replaces wearing different
            // clothes.
            nudgeHost.choose(quietHours: window)
            persistInterventionPreferences()
            refreshCockpit()
        // **The two halves of the exclusion list** (F-121, focus-62o, focus-u3w). Straight to
        // the store's own verbs, which are idempotent and tombstone-aware: adding twice is one
        // row, and removing a built-in leaves a tombstone rather than a gap the next launch
        // would re-seed. `SensitiveAppSeed.add` had **no shipping call site at all** before this.
        case .setPolicyTuning(let tuning, let value):
            do {
                try FocusStore.setPolicyTuning(
                    tuning,
                    to: value,
                    in: modelContainer.mainContext,
                    now: dateProvider.now
                )
            } catch {
                logger.error("a policy dial could not be stored: \(error, privacy: .public)")
            }
            applyStoredPolicyTunings()
        case .resetPolicyTunings:
            do {
                try FocusStore.resetPolicyTunings(in: modelContainer.mainContext)
            } catch {
                logger.error("the policy dials could not be reset: \(error, privacy: .public)")
            }
            applyStoredPolicyTunings()
        case .addPresentationExclusion(let bundleID):
            writeExclusion { context, now in
                _ = try SensitiveAppSeed.add(
                    bundleID: bundleID,
                    to: .presentationExcluded,
                    in: context,
                    now: now
                )
            }
        case .removePresentationExclusion(let bundleID):
            writeExclusion { context, _ in
                try SensitiveAppSeed.remove(
                    bundleID: bundleID,
                    from: .presentationExcluded,
                    in: context
                )
            }
        }
    }

    /// One write, and then the pane and the loop both re-read. The sensing host consults the
    /// list on every judgement, so a change that only reached the store would take effect on the
    /// next launch — which is the shape of a setting that does not work.
    private func writeExclusion(_ body: (ModelContext, Date) throws -> Void) {
        do {
            try body(modelContainer.mainContext, dateProvider.now)
        } catch {
            logger.error(
                "the exclusion list refused a write: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        refreshCockpit()
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
    /// **Sweep, if the day has turned since the last one** (F-115, focus-tzj.3).
    ///
    /// Two moments, and they are the same call: the launch, and the first corroboration tick of
    /// a new local day. There is no timer — this programme has none — and there does not need to
    /// be one: the tick already runs every five seconds and the local day is already computed on
    /// it, so "once a day" is a comparison rather than a schedule.
    ///
    /// The day is the person's own calendar's, for `LocalDay`'s reason: a retention window is a
    /// promise about days, and somebody who flies to Auckland mid-morning is in a different one.
    ///
    /// A failed sweep is logged and **not** retried until the next day boundary. Retrying on the
    /// next tick would turn a store that will not delete into a store the app tries to delete
    /// from twelve times a minute, which is the shape of an unbounded table seen from the other
    /// side.
    func sweepRetentionIfDue() {
        let today = LocalDay.today(calendar: calendar, dateProvider: dateProvider)
        guard lastRetentionSweep?.day != today else { return }
        do {
            let result = try retentionSweep.run()
            lastRetentionSweep = result
            if result.rowsRemoved > 0 {
                logger.notice(
                    """
                    retention swept \(result.rowsRemoved, privacy: .public) row(s) \
                    older than the window
                    """
                )
            }
        } catch {
            // The day is recorded even so, for the reason above. What is lost is one day's
            // sweep; what is prevented is a write attempt on every tick for the life of the run.
            lastRetentionSweep = RetentionSweep.Result(
                day: today,
                window: FocusStore.privacyPreferences(
                    in: modelContainer.mainContext
                ).retention,
                activityEvents: 0,
                interventionRows: 0,
                queryReceipts: 0
            )
            logger.error(
                "the retention sweep failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func refreshCockpit() {
        // The day boundary the budget already computes, read for the other thing that happens
        // once a day (focus-tzj.3). It is a comparison against a stored `LocalDay` and nothing
        // else on the overwhelming majority of ticks.
        sweepRetentionIfDue()
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
                storeOpened: storeStatus.isReady,
                isObservingActivity: sensingHost.isRunning,
                session: snapshot,
                sensing: sensingHost.summary,
                capabilities: sensingHost.capabilities,
                verdict: relevanceHost.verdict,
                // **Through the environment, so a change to either redraws the window**
                // (focus-odz.4, focus-odz.7). See `PriorityHost.Environment` for the measurement
                // that put them here rather than on the projection afterwards.
                showsLaunchAtLoginOffer: showsLaunchAtLoginOffer,
                showsFirstRunExplanation: showsFirstRunExplanation
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
