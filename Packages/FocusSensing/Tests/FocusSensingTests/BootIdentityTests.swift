import FocusCore
import Foundation
import Testing

@testable import FocusSensing

@Suite("Boot identity")
struct BootIdentityTests {
    @Test("It is non-empty on this machine")
    func currentIsNonEmpty() {
        #expect(BootIdentity.current().isEmpty == false)
    }

    @Test("Two reads in one process are identical")
    func stableAcrossTwoReads() {
        // `kern.boottime` read byte-identically across two separate *processes* two seconds
        // apart on the rig (probe P-106); within one process it cannot move at all, and an
        // identity that did would discard a live session's anchor on every read.
        #expect(BootIdentity.current() == BootIdentity.current())
    }

    @Test("It parses into a boot instant, and the instant is in the past")
    func parsesIntoAPlausibleInstant() {
        let raw = BootIdentity.current()
        guard let parsed = BootIdentity.parse(raw) else {
            Issue.record("the identity this machine reports does not parse: \(raw)")
            return
        }

        #expect(parsed.seconds > 0)
        #expect(parsed.microseconds >= 0)

        // The Mac booted before now, and after the release of the operating system it is
        // running. 2020-01-01 is the loose lower bound; the upper one is simply "not the
        // future", read through the same wall clock every other timestamp uses.
        let boot = Date(timeIntervalSince1970: TimeInterval(parsed.seconds))
        #expect(boot > Date(timeIntervalSince1970: 1_577_836_800))
        #expect(boot < SystemDateProvider().now)
    }

    @Test("A value this build cannot interpret parses to nothing")
    func malformedIdentitiesDoNotParse() {
        #expect(BootIdentity.parse(nil) == nil)
        #expect(BootIdentity.parse("") == nil)
        #expect(BootIdentity.parse("1786742847") == nil)
        #expect(BootIdentity.parse("not.anumber") == nil)
        #expect(BootIdentity.parse("1786742847.869178.1") == nil)
    }

    @Test("It carries both halves, so two boots a fraction apart are still distinguishable")
    func carriesSecondsAndMicroseconds() {
        let parsed = BootIdentity.parse("1786742847.869178")
        #expect(parsed?.seconds == 1_786_742_847)
        #expect(parsed?.microseconds == 869_178)
    }

    @Test("An empty identity matches nothing, including another empty one")
    func emptyIdentityNeverMatches() {
        // The failure mode this exists to prevent: a failed sysctl on both sides comparing
        // equal, and a dead anchor from another boot being treated as usable.
        #expect(BootIdentity.isSameBoot("", as: "") == false)
        #expect(BootIdentity.isSameBoot(nil, as: BootIdentity.current()) == false)
        #expect(BootIdentity.isSameBoot("1786742847.869178", as: "") == false)
    }

    @Test("Matching identities are the same boot and differing ones are not")
    func matchingIdentitiesAreTheSameBoot() {
        let current = BootIdentity.current()
        #expect(BootIdentity.isSameBoot(current, as: current))
        #expect(BootIdentity.isSameBoot("1.0", as: current) == false)
    }

    @Test("The reconciler treats a differing identity as a restart, and computes no drift")
    func aDifferentIdentityDiscardsTheAnchor() {
        // The end-to-end shape this type exists for, asserted against the pure reconciler with
        // the identity this machine actually reports on one side of it.
        let started = Date(timeIntervalSince1970: 1_767_225_600)
        let record = SessionRestoration.StoredSession(
            sessionID: UUID(),
            startedAt: started,
            phase: .focus,
            phaseChangedAt: started,
            uptimeAnchorSeconds: 741_532.264,
            bootIdentity: "1.0"
        )

        let restored = SessionRestoration.reconcile(
            record: record,
            now: started.addingTimeInterval(60),
            nowUptimeSeconds: 12,
            bootIdentity: BootIdentity.current()
        )

        #expect(restored.notes.contains(.rebootedDuringSession))
        #expect(restored.notes.contains(.clockAnomaly) == false)
        #expect(restored.driftSeconds == nil)
        #expect(restored.pauseCauses == [.systemRestart])
    }
}

/// The third of T64's platform adapters, tested beside the other two because they are one
/// unit: the probe answers for the whole platform, and two of its twelve answers are the boot
/// identity's and the uptime clock's neighbours in `FocusSensing/Platform`.
@MainActor
@Suite("Platform capability probe")
struct PlatformCapabilityProbeTests {
    private static let instant = Date(timeIntervalSince1970: 1_767_225_600)

    /// A probe answering from fixtures, so the states this rig cannot produce are still
    /// exercised — which is the whole of F-155's permission-absent matrix.
    private static func fixtureProbe(
        windows: [[String: Any]] = WindowCorpus.standard,
        screens: [DisplayGeometry] = [
            DisplayGeometry(
                displayID: 3, screenIndex: 0, isPrimary: true,
                frame: WindowCorpus.primaryFrame,
                visibleFrame: WindowCorpus.primaryFrame,
                backingScaleFactor: 1
            )
        ],
        idle: any IdleSourceReading = FixedIdleSource(hardwareSeconds: 10, sessionSeconds: 5),
        audio: [AudioDeviceSnapshot] = [ScriptedAudioDevices.microphone],
        cameras: [CameraDeviceIdentifier] = []
    ) -> PlatformCapabilityProbe {
        PlatformCapabilityProbe(
            windowList: RecordedWindowList(rows: windows),
            screens: FixedScreenList(screens),
            idleSource: idle,
            audio: ScriptedAudioDevices(devices: audio),
            camera: CMIOMediaObserver(
                enumerator: ScriptedCameraDevices(identifiers: cameras),
                environment: [:]
            )
        )
    }

    @Test("It answers for all thirteen capabilities, once each")
    func answersForEveryCapability() {
        let states = Self.fixtureProbe().states()

        #expect(states.count == Capability.allCases.count)
        #expect(Set(states.map(\.0)) == Set(Capability.allCases))
    }

    @Test("On a working machine the seven capabilities this epic uses are available")
    func theSevenUsedCapabilitiesAreAvailable() {
        let matrix = Self.fixtureProbe().probeOnMainActor(at: Self.instant)

        for capability in CapabilityMatrix.capabilitiesUsedInThisEpic {
            #expect(matrix.state(of: capability) == .available)
        }
    }

    @Test("No capability this epic uses is left .notRequested")
    func nothingThisEpicUsesIsUnprobed() {
        let matrix = Self.fixtureProbe().probeOnMainActor(at: Self.instant)

        for capability in CapabilityMatrix.capabilitiesUsedInThisEpic {
            #expect(matrix.state(of: capability) != .notRequested)
        }
    }

    @Test("The camera is unavailable even with two devices enumerated, and is never denied")
    func theCameraIsPinnedUnavailable() {
        let probe = Self.fixtureProbe(cameras: [11, 12])
        let matrix = probe.probeOnMainActor(at: Self.instant)

        #expect(matrix.state(of: .cameraActivity) == .unavailable)
        #expect(matrix.state(of: .cameraActivity) != .denied)
        #expect(probe.cameraUnavailableReason == .unprovenOnThisHardware)
        #expect(probe.cameraDeviceCount == 2)
        #expect(probe.cameraListenersInstalled == 0)
    }

    @Test("With no camera the reason is the hardware fact rather than the hold")
    func noCameraIsAHardwareFact() {
        let probe = Self.fixtureProbe(cameras: [])
        _ = probe.probeOnMainActor(at: Self.instant)

        #expect(probe.cameraUnavailableReason == .noDevices)
        #expect(probe.cameraListenersInstalled == 0)
    }

    @Test("Zero audio input devices reports unavailable rather than available")
    func noInputDeviceIsUnavailable() {
        let probe = Self.fixtureProbe(audio: [ScriptedAudioDevices.headphones])
        let matrix = probe.probeOnMainActor(at: Self.instant)

        #expect(matrix.state(of: .microphoneActivity) == .unavailable)
    }

    @Test("No display means display geometry is unavailable, not a guessed primary")
    func noDisplayIsUnavailable() {
        let matrix = Self.fixtureProbe(screens: []).probeOnMainActor(at: Self.instant)

        #expect(matrix.state(of: .displayGeometry) == .unavailable)
    }

    @Test("A window list that answers nothing makes window metadata and presentation unavailable")
    func noWindowsIsUnavailable() {
        let matrix = Self.fixtureProbe(windows: []).probeOnMainActor(at: Self.instant)

        #expect(matrix.state(of: .windowMetadata) == .unavailable)
        #expect(matrix.state(of: .presentation) == .unavailable)
    }

    @Test("The four capabilities later epics own report the literal truth")
    func laterEpicsAreNotRequestedOrParked() {
        let matrix = Self.fixtureProbe().probeOnMainActor(at: Self.instant)

        // Nobody asked, so nobody was refused. Reporting `.denied` here would invent one.
        #expect(matrix.state(of: .accessibilityWindowContext) == .notRequested)
        #expect(matrix.state(of: .notifications) == .notRequested)
        #expect(matrix.state(of: .onDeviceModel) == .notRequested)
        // Parked by the Court, so there is nothing to probe because there is nothing to use.
        #expect(matrix.state(of: .screenCapture) == .unavailable)
    }

    @Test("On a fully working rig the probe matches the recorded zero-grant expectation")
    func matchesTheZeroGrantExpectation() {
        let matrix = Self.fixtureProbe().probeOnMainActor(at: Self.instant)
        let expected = CapabilityMatrix.zeroGrantExpectation(at: Self.instant)

        for capability in Capability.allCases {
            #expect(matrix.state(of: capability) == expected.state(of: capability))
        }
    }

    @Test("The live probe on this machine reports the same shape")
    func theLiveProbeAgrees() {
        // Not a fixture: the real readers, on this Mac, at zero grants. The camera is the one
        // answer that is a decision rather than a measurement, and it is asserted by name.
        let matrix = PlatformCapabilityProbe().probeOnMainActor(at: Self.instant)

        #expect(matrix.state(of: .frontmostApplication) == .available)
        #expect(matrix.state(of: .idle) == .available)
        #expect(matrix.state(of: .systemLifecycle) == .available)
        #expect(matrix.state(of: .cameraActivity) == .unavailable)
        #expect(matrix.state(of: .screenCapture) == .unavailable)
        #expect(matrix.allStates.count == Capability.allCases.count)
    }
}
