import Foundation

/// Whether a hot-key registrar can actually register anything in this build.
///
/// The shape mirrors `FocusSensing.ObservationAvailability` deliberately: a source that
/// cannot do its job says so as a value the UI can render, rather than throwing at the first
/// call. The capture settings tab uses this to decide whether the "press your shortcut to
/// test it" row is live or explained away.
public enum HotKeyAvailability: Sendable, Equatable, Hashable {
    case available
    case unavailable(reason: Reason)

    public enum Reason: String, Sendable, CaseIterable, Codable, Hashable {
        /// No registrar is wired up — the null implementation.
        case notImplemented
        /// The machine or the build cannot offer global hot keys at all.
        case unsupportedOnThisMac
    }

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// What happened when a shortcut was offered to the platform.
///
/// Four outcomes, each measured (P-55):
///
/// * `.registered` — `RegisterEventHotKey` returned `noErr` and the combination is live.
/// * `.alreadyRegistered` — status `-9878` (`eventHotKeyExistsErr`), which is what the API
///   returns when the combination is already held. It is recoverable: unregister the holder
///   and try again.
/// * `.refused(reason:)` — the app turned it down itself, before calling the API, and can say
///   why. This is the only outcome that exists for a *system* collision, because the API does
///   not report one: registering ⌘Space returned `noErr` and quietly took the key away from
///   Spotlight.
/// * `.failed(status:)` — anything else the toolbox reported, carried verbatim so a bug
///   report can name the number instead of describing a mood.
public enum HotKeyRegistration: Sendable, Equatable, Hashable {
    case registered
    case alreadyRegistered
    case refused(reason: HotKeyRefusal)
    case failed(status: Int32)

    public var isRegistered: Bool {
        if case .registered = self { return true }
        return false
    }
}

/// The global hot-key seam.
///
/// It is declared in `FocusCore` — not in `FocusSensing`, where the Carbon implementation
/// lives — so that `FocusUI` and the app target can talk about hot keys without importing the
/// package that imports Carbon. `FocusUI` may not import `FocusSensing` at all (R-14), and a
/// settings tab that has to describe a shortcut needs this vocabulary.
///
/// It is `@MainActor` because the handler ends up showing a window: the capture panel is
/// shown from the callback, and a panel that appears on a background thread is a crash
/// waiting for a busy afternoon.
@MainActor
public protocol HotKeyRegistering: AnyObject {
    /// Whether this registrar can register anything at all.
    var availability: HotKeyAvailability { get }

    /// The combination currently held, or `nil` when nothing is registered.
    var registeredSpec: HotKeySpec? { get }

    /// Offer a combination to the platform.
    ///
    /// A registrar releases its own previous registration first, so changing the shortcut is
    /// one call and never leaves two live (P-55 measured unregister → re-register returning
    /// `noErr`). `.alreadyRegistered` therefore means somebody *else* holds it.
    ///
    /// The handler is called on the main actor every time the combination fires. It is
    /// `@Sendable` as well as `@MainActor` because the Carbon implementation hands it across
    /// a C callback boundary; being isolated to the main actor is what makes that safe, and
    /// spelling both out is what lets the compiler check it rather than the reviewer.
    @discardableResult
    func register(_ spec: HotKeySpec, handler: @escaping @MainActor @Sendable () -> Void)
        -> HotKeyRegistration

    /// Release the current registration. Safe to call when nothing is registered.
    func unregister()
}
