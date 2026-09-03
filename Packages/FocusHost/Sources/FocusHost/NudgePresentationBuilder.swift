import FocusCore
import FocusUI
import Foundation

/// **What a surface is told to draw** (focus-lmo, focus-xix, focus-rdw, focus-zrs, focus-tzj.6).
///
/// One builder, so the panel, the badge and anything that asks *which corrections is this nudge
/// offering* read the same answer. It is the reading `NudgeHost.resolve(_:snoozeDuration:)` has to
/// agree with: an action this does not offer is one the loop must refuse, and a test that derived
/// the expected list for itself would be a proof that agrees with itself rather than with the app.
///
/// A value built for one read, from what the host is holding at that moment, so that nothing here
/// can take a second reading of anything. That is the defect this shape exists against: both
/// presentations used to read the live surroundings — `activeCommitment()?.intent ?? ""` — at
/// redraw time, so the badge could draw a question under a task the receipt will not be keyed to,
/// and every redraw of an open popover re-ran a guard that answered `nil` once the commitment went
/// away, emptying a live nudge's answers under the person's cursor. The commitment a nudge was
/// raised with is carried **in**, by the caller that is holding it.
///
/// It builds a question's presentation and a rung's, and it can build neither into the other: it
/// takes a `QueryWarrant` for one and a `LadderRung` for the other, constructs neither, and there
/// is no path from one to the other in the type of anything here (R-96b, R-96c, R-96d).
@MainActor
struct NudgePresentationBuilder {
    /// The deck the person chose. Read once by the caller, so the two halves of one redraw cannot
    /// speak in two voices.
    let voice: NudgeVoice

    /// **What the app calls the thing it is nudging about** (focus-ebv). The memo, not a second
    /// lookup: a sticky panel and a running snooze keep the name they were raised with.
    let naming: SubjectNaming

    /// Where "Back to what I was doing" would go, and the workspace that resolves it.
    let returnAnchor: String?
    let workspace: any ReturnWorkspace

    /// What is snoozed, and the clock the countdown is read against.
    let snoozes: SnoozeBook
    let monotonicClock: any MonotonicClock

    /// **Whether the two session-scoped actions have anything to act on** (focus-rdw). Evaluated
    /// only where it is drawn, so a question's redraw asks nothing of the session host.
    let hasOpenSession: @MainActor () -> Bool

    /// The question one surface is drawing, under the commitment it was asked beneath.
    func query(_ warrant: QueryWarrant, under commitment: ActiveCommitment) -> QueryPresentation {
        QueryPresentation(
            voice: voice,
            // **The commitment this question was asked under, carried on it** (focus-lmo,
            // focus-xix). It was `activeCommitment()?.intent ?? ""` — a live reading taken at
            // redraw time, so the popover could draw the question under a task the receipt will
            // not be keyed to, or under no task at all.
            task: commitment.intent,
            subject: naming.subject(of: warrant.subject),
            reason: warrant.reason,
            dwelled: warrant.dwelled
        )
    }

    /// The rung one surface is drawing, under the commitment it was raised beneath.
    func accusation(for rung: LadderRung, commitment: ActiveCommitment) -> AccusationPresentation {
        let target = ReturnToTask.target(anchor: returnAnchor, workspace: workspace)
        // **The rung's key, and the name that key is known by** (focus-ebv). Both come off the
        // one value: the snooze below is looked up by `subject.identifier`, exactly as it was,
        // and only the panel's body line reads the other half. `rung.subject` is already `nil`
        // for mixed drift, so an accusation that names nobody goes on naming nobody.
        let subject = naming.subject(rung.subject)
        return AccusationPresentation(
            rung: rung.kind,
            voice: voice,
            // The commitment the rung was raised under, carried in — so the sentence on the panel
            // names the task the click will be written against (focus-zrs, focus-lmo).
            task: commitment.intent,
            subject: subject,
            dwelled: rung.mandate.sustainedFor,
            returnTarget: target?.displayName,
            snoozeRemaining: subject.flatMap { snoozes.snooze(for: $0.identifier) }?
                .remaining(at: monotonicClock.elapsed),
            // **Whether the two session-scoped actions have anything to act on** (focus-rdw).
            // The same wire `apply(_:…)` reads before writing a session rule, asked *before* the
            // buttons are drawn rather than after one is pressed: an action that would be dropped
            // in a `guard` is an action this panel must not offer.
            hasOpenSession: hasOpenSession()
        )
    }
}
