import FocusCore
import SwiftUI

// MARK: - One task

/// **One task, as a row** (task mirror): a check, the title, where it lives, and a pin.
///
/// The title is the source's own words, drawn verbatim. The reference (`work-os#12`) is a link
/// out to the task where it was made; a task from the local list has none. A task whose change
/// is still in the outbox says so, so a press that has not reached GitHub yet is never mistaken
/// for one that has.
struct TaskRow: View {
    let item: TaskBoardItem
    let model: TaskBoardModel?
    /// The priority a pin would attach this task to; `nil` hides the pin.
    let pinTarget: UUID?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    var body: some View {
        let actions = model?.actions
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Button {
                actions?.setDone(item.key, done: !item.isDone)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        item.isDone
                            ? DesignTokens.Palette.role(.spruce, for: traits)
                            : DesignTokens.supportingTextColor(for: traits)
                    )
            }
            .buttonStyle(.plain)
            .disabled(actions == nil)
            .accessibilityLabel(Text(ShellStrings.resource(item.isDone ? .tasksActionReopen : .tasksActionComplete)))
            .shellHelp(item.isDone ? .tasksActionReopenHelp : .tasksActionCompleteHelp)

            VStack(alignment: .leading, spacing: spacing / 4) {
                Text(verbatim: item.task.title)
                    .font(DesignTokens.font(.callout, scale: textScale))
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? DesignTokens.supportingTextColor(for: traits) : Color.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                if hasDetail {
                    HStack(spacing: spacing / 2) {
                        if let label = TaskBoardModel.sourceLabel(item) {
                            sourceLink(label)
                        }
                        ForEach(item.task.tags, id: \.self) { tag in
                            Text(verbatim: tag)
                                .font(DesignTokens.font(.caption, scale: textScale))
                                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        }
                        if item.pending != nil {
                            ShellText(.tasksPending, role: .caption)
                                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        }
                    }
                }
            }

            Spacer(minLength: spacing)

            if let pinTarget, !item.isDone {
                let pinned = item.pinnedTo == pinTarget
                Button {
                    actions?.pin(item.key, to: pinned ? nil : pinTarget)
                } label: {
                    Image(systemName: pinned ? "pin.slash" : "pin")
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                }
                .buttonStyle(.plain)
                .disabled(actions == nil)
                .accessibilityLabel(Text(ShellStrings.resource(pinned ? .tasksActionUnpin : .tasksActionPin)))
                .shellHelp(pinned ? .tasksActionUnpinHelp : .tasksActionPinHelp)
            }
        }
    }

    private var hasDetail: Bool {
        TaskBoardModel.sourceLabel(item) != nil || !item.task.tags.isEmpty || item.pending != nil
    }

    @ViewBuilder
    private func sourceLink(_ label: String) -> some View {
        if let url = item.task.url {
            Button {
                openURL(url)
            } label: {
                Label {
                    Text(verbatim: label)
                } icon: {
                    Image(systemName: "arrow.up.right.square")
                }
                .font(DesignTokens.font(.caption, scale: textScale))
                .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))
            }
            .buttonStyle(.plain)
            .shellHelp(.tasksActionOpenHelp)
        } else {
            Text(verbatim: label)
                .font(DesignTokens.font(.caption, scale: textScale))
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
        }
    }
}

// MARK: - Adding one

/// **The one-line add** (task mirror). Drawn only with a live host: an AppKit `TextField` draws
/// as SwiftUI's yellow placeholder under `ImageRenderer`, and a field that goes nowhere is worse
/// than none (the capture field's rule).
struct TaskQuickAdd: View {
    let model: TaskBoardModel
    let prompt: ShellStringKey
    /// Pin the new task to this priority as it is made.
    let pinTo: UUID?
    /// Give the new task these tags (the filter that is on, so it stays in view).
    var tags: [String] = []

    @State private var draft = ""
    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            TextField(text: $draft, prompt: Text(ShellStrings.resource(prompt))) {
                ShellText(prompt)
            }
            .labelsHidden()
            .font(DesignTokens.font(.callout, scale: textScale))
            .textFieldStyle(.plain)
            .padding(.horizontal, spacing)
            .padding(.vertical, spacing * 0.75)
            .softField(traits)
            .accessibilityLabel(Text(ShellStrings.resource(prompt)))
            .onSubmit(add)

            Button(action: add) {
                Image(systemName: "plus")
            }
            .disabled((try? TaskMirror.normalisedTitle(draft)) == nil || model.actions == nil)
            .accessibilityLabel(Text(ShellStrings.resource(.tasksAddAction)))
            .shellHelp(.tasksAddActionHelp)
        }
    }

    private func add() {
        guard let title = try? TaskMirror.normalisedTitle(draft), let actions = model.actions else { return }
        actions.create(title: title, source: nil, tags: tags, pinTo: pinTo)
        draft = ""
    }
}

// MARK: - The Tasks tab

/// **The cockpit's Tasks destination** (task mirror): the inbox of every task the configured
/// sources mirror, plus the ones made here.
///
/// Deliberately small. A row of label chips filters it, *Show done* brings the finished ones
/// back, and one line adds a task. Everything else — which repository, which labels, where new
/// tasks go — is Settings ▸ Tasks.
public struct TasksPane: View {
    let model: TaskBoardModel?
    /// The current priority, for the pin on each row.
    let priority: UUID?

    @State private var selectedTags: Set<String> = []
    @State private var includeDone = false
    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @Environment(\.openSettings) private var openSettings
    @ScaledMetric(relativeTo: .body) private var rowSpacing: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var sectionSpacing: CGFloat = 16

    public init(model: TaskBoardModel?, priority: UUID?) {
        self.model = model
        self.priority = priority
    }

    public var body: some View {
        let board = model?.board ?? .empty
        let items = board.items(tagged: Array(selectedTags), includeDone: includeDone)
        VStack(alignment: .leading, spacing: sectionSpacing) {
            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    CompanionSectionHeading(key: .tasksHeading, symbol: "checklist")
                    Spacer(minLength: rowSpacing)
                    showDoneButton
                }

                if !board.allTags.isEmpty { tagChips(board.allTags) }

                if let model, model.actions != nil {
                    TaskQuickAdd(model: model, prompt: .tasksAddPrompt, pinTo: nil, tags: selectedTags.sorted())
                }

                if items.isEmpty {
                    ShellText(.tasksEmpty, role: .footnote)
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(items) { item in
                        TaskRow(item: item, model: model, pinTarget: priority)
                            .padding(.vertical, rowSpacing / 4)
                        if item.id != items.last?.id { CompanionSeparator() }
                    }
                }
            }
            .companionSurface()

            footer(board)
        }
    }

    private var showDoneButton: some View {
        Button {
            includeDone.toggle()
        } label: {
            Label {
                ShellText(.tasksFilterDone, role: .callout)
            } icon: {
                Image(systemName: includeDone ? "checkmark.circle.fill" : "checkmark.circle")
            }
        }
        .buttonStyle(CompanionButtonStyle(selected: includeDone))
        .accessibilityAddTraits(includeDone ? [.isSelected] : [])
        .shellHelp(.tasksFilterDoneHelp)
    }

    private func tagChips(_ tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: rowSpacing / 2) {
                chip(selected: selectedTags.isEmpty) {
                    selectedTags.removeAll()
                } label: {
                    ShellText(.tasksFilterAll, role: .caption)
                }
                .shellHelp(.tasksFilterAllHelp)
                ForEach(tags, id: \.self) { tag in
                    let on = selectedTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                    chip(selected: on) {
                        if on {
                            selectedTags = selectedTags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
                        } else {
                            selectedTags.insert(tag)
                        }
                    } label: {
                        Text(verbatim: tag)
                            .font(DesignTokens.font(.caption, scale: textScale))
                    }
                    .shellHelp(.tasksFilterTagHelp)
                }
            }
        }
    }

    private func chip<Label: View>(
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(
                    selected
                        ? DesignTokens.Palette.role(.spruce, for: traits)
                        : DesignTokens.supportingTextColor(for: traits)
                )
                .padding(.horizontal, rowSpacing)
                .padding(.vertical, rowSpacing / 3)
                .contentInset(in: Capsule(), traits: traits)
                .overlay {
                    Capsule().strokeBorder(
                        DesignTokens.Palette.role(.spruce, for: traits).opacity(selected ? 0.8 : 0),
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Where the tasks came from and when, each source's last failure, and the two verbs that
    /// act on sources rather than tasks.
    private func footer(_ board: TaskBoard) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing / 2) {
            HStack(spacing: rowSpacing) {
                syncLine
                Spacer(minLength: rowSpacing)
                Button {
                    model?.actions?.syncNow()
                } label: {
                    Label {
                        ShellText(.tasksSyncAction, role: .callout)
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(model?.actions == nil || model?.isSyncing == true)
                .shellHelp(.tasksSyncActionHelp)

                Button {
                    openSettings()
                } label: {
                    Label {
                        ShellText(.tasksConfigure, role: .callout)
                    } icon: {
                        Image(systemName: "gearshape")
                    }
                }
                .shellHelp(.tasksConfigureHelp)
            }

            ForEach(board.sources.filter { $0.lastError != nil }, id: \.name) { status in
                Label {
                    ShellText(.tasksSourceError, role: .footnote, arguments: [status.name, status.lastError ?? ""])
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }

            if let problem = model?.syncProblem {
                Label {
                    ShellText(.tasksSyncProblem, role: .footnote, arguments: [problem])
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }
        }
    }

    @ViewBuilder
    private var syncLine: some View {
        Group {
            if model?.isSyncing == true {
                ShellText(.tasksSyncRunning, role: .footnote)
            } else if let last = model?.lastSyncedAt {
                ShellText(.tasksSyncLast, role: .footnote, arguments: [last.formatted(.relative(presentation: .named))])
            } else {
                ShellText(.tasksSyncNever, role: .footnote)
            }
        }
        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
    }
}

// MARK: - Subtasks on Now

/// **The priority's subtasks, on Now** (task mirror): the tasks pinned to it, open first, and a
/// line to add one. Draws nothing without a live board, so a snapshot of Now is unchanged.
public struct PinnedTasksSection: View {
    let model: TaskBoardModel?
    let priority: UUID

    @Environment(\.appearanceTraits) private var traits
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    public init(model: TaskBoardModel?, priority: UUID) {
        self.model = model
        self.priority = priority
    }

    public var body: some View {
        if let model, model.actions != nil {
            let items = model.board.pinned(to: priority)
            VStack(alignment: .leading, spacing: spacing) {
                CompanionSectionHeading(key: .tasksSubtasksHeading, symbol: "list.bullet.indent")
                ForEach(items) { item in
                    TaskRow(item: item, model: model, pinTarget: priority)
                        .padding(.vertical, spacing / 4)
                    CompanionSeparator()
                }
                TaskQuickAdd(model: model, prompt: .tasksSubtaskAddPrompt, pinTo: priority)
            }
            .companionSurface()
        }
    }
}
