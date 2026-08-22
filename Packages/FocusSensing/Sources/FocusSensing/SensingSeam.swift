import FocusCore
import Foundation

/// What kind of thing happened.
///
/// Raw values are strings and are persisted as strings (`ActivityEvent.kindRaw`), so
/// reordering this enum can never reinterpret stored history.
public enum ActivityEventKind: String, Sendable, CaseIterable, Codable, Hashable {
    /// The frontmost application changed.
    case frontmostApplicationChanged
    /// The frontmost window's context changed (a different document, tab or origin).
    case contextChanged
    /// The user stopped interacting with the machine.
    case userIdle
    /// The user started interacting again.
    case userActive
    /// The display went to sleep or the screen was locked.
    case displayInactive
}

/// One observation, already normalised.
///
/// `detail` is a short, normalised token set — never a window title verbatim, never a URL
/// with a path or query, never captured content. What is stored is evidence *about* what
/// the user was doing, not a recording of it.
public struct ActivityEventValue: Sendable, Equatable, Hashable, Codable, Identifiable {
    public let id: UUID
    public var at: Date
    public var kind: ActivityEventKind
    /// Bundle identifier of the application involved, when there is one.
    public var bundleIdentifier: String?
    /// A normalised, non-identifying descriptor. `nil` when there is nothing to say.
    public var detail: String?

    public init(
        id: UUID = UUID(),
        at: Date,
        kind: ActivityEventKind,
        bundleIdentifier: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.detail = detail
    }

    /// Stamp an observation from an injected wall clock rather than from `Date()`.
    ///
    /// Observation timestamps end up in the persisted event stream and in every
    /// "how long were you off task" calculation, so they go through
    /// `FocusCore.DateProvider` like every other timestamp in this programme.
    public init(
        id: UUID = UUID(),
        kind: ActivityEventKind,
        bundleIdentifier: String? = nil,
        detail: String? = nil,
        dateProvider: some DateProvider
    ) {
        self.init(
            id: id,
            at: dateProvider.now,
            kind: kind,
            bundleIdentifier: bundleIdentifier,
            detail: detail
        )
    }
}

/// Whether an observation source can actually do its job right now.
///
/// macOS observation is permission-shaped: the same code is fully functional, partly
/// functional or inert depending on what the user has granted. Making that a value the app
/// can read — rather than a thrown error at the first call — is what lets the shell degrade
/// gracefully and say so, which is the behaviour the verification doctrine requires.
public enum ObservationAvailability: Sendable, Equatable, Hashable {
    /// The source is running and producing events.
    case available
    /// The source cannot run and says why, in a form the UI can explain to the user.
    case unavailable(reason: UnavailabilityReason)

    public enum UnavailabilityReason: String, Sendable, CaseIterable, Codable, Hashable {
        /// The user has not granted the permission this source needs.
        case permissionNotGranted
        /// No implementation is wired up in this build.
        case notImplemented
        /// The machine does not offer the facility at all.
        case unsupportedOnThisMac
    }

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// The observation seam.
///
/// e03 implements this over `NSWorkspace` notifications and the Accessibility API. Nothing
/// above the seam learns which mechanism produced an event.
public protocol ActivityObserving: Sendable {
    /// Whether this source can currently produce events, and why not if it cannot.
    var availability: ObservationAvailability { get }
    /// The stream of observations. A source that is unavailable finishes the stream
    /// immediately rather than hanging or throwing.
    func events() -> AsyncStream<ActivityEventValue>
}

/// Reads whether the user is present. Split from `ActivityObserving` because idleness is
/// available without any TCC grant while window context is not, and the app must be able
/// to use one without the other.
public protocol IdleObserving: Sendable {
    var availability: ObservationAvailability { get }
    /// How long the user has been idle, measured from an injected clock in tests.
    func idleDuration() -> Duration
}

/// The observer e01 ships: it observes nothing and says so.
///
/// This is the honest source for a build that has no sensing adapters yet. It is not a
/// stand-in that pretends to work — `availability` reports `.notImplemented`, and the
/// event stream finishes immediately, so a consumer that forgets to check availability
/// still behaves correctly instead of waiting forever.
public struct NullActivityObserver: ActivityObserving, IdleObserving {
    public init() {}

    public var availability: ObservationAvailability {
        .unavailable(reason: .notImplemented)
    }

    public func events() -> AsyncStream<ActivityEventValue> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func idleDuration() -> Duration {
        .zero
    }
}
