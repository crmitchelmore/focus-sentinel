import Foundation
import Testing

@testable import FocusCore

/// **Where the companion may draw, folded over every geometry this rig cannot produce** (e08a,
/// `focus-26b`).
///
/// ## Why the fixtures are labelled `synthetic`
///
/// This Mac is a Mac mini with no built-in panel. The review measured it directly:
/// `safeAreaInsets` is `NSEdgeInsets(top: 0, …)` and **both** `auxiliaryTop*Area` are `nil` rather
/// than degenerate rectangles. So exactly one cell of this fold is a fact about hardware — the one
/// named `theRealRig` — and every cell with an interesting housing is a value somebody wrote down.
/// They stay labelled `synthetic` until P-e08-B pastes measured `safeAreaInsets.top` and both
/// auxiliary rectangles off a 14″ and a 16″ MacBook, at each backing scale, into `focus-26b`.
///
/// That is not a weakness of the fold; it is the reason the geometry is a **value**. A rig with no
/// notch can check every branch of the built-in path, and cannot check that AppKit reports what
/// this file assumes it reports. The two claims are kept apart on purpose.
///
/// ## What the fold asserts
///
/// Per cell, one expected outcome declared in the fixture table rather than recomputed from the
/// implementation, plus four structural invariants on every landing:
///
/// * the strip and the housing do not overlap;
/// * the strip's top edge is the housing's bottom edge, within a point;
/// * both are wholly inside the display's own frame;
/// * a landing happens **only** for a sane built-in notched geometry, and always for one.
///
/// ## The mutations it exists to catch
///
/// 1. refuse unconditionally → every positive cell fails;
/// 2. anchor the housing on the origin instead of this display's frame, or drop the clamp
///    entirely → `ultraWideSecondDisplay` and `offDisplay` fail;
/// 3. read `auxiliaryTopLeft` twice → `asymmetric` fails, because its two strips are different
///    widths and a housing measured from one of them twice is in the wrong place;
/// 4. drop `isBuiltIn` from the guard → `externalLookalike` fails, which is the review's §0
///    finding as a test: a monitor reporting a plausible inset is not a MacBook panel.
@Suite("Where a notch companion may land")
struct NotchLandingTests {
    /// One column of the fold: a display's frame and the pair of auxiliary areas AppKit would
    /// publish for it, with the outcome expected **once the built-in and inset guards have
    /// passed**. `nil` means this shape lands.
    struct AuxiliaryShape {
        let name: String
        let synthetic: Bool
        let frame: ScreenRect
        let left: ScreenRect?
        let right: ScreenRect?
        /// What this shape is refused for, or `nil` when it lands.
        let refusal: NotchLanding.Refusal?
    }

    /// A 14″ MacBook Pro's panel, as the plan describes it: a ≈185 × 32 housing.
    static let fourteenInch = ScreenRect(x: 0, y: 0, width: 1_512, height: 982)
    /// A 16″ MacBook Pro's: ≈220 × 38.
    static let sixteenInch = ScreenRect(x: 0, y: 0, width: 1_728, height: 1_117)

    static let shapes: [AuxiliaryShape] = [
        // **The one cell that is not synthetic.** Mac16,10, one external display, no built-in
        // panel: both auxiliary areas nil, and the built-in column below is what actually decides
        // it. Kept in the fold rather than beside it so the machine the gate runs on is one row of
        // the same table every imagined MacBook is a row of.
        AuxiliaryShape(
            name: "theRealRig",
            synthetic: false,
            frame: ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080),
            left: nil,
            right: nil,
            refusal: .auxiliaryAreasAbsent
        ),
        AuxiliaryShape(
            name: "leftAreaOnly",
            synthetic: true,
            frame: fourteenInch,
            left: ScreenRect(x: 0, y: 950, width: 663.5, height: 32),
            right: nil,
            refusal: .auxiliaryAreasAbsent
        ),
        AuxiliaryShape(
            name: "rightAreaOnly",
            synthetic: true,
            frame: fourteenInch,
            left: nil,
            right: ScreenRect(x: 848.5, y: 950, width: 663.5, height: 32),
            refusal: .auxiliaryAreasAbsent
        ),
        AuxiliaryShape(
            name: "zeroWidthAreas",
            synthetic: true,
            frame: fourteenInch,
            left: ScreenRect(x: 663.5, y: 950, width: 0, height: 32),
            right: ScreenRect(x: 848.5, y: 950, width: 0, height: 32),
            refusal: .auxiliaryAreasIncoherent
        ),
        AuxiliaryShape(
            name: "overlappingAreas",
            synthetic: true,
            frame: fourteenInch,
            left: ScreenRect(x: 0, y: 950, width: 900, height: 32),
            right: ScreenRect(x: 848.5, y: 950, width: 663.5, height: 32),
            refusal: .auxiliaryAreasIncoherent
        ),
        // The pair the right way round, handed over the wrong way. The app cannot tell a swap from
        // an overlap and does not claim to — both answer `auxiliaryAreasIncoherent`.
        AuxiliaryShape(
            name: "swappedAreas",
            synthetic: true,
            frame: fourteenInch,
            left: ScreenRect(x: 848.5, y: 950, width: 663.5, height: 32),
            right: ScreenRect(x: 0, y: 950, width: 663.5, height: 32),
            refusal: .auxiliaryAreasIncoherent
        ),
        AuxiliaryShape(
            name: "narrowGap",
            synthetic: true,
            frame: fourteenInch,
            left: ScreenRect(x: 0, y: 950, width: 700, height: 32),
            right: ScreenRect(x: 720, y: 950, width: 792, height: 32),
            refusal: .housingTooNarrow
        ),
        // Two coherent areas that are not on the display they came from. This is the clamp's own
        // cell: with the containment guard removed, this lands.
        AuxiliaryShape(
            name: "offDisplay",
            synthetic: true,
            frame: fourteenInch,
            left: ScreenRect(x: 2_000, y: 950, width: 100, height: 32),
            right: ScreenRect(x: 2_400, y: 950, width: 100, height: 32),
            refusal: .housingOffDisplay
        ),
        AuxiliaryShape(
            name: "macBook14",
            synthetic: true,
            frame: fourteenInch,
            left: ScreenRect(x: 0, y: 950, width: 663.5, height: 32),
            right: ScreenRect(x: 848.5, y: 950, width: 663.5, height: 32),
            refusal: nil
        ),
        AuxiliaryShape(
            name: "macBook16",
            synthetic: true,
            frame: sixteenInch,
            left: ScreenRect(x: 0, y: 1_079, width: 754, height: 38),
            right: ScreenRect(x: 974, y: 1_079, width: 754, height: 38),
            refusal: nil
        ),
        // **Deliberately lopsided.** A housing is not centred on every panel, and a derivation
        // that read one auxiliary area twice would put this one 60 points out.
        AuxiliaryShape(
            name: "asymmetric",
            synthetic: true,
            frame: fourteenInch,
            left: ScreenRect(x: 0, y: 950, width: 600, height: 32),
            right: ScreenRect(x: 785, y: 950, width: 727, height: 32),
            refusal: nil
        ),
        // A notched panel docked to the *right* of an external monitor, so its frame does not
        // start at the origin. Every rectangle below is in global AppKit coordinates, which is
        // what AppKit publishes.
        AuxiliaryShape(
            name: "ultraWideSecondDisplay",
            synthetic: true,
            frame: ScreenRect(x: 1_920, y: 0, width: 5_120, height: 2_160),
            left: ScreenRect(x: 1_920, y: 2_128, width: 2_350, height: 32),
            right: ScreenRect(x: 4_620, y: 2_128, width: 2_420, height: 32),
            refusal: nil
        )
    ]

    /// The insets the fold crosses every shape with. `0` is every notchless panel and this rig;
    /// `200` is absurd and is here because the app has no business inventing a hardware policy —
    /// a built-in panel reserving 200 points has a 200-point housing.
    static let insets: [Double] = [0, 1, 24, 32, 38, 200]
    static let scales: [Double] = [1.0, 2.0]

    static func geometry(
        _ shape: AuxiliaryShape,
        inset: Double,
        isBuiltIn: Bool,
        scale: Double
    ) -> DisplayGeometry {
        DisplayGeometry(
            displayID: 1,
            screenIndex: 0,
            isPrimary: true,
            frame: shape.frame,
            visibleFrame: shape.frame,
            backingScaleFactor: scale,
            safeAreaTopInset: inset,
            auxiliaryTopLeft: shape.left,
            auxiliaryTopRight: shape.right,
            isBuiltIn: isBuiltIn
        )
    }

    /// **The expected answer, declared rather than derived.** The order of the three questions is
    /// the ruling — no built-in panel is a different sentence from a built-in panel with no notch,
    /// and both are different from a panel whose areas disagree — so the table states the order
    /// instead of recomputing it.
    static func expected(
        _ shape: AuxiliaryShape,
        inset: Double,
        isBuiltIn: Bool
    ) -> NotchLanding.Refusal? {
        if !isBuiltIn { return .noBuiltInDisplay }
        if inset <= 0 { return .noSafeAreaInset }
        return shape.refusal
    }

    @Test("every geometry either lands somewhere sane or refuses for exactly one named reason")
    func theWholeFold() {
        var cells = 0
        var landings = 0
        var reasonsSeen: Set<NotchLanding.Refusal> = []

        for shape in Self.shapes {
            for inset in Self.insets {
                for isBuiltIn in [true, false] {
                    for scale in Self.scales {
                        cells += 1
                        let cell = "\(shape.name)/inset=\(inset)/builtIn=\(isBuiltIn)/@\(scale)x: "
                        let geometry = Self.geometry(
                            shape, inset: inset, isBuiltIn: isBuiltIn, scale: scale
                        )
                        let landing = NotchLanding.of(geometry)
                        let want = Self.expected(shape, inset: inset, isBuiltIn: isBuiltIn)

                        #expect(
                            landing.refusal == want,
                            """
                            \(cell)expected \(want.map(\.rawValue) ?? "a landing") and got \
                            \(landing.refusal.map(\.rawValue) ?? "a landing")
                            """
                        )
                        if let reason = landing.refusal { reasonsSeen.insert(reason) }

                        guard case .landed(let landed) = landing else {
                            #expect(
                                landing.collapsed == nil,
                                "\(cell)a refusal offered a strip to draw in"
                            )
                            continue
                        }
                        landings += 1

                        // — the four structural invariants —
                        #expect(
                            landed.collapsed.intersectionArea(with: landed.forbidden) == 0,
                            "\(cell)the strip overlaps the housing it is supposed to sit under"
                        )
                        #expect(
                            abs(landed.collapsed.maxY - landed.forbidden.minY) <= 1,
                            """
                            \(cell)the strip is not flush under the housing — strip top \
                            \(landed.collapsed.maxY), housing bottom \(landed.forbidden.minY)
                            """
                        )
                        #expect(
                            NotchLanding.contains(shape.frame, landed.forbidden),
                            "\(cell)the housing is not wholly on the display it came from"
                        )
                        #expect(
                            NotchLanding.contains(shape.frame, landed.collapsed),
                            "\(cell)the strip is not wholly on the display it came from"
                        )
                        // Centred on the housing, which is what "under the notch" means.
                        let housingCentre = (landed.forbidden.minX + landed.forbidden.maxX) / 2
                        let stripCentre = (landed.collapsed.minX + landed.collapsed.maxX) / 2
                        #expect(
                            abs(housingCentre - stripCentre) <= 0.5,
                            "\(cell)the strip is not centred under the housing"
                        )
                        #expect(landing.collapsed == landed.collapsed)
                    }
                }
            }
        }

        // — the vacuity guards, stated —
        #expect(cells == Self.shapes.count * Self.insets.count * 2 * Self.scales.count)
        #expect(landings > 0, "nothing ever landed, so a function that always refuses would pass")
        let unproven = Set(NotchLanding.Refusal.allCases)
            .subtracting(reasonsSeen)
            .map(\.rawValue)
            .sorted()
        #expect(
            reasonsSeen == Set(NotchLanding.Refusal.allCases),
            "the fold never produced \(unproven), so those refusals are unproven"
        )
    }

    /// **The positive cells, as specific rectangles rather than as invariants.**
    ///
    /// The fold above is satisfied by any landing in the right neighbourhood; these are the
    /// numbers. They are written out rather than computed, so an arithmetic that drifted would
    /// have to drift here too — which is the point of a green-for on a function whose green
    /// answer is "it refuses".
    @Test("the two MacBook shapes land on exactly these rectangles")
    func theMacBookRectangles() {
        let fourteen = Self.geometry(
            Self.shapes.first { $0.name == "macBook14" }!,
            inset: 32, isBuiltIn: true, scale: 2.0
        )
        #expect(
            NotchLanding.of(fourteen) == .landed(
                NotchLanding.Landing(
                    // 982 − 32 = 950, x from 663.5 to 848.5, so 185 wide.
                    forbidden: ScreenRect(x: 663.5, y: 950, width: 185, height: 32),
                    collapsed: ScreenRect(x: 663.5, y: 948, width: 185, height: 2)
                )
            ),
            "\(NotchLanding.of(fourteen))"
        )

        let sixteen = Self.geometry(
            Self.shapes.first { $0.name == "macBook16" }!,
            inset: 38, isBuiltIn: true, scale: 2.0
        )
        #expect(
            NotchLanding.of(sixteen) == .landed(
                NotchLanding.Landing(
                    // 1117 − 38 = 1079, x from 754 to 974, so 220 wide.
                    forbidden: ScreenRect(x: 754, y: 1_079, width: 220, height: 38),
                    collapsed: ScreenRect(x: 754, y: 1_077, width: 220, height: 2)
                )
            ),
            "\(NotchLanding.of(sixteen))"
        )

        // The docked panel, whose frame does not start at the origin: 2160 − 32 = 2128.
        let ultraWide = Self.geometry(
            Self.shapes.first { $0.name == "ultraWideSecondDisplay" }!,
            inset: 32, isBuiltIn: true, scale: 2.0
        )
        #expect(
            NotchLanding.of(ultraWide) == .landed(
                NotchLanding.Landing(
                    forbidden: ScreenRect(x: 4_270, y: 2_128, width: 350, height: 32),
                    collapsed: ScreenRect(x: 4_270, y: 2_126, width: 350, height: 2)
                )
            ),
            "\(NotchLanding.of(ultraWide))"
        )

        // The lopsided one, which a derivation reading one auxiliary area twice gets wrong.
        let lopsided = Self.geometry(
            Self.shapes.first { $0.name == "asymmetric" }!,
            inset: 32, isBuiltIn: true, scale: 1.0
        )
        #expect(
            NotchLanding.of(lopsided) == .landed(
                NotchLanding.Landing(
                    forbidden: ScreenRect(x: 600, y: 950, width: 185, height: 32),
                    collapsed: ScreenRect(x: 600, y: 948, width: 185, height: 2)
                )
            ),
            "\(NotchLanding.of(lopsided))"
        )
    }

    /// **The notched and the notchless columns are not the same column.**
    ///
    /// A fold whose two halves agreed everywhere would be a fold over one thing, and a function
    /// that always refused would satisfy every invariant above. This is the sentence that stops
    /// that: one geometry, one field changed, two different answers.
    @Test("the built-in column and the external column disagree on the same geometry")
    func theColumnsDiffer() {
        let shape = Self.shapes.first { $0.name == "macBook14" }!
        let builtIn = NotchLanding.of(
            Self.geometry(shape, inset: 32, isBuiltIn: true, scale: 2.0)
        )
        let external = NotchLanding.of(
            Self.geometry(shape, inset: 32, isBuiltIn: false, scale: 2.0)
        )

        #expect(builtIn != external)
        #expect(builtIn.collapsed != nil, "the built-in panel refused a housing it has")
        #expect(
            external == .refused(.noBuiltInDisplay),
            """
            an external monitor reporting a MacBook's inset was treated as a MacBook — \
            \(external)
            """
        )
    }

    /// **This rig, named.** Not a geometry somebody chose: the values the review measured on
    /// Mac16,10 with one external `2490W1`, and the reason every landing on this machine is a
    /// refusal with a reason rather than a hairline nobody can see.
    @Test("this Mac refuses for the reason it actually has")
    func theRealRigRefusesByName() {
        let rig = DisplayGeometry(
            displayID: 1,
            screenIndex: 0,
            isPrimary: true,
            frame: ScreenRect(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: ScreenRect(x: 0, y: 81, width: 1_920, height: 969),
            backingScaleFactor: 1.0,
            safeAreaTopInset: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            isBuiltIn: false
        )

        #expect(rig.notchLanding == .refused(.noBuiltInDisplay))
        #expect(rig.notchLanding.collapsed == nil)
    }

    /// The defaults are this machine's readings, which is what lets every construction site
    /// written before e08a go on describing the Mac it was written on.
    @Test("a geometry built without the four readings describes a notchless external display")
    func theDefaultsAreThisRig() {
        let plain = DisplayGeometry(
            displayID: 2,
            screenIndex: 1,
            isPrimary: false,
            frame: ScreenRect(x: 0, y: 0, width: 100, height: 100),
            visibleFrame: ScreenRect(x: 0, y: 0, width: 100, height: 100),
            backingScaleFactor: 1.0
        )

        #expect(plain.safeAreaTopInset == 0)
        #expect(plain.auxiliaryTopLeft == nil)
        #expect(plain.auxiliaryTopRight == nil)
        #expect(!plain.isBuiltIn)
        #expect(plain.notchLanding == .refused(.noBuiltInDisplay))
    }
}
