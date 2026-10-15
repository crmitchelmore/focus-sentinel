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
        .onDeviceModel: .notRequested,
        .calendarEvents: .notRequested
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
        .onDeviceModel: .notRequested,
        .calendarEvents: .available
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
        #expect(names.count == 13)
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
            let tokens = drawn.map(\.fallback.token)
            #expect(Set(tokens).count == tokens.count)

            // …and every one of them is an answer the contract really gives for this capability.
            let declared = Set(
                SensingConsumer.allCases.map {
                    CapabilityContract.fallback(for: capability, consumer: $0).token
                }
            )
            #expect(Set(tokens) == declared, "\(capability.rawValue) drew \(tokens) against \(declared)")

            // What changed is drawn before what did not: "carries on unchanged" is the
            // complement and usually the longest list, and it used to arrive first.
            if let unchanged = tokens.firstIndex(of: CapabilityFallback.fullFunction.token) {
                #expect(
                    unchanged == tokens.count - 1,
                    "\(capability.rawValue) drew the unchanged line above a degradation"
                )
            }

            // **Every consumer appears on exactly one line** (focus-doc). The lines partition the
            // ten consumers, so no line can be true of somebody it does not name and none can be
            // read as an app-level claim — which is what four unattributed sentences under
            // "Which app is in front" were doing to each other.
            let attributed = drawn.flatMap(\.consumers)
            #expect(
                Set(attributed) == Set(SensingConsumer.allCases),
                "\(capability.rawValue) attributed \(attributed.count) of ten consumers"
            )
            #expect(attributed.count == SensingConsumer.allCases.count)
            for (fallback, consumers) in drawn {
                #expect(!consumers.isEmpty)
                for consumer in consumers {
                    #expect(
                        CapabilityContract.fallback(for: capability, consumer: consumer).token
                            == fallback.token,
                        "\(capability.rawValue) put \(consumer.rawValue) under \(fallback.token)"
                    )
                }
            }
        }
    }

    /// **The defect this suite could not see, asserted as text** (focus-doc).
    ///
    /// The four sentences that shipped under *"Which app is in front"* — *"There is nothing to
    /// fall back to, so the app says so."* / *"That part of the app does not run."* / *"The app
    /// does less, never more."* / *"Nothing depends on it."* — were each a complete sentence with
    /// no subject, so a reader supplied one, and the only subject available was the app. The last
    /// was then false of an app whose Watching section two inches above says the app in front is
    /// watched.
    ///
    /// Two claims, and neither is about a picture. A fallback predicate may not begin with a
    /// capital or name the app; and the line as drawn must begin with the consumers it is about.
    @Test(
        "no fallback line can be read as a claim about the app",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func everyFallbackLineNamesItsConsumers() {
        let predicates: [CapabilityFallback] = [
            .fullFunction, .featureAbsent, .suppressOnly, .showUnavailable,
            .degraded(to: .frontmostApplication)
        ]
        for fallback in predicates {
            let text = CapabilityMatrixView.predicate(fallback)
            #expect(!text.isEmpty)
            #expect(
                text.first?.isUppercase != true,
                "\"\(text)\" starts a sentence, so it reads as a claim of its own"
            )
            #expect(
                !text.lowercased().contains("the app "),
                "\"\(text)\" says what THE APP does; a fallback is what one consumer does"
            )
        }

        // And the drawn line puts the subject in front of it.
        let matrix = CapabilityFixture.everyState
        for capability in Capability.allCases where !matrix.isAvailable(capability) {
            for (fallback, consumers) in CapabilityMatrixView.fallbacks(for: capability, in: matrix) {
                let subject = CapabilityMatrixView.subject(consumers)
                #expect(!subject.isEmpty)
                for consumer in consumers {
                    let name = ShellStrings.string(CapabilityMatrixView.labelKey(for: consumer))
                    #expect(subject.contains(name), "\(subject) does not name \(name)")
                }
                #expect(!CapabilityMatrixView.predicate(fallback).contains(subject))
            }
        }
    }

    /// **Both halves of a fallback line are authored prose, so both must pseudo-localise.**
    ///
    /// `ShellText` expands the format it is handed and leaves its arguments alone, which is
    /// exactly right for the one place that mechanism was built for — the user's own words in
    /// the refinement strip — and exactly wrong here, where the arguments are two catalog
    /// entries. Without the transform reaching them the matrix would draw a 2× heading over
    /// unexpanded fallback lines and `capabilityComponentsExpand` would report a row narrower
    /// than any real translation will make it.
    @Test(
        "a fallback line's consumer list and its predicate both expand under the pseudo-locale",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func bothHalvesOfAFallbackLinePseudoLocalise() {
        let plainSubject = CapabilityMatrixView.subject([.nudgeLadder, .analytics])
        let pseudoSubject = CapabilityMatrixView.subject(
            [.nudgeLadder, .analytics], transform: PseudoLocale.transform
        )
        #expect(pseudoSubject.count > plainSubject.count)
        #expect(pseudoSubject.contains(PseudoLocale.opening))

        for fallback in [
            CapabilityFallback.fullFunction, .featureAbsent, .suppressOnly, .showUnavailable,
            .degraded(to: .frontmostApplication)
        ] {
            let plain = CapabilityMatrixView.predicate(fallback)
            let pseudo = CapabilityMatrixView.predicate(fallback, transform: PseudoLocale.transform)
            #expect(pseudo.count > plain.count, "\(fallback.token) did not expand: \(pseudo)")
            #expect(pseudo.contains(PseudoLocale.opening))
        }
    }

    /// Ten consumers, ten distinct names — a list that reads "Nudges and Nudges" names nothing.
    @Test(
        "every sensing consumer has its own name",
        .enabled(if: LocalizationLane.catalogsAreCompiled)
    )
    func everyConsumerIsNamed() {
        let names = SensingConsumer.allCases
            .map { ShellStrings.string(CapabilityMatrixView.labelKey(for: $0)) }
        #expect(names.count == 10)
        #expect(Set(names).count == names.count, "two consumers read the same: \(names)")
        for name in names {
            #expect(!name.isEmpty)
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
        // The fallback lines too, both halves — they are the only prose on this pane that is
        // composed at draw time, and focus-doc added ten more strings to it.
        strings += SensingConsumer.allCases
            .map { ShellStrings.string(CapabilityMatrixView.labelKey(for: $0)) }
        strings += [
            CapabilityFallback.fullFunction, .featureAbsent, .suppressOnly, .showUnavailable,
            .degraded(to: .frontmostApplication)
        ].map { CapabilityMatrixView.predicate($0) }

        // Words an ask is made of. A surface that says "allow", "grant", "enable" or "open
        // System Settings" is asking, whatever the button is called.
        let asking = ["allow", "grant", "enable", "turn on", "system settings", "permission", "request"]
        // These exact descriptions report a state or explicitly say this is read-only.
        // Their permission/request nouns are not invitations. All other wording still
        // passes the conservative ask-word guard, so a new request cannot slip through.
        let readOnlyDescriptions: Set<String> = [
            "Permission denied", "Not requested",
            "This page shows what Focus can read. It does not request permissions."
        ]
        for text in strings {
            if readOnlyDescriptions.contains(text) { continue }
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
