import Foundation

/// **One thing a window put on the screen, named** (focus-h7h).
///
/// The vocabulary the surfaces report in and the vocabulary the composition root computes its
/// expectations in are the same enum, for the reason `ActionHitTarget.identifier` is an action's
/// own `rawValue`: two vocabularies that have to be kept in step are two vocabularies that drift,
/// and a field reported under a name nobody expects reads as *not drawn* rather than as a typo.
public enum ShellRenderedField: String, Sendable, CaseIterable, Codable, Hashable {
    // --- the cockpit ---------------------------------------------------------------------
    /// The sentence the hero drew, or the empty string where it drew the placeholder prompt.
    case priorityIntent
    /// The status the badge drew.
    case status
    /// How many rows the recent-priorities list drew.
    case recentCount
    /// The elapsed figure the session controls were given, formatted to whole seconds.
    ///
    /// `"none"` when there is no figure. A session timer that reads nothing and one that reads
    /// zero are different defects, and `""` for both would make them the same reading.
    case sessionElapsedSeconds
    /// The phase the session badge drew, or `"none"`.
    case sessionPhase
    /// The task named by the handoff sheet the window is showing, or `""`.
    case handoffTask
    /// The sensing sentence the footer drew.
    case sensingSummary
    /// Every capability and the state the window drew it in.
    case capabilityStates
    /// Which mutation hosts the window was given. A cockpit handed neither draws every control
    /// disabled and no capture field at all — a window that looks finished and does nothing,
    /// which is a defect no receipt can see.
    case mutationHostsAttached

    // --- the Settings window --------------------------------------------------------------
    /// The sensing sentence the **Privacy** pane drew. Separate from the cockpit's, because a
    /// shell that told the truth in one window and not the other is a real, shippable defect.
    case privacySummary
    /// Every capability, as the Privacy pane's matrix drew it.
    case privacyCapabilities
    /// The band the verdict inspector drew, or `"none"`.
    case verdictBand
    /// The voice the Intervention pane's picker drew as selected.
    case interventionVoice
    /// Whether the Intervention pane's Reduced-Interruption switch drew as on.
    case reducedInterruption
    /// The appearance the General pane's picker drew as selected.
    case appearancePreference

    // --- the Keyboard Shortcuts window ------------------------------------------------------
    /// How many shortcut rows the reference actually drew. `0` is the empty window.
    case shortcutRowCount

    // --- every window ------------------------------------------------------------------------
    /// The `AppearanceTraits` the window **resolved out of its own environment**, as
    /// `AppearanceTraits.renderedDescription`. This is the one field that says whether the
    /// scene's `.appearanceTraits` injection reached the view, and it is reported by all three
    /// windows separately for the reason `ShellThemedSurface` has three cases.
    case appearanceTraits
}

/// **What one window says it drew**, with the connection generation it drew from.
///
/// ## Why the generation is here, and why it is the whole reason this is a struct
///
/// Taken from `NudgeActionFrameSet`, where it was measured to be load-bearing.
/// `onPreferenceChange` fires when the **value** changes, so a window laid out twice with the
/// same content produces the same value and the second layout is never delivered — and a host
/// that cleared its collection before each pass would read *nothing* for a window that is drawn
/// perfectly. The generation makes two identical layouts two distinguishable readings.
///
/// It does a second job here that it does not do there. The composition root stamps each
/// connection it builds with a fresh generation, so a report carrying an **older** one is a
/// window drawing from a connection the root has already replaced — which is exactly what a
/// scene that cached a value, or fabricated one from a stale copy, produces.
public struct ShellRenderedValues: Sendable, Equatable, Hashable, Codable {
    public var generation: Int
    public var values: [String: String]

    public init(generation: Int = 0, values: [String: String] = [:]) {
        self.generation = generation
        self.values = values
    }

    /// A window that has reported nothing at all.
    ///
    /// Generation `0`, which no connection is ever stamped with — the root's counter starts at
    /// one — so "nothing was reported" cannot be mistaken for "the first connection was drawn".
    public static let nothing = ShellRenderedValues()

    /// The generation of a surface that has **no connection to become stale**.
    ///
    /// The Keyboard Shortcuts reference reads nothing from the graph: it draws
    /// `CommandRegistry.shell`, a committed value that cannot change while the process lives. A
    /// counter over it would only ever reach one, and a reader would have to work out that this
    /// was by construction rather than by accident. One named constant says so instead.
    public static let singleIssue = 1

    public subscript(field: ShellRenderedField) -> String? {
        get { values[field.rawValue] }
        set { values[field.rawValue] = newValue }
    }

    public var dictionary: [String: Any] {
        ["generation": generation, "values": values]
    }
}

/// **Whether a window drew what the application actually knows** (focus-h7h).
///
/// A reading rather than a `Bool`, for the reason `DecisionSurfaceReading` is one: the three ways
/// it fails are three different defects.
///
/// | field | the defect it names |
/// |---|---|
/// | `generation` ≠ `expectedGeneration` | the window is drawing from a connection the root has replaced — or from none at all |
/// | `unreportedFields` | a value the window is supposed to draw was never reported: that part of the window drew nothing |
/// | `staleFields` | it drew **something else** — the frozen placeholder, the constant, the default |
public struct ShellRenderReading: Sendable, Equatable, Hashable {
    public let surface: String
    public let generation: Int
    public let expectedGeneration: Int
    public let unreportedFields: [String]
    /// Each disagreement as `field: drew "x", the app knows "y"`, so a failing gate line names the
    /// value rather than only the field.
    public let staleFields: [String]

    /// **How many values the composition root claimed to have handed this window.**
    ///
    /// The non-vacuity guard, and it is not decoration. A field the root has no opinion about is
    /// skipped rather than failed — the Settings window has nothing to say about the cockpit's
    /// recents — so a root that recorded *nothing* would make `drewWhatTheAppKnows` true for a
    /// window drawing anything at all. The gate asserts a floor on this number, which is the same
    /// job `len(declared) >= 12` does for the wire enumeration.
    public let expectedFieldCount: Int

    public init(
        surface: String,
        generation: Int,
        expectedGeneration: Int,
        unreportedFields: [String],
        staleFields: [String],
        expectedFieldCount: Int
    ) {
        self.surface = surface
        self.generation = generation
        self.expectedGeneration = expectedGeneration
        self.unreportedFields = unreportedFields
        self.staleFields = staleFields
        self.expectedFieldCount = expectedFieldCount
    }

    /// **The one honest predicate**, and the thing that replaced "the wire fired".
    ///
    /// A receipt that fires when a closure runs cannot tell a closure that produced the right
    /// value from one that produced a constant. This can: the window says what it put on the
    /// screen, and the composition root holds it up beside what it knows.
    public var drewWhatTheAppKnows: Bool {
        generation == expectedGeneration
            && unreportedFields.isEmpty
            && staleFields.isEmpty
    }

    public var summary: String {
        if drewWhatTheAppKnows { return "\(surface) drew every value the app knows" }
        var parts: [String] = []
        if generation != expectedGeneration {
            parts.append(
                "drawn from connection \(generation), the app has issued \(expectedGeneration)"
            )
        }
        if !unreportedFields.isEmpty {
            parts.append("nothing drawn for \(unreportedFields.joined(separator: ", "))")
        }
        if !staleFields.isEmpty {
            parts.append(staleFields.joined(separator: "; "))
        }
        return "\(surface): " + parts.joined(separator: "; ")
    }

    public var dictionary: [String: Any] {
        [
            "surface": surface,
            "generation": generation,
            "expectedGeneration": expectedGeneration,
            "unreportedFields": unreportedFields,
            "staleFields": staleFields,
            "expectedFieldCount": expectedFieldCount,
            "drewWhatTheAppKnows": drewWhatTheAppKnows,
            "summary": summary
        ]
    }
}

/// **The comparison, as a pure function of two dictionaries** (focus-h7h).
///
/// Nothing here touches a view, a window or a store, which is what makes the whole invariant
/// table-testable instead of only being observable on a Mac with a window server — the same
/// division `DecisionSurfaceReachability` is built on.
public enum ShellRenderFidelity {
    /// - Parameters:
    ///   - surface: which window, for the report line.
    ///   - rendered: what the window said it drew.
    ///   - expected: what the application knows, field by field, computed by the composition
    ///     root at the moment of the reading. A field the root has no opinion about is simply
    ///     absent, and an absent expectation is never a failure: the Settings window has nothing
    ///     to say about the cockpit's recents.
    public static func evaluate(
        surface: String,
        rendered: ShellRenderedValues,
        expected: [ShellRenderedField: String],
        expectedGeneration: Int
    ) -> ShellRenderReading {
        var unreported: [String] = []
        var stale: [String] = []

        for field in ShellRenderedField.allCases {
            guard let want = expected[field] else { continue }
            guard let drew = rendered[field] else {
                unreported.append(field.rawValue)
                continue
            }
            if drew != want {
                stale.append("\(field.rawValue): drew \"\(drew)\", the app knows \"\(want)\"")
            }
        }

        return ShellRenderReading(
            surface: surface,
            generation: rendered.generation,
            expectedGeneration: expectedGeneration,
            unreportedFields: unreported,
            staleFields: stale,
            expectedFieldCount: expected.count
        )
    }
}

extension AppearanceTraits {
    /// The traits as one comparable line.
    ///
    /// A string rather than the value itself because this crosses a SwiftUI preference and a JSON
    /// report, and because a failing gate line that reads `drew "light/-/-/-/-", the app knows
    /// "dark/contrast/-/motion/-"` says what broke without anybody decoding a struct.
    public var renderedDescription: String {
        [
            colorScheme.rawValue,
            increasedContrast ? "contrast" : "-",
            reduceTransparency ? "transparency" : "-",
            reduceMotion ? "motion" : "-",
            differentiateWithoutColor ? "colour" : "-"
        ].joined(separator: "/")
    }
}

extension CapabilityMatrix {
    /// Every capability and its state, in `Capability.allCases` order, as one comparable line.
    ///
    /// The whole table rather than a count: a matrix nobody probed is twelve `notRequested` rows
    /// and has exactly the same *size* as the live one, so counting would compare equal for the
    /// one mutation this field exists to catch.
    public var renderedDescription: String {
        allStates
            .map { "\($0.capability.rawValue)=\($0.state.rawValue)" }
            .joined(separator: ",")
    }
}
