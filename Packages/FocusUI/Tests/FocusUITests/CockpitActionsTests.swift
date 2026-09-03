import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// A `PriorityActing` that writes nothing and remembers everything.
///
/// The cockpit's contract with the rest of the app is this protocol and nothing else (R-24):
/// it renders a `CockpitState` and calls one of these verbs. So the double *is* the store as
/// far as every surface in this package is concerned, and what it records is exactly what the
/// app would have been asked to do.
///
/// The `Verb` enum is the point of the whole file. It has one case per protocol method, and
/// because the double must implement the protocol to compile, a verb added to `PriorityActing`
/// cannot be forgotten: the double stops compiling, gaining the case makes
/// `everyVerbIsReachableFromTheCockpit` fail, and the only way back to green is to give the
/// verb a surface. That is the check that was missing when `editIntent` shipped implemented in
/// `PriorityHost`, declared in the protocol, and reachable from nothing.
@MainActor
final class RecordingPriorityActing: PriorityActing {
    /// One case per verb in `PriorityActing`.
    enum Verb: String, CaseIterable, Sendable {
        case setPriority
        case editIntent
        case editDoneWhen
        case setTimebox
        case activate
        case complete
        case clear
        case addContext
        case removeContext
        case addRule
        case changeRule
        case removeRule
        case acceptHandoff
        case cancelHandoff
        case dismissRitual
        case acknowledgeStoreFailure
    }

    /// One thing the cockpit asked for: which verb, and enough of the payload to tell a
    /// correctly wired surface from a plausibly wired one.
    struct Call: Equatable, Sendable {
        let verb: Verb
        let taskID: UUID?
        let detail: String

        init(_ verb: Verb, taskID: UUID? = nil, detail: String = "") {
            self.verb = verb
            self.taskID = taskID
            self.detail = detail
        }
    }

    private(set) var calls: [Call] = []

    var verbs: [Verb] { calls.map(\.verb) }

    func calls(of verb: Verb) -> [Call] { calls.filter { $0.verb == verb } }

    // MARK: - PriorityActing

    func setPriority(intent: String, doneWhen: String?) {
        calls.append(Call(.setPriority, detail: "\(intent)|\(doneWhen ?? "-")"))
    }

    func editIntent(taskID: UUID, to intent: String) {
        calls.append(Call(.editIntent, taskID: taskID, detail: intent))
    }

    func editDoneWhen(taskID: UUID, to doneWhen: String?) {
        calls.append(Call(.editDoneWhen, taskID: taskID, detail: doneWhen ?? "-"))
    }

    func setTimebox(taskID: UUID, seconds: Int?) {
        calls.append(Call(.setTimebox, taskID: taskID, detail: seconds.map(String.init) ?? "-"))
    }

    func activate(taskID: UUID) {
        calls.append(Call(.activate, taskID: taskID))
    }

    func complete(taskID: UUID, shipped: String?, restartPoint: String?) {
        calls.append(
            Call(.complete, taskID: taskID, detail: "\(shipped ?? "-")|\(restartPoint ?? "-")")
        )
    }

    func clear() {
        calls.append(Call(.clear))
    }

    func addContext(taskID: UUID, item: ContextItemDraft) {
        calls.append(Call(.addContext, taskID: taskID, detail: item.value))
    }

    func removeContext(id: UUID) {
        calls.append(Call(.removeContext, detail: id.uuidString))
    }

    func addRule(
        taskID: UUID,
        scope: PriorityRuleScope,
        subject: String,
        verdict: PriorityRuleVerdict
    ) {
        calls.append(
            Call(
                .addRule,
                taskID: taskID,
                detail: "\(scope.rawValue)|\(subject)|\(verdict.rawValue)"
            )
        )
    }

    func changeRule(id: UUID, verdict: PriorityRuleVerdict) {
        calls.append(Call(.changeRule, detail: "\(id.uuidString)|\(verdict.rawValue)"))
    }

    func removeRule(id: UUID) {
        calls.append(Call(.removeRule, detail: id.uuidString))
    }

    func acceptHandoff(_ request: HandoffRequest) {
        calls.append(Call(.acceptHandoff, detail: request.task))
    }

    func cancelHandoff() {
        calls.append(Call(.cancelHandoff))
    }

    func dismissRitual() {
        calls.append(Call(.dismissRitual))
    }

    func acknowledgeStoreFailure() {
        calls.append(Call(.acknowledgeStoreFailure))
    }
}

/// What the cockpit can actually *do* — as opposed to what it draws.
///
/// The snapshot lane proves the surfaces look right and `TypeHierarchyTests` proves the
/// priority outranks everything on them, but neither can press a button: a SwiftUI view is a
/// struct with no headless way to activate its controls. `CockpitWiring` is the seam that
/// closes that gap — the view draws exactly these closures, and this suite drives exactly
/// these closures through the recording double.
///
/// Three claims, all grant-free and all headless:
///
/// 1. **Every verb is reachable.** Not "most", and not "the ones somebody remembered": the
///    set of verbs the wiring exposes is compared against `PriorityActing`'s whole surface.
/// 2. **Nothing is live without a host.** With no `PriorityActing` attached every verb is
///    `nil`, which is what makes the read-only cockpit read-only rather than merely quiet.
/// 3. **Cancel changes nothing, and Complete waits for nothing.** The two sheet promises
///    F-142 and F-22 are made of.
@Suite("Cockpit actions")
@MainActor
struct CockpitActionsTests {
    // MARK: - Fixtures

    private static let taskID = UUID(uuidString: "E0200000-0000-4000-A000-0000000000A1")!
    private static let contextID = UUID(uuidString: "E0200000-0000-4000-A000-0000000000A2")!
    private static let ruleID = UUID(uuidString: "E0200000-0000-4000-A000-0000000000A3")!
    private static let otherTaskID = UUID(uuidString: "E0200000-0000-4000-A000-0000000000A4")!

    private static func priority(
        intent: String = "Finish and submit the Q3 proposal"
    ) -> PrioritySnapshot {
        PrioritySnapshot(
            id: taskID,
            intent: intent,
            doneWhen: "Legal has replied",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static let handoff = HandoffRequest(
        verb: .start,
        task: "Draft the migration note",
        doneWhen: nil,
        flags: []
    )

    /// Drive every verb the wiring exposes, exactly as the cockpit's surfaces do.
    ///
    /// Deliberately written as a straight-line list rather than a loop: each line is the call
    /// one real surface makes, with the arguments that surface passes, so a wiring member whose
    /// payload is wrong fails on its own assertion below rather than disappearing into a
    /// generic "something was called".
    private static func driveEveryVerb(_ wiring: CockpitWiring) {
        wiring.setPriority?("Ship the migration note", "The note is merged")
        wiring.editIntent?("Finish and submit the Q3 proposal today")
        wiring.editDoneWhen?("Legal has replied in writing")
        wiring.setTimebox?(25 * 60)
        wiring.activate?(otherTaskID)
        wiring.complete?(nil, nil)
        wiring.clear?()
        wiring.addContext?([ContextItemDraft.keyword("proposal")!])
        wiring.removeContext?(contextID)
        wiring.addRule?(.app, "com.apple.Safari", .relevant)
        wiring.changeRule?(ruleID, .unrelated)
        wiring.removeRule?(ruleID)
        wiring.acceptHandoff?(handoff)
        wiring.cancelHandoff?()
        wiring.dismissRitual?()
    }

    // MARK: - Every verb is reachable

    @Test("every PriorityActing verb is reachable from the cockpit")
    func everyVerbIsReachableFromTheCockpit() {
        let host = RecordingPriorityActing()
        let wiring = CockpitWiring(actions: host, priority: Self.priority())

        Self.driveEveryVerb(wiring)

        let reached = Set(host.verbs)
        let declared = Set(RecordingPriorityActing.Verb.allCases)
        #expect(
            reached == declared,
            "unreachable from the cockpit: \(declared.subtracting(reached).map(\.rawValue).sorted())"
        )
        // Each verb once: a wiring member that quietly calls two things would pass the set
        // comparison above.
        #expect(host.calls.count == declared.count)
    }

    @Test("every task-scoped verb names the current priority, not some other task")
    func taskScopedVerbsCarryTheCurrentTask() {
        let host = RecordingPriorityActing()
        let wiring = CockpitWiring(actions: host, priority: Self.priority())

        Self.driveEveryVerb(wiring)

        for verb in [RecordingPriorityActing.Verb.editIntent, .editDoneWhen, .setTimebox,
                     .complete, .addContext, .addRule] {
            let call = host.calls(of: verb).first
            #expect(call?.taskID == Self.taskID, "\(verb.rawValue) named \(String(describing: call?.taskID))")
        }

        // "Work on this again" is the one verb that names a *different* task on purpose: it is
        // how a previous commitment becomes the current one (F-15).
        #expect(host.calls(of: .activate).first?.taskID == Self.otherTaskID)
    }

    @Test("the payloads arrive as typed, not as approximations")
    func payloadsArriveIntact() {
        let host = RecordingPriorityActing()
        let wiring = CockpitWiring(actions: host, priority: Self.priority())

        Self.driveEveryVerb(wiring)

        #expect(host.calls(of: .setPriority).first?.detail == "Ship the migration note|The note is merged")
        #expect(host.calls(of: .editIntent).first?.detail == "Finish and submit the Q3 proposal today")
        #expect(host.calls(of: .editDoneWhen).first?.detail == "Legal has replied in writing")
        #expect(host.calls(of: .setTimebox).first?.detail == "1500")
        #expect(host.calls(of: .addContext).first?.detail == "proposal")
        #expect(host.calls(of: .addRule).first?.detail == "app|com.apple.Safari|relevant")
        #expect(host.calls(of: .changeRule).first?.detail == "\(Self.ruleID.uuidString)|unrelated")
        #expect(host.calls(of: .acceptHandoff).first?.detail == Self.handoff.task)
    }

    @Test("the context pack adds every dropped item, in the order they arrived")
    func contextAddsEveryDraft() {
        let host = RecordingPriorityActing()
        let wiring = CockpitWiring(actions: host, priority: Self.priority())

        wiring.addContext?([
            ContextItemDraft.keyword("proposal")!,
            ContextItemDraft.domain(origin: "https://docs.google.com")!
        ])

        #expect(host.calls(of: .addContext).map(\.detail) == ["proposal", "https://docs.google.com"])
    }

    // MARK: - Nothing is live without a host

    @Test("the read-only cockpit exposes no verb at all")
    func readOnlyCockpitHasNoVerbs() {
        let wiring = CockpitWiring(actions: nil, priority: Self.priority())

        #expect(wiring.setPriority == nil)
        #expect(wiring.editIntent == nil)
        #expect(wiring.editDoneWhen == nil)
        #expect(wiring.setTimebox == nil)
        #expect(wiring.activate == nil)
        #expect(wiring.complete == nil)
        #expect(wiring.clear == nil)
        #expect(wiring.addContext == nil)
        #expect(wiring.removeContext == nil)
        #expect(wiring.addRule == nil)
        #expect(wiring.changeRule == nil)
        #expect(wiring.removeRule == nil)
        #expect(wiring.acceptHandoff == nil)
        #expect(wiring.cancelHandoff == nil)
        #expect(wiring.dismissRitual == nil)
    }

    @Test("with no priority, no verb can name a task")
    func taskScopedVerbsAreAbsentWithoutAPriority() {
        let host = RecordingPriorityActing()
        let wiring = CockpitWiring(actions: host, priority: nil)

        // Nothing to mutate yet.
        #expect(wiring.editIntent == nil)
        #expect(wiring.editDoneWhen == nil)
        #expect(wiring.setTimebox == nil)
        #expect(wiring.complete == nil)
        #expect(wiring.addContext == nil)
        #expect(wiring.addRule == nil)

        // Still available: an empty cockpit's whole job is to take the first sentence, and a
        // previous commitment can always be picked back up.
        #expect(wiring.setPriority != nil)
        #expect(wiring.activate != nil)
        #expect(wiring.clear != nil)
        #expect(wiring.cancelHandoff != nil)
        #expect(wiring.dismissRitual != nil)
    }

    // MARK: - Correcting the sentence in place (F-02)

    @Test("an in-place correction writes only when the words actually changed")
    func correctionRulesHold() {
        let intent = "Finish and submit the Q3 proposal"

        #expect(CockpitWiring.correction("Finish and submit the Q3 proposal today", replacing: intent)
            == "Finish and submit the Q3 proposal today")
        // Trimmed, because trailing whitespace is not a revision.
        #expect(CockpitWiring.correction("  \(intent) today  ", replacing: intent) == "\(intent) today")
        // Unchanged: no write, so no undo step that undoes nothing.
        #expect(CockpitWiring.correction(intent, replacing: intent) == nil)
        #expect(CockpitWiring.correction("  \(intent)  ", replacing: intent) == nil)
        // Emptied: a slip, not an instruction to erase the commitment.
        #expect(CockpitWiring.correction("", replacing: intent) == nil)
        #expect(CockpitWiring.correction("   \n  ", replacing: intent) == nil)
    }

    @Test("correcting the wording is a different verb from replacing the priority")
    func correctingIsNotReplacing() {
        let host = RecordingPriorityActing()
        let wiring = CockpitWiring(actions: host, priority: Self.priority())

        wiring.editIntent?("Finish and submit the Q3 proposal today")

        // The distinction is the whole reason both verbs exist: `setPriority` starts a new
        // commitment and pushes this one into history, `editIntent` keeps the task — and with
        // it the context pack, the rules and the timebox — one revision later.
        #expect(host.verbs == [.editIntent])
        #expect(host.calls(of: .setPriority).isEmpty)
    }

    // MARK: - The handoff sheet (F-142)

    @Test("the handoff sheet's Cancel calls nothing that could change the store")
    func handoffCancelCallsNothing() {
        let host = RecordingPriorityActing()
        let wiring = CockpitWiring(actions: host, priority: Self.priority())
        let sheet = HandoffConfirmationSheet(
            request: Self.handoff,
            current: Self.priority(),
            replace: { wiring.acceptHandoff?(Self.handoff) },
            cancel: { wiring.cancelHandoff?() }
        )

        sheet.cancel()

        // `cancelHandoff` drops the pending request and touches nothing else; it is the one
        // thing Cancel is allowed to do.
        #expect(host.verbs == [.cancelHandoff])
        #expect(host.calls(of: .acceptHandoff).isEmpty)
        #expect(host.calls(of: .setPriority).isEmpty)
    }

    @Test("the handoff sheet's Replace is the only route from a URL to a mutation")
    func handoffReplaceIsTheOnlyMutatingRoute() {
        let host = RecordingPriorityActing()
        let wiring = CockpitWiring(actions: host, priority: Self.priority())
        let sheet = HandoffConfirmationSheet(
            request: Self.handoff,
            current: Self.priority(),
            replace: { wiring.acceptHandoff?(Self.handoff) },
            cancel: { wiring.cancelHandoff?() }
        )

        // The other half of the previous test: Cancel calling nothing would prove little if
        // the sheet's other button called nothing either.
        sheet.replace()

        #expect(host.verbs == [.acceptHandoff])
        #expect(host.calls(of: .acceptHandoff).first?.detail == Self.handoff.task)
    }

    // MARK: - The completion sheet (F-22)

    @Test("Complete is enabled with both reflection fields empty")
    func completeIsEnabledWithEmptyFields() {
        #expect(CompletionSheet.isCompleteEnabled(shipped: "", restartPoint: ""))

        // And with every other combination of empty, blank and written-in: reflection is
        // offered, never extracted, so there is no state of these two fields that withholds
        // the button (acceptance criterion 21).
        for shipped in ["", "   ", "The note is merged"] {
            for restartPoint in ["", "\n ", "Pick up at the migration test"] {
                #expect(
                    CompletionSheet.isCompleteEnabled(shipped: shipped, restartPoint: restartPoint),
                    "Complete was withheld for \(shipped.debugDescription)/\(restartPoint.debugDescription)"
                )
            }
        }
    }

    @Test("an empty reflection field is stored as an absent answer, not as an empty string")
    func emptyReflectionIsAbsent() {
        let empty = CompletionSheet.reflection(shipped: "", restartPoint: "  \n ")
        #expect(empty.shipped == nil)
        #expect(empty.restartPoint == nil)

        let written = CompletionSheet.reflection(
            shipped: "  The note is merged  ",
            restartPoint: "Pick up at the migration test"
        )
        #expect(written.shipped == "The note is merged")
        #expect(written.restartPoint == "Pick up at the migration test")
    }

    @Test("completing with both fields empty reaches the host with two absent answers")
    func completingEmptyReachesTheHost() {
        let host = RecordingPriorityActing()
        let wiring = CockpitWiring(actions: host, priority: Self.priority())
        let sheet = CompletionSheet(
            intent: Self.priority().intent,
            complete: { shipped, restartPoint in wiring.complete?(shipped, restartPoint) },
            cancel: {}
        )

        let reflection = CompletionSheet.reflection(shipped: "", restartPoint: "")
        sheet.complete(reflection.shipped, reflection.restartPoint)

        #expect(host.verbs == [.complete])
        #expect(host.calls(of: .complete).first?.taskID == Self.taskID)
        #expect(host.calls(of: .complete).first?.detail == "-|-")
    }

    @Test("the completion sheet's Cancel finishes nothing")
    func completionCancelFinishesNothing() {
        let host = RecordingPriorityActing()
        var cancelled = false
        let sheet = CompletionSheet(
            intent: Self.priority().intent,
            complete: { _, _ in Issue.record("Cancel completed the priority") },
            cancel: { cancelled = true }
        )

        sheet.cancel()

        #expect(cancelled)
        #expect(host.calls.isEmpty)
    }
}
