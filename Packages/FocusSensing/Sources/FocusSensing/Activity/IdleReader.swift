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
    /// `.hidSystemState` at `kCGAnyInputEventType` — IOHIDSystem's raw `HIDIdleTime` clock.
    var hardwareSeconds: Double { get }
    /// `.combinedSessionState` at `kCGAnyInputEventType` — this session's newest CGEvent.
    var sessionSeconds: Double { get }
}

/// One concrete `CGEventType` read under **both** source states at nearly one instant.
///
/// This is the invariant that is actually true of the two states, and the reason the old one
/// (`hardware >= session`) was not: for a concrete event type the two states answer with the
/// same number. See `CGEventIdleSource.secondsPerConcreteEventType()`.
public struct IdleSourceAgreement: Sendable, Equatable, Hashable {
    /// The event type's own name, as the report and the gate print it.
    public let eventType: String
    /// `.hidSystemState`, for this one type.
    public let hardwareSeconds: Double
    /// `.combinedSessionState`, for this one type.
    public let sessionSeconds: Double

    public init(eventType: String, hardwareSeconds: Double, sessionSeconds: Double) {
        self.eventType = eventType
        self.hardwareSeconds = hardwareSeconds
        self.sessionSeconds = sessionSeconds
    }

    /// Signed, so a report reader can see which way a disagreement went.
    public var differenceSeconds: Double { hardwareSeconds - sessionSeconds }
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
    ///
    /// **It is not "the newest event of any type."** Under `.hidSystemState` it is IOHIDSystem's
    /// `HIDIdleTime` — measured byte-identical to `ioreg`'s across six paired samples — which a
    /// HID device report resets even when no input event is produced. That is why `isIdle` no
    /// longer trusts it alone, and why the pin below reads concrete types instead.
    static let anyInputEventType: CGEventType = CGEventType(rawValue: ~UInt32(0)) ?? .null

    /// The concrete event types the agreement pin reads, with the names it publishes.
    ///
    /// Four kinds of real input a person produces — a pointer moving, a key going down, a click,
    /// a scroll — chosen so no one input device carries the pin on its own. The self-check
    /// publishes a row per entry and the gate asserts a floor on how many it got, so shrinking
    /// this list is a red gate rather than a quieter one.
    public static let concreteEventTypes: [(name: String, type: CGEventType)] = [
        ("mouseMoved", .mouseMoved),
        ("keyDown", .keyDown),
        ("leftMouseDown", .leftMouseDown),
        ("scrollWheel", .scrollWheel)
    ]

    /// Both states, per concrete event type, session read first for the same reason `read()`
    /// reads it first: whichever is read second is measured a hair later and comes back a hair
    /// larger, and putting that on the hardware side keeps the difference one-signed.
    ///
    /// Measured 2026-09-03: every row's two figures agreed to the nanosecond-ish width of one
    /// syscall while the `~0` sentinel disagreed by four hours. That is the true property of
    /// the two states, and it is what the gate and the suite assert now.
    public static func secondsPerConcreteEventType() -> [IdleSourceAgreement] {
        concreteEventTypes.map { entry in
            let session = CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: entry.type
            )
            let hardware = CGEventSource.secondsSinceLastEventType(
                .hidSystemState,
                eventType: entry.type
            )
            return IdleSourceAgreement(
                eventType: entry.name,
                hardwareSeconds: hardware,
                sessionSeconds: session
            )
        }
    }

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

/// Whether the person is at the keyboard — read from **both** counters, neither of them alone.
///
/// ## Why neither source is the primary any more
///
/// The old note here said `.combinedSessionState` counts a strict superset of what
/// `.hidSystemState` counts, so `combined ≤ hid` always, which made the hardware figure the
/// pessimistic one. Measured 2026-09-03, that is false: at `kCGAnyInputEventType` the hardware
/// state does not report the newest CGEvent at all but IOHIDSystem's `HIDIdleTime`, which a HID
/// device report resets without any input event being produced. On this Mac it read 105.71 s
/// against 14 850 s of real quiet, and gate 5 kept nudging an empty chair.
///
/// `IdleReading.isIdle` therefore takes the **maximum**, which keeps the asymmetry the design
/// always wanted: calling a present user idle costs a nudge that would have been welcome, while
/// calling an absent user present nudges an empty chair.
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

    /// Both counters, session first.
    ///
    /// **The order is still load-bearing, for a smaller reason than it used to be.** Both
    /// counters are "seconds since the last event of their kind", so both grow with the passage
    /// of time and the two reads cannot happen at the same instant; whichever is read *second*
    /// is measured a little later and comes back a little larger. Reading session first keeps
    /// that syscall's worth of elapsed time on one known side, so the published
    /// `hardwareMinusSessionSeconds` gap is a fact about the sources and not about read order.
    /// It no longer props up an ordering invariant, because there is no ordering invariant:
    /// `hardware >= session` was never a property of these two states (focus-7az). What is
    /// asserted instead is `CGEventIdleSource.secondsPerConcreteEventType()` — per concrete
    /// event type, the two states agree.
    public func read() -> IdleReading {
        let sessionSeconds = source.sessionSeconds
        return IdleReading(
            hardwareSeconds: source.hardwareSeconds,
            sessionSeconds: sessionSeconds
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

    /// How long the person has been away — the longest silence either source can testify to,
    /// which is the same figure `IdleReading.isIdle` compares against the threshold.
    ///
    /// It was `source.hardwareSeconds` alone, which on this Mac answered 105 s for a chair that
    /// had been empty four hours (focus-7az). A seam that disagreed with the verdict it exists
    /// to explain would be worse than no seam.
    public nonisolated func idleDuration() -> Duration {
        .seconds(max(source.hardwareSeconds, source.sessionSeconds))
    }
}
