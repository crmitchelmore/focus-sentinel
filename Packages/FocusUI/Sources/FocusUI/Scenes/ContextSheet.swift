import FocusCore
import SwiftUI

/// **What counts as work on this priority** (focus-g9iw).
///
/// The priority's context pack and its per-task rules, in one bounded sheet opened from Now's
/// *Configure context…*. They used to be a Details tab drawn beside a second copy of the
/// session, and it was hard to say what that tab was or how it connected to the priority above
/// it. They are one idea — what this piece of work looks like on this Mac — so they are one
/// sheet, titled with the priority they belong to and introduced by the sentence that says what
/// they are for.
///
/// Nothing here is new: the chips, the add controls and the rule rows are the same views the
/// tab drew, calling the same host verbs, so drag, paste, ⌘O, Quick Look and undo behave as they
/// did. The sheet invents no sensing of its own; it only edits what the engine already reads.
///
/// Every edit lands as it is made, so the one button is *Done* rather than a Save with a Cancel
/// beside it. Escape is the same Done.
public struct ContextSheet: View {
    /// The priority's own sentence, for the title. Verbatim, and free to wrap.
    public let intent: String
    public let contextItems: [ContextItemValue]
    public let rules: [PriorityRuleValue]
    public let addContext: (([ContextItemDraft]) -> Void)?
    public let removeContext: ((UUID) -> Void)?
    public let addRule: ((PriorityRuleScope, String, PriorityRuleVerdict) -> Void)?
    public let changeRule: ((UUID, PriorityRuleVerdict) -> Void)?
    public let removeRule: ((UUID) -> Void)?
    /// Bumped by the cockpit when ⌘O arrives while the sheet is already up.
    public let importRequest: Int
    /// Whether the sheet was opened by ⌘O, and so opens its file panel as soon as it appears.
    public let importsOnOpen: Bool
    public let done: () -> Void
    /// The displays this sheet bounds itself against; `nil` for the live ones.
    private let screens: ShellScreens

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState private var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    /// The token the context row's file panel listens to. Local, so a request that arrived
    /// before the sheet existed and one that arrives while it is up reach the panel the same way.
    @State private var importToken: Int = 0

    public init(
        intent: String,
        contextItems: [ContextItemValue],
        rules: [PriorityRuleValue],
        addContext: (([ContextItemDraft]) -> Void)? = nil,
        removeContext: ((UUID) -> Void)? = nil,
        addRule: ((PriorityRuleScope, String, PriorityRuleVerdict) -> Void)? = nil,
        changeRule: ((UUID, PriorityRuleVerdict) -> Void)? = nil,
        removeRule: ((UUID) -> Void)? = nil,
        importRequest: Int = 0,
        importsOnOpen: Bool = false,
        done: @escaping () -> Void,
        screens: ShellScreens = nil
    ) {
        self.intent = intent
        self.contextItems = contextItems
        self.rules = rules
        self.addContext = addContext
        self.removeContext = removeContext
        self.addRule = addRule
        self.changeRule = changeRule
        self.removeRule = removeRule
        self.importRequest = importRequest
        self.importsOnOpen = importsOnOpen
        self.done = done
        self.screens = screens
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            // `CompanionSectionHeading`'s furniture, with the priority's sentence as the catalog
            // title's one argument, so the sheet says whose context this is in the person's words.
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(DesignTokens.font(.callout, scale: textScale))
                    .accessibilityHidden(true)
                ShellText(.contextSheetTitle, role: .sectionHeading, argument: intent)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))

            ShellText(.contextSheetExplanation, role: .callout)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            ContextChipRow(
                items: contextItems,
                add: addContext,
                remove: removeContext,
                importFilesToken: importToken,
                focus: $focus
            )
            .walkthroughAnchor(.contextPack)

            CompanionSeparator()

            TaskRulesView(
                rules: rules,
                add: addRule,
                change: changeRule,
                remove: removeRule,
                focus: $focus
            )
            .walkthroughAnchor(.rules)

            HStack(spacing: spacing) {
                Spacer(minLength: 0)

                // Escape, not Return: this sheet is full of fields whose Return adds a keyword or
                // a rule, and a default button would collect every Return a field did not claim.
                Button(action: done) {
                    ShellText(.contextSheetDone)
                }
                .keyboardShortcut(.cancelAction)
                .focused($focus, equals: .contextSheetDone)
                .shellHelp(.contextSheetDoneHelp)
            }
        }
        .dialogInset()
        .buttonStyle(CompanionButtonStyle())
        .boundedSheet(width: ShellSurfaceBounds.contextSheetWidth, screens: screens)
        .background(DesignTokens.Palette.windowBackground(for: traits))
        .task {
            if importsOnOpen { importToken &+= 1 }
        }
        .onChange(of: importRequest) { importToken &+= 1 }
    }
}
