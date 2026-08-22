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

    /// The activity source. In e01 this is the null observer: it reports itself
    /// unavailable and finishes its stream immediately, which is the honest answer for a
    /// build with no sensing adapters. e03 replaces it without any consumer changing.
    let activityObserver: any ActivityObserving

    /// The relevance classifier. In e01 this is the undecided classifier: it answers
    /// `uncertain` to everything, and `uncertain` suppresses intervention, so an app built
    /// on it is structurally incapable of nudging. e04 and e06 replace it behind the same
    /// seam.
    let classifier: any RelevanceClassifier

    /// The rule store. In-memory in e01 — the SwiftData-backed store arrives with e02's
    /// rule-authoring surface, and nothing yet writes a durable rule.
    let ruleStore: any RuleStore

    init(
        dateProvider: any DateProvider = SystemDateProvider(),
        monotonicClock: any MonotonicClock = SystemMonotonicClock(),
        activityObserver: any ActivityObserving = NullActivityObserver(),
        classifier: any RelevanceClassifier = UndecidedClassifier(),
        ruleStore: any RuleStore = InMemoryRuleStore()
    ) {
        self.dateProvider = dateProvider
        self.monotonicClock = monotonicClock
        self.activityObserver = activityObserver
        self.classifier = classifier
        self.ruleStore = ruleStore

        // Every container in this programme is built through `FocusStore.makeContainer`,
        // which always goes through the migration plan. If the on-disk store cannot be
        // opened we fall back to an in-memory one so the shell still runs and can *report*
        // the failure — never a crash, and never a silent switch the user cannot see.
        do {
            self.modelContainer = try FocusStore.makeContainer(kind: .applicationSupport)
            self.storeStatus = .ready
        } catch {
            self.storeStatus = .unavailable(error.localizedDescription)
            do {
                self.modelContainer = try FocusStore.makeContainer(kind: .inMemory)
            } catch {
                // An in-memory container cannot fail for any reason the app can recover
                // from: the schema itself would have to be invalid, which is a programming
                // error, not a runtime condition.
                fatalError("the v1 schema does not load: \(error)")
            }
        }
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
        CockpitState(
            status: currentStatus,
            storeIsReady: storeStatus.isReady,
            isObservingActivity: activityObserver.availability.isAvailable
        )
    }
}
