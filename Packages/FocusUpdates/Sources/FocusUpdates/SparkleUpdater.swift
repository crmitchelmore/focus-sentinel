import AppKit
import FocusCore
import Sparkle
import os

@MainActor
protocol SparkleControlling: AnyObject {
    var canCheckForUpdates: Bool { get }
    var lastCheckDate: Date? { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func start() throws
    func checkForUpdates()
    /// Calls `onChange` whenever Sparkle's own `canCheckForUpdates` moves; the token keeps it alive.
    func observeAvailability(_ onChange: @escaping @MainActor () -> Void) -> AnyObject?
}

extension SPUStandardUpdaterController: SparkleControlling {
    var canCheckForUpdates: Bool { updater.canCheckForUpdates }
    var lastCheckDate: Date? { updater.lastUpdateCheckDate }
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    func start() throws { try updater.start() }
    func checkForUpdates() { checkForUpdates(nil) }

    func observeAvailability(_ onChange: @escaping @MainActor () -> Void) -> AnyObject? {
        // `canCheckForUpdates` is KVO-compliant and moves on Sparkle's main-queue callbacks:
        // false when a background check or download starts, true when it ends or is shown.
        updater.observe(\.canCheckForUpdates, options: [.new]) { _, _ in
            Task { @MainActor in onChange() }
        }
    }
}

/// **The Sparkle-backed updater, inert until asked** (focus-h8jf).
///
/// ## What "inert" means here, exactly
///
/// `SPUStandardUpdaterController` is built with `startingUpdater: false`. Until `startUpdater()`
/// is called Sparkle schedules nothing, reads no feed and opens no socket; it is a framework in
/// memory. The two verbs on `SoftwareUpdating` are the only two callers of `startUpdater()` in
/// this repository, and both are reached from a control the person operated: the General pane's
/// switch and the manual check in Settings or the app menu. That is the shape the owner's
/// ruling on grants gave (focus-exdi.4), applied to the network: **the app asks for nothing unless the person
/// switched that ask on.**
///
/// ## The feed is the train's
///
/// `feedURLString(for:)` answers with `ReleaseTrain.current.feedURL`, so there is no `SUFeedURL`
/// in the plist and an Alpha build cannot be offered a Stable update or the reverse. The feed
/// URL is https and Sparkle verifies the EdDSA signature on every enclosure against
/// `SUPublicEDKey`, so a substituted feed cannot install unsigned code.
///
/// ## Sparkle's own memory of the switch
///
/// Sparkle mirrors `automaticallyChecksForUpdates` into its `SUEnableAutomaticChecks` default.
/// The store's row is the source of truth: the root reads it at launch and applies it here, so a
/// person who deleted everything, or whose defaults were reset, is back to "off" and not to
/// whatever Sparkle remembered.
@MainActor
public final class SparkleUpdater: NSObject, SoftwareUpdating {
    private let train: ReleaseTrain
    private let makeController: (any SPUUpdaterDelegate) -> any SparkleControlling
    private let reportStartupError: (Error) -> Void
    private let logger = Logger(subsystem: "com.chrismitchelmore.FocusSentinel", category: "updates")
    private var controller: (any SparkleControlling)?
    private var availabilityObservation: AnyObject?
    private var automaticChecks = false
    public private(set) var isStarted = false
    public private(set) var lastFailure: SoftwareUpdateFailure?
    public var onStatusChange: (@MainActor () -> Void)?

    /// - Parameters:
    ///   - train: the feed this build updates from.
    ///   - checksAutomatically: the stored choice. `true` starts the updater at once, because
    ///     that is what the person asked for on an earlier launch; `false` builds it and stops.
    public convenience init(train: ReleaseTrain, checksAutomatically: Bool) {
        self.init(
            train: train,
            checksAutomatically: checksAutomatically,
            makeController: {
                SPUStandardUpdaterController(
                    startingUpdater: false, updaterDelegate: $0, userDriverDelegate: nil
                )
            },
            reportStartupError: { error in
                Task { @MainActor in NSAlert(error: error).runModal() }
            }
        )
    }

    init(
        train: ReleaseTrain,
        checksAutomatically: Bool,
        makeController: @escaping (any SPUUpdaterDelegate) -> any SparkleControlling,
        reportStartupError: @escaping (Error) -> Void
    ) {
        self.train = train
        self.makeController = makeController
        self.reportStartupError = reportStartupError
        super.init()
        if checksAutomatically {
            setAutomaticChecks(true)
        }
    }

    public var canCheckForUpdates: Bool {
        // Before the first start a manual check is possible: `checkForUpdates()` starts it.
        !isStarted || controller?.canCheckForUpdates == true
    }

    public var lastCheckDate: Date? {
        controller?.lastCheckDate
    }

    public func setAutomaticChecks(_ enabled: Bool) {
        automaticChecks = enabled
        if enabled {
            _ = start()
        } else if let controller {
            // Never started: there is nothing to switch off, and starting it in order to say so
            // would be the one thing "off" must not do.
            controller.automaticallyChecksForUpdates = false
        }
        onStatusChange?()
    }

    public func checkForUpdates() {
        guard canCheckForUpdates, start() else { return }
        lastFailure = nil
        controller?.checkForUpdates()
        onStatusChange?()
    }

    /// Build and start the controller, once.
    private func start() -> Bool {
        if isStarted {
            controller?.automaticallyChecksForUpdates = automaticChecks
            return true
        }
        let controller = controller ?? makeController(self)
        self.controller = controller
        if availabilityObservation == nil {
            // Without this the menu only heard about the end of a cycle, never its start.
            availabilityObservation = controller.observeAvailability { [weak self] in
                self?.onStatusChange?()
            }
        }
        // Apply the store's choice BEFORE starting: Sparkle may remember a different choice.
        controller.automaticallyChecksForUpdates = automaticChecks
        do {
            try controller.start()
            isStarted = true
            lastFailure = nil
            return true
        } catch {
            lastFailure = .configuration
            logger.error("the updater could not start: \(error, privacy: .public)")
            onStatusChange?()
            reportStartupError(error)
            return false
        }
    }

    func finishUpdateCheck(error: Error?) {
        lastFailure = error.flatMap(Self.failure)
        if let error, lastFailure != nil {
            logger.error("the update check failed: \(error, privacy: .public)")
        }
        onStatusChange?()
    }

    static func failure(for error: Error) -> SoftwareUpdateFailure? {
        let error = error as NSError
        if error.domain == SUSparkleErrorDomain {
            switch error.code {
            case Int(SUError.noUpdateError.rawValue), Int(SUError.installationCanceledError.rawValue),
                 Int(SUError.installationAuthorizeLaterError.rawValue):
                return nil
            default:
                break
            }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return failure(for: underlying)
        }
        if error.domain == NSURLErrorDomain {
            return .network
        }
        if error.domain == SUSparkleErrorDomain,
           [SUError.downloadError, .appcastError, .appcastParseError].contains(where: {
               Int($0.rawValue) == error.code
           }) {
            return .feedUnavailable
        }
        return .other
    }
}

extension SparkleUpdater: SPUUpdaterDelegate {
    public func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        // Sparkle finishes resetting availability after this delegate returns.
        Task { @MainActor [weak self] in self?.finishUpdateCheck(error: error) }
    }

    /// The train's feed, and never a plist key: an Alpha build asks the Alpha feed.
    public nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        // `train` is a `let` of a `Sendable` value, which Swift lets a nonisolated context read;
        // the delegate is called on Sparkle's own queue and must not hop to the main actor.
        train.feedURL
    }
}
