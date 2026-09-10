import Foundation

/// **Where a notch companion may draw on one display, or the named reason it may not** (e08a).
///
/// ## Why this is a refusal and not a `nil`
///
/// The Court's F-74 ruling forbids a `hasNotch` boolean, and this type is the reason it can be
/// obeyed without losing the answer. A `Bool` collapses six different facts about a display —
/// *there is no built-in panel at all*, *the built-in panel reports no inset*, *the panel reports
/// an inset but publishes no auxiliary areas*, *it publishes two areas that cannot both be true*,
/// *the housing between them is too narrow to be a housing*, *the housing is not on the display it
/// came from* — into one word, and a Settings row rendered from that word must lie about five of
/// them. `Refusal` is closed and `CaseIterable`, so the fold in `NotchLandingTests`, the copy
/// table in `InterventionSettingsView` and the self-check's published vocabulary all enumerate the
/// **same** set, and a seventh reason cannot be added without all three noticing.
///
/// ## What this rig answers
///
/// `.refused(.noBuiltInDisplay)`. This is a Mac mini (Mac16,10) with no built-in panel: the review
/// measured `safeAreaInsets` at `NSEdgeInsets(top: 0, …)` and both `auxiliaryTop*Area` at **`nil`,
/// not degenerate rects**, corroborating P-90. So every fixture with an interesting housing here is
/// **synthetic** and labelled as such until P-e08-B pastes measured values off a 14″ and a 16″
/// MacBook into `focus-26b`. The one non-synthetic cell is the `nil`/`nil`/`isBuiltIn: false` one,
/// and it is named `theRealRig` in the fold.
///
/// ## The order of the guards is the order of the answers
///
/// Each guard is asked only once the guard above it has passed, so a display can never be refused
/// for two reasons at once and the published reason is always the *first* thing wrong with it —
/// which is the sentence a person would say. `noBuiltInDisplay` is first because F-80's
/// built-in-only policy has no branch a display without a panel enters, and because "this Mac has
/// no notch" is a false sentence to show somebody whose Mac has no built-in display at all.
public enum NotchLanding: Sendable, Equatable, Hashable {
    case landed(Landing)
    case refused(Refusal)

    /// **Every reason a display cannot carry the companion**, closed and enumerable.
    public enum Refusal: String, Sendable, CaseIterable, Codable, Hashable {
        /// There is no built-in panel on this Mac at all — the answer on this rig, and a
        /// different fact from "the built-in panel has no notch" (review §0).
        case noBuiltInDisplay
        /// A built-in panel that reserves nothing at the top: `safeAreaInsets.top` is zero, so
        /// there is no housing for anything to sit under.
        case noSafeAreaInset
        /// An inset with no auxiliary areas published beside it. AppKit answers `nil` for both on
        /// a notchless panel, and `nil` is the shape this case is named for.
        case auxiliaryAreasAbsent
        /// Two areas that cannot both be true of one menu bar: one of them empty, or the left one
        /// reaching past the right one — which is what a swapped pair looks like from here.
        case auxiliaryAreasIncoherent
        /// The gap between the two areas is narrower than any real housing. A hairline drawn
        /// under a two-point gap is a smudge, not a surface.
        case housingTooNarrow
        /// The housing, or the hairline that would sit under it, is not wholly on the display the
        /// geometry came from — so drawing it would put ink on somebody else's screen.
        case housingOffDisplay
    }

    /// The two rectangles the companion is allowed to know about, both in **AppKit** coordinates
    /// on the display they were derived from.
    public struct Landing: Sendable, Equatable, Hashable {
        /// **The housing itself, which nothing may draw in.** Named `forbidden` rather than
        /// `notch` because its only use is exclusion: e08a draws under it and e08b, if the
        /// receipts arrive, will still draw under it.
        public let forbidden: ScreenRect
        /// The hairline strip flush under the housing — the whole of what e08a draws.
        public let collapsed: ScreenRect

        public init(forbidden: ScreenRect, collapsed: ScreenRect) {
            self.forbidden = forbidden
            self.collapsed = collapsed
        }
    }

    /// How tall the collapsed strip is. Two points, which is the top of the 1–2 pt band the plan
    /// allows: one point is a hairline that vanishes at `backingScaleFactor` 1.0, and this rig's
    /// one display is at 1.0.
    public static let collapsedHeight: Double = 2

    /// The narrowest gap that is still a housing. A 14″ MacBook's is ≈185 pt and a 16″'s ≈220 pt,
    /// so this is far below any real one and exists to refuse arithmetic noise rather than to
    /// classify hardware.
    public static let minimumHousingWidth: Double = 40

    /// **The whole decision, as a pure function of one display.**
    ///
    /// No `NSScreen`, no window server, no clock: the same value the shipping app computes is the
    /// value a test computes from a fixture, which is what makes a rig with no built-in display
    /// able to check the built-in path at all.
    public static func of(_ geometry: DisplayGeometry) -> NotchLanding {
        guard geometry.isBuiltIn else { return .refused(.noBuiltInDisplay) }

        let inset = geometry.safeAreaTopInset
        guard inset > 0 else { return .refused(.noSafeAreaInset) }

        guard let left = geometry.auxiliaryTopLeft, let right = geometry.auxiliaryTopRight else {
            return .refused(.auxiliaryAreasAbsent)
        }

        // Empty on either side, or a left area that reaches past the right one. A swapped pair
        // arrives here as exactly that overlap, which is why there is no separate `swapped` case:
        // the app cannot tell a swap from an overlap and must not claim to.
        guard !left.isEmpty, !right.isEmpty, left.maxX <= right.minX else {
            return .refused(.auxiliaryAreasIncoherent)
        }

        let housingWidth = right.minX - left.maxX
        guard housingWidth >= minimumHousingWidth else { return .refused(.housingTooNarrow) }

        // **The vertical anchor is this display's own frame**, never the primary's and never the
        // origin. A notched MacBook docked beside an external monitor is routinely not at
        // `(0, 0)`, and a housing placed from the origin would land on the other display.
        let forbidden = ScreenRect(
            x: left.maxX,
            y: geometry.frame.maxY - inset,
            width: housingWidth,
            height: inset
        )
        let collapsed = ScreenRect(
            x: forbidden.x,
            y: forbidden.minY - collapsedHeight,
            width: forbidden.width,
            height: collapsedHeight
        )
        // The display clamp. Both rectangles are checked, not just the housing: the strip hangs a
        // further two points below it and a panel whose inset is its whole height would put the
        // hairline off the bottom of a display it was supposed to be inside.
        guard contains(geometry.frame, forbidden), contains(geometry.frame, collapsed) else {
            return .refused(.housingOffDisplay)
        }

        return .landed(Landing(forbidden: forbidden, collapsed: collapsed))
    }

    /// Whether `inner` is wholly inside `outer`. Local rather than on `ScreenRect`, because
    /// containment with no tolerance is only the right question for two rectangles computed by the
    /// same arithmetic — which these are, and a window's bounds against a display's frame are not
    /// (that pair has `isEqual(to:tolerance:)`).
    static func contains(_ outer: ScreenRect, _ inner: ScreenRect) -> Bool {
        inner.minX >= outer.minX && inner.maxX <= outer.maxX
            && inner.minY >= outer.minY && inner.maxY <= outer.maxY
    }

    /// The reason, when there is one. `nil` for a landing — deliberately not a seventh case, so
    /// the copy table stays a total switch over `Refusal`.
    public var refusal: Refusal? {
        switch self {
        case .landed: nil
        case .refused(let reason): reason
        }
    }

    /// The strip the companion would draw in, or `nil` when nothing may be drawn. **The one
    /// reading the renderer takes**, so "refused" and "no ink" cannot come apart.
    public var collapsed: ScreenRect? {
        switch self {
        case .landed(let landing): landing.collapsed
        case .refused: nil
        }
    }
}
