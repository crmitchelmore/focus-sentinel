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
        generation: Int = 0,
        didRender: @escaping @MainActor () -> Void = {},
        didDraw: @escaping @MainActor (ShellRenderedValues) -> Void = { _ in }
    ) {
        self.state = state
        self.actions = actions
        self.sessionActions = sessionActions
        self.sessionElapsedSeconds = sessionElapsedSeconds
        self.lastActiveBundleID = lastActiveBundleID
        self.generation = generation
        self.didRender = didRender
        self.didDraw = didDraw
    }
}
