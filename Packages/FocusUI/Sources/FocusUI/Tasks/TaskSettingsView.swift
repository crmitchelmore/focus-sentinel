import FocusCore
import SwiftUI

/// **Settings ▸ Tasks** (task mirror): the sources the Tasks tab mirrors.
///
/// Each source is one GitHub repository's issues or one GitHub project's items, optionally
/// narrowed to some labels. The app never talks to GitHub itself: `focus-bridge` does, with the
/// `gh` CLI's sign-in, and writes what it read beside the store. A source added here is written
/// to the same `config.json` the bridge's `tasks add-source` writes.
///
/// The provider is two buttons rather than a `Picker`, and the fields only draw with a live
/// host, for the reason the capture field gives: AppKit controls rasterise as placeholders.
public struct TaskSettingsView: View {
    let model: TaskBoardModel?

    @State private var provider: TaskProviderKind = .githubIssues
    @State private var name = ""
    @State private var repository = ""
    @State private var owner = ""
    @State private var number = ""
    @State private var account = ""
    @State private var labels = ""
    @State private var addFailed = false

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 12

    public init(model: TaskBoardModel?) {
        self.model = model
    }

    public var body: some View {
        BoundedSurface(
            width: ShellSurfaceBounds.settingsWidth,
            ceiling: ShellSurfaceBounds.settingsCeiling(screens: NudgePanelController.currentScreens())
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing, scale: textScale)) {
                CompanionHeader { ShellText(.settingsTasksTitle, role: .title2) }
                sourcesSection
                    .companionSurface()
                if let model, model.actions != nil {
                    addSection(model)
                        .companionSurface()
                }
                ShellText(.settingsTasksFootnote, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .dialogInset()
            .contentGround(traits)
            .buttonStyle(CompanionButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - The sources

    private var sourcesSection: some View {
        let config = model?.config ?? TaskMirrorConfig()
        let statuses = model?.board.sources ?? []
        return VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            CompanionSectionHeading(key: .settingsTasksSourcesHeading, symbol: "tray.2")
            if config.sources.isEmpty {
                ShellText(.settingsTasksSourcesEmpty, role: .footnote)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(config.sources, id: \.name) { source in
                sourceRow(source, status: statuses.first { $0.name == source.name }, config: config)
                if source.name != config.sources.last?.name { CompanionSeparator() }
            }
        }
    }

    private func sourceRow(_ source: TaskSourceConfig, status: TaskSourceStatus?, config: TaskMirrorConfig) -> some View {
        let isDefault = config.createSource == source.name
        return HStack(alignment: .firstTextBaseline, spacing: spacing / 2) {
            VStack(alignment: .leading, spacing: spacing / 4) {
                Text(verbatim: source.name)
                    .font(DesignTokens.font(.headline, scale: textScale))
                Text(verbatim: Self.describe(source))
                    .font(DesignTokens.font(.caption, scale: textScale))
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                statusLine(status)
                if isDefault {
                    ShellText(.settingsTasksSourceIsDefault, role: .caption)
                        .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))
                }
            }
            Spacer(minLength: spacing / 2)
            if !isDefault {
                Button {
                    var next = config
                    next.createSource = source.name
                    model?.actions?.saveConfig(next)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(model?.actions == nil)
                .accessibilityLabel(Text(ShellStrings.resource(.settingsTasksSourceMakeDefault)))
                .shellHelp(.settingsTasksSourceMakeDefaultHelp)
            }
            Button {
                var next = config
                next.remove(named: source.name)
                model?.actions?.saveConfig(next)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(model?.actions == nil)
            .accessibilityLabel(Text(ShellStrings.resource(.settingsTasksSourceRemove)))
            .shellHelp(.settingsTasksSourceRemoveHelp)
        }
    }

    @ViewBuilder
    private func statusLine(_ status: TaskSourceStatus?) -> some View {
        Group {
            if let status, let error = status.lastError {
                ShellText(.settingsTasksSourceFailed, role: .caption, arguments: [error])
            } else if let status, let synced = status.syncedAt {
                ShellText(
                    .settingsTasksSourceSynced,
                    role: .caption,
                    arguments: [status.taskCount.formatted(), synced.formatted(.relative(presentation: .named))]
                )
            } else {
                ShellText(.settingsTasksSourceNotSynced, role: .caption)
            }
        }
        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `owner/repo` or `owner #3`, then the labels it is narrowed to — data, so drawn verbatim.
    static func describe(_ source: TaskSourceConfig) -> String {
        var where_: String
        switch source.providerKind {
        case .githubIssues, nil:
            where_ = source.settings["repository"] ?? ""
        case .githubProject:
            where_ = "\(source.settings["owner"] ?? "") #\(source.settings["number"] ?? "")"
        }
        if !source.tags.isEmpty { where_ += " · " + source.tags.joined(separator: ", ") }
        return where_
    }

    // MARK: - Adding one

    private func addSection(_ model: TaskBoardModel) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing(spacing / 2, scale: textScale)) {
            CompanionSectionHeading(key: .settingsTasksAddHeading, symbol: "plus.circle")
            HStack(spacing: spacing / 2) {
                providerButton(.githubIssues, key: .settingsTasksProviderIssues)
                providerButton(.githubProject, key: .settingsTasksProviderProject)
            }
            field(.settingsTasksFieldName, prompt: .settingsTasksFieldNamePrompt, text: $name)
            if provider == .githubIssues {
                field(.settingsTasksFieldRepository, prompt: .settingsTasksFieldRepositoryPrompt, text: $repository)
            } else {
                field(.settingsTasksFieldOwner, prompt: .settingsTasksFieldOwnerPrompt, text: $owner)
                field(.settingsTasksFieldNumber, prompt: .settingsTasksFieldNumberPrompt, text: $number)
            }
            field(.settingsTasksFieldLabels, prompt: .settingsTasksFieldLabelsPrompt, text: $labels)
            field(.settingsTasksFieldAccount, prompt: .settingsTasksFieldAccountPrompt, text: $account)
            if addFailed {
                ShellText(.settingsTasksAddInvalid, role: .footnote)
                    .foregroundStyle(DesignTokens.Palette.role(.slate, for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                add(model)
            } label: {
                ShellText(.settingsTasksAddAction)
            }
            .buttonStyle(CompanionButtonStyle(prominent: true))
            .shellHelp(.settingsTasksAddActionHelp)
        }
    }

    private func providerButton(_ kind: TaskProviderKind, key: ShellStringKey) -> some View {
        Button {
            provider = kind
        } label: {
            ShellText(key, role: .callout)
        }
        .buttonStyle(CompanionButtonStyle(selected: provider == kind))
        .accessibilityAddTraits(provider == kind ? [.isSelected] : [])
        .shellHelp(kind == .githubIssues ? .settingsTasksProviderIssuesHelp : .settingsTasksProviderProjectHelp)
    }

    private func field(_ label: ShellStringKey, prompt: ShellStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: spacing / 4) {
            ShellText(label, role: .caption)
                .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            TextField(text: text, prompt: Text(ShellStrings.resource(prompt))) {
                ShellText(label)
            }
            .labelsHidden()
            .font(DesignTokens.font(.callout, scale: textScale))
            .textFieldStyle(.plain)
            .padding(8)
            .softField(traits)
            .accessibilityLabel(Text(ShellStrings.resource(label)))
        }
    }

    private func add(_ model: TaskBoardModel) {
        guard let source = draftSource(), (try? TaskMirror.validate(source)) != nil,
              let actions = model.actions else {
            addFailed = true
            return
        }
        var next = model.config
        next.upsert(source)
        actions.saveConfig(next)
        addFailed = false
        name = ""; repository = ""; owner = ""; number = ""; account = ""; labels = ""
    }

    /// The form as a source, or `nil` when a required field is empty.
    func draftSource() -> TaskSourceConfig? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard TaskMirror.isValidSourceName(trimmedName) else { return nil }
        var settings: [String: String] = [:]
        switch provider {
        case .githubIssues:
            let repo = repository.trimmingCharacters(in: .whitespaces)
            guard repo.split(separator: "/").count == 2 else { return nil }
            settings["repository"] = repo
        case .githubProject:
            let ownerValue = owner.trimmingCharacters(in: .whitespaces)
            let numberValue = number.trimmingCharacters(in: .whitespaces)
            guard !ownerValue.isEmpty, Int(numberValue) != nil else { return nil }
            settings["owner"] = ownerValue
            settings["number"] = numberValue
        }
        let accountValue = account.trimmingCharacters(in: .whitespaces)
        if !accountValue.isEmpty { settings["account"] = accountValue }
        return TaskSourceConfig(
            name: trimmedName,
            provider: provider.rawValue,
            settings: settings,
            tags: TaskMirror.parseTags(labels)
        )
    }
}
