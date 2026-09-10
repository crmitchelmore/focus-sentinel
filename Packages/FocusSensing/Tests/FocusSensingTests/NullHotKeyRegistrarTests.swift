import FocusCore
import Foundation
import Testing

@testable import FocusSensing

@MainActor
@Suite("The null hot-key registrar")
struct NullHotKeyRegistrarTests {
    @Test("it reports itself unavailable rather than throwing or pretending")
    func reportsUnavailable() {
        let registrar = NullHotKeyRegistrar()
        #expect(registrar.availability == .unavailable(reason: .notImplemented))
        #expect(!registrar.availability.isAvailable)
        #expect(registrar.registeredSpec == nil)
    }

    @Test("registering is a no-op that returns a typed refusal, not a silent success")
    func registeringIsATypedNoOp() {
        let registrar = NullHotKeyRegistrar()
        let result = registrar.register(.quickCaptureDefault) {}
        #expect(result == .refused(reason: .registrarUnavailable))
        #expect(!result.isRegistered)
        #expect(registrar.registeredSpec == nil)
        #expect(registrar.registerCallCount == 1)
        #expect(registrar.lastOfferedSpec == .quickCaptureDefault)
    }

    /// The handler must never fire. A null registrar that invoked its handler once "so the UI
    /// has something to show" would make the capture panel appear out of nowhere in a build
    /// with no hot key at all.
    @Test("the handler is never called")
    func theHandlerIsNeverCalled() {
        let registrar = NullHotKeyRegistrar()
        let fired = Fired()
        registrar.register(.quickCaptureDefault) { fired.count += 1 }
        registrar.register(HotKeySpec(keyCode: 12, modifiers: [.option, .command])) {
            fired.count += 1
        }
        #expect(fired.count == 0)
        #expect(registrar.registerCallCount == 2)
    }

    @Test("a refused combination is still recorded as offered, so the UI can explain it")
    func refusedCombinationsAreRecorded() {
        let registrar = NullHotKeyRegistrar()
        let spotlight = HotKeySpec(keyCode: VirtualKey.space, modifiers: .command)
        let result = registrar.register(spotlight) {}
        // The null registrar declines before it ever looks at the spec — being unavailable is
        // the more fundamental fact — but it still records what was asked for.
        #expect(result == .refused(reason: .registrarUnavailable))
        #expect(registrar.lastOfferedSpec == spotlight)
        #expect(spotlight.refusal == .systemReserved(function: .spotlight))
    }

    @Test("unregistering is safe when nothing was ever registered")
    func unregisteringIsSafe() {
        let registrar = NullHotKeyRegistrar()
        registrar.unregister()
        registrar.unregister()
        #expect(registrar.unregisterCallCount == 2)
        #expect(registrar.registeredSpec == nil)
    }

    /// It is what the composition root and every snapshot render wire in, so it has to satisfy
    /// the seam rather than merely resemble it.
    @Test("it satisfies the FocusCore seam")
    func satisfiesTheSeam() {
        let registrar: any HotKeyRegistering = NullHotKeyRegistrar()
        #expect(registrar.availability.isAvailable == false)
        #expect(registrar.register(.quickCaptureDefault) {} == .refused(reason: .registrarUnavailable))
    }
}

/// A main-actor counter the test handlers can close over.
@MainActor
private final class Fired {
    var count = 0
}
