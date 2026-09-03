import AppKit
import FocusCore
import FocusUI
import Foundation
import SwiftData

@testable import FocusHost

/// A clock that answers whatever the test set, so every cooldown and dwell in these suites is a
/// number the test chose rather than however long the machine took.
final class FixedMonotonicClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Duration

    init(_ value: Duration = .seconds(10_000)) {
        self.value = value
    }

    var elapsed: Duration {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: Duration) {
        lock.lock()
        value += interval
        lock.unlock()
    }
}

/// The wall clock, fixed. R-26 bans a bare `Date()` outside a `DateProvider`, and a receipt
/// stamped with "whenever the suite happened to run" is not a value anything can assert on.
struct FixedDateProvider: DateProvider {
    let now: Date
}

/// A notification centre that never touches `UNUserNotificationCenter`.
///
/// The nudge host takes a `NotificationDelivery`, and building one against the system centre
/// from a test bundle would be asking a permission boundary a question in a process that has no
/// business asking it. Since focus-wy0 the seam has one call, so this has one answer.
@MainActor
final class SilentNotificationCentre: NotificationCentring {
    func authorizationStatus(_ completion: @escaping @MainActor (Int) -> Void) {
        // `UNAuthorizationStatus.denied`. It reaches no decision — no rung routes to a
        // notification and no pane offers to change it — so what it answers is immaterial, and
        // "denied" is the posture that would once have mattered most.
        completion(1)
    }
}

/// A workspace that launches nothing. "Back to …" is `ReturnToTask`'s own subject; a test of the
/// nudge loop must not be able to bring another application forward as a side effect.
@MainActor
final class InertReturnWorkspace: ReturnWorkspace {
    private(set) var activations: [String] = []
    /// **What the applications in these suites call themselves** (focus-ebv).
    ///
    /// It answered `nil` for everything, which made the naming seam unfalsifiable from here: a
    /// host that never consulted it would fall back to the identifier and every assertion about
    /// a drawn sentence would still pass, because the fallback and the key are the same string.
    /// Seeded with `NudgeHostFixture.displayNames`, they are different strings and a host that
    /// skipped the seam fails.
    var runningNames: [String: String] = NudgeHostFixture.displayNames

    func localizedNameOfRunningApplication(_ bundleIdentifier: String) -> String? {
        runningNames[bundleIdentifier]
    }

    func activateRunningApplication(_ bundleIdentifier: String) -> Bool {
        activations.append(bundleIdentifier)
        return true
    }

    /// **What is on the disk** (focus-7gc). Empty by default, so these suites go on exercising
    /// the running branch; a suite that wants the not-running one seeds a URL here and a name in
    /// `installedNames`, and gets the same two-map shape `StubReturnWorkspace` has.
    var installedURLs: [String: URL] = [:]
    var installedNames: [URL: String] = [:]

    func applicationURL(for bundleIdentifier: String) -> URL? { installedURLs[bundleIdentifier] }

    func applicationName(at url: URL) -> String? { installedNames[url] }

    func openApplication(at url: URL, completion: @escaping @MainActor (Bool) -> Void) {
        completion(false)
    }
}

/// **A real nudge loop, on real surfaces, against a real store.**
///
/// Nothing here is a double except the human at the input boundary and the two boundaries a test
/// process must not cross — the notification centre and the workspace. The panel is the shipping
/// `NudgePanelController` with a real `NSPanel`, the menu bar is the shipping `MenuBarController`
/// with a real `NSStatusItem`, the ledger and the log are the shipping stores over an in-memory
/// container, and the decision is `NudgeDecider`'s.
///
/// That is the whole point of the package this file lives in: when these objects were in the
/// application target no test could reach them, and the wiring between them was asserted by
/// grepping the source for the substrings it was spelled with.
@MainActor
struct NudgeHostFixture {
    let container: ModelContainer
    let context: ModelContext
    let host: NudgeHost
    let panel: NudgePanelController
    let menuBar: MenuBarController
    let centre: SilentNotificationCentre
    let workspace: InertReturnWorkspace
    let clock: FixedMonotonicClock
    let ledger: QueryLedger
    let log: InterventionLog
    let priorities: PriorityStore
    let priorityID: UUID
    /// The notification boundary the host is wired to. Exposed because a press on a banner is one
    /// of the two ways a correction reaches the loop, and the other one — the panel's buttons —
    /// is reachable from a test only because the panel is real (focus-zrs).
    let notifications: NotificationDelivery
    /// **The one commitment this fixture's loop is acting under** (focus-zrs). The same value the
    /// composition root builds from `PriorityHost.activeCommitment`: gate 1 is `commitment != nil`
    /// and every receipt, rule and budget key is `commitment.id`, so a test cannot accidentally
    /// drive a loop that speaks about one thing and writes about another.
    let commitment: ActiveCommitment
    /// The session-lived rule box the host writes "Not this time" into. Exposed because the
    /// rule it writes is keyed on a **priority** as well as a session (focus-lmo).
    let sessionRules: SessionRuleBox
    /// **The session the loop is running inside**, and it was never wired here (focus-rdw).
    ///
    /// `NudgeHost.currentSessionID` answered `nil` in every suite built on this fixture, which
    /// meant every one of them was driving the *no-session* state while asserting on actions
    /// that cannot write in it — `theBadgeRungCarriesItsAnswers` asserted that "Not this time"
    /// and "Pause" were on offer over a loop that could write neither. The fixture states which
    /// state it is in now, and `closeSession()` is how a test asks for the other one.
    /// A box rather than a stored value, because this fixture is a struct and the host reads the
    /// identifier through a closure that has to see a later change.
    @MainActor
    final class OpenSession {
        var identifier: UUID? = UUID(uuidString: "5E551011-0000-4000-8000-000000000001")!
    }

    let session = OpenSession()

    var openSessionID: UUID? { session.identifier }

    /// Drive the supported default state: a priority set and no session open.
    func closeSession() { session.identifier = nil }

    static let decoy = "com.chrismitchelmore.FocusDecoy"
    /// The name each identifier in these suites is known by, and the reason every one of them
    /// differs from its key: a sentence drawing the key is the defect focus-ebv repaired, and a
    /// fixture whose name *equals* its key could not tell the two apart.
    static let displayNames = [
        decoy: "Focus Decoy",
        "com.chrismitchelmore.FocusOtherApp": "Other App",
        "com.example.Reader": "Reader"
    ]
    /// A commitment for the handful of callers that need gate 1 open and never look at the key —
    /// the pure-decider drives, which have no store behind them at all.
    static let anyCommitment = ActiveCommitment(
        id: UUID(uuidString: "A11C0117-0000-4000-8000-000000000001")!,
        intent: "Write the Q3 proposal for Acme"
    )
    static let reference = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01T00:00:00Z

    static var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    /// - Parameter intent: the priority's own sentence. Long values are how these suites build a
    ///   panel whose answers overflow the display: the question renders the task, so a task
    ///   nobody would type produces a real layout that really is out of reach.
    init(intent: String = "Write the Q3 proposal for Acme") throws {
        container = try FocusStore.makeContainer(kind: .inMemory)
        context = container.mainContext
        let dateProvider = FixedDateProvider(now: Self.reference)
        clock = FixedMonotonicClock()
        panel = NudgePanelController()
        menuBar = MenuBarController()
        centre = SilentNotificationCentre()
        workspace = InertReturnWorkspace()

        priorities = PriorityStore(context: context, dateProvider: dateProvider)
        priorityID = try priorities.setPriority(intent: intent)

        ledger = QueryLedger(context: context, dateProvider: dateProvider)
        log = InterventionLog(
            context: context,
            dateProvider: dateProvider,
            calendar: Self.londonCalendar
        )

        sessionRules = SessionRuleBox()
        notifications = NotificationDelivery(centre: centre)
        host = NudgeHost(
            context: context,
            sessionRules: sessionRules,
            panel: panel,
            menuBar: menuBar,
            notifications: notifications,
            workspace: workspace,
            monotonicClock: clock,
            dateProvider: dateProvider,
            calendar: Self.londonCalendar
        )
        // The session identifier the composition root supplies from `SessionHost.snapshot`.
        // Read through `self` so `closeSession()` moves it, exactly as ending a real session does.
        host.currentSessionID = { [session] in session.identifier }
        // The commitment the loop is acting under, as one value — the same shape the composition
        // root builds from `PriorityHost.activeCommitment` (focus-zrs). Captured from the locals
        // rather than from `self`, which is not yet whole.
        let commitment = ActiveCommitment(id: priorityID, intent: intent)
        self.commitment = commitment
        host.surroundings = { [clock] in
            Self.surroundings(monotonic: clock.elapsed, commitment: commitment)
        }
    }

    /// **The menu bar, joined to the loop the way the composition root joins it** (focus-xix).
    ///
    /// `AppComposition.startNudgeLoop()` makes exactly four connections, and a nudge test needs
    /// all four or it is not driving the menu bar at all:
    ///
    /// * `menuBar.onPopoverDidShow` → `NudgeHost.popoverPresented()`, which is the only moment a
    ///   badge nudge of either kind may be counted;
    /// * `menuBar.onGlyphWritten` → `NudgeHost.menuBarItemRedrawn()`, which is the only moment a
    ///   **glyph** rung may be (focus-1b5, focus-nrl). The charge is a consequence of the write;
    /// * `NudgeHost.onQuestionSurfacesChanged` → a redraw, because the popover on screen is a
    ///   hosting controller built from the presentation the menu bar was last handed;
    /// * that redraw taken from the **loop's own projection**, which is what
    ///   `AppComposition.menuBarPresentation()` builds.
    ///
    /// Wired here rather than in each test, because a test that hand-rolled one of the four
    /// would be proving that its own closure ran — the defect `thePopoverWireReachesTheLoop`
    /// used to have.
    func wireMenuBarToTheLoop() throws {
        // **The item goes into the menu bar first, exactly as `startNudgeLoop()` does it**
        // (focus-1b5). It was not, and the omission became load-bearing the moment the charge
        // became a consequence of the write: `MenuBarController.redraw(force:)` refuses to write
        // to an item nobody can see (F-163), so a fixture with no status item drives an app whose
        // menu bar is not there — and the ambient rung, whose entire content is that item,
        // correctly reaches nobody. Every suite that wires the loop is asking for the shipping
        // arrangement, and the shipping arrangement has an item in it.
        try MenuBarStage.install(menuBar)
        menuBar.update(Self.menuBarPresentation(of: host))
        menuBar.onPopoverDidShow = { [host] in host.popoverPresented() }
        // **The wire that makes a charge a consequence of a write** (focus-1b5, focus-nrl). A
        // fixture missing it would drive a menu bar the shipping app does not have: the glyph
        // rung would land, the item would be written, and nothing would ever charge for it.
        menuBar.onGlyphWritten = { [host] in host.menuBarItemRedrawn() }
        host.onQuestionSurfacesChanged = { [host, menuBar] in
            menuBar.update(Self.menuBarPresentation(of: host))
        }
    }

    /// What `AppComposition.menuBarPresentation()` builds, of the parts a nudge test is about.
    static func menuBarPresentation(of host: NudgeHost) -> MenuBarPresentation {
        MenuBarPresentation(
            status: .unrelated,
            snoozes: host.activeSnoozes(),
            pendingQuery: host.pendingPopoverQuery,
            pendingAccusation: host.pendingPopoverAccusation,
            rung: host.currentRung,
            // **Where the rung is, not only what it is called** (focus-mkk). The composition root
            // passes it, so a fixture that did not would be driving a menu bar the shipping app
            // does not have — and the glyph mark, which is the whole of the ambient rung, would
            // be missing from every drive in this package.
            rungSurface: host.landedRungSurface
        )
    }

    /// Take every surface down and the status item out of the menu bar. A test that left one
    /// behind would leave a floating panel on the machine running the gate.
    func tearDown() {
        host.hideOverlays()
        panel.hide()
        menuBar.closePopover()
        menuBar.remove()
        // The activation the stage needed to open a real popover is process-wide state, and it
        // goes back with the surfaces (focus-tzj.5).
        MenuBarStage.restoreActivationPolicy()
    }

    // MARK: - What the world is doing

    static func sensitivity(_ bundle: String) -> SensitiveScreenDecision {
        SensitivityGate().evaluate(
            FrontmostActivation(
                bundleIdentifier: bundle,
                localizedName: bundle,
                pid: 4242,
                at: reference,
                dwellSeconds: 120
            )
        )
    }

    static func surroundings(
        monotonic: Duration,
        commitment: ActiveCommitment?,
        presentation: PresentationState = .notPresenting,
        media: MediaActivity = .idle,
        menuBarVisible: Bool = true,
        quietHours: QuietHours = .off
    ) -> NudgeSurroundings {
        NudgeSurroundings(
            commitment: commitment,
            sensitivity: sensitivity(decoy),
            idle: IdleReading(hardwareSeconds: 0, sessionSeconds: 0),
            idleThresholdSeconds: 120,
            media: media,
            presentation: presentation,
            menuBarVisible: menuBarVisible,
            quietHours: quietHours,
            now: reference,
            calendar: londonCalendar,
            monotonic: monotonic
        )
    }

    // MARK: - A judgement the decider turns into a question

    /// An `uncertain` verdict with a named reason, a subject and enough dwell: U-1's central
    /// case, and the one the decider answers with `.ask`.
    static func uncertainJudgement(
        subject: String?,
        reason: UncertaintyReason = .noNegativeBasis,
        dwelled: Duration = .seconds(120)
    ) -> NudgeJudgement {
        let outcome = ClassificationOutcome(
            verdict: .uncertain, source: .heuristic, confidence: 1, band: .low
        )
        let explanation = Explanation.make(
            stage: .heuristic,
            band: .low,
            clauses: [.insufficientEvidence(reason: reason)],
            stamp: .current
        )
        let eligibility = InterventionEligibility.decide(
            outcome: outcome,
            drift: .aligned,
            phase: .focus,
            status: .uncertain,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: explanation,
            stamp: .current
        )
        return NudgeJudgement(
            outcome: outcome,
            uncertainty: reason,
            subject: subject,
            dwelled: dwelled,
            snapshot: VerdictSnapshot(
                status: .uncertain,
                stage: .heuristic,
                band: nil,
                drift: .aligned,
                eligibility: eligibility,
                explanation: explanation,
                stampKey: EngineStamp.current.cacheKey
            ),
            stamp: .current
        )
    }

    /// An `unrelated` verdict that has been sustained: the input the ladder answers.
    static func unrelatedJudgement(
        subject: String,
        dwelled: Duration = .seconds(180)
    ) -> NudgeJudgement {
        let outcome = ClassificationOutcome(
            verdict: .unrelated, source: .heuristic, confidence: 1, band: .high
        )
        let explanation = Explanation.make(
            stage: .heuristic,
            band: .high,
            clauses: [.sustainedDwell(seconds: 180)],
            stamp: .current
        )
        let drift = DriftState.sustained(
            subject: .single(subject), accumulated: dwelled, isMixed: false
        )
        let eligibility = InterventionEligibility.decide(
            outcome: outcome,
            drift: drift,
            phase: .focus,
            status: .unrelated,
            isUserIdle: false,
            hasActivePriority: true,
            explanation: explanation,
            stamp: .current
        )
        return NudgeJudgement(
            outcome: outcome,
            uncertainty: nil,
            subject: subject,
            dwelled: dwelled,
            snapshot: VerdictSnapshot(
                status: .unrelated,
                stage: .heuristic,
                band: .high,
                drift: drift,
                eligibility: eligibility,
                explanation: explanation,
                stampKey: EngineStamp.current.cacheKey
            ),
            stamp: .current
        )
    }

    /// One turn of the run loop, so AppKit and SwiftUI get theirs.
    ///
    /// The interval between "the app showed the nudge" and "a person looked at it" is exactly
    /// where the defects these suites are about live. `CFRunLoopRunInMode` rather than
    /// `RunLoop.run(until:)` because the latter needs a `Date`, and this is not a question about
    /// the time of day.
    static func settle(_ seconds: Double = 0.3) {
        CFRunLoopRunInMode(.defaultMode, seconds, false)
    }

    // MARK: - Reading the record back

    func interventions() throws -> [FocusSchemaV7.InterventionRecord] {
        try context.fetch(FetchDescriptor<FocusSchemaV7.InterventionRecord>())
    }

    func receipts() throws -> [FocusSchemaV4.AskedQuestion] {
        try ledger.receipts(priorityID: priorityID)
    }
}
