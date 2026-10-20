import FocusCore
import Foundation
import Sparkle
import Testing

@testable import FocusUpdates

/// **The updater does nothing until it is asked** (focus-h8jf).
///
/// The real updater stays inert. Its lifecycle is driven through a controller double that
/// opens no socket and presents no UI.
@Suite("The Sparkle updater")
@MainActor
struct SparkleUpdaterTests {
    @Test("built with checks off, it is not started and can still take a manual check")
    func offIsInert() {
        let updater = SparkleUpdater(train: .stable, checksAutomatically: false)
        #expect(!updater.isStarted)
        #expect(updater.canCheckForUpdates)
        #expect(updater.lastCheckDate == nil)
    }

    @Test("switching checks off on a never-started updater leaves it never started")
    func offOnUnstartedStaysUnstarted() {
        let updater = SparkleUpdater(train: .alpha, checksAutomatically: false)
        updater.setAutomaticChecks(false)
        #expect(!updater.isStarted)
    }

    @Test("the feed it would ask is the train's, per train")
    func feedIsTheTrains() {
        for train in ReleaseTrain.allCases {
            #expect(train.feedURL.hasPrefix("https://"), "\(train.rawValue) feed is not https")
        }
        #expect(ReleaseTrain.stable.feedURL != ReleaseTrain.alpha.feedURL)
    }

    @Test("a failed start is not reported as started, does not check, and can be retried")
    func failedStartCanBeRetried() {
        let controller = SparkleControllerDouble()
        controller.startError = NSError(domain: SUSparkleErrorDomain, code: 7)
        var reportedErrors = 0
        let updater = SparkleUpdater(
            train: .stable,
            checksAutomatically: false,
            makeController: { _ in controller },
            reportStartupError: { _ in reportedErrors += 1 }
        )
        updater.checkForUpdates()
        #expect(!updater.isStarted)
        #expect(updater.canCheckForUpdates)
        #expect(updater.lastFailure == .configuration)
        #expect(controller.manualChecks == 0)
        #expect(reportedErrors == 1)

        controller.startError = nil
        updater.checkForUpdates()
        #expect(updater.isStarted)
        #expect(updater.lastFailure == nil)
        #expect(controller.starts == 2)
        #expect(controller.manualChecks == 1)
        updater.checkForUpdates()
        #expect(controller.starts == 2)
        #expect(controller.manualChecks == 2)
    }

    @Test("Sparkle's own availability changes reach the status callback, observed once")
    func availabilityChangesAreHeard() {
        let controller = SparkleControllerDouble()
        let updater = SparkleUpdater(
            train: .stable,
            checksAutomatically: false,
            makeController: { _ in controller },
            reportStartupError: { _ in }
        )
        var changes = 0
        updater.onStatusChange = { changes += 1 }
        updater.setAutomaticChecks(true)
        updater.setAutomaticChecks(true)
        #expect(controller.availabilityObservers.count == 1)

        changes = 0
        controller.sparkleAvailabilityChanged(to: false)
        #expect(changes == 1)
        #expect(!updater.canCheckForUpdates)
        controller.sparkleAvailabilityChanged(to: true)
        #expect(changes == 2)
        #expect(updater.canCheckForUpdates)
    }

    @Test("a manual check clears Sparkle's remembered automatic opt-in before starting")
    func manualCheckDoesNotEnableScheduledChecks() {
        let controller = SparkleControllerDouble()
        controller.automaticallyChecksForUpdates = true
        var madeControllers = 0
        let updater = SparkleUpdater(
            train: .alpha,
            checksAutomatically: false,
            makeController: { _ in madeControllers += 1; return controller },
            reportStartupError: { _ in Issue.record("unexpected startup failure") }
        )
        updater.setAutomaticChecks(false)
        #expect(madeControllers == 0)
        updater.checkForUpdates()
        #expect(controller.automaticChoicesAtStart == [false])
        #expect(!controller.automaticallyChecksForUpdates)

        updater.setAutomaticChecks(true)
        #expect(controller.automaticallyChecksForUpdates)
        updater.setAutomaticChecks(false)
        #expect(!controller.automaticallyChecksForUpdates)
        #expect(controller.starts == 1)
    }

    @Test("an automatic opt-in is applied before the updater starts")
    func automaticChoicePrecedesStart() {
        let controller = SparkleControllerDouble()
        let updater = SparkleUpdater(
            train: .stable,
            checksAutomatically: true,
            makeController: { _ in controller },
            reportStartupError: { _ in Issue.record("unexpected startup failure") }
        )
        #expect(updater.isStarted)
        #expect(controller.automaticChoicesAtStart == [true])
    }

    @Test("a busy updater does not receive another check, and status changes are reported")
    func busyAndFinishedChecks() {
        let controller = SparkleControllerDouble()
        let updater = SparkleUpdater(
            train: .stable,
            checksAutomatically: false,
            makeController: { _ in controller },
            reportStartupError: { _ in Issue.record("unexpected startup failure") }
        )
        var changes = 0
        updater.onStatusChange = { changes += 1 }
        updater.checkForUpdates()
        controller.canCheckForUpdates = false
        updater.checkForUpdates()
        #expect(controller.manualChecks == 1)

        updater.finishUpdateCheck(error: NSError(
            domain: SUSparkleErrorDomain, code: Int(SUError.downloadError.rawValue)
        ))
        #expect(updater.lastFailure == .feedUnavailable)
        #expect(changes == 2)

        controller.canCheckForUpdates = true
        updater.checkForUpdates()
        #expect(updater.lastFailure == nil)
        #expect(controller.manualChecks == 2)
        updater.finishUpdateCheck(error: nil)
        #expect(updater.lastFailure == nil)
    }

    @Test("feed failures and wrapped connection errors are distinct; no update is not a failure")
    func errorsAreClassified() {
        let connection = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let wrapped = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.downloadError.rawValue),
            userInfo: [NSUnderlyingErrorKey: connection]
        )
        #expect(SparkleUpdater.failure(for: wrapped) == .network)
        for code in [SUError.downloadError, .appcastError, .appcastParseError] {
            #expect(SparkleUpdater.failure(for: NSError(
                domain: SUSparkleErrorDomain, code: Int(code.rawValue)
            )) == .feedUnavailable)
        }
        for code in [SUError.noUpdateError, .installationCanceledError, .installationAuthorizeLaterError] {
            #expect(SparkleUpdater.failure(for: NSError(
                domain: SUSparkleErrorDomain, code: Int(code.rawValue)
            )) == nil)
        }
        #expect(SparkleUpdater.failure(for: NSError(domain: "test", code: 1)) == .other)
    }
}

@MainActor
private final class SparkleControllerDouble: SparkleControlling {
    var canCheckForUpdates = true
    var lastCheckDate: Date?
    var automaticallyChecksForUpdates = false
    var startError: Error?
    private(set) var starts = 0
    private(set) var manualChecks = 0
    private(set) var automaticChoicesAtStart: [Bool] = []

    func start() throws {
        starts += 1
        automaticChoicesAtStart.append(automaticallyChecksForUpdates)
        if let startError { throw startError }
    }

    func checkForUpdates() { manualChecks += 1 }

    private(set) var availabilityObservers: [@MainActor () -> Void] = []
    func observeAvailability(_ onChange: @escaping @MainActor () -> Void) -> AnyObject? {
        availabilityObservers.append(onChange)
        return NSObject()
    }

    func sparkleAvailabilityChanged(to value: Bool) {
        canCheckForUpdates = value
        availabilityObservers.forEach { $0() }
    }
}
