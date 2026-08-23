import FocusCore
import Foundation
import SwiftUI
import Testing

@testable import FocusUI

/// The capability matrices every render is drawn from.
enum CapabilityFixture {
    /// 2026-01-01T00:00:00Z.
    static let now = Date(timeIntervalSince1970: 1_767_225_600)

    static func matrix(_ states: [Capability: CapabilityState]) -> CapabilityMatrix {
        CapabilityMatrix(
            observations: Dictionary(
                uniqueKeysWithValues: Capability.allCases.map { capability in
                    (
                        capability,
                        CapabilityObservation(
                            state: states[capability] ?? .notRequested,
                            observedAt: now
                        )
                    )
                }
            )
        )
    }

    /// What this rig actually reports at zero grants, exactly as the plan's R-50 table records
    /// it: seven available, the camera **unavailable** (a hold on every Mac in v1, and on this
    /// one also a hardware fact), screen capture unavailable because it is parked, and the three
    /// later epics' capabilities never asked for.
    static let asMeasured = matrix([
        .frontmostApplication: .available,
        .windowMetadata: .available,
        .idle: .available,
        .systemLifecycle: .available,
        .displayGeometry: .available,
        .presentation: .available,
        .microphoneActivity: .available,
        .cameraActivity: .unavailable,
        .screenCapture: .unavailable,
        .accessibilityWindowContext: .notRequested,
        .notifications: .notRequested,
        .onDeviceModel: .notRequested
    ])

    /// A matrix carrying **all five** states at once.
    ///
    /// Constructed rather than measured, and it has to be: `.denied` and `.restricted` cannot
    /// occur in e03 at all, because the app never asks for anything. They are rendered here so
    /// that the surface which will draw them in e05 and e07 is proven to draw them *now* —
    /// including the assertion that a denial is not turned into a red alarm with a button
    /// beside it.
    static let everyState = matrix([
        .frontmostApplication: .available,
        .windowMetadata: .available,
        .idle: .available,
        .systemLifecycle: .available,
        .displayGeometry: .available,
        .presentation: .available,
        .microphoneActivity: .restricted,
        .cameraActivity: .unavailable,
        .screenCapture: .unavailable,
        .accessibilityWindowContext: .denied,
        .notifications: .denied,
        .onDeviceModel: .notRequested
    ])

    /// Nothing observed yet — the honest first launch, before a single probe has run.
    static let unobserved = CapabilityMatrix.unobserved(at: now)
}

enum CapabilityComponent: String, CaseIterable, Sendable {
    case capabilityMatrixAsMeasured
    case capabilityMatrixEveryState
    case capabilityMatrixUnobserved

    var width: CGFloat? { 520 }

    var capabilities: CapabilityMatrix {
        switch self {
        case .capabilityMatrixAsMeasured: CapabilityFixture.asMeasured
        case .capabilityMatrixEveryState: CapabilityFixture.everyState
        case .capabilityMatrixUnobserved: CapabilityFixture.unobserved
        }
    }

    @MainActor
    var view: AnyView {
        AnyView(CapabilityMatrixView(capabilities: capabilities))
    }
}

/// F-126's surface, proved rather than promised.
///
/// The Feasibility Court called the graceful-degradation matrix "the most charter-critical row
/// in the registry", and a degraded path nobody can see is a degraded path nobody maintains. So
/// the table is *drawn*, all five states are rendered, and each carries the fallback sentence
/// the contract actually declares — read from `CapabilityContract` rather than written out
/// again in the view.
@Suite("Capability matrix snapshots", .enabled(if: LocalizationLane.catalogsAreCompiled))
@MainActor
struct CapabilityMatrixSnapshotTests {
    @Test(
        "every capability matrix matches its baseline in every appearance variant",
        arguments: CapabilityComponent.allCases, AppearanceTraits.namedVariants.map(\.name)
    )
    func componentMatchesBaseline(component: CapabilityComponent, variant: String) throws {
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

    @Test("light and dark are different pictures", arguments: CapabilityComponent.allCases)
    func lightAndDarkDiffer(component: CapabilityComponent) throws {
        let light = try render(component, variant: "light")
        let dark = try render(component, variant: "dark")
        #expect(PNGCompare.areDistinct(light.pixels, dark.pixels))
    }

    @Test("increased contrast changes the picture", arguments: CapabilityComponent.allCases)
    func increasedContrastDiffers(component: CapabilityComponent) throws {
        let plain = try render(component, variant: "light")
        let contrasted = try render(component, variant: "increasedContrast")
        #expect(PNGCompare.areDistinct(plain.pixels, contrasted.pixels))
    }

    // MARK: - All five states, and every one of them named

    @Test("all five capability states are rendered, each with its own words")
    func everyStateIsRenderedAndNamed() {
        let drawn = CapabilityFixture.everyState.allStates.map(\.state)
        #expect(Set(drawn) == Set(CapabilityState.allCases))

        let words = CapabilityState.allCases
            .map { ShellStrings.string(CapabilityMatrixView.labelKey(for: $0)) }
        #expect(Set(words).count == words.count, "two capability states read the same: \(words)")
        for word in words {
            #expect(!word.isEmpty)
        }
    }

    @Test("every capability has its own name and every fallback its own sentence")
    func everyCapabilityAndFallbackIsNamed() {
        let names = Capability.allCases
            .map { ShellStrings.string(CapabilityMatrixView.labelKey(for: $0)) }
        #expect(names.count == 12)
        #expect(Set(names).count == names.count, "two capabilities read the same: \(names)")

        let fallbacks: [CapabilityFallback] = [
            .fullFunction,
            .degraded(to: .frontmostApplication),
            .featureAbsent,
            .suppressOnly,
            .showUnavailable
        ]
        let sentences = fallbacks.map { ShellStrings.string(CapabilityMatrixView.labelKey(for: $0)) }
        #expect(Set(sentences).count == sentences.count)
    }

    /// The fallback lines come out of the contract, not out of this view.
    ///
    /// An available capability draws none — a signal that works needs no explanation — and every
    /// unavailable one draws the **distinct** answers its ten consumers actually give, so the
    /// surface cannot drift from the table a test already proves total.
    @Test("the drawn fallbacks are the contract's own, deduplicated and ordered")
    func fallbacksComeFromTheContract() {
        let matrix = CapabilityFixture.everyState

        for capability in Capability.allCases where matrix.isAvailable(capability) {
            #expect(
                CapabilityMatrixView.fallbacks(for: capability, in: matrix).isEmpty,
                "\(capability.rawValue) is available and still drew a fallback"
            )
        }

        for capability in Capability.allCases where !matrix.isAvailable(capability) {
            let drawn = CapabilityMatrixView.fallbacks(for: capability, in: matrix)
            #expect(!drawn.isEmpty, "\(capability.rawValue) is not available and drew nothing")

            // No repeats…
            let tokens = drawn.map(\.token)
            #expect(Set(tokens).count == tokens.count)

            // …and every one of them is an answer the contract really gives for this capability.
            let declared = Set(
                SensingConsumer.allCases.map {
                    CapabilityContract.fallback(for: capability, consumer: $0).token
                }
            )
            #expect(Set(tokens) == declared, "\(capability.rawValue) drew \(tokens) against \(declared)")
        }
    }

    /// **No call to action anywhere.** F-126 is explicit that a button here would be an ask in
    /// disguise, and in this epic the app could not ask even if one existed: every prompting API
    /// is banned from the shipping graph by lint.
    ///
    /// Asserted through the copy, which is where such a thing would have to appear. A surface
    /// with nothing to press cannot be checked by counting buttons in a rendered image, so what
    /// is checked is that none of its words invites one.
    @Test("nothing in the capability surface invites the person to grant anything")
    func noStringIsACallToAction() {
        var strings = CapabilityMatrixView.contentKeys.map(ShellStrings.string)
        strings += Capability.allCases.map { ShellStrings.string(CapabilityMatrixView.labelKey(for: $0)) }
        strings += CapabilityState.allCases.map { ShellStrings.string(CapabilityMatrixView.labelKey(for: $0)) }

        // Words an ask is made of. A surface that says "allow", "grant", "enable" or "open
        // System Settings" is asking, whatever the button is called.
        let asking = ["allow", "grant", "enable", "turn on", "system settings", "permission", "request"]
        for text in strings {
            let lowered = text.lowercased()
            for word in asking {
                #expect(!lowered.contains(word), "\(text) reads as a call to action (\(word))")
            }
        }
    }

    /// A denial is not an alarm.
    ///
    /// Only `.available` is coloured. Painting "you said no" red would turn the person's own
    /// answer into a problem the app is inviting them to fix, which is the same ask in a
    /// different costume.
    @Test("only the working state is coloured")
    func onlyAvailableIsTinted() {
        let available = DesignTokens.tint(for: CapabilityState.available)
        for state in CapabilityState.allCases where state != .available {
            #expect(
                DesignTokens.tint(for: state) == DesignTokens.Palette.secondaryText,
                "\(state.rawValue) is drawn in a colour of its own"
            )
        }
        #expect(available != DesignTokens.Palette.secondaryText)
    }

    // MARK: -

    private func render(_ component: CapabilityComponent, variant: String) throws -> Snapshot {
        try SnapshotHarness.render(
            component.view,
            traits: SnapshotHarness.variantTraits(named: variant),
            width: component.width,
            name: "\(component.rawValue).distinctness.\(variant)"
        )
    }
}
