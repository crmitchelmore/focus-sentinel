import FocusCore
import SwiftUI

/// Everything the cockpit draws, as a value.
///
/// The view is handed this by the app's composition root; it never reaches for a sensing or
/// classification type of its own. That one-way rule is what keeps `FocusUI` free of any
/// dependency on `FocusSensing` and `FocusClassify` — and therefore what makes the privacy
/// posture checkable from the dependency graph rather than by reading code.
public struct CockpitState: Sendable, Equatable, Hashable {
    /// What the app currently believes about the user's context.
    public var status: FocusStatus
    /// Whether the local data store opened.
    public var storeIsReady: Bool
    /// Whether any activity source is actually running.
    public var isObservingActivity: Bool

    public init(status: FocusStatus, storeIsReady: Bool, isObservingActivity: Bool) {
        self.status = status
        self.storeIsReady = storeIsReady
        self.isObservingActivity = isObservingActivity
    }

    /// What the shell reports in e01: the store is open, nothing is being observed yet, and
    /// the status is therefore `paused`.
    ///
    /// `paused` is the honest answer, not a stand-in. The app has observed nothing and so
    /// has judged nothing; showing `relevant` or `unrelated` here would be inventing a
    /// verdict it has no basis for.
    public static let ready = CockpitState(
        status: .paused,
        storeIsReady: true,
        isObservingActivity: false
    )

    /// The degraded state: the store could not be opened, so nothing will be saved.
    public static let storeUnavailable = CockpitState(
        status: .paused,
        storeIsReady: false,
        isObservingActivity: false
    )
}

/// The cockpit: one column, no sidebar, no custom chrome.
///
/// Deliberately **not** a `NavigationSplitView`. A sidebar ships in e09, with its last real
/// destination; an empty "Insights" row today would be a surface with nothing behind it.
///
/// Everything that has to survive an accessibility text size is written for it: spacing is
/// `@ScaledMetric`, the header collapses from a row to a column through `ViewThatFits`, and
/// every label that carries meaning is `lineLimit(nil)` and free to grow vertically.
public struct CockpitView: View {
    public let state: CockpitState

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.openSettings) private var openSettings
    @FocusState private var focus: FocusField?

    @ScaledMetric(relativeTo: .body) private var rowSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .largeTitle) private var sectionSpacing: CGFloat = 20

    public init(state: CockpitState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: rowSpacing) {
                    heading
                    Spacer(minLength: rowSpacing)
                    StatusBadge(status: state.status)
                }
                VStack(alignment: .leading, spacing: rowSpacing) {
                    heading
                    StatusBadge(status: state.status)
                }
            }

            VStack(alignment: .leading, spacing: rowSpacing) {
                detail(
                    systemImage: state.storeIsReady
                        ? "internaldrive.fill"
                        : "exclamationmark.triangle.fill",
                    key: state.storeIsReady ? .cockpitStoreReady : .cockpitStoreUnavailable
                )
                detail(
                    systemImage: state.isObservingActivity ? "eye" : "eye.slash",
                    key: .cockpitSensingUnavailable
                )
            }

            Button {
                openSettings()
            } label: {
                ShellText(.cockpitOpenSettings)
            }
            .keyboardShortcut(.defaultAction)
            .focused($focus, equals: .cockpitOpenSettings)

            Spacer(minLength: 0)
        }
        .padding(sectionSpacing)
        .frame(minWidth: 420, minHeight: 260, alignment: .topLeading)
        .background(DesignTokens.Palette.windowBackground)
        .defaultFocus($focus, .cockpitOpenSettings)
    }

    private var heading: some View {
        ShellText(.cockpitHeading)
            .font(.largeTitle)
            .fontWeight(.semibold)
            .foregroundStyle(DesignTokens.Palette.primaryText)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One supporting line: a glyph, then text that is free to wrap as far as it needs to.
    private func detail(systemImage: String, key: ShellStringKey) -> some View {
        Label {
            ShellText(key)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
    }
}
