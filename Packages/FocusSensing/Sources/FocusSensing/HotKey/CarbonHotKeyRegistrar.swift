import Carbon.HIToolbox
import FocusCore
import Foundation

// The one file in this repository permitted to import Carbon, and the reason the SC-2 lint
// was narrowed rather than waived (plan R-13). `scripts/check-forbidden.sh` fails if
// `Carbon.HIToolbox` appears in any other file **and** fails if it stops appearing in this
// one, so the exemption cannot outlive the reason it was granted.
//
// ## Why Carbon at all, in 2026
//
// The Feasibility Court chose `RegisterEventHotKey` for the quick-capture shortcut (F-06)
// because it is public, documented, and needs **no TCC grant**. The alternative,
// `NSEvent.addGlobalMonitorForEvents`, buys an Accessibility prompt for no gain. That claim
// was measured, not assumed (probe P-56): with `tccutil reset Accessibility` run first and the
// app launched by `open -a` so it is its own responsible process, `AXIsProcessTrusted()`
// reported **false** and the hot key still fired while Finder was frontmost.
//
// ## What the API will and will not tell you (probe P-55)
//
// * Installing the handler and registering ⌥⌘J both returned `noErr`.
// * Registering the **same** combination a second time returned `-9878`
//   (`eventHotKeyExistsErr`) with a `nil` ref — so a self-collision is detectable.
// * Registering **⌘Space** — Spotlight's — also returned `noErr`, and our handler received the
//   key. A system collision is therefore *not* reported at all: the app simply wins, silently.
//   That is why the refusal list lives in `HotKeySpec` and is consulted before this file ever
//   calls the API, and why the settings tab offers a live "press it to test it" row instead of
//   trusting a return code.
// * `UnregisterEventHotKey` returned `0`, and re-registering the freed combination returned
//   `0` — which is what makes "changing the shortcut" one safe call rather than a leak.

/// The Carbon tokens, in a box that is safe to touch from anywhere.
///
/// Two things force this shape. A C event handler is a bare function pointer that cannot
/// capture context, so the receiver has to travel through `userData` as an opaque pointer.
/// And `deinit` on a `@MainActor` class is *not* main-actor isolated, so the teardown path
/// cannot reach isolated state — it can only reach something like this, which carries its own
/// lock and is `Sendable` in its own right.
private final class HotKeyTokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (@Sendable () -> Void)?

    func setAction(_ action: (@Sendable () -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        self.action = action
    }

    /// Called from the C callback, on whatever thread the toolbox dispatched it on — which is
    /// the main thread in practice, and the action itself re-enters the main actor either way.
    func fire() {
        lock.lock()
        let action = self.action
        lock.unlock()
        action?()
    }

    /// Install the application-level handler once. Repeated calls are no-ops that report
    /// `noErr`, so `register` does not have to remember whether it has been here before.
    func installHandlerIfNeeded(_ callback: EventHandlerUPP) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        if handlerRef != nil { return noErr }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installed: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &installed
        )
        if status == noErr { handlerRef = installed }
        return status
    }

    func setHotKeyRef(_ ref: EventHotKeyRef?) {
        lock.lock()
        defer { lock.unlock() }
        hotKeyRef = ref
    }

    /// Release the hot key, keeping the installed handler. Reports the toolbox status, or
    /// `noErr` when there was nothing to release.
    @discardableResult
    func unregisterHotKey() -> OSStatus {
        lock.lock()
        let ref = hotKeyRef
        hotKeyRef = nil
        lock.unlock()
        guard let ref else { return noErr }
        return UnregisterEventHotKey(ref)
    }

    /// Release everything. The `deinit` path.
    func tearDown() {
        unregisterHotKey()
        lock.lock()
        let handler = handlerRef
        handlerRef = nil
        action = nil
        lock.unlock()
        if let handler { RemoveEventHandler(handler) }
    }
}

/// The Carbon event callback.
///
/// A `@convention(c)` function has no captured context, so the box travels through `userData`.
/// The hot-key id is checked before firing: the handler is installed on the *application*
/// event target, so it would otherwise also see hot keys registered by any framework linked
/// into this process.
private func focusHotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    guard hotKeyID.signature == CarbonHotKeyRegistrar.hotKeySignature,
          hotKeyID.id == CarbonHotKeyRegistrar.hotKeyIdentifier
    else { return OSStatus(eventNotHandledErr) }

    Unmanaged<HotKeyTokenBox>.fromOpaque(userData).takeUnretainedValue().fire()
    return noErr
}

/// The grant-free global hot key (F-06).
///
/// One registration at a time. `register` releases whatever this registrar already held before
/// offering the new combination, so changing the shortcut cannot leave two live; `deinit`
/// releases the last one through the token box.
@MainActor
public final class CarbonHotKeyRegistrar: HotKeyRegistering {
    /// `'FCSN'` — Focus Sentinel. The signature scopes our hot-key ids away from every other
    /// framework's inside this process.
    nonisolated static let hotKeySignature: OSType = 0x4643_534E
    /// One hot key exists at a time, so one identifier is enough.
    nonisolated static let hotKeyIdentifier: UInt32 = 1

    private nonisolated let tokens = HotKeyTokenBox()

    public private(set) var registeredSpec: HotKeySpec?

    public init() {}

    deinit {
        // Not main-actor isolated, by language rule. The box is what makes it safe.
        tokens.tearDown()
    }

    public nonisolated var availability: HotKeyAvailability { .available }

    @discardableResult
    public func register(
        _ spec: HotKeySpec,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> HotKeyRegistration {
        // The refusal list is consulted **before** the API, because the API will not refuse
        // for us: P-55 measured ⌘Space registering successfully and stealing Spotlight's key.
        if let refusal = spec.refusal {
            return .refused(reason: refusal)
        }
        guard let keyCode = UInt32(exactly: spec.keyCode) else {
            return .refused(reason: .unsupportedKeyCode)
        }

        // One at a time: release our own registration first. Measured safe (P-55).
        unregister()

        tokens.setAction {
            // The toolbox dispatches this on the main thread; `assumeIsolated` is the cheap,
            // correct path when it does, and the `Task` is the honest fallback if it ever
            // does not, rather than an unchecked assumption that would crash at 3 a.m.
            if Thread.isMainThread {
                MainActor.assumeIsolated { handler() }
            } else {
                Task { @MainActor in handler() }
            }
        }

        let installStatus = tokens.installHandlerIfNeeded(focusHotKeyEventHandler)
        guard installStatus == noErr else {
            tokens.setAction(nil)
            return .failed(status: installStatus)
        }

        var ref: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyIdentifier)
        let status = RegisterEventHotKey(
            keyCode,
            Self.carbonModifierMask(for: spec.modifiers),
            identifier,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        switch status {
        case noErr:
            guard let ref else { return .failed(status: status) }
            tokens.setHotKeyRef(ref)
            registeredSpec = spec
            return .registered
        case OSStatus(eventHotKeyExistsErr):
            tokens.setAction(nil)
            return .alreadyRegistered
        default:
            tokens.setAction(nil)
            return .failed(status: status)
        }
    }

    public func unregister() {
        tokens.unregisterHotKey()
        tokens.setAction(nil)
        registeredSpec = nil
    }

    /// Translate `NSEvent.ModifierFlags` raw values into the Carbon mask.
    ///
    /// `FocusCore` stores the AppKit numbering because that is what a shortcut recorder and
    /// the settings row speak; these four constants are the only place the two vocabularies
    /// meet.
    static func carbonModifierMask(for modifiers: HotKeyModifiers) -> UInt32 {
        var mask: UInt32 = 0
        let significant = modifiers.significant
        if significant.contains(.command) { mask |= UInt32(cmdKey) }
        if significant.contains(.option) { mask |= UInt32(optionKey) }
        if significant.contains(.control) { mask |= UInt32(controlKey) }
        if significant.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }
}
