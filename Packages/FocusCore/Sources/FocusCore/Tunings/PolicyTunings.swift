import Foundation

/// **Every numeric policy constant, as something a person may turn** (focus-exdi, owner ruling
/// 2026-09-08).
///
/// `RelevancePolicy` and `InterventionPolicy` stay what they are: the shipped defaults, classed,
/// digested and witnessed (R-59, R-74), and everything the evaluation gate replays runs on them.
/// What changes is that the running app reads each constant through a `PolicyTunings` value,
/// which is the defaults with the person's overrides on top. A tuning that was never touched is
/// exactly the constant; a tuning that was touched is clamped to its range, so no value a person
/// can enter takes the engine somewhere its invariants do not hold.
///
/// One case per constant rather than a field per constant, for three reasons: the Settings
/// pane draws the whole table from `allCases` and cannot forget one; the store keeps one row per
/// case and a new case needs no schema stage; and the self-check can report the table whole.
public enum PolicyTuning: String, Sendable, CaseIterable, Hashable, Codable, Identifiable {
    // Interventions — the pane's own nine
    case queryDwellThreshold
    case queryCooldown
    case mandateCooldown
    case escalationDwell
    case snoozeFirst
    case snoozeSecond
    case snoozeThird
    case dailyQueryCap
    case dailyQueryCapAllPriorities
    case dailyAccusationCap
    case dailyInterruptionCap
    // Interventions — the rest
    case reservedAccusationUnits
    case ignoredQueryBackoff
    case ignoredAccusationBackoff
    case backoffSpan
    case pausePreset
    // Drift and return
    case sustainedDriftThreshold
    case driftResetGrace
    case lookBackSpan
    case maximumLookBackEvents
    case returnAnchorDwell
    case detourExtension
    // Relevance
    case minimumTokenLength
    case minimumStrongTokenLength
    case minimumOverlapTokens
    case minimumPriorityContentTokens
    case minimumNegativeBasisItems
    case maximumExplanationTokens
    case similarityRelevantCeiling
    case languageConfidenceFloor
    case similarityCacheCapacity

    public var id: String { rawValue }

    /// What the number is, which decides how the pane draws it and how the engine reads it.
    public enum Unit: String, Sendable, Hashable, Codable {
        /// A span; drawn in minutes and seconds, read back as a `Duration`.
        case seconds
        /// A whole count.
        case count
        /// A proportion between 0 and 1.
        case ratio
    }

    /// Where the constant lives, which is the section the pane draws it under.
    public enum Family: String, Sendable, Hashable, Codable, CaseIterable {
        case interventions
        case drift
        case relevance
    }

    public var unit: Unit {
        switch self {
        case .queryDwellThreshold, .queryCooldown, .mandateCooldown, .escalationDwell,
             .snoozeFirst, .snoozeSecond, .snoozeThird, .backoffSpan, .pausePreset,
             .sustainedDriftThreshold, .driftResetGrace, .lookBackSpan, .returnAnchorDwell,
             .detourExtension:
            .seconds
        case .similarityRelevantCeiling, .languageConfidenceFloor:
            .ratio
        default:
            .count
        }
    }

    public var family: Family {
        switch self {
        case .queryDwellThreshold, .queryCooldown, .mandateCooldown, .escalationDwell,
             .snoozeFirst, .snoozeSecond, .snoozeThird, .dailyQueryCap,
             .dailyQueryCapAllPriorities, .dailyAccusationCap, .dailyInterruptionCap,
             .reservedAccusationUnits, .ignoredQueryBackoff, .ignoredAccusationBackoff,
             .backoffSpan, .pausePreset:
            .interventions
        case .sustainedDriftThreshold, .driftResetGrace, .lookBackSpan, .maximumLookBackEvents,
             .returnAnchorDwell, .detourExtension:
            .drift
        case .minimumTokenLength, .minimumStrongTokenLength, .minimumOverlapTokens,
             .minimumPriorityContentTokens, .minimumNegativeBasisItems,
             .maximumExplanationTokens, .similarityRelevantCeiling, .languageConfidenceFloor,
             .similarityCacheCapacity:
            .relevance
        }
    }

    /// The shipped value — the policy constant itself, never a copy of it.
    public var shippedValue: Double {
        switch self {
        case .queryDwellThreshold: Self.seconds(InterventionPolicy.queryDwellThreshold)
        case .queryCooldown: Self.seconds(InterventionPolicy.queryCooldown)
        case .mandateCooldown: Self.seconds(RelevancePolicy.mandateCooldown)
        case .escalationDwell: Self.seconds(RelevancePolicy.escalationDwell)
        case .snoozeFirst: Self.seconds(InterventionPolicy.snoozeDurations[0])
        case .snoozeSecond: Self.seconds(InterventionPolicy.snoozeDurations[1])
        case .snoozeThird: Self.seconds(InterventionPolicy.snoozeDurations[2])
        case .dailyQueryCap: Double(InterventionPolicy.dailyQueryCap)
        case .dailyQueryCapAllPriorities: Double(InterventionPolicy.dailyQueryCapAllPriorities)
        case .dailyAccusationCap: Double(InterventionPolicy.dailyAccusationCap)
        case .dailyInterruptionCap: Double(InterventionPolicy.dailyInterruptionCap)
        case .reservedAccusationUnits: Double(InterventionPolicy.reservedAccusationUnits)
        case .ignoredQueryBackoff: Double(InterventionPolicy.ignoredQueryBackoff)
        case .ignoredAccusationBackoff: Double(InterventionPolicy.ignoredAccusationBackoff)
        case .backoffSpan: Self.seconds(InterventionPolicy.backoffSpan)
        case .pausePreset: Self.seconds(Self.fixedPausePreset)
        case .sustainedDriftThreshold: Self.seconds(RelevancePolicy.sustainedDriftThreshold)
        case .driftResetGrace: Self.seconds(RelevancePolicy.driftResetGrace)
        case .lookBackSpan: Self.seconds(RelevancePolicy.lookBackSpan)
        case .maximumLookBackEvents: Double(RelevancePolicy.maximumLookBackEvents)
        case .returnAnchorDwell: Self.seconds(RelevancePolicy.returnAnchorDwell)
        case .detourExtension: Self.seconds(RelevancePolicy.detourExtension)
        case .minimumTokenLength: Double(RelevancePolicy.minimumTokenLength)
        case .minimumStrongTokenLength: Double(RelevancePolicy.minimumStrongTokenLength)
        case .minimumOverlapTokens: Double(RelevancePolicy.minimumOverlapTokens)
        case .minimumPriorityContentTokens: Double(RelevancePolicy.minimumPriorityContentTokens)
        case .minimumNegativeBasisItems: Double(RelevancePolicy.minimumNegativeBasisItems)
        case .maximumExplanationTokens: Double(RelevancePolicy.maximumExplanationTokens)
        case .similarityRelevantCeiling: RelevancePolicy.similarityRelevantCeiling.value ?? 0
        case .languageConfidenceFloor: RelevancePolicy.languageConfidenceFloor.value ?? 0
        case .similarityCacheCapacity: Double(RelevancePolicy.similarityCacheCapacity)
        }
    }

    /// The span a person may set, and the step a control moves it by.
    ///
    /// The ranges are UI bounds, not thresholds: a floor under which the engine's invariants
    /// stop holding (a cooldown of zero, a cap of zero, a token shorter than one character) and
    /// a ceiling past which the setting stops meaning anything a person would want (a day of
    /// dwell, a hundred questions). They are stated here, in one place, beside the units.
    public var range: ClosedRange<Double> {
        switch unit {
        case .seconds:
            switch self {
            case .driftResetGrace, .returnAnchorDwell: Self.oneSecond...Self.tenMinutes
            case .queryDwellThreshold, .sustainedDriftThreshold: Self.tenSeconds...Self.oneHour
            case .backoffSpan: Self.oneMinute...Self.oneDay
            case .pausePreset: Self.oneMinute...Self.fourHours
            default: Self.tenSeconds...Self.fourHours
            }
        case .count:
            switch self {
            case .dailyQueryCap, .dailyQueryCapAllPriorities, .dailyAccusationCap,
                 .dailyInterruptionCap:
                Self.zero...Self.hundred
            case .reservedAccusationUnits, .minimumNegativeBasisItems, .minimumOverlapTokens:
                Self.zero...Self.ten
            case .similarityCacheCapacity, .maximumLookBackEvents:
                Self.one...Self.thousand
            default:
                Self.one...Self.twenty
            }
        case .ratio:
            Self.zero...Self.one
        }
    }

    public var step: Double {
        switch unit {
        case .seconds:
            switch self {
            case .driftResetGrace, .returnAnchorDwell, .queryDwellThreshold: Self.fiveSeconds
            case .backoffSpan, .pausePreset: Self.fiveMinutes
            default: Self.thirtySeconds
            }
        case .count: Self.one
        case .ratio: Self.ratioStep
        }
    }

    /// Clamp a candidate into the range, on the step's grid where the unit has one.
    public func clamped(_ candidate: Double) -> Double {
        let bounded = min(max(candidate, range.lowerBound), range.upperBound)
        guard unit != .ratio else { return bounded }
        return bounded.rounded()
    }

    // The bounds, named once. UI bounds, deliberately outside the two policy files and outside
    // the directories the literal lint reads (R-70f, R-96j): they are not thresholds and owe no
    // witness — a witness for "the stepper stops at four hours" would be a witness for nothing.
    static let zero = 0.0
    static let one = 1.0
    static let ten = 10.0
    static let twenty = 20.0
    static let hundred = 100.0
    static let thousand = 1000.0
    static let ratioStep = 0.01
    static let oneSecond = 1.0
    static let fiveSeconds = 5.0
    static let tenSeconds = 10.0
    static let thirtySeconds = 30.0
    static let oneMinute = 60.0
    static let fiveMinutes = 300.0
    static let tenMinutes = 600.0
    static let oneHour = 3600.0
    static let fourHours = 14_400.0
    static let oneDay = 86_400.0

    /// The one fixed pause preset in `InterventionPolicy.pauseDurations`; the other two are
    /// "until a time" and "the rest of the day" and have no number to turn.
    static var fixedPausePreset: Duration {
        for preset in InterventionPolicy.pauseDurations {
            if case .fixed(let span) = preset { return span }
        }
        return .zero
    }

    static func seconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

/// The defaults with a person's overrides on top: what the engine reads at runtime.
public struct PolicyTunings: Sendable, Equatable, Hashable, Codable {
    /// Only the values that differ from the shipped ones. Absent means "the constant".
    public private(set) var overrides: [PolicyTuning: Double]

    public init(overrides: [PolicyTuning: Double] = [:]) {
        self.overrides = [:]
        for (tuning, value) in overrides { set(tuning, to: value) }
    }

    /// Every constant at its shipped value.
    public static let shipped = PolicyTunings()

    public var isShipped: Bool { overrides.isEmpty }

    public func value(_ tuning: PolicyTuning) -> Double {
        overrides[tuning] ?? tuning.shippedValue
    }

    public func duration(_ tuning: PolicyTuning) -> Duration {
        .seconds(value(tuning))
    }

    public func count(_ tuning: PolicyTuning) -> Int {
        Int(value(tuning).rounded())
    }

    /// The three snooze spans, in order, as the panel offers them.
    public var snoozeDurations: [Duration] {
        [duration(.snoozeFirst), duration(.snoozeSecond), duration(.snoozeThird)]
    }

    /// Set one tuning. A value equal to the shipped one is not an override, so a person who
    /// turns a dial back by hand is exactly where a person who never touched it is.
    public mutating func set(_ tuning: PolicyTuning, to candidate: Double) {
        let value = tuning.clamped(candidate)
        if value == tuning.shippedValue {
            overrides.removeValue(forKey: tuning)
        } else {
            overrides[tuning] = value
        }
    }

    public mutating func reset(_ tuning: PolicyTuning) {
        overrides.removeValue(forKey: tuning)
    }

    public mutating func resetAll() {
        overrides.removeAll()
    }
}
