import FocusCore
import Foundation

/// **What each window drew, beside what it was handed** (focus-h7h, focus-7ow).
///
/// The composition root's receipts say **which** wire fired. They were measured to say nothing
/// about what travelled down it: an eight-part mutation that kept every receipt firing and
/// replaced every value with a constant passed the whole nineteen-stage gate, 262 ok-assertions
/// against 262, with an empty diff between the clean run's list and the mutant's. The cockpit
/// showed a frozen placeholder, the session timer read nothing, the Privacy pane always said
/// nothing was watched, three windows ignored dark mode and every accessibility setting, and the
/// Keyboard Shortcuts window was empty.
///
/// So each window reports the values it put on the screen, through the preference channel
/// `ShellRenderedValuesKey` — `DecisionSurfaceReachability`'s mechanism, pointed at the windows —
/// and this is where they arrive. Beside them is what the root **put into the connection**,
/// recorded at the moment it built it.
///
/// The expectation is recorded here rather than re-derived at the reading, and that is not an
/// optimisation. A comparison against a fresh read would be two reads taken a second apart, and
/// the session's elapsed figure moves between them: it would fail on the passage of time rather
/// than on a defect. What is asserted is exactly *what I handed you* against *what you drew*, and
/// `generation` is what keeps the two the same issue.
///
/// **It is its own object** (focus-tzj.6). Four dictionaries and six verbs that nothing else in
/// the root reads: `AppComposition` owns one of these and forwards the four readings the
/// self-check and the test lane ask it for, so the ledger of what was handed over and what came
/// back can be read — and unit-tested — without a composition root, a store or a window.
@MainActor
final class ShellRenderAudit {
    /// What each window says it drew, latest report per surface.
    private(set) var renderings: [ShellThemedSurface: ShellRenderedValues] = [:]

    /// What the root handed that window, recorded when it handed it over.
    private var expectations: [ShellThemedSurface: [ShellRenderedField: String]] = [:]

    /// How many connections the root has issued for each window. Stamped into the connection,
    /// carried back in every reported value, and compared: a report from an older issue is a
    /// window drawing from something the root has already replaced.
    private var generations: [ShellThemedSurface: Int] = [:]

    /// What each connection's audit said, taken at the moment the connection was built.
    private var totalities: [ShellThemedSurface: ShellTotalityReading] = [:]

    /// The issue number a window's report must carry to be current.
    func generation(of surface: ShellThemedSurface) -> Int {
        generations[surface] ?? 0
    }

    /// **The reading for one window**: what it drew, held up beside what it was handed.
    ///
    /// The whole of focus-h7h's acceptance in one value. `drewWhatTheAppKnows` is false for a
    /// window that reported nothing, for one drawing from a replaced connection, and for one that
    /// drew a constant where a live value was handed to it — three different defects, named
    /// separately, because a caller that could not tell them apart would report "wrong" for all
    /// of them.
    func renderReading(of surface: ShellThemedSurface) -> ShellRenderReading {
        ShellRenderFidelity.evaluate(
            surface: surface.rawValue,
            rendered: renderings[surface] ?? .nothing,
            expected: expectations[surface] ?? [:],
            expectedGeneration: generation(of: surface)
        )
    }

    /// One window's report, as it arrived from the preference channel.
    ///
    /// Late reports are kept rather than dropped: the reading compares the generation itself, so
    /// a stale one has to survive to be reported as stale. Dropping it here would turn "drawing
    /// from a replaced connection" back into "reported nothing", which is a different defect.
    ///
    /// **Reports accumulate forwards and a stale one replaces** (focus-7ow).
    ///
    /// The Settings window's panes are drawn one at a time — a macOS `TabView` builds only the
    /// selected one, and choosing a different one re-evaluates the window body and therefore
    /// takes a fresh issue of the connection. So a reading taken after the self-check has walked
    /// all three panes has to hold what each of them said, and each of them said it under a
    /// different issue number.
    ///
    /// That is the **same** rule `expect(_:_:for:)` and `nextGeneration(for:)` already follow on
    /// the other side of the comparison: expectations are additive and are deliberately not
    /// cleared when a new issue is taken, because the traits injection and the connection are two
    /// separate wires evaluated at two separate moments of one pass. What each side holds is
    /// therefore the same thing — the latest answer for every field, from whichever pass produced
    /// it — and the two are comparable field by field.
    ///
    /// A report carrying an **older** issue than the one already recorded still replaces the
    /// whole reading rather than merging into it. That is a window drawing from a connection this
    /// object has already replaced, it is its own defect, and merging it would turn "drawing from
    /// something stale" into "everything is fine".
    func record(_ values: ShellRenderedValues, for surface: ShellThemedSurface) {
        guard var existing = renderings[surface], values.generation >= existing.generation
        else {
            renderings[surface] = values
            return
        }
        existing.values.merge(values.values) { _, latest in latest }
        existing.generation = values.generation
        renderings[surface] = existing
    }

    // MARK: - Totality: every field of every connection, echoed by a receipt (focus-7ow)

    /// **Whether the receipts for this window's connection are total.**
    ///
    /// The reading that ends the enumeration. `ShellRenderReading` answers "did the window draw
    /// what it was handed", and it can only answer it about fields somebody thought to list —
    /// which is how a residue mutant reproduced the round-3 invisibility signature verbatim while
    /// four drawn things lied. This answers the prior question: **is there a field of this
    /// connection that no receipt covers at all.**
    func totalityReading(of surface: ShellThemedSurface) -> ShellTotalityReading {
        totalities[surface]
            ?? ShellTotalityReading(
                connection: surface.rawValue,
                walkedPaths: [],
                unmappedPaths: [],
                strandedPaths: [],
                unreportedPaths: []
            )
    }

    /// Walk the connection the root has just built, against the expectations it has just
    /// recorded.
    ///
    /// Run at the moment of building rather than in a test fixture because that is the only place
    /// that holds both halves at once: the value with all its fields, and the set of fields the
    /// root has an opinion about. A field with no echo, or an echo pointing at a field nothing
    /// expects, is a hole in the boundary and the self-check fails on it by name.
    func audit<Connection: ShellDrawnConnection>(
        _ connection: Connection,
        for surface: ShellThemedSurface
    ) {
        totalities[surface] = ShellConnectionTotality.audit(
            connection,
            reported: Set(expectations[surface, default: [:]].keys)
        )
    }

    /// Take the next issue number for a window.
    ///
    /// It deliberately does **not** clear that window's expectations. The traits injection and
    /// the connection are two separate wires evaluated at two separate moments of one pass —
    /// `.appearanceTraits(composition.appearanceTraits(for: .cockpit))` is an argument to a scene
    /// modifier and runs first, `CockpitHost.body` calls `cockpitConnection()` and runs second —
    /// so clearing here would throw away the traits the root had just recorded handing over.
    /// Every field is overwritten by the pass that hands it over again, which is what keeps the
    /// dictionary current without a reset that races the scene.
    func nextGeneration(for surface: ShellThemedSurface) -> Int {
        let next = generation(of: surface) + 1
        generations[surface] = next
        return next
    }

    /// **Pin a window's issue number to a constant**, for a window that has no connection to take
    /// an issue of.
    ///
    /// The Keyboard Shortcuts window's case, and its only one: it reads nothing from the graph, so
    /// there is nothing for it to become stale against and `ShellRenderedValues.singleIssue` is
    /// the issue it draws under for the life of the process.
    func pinGeneration(_ generation: Int, for surface: ShellThemedSurface) {
        generations[surface] = generation
    }

    /// Record one value the root is handing to a window.
    ///
    /// Additive, because the traits injection and the connection are two separate wires evaluated
    /// at two separate moments in one pass of the scene's body: the traits arrive first, the
    /// connection second, and a recording that replaced the dictionary would drop whichever came
    /// before it.
    func expect(_ field: ShellRenderedField, _ value: String, for surface: ShellThemedSurface) {
        expectations[surface, default: [:]][field] = value
    }
}
