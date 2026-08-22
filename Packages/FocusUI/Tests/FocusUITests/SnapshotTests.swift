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
    case shortcutsHelp
    case privacySettings
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
        default:
            520
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
        case .shortcutsHelp:
            return AnyView(ShortcutsHelpContent(registry: .shell))
        case .privacySettings:
            return AnyView(PrivacySettingsView(storeURL: Self.storeURL))
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
        #expect(DesignTokens.material(for: .reduceTransparency) == .opaque)
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
