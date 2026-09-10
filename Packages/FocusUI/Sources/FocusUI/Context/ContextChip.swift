import AppKit
import FocusCore
import SwiftUI

/// One item of the task's context pack, drawn.
///
/// Four kinds and no fifth (F-09): an application, a normalised web origin, a keyword and a
/// file. A fifth thing a *later* build wrote renders as an inert chip carrying its own string,
/// because a row this version does not understand is not a row it may drop.
///
/// Three rules the chip keeps:
///
/// * **Colour is never the only channel.** Each kind has its own SF Symbol, and under
///   "Differentiate without colour" the kind's name is drawn as well — the same arrangement
///   `StatusBadge` uses.
/// * **A missing file is a state, never a deletion.** A bookmark that no longer resolves
///   makes the chip say so and offer *Locate…*. It is never removed automatically: throwing
///   away the user's context because a disk was unplugged is a bug, not tidiness.
/// * **A file chip opens Quick Look.** It is a button, so Space on the focused chip previews
///   it — the Mac idiom (F-95). The preview itself is driven by the row, which owns the
///   selection.
public struct ContextChip: View {
    public let item: ContextItemValue
    /// Preview this file. `nil` for every kind that is not a file.
    public let preview: (() -> Void)?
    /// Re-attach a file whose bookmark no longer resolves.
    public let locate: (() -> Void)?
    /// Remove the item. `nil` in a read-only render.
    public let remove: (() -> Void)?

    @Environment(\.appearanceTraits) private var traits
    @Environment(\.shellTextScale) private var textScale
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 16

    public init(
        item: ContextItemValue,
        preview: (() -> Void)? = nil,
        locate: (() -> Void)? = nil,
        remove: (() -> Void)? = nil
    ) {
        self.item = item
        self.preview = preview
        self.locate = locate
        self.remove = remove
    }

    public var body: some View {
        HStack(spacing: spacing / 2) {
            if let preview {
                Button(action: preview) { chipBody }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: accessibilityDescription))
            } else {
                chipBody
            }

            if let locate, item.availability == .missing {
                Button(action: locate) {
                    ShellText(.contextActionLocate, role: .caption)
                }
            }

            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(ShellStrings.resource(.contextActionRemove)))
            }
        }
        .padding(.horizontal, spacing)
        .padding(.vertical, spacing / 2)
        .shellSurface(DesignTokens.material(for: traits, provenance: .summoned), in: Capsule(), traits: traits)
        .overlay {
            Capsule()
                .strokeBorder(
                    borderColor.opacity(DesignTokens.emphasis(for: traits).outlineOpacity),
                    lineWidth: DesignTokens.emphasis(for: traits).borderWidth
                )
        }
    }

    // MARK: - The chip itself

    private var chipBody: some View {
        HStack(spacing: spacing / 2) {
            glyph
                .frame(
                    width: DesignTokens.spacing(glyphSize, scale: textScale),
                    height: DesignTokens.spacing(glyphSize, scale: textScale)
                )
                .accessibilityHidden(true)

            // The subject is the user's own material — an app's name, a host, a keyword, a
            // file name — and never goes through a catalog.
            Text(verbatim: displayName)
                .font(DesignTokens.font(.callout, scale: textScale))
                .lineLimit(1)

            if traits.differentiateWithoutColor {
                ShellText(kindKey, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }

            if let statusKey {
                ShellText(statusKey, role: .caption)
                    .foregroundStyle(DesignTokens.supportingTextColor(for: traits))
            }
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if item.kind == .app, let icon = InstalledApplication.info(bundleID: item.value)?.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: item.kind.symbolName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(DesignTokens.Palette.primaryText)
        }
    }

    /// What the chip shows.
    ///
    /// An application chip prefers the *installed* application's own display name, because
    /// that is the name the user knows it by; a bundle identifier they have never seen is a
    /// worse label than the one in their Dock.
    private var displayName: String {
        if item.kind == .app, let name = InstalledApplication.name(bundleID: item.value) {
            return name
        }
        // The stored half, which for a file is its file name and for an origin is its host —
        // neither of which a bundle lookup could have improved. Asking `info` for the name and
        // taking `?? item.displayName` would have thrown the stored name away for an application
        // whose bundle answers with whitespace; this keeps it.
        return item.displayName
    }

    /// The extra word a chip says about itself when something is wrong with it.
    private var statusKey: ShellStringKey? {
        if item.availability == .missing { return .contextFileMissing }
        if item.kind == .app, InstalledApplication.info(bundleID: item.value) == nil {
            return .contextAppNotInstalled
        }
        return nil
    }

    private var kindKey: ShellStringKey {
        switch item.kind {
        case .app: .contextKindApp
        case .domain: .contextKindDomain
        case .keyword: .contextKindKeyword
        case .file: .contextKindFile
        case .unknown: .contextKindUnknown
        }
    }

    private var borderColor: Color {
        item.availability == .available
            ? DesignTokens.Palette.separator(for: traits)
            : Color(nsColor: .systemOrange)
    }

    /// What VoiceOver reads for a previewable chip: the kind, then the subject.
    private var accessibilityDescription: String {
        "\(ShellStrings.string(kindKey)): \(displayName)"
    }
}
