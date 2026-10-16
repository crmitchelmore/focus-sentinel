import FocusCore
import Foundation

/// Every verb the cockpit can perform, in one place.
///
/// `CockpitView` hands each of its sub-surfaces a closure; each of those closures is one call
/// into `PriorityActing`. Written inline they were unreachable from a test — a SwiftUI view is
/// a struct with no way to press its buttons headlessly — so the wiring lives here, the view
/// draws it, and `CockpitActionsTests` drives the same values the view does through a
/// recording double. A verb that no surface reaches is then a failing test rather than a
/// promise nobody kept, which is exactly what happened to `editIntent`.
///
/// Two rules the shape enforces on every verb:
///
/// * **No host, no closure.** With `actions == nil` every member is `nil`, and every control
///   in the cockpit is drawn disabled or not drawn at all. A button that looks live and does
///   nothing is worse than one that is visibly unavailable — and the snapshot lane renders
///   precisely that read-only cockpit.
/// * **No priority, no task-scoped verb.** The verbs that name a task are `nil` until there
///   is one, so a surface cannot be wired to mutate a commitment that does not exist.
///
/// It is a value, rebuilt on every render, and holds nothing but the two things it is given.
/// `@MainActor` because `PriorityActing` is: every verb the cockpit performs runs where the
/// store and the undo journal live.
@MainActor
struct CockpitWiring {
    /// The mutation host, or `nil` for the read-only cockpit.
    let actions: (any PriorityActing)?
    /// The current commitment, or `nil` when nothing has been committed to.
    let priority: PrioritySnapshot?

    init(actions: (any PriorityActing)?, priority: PrioritySnapshot?) {
        self.actions = actions
        self.priority = priority
    }

    // MARK: - Capture

    func showsCapture(requestedFor taskID: UUID?) -> Bool {
        actions != nil && (priority == nil || (taskID != nil && taskID == priority?.id))
    }

    /// **The person has read the sheet that says nothing will be saved** (focus-tzj.4).
    ///
    /// `nil` for the read-only cockpit, like every other verb here — a surface with no host has
    /// nothing to acknowledge to.
    var acknowledgeStoreFailure: (() -> Void)? {
        actions.map { host in { host.acknowledgeStoreFailure() } }
    }

    /// Commit a sentence: a new priority, replacing whatever was there (F-02, F-07).
    var setPriority: ((String, String?) -> Void)? {
        actions.map { host in { intent, doneWhen in host.setPriority(intent: intent, doneWhen: doneWhen) } }
    }

    /// Fix the wording of the *same* commitment (F-02). Distinct from `setPriority`, which
    /// starts a new one: this keeps the task, its context pack and its rules, and bumps its
    /// revision. An empty edit is not a verb — the caller drops it rather than erasing a
    /// commitment with an empty string.
    /// A new priority that keeps this one's desk (focus-1rj7). `nil` without a priority: there
    /// is no desk to keep, and the plain `setPriority` is the verb for that.
    var setPriorityKeepingContext: ((String, String?) -> Void)? {
        guard let actions, let priority else { return nil }
        return { intent, doneWhen in
            actions.setPriority(intent: intent, doneWhen: doneWhen, keepingContextOf: priority.id)
        }
    }

    var editIntent: ((String) -> Void)? {
        guard let actions, let priority else { return nil }
        return { intent in actions.editIntent(taskID: priority.id, to: intent) }
    }

    func autosaveIntent(_ draft: String) {
        // This closure may outlive its snapshot; the store, not that snapshot, skips no-op saves.
        guard let corrected = Self.correction(draft, replacing: nil) else { return }
        editIntent?(corrected)
    }

    /// What an in-place correction of the sentence is worth writing, if anything.
    ///
    /// Two things are deliberately *not* verbs. An emptied field is a slip, not an instruction
    /// to erase the commitment — the store has `clear()` for putting a priority down, and it
    /// does not work by deleting the words. And a sentence that came back unchanged writes
    /// nothing, because an undo step that undoes nothing is a step the user has to take twice
    /// before anything happens.
    ///
    /// `nonisolated` and `static`: it is a rule about two strings, and keeping it here rather
    /// than inside the view is what lets it be held to.
    nonisolated static func correction(_ draft: String, replacing intent: String?) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != intent else { return nil }
        return trimmed
    }

    /// **The definition of done the read-only cockpit has anything to say about** (focus-0ai).
    ///
    /// `nil` when there is nothing written down, which includes a stored value that is only
    /// whitespace — a person who typed a space and moved on has not defined done, and drawing a
    /// caption over a blank line tells them the app is holding something it is not. `NudgeSubject`
    /// states the doctrine: *"a nudge that renders an empty string is worse than one that renders
    /// an identifier — the empty string is a bug the person is asked to answer."*
    ///
    /// Deliberately **not** used by the editable branch. There the caption is a control's label
    /// and the emptiness is answered by the field's own prompt, so the section is drawn whether
    /// or not there is a value in it. Two branches, one of which has a place to put the answer;
    /// this is the rule for the one that does not.
    ///
    /// `nonisolated` and `static` for `correction(_:replacing:)`'s reason: it is a rule about a
    /// string, and holding it here is what lets a test hold it.
    nonisolated static func doneWhenToDraw(_ stored: String?) -> String? {
        guard let stored else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : stored
    }

    /// Set or clear the definition of done (F-08).
    var editDoneWhen: ((String?) -> Void)? {
        guard let actions, let priority else { return nil }
        return { doneWhen in actions.editDoneWhen(taskID: priority.id, to: doneWhen) }
    }

    // MARK: - The priority itself

    /// Set or clear the timebox, in seconds (F-12).
    var setTimebox: ((Int?) -> Void)? {
        guard let actions, let priority else { return nil }
        return { seconds in actions.setTimebox(taskID: priority.id, seconds: seconds) }
    }

    /// "Work on this again" (F-15): re-point at an existing task, which brings its stored
    /// context pack back by construction rather than by copying it.
    var activate: ((UUID) -> Void)? {
        actions.map { host in { id in host.activate(taskID: id) } }
    }

    /// Finish it (F-22). Both reflection fields are optional and completion never waits.
    var complete: ((String?, String?) -> Void)? {
        guard let actions, let priority else { return nil }
        return { shipped, restartPoint in
            actions.complete(taskID: priority.id, shipped: shipped, restartPoint: restartPoint)
        }
    }

    /// Put the priority down without completing or deleting anything.
    var clear: (() -> Void)? {
        actions.map { host in { host.clear() } }
    }

    // MARK: - The context pack (F-09)

    var addContext: (([ContextItemDraft]) -> Void)? {
        guard let actions, let priority else { return nil }
        return { drafts in
            for draft in drafts { actions.addContext(taskID: priority.id, item: draft) }
        }
    }

    /// Remove one item, and only ever because the user said so — a missing file stays on the
    /// board with a Locate… action (R-22).
    var removeContext: ((UUID) -> Void)? {
        actions.map { host in { id in host.removeContext(id: id) } }
    }

    // MARK: - Per-task rules (F-11)

    var addRule: ((PriorityRuleScope, String, PriorityRuleVerdict) -> Void)? {
        guard let actions, let priority else { return nil }
        return { scope, subject, verdict in
            actions.addRule(taskID: priority.id, scope: scope, subject: subject, verdict: verdict)
        }
    }

    var changeRule: ((UUID, PriorityRuleVerdict) -> Void)? {
        actions.map { host in { id, verdict in host.changeRule(id: id, verdict: verdict) } }
    }

    var removeRule: ((UUID) -> Void)? {
        actions.map { host in { id in host.removeRule(id: id) } }
    }

    // MARK: - The handoff (F-142)

    /// Accept an incoming `focus://` handoff. Reachable from exactly one control in the whole
    /// app: the confirmation sheet's Replace button.
    var acceptHandoff: ((HandoffRequest) -> Void)? {
        actions.map { host in { request in host.acceptHandoff(request) } }
    }

    /// Dismiss the pending handoff, changing nothing. Cancel, Escape and dismissing the sheet
    /// by any other route all land here.
    var cancelHandoff: (() -> Void)? {
        actions.map { host in { host.cancelHandoff() } }
    }

    // MARK: - The daily ritual (F-19)

    /// Answering *or* dismissing writes the day key, so the banner asks once (R-28).
    var dismissRitual: (() -> Void)? {
        actions.map { host in { host.dismissRitual() } }
    }
}
