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
@MainActor
public struct CockpitConnection {
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

    public init(
        state: CockpitState,
        actions: (any PriorityActing)?,
        sessionActions: (any SessionActing)?,
        sessionElapsedSeconds: Double?,
        lastActiveBundleID: String?,
        didRender: @escaping @MainActor () -> Void = {}
    ) {
        self.state = state
        self.actions = actions
        self.sessionActions = sessionActions
        self.sessionElapsedSeconds = sessionElapsedSeconds
        self.lastActiveBundleID = lastActiveBundleID
        self.didRender = didRender
    }
}
