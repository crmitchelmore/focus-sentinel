import CoreGraphics
import FocusCore
import Foundation

/// The two idle counters macOS offers, behind a seam.
///
/// Both are read on **every** sample. The seam exists because the difference between them is
/// the whole of R-36 and has to be exercised at figures this machine cannot be made to produce
/// on demand: probe P-85 caught a 21-minute disagreement once, and a test may not wait
/// twenty-one minutes for it.
public protocol IdleSourceReading: Sendable {
    /// `.hidSystemState` — **hardware input only**. The primary.
    var hardwareSeconds: Double { get }
    /// `.combinedSessionState` — hardware *and* synthetic posted events. Recorded, never
    /// decisive.
    var sessionSeconds: Double { get }
}

/// The production idle source: `CGEventSource.secondsSinceLastEventType`.
///
/// Grant-free, measured: both states returned seconds with no prompt and no error from a
/// bundle holding no TCC row, and the value advanced by exactly the elapsed time across a
/// 600 ms sleep with no input — a live counter, not a cached one (probe P-84).
public struct CGEventIdleSource: IdleSourceReading {
    public init() {}

    public var hardwareSeconds: Double {
        Self.seconds(since: .hidSystemState)
    }

    public var sessionSeconds: Double {
        Self.seconds(since: .combinedSessionState)
    }

    /// `kCGAnyInputEventType`, the sentinel that means "any input at all" — `0xFFFFFFFF`.
    ///
    /// Swift imports `CGEventType` with a failable initialiser and does not surface the C
    /// sentinel as a case, so the raw value is written out here once, with its name, rather
    /// than at four call sites. `.null` is the fallback purely to keep the expression total;
    /// the initialiser does not fail for this value on any Mac this app runs on.
    static let anyInputEventType: CGEventType = CGEventType(rawValue: ~UInt32(0)) ?? .null

    private static func seconds(since state: CGEventSourceStateID) -> Double {
        CGEventSource.secondsSinceLastEventType(state, eventType: anyInputEventType)
    }
}

/// An idle source pinned at figures a test chose.
public struct FixedIdleSource: IdleSourceReading {
    public let hardwareSeconds: Double
    public let sessionSeconds: Double

    public init(hardwareSeconds: Double, sessionSeconds: Double) {
        self.hardwareSeconds = hardwareSeconds
        self.sessionSeconds = sessionSeconds
    }
}

/// Whether the person is at the keyboard — read from the **hardware** counter, with the other
/// one recorded beside it.
///
/// ## Why the hardware source is the primary
///
/// Measured on this machine at one instant (probe P-85): `.combinedSessionState` read **267 s**
/// while `.hidSystemState` read **1536 s**. The combined counter includes synthetic posted
/// events, so a daemon, an automation tool or a Screen Sharing session keeps it small while the
/// human is demonstrably absent.
///
/// Because combined counts a strict superset of events, `combined ≤ hid` **always**, which
/// makes the hardware source the strictly more pessimistic one — it declares the user idle
/// sooner. That asymmetry is the argument: idle **suppresses** intervention, so calling a
/// present user idle costs a nudge that would have been welcome, while calling an absent user
/// present nudges an empty chair, which is the exact failure idle detection exists to prevent.
///
/// ## The limitation, stated rather than hidden
///
/// A person working over Screen Sharing produces only synthetic events and will be treated as
/// idle. That goes in the Settings copy, not in a comment nobody reads.
///
/// ## Transitions, once each
///
/// A sample reports a transition **only on the sample that flips it**, so the caller writes one
/// `userIdle`, one `userActive` and one `syntheticInputObserved` row per change rather than one
/// per tick. There is no idle timer: the sample is taken on the corroboration tick, which is
/// the only periodic thing in this epic.
@MainActor
public final class IdleReader: IdleObserving {
    /// What one reading found, and what changed since the last one.
    public struct Sample: Sendable, Equatable, Hashable {
        public let reading: IdleReading
        public let isIdle: Bool
        /// Non-`nil` **only** on the sample where presence flipped.
        public let idleTransition: IdleTransition?
        /// Non-`nil` **only** on the sample where the synthetic-input suspicion flipped.
        public let syntheticInputTransition: SyntheticInputTransition?

        public init(
            reading: IdleReading,
            isIdle: Bool,
            idleTransition: IdleTransition? = nil,
            syntheticInputTransition: SyntheticInputTransition? = nil
        ) {
            self.reading = reading
            self.isIdle = isIdle
            self.idleTransition = idleTransition
            self.syntheticInputTransition = syntheticInputTransition
        }
    }

    public enum IdleTransition: String, Sendable, CaseIterable, Hashable {
        case becameIdle
        case becameActive
    }

    public enum SyntheticInputTransition: String, Sendable, CaseIterable, Hashable {
        case began
        case ended
    }

    private let source: any IdleSourceReading

    /// Seconds of no hardware input above which the person is treated as away.
    ///
    /// `AppSettingsRecord.idleThresholdSeconds`, default 180, injected everywhere. Settable
    /// because the person can change it in Settings while the app is running.
    public var thresholdSeconds: Double

    /// How far the two counters may disagree before synthetic input is suspected.
    ///
    /// The same five seconds the reconciler uses for clock drift, and for a related reason:
    /// two figures produced by different mechanisms never agree exactly, and zero is not a
    /// tolerance.
    public var syntheticToleranceSeconds: Double

    private var wasIdle = false
    private var wasSyntheticSuspected = false

    public init(
        source: any IdleSourceReading = CGEventIdleSource(),
        thresholdSeconds: Double = Double(FocusSchemaV3.defaultIdleThresholdSeconds),
        syntheticToleranceSeconds: Double = 5
    ) {
        self.source = source
        self.thresholdSeconds = thresholdSeconds
        self.syntheticToleranceSeconds = syntheticToleranceSeconds
    }

    /// Read both counters and report what changed.
    public func sample() -> Sample {
        let reading = read()
        let isIdle = reading.isIdle(threshold: thresholdSeconds)
        let syntheticSuspected = reading.syntheticInputSuspected(threshold: syntheticToleranceSeconds)

        let idleTransition: IdleTransition?
        if isIdle != wasIdle {
            idleTransition = isIdle ? .becameIdle : .becameActive
        } else {
            idleTransition = nil
        }

        let syntheticTransition: SyntheticInputTransition?
        if syntheticSuspected != wasSyntheticSuspected {
            syntheticTransition = syntheticSuspected ? .began : .ended
        } else {
            syntheticTransition = nil
        }

        wasIdle = isIdle
        wasSyntheticSuspected = syntheticSuspected

        return Sample(
            reading: reading,
            isIdle: isIdle,
            idleTransition: idleTransition,
            syntheticInputTransition: syntheticTransition
        )
    }

    /// Both counters, in the order that makes `hardwareSeconds >= sessionSeconds` a property
    /// rather than a coincidence. A reading that violates it means the sources were swapped,
    /// which would silently invert the safe direction — so the self-check asserts it on live
    /// readings and the suite asserts it on every fixture.
    public func read() -> IdleReading {
        IdleReading(
            hardwareSeconds: source.hardwareSeconds,
            sessionSeconds: source.sessionSeconds
        )
    }

    /// Forget what the last sample found.
    ///
    /// Called when sensing resumes from a global pause: while the observers were detached the
    /// person may have come and gone several times, and reporting "became active" against a
    /// state from ten minutes ago would put a transition in the timeline that did not happen
    /// when the row says it did.
    public func forgetTransitions() {
        wasIdle = false
        wasSyntheticSuspected = false
    }

    // MARK: - IdleObserving

    /// Reading the idle counter needs no grant, on either source (probe P-84).
    public nonisolated var availability: ObservationAvailability { .available }

    /// How long the person has been away, by the pessimistic source.
    public nonisolated func idleDuration() -> Duration {
        .seconds(source.hardwareSeconds)
    }
}
