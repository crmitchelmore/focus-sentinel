import FocusCore
import SwiftUI

/// The graceful-degradation matrix, rendered (F-126, F-127).
///
/// ## Why this surface exists at all
///
/// The Feasibility Court called F-126 "the most charter-critical row in the registry", and the
/// reason is that a degraded path nobody can see is a degraded path nobody maintains. So the
/// table is drawn: twelve capabilities, the state each is in, and — for every one that is not
/// available — **what the app actually does instead**, taken from
/// `CapabilityContract.fallback(for:consumer:)` rather than written out again here.
///
/// ## There is no call to action anywhere in this view
///
/// Not a button, not a link, not a "Fix this…". That is not restraint, it is the requirement:
/// F-126 says the surface shows what is active, what is reduced and what the reduced behaviour
/// is, **with no call to action that would be an ask in disguise**. In this epic the app could
/// not ask even if somebody added one — every prompting API is banned from the shipping graph
/// by lint (R-33) — and this view is where that promise is visible to a person.
///
/// The states are drawn accordingly. Only `.available` is coloured; `.denied` is not a red
/// alarm, because "you said no" is an answer the app is required to respect rather than a
/// problem it is inviting the person to solve.
///
/// ## Where the fallback sentences come from
///
/// The contract is indexed by capability **and** consumer, so one capability can have several
/// answers: an unavailable microphone signal means one thing to the suppression rule that
/// wanted it and something else to the analytics that merely counted it. The view collects the
/// **distinct** fallbacks across all ten consumers and draws each once, which is a true
/// statement about the table rather than a summary invented here. A capability whose ten
/// consumers all answer the same way therefore draws one line, which is the common case.
public struct CapabilityMatrixView: View {
    public let capabilities: CapabilityMatrix

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(capabilities: CapabilityMatrix) {
        self.capabilities = capabilities
    }

    /// The strings this surface always draws, asserted non-empty by the settings suite: a pane
    /// that renders nothing is a defect, not a design.
    nonisolated public static let contentKeys: [ShellStringKey] = [
        .capabilityHeading,
        .capabilityExplanation
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(.capabilityHeading, role: .headline)

            ShellText(.capabilityExplanation, role: .callout)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: spacing / 2) {
                ForEach(capabilities.allStates, id: \.capability) { entry in
                    row(capability: entry.capability, state: entry.state)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(.capabilityHeading)))
    }

    /// One capability: its name, its state, and — when it is not available — what happens
    /// instead.
    private func row(capability: Capability, state: CapabilityState) -> some View {
        VStack(alignment: .leading, spacing: spacing / 4) {
            HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
                Image(systemName: state.isUsable ? "checkmark.circle" : "minus.circle")
                    .foregroundStyle(DesignTokens.tint(for: state))
                    .accessibilityHidden(true)

                ShellText(Self.labelKey(for: capability), role: .callout)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: spacing / 2)

                ShellText(Self.labelKey(for: state), role: .callout)
                    .foregroundStyle(DesignTokens.tint(for: state))
            }

            ForEach(Self.fallbacks(for: capability, in: capabilities), id: \.token) { fallback in
                fallbackLine(fallback)
                    .padding(.leading, spacing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One fallback sentence. `degraded` names where it falls back to, because "falls back to
    /// something cheaper" is not an answer a person can check.
    @ViewBuilder
    private func fallbackLine(_ fallback: CapabilityFallback) -> some View {
        switch fallback {
        case .degraded(let destination):
            ShellText(
                .capabilityFallbackDegraded,
                role: .footnote,
                argument: ShellStrings.string(Self.labelKey(for: destination))
            )
            .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

        case .fullFunction, .featureAbsent, .suppressOnly, .showUnavailable:
            ShellText(Self.labelKey(for: fallback), role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The table, read rather than restated

    /// The distinct fallbacks a capability produces across every consumer, in a stable order.
    ///
    /// Empty when the capability is available: a capability that works needs no explanation,
    /// and printing "nothing depends on it" beside a working signal would be noise.
    nonisolated public static func fallbacks(
        for capability: Capability,
        in capabilities: CapabilityMatrix
    ) -> [CapabilityFallback] {
        guard !capabilities.isAvailable(capability) else { return [] }

        var seen: Set<String> = []
        var ordered: [CapabilityFallback] = []
        for consumer in SensingConsumer.allCases {
            let fallback = CapabilityContract.fallback(for: capability, consumer: consumer)
            guard seen.insert(fallback.token).inserted else { continue }
            ordered.append(fallback)
        }
        return ordered
    }

    // MARK: - Labels

    nonisolated public static func labelKey(for capability: Capability) -> ShellStringKey {
        switch capability {
        case .frontmostApplication: .capabilityNameFrontmostApplication
        case .windowMetadata: .capabilityNameWindowMetadata
        case .idle: .capabilityNameIdle
        case .systemLifecycle: .capabilityNameSystemLifecycle
        case .displayGeometry: .capabilityNameDisplayGeometry
        case .presentation: .capabilityNamePresentation
        case .microphoneActivity: .capabilityNameMicrophoneActivity
        case .cameraActivity: .capabilityNameCameraActivity
        case .accessibilityWindowContext: .capabilityNameAccessibilityWindowContext
        case .screenCapture: .capabilityNameScreenCapture
        case .notifications: .capabilityNameNotifications
        case .onDeviceModel: .capabilityNameOnDeviceModel
        }
    }

    /// The five states, in the user's language.
    ///
    /// The distinctions are load-bearing and the words keep them: `.unavailable` is not
    /// `.denied` — there is no camera on this Mac and nobody refused anything — and
    /// `.notRequested` is not `.denied` either, which in this epic means it never will be.
    nonisolated public static func labelKey(for state: CapabilityState) -> ShellStringKey {
        switch state {
        case .available: .capabilityStateAvailable
        case .denied: .capabilityStateDenied
        case .restricted: .capabilityStateRestricted
        case .unavailable: .capabilityStateUnavailable
        case .notRequested: .capabilityStateNotRequested
        }
    }

    nonisolated public static func labelKey(for fallback: CapabilityFallback) -> ShellStringKey {
        switch fallback {
        case .fullFunction: .capabilityFallbackFullFunction
        case .degraded: .capabilityFallbackDegraded
        case .featureAbsent: .capabilityFallbackFeatureAbsent
        case .suppressOnly: .capabilityFallbackSuppressOnly
        case .showUnavailable: .capabilityFallbackShowUnavailable
        }
    }
}

extension CapabilityFallback: Identifiable {
    /// A stable identity for `ForEach`. `degraded` carries its destination, so two fallbacks
    /// that differ only in where they fall back to are two rows rather than one.
    public var id: String { token }
}
