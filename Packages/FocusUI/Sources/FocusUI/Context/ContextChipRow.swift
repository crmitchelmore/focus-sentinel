import FocusCore
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// The task's context pack: apps, sites, keywords and files, with the three ways of adding
/// one — dragging, pasting, and asking.
///
/// **Quick Look is the reason `QuickLook` is imported.** `.quickLookPreview(_:in:)` is *not*
/// in SwiftUI: it lives in the `_QuickLook_SwiftUI` cross-import overlay and only exists once
/// `QuickLook` is imported alongside it (P-62). `QLPreviewPanel` is never driven by hand —
/// measured, its `orderOut(nil)` leaves `isVisible == true`, so its bookkeeping is not what it
/// appears to be.
///
/// **A missing attachment is never removed.** The chip says *Missing* and offers *Locate…*.
/// Re-attaching is a remove and an add through the same undoable facade as everything else.
///
/// With no mutation host attached the row draws the chips and nothing else — no fields, no
/// buttons. See `CockpitView.showsCapture` for why a read-only render carries no controls.
public struct ContextChipRow: View {
    public let items: [ContextItemValue]
    /// Add whatever was dropped, pasted, typed or chosen.
    public let add: (([ContextItemDraft]) -> Void)?
    public let remove: ((UUID) -> Void)?
    /// Bumped by the surrounding surface to open the file importer from the File menu (⌘O).
    /// A token rather than a binding, so the row keeps sole ownership of its own sheet state.
    public let importFilesToken: Int

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @FocusState.Binding var focus: FocusField?
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8

    @State private var keyword: String = ""
    @State private var isImportingFiles: Bool = false
    /// The item being re-attached, if the user is in the middle of locating a moved file.
    @State private var relocating: UUID?
    /// The file URLs Quick Look can page through, resolved off the render path.
    @State private var previewURLs: [URL] = []
    @State private var quickLookSelection: URL?

    public init(
        items: [ContextItemValue],
        add: (([ContextItemDraft]) -> Void)? = nil,
        remove: ((UUID) -> Void)? = nil,
        importFilesToken: Int = 0,
        focus: FocusState<FocusField?>.Binding
    ) {
        self.items = items
        self.add = add
        self.remove = remove
        self.importFilesToken = importFilesToken
        self._focus = focus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ShellText(.contextHeading, role: .sectionHeading)
                .foregroundStyle(DesignTokens.Palette.role(.spruce, for: traits))

            if items.isEmpty {
                ShellText(.contextEmpty, role: .callout)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ChipFlowLayout(spacing: spacing) {
                    ForEach(items) { item in
                        ContextChip(
                            item: item,
                            preview: item.kind == .file ? { preview(item) } : nil,
                            locate: add == nil ? nil : { beginRelocating(item) },
                            remove: remove.map { removeItem in { removeItem(item.id) } }
                        )
                    }
                }
            }

            if add != nil {
                controls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextDropTarget(isEnabled: add != nil) { drafts in
            add?(drafts)
        }
        .quickLookPreview($quickLookSelection, in: previewURLs)
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: relocating == nil
        ) { result in
            handleImport(result)
        }
        // Resolving bookmarks touches the disk, so it happens off the render path and only
        // when the set of file attachments actually changes.
        .task(id: items.filter { $0.kind == .file }.map(\.id)) {
            previewURLs = resolvedFileURLs()
        }
        .onChange(of: importFilesToken) {
            guard add != nil else { return }
            relocating = nil
            isImportingFiles = true
        }
    }

    // MARK: - Adding

    private var controls: some View {
        HStack(spacing: spacing) {
            TextField(
                text: $keyword,
                prompt: Text(ShellStrings.resource(.contextKeywordPrompt))
            ) {
                ShellText(.contextKeywordPrompt)
            }
            .labelsHidden()
            .font(DesignTokens.font(.callout, scale: textScale))
            .focused($focus, equals: .cockpitContextKeyword)
            .onSubmit(addKeyword)
            .accessibilityLabel(Text(ShellStrings.resource(.contextKeywordPrompt)))

            Button(action: addKeyword) {
                ShellText(.contextActionAddKeyword)
            }
            .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                relocating = nil
                isImportingFiles = true
            } label: {
                ShellText(.contextActionAddFiles)
            }
            .focused($focus, equals: .cockpitContextAddFiles)

            Spacer(minLength: 0)
        }
    }

    private func addKeyword() {
        guard let draft = ContextItemDraft.keyword(keyword) else { return }
        add?([draft])
        keyword = ""
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else {
            relocating = nil
            return
        }

        if let relocating {
            // Re-attaching a moved file: the old chip goes, the new one arrives. Two steps in
            // the undo journal, and honestly so — a re-bookmark is a different row.
            remove?(relocating)
            self.relocating = nil
        }
        add?(urls.map(ContextItemDraft.file(url:)))
    }

    private func beginRelocating(_ item: ContextItemValue) {
        relocating = item.id
        isImportingFiles = true
    }

    // MARK: - Quick Look

    private func preview(_ item: ContextItemValue) {
        quickLookSelection = resolvedURL(for: item)
    }

    private func resolvedFileURLs() -> [URL] {
        items.filter { $0.kind == .file }.compactMap(resolvedURL(for:))
    }

    /// The live location of an attachment.
    ///
    /// The bookmark is the durable handle and is tried first — it follows a file that has been
    /// renamed or moved. The recorded path is the fallback and is only ever *display* material
    /// promoted to a guess: a path is not a file, which is exactly why the bookmark exists.
    private func resolvedURL(for item: ContextItemValue) -> URL? {
        if let data = item.bookmark, let url = SecurityScopedBookmark.resolve(data).url {
            return url
        }
        guard !item.value.isEmpty else { return nil }
        return URL(filePath: item.value)
    }
}

/// A flow of chips that wraps instead of scrolling.
///
/// Wrapping rather than a horizontal `ScrollView` on purpose: at the largest accessibility
/// text size a scroller would keep the row exactly as tall as it was and hide the overflow,
/// which is precisely the failure the dynamic-text lane exists to catch. Wrapped, the row
/// grows downward and the growth is measurable.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(of: subviews, inWidth: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in rows(of: subviews, inWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, inWidth width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let advance = current.indices.isEmpty ? size.width : size.width + spacing
            if !current.indices.isEmpty && current.width + advance > width {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width += advance
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
