import Foundation

/// **What the General pane draws about software updates**, as one value (focus-h8jf).
///
/// Carried on the settings connection rather than read by the pane, like everything else the
/// pane draws: `FocusUI` renders values and never learns which updater produced them.
///
/// `checksAutomatically` is the person's stored choice, read from the store every time the
/// connection is built — never a switch remembering its own answer. `canCheckNow` is the
/// updater's own reading, and `false` only while a check is already running.
public struct SoftwareUpdateStatus: Sendable, Equatable, Hashable {
    /// The train this build updates from. Drawn so an Alpha build says it is one.
    public var train: ReleaseTrain
    /// Whether the person switched automatic checks on. Off on every store the app has never
    /// been told otherwise about: no row is the shipped state.
    public var checksAutomatically: Bool
    /// Whether a manual check can be taken right now.
    public var canCheckNow: Bool
    /// When the updater last asked the feed, or `nil` if it never has.
    public var lastCheckAt: Date?

    public init(
        train: ReleaseTrain = .stable,
        checksAutomatically: Bool = false,
        canCheckNow: Bool = true,
        lastCheckAt: Date? = nil
    ) {
        self.train = train
        self.checksAutomatically = checksAutomatically
        self.canCheckNow = canCheckNow
        self.lastCheckAt = lastCheckAt
    }

    /// The shipped state: Stable, checks off, a manual check available, never asked.
    public static let off = SoftwareUpdateStatus()
}

/// **The updater, as something the composition root can be handed** (focus-h8jf).
///
/// A protocol for `LoginItemControlling`'s reason: the shipping implementation opens a socket
/// when it is started, and no test and no gate stage may start one. `FocusUpdates` ships the
/// Sparkle-backed implementation; every test holds a double that records what it was asked.
///
/// The contract that matters is in the two verbs: **nothing is started until one of them is
/// called.** An updater that is never asked to check automatically and never asked to check now
/// never connects to anything, which is what lets the Privacy pane say so.
@MainActor
public protocol SoftwareUpdating: AnyObject {
    /// Whether the updater has been started at all. `false` until the first verb.
    var isStarted: Bool { get }
    /// Whether a manual check can be taken right now.
    var canCheckForUpdates: Bool { get }
    /// When the feed was last asked, or `nil`.
    var lastCheckDate: Date? { get }
    /// Turn automatic checks on or off. On starts the updater if it is not started.
    func setAutomaticChecks(_ enabled: Bool)
    /// A person-initiated check. Starts the updater if it is not started.
    func checkForUpdates()
}

/// **The updater that never starts**, for a process with no store of its own or no train to
/// update from. The unit lane's default, and what `AppComposition` holds when handed nothing.
@MainActor
public final class NoSoftwareUpdater: SoftwareUpdating {
    public private(set) var isStarted = false
    public var canCheckForUpdates: Bool { false }
    public var lastCheckDate: Date? { nil }
    /// How many times either verb was called, so a test can prove the root never called one.
    public private(set) var requests = 0

    public init() {}

    public func setAutomaticChecks(_ enabled: Bool) {
        requests += 1
    }

    public func checkForUpdates() {
        requests += 1
    }
}
