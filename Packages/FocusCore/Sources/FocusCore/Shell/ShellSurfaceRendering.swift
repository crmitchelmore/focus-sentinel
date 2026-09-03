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
    /// The **definition of done** the hero's second line drew, or `""` (F-08). Separate from
    /// `priorityDetail` because it is the one field of the priority that has its own control and
    /// its own two draw sites — read-only text and an editable field — and a defect in either is
    /// a sentence the person wrote coming back wrong.
    case priorityDoneWhen
    /// The whole commitment, as `ShellValueDigest`. Derived rather than enumerated: a field added
    /// to `PrioritySnapshot` is in this string the moment it is added, with nobody editing
    /// anything (focus-7ow).
    case priorityDetail
    /// The status the badge drew.
    case status
    /// Which line the footer drew about the store — `cockpitStoreReady` or
    /// `cockpitStoreUnavailable`, by the **string key the label was actually given**.
    ///
    /// A boolean flip here tells the person their work is not being saved when it is, or the
    /// reverse. It was drawn from `state.storeIsReady` and reported nowhere (focus-7ow).
    case storeStatus
    /// Whether the start-of-day ritual banner is on the screen: `"shown"` or `"hidden"`.
    ///
    /// The banner appears when `showsRitualPrompt` **and** a mutation host is attached, so this
    /// is the conjunction the window actually drew rather than either half of it.
    case ritualBanner
    /// How many rows the recent-priorities list drew.
    case recentCount
    /// **What is in those rows** (focus-7ow). `recentCount` alone was satisfied by a list of the
    /// right length holding somebody else's history.
    case recentDigest
    /// The elapsed figure the session controls were given, formatted to whole seconds.
    ///
    /// `"none"` when there is no figure. A session timer that reads nothing and one that reads
    /// zero are different defects, and `""` for both would make them the same reading.
    case sessionElapsedSeconds
    /// The phase the session badge drew, or `"none"`.
    case sessionPhase
    /// The whole session, as `ShellValueDigest` — the phase is one field of several.
    case sessionDetail
    /// The application the session controls named as the one to return to, or `"none"` (F-101).
    ///
    /// Reported by `SessionControls` itself, from the identifier it will hand the interruption
    /// sheet: a sheet that names an application which does not exist is what a mutation to this
    /// argument produces, and nothing reported it.
    case lastActiveApp
    /// The task named by the handoff sheet the window is showing, or `""`.
    case handoffTask
    /// The whole handoff, as `ShellValueDigest`: the task is one field of a request that also
    /// carries where it came from.
    case handoffDetail
    /// The sensing sentence the footer drew.
    case sensingSummary
    /// The whole `SensingSummary` behind that sentence, as `ShellValueDigest`. The sentence is a
    /// projection of six facts, and five of them could move without it changing.
    case sensingDetail
    /// Every capability and the state the window drew it in.
    case capabilityStates
    /// Which mutation hosts the window was given. A cockpit handed neither draws every control
    /// disabled and no capture field at all — a window that looks finished and does nothing,
    /// which is a defect no receipt can see.
    case mutationHostsAttached
    /// **Whether the footer is making the one-time launch-at-login offer**: `"shown"` or
    /// `"hidden"` (D-12, focus-odz.4).
    ///
    /// The conjunction the window actually drew, in `ritualBanner`'s shape and for its reason: an
    /// offer that appears when it should not is a row asking somebody for a commitment they have
    /// already declined, and one that never appears is a feature nobody can find.
    case launchAtLoginOffer
    /// **Whether the first-run explanation is on screen**: `"shown"` or `"hidden"`
    /// (focus-odz.7).
    ///
    /// The one screen that says what this app looks at, and it is shown exactly once. A receipt
    /// is what tells "shown on the wrong launch" from "never shown at all", and those are two
    /// different broken promises.
    case firstRunExplanation

    // --- the Settings window --------------------------------------------------------------
    /// The sensing sentence the **Privacy** pane drew. Separate from the cockpit's, because a
    /// shell that told the truth in one window and not the other is a real, shippable defect.
    case privacySummary
    /// Every capability, as the Privacy pane's matrix drew it.
    case privacyCapabilities
    /// **Where the Privacy pane told the person their data lives** — the path it actually drew,
    /// which is also what its Reveal in Finder button opens. A mutation printed `/` (focus-7ow).
    case privacyStorePath
    /// **The retention window the Privacy pane drew as chosen**, as its stored day count —
    /// `7`, `30`, `90`, or `0` for forever (F-115, focus-l7n).
    ///
    /// The number rather than the button's label, because the number is what the sweep reads: a
    /// pane that highlighted the right row while holding a different value would be a pane that
    /// tells somebody their history is being kept for a week when it is being kept for a
    /// quarter. Reported by the pane for `privacyStorePath`'s reason.
    case retentionWindow
    /// The band the verdict inspector drew, or `"none"`.
    case verdictBand
    /// The whole verdict, as `ShellValueDigest`. The band is one field: a verdict about a
    /// different subject, with a different confidence and a different explanation, has the same
    /// band.
    case verdictDetail
    /// The voice the Intervention pane's picker drew as selected.
    case interventionVoice
    /// Whether the Intervention pane's Reduced-Interruption switch drew as on.
    case reducedInterruption
    /// Whether that switch drew as **forced** by Reduce Motion rather than as a preference
    /// (F-148). The pane says which, and saying the wrong one tells a person they can change
    /// something they cannot, or the reverse.
    case reducedInterruptionForced
    /// The quiet-hours window the pane drew, or `"none"` for off (R-85).
    case quietHours
    /// Today's spend over the cap, as the pane drew it (D-01: information, never a score).
    case interruptionUsage
    /// **The notch companion's row, as the geometry decided it** (e08a). The named refusal, or
    /// `landed` — never the preference, because the row is a reading of the display and a row
    /// rendered from a switch would say a surface is real on a Mac that has no built-in panel.
    case notchCompanion
    /// The appearance the General pane's picker drew as selected.
    case appearancePreference
    /// **What the General pane's launch-at-login switch drew**, as the whole reading rather than
    /// as a `Bool` (D-12, focus-odz.4).
    ///
    /// The status and not the switch position, because the position is a projection of it and two
    /// of the four states draw the same position: `enabled` and `requiresApproval` both read on,
    /// and only one of them is true yet. A receipt carrying the position alone could not tell a
    /// pane that drew the footnote from one that did not.
    case launchAtLoginStatus
    /// **Whether the daily ritual banner is offered at all**, as the General pane's switch drew
    /// it (focus-d3g). Reported by the pane, for `appVersion`'s reason: a control handed a
    /// constant is invisible to a receipt taken anywhere else.
    case ritualEnabled
    /// **The combination quick capture is bound to**, as the General pane's picker drew it
    /// (focus-d3g). The glyphs rather than the two integers, because the glyphs are what the
    /// person reads and a receipt should carry what was on the screen.
    case quickCaptureShortcut
    /// **The build a person is looking at**, as the General pane drew it (focus-odz.3).
    ///
    /// Nothing in the programme read `CFBundleShortVersionString` before this, so a defect report
    /// against "Focus Sentinel" named no artefact. It is reported by the pane rather than by the
    /// window for `privacyStorePath`'s reason: a mutation that hands the pane a constant is
    /// invisible to a receipt taken anywhere but where the string is drawn.
    case appVersion
    /// **Which pane is on screen** (focus-7ow).
    ///
    /// A macOS `TabView` builds only the selected pane, so before this existed every stamp inside
    /// an unselected pane simply never arrived and a defect in one was invisible. The selection
    /// is driven from the composition root now, and this is how a reading says which pane it is a
    /// reading *of*.
    case settingsTab

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

    /// **What a cockpit with nothing committed to reports for the sections it does not draw**
    /// (focus-7ow).
    ///
    /// The commitment sections — the definition of done, the session controls, the application to
    /// return to — exist only while there is a priority, and a field nobody reported is
    /// indistinguishable from a section somebody deleted. So the window reports this instead, the
    /// composition root expects exactly this under the same condition, and "there was nothing to
    /// draw" stays a reading rather than becoming a silence.
    public static let noCommitment = "no-commitment"

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
