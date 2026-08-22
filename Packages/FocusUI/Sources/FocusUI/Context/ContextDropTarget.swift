import FocusCore
import SwiftUI
import UniformTypeIdentifiers

/// Something a person dropped or pasted onto a context surface.
///
/// One `Transferable` type with two proxy representations, rather than two competing drop
/// destinations on the same view: a view may only have one, and "whichever modifier came last
/// wins" is not a decode rule anybody can reason about.
///
/// The representations are the two things measured arriving (P-64): a file URL advertises
/// `public.file-url` *and* `public.url`, a web URL advertises `public.url` alone, and
/// `canLoadObject(ofClass: URL.self)` is true for both — so **one** `URL` representation
/// accepts both kinds and `url.isFileURL` is the split, not a UTType test. Text is a separate
/// representation because it is a separate thing, not a substitute for a URL.
public enum DroppedContext: Transferable, Sendable, Equatable, Hashable {
    case url(URL)
    case text(String)

    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation<DroppedContext, URL>(importing: { DroppedContext.url($0) })
        ProxyRepresentation<DroppedContext, String>(importing: { DroppedContext.text($0) })
    }
}

/// How a dropped or pasted thing becomes a context item.
///
/// A pure function, deliberately: the decode is the part that can be wrong in a way a user
/// would notice — a full URL stored where an origin belongs would break standing condition 3 —
/// and a pure function is the part a test can hold still.
public enum ContextDecoder {
    /// The rules, in order:
    ///
    /// * a **file** URL becomes a file item, bookmarked at the moment it was dropped;
    /// * any other URL becomes a **domain** item, normalised to `scheme://host[:port]` —
    ///   there is no route from a dropped link to a stored path, query or credential;
    /// * **text** that parses as a URL with a scheme and a host takes the domain path too,
    ///   because a pasted link is a link whatever pasteboard flavour carried it;
    /// * anything else becomes a **keyword**, trimmed and lowercased;
    /// * and anything that survives none of that — an empty string, a URL with no host —
    ///   yields `nil` rather than an empty chip.
    public static func decode(_ dropped: DroppedContext) -> ContextItemDraft? {
        switch dropped {
        case .url(let url):
            return url.isFileURL ? ContextItemDraft.file(url: url) : ContextItemDraft.domain(from: url)
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let url = URL(string: trimmed),
               url.scheme != nil,
               let draft = ContextItemDraft.domain(from: url) {
                return draft
            }
            return ContextItemDraft.keyword(trimmed)
        }
    }

    /// Decode a whole drop, discarding what could not be understood.
    ///
    /// Dropping five things of which one is unreadable adds four chips and says nothing about
    /// the fifth; that is better than refusing the drop entirely, and far better than adding
    /// an empty chip to stand for it.
    public static func decode(_ dropped: [DroppedContext]) -> [ContextItemDraft] {
        dropped.compactMap(decode)
    }
}

extension View {
    /// Accept dropped and pasted files, links and text on this view (F-96, F-21).
    ///
    /// Both use the current, non-deprecated shapes measured on this SDK (P-63):
    /// `dropDestination(for:isEnabled:action:)` taking `(items, session)` — the
    /// `(items, location) -> Bool` form is deprecated — and
    /// `pasteDestination(for:action:validator:)`. Paste is wired to the same decoder as the
    /// drop, so ⌘V and a drag put exactly the same thing in the pack.
    public func contextDropTarget(
        isEnabled: Bool = true,
        receive: @escaping ([ContextItemDraft]) -> Void
    ) -> some View {
        dropDestination(for: DroppedContext.self, isEnabled: isEnabled) { items, _ in
            let drafts = ContextDecoder.decode(items)
            guard !drafts.isEmpty else { return }
            receive(drafts)
        }
        .pasteDestination(for: DroppedContext.self) { items in
            guard isEnabled else { return }
            let drafts = ContextDecoder.decode(items)
            guard !drafts.isEmpty else { return }
            receive(drafts)
        }
    }
}
