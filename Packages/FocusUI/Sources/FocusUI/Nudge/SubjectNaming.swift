import FocusCore
import Foundation

/// **Where a nudge learns what to call the application it is about** (focus-ebv, R-88).
///
/// ## Why this is the same seam "Back to …" already uses
///
/// The app had the name and used it three feet away: `ReturnToTask.target(anchor:workspace:)`
/// asks `ReturnWorkspace.localizedNameOfRunningApplication(_:)` and gets *"Pages"*, which is why
/// the accusation panel read *"Back to Pages"* directly under *"com.apple.Safari, 12 minutes."*
/// One panel, one kind of thing, two names for it. So this asks the **same protocol** the same
/// question rather than reaching for `NSRunningApplication` a second time: one seam, one fake in
/// the unit lane, and no second place the answer could differ.
///
/// It is also why this lives in `FocusUI` beside `ReturnToTask` rather than in the decision
/// module. `FocusCore/Nudge` decides *whether to speak* and holds no AppKit at all
/// (`check-boundaries.sh`, R-96k); the naming policy that does not need the world is on
/// `NudgeSubject` there, and only the lookup is here.
///
/// ## The name is learned once and kept for the session
///
/// A nudge surface is deliberately sticky — `hidesOnDeactivate` is `false` (R-89) — so a panel
/// raised about Safari is still on screen after somebody quits Safari, and a snooze on it is
/// still listed in the popover for its whole span. Re-asking the workspace on every redraw would
/// let a live panel change its own sentence from *"Safari"* to *"com.apple.Safari"* underneath
/// the person, and the popover's snooze row would do it once a second beside a ticking
/// countdown.
///
/// So a name that was true when the nudge was raised stays the name for the rest of the session.
/// The memo is per-process and dies with it, exactly as the ladder, the fatigue runs and the
/// snooze book do — a name cached across a relaunch would outlive the application it describes.
///
/// ## What it does when there is no name to be had
///
/// Two questions, in order, and then the key. **Is it running?** — the localised name, memoised.
/// **Is it installed?** — the name the bundle on the disk declares (focus-7gc). Only when both
/// answer nothing does `NudgeSubject` fall back to the identifier, and this type does not cache
/// that fallback. An application that was asked about before it finished launching is asked about
/// again next time, and answers with its real name.
@MainActor
public final class SubjectNaming {
    private let workspace: any ReturnWorkspace
    /// Identifier → the name the workspace gave for it, the first time it gave one.
    private var learned: [String: String] = [:]

    public init(workspace: any ReturnWorkspace) {
        self.workspace = workspace
    }

    /// The subject a question is about. **Total**, because `QuerySubject.identifier` is
    /// non-empty by construction — which is what keeps `QueryPresentation.subject`
    /// non-optional (R-76.2).
    public func subject(of query: QuerySubject) -> NudgeSubject {
        NudgeSubject.of(query, runningName: name(for: query.identifier))
    }

    /// The subject an accusation or a snooze is about, or `nil` when there is nobody to name —
    /// drift that accumulated across several applications carries `""` and must go on naming
    /// nobody rather than being given a name here.
    public func subject(_ identifier: String?) -> NudgeSubject? {
        guard let identifier else { return nil }
        return NudgeSubject.named(identifier, runningName: name(for: identifier))
    }

    /// What the workspace calls this identifier, or `nil` when it has nothing to say.
    ///
    /// An origin is never asked about: no application owns `https://docs.google.com`, so a
    /// lookup could only ever return a browser's name for a site, and `NudgeSubject` derives the
    /// host instead.
    ///
    /// **A subject that is not running is still asked about** (focus-7gc). The memo above covers
    /// the ordinary case — a name learned while the panel was raised outlives the application it
    /// describes — but it only ever holds a name somebody once looked up *while it was running*,
    /// and the first look does not always happen then: the snooze row's own comment says a snooze
    /// outlives its application far more often than a panel does. So the disk is asked second,
    /// through the same seam `ReturnToTask` asks. Without it the panel could say
    /// *"You've been in com.figma.Desktop"* directly above a button reading *"Back to Pages"* —
    /// which is focus-ebv's defect again, with the halves swapped.
    private func name(for identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !NudgeSubject.isOrigin(trimmed) else { return nil }
        if let learnt = learned[trimmed] { return learnt }

        if let usable = NudgeSubject.nameable(
            workspace.localizedNameOfRunningApplication(trimmed)
        ) {
            learned[trimmed] = usable
            return usable
        }

        // Installed but not running. **Deliberately not memoised**: the memo exists to stop a
        // live surface changing its own sentence, and this answer cannot change one — it is read
        // from a bundle that is sitting still. Leaving it out keeps the promise the memo's own
        // doc makes, that an application asked about before it finished launching is asked again
        // and answers with its running name.
        guard let url = workspace.applicationURL(for: trimmed) else { return nil }
        return NudgeSubject.nameable(workspace.applicationName(at: url))
    }
}
