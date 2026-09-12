import FocusCore
import SwiftUI

/// **One page of the walkthrough** (focus-u6de).
///
/// A closed vocabulary rather than an array of views, for the reason every other vocabulary in
/// this package is one: the test lane folds over `allCases` to hold that every page has a
/// title, that every paragraph key belongs to exactly one page, and that the first page is
/// still the privacy statement `FirstRunSheet` shipped as focus-odz.7. A page added without a
/// title does not compile; a key added without a page fails the bijection.
///
/// The order is the declaration order. It reads the way a person meets the app: what it looks
/// at, the one priority, the time around it, the desk and the rules, how the app speaks, where
/// it lives in the menu bar, and where the settings and the data are. The first page is the
/// sheet's; the rest are the floating tour's, and each of those carries the `actions` that do
/// its subject in the real app (`WalkthroughAction`).
public enum WalkthroughPage: String, Sendable, CaseIterable, Hashable, Identifiable {
    /// What the app observes and what it never observes. The first-run explanation, unchanged.
    case watches
    /// The one priority, its definition of done, and the daily prompt.
    case priority
    /// The timebox, the session, and the history.
    case time
    /// The context pack and the per-task rules.
    case desk
    /// The two rungs, the question, and the caps that bound them.
    case nudges
    /// The status item, the popover, and the keyboard.
    case menuBar
    /// The three Settings panes, the data, and how to read this again.
    case settings

    public var id: String { rawValue }

    /// The heading the companion header draws for this page.
    public var titleKey: ShellStringKey {
        switch self {
        case .watches: .firstRunTitle
        case .priority: .walkthroughPriorityTitle
        case .time: .walkthroughTimeTitle
        case .desk: .walkthroughDeskTitle
        case .nudges: .walkthroughNudgesTitle
        case .menuBar: .walkthroughMenuBarTitle
        case .settings: .walkthroughSettingsTitle
        }
    }

    /// The paragraphs, each with the SF Symbol drawn beside it.
    ///
    /// The symbols are navigation cues in `CompanionSectionHeading`'s sense: they mark the
    /// paragraph and carry no status, which is why none of them is a status mark.
    public var paragraphs: [WalkthroughParagraph] {
        switch self {
        case .watches:
            [
                WalkthroughParagraph(key: .firstRunObserves, symbol: "eye"),
                WalkthroughParagraph(key: .firstRunNever, symbol: "lock.shield"),
                WalkthroughParagraph(key: .firstRunPermissions, symbol: "hand.raised")
            ]
        case .priority:
            [
                WalkthroughParagraph(key: .walkthroughPriorityOne, symbol: "scope"),
                WalkthroughParagraph(key: .walkthroughPriorityDoneWhen, symbol: "checkmark.seal"),
                WalkthroughParagraph(key: .walkthroughPriorityRefine, symbol: "text.badge.checkmark"),
                WalkthroughParagraph(key: .walkthroughPriorityRitual, symbol: "sun.max")
            ]
        case .time:
            [
                WalkthroughParagraph(key: .walkthroughTimeTimebox, symbol: "timer"),
                WalkthroughParagraph(key: .walkthroughTimeSession, symbol: "play.circle"),
                WalkthroughParagraph(key: .walkthroughTimeStop, symbol: "stop.circle"),
                WalkthroughParagraph(key: .walkthroughTimeRecent, symbol: "clock.arrow.circlepath")
            ]
        case .desk:
            [
                WalkthroughParagraph(key: .walkthroughDeskPack, symbol: "tray.full"),
                WalkthroughParagraph(key: .walkthroughDeskJudgement, symbol: "checkmark.circle"),
                WalkthroughParagraph(key: .walkthroughDeskRules, symbol: "list.bullet.rectangle")
            ]
        case .nudges:
            [
                WalkthroughParagraph(key: .walkthroughNudgesGlyph, symbol: "circle.dashed"),
                WalkthroughParagraph(key: .walkthroughNudgesPanel, symbol: "rectangle.on.rectangle"),
                WalkthroughParagraph(key: .walkthroughNudgesQuestion, symbol: "questionmark.circle"),
                WalkthroughParagraph(key: .walkthroughNudgesAnswers, symbol: "hand.raised"),
                WalkthroughParagraph(key: .walkthroughNudgesLimits, symbol: "bell.slash")
            ]
        case .menuBar:
            [
                WalkthroughParagraph(key: .walkthroughMenuBarMark, symbol: "menubar.rectangle"),
                WalkthroughParagraph(key: .walkthroughMenuBarCapture, symbol: "keyboard"),
                WalkthroughParagraph(key: .walkthroughMenuBarShortcuts, symbol: "command")
            ]
        case .settings:
            [
                WalkthroughParagraph(key: .walkthroughSettingsIntervention, symbol: "bell.badge"),
                WalkthroughParagraph(key: .walkthroughSettingsPrivacy, symbol: "hand.raised"),
                WalkthroughParagraph(key: .walkthroughSettingsData, symbol: "square.and.arrow.up"),
                WalkthroughParagraph(key: .walkthroughSettingsReplay, symbol: "arrow.counterclockwise")
            ]
        }
    }

    /// Whether this page draws the store path under its paragraphs. Only the first: it is the
    /// one screen that says where the data lives, and the path is the same one Settings ▸
    /// Privacy draws.
    public var showsStoreLocation: Bool { self == .watches }

    /// The page after this one, or `nil` on the last.
    public var next: WalkthroughPage? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// The page before this one, or `nil` on the first.
    public var previous: WalkthroughPage? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index > 0 else { return nil }
        return all[index - 1]
    }

    /// Where this page sits, counted from one, for the "n of m" line.
    public var ordinal: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// The first page, which is the page the first launch opens on and the page a replay
    /// starts from.
    public static let first: WalkthroughPage = allCases[0]
    public static let last: WalkthroughPage = allCases[allCases.count - 1]
}

/// One paragraph of a walkthrough page: a catalog key and the symbol drawn beside it.
public struct WalkthroughParagraph: Sendable, Equatable, Hashable, Identifiable {
    public let key: ShellStringKey
    public let symbol: String

    public var id: String { key.rawValue }

    public init(key: ShellStringKey, symbol: String) {
        self.key = key
        self.symbol = symbol
    }
}

/// **The walkthrough's first page: what this app looks at, before it has looked at anything**
/// (focus-odz.7, focus-u6de).
///
/// ## What it is for
///
/// `FirstRunSheet` was one screen shown once, and it said what the app observes. That claim is
/// still this sheet, word for word: it is read before anything is touched, on a first launch
/// against a store the app has never opened, and again whenever the walkthrough is asked for.
/// Its one button, *Continue*, closes it and opens the **tour** — a floating panel beside the
/// cockpit that walks the other six pages and does each one in the real app
/// (`WalkthroughPanelController`, `WalkthroughAction`). The pages themselves are one
/// vocabulary, `WalkthroughPage`; this sheet draws its first member and the panel draws the rest.
///
/// ## Shown on the first launch, and again whenever it is asked for
///
/// The first showing is the host's decision, exactly as before: `CockpitState.showsFirstRunExplanation`
/// is `true` on a launch that opened a store the app has never opened, the showing is written
/// down at that moment, and every route out goes through `onFirstRunExplanationDismissed`. A
/// replay is the cockpit's: `PriorityCommand.showWalkthrough` arrives from the Help menu or from
/// Settings ▸ General and sets a local flag that presents this same sheet. Nothing is written for
/// a replay.
///
/// ## Return and Escape
///
/// Return is Continue. There is nothing to lose by pressing it: the sheet holds no field and
/// changes nothing, and the tour it opens does nothing until one of its own buttons is pressed.
/// Escape does nothing on a first showing, for `StoreUnavailableSheet`'s reason, and closes a
/// replay without opening the tour.
public struct WalkthroughSheet: View {
    /// Where this app's store lives. The same path the Privacy pane draws.
    public let storeLocation: String
    /// What Continue does after closing the sheet: opens the tour. Escape on a replay does not.
    public let dismiss: () -> Void
    /// Whether Escape closes the sheet. `false` on a first showing, `true` on a replay.
    public let escapeDismisses: Bool
    /// What Escape performs on a replay: the same route out as `dismiss`, without the tour.
    public let cancel: () -> Void
    /// The displays this sheet bounds itself against; `nil` for the live ones.
    private let screens: ShellScreens

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    /// The page this sheet draws: the first, always.
    public static let page: WalkthroughPage = .first

    public init(
        storeLocation: String,
        dismiss: @escaping () -> Void,
        escapeDismisses: Bool = false,
        cancel: (() -> Void)? = nil,
        screens: ShellScreens = nil
    ) {
        self.storeLocation = storeLocation
        self.dismiss = dismiss
        self.escapeDismisses = escapeDismisses
        self.cancel = cancel ?? dismiss
        self.screens = screens
    }

    public var body: some View {
        content.boundedSheet(width: ShellSurfaceBounds.handoffSheetWidth, screens: screens)
    }

    private var content: some View {
        let page = Self.page
        return VStack(alignment: .leading, spacing: spacing) {
            CompanionHeader { ShellText(page.titleKey, role: .title2) }

            ForEach(page.paragraphs) { paragraph in
                self.paragraph(paragraph)
            }

            ShellText(.firstRunStoreLabel, role: .callout)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            // **The path, drawn as a value and never as prose**, the same decision the Privacy
            // pane and the store-failure sheet make, and it is the same path. Monospaced because
            // it is a path, and selectable because somebody being told where their data lives
            // will want to go and look at it.
            Text(verbatim: storeLocation)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            ShellText(.walkthroughContinueNote, role: .footnote)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: spacing) {
                Spacer(minLength: 0)
                Button(action: dismiss) {
                    ShellText(.walkthroughContinue)
                }
                .buttonStyle(CompanionButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(spacing * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Palette.windowBackground(for: traits))
        .onExitCommand {
            if escapeDismisses { cancel() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ShellStrings.resource(page.titleKey)))
    }

    private func paragraph(_ paragraph: WalkthroughParagraph) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: paragraph.symbol)
                .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))
                .frame(width: 24)
                .accessibilityHidden(true)
            ShellText(paragraph.key, role: .callout)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}
