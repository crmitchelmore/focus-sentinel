import Foundation

/// **Everything the cockpit scene hands the cockpit view, as one value** (focus-2er).
///
/// ## Why this type exists
///
/// The scene used to pass five separate arguments, each read straight off the composition root:
/// the state, the two mutation hosts, the elapsed figure and the last foreign bundle identifier.
/// `App/` is not a package, so no test bundle can reach that call — and each argument was
/// independently guttable with a one-line, compiling no-op. Replacing `composition.cockpitState`
/// with `CockpitState()` froze the whole window into a placeholder: no priority, no session, no
/// recents, no verdict, no capabilities, no handoff sheet. The nineteen-stage gate stayed at
/// PASS with an empty diff of its ok-assertions.
///
/// Bundling them does two things, and neither is tidiness.
///
/// * **It moves the five reads into `FocusHost`**, where `AppComposition.cockpitConnection()` is
///   an ordinary function a test can call and assert field by field. A mutation to any one of
///   them is now a mutation to package code with a test target over it.
/// * **It leaves one wire in `App/`, and that wire cannot be gutted with a placeholder.** There
///   is no `CockpitConnection` a scene can fabricate: it needs a `PriorityActing` and a
///   `SessionActing`, and the shipping graph contains exactly one of each, both owned by the
///   composition root. A mutant would have to write conforming types rather than delete a call.
///
/// ## `didRender`, and why a value type carries a closure
///
/// The remaining hole is a mutant that calls the verb and then hands the view something else. So
/// the receipt is taken **at the far end**: `CockpitView.body` calls `didRender()`, which is the
/// composition root's own closure, and `--focus-self-check` reports which wires it has heard
/// from. A connection that never reached a view body says nothing, and a fabricated connection
/// carries somebody else's closure. The receipt names *which* wire; the live projections beside
/// it in the report say *whether* it carried anything.
///
/// ## `didDraw`, and why `didRender` was not enough (focus-h7h)
///
/// It was not enough, and the measurement is unambiguous. A mutant that kept **every** receipt
/// firing and replaced only the values — this type rebuilt field by field from the live one, with
/// `state:` a placeholder and `sessionElapsedSeconds:` `nil` — passed the whole nineteen-stage
/// gate: 262 ok-assertions against 262, and an empty diff between the clean run's assertion list
/// and the mutant's. A receipt that fires when a closure runs cannot distinguish a closure that
/// produced the right value from one that produced a constant.
///
/// So the view reports the **values it drew**, through the preference channel
/// `ShellRenderedValuesKey` — the mechanism `DecisionSurfaceReachability` already proved on the
/// nudge panel — and `didDraw` is where they arrive. The composition root records what it put in
/// this connection at the moment it built it, and compares. `generation` is what makes the
/// comparison exact rather than a race against the wall clock: it is *what I handed you* against
/// *what you drew*, not two reads taken a second apart.
@MainActor
public struct CockpitConnection {
    /// **Which issue of this connection the window is drawing from** (focus-h7h).
    ///
    /// Stamped by `AppComposition`, injected into the view's environment, and carried back in
    /// every reported value. Two jobs, both taken from `NudgeActionFrameSet.generation`: it makes
    /// two identical layouts two distinguishable readings, so a window drawn twice with the same
    /// content is not silently dropped by `onPreferenceChange`; and a report stamped with an
    /// issue the root has already replaced is a window drawing from something stale, which is its
    /// own defect and is legible as one.
    public let generation: Int

    /// Everything the window draws.
    public let state: CockpitState

    /// The mutation host, or `nil` for the read-only cockpit the snapshot lane renders.
    public let actions: (any PriorityActing)?

    /// The session host, or `nil` when none is attached.
    public let sessionActions: (any SessionActing)?

    /// How long the open session has been running on the wall clock, read by whoever owns the
    /// injected clock. `nil` when there is no session.
    public let sessionElapsedSeconds: Double?

    /// The last application in front that was not this one (F-101).
    public let lastActiveBundleID: String?

    /// **What the footer's one-time launch-at-login offer performs** (D-12, focus-odz.4).
    ///
    /// A closure rather than a verb on `PriorityActing`, and the division is the one that type's
    /// name states: `PriorityActing` is what a person does to their *commitment*, and adding a
    /// login-item verb to it would put a platform registration in the protocol every priority
    /// double in the programme has to implement. This is one sink, on the value the composition
    /// root already assembles, reached only by a click — which is why it is exempted as a sink in
    /// the totality table and driven by the self-check rather than drawn.
    public let onLaunchAtLoginOffer: @MainActor (LaunchAtLoginOfferAction) -> Void

    /// **What the first-run explanation's one button performs** (focus-odz.7). A sink for
    /// `onLaunchAtLoginOffer`'s reason and driven the same way: only a click reaches it.
    public let onFirstRunExplanationDismissed: @MainActor () -> Void
    /// **What the walkthrough sheet's Continue performs after closing it** (focus-u6de): the
    /// composition root opens the floating tour beside the cockpit. A sink like the one above,
    /// for its reason; driven by `WalkthroughTourTests` rather than clicked.
    public let onWalkthroughContinued: @MainActor () -> Void

    /// Called from the view's body: the far end of the one wire this type leaves in `App/`.
    ///
    /// Idempotent by construction — the composition root records it in a `Set` — so a body
    /// SwiftUI evaluates many times reports the same fact many times and changes nothing.
    public let didRender: @MainActor () -> Void

    /// **What the window put on the screen**, delivered from the preference channel every
    /// reporting site below `CockpitView` publishes into (focus-h7h).
    ///
    /// Separate from `didRender` because the two answer different questions and both are needed:
    /// the receipt says the body ran, and this says what the body drew. A no-op default, like
    /// `didRender`'s, so the snapshot lane and the previews report to nobody — which is right,
    /// because nothing is claiming anything about a layout that is not in the app.
    public let didDraw: @MainActor (ShellRenderedValues) -> Void

    public init(
        state: CockpitState,
        actions: (any PriorityActing)?,
        sessionActions: (any SessionActing)?,
        sessionElapsedSeconds: Double?,
        lastActiveBundleID: String?,
        onLaunchAtLoginOffer: @escaping @MainActor (LaunchAtLoginOfferAction) -> Void = { _ in },
        onFirstRunExplanationDismissed: @escaping @MainActor () -> Void = {},
        onWalkthroughContinued: @escaping @MainActor () -> Void = {},
        generation: Int = 0,
        didRender: @escaping @MainActor () -> Void = {},
        didDraw: @escaping @MainActor (ShellRenderedValues) -> Void = { _ in }
    ) {
        self.state = state
        self.actions = actions
        self.sessionActions = sessionActions
        self.sessionElapsedSeconds = sessionElapsedSeconds
        self.lastActiveBundleID = lastActiveBundleID
        self.onLaunchAtLoginOffer = onLaunchAtLoginOffer
        self.onFirstRunExplanationDismissed = onFirstRunExplanationDismissed
        self.onWalkthroughContinued = onWalkthroughContinued
        self.generation = generation
        self.didRender = didRender
        self.didDraw = didDraw
    }
}

/// **Every field of this connection, bound to the receipt that echoes it** (focus-7ow).
///
/// Nothing here is optional and nothing is defaulted: `ShellConnectionTotality` walks the type
/// with `Mirror` and a property with no entry in this table is a **failure**, whatever anybody
/// intended. That is the whole difference between this and the enumeration it replaces — round 4
/// listed the nine values a known mutant touched, and round 5's residue mutant lied about four
/// more that nobody had thought of. This table cannot fail to think of a field, because it is
/// checked against the type rather than against a memory of it.
///
/// `state` descends: the cockpit draws its members one at a time — the footer's store line, the
/// ritual banner, the recents list — so a receipt for "the state" as one blob would be satisfied
/// by a window that drew nine of eleven fields correctly and lied about two.
extension CockpitConnection: ShellDrawnConnection {
    public nonisolated static var connectionName: String { "CockpitConnection" }

    public nonisolated static var fieldEchoes: [String: ShellFieldEcho] {
        [
            "generation": .undrawn(.generation),
            "state": .composite,
            // Both hosts decide whether every control in the window is live or disabled, and one
            // field reports the pair: a cockpit handed neither looks finished and does nothing.
            "actions": .drawn([.mutationHostsAttached]),
            "sessionActions": .drawn([.mutationHostsAttached]),
            "sessionElapsedSeconds": .drawn([.sessionElapsedSeconds]),
            "lastActiveBundleID": .drawn([.lastActiveApp]),
            "onLaunchAtLoginOffer": .undrawn(.sink),
            "onFirstRunExplanationDismissed": .undrawn(.sink),
            "onWalkthroughContinued": .undrawn(.sink),
            "didRender": .undrawn(.receipt),
            "didDraw": .undrawn(.receipt),

            "state.status": .drawn([.status]),
            // **Two facts where there was one** (focus-tzj.4). `storeIsReady` was a stored flag
            // that the store never opening and a write being refused were both OR-ed into; it is
            // a derived reading now, and these are the two fields it is derived from. Both reach
            // the footer's one line, which says which of the three states the store is in.
            "state.storeOpened": .drawn([.storeStatus]),
            "state.lastWriteFailed": .drawn([.storeStatus]),
            // Drawn by the sheet the cockpit raises when the store did not open, which is a
            // presentation rather than a label in the window — so there is no receipt site for
            // it here, and saying so is the exemption.
            "state.storeFailureAcknowledged": .undrawn(.notDrawnOnThisSurface),
            "state.storeLocation": .undrawn(.notDrawnOnThisSurface),
            // The cockpit's footer draws `sensing`; this flag reaches no label in the window.
            // Written down as an exemption rather than left unlisted, because unlisted is a
            // failure and an exemption is a diff somebody can argue with.
            "state.isObservingActivity": .undrawn(.notDrawnOnThisSurface),
            "state.priority": .drawn([.priorityIntent, .priorityDoneWhen, .priorityDetail]),
            "state.recent": .drawn([.recentCount, .recentDigest]),
            "state.pendingHandoff": .drawn([.handoffTask, .handoffDetail]),
            "state.showsRitualPrompt": .drawn([.ritualBanner]),
            "state.session": .drawn([.sessionPhase, .sessionDetail]),
            "state.sensing": .drawn([.sensingSummary, .sensingDetail]),
            // e04's verdict inspector is a Settings surface. The cockpit draws a `status` badge,
            // never the verdict itself — `grep state.verdict CockpitView.swift` finds nothing.
            // `.undrawn` prunes the subtree with it, which is the decision it is meant to be:
            // nothing *inside* a value this window does not draw is drawn either.
            "state.verdict": .undrawn(.notDrawnOnThisSurface),
            "state.capabilities": .drawn([.capabilityStates]),
            "state.showsLaunchAtLoginOffer": .drawn([.launchAtLoginOffer]),
            "state.showsFirstRunExplanation": .drawn([.firstRunExplanation]),

            // --- one level down (focus-cxs) -----------------------------------------------
            //
            // Round 6 closed the boundary at this struct and named its own residue in the same
            // breath: *"deeper structs are leaves"*. A `.drawn` binding stopped the walk, so a
            // field invented inside `PrioritySnapshot` was reached by nothing — and the
            // whole-value digest that was supposed to cover it is computed on **both** sides from
            // the same input, so it does not participate in the comparison either. A three-line
            // residue mutant gave 19/19 PASS, 303 ok against 303 and an empty ok-assertion diff
            // while three drawn things lied.
            //
            // Most of these bind to the digest, and that is an honest claim rather than a
            // shrug: `ShellValueDigest.describe` is `Mirror` to the leaves, so every field below
            // genuinely is in the string the window reports. What the entries buy is **totality**
            // — a field added tomorrow has no line here, and a path with no line is a failure.
            "state.priority.id": .drawn([.priorityDetail]),
            "state.priority.intent": .drawn([.priorityIntent, .priorityDetail]),
            "state.priority.doneWhen": .drawn([.priorityDoneWhen, .priorityDetail]),
            "state.priority.createdAt": .drawn([.priorityDetail]),
            "state.priority.lastActivatedAt": .drawn([.priorityDetail]),
            "state.priority.timeboxSeconds": .drawn([.priorityDetail]),
            "state.priority.startedAt": .drawn([.priorityDetail]),
            "state.priority.timebox": .drawn([.priorityDetail]),
            "state.priority.contextItems": .drawn([.priorityDetail]),
            "state.priority.rules": .drawn([.priorityDetail]),
            "state.priority.assessment": .drawn([.priorityDetail]),

            "state.pendingHandoff.verb": .drawn([.handoffDetail]),
            "state.pendingHandoff.task": .drawn([.handoffTask, .handoffDetail]),
            "state.pendingHandoff.doneWhen": .drawn([.handoffDetail]),
            "state.pendingHandoff.flags": .drawn([.handoffDetail]),

            "state.session.sessionID": .drawn([.sessionDetail]),
            "state.session.taskID": .drawn([.sessionDetail]),
            "state.session.phase": .drawn([.sessionPhase, .sessionDetail]),
            "state.session.pauseCauses": .drawn([.sessionDetail]),
            "state.session.resumeTo": .drawn([.sessionDetail]),
            "state.session.kind": .drawn([.sessionDetail]),
            "state.session.startedAt": .drawn([.sessionDetail]),
            "state.session.endedAt": .drawn([.sessionDetail]),
            "state.session.plannedSeconds": .drawn([.sessionDetail]),
            "state.session.deadlineAt": .drawn([.sessionDetail]),
            "state.session.notes": .drawn([.sessionDetail]),

            // The footer's *sentence* is a projection of three of these — `headlineKey(for:)`
            // reads `isWatching`, which is `isObserving && liveObserverCount > 0`, and
            // `isPausedByUser`. The other seven reach the sentence not at all, which is exactly
            // why `sensingDetail` exists and why they are bound to it alone.
            "state.sensing.isObserving": .drawn([.sensingSummary, .sensingDetail]),
            "state.sensing.isPausedByUser": .drawn([.sensingSummary, .sensingDetail]),
            "state.sensing.liveObserverCount": .drawn([.sensingSummary, .sensingDetail]),
            "state.sensing.redundantActivations": .drawn([.sensingDetail]),
            "state.sensing.lifecycle": .drawn([.sensingDetail]),
            "state.sensing.isUserIdle": .drawn([.sensingDetail]),
            "state.sensing.media": .drawn([.sensingDetail]),
            "state.sensing.cameraReason": .drawn([.sensingDetail]),
            "state.sensing.presentation": .drawn([.sensingDetail]),
            "state.sensing.isOnSecondaryDisplay": .drawn([.sensingDetail]),
            // Two levels down, and the walk keeps going because these are our own value types
            // too. The Privacy pane draws the microphone row and the presentation quorum's three
            // inputs; the cockpit's footer draws neither, and both are in the digest.
            "state.sensing.media.microphoneRunning": .drawn([.sensingDetail]),
            "state.sensing.media.cameraRunning": .drawn([.sensingDetail]),
            "state.sensing.presentation.signals": .drawn([.sensingDetail]),
            "state.sensing.presentation.isUserExcluded": .drawn([.sensingDetail]),
            "state.sensing.presentation.isPresenting": .drawn([.sensingDetail]),
            // Three levels down, and this is where the walk stops of its own accord: three `Bool`s
            // have no members. The Privacy pane draws the quorum's working — each signal whether
            // the answer is yes or no — and the digest carries all three.
            "state.sensing.presentation.signals.frontmostWindowFillsAScreen": .drawn([.sensingDetail]),
            "state.sensing.presentation.signals.presentationOptionsSayFullScreen": .drawn([.sensingDetail]),
            "state.sensing.presentation.signals.menuBarHidden": .drawn([.sensingDetail]),

            // The matrix's one stored property. `CapabilityMatrix.renderedDescription` is a
            // hand-written whole-value line — the order and the spelling are load-bearing in a
            // gate log — and it names every capability and its state.
            "state.capabilities.observations": .drawn([.capabilityStates])
        ]
    }
}
