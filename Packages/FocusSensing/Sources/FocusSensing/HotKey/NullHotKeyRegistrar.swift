import FocusCore
import Foundation

/// The registrar for a build that has no global hot key: it registers nothing and says so.
///
/// This is the same honesty `NullActivityObserver` ships with. It is not a stand-in that
/// pretends to have worked — `availability` reports `.notImplemented`, `register` returns
/// `.refused(reason: .registrarUnavailable)`, and `registeredSpec` stays `nil` — so a caller
/// that forgets to check availability still behaves correctly instead of waiting for a key
/// that will never fire.
///
/// It is also the injectable double for every test and every snapshot render: the capture
/// surfaces can be exercised without taking a real system-wide key away from the machine
/// running the gate.
@MainActor
public final class NullHotKeyRegistrar: HotKeyRegistering {
    /// How many times `register` was called. A test double that records is worth more than one
    /// that merely declines, and it costs a single integer.
    public private(set) var registerCallCount = 0
    /// How many times `unregister` was called.
    public private(set) var unregisterCallCount = 0
    /// The last combination offered, whether or not it could have been registered.
    public private(set) var lastOfferedSpec: HotKeySpec?

    public init() {}

    public nonisolated var availability: HotKeyAvailability {
        .unavailable(reason: .notImplemented)
    }

    /// Always `nil`: nothing is ever registered, and reporting a spec here would be the lie
    /// this type exists to avoid.
    public var registeredSpec: HotKeySpec? { nil }

    @discardableResult
    public func register(
        _ spec: HotKeySpec,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> HotKeyRegistration {
        registerCallCount += 1
        lastOfferedSpec = spec
        return .refused(reason: .registrarUnavailable)
    }

    public func unregister() {
        unregisterCallCount += 1
    }
}
