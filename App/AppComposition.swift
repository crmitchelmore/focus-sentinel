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

    /// The activity source. In e02 this is still the null observer: it reports itself
    /// unavailable and finishes its stream immediately, which is the honest answer for a
    /// build with no sensing adapters. e03 replaces it without any consumer changing.
    let activityObserver: any ActivityObserving

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
        activityObserver: any ActivityObserving = NullActivityObserver(),
        classifier: any RelevanceClassifier = UndecidedClassifier(),
        hotKeyRegistrar: any HotKeyRegistering = CarbonHotKeyRegistrar(),
        ruleStoreOverride: (any RuleStore)? = nil
    ) {
        self.dateProvider = dateProvider
        self.monotonicClock = monotonicClock
        self.calendar = calendar
        self.locale = locale
        self.activityObserver = activityObserver
        self.classifier = classifier
        self.hotKeyRegistrar = hotKeyRegistrar

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
        self.priorityHost = PriorityHost(
            context: context,
            dateProvider: dateProvider,
            calendar: calendar,
            locale: locale,
            environment: PriorityHost.Environment(
                status: activityObserver.availability.isAvailable ? .uncertain : .paused,
                storeIsReady: status.isReady,
                isObservingActivity: activityObserver.availability.isAvailable
            )
        )

        // Built now, with the panel's SwiftUI content and its hosting view, so that `show()`
        // later is nothing but state changes on objects that already exist (P-57).
        self.quickCapturePanel = QuickCapturePanelController()
    }

    /// Register the hot key and connect the panel to the store.
    ///
    /// Separate from `init` and idempotent, because it is the half that touches AppKit and
    /// the Carbon event target: it must run once the application object exists, and running
    /// it twice would offer the same combination to the platform twice.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        quickCapturePanel.onCommit = { [weak self] result in
            guard let self else { return }
            self.priorityHost.setPriority(intent: result.intent, doneWhen: result.doneWhen)
        }

        registerHotKey(storedHotKeySpec())
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
    /// `paused` is the truthful answer while no activity source is running: the app has
    /// observed nothing and therefore judged nothing. Showing `relevant` or `unrelated`
    /// here would be inventing a verdict.
    var currentStatus: FocusStatus {
        activityObserver.availability.isAvailable ? .uncertain : .paused
    }

    /// Why the app is not observing anything yet, when it is not.
    var observationAvailability: ObservationAvailability {
        activityObserver.availability
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
}
