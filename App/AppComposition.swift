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

    /// The relevance classifier. In e02 this is still the undecided classifier: it answers
    /// `uncertain` to everything, and `uncertain` suppresses intervention, so an app built
    /// on it is structurally incapable of nudging. e04 and e06 replace it behind the same
    /// seam.
    let classifier: any RelevanceClassifier

    /// The rule store. SwiftData-backed from e02, so a rule the user authors in the cockpit
    /// is the same row e04's engine will read.
    let ruleStore: any RuleStore

    /// The global hot-key registrar (F-06). Carbon `RegisterEventHotKey`, proven grant-free on
    /// this Mac (P-56), reached through a `FocusCore` seam so that neither `FocusUI` nor this
    /// file has to know Carbon exists.
    let hotKeyRegistrar: any HotKeyRegistering

    /// The pre-built quick-capture panel. Built here, at launch, and never rebuilt.
    let quickCapturePanel: QuickCapturePanelController

    /// The only `PriorityActing` implementation: the SwiftData ⇄ `CockpitState` bridge.
    let priorityHost: PriorityHost

    /// What the platform said when the app offered it the stored shortcut, kept so that
    /// `--focus-self-check` can report it and the Capture settings tab can explain a refusal
    /// rather than leaving a shortcut that silently does nothing.
    private(set) var hotKeyRegistration: HotKeyRegistration?

    /// The shortcut the app actually asked for.
    private(set) var hotKeySpec: HotKeySpec = .quickCaptureDefault

    private var hasStarted = false

    init(
        dateProvider: any DateProvider = SystemDateProvider(),
        monotonicClock: any MonotonicClock = SystemMonotonicClock(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        uptimeClock: any UptimeClock = SystemUptimeClock(),
        classifier: any RelevanceClassifier = UndecidedClassifier(),
        hotKeyRegistrar: any HotKeyRegistering = CarbonHotKeyRegistrar(),
        ruleStoreOverride: (any RuleStore)? = nil
    ) {
        self.dateProvider = dateProvider
        self.monotonicClock = monotonicClock
        self.calendar = calendar
        self.locale = locale
        self.uptimeClock = uptimeClock
        self.classifier = classifier
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

        self.priorityHost = PriorityHost(
            context: context,
            dateProvider: dateProvider,
            calendar: calendar,
            locale: locale,
            environment: PriorityHost.Environment(
                // Sensing is live from e03, so the honest status is `uncertain` — the app is
                // observing and the classifier is still `UndecidedClassifier`, which answers
                // `uncertain` to everything. It is `paused` when the person has the switch off.
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
    /// nothing and therefore judged nothing. `uncertain` is the truthful answer while it *is* —
    /// `UndecidedClassifier` is still wired, and it answers `uncertain` to everything, so at
    /// the end of this epic the app observes everything and judges nothing. Showing `relevant`
    /// or `unrelated` here would be inventing a verdict.
    var currentStatus: FocusStatus {
        sensingHost.isRunning ? .uncertain : .paused
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
        priorityHost.update(
            environment: PriorityHost.Environment(
                status: currentStatus,
                storeIsReady: storeStatus.isReady,
                isObservingActivity: sensingHost.isRunning,
                session: snapshot,
                sessionElapsedSeconds: snapshot?.elapsedWallSeconds(now: dateProvider.now),
                lastActiveBundleID: sensingHost.lastForeignBundleIdentifier,
                sensing: sensingHost.summary,
                capabilities: sensingHost.capabilities
            )
        )
    }
}
