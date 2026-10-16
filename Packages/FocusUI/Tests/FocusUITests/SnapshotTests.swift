import FocusCore
import SwiftUI
import Testing

@testable import FocusUI

/// Every shell component the snapshot matrix covers.
///
/// Named cases rather than an array of views, because the test arguments have to be
/// `Sendable` and a SwiftUI view is not. The view is built on the main actor from the case.
/// **Why the General settings pane is not here.** Measured on this machine: an AppKit-backed
/// control does not rasterise under `ImageRenderer` — a `Picker` renders as SwiftUI's
/// "unrenderable view" placeholder glyph on a white ground, whatever appearance is injected.
/// Committing that as a baseline would mean committing a picture of a broken render and
/// calling it evidence. The pane is covered instead by `SettingsTests` (every option, every
/// title, the store round-trip) and by the TCC-gated live frames, where it is drawn by
/// AppKit for real. A `Button` renders correctly, which is why the Privacy pane and the
/// cockpit are both here.
enum SnapshotComponent: String, CaseIterable, Sendable {
    case cockpit
    case cockpitStoreUnavailable
    /// **The store opened and refused the last write** (focus-tzj.4). A separate picture from
    /// the one above because it used to be the same one: both drew the same warning line from
    /// the same boolean, and only one of the two costs a person a day's work.
    case cockpitStoreWriteFailed
    /// The sheet a person actually reads when their store did not open. Rendered on its own,
    /// because `ImageRenderer` cannot rasterise a `.sheet` presentation — what is photographed
    /// is the sheet's own content, which is what the presentation shows.
    case cockpitStoreUnavailableSheet
    /// **The walkthrough, one picture per page** (focus-odz.7, focus-u6de). The first page is the
    /// sheet, rendered on its own for `cockpitStoreUnavailableSheet`'s reason: `ImageRenderer`
    /// cannot rasterise a `.sheet` presentation, so what is photographed is the sheet's own
    /// content. The other eleven are the floating tour's steps, drawn as the person first meets
    /// them, nothing done yet. Every step, because every step is different text and the lane's
    /// whole question is whether that text grows rather than clips.
    case walkthroughWatches
    case walkthroughSetPriority
    case walkthroughDoneWhen
    case walkthroughTimebox
    case walkthroughStartSession
    case walkthroughDesk
    case walkthroughRules
    case walkthroughNudge
    case walkthroughQuestion
    case walkthroughMenuBar
    case walkthroughSettings
    case walkthroughFinish
    case shortcutsHelp
    /// **The day's ledger** (e09a). Rendered from a fixed value with one of every row type —
    /// an accusation, a question, a session, a correctable silent interval and a withdrawn one —
    /// so the picture shows every shape the surface can draw rather than whichever shapes the
    /// machine that recorded it happened to have.
    case history
    case privacySettings
    /// Separate observation and reasoning renders keep expanded large-text images below
    /// CoreGraphics' image-height limit. The shipping pane still draws both together.
    case privacySettingsInsight
    /// The third part of the Privacy pane: what the app is allowed to look at, and the two
    /// switches that decide it. Photographed apart from the observation part since focus-oqsx —
    /// together they passed eighteen thousand rows under the pseudo-locale at the largest text
    /// size, which is a height `ImageRenderer` answers with an empty buffer rather than a picture.
    case privacySettingsCapability
    /// The grant switches, apart from the capability table: the remote judge's switch carried
    /// the two together past the row limit under the pseudo-locale.
    case privacySettingsGrants
    /// The fifth part of the Privacy pane: what the app made of what it saw.
    case privacySettingsReasoning
    case statusRelevant
    case statusUncertain
    case statusUnrelated
    case statusPaused
    case statusBreak

    /// A fixed store location, so the Privacy pane's path is the same string on every
    /// machine that ever records these baselines.
    static let storeURL = URL(
        filePath: "/Users/example/Library/Application Support/com.chrismitchelmore.FocusSentinel/FocusSentinel.store"
    )

    /// The render width. Badges size themselves; everything else wraps inside a fixed width
    /// so that growing text grows the *height*, which is what the dynamic-type and
    /// pseudo-localisation assertions read.
    var width: CGFloat? {
        switch self {
        case .statusRelevant, .statusUncertain, .statusUnrelated, .statusPaused, .statusBreak:
            nil
        case .privacySettings, .privacySettingsInsight, .privacySettingsCapability,
            .privacySettingsGrants, .privacySettingsReasoning:
            // **The width the pane commits to**, plus the harness's own 16-point padding on each
            // side, so the pane is proposed exactly `settingsWidth` and the picture has no dead
            // band beside it (focus-nu6). A surface that commits a width must be photographed at
            // it: a picture rendered at a width the test chose can never show the width being
            // wrong, which is the defect `MenuBarController.popoverLayout` records for the
            // popover baselines.
            ShellSurfaceBounds.settingsWidth + 32
        default:
            520
        }
    }

    /// The tour step a walkthrough component photographs. One component per step, plus the
    /// sheet, so the mapping is exhaustive in both directions: `WalkthroughTests` holds that
    /// every step has a component.
    var walkthroughStep: WalkthroughAction {
        switch self {
        case .walkthroughSetPriority: .setDemoPriority
        case .walkthroughDoneWhen: .setDemoDoneWhen
        case .walkthroughTimebox: .setDemoTimebox
        case .walkthroughStartSession: .startDemoSession
        case .walkthroughDesk: .addDemoDesk
        case .walkthroughRules: .addDemoRule
        case .walkthroughNudge: .showDemoNudge
        case .walkthroughQuestion: .showDemoQuestion
        case .walkthroughMenuBar: .openMenuBar
        case .walkthroughSettings: .openPrivacySettings
        case .walkthroughFinish: .finishDemo
        default: preconditionFailure("\(rawValue) is not a walkthrough step")
        }
    }

    var status: FocusStatus? {
        switch self {
        case .statusRelevant: .relevant
        case .statusUncertain: .uncertain
        case .statusUnrelated: .unrelated
        case .statusPaused: .paused
        case .statusBreak: .onBreak
        default: nil
        }
    }

    @MainActor
    var view: AnyView {
        if let status {
            return AnyView(StatusBadge(status: status))
        }
        switch self {
        case .cockpit:
            return AnyView(CockpitView(state: .ready))
        case .cockpitStoreUnavailable:
            return AnyView(CockpitView(state: .storeUnavailable))
        case .cockpitStoreWriteFailed:
            return AnyView(CockpitView(state: .storeWriteFailed))
        case .cockpitStoreUnavailableSheet:
            // `screens: []` for `privacySettings`'s reason: the bounded sheet derives its
            // ceiling from the live display, and a baseline whose dimensions depend on the
            // monitor that recorded it is not a baseline.
            return AnyView(
                StoreUnavailableSheet(
                    storeLocation: Self.storeURL.path(percentEncoded: false),
                    acknowledge: {},
                    screens: []
                )
            )
        case .walkthroughWatches:
            // `screens: []` for the store-failure sheet's reason: the bounded sheet derives its
            // ceiling from the live display, and a baseline whose dimensions depend on the monitor
            // that recorded it is not a baseline.
            return AnyView(
                WalkthroughSheet(
                    storeLocation: Self.storeURL.path(percentEncoded: false),
                    dismiss: {},
                    screens: []
                )
            )
        case .walkthroughSetPriority, .walkthroughDoneWhen, .walkthroughTimebox, .walkthroughStartSession,
             .walkthroughDesk, .walkthroughRules, .walkthroughNudge, .walkthroughQuestion,
             .walkthroughMenuBar, .walkthroughSettings, .walkthroughFinish:
            // The step as the person first meets it, not yet done, at the panel's own width: a
            // surface that commits a width is photographed at it.
            return AnyView(WalkthroughStepView(step: walkthroughStep).frame(width: WalkthroughPanelController.width))
        case .shortcutsHelp:
            return AnyView(ShortcutsHelpContent(registry: .shell))
        case .history:
            // The content, not the window: `HistoryView`'s `ScrollView` cannot be rasterised by
            // `ImageRenderer` at all (`BoundedSurfaceTests` re-measures that every run), and the
            // thing that must not clip is the content inside it.
            return AnyView(
                HistoryContent(
                    history: HistoryFixture.day,
                    corrected: [],
                    // `nil`, so the affordance is drawn as the disabled control a picture can
                    // show rather than as a live button pointing at a store this lane has none of.
                    correct: nil
                )
            )
        case .privacySettings:
            // **The real pane, handed no display** (focus-nu6).
            //
            // The pane is a `BoundedSurface` now, and two things about it are unrenderable here:
            // past its ceiling the container is a `ScrollView`, which `ImageRenderer` cannot
            // rasterise at all — re-measured every run by
            // `BoundedSurfaceTests.imageRendererStillCannotDrawAScrollView` — and the ceiling
            // itself is derived from the **live** display, so a picture of the bounded pane would
            // have dimensions that depend on the monitor that recorded it. A baseline that
            // changes with the machine is not a baseline.
            //
            // `screens: []` is the honest injection for both: with no display attached there is
            // nothing to clamp to, the container draws the column whole, and the picture is a
            // deterministic function of the committed code. It is the shipping view either way —
            // the pane's own `@ScaledMetric` spacing and `@Environment` text scale are installed,
            // which is exactly what reaching past `body` for an inner property lost: measured,
            // that renders the pane 70 points short at `accessibilityLarge` because the spacing
            // stops scaling.
            //
            // The pane used to have no scroll view at all, because one made this lane render a
            // blank. That was the product cut to suit the harness; this is the harness measuring
            // the product.
            return AnyView(
                PrivacySettingsView(storeURL: Self.storeURL, half: .ownership, screens: [])
            )
        case .privacySettingsInsight:
            return AnyView(
                PrivacySettingsView(storeURL: Self.storeURL, half: .insight, screens: [])
            )
        case .privacySettingsCapability:
            return AnyView(
                PrivacySettingsView(storeURL: Self.storeURL, half: .capability, screens: [])
            )
        case .privacySettingsGrants:
            return AnyView(
                PrivacySettingsView(storeURL: Self.storeURL, half: .grants, screens: [])
            )
        case .privacySettingsReasoning:
            return AnyView(
                PrivacySettingsView(storeURL: Self.storeURL, half: .reasoning, screens: [])
            )
        default:
            preconditionFailure("unhandled snapshot component \(rawValue)")
        }
    }
}

/// The F-157 snapshot lane.
///
/// Component renders through `ImageRenderer`, inside the ordinary unit lane: no app host, no
/// window server session, no TCC grant. Every appearance variant is *injected* rather than
/// read from the system — which is the only reason all five can be exercised on a Mac where
/// every accessibility setting is switched off.
///
/// Lane-gated on compiled String Catalogs, and that is not a convenience: under `swift test`
/// SwiftPM copies the catalogs verbatim, so every label would render as its own key and the
/// baselines would be pictures of `shell.cockpit.heading`. The gate lane compiles them, so
/// the baselines are pictures of the shell the user actually sees.
@Suite("Snapshots", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct SnapshotTests {
    @Test(
        "every component matches its baseline in every appearance variant",
        arguments: SnapshotComponent.allCases, AppearanceTraits.namedVariants.map(\.name)
    )
    func componentMatchesBaseline(component: SnapshotComponent, variant: String) throws {
        for size in SnapshotTypeSize.allCases {
            try SnapshotHarness.assertSnapshot(
                component.view,
                component: component.rawValue,
                variant: variant,
                textScale: size.textScale,
                width: component.width
            )
        }
    }

    @Test("light and dark are different pictures", arguments: SnapshotComponent.allCases)
    func lightAndDarkDiffer(component: SnapshotComponent) throws {
        // A component that renders identically in light and dark is not honouring dark mode,
        // however green its baseline comparison is.
        let light = try render(component, variant: "light")
        let dark = try render(component, variant: "dark")
        // Through a `Bool`: handing the macro the pixel buffers themselves would put two
        // megabytes of decoded image into every failure message.
        let differs = PNGCompare.areDistinct(light.pixels, dark.pixels)
        #expect(differs, "\(component.rawValue) ignores dark mode")
    }

    @Test("increased contrast changes the picture", arguments: SnapshotComponent.allCases)
    func increasedContrastDiffers(component: SnapshotComponent) throws {
        let plain = try render(component, variant: "light")
        let contrasted = try render(component, variant: "increasedContrast")
        let differs = PNGCompare.areDistinct(plain.pixels, contrasted.pixels)
        #expect(differs, "\(component.rawValue) ignores Increase Contrast")
    }

    @Test("reduce transparency changes any component that uses a material")
    func reduceTransparencyChangesMaterials() throws {
        // The status badge is the shell's one material surface in e01, so it is where the
        // Reduce Transparency promise is actually testable.
        let plain = try render(.statusPaused, variant: "light")
        let opaque = try render(.statusPaused, variant: "reduceTransparency")
        let differs = PNGCompare.areDistinct(plain.pixels, opaque.pixels)
        #expect(differs)
        #expect(DesignTokens.material(for: .reduceTransparency, provenance: .summoned) == .opaque)
    }

    @Test("every status badge is distinguishable without colour", arguments: FocusStatus.allCases)
    func statusBadgesAreDistinctWithoutColour(status: FocusStatus) throws {
        // Rendered in greyscale terms: `differentiateWithoutColor` forces the label on, and
        // the silhouette and symbol differ per case, so two statuses can never collapse into
        // the same picture even if their tints did.
        let traits = AppearanceTraits(colorScheme: .light, differentiateWithoutColor: true)
        let subject = try SnapshotHarness.render(
            StatusBadge(status: status),
            traits: traits,
            width: nil,
            name: "statusBadge.differentiateWithoutColor.\(status.rawValue)"
        )

        for other in FocusStatus.allCases where other != status {
            let comparison = try SnapshotHarness.render(
                StatusBadge(status: other),
                traits: traits,
                width: nil,
                name: "statusBadge.differentiateWithoutColor.\(other.rawValue)"
            )
            let differs = PNGCompare.areDistinct(subject.pixels, comparison.pixels)
            #expect(
                differs,
                "\(status.rawValue) and \(other.rawValue) render identically without colour"
            )
        }
    }

    @Test("the largest accessibility text size grows the layout instead of clipping it")
    func accessibilitySizesGrow() throws {
        for component in SnapshotComponent.allCases {
            let large = try SnapshotHarness.render(
                component.view,
                traits: .light,
                textScale: .standard,
                width: component.width,
                name: "\(component.rawValue).growth.standard"
            )
            let accessibility = try SnapshotHarness.render(
                component.view,
                traits: .light,
                textScale: .accessibilityLarge,
                width: component.width,
                name: "\(component.rawValue).growth.accessibilityLarge"
            )

            // Growing rather than staying put is what proves nothing is pinned to a fixed
            // height and quietly truncating.
            let grew = accessibility.height > large.height
            #expect(
                grew,
                "\(component.rawValue) did not grow at the largest text size (\(large.height) → \(accessibility.height))"
            )
        }
    }

    // MARK: -

    private func render(_ component: SnapshotComponent, variant: String) throws -> Snapshot {
        try SnapshotHarness.render(
            component.view,
            traits: SnapshotHarness.variantTraits(named: variant),
            width: component.width,
            name: "\(component.rawValue).distinctness.\(variant)"
        )
    }
}
