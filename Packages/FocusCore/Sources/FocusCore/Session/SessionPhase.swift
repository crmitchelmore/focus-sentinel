import Foundation

/// Which phase a focus session is in.
///
/// Six canonical phases, two of them terminal. This enum is an **input to the nudge ladder**
/// (e05): `permitsIntervention` is true for `.focus` alone, and the ladder must require it
/// together with `FocusStatus.permitsIntervention`. Two independent gates, both declared
/// before anything consumes them, because a nudger that fires during a break and then has
/// suppression retrofitted is a defect shipped on purpose.
///
/// Raw values are strings and are persisted as strings, so reordering can never reinterpret a
/// stored row. e01's schema shipped `running` and `ended`; `decode(_:)` carries the aliases,
/// and `init(rawValue:)` is banned by the lint because it would silently turn a legacy
/// "running" session into a phase this build does not recognise.
public enum SessionPhase: String, Sendable, CaseIterable, Codable, Hashable {
    case focus
    case intentionalDetour
    case onBreak
    case paused
    case interrupted
    case complete

    /// The one sanctioned decoder — an **exhaustive switch over literals**, using no
    /// `RawRepresentable` initialiser anywhere.
    ///
    /// This is not stylistic. `SessionPhase(rawValue:)` is banned by `check-forbidden.sh`
    /// with no allowlist and no exempted call site, and that lint lands before this type is
    /// written — so a decoder that reached for `init(rawValue:)` internally could never have
    /// produced a green gate. Writing the cases out is what makes the ban total instead of
    /// aspirational.
    ///
    /// The switch's completeness is held by a test, not by the compiler:
    /// `SessionPhase.allCases` must each satisfy `decode(phase.rawValue) == phase`, so a
    /// seventh phase added without touching this function fails the suite rather than
    /// silently decoding to `.complete` in production.
    public static func decode(_ raw: String) -> SessionPhase {
        switch raw {
        case "focus", "running": .focus         // "running" is e01/e02 legacy
        case "intentionalDetour": .intentionalDetour
        case "onBreak": .onBreak
        case "paused": .paused
        case "interrupted": .interrupted
        case "complete", "ended": .complete     // "ended" is e01/e02 legacy
        default: .complete                      // unreadable to this build ⇒ over
        }
    }

    public var isTerminal: Bool { self == .interrupted || self == .complete }

    /// Whether the app may interrupt the user while the session is in this phase.
    ///
    /// `.focus` only. During an intentional detour the user has declared the deviation
    /// deliberate; on a break, paused, interrupted or complete there is nothing to nudge
    /// about. This mirrors `FocusStatus.permitsIntervention`, which is true for `unrelated`
    /// alone, and e05 must satisfy both.
    public var permitsIntervention: Bool { self == .focus }
}

/// The phases a paused session may be resumed into. A compile-time subset, so `resumeTo`
/// cannot be set to a terminal phase or to `.paused` itself.
///
/// `phase` is an exhaustive switch for the same reason `SessionPhase.decode` is: the lint
/// bans `ResumablePhase(rawValue:` too, and a force-unwrapped `init(rawValue:)` here would
/// both trip it and turn a future typo into a crash. `ResumablePhase.allCases` must each
/// satisfy `resumable.phase.rawValue == resumable.rawValue`.
public enum ResumablePhase: String, Sendable, CaseIterable, Codable, Hashable {
    case focus, intentionalDetour, onBreak

    public var phase: SessionPhase {
        switch self {
        case .focus: .focus
        case .intentionalDetour: .intentionalDetour
        case .onBreak: .onBreak
        }
    }

    /// The resumable phase a session is *leaving* at its first pause, or `nil` if the phase
    /// it is leaving is not one a session can be resumed into.
    ///
    /// Also an exhaustive switch, and for the same reason: this is the one place a
    /// `SessionPhase` is narrowed to a `ResumablePhase`, so it is the one place a
    /// `ResumablePhase(rawValue: phase.rawValue)` would otherwise have been written.
    public static func narrowing(_ phase: SessionPhase) -> ResumablePhase? {
        switch phase {
        case .focus: .focus
        case .intentionalDetour: .intentionalDetour
        case .onBreak: .onBreak
        case .paused, .interrupted, .complete: nil
        }
    }

    /// The one sanctioned decoder for a persisted `resumeToRaw`, in the same exhaustive shape
    /// as `SessionPhase.decode(_:)`. An unreadable value decodes to `nil`, and a resume with
    /// no stored destination goes to `.focus` — which is what the machine does anyway.
    public static func decode(_ raw: String?) -> ResumablePhase? {
        switch raw {
        case "focus": .focus
        case "intentionalDetour": .intentionalDetour
        case "onBreak": .onBreak
        default: nil
        }
    }
}
