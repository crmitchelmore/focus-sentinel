import AppKit
import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// **The proof the snapshot lane cannot give** (focus-nu6).
///
/// Two Settings panes recorded, in their own source, that their `ScrollView` had been deleted
/// because "a `ScrollView` reports no intrinsic height, so under `ImageRenderer` the snapshot…" —
/// the product reshaped to suit the harness, which is this epic's recurring failure in its purest
/// form. The measurement behind that note is also wrong in a way that matters: measured here,
/// twice, a `ScrollView` reports the **right** height and rasterises **no ink at all**, and it
/// still rasterises no ink when handed its content's measured height explicitly. `ImageRenderer`
/// cannot draw a scroll view, full stop. No amount of measuring will make it.
///
/// So the scroll goes back into the product and the assertion moves: this suite lays the container
/// out at a real ceiling and reads the **view hierarchy** for an `NSScrollView`, which is a
/// reading `ImageRenderer` is not involved in. The baseline lane renders each pane's `content` —
/// the column that carries every pixel of ink — and keeps proving what it was always the right
/// instrument for, which is what the pane looks like.
@Suite("A bounded surface clamps to its ceiling and scrolls past it")
@MainActor
struct BoundedSurfaceTests {
    /// A column of `rows` wrapped paragraphs. Real text, so the height is a real wrapped height.
    struct Column: View {
        let rows: Int
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<rows, id: \.self) { index in
                    Text(verbatim: "Row \(index): a sentence long enough to wrap in a narrow column")
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    static let width: Double = 460
    static let ceiling: Double = 400

    static func height(of view: some View, proposing height: Double = .greatestFiniteMagnitude) -> Double {
        NSHostingController(rootView: AnyView(view))
            .sizeThatFits(in: CGSize(width: Self.width, height: height))
            .height
    }

    /// Whether the laid-out hierarchy actually contains a scroll view. This is the reading the
    /// snapshot lane could never take, and the one the deleted `ScrollView` needed somebody to.
    static func scrolls(_ view: some View, atHeight height: Double) -> Bool {
        let controller = NSHostingController(rootView: AnyView(view))
        controller.view.frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
        controller.view.layoutSubtreeIfNeeded()
        var found = false
        func walk(_ view: NSView) {
            if view is NSScrollView { found = true }
            view.subviews.forEach(walk)
        }
        walk(controller.view)
        return found
    }

    static func surface(rows: Int, ceiling: Double? = ceiling) -> some View {
        BoundedSurface(width: Self.width, ceiling: ceiling) { Column(rows: rows) }
    }

    // MARK: - Under the ceiling

    /// A short pane must not acquire a scroll bar, and — the failure mode of every other
    /// construction measured — must not open at the height of the display either. A
    /// `frame(maxHeight:)` reports the whole proposal, so without the `fixedSize` a two-line
    /// sheet would be as tall as the screen.
    @Test("content that fits is drawn whole, at its own height, with no scroll view")
    func contentThatFitsIsDrawnWhole() {
        let natural = Self.height(of: Column(rows: 3).frame(width: Self.width, alignment: .leading))
        try? #require(natural < Self.ceiling)

        let surface = Self.surface(rows: 3)
        let committed = Self.height(of: surface)

        #expect(
            abs(committed - natural) <= SurfaceSizeCommitments.tolerance,
            "a \(natural)-point column opened at \(committed) points"
        )
        let scrolls = Self.scrolls(surface, atHeight: committed)
        #expect(!scrolls, "a surface that fits drew a scroll bar")
    }

    // MARK: - Over the ceiling

    /// The defect itself. `PrivacySettingsView` measured 2 699 points at the shipping text size,
    /// on a window whose only commitment was `minWidth: 460` — so its lower half was off the
    /// bottom of every display made, and no gesture in macOS reached it.
    @Test("content taller than the ceiling is clamped to it and scrolls")
    func contentOverTheCeilingScrollsRatherThanClipping() {
        let natural = Self.height(of: Column(rows: 60).frame(width: Self.width, alignment: .leading))
        try? #require(natural > Self.ceiling)

        let surface = Self.surface(rows: 60)
        let committed = Self.height(of: surface)

        #expect(
            committed <= Self.ceiling + SurfaceSizeCommitments.tolerance,
            "\(natural) points of content opened a surface \(committed) points tall"
        )
        let scrolls = Self.scrolls(surface, atHeight: Self.ceiling)
        #expect(
            scrolls,
            """
            the surface clamped \(natural) points of content to \(committed) and drew no scroll \
            view: everything past the clamp is laid out and unreachable
            """
        )
    }

    /// The property the pure arithmetic asserts, held against the real SwiftUI layout: over a
    /// range of contents, a surface that was clamped is always a surface that scrolls.
    @Test("across every content, a clamped surface is a scrolling surface")
    func clampingAlwaysImpliesScrolling() {
        for rows in [1, 2, 4, 8, 16, 32, 64] {
            let natural = Self.height(
                of: Column(rows: rows).frame(width: Self.width, alignment: .leading)
            )
            let surface = Self.surface(rows: rows)
            let committed = Self.height(of: surface)
            let wasClamped = committed < natural - SurfaceSizeCommitments.tolerance
            let scrolls = Self.scrolls(surface, atHeight: committed)
            #expect(committed <= Self.ceiling + SurfaceSizeCommitments.tolerance)
            #expect(
                !wasClamped || scrolls,
                "\(rows) rows: \(natural) points cut to \(committed) with no scroll view"
            )
        }
    }

    /// The width is a commitment, not a floor: text wraps into it rather than the surface growing
    /// sideways. This is what `minWidth` alone never promised.
    @Test("the surface commits its width rather than growing sideways")
    func theWidthIsCommitted() {
        let size = NSHostingController(rootView: AnyView(Self.surface(rows: 8)))
            .sizeThatFits(in: CGSize(width: 4_000, height: CGFloat.greatestFiniteMagnitude))
        #expect(
            abs(size.width - Self.width) <= SurfaceSizeCommitments.tolerance,
            "offered 4000 points of width the surface took \(Double(size.width))"
        )
    }

    /// No display to read. Nothing bounds a surface nobody can point at, so the column is drawn
    /// whole — never clamped to a fallback constant that would cut it off for a reason that has
    /// nothing to do with the person's screen.
    @Test("with no ceiling the column is drawn whole and nothing scrolls")
    func anUnboundedSurfaceDrawsTheColumnWhole() {
        let natural = Self.height(of: Column(rows: 60).frame(width: Self.width, alignment: .leading))
        let surface = Self.surface(rows: 60, ceiling: nil)
        #expect(abs(Self.height(of: surface) - natural) <= SurfaceSizeCommitments.tolerance)
        let scrolls = Self.scrolls(surface, atHeight: natural)
        #expect(!scrolls, "an unbounded surface drew a scroll bar")
    }

    // MARK: - The reason the ScrollView was deleted, recorded as a measurement

    /// **`ImageRenderer` cannot rasterise a scroll view**, which is a different fact from the one
    /// the two panes recorded, and it is the reason the fix is a different *instrument* rather
    /// than a different layout.
    ///
    /// If this ever starts passing, the baseline lane can render the bounded body directly and the
    /// split between `content` and `body` stops being necessary. Until then it is load-bearing,
    /// and this is what says so out loud instead of a comment nobody re-measures.
    @Test("a scroll view still rasterises no ink, which is why the baseline renders the column")
    func imageRendererStillCannotDrawAScrollView() throws {
        let column = Column(rows: 40)
        let plain = try Self.ink(of: column)
        #expect(plain > 0, "the column itself drew nothing, so this measures nothing")

        let scrolled = try Self.ink(of: ScrollView(.vertical) { column })
        #expect(
            scrolled == 0,
            """
            ImageRenderer drew \(scrolled) ink pixels inside a ScrollView. It could not when this \
            was written, which is the whole reason PrivacySettingsView and InterventionSettingsView \
            render their `content` rather than their `body` — re-read that split, it may now be \
            removable
            """
        )
    }

    static func ink(of view: some View) throws -> Int {
        let subject = view
            .padding(16)
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.white)
        let renderer = ImageRenderer(content: subject)
        renderer.scale = 2
        renderer.isOpaque = true
        let image = try #require(renderer.cgImage)
        return try PNGCompare.inkPixels(PNGCompare.pixels(of: image))
    }
}
