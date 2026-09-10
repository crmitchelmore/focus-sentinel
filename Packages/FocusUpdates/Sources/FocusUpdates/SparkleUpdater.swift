import AppKit
import FocusCore
import Sparkle

/// **The Sparkle-backed updater, inert until asked** (focus-h8jf).
///
/// ## What "inert" means here, exactly
///
/// `SPUStandardUpdaterController` is built with `startingUpdater: false`. Until `startUpdater()`
/// is called Sparkle schedules nothing, reads no feed and opens no socket; it is a framework in
/// memory. The two verbs on `SoftwareUpdating` are the only two callers of `startUpdater()` in
/// this repository, and both are reached from a control the person operated: the General pane's
/// switch and its *Check for updates now* button. That is the shape the owner's ruling on grants
/// gave (focus-exdi.4), applied to the network: **the app asks for nothing unless the person
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
    private var controller: SPUStandardUpdaterController?
    public private(set) var isStarted = false

    /// - Parameters:
    ///   - train: the feed this build updates from.
    ///   - checksAutomatically: the stored choice. `true` starts the updater at once, because
    ///     that is what the person asked for on an earlier launch; `false` builds it and stops.
    public init(train: ReleaseTrain, checksAutomatically: Bool) {
        self.train = train
        super.init()
        if checksAutomatically {
            setAutomaticChecks(true)
        }
    }

    public var canCheckForUpdates: Bool {
        // Before the first start a manual check is possible: `checkForUpdates()` starts it.
        controller?.updater.canCheckForUpdates ?? true
    }

    public var lastCheckDate: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    public func setAutomaticChecks(_ enabled: Bool) {
        if enabled {
            start()
            controller?.updater.automaticallyChecksForUpdates = true
        } else if let controller {
            // Never started: there is nothing to switch off, and starting it in order to say so
            // would be the one thing "off" must not do.
            controller.updater.automaticallyChecksForUpdates = false
        }
    }

    public func checkForUpdates() {
        start()
        controller?.checkForUpdates(nil)
    }

    /// Build and start the controller, once.
    private func start() {
        guard !isStarted else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller
        controller.startUpdater()
        isStarted = true
    }
}

extension SparkleUpdater: SPUUpdaterDelegate {
    /// The train's feed, and never a plist key: an Alpha build asks the Alpha feed.
    public nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        // `train` is a `let` of a `Sendable` value, which Swift lets a nonisolated context read;
        // the delegate is called on Sparkle's own queue and must not hop to the main actor.
        train.feedURL
    }
}
