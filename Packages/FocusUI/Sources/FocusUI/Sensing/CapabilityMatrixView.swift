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
/// ## Where the fallback sentences come from — and why each one names its consumers
///
/// The contract is indexed by capability **and** consumer, so one capability can have several
/// answers: an unavailable microphone signal means one thing to the suppression rule that
/// wanted it and something else to the analytics that merely counted it. The view collects the
/// **distinct** fallbacks across all ten consumers and draws each once, which is a true
/// statement about the table rather than a summary invented here.
///
/// **Each line names the consumers it is true of, and it did not** (focus-doc). Read by eye in
/// the committed baseline `privacySettings.reduceMotion.standard.png`, the row for *"Which app
/// is in front"* printed four unattributed sentences one under another:
///
/// > There is nothing to fall back to, so the app says so.
/// > That part of the app does not run.
/// > The app does less, never more.
/// > Nothing depends on it.
///
/// Per consumer each is true. Rendered together they contradict one another, and the last is
/// plainly false of an app whose own Watching section two inches above reads *"The app in front
/// is in a window."* The comment on `capability.fallback.fullFunction` said as much: *"What
/// happens instead when a capability is missing"* — an **app-level** claim, written as one and
/// rendered as one.
///
/// The fix is both halves of what the bug asked for. `fallbacks(for:in:)` now returns each
/// distinct answer **with the consumers that give it**, and every fallback string was reworded
/// into a predicate — *"carries on unchanged."*, *"does not run."* — so that none of them can be
/// read as a claim about the app even in isolation.
///
/// ## This is the only place the matrix composes several consumers into one line
///
/// Checked, per the bug's second half: the capability column is one name per capability
/// (`labelKey(for: Capability)`), and the state column is one `CapabilityState` per capability
/// read straight off `CapabilityMatrix.allStates` — neither folds a per-consumer value. The
/// fallback list was the only fold, and it is now attributed.
public struct CapabilityMatrixView: View {
    public let capabilities: CapabilityMatrix

    @Environment(\.appearanceTraits) private var traits
    /// Read here, not only inside `ShellText`, because the fallback lines compose two authored
    /// catalog strings into the arguments of a third — see `fallbackLine(_:consumers:)`.
    @Environment(\.shellStringTransform) private var transform
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

            ForEach(Self.fallbacks(for: capability, in: capabilities), id: \.fallback.token) { row in
                fallbackLine(row.fallback, consumers: row.consumers)
                    .padding(.leading, spacing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One fallback line: **whose** fallback it is, then what they do instead.
    ///
    /// `degraded` names where it falls back to, because "falls back to something cheaper" is not
    /// an answer a person can check.
    /// Both halves go through the **string transform** before they are substituted, which is
    /// what keeps the pseudo-localisation lane honest: `ShellText` expands the format it is
    /// given and leaves its arguments alone by design — that is right for the user's own words
    /// and wrong here, where every argument is authored catalog prose. Without this the matrix
    /// would draw a 2× heading over unexpanded fallback lines and the lane would report a row
    /// narrower than any translation will ever make it.
    private func fallbackLine(
        _ fallback: CapabilityFallback,
        consumers: [SensingConsumer]
    ) -> some View {
        ShellText(
            .capabilityFallbackAttributed,
            role: .footnote,
            arguments: [
                Self.subject(consumers, transform: transform),
                Self.predicate(fallback, transform: transform)
            ]
        )
        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The consumers this line is true of, as a list in the reader's own language.
    ///
    /// `.list(type: .and)` rather than a joined `", "`: the separator and the final conjunction
    /// are the locale's, which is the same reason every number in this app goes through
    /// `.formatted()`.
    nonisolated public static func subject(
        _ consumers: [SensingConsumer],
        transform: ShellStringTransform = .identity
    ) -> String {
        consumers
            .map { transform(ShellStrings.string(Self.labelKey(for: $0))) }
            .formatted(.list(type: .and))
    }

    /// What they do instead — a predicate, never a whole sentence (focus-doc).
    nonisolated public static func predicate(
        _ fallback: CapabilityFallback,
        transform: ShellStringTransform = .identity
    ) -> String {
        switch fallback {
        case .degraded(let destination):
            String(
                format: transform(ShellStrings.string(.capabilityFallbackDegraded)),
                transform(ShellStrings.string(Self.labelKey(for: destination)))
            )
        case .fullFunction, .featureAbsent, .suppressOnly, .showUnavailable:
            transform(ShellStrings.string(Self.labelKey(for: fallback)))
        }
    }

    // MARK: - The table, read rather than restated

    /// The distinct fallbacks a capability produces, **each with the consumers that give it**,
    /// in a stable order.
    ///
    /// Empty when the capability is available: a capability that works needs no explanation,
    /// and printing "carries on unchanged" beside a working signal would be noise.
    ///
    /// It returned the bare fallbacks until focus-doc, which is what let four contradicting
    /// sentences be drawn one under another with nothing saying who each was about.
    ///
    /// **What changed comes before what did not.** `fullFunction` is the complement of the
    /// interesting answers and is usually the longest list — eight of the ten consumers, under a
    /// capability whose one real degradation is on the line below. Drawn in consumer order it
    /// arrived first and buried the answer a person came to this pane for. It is not dropped: a
    /// row that says which parts are untouched is a row somebody can check, and this pane exists
    /// to be checked.
    nonisolated public static func fallbacks(
        for capability: Capability,
        in capabilities: CapabilityMatrix
    ) -> [(fallback: CapabilityFallback, consumers: [SensingConsumer])] {
        guard !capabilities.isAvailable(capability) else { return [] }

        var order: [String] = []
        var grouped: [String: (CapabilityFallback, [SensingConsumer])] = [:]
        for consumer in SensingConsumer.allCases {
            let fallback = CapabilityContract.fallback(for: capability, consumer: consumer)
            if var entry = grouped[fallback.token] {
                entry.1.append(consumer)
                grouped[fallback.token] = entry
            } else {
                order.append(fallback.token)
                grouped[fallback.token] = (fallback, [consumer])
            }
        }
        let unchanged = CapabilityFallback.fullFunction.token
        return (order.filter { $0 != unchanged } + order.filter { $0 == unchanged })
            .map { (fallback: grouped[$0]!.0, consumers: grouped[$0]!.1) }
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

    /// The ten consumers, named. This is the subject the fallback sentences were missing.
    nonisolated public static func labelKey(for consumer: SensingConsumer) -> ShellStringKey {
        switch consumer {
        case .activationTimeline: .capabilityConsumerActivationTimeline
        case .dwellAttribution: .capabilityConsumerDwellAttribution
        case .displayFairness: .capabilityConsumerDisplayFairness
        case .presentationSuppression: .capabilityConsumerPresentationSuppression
        case .mediaSuppression: .capabilityConsumerMediaSuppression
        case .lifecyclePause: .capabilityConsumerLifecyclePause
        case .idlePause: .capabilityConsumerIdlePause
        case .classification: .capabilityConsumerClassification
        case .nudgeLadder: .capabilityConsumerNudgeLadder
        case .analytics: .capabilityConsumerAnalytics
        }
    }
}

extension CapabilityFallback: Identifiable {
    /// A stable identity for `ForEach`. `degraded` carries its destination, so two fallbacks
    /// that differ only in where they fall back to are two rows rather than one.
    public var id: String { token }
}
