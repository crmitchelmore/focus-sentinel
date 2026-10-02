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
    /// * a **file** URL becomes a file item, bookmarked at the moment it was dropped — unless
    ///   it is an **application**, which becomes an app item keyed by its bundle identifier,
    ///   because that is the only thing the engine can match an application by (focus-6ji4);
    /// * any other URL is a **site**, normalised to `scheme://host[:port]` — and while the
    ///   shipping app reads no site it yields `nil`, not a chip that does nothing;
    /// * **text** shaped like a location — a link, a path, a `file:` or `mailto:` URL — takes
    ///   the site path too, or yields `nil`; it is never stored verbatim as a keyword, so a
    ///   paste cannot put a file path in the store that a dropped `.url` could not;
    /// * any other text becomes a **keyword**, trimmed and lowercased;
    /// * and anything that survives none of that yields `nil` rather than an empty chip.
    ///
    /// The rules themselves live on `ContextItemDraft` in `FocusCore`, where the file picker
    /// shares them and a test can hold them still without this package.
    public static func decode(_ dropped: DroppedContext) -> ContextItemDraft? {
        switch dropped {
        case .url(let url):
            return url.isFileURL ? ContextItemDraft.attachment(url: url) : ContextItemDraft.site(from: url)
        case .text(let text):
            return ContextItemDraft.pasted(text)
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
    /// The modifiers are attached only when there is somewhere for a drop to *go*, rather
    /// than attached-and-disabled. Two reasons, and both are about honesty: a view advertising
    /// a drop destination it will refuse is a lie told with the cursor, and a drop destination
    /// makes its whole subtree unrenderable under `ImageRenderer` — measured on this machine —
    /// so a read-only render would be a yellow placeholder where the chips should be.
    @ViewBuilder
    public func contextDropTarget(
        isEnabled: Bool = true,
        receive: @escaping ([ContextItemDraft]) -> Void
    ) -> some View {
        if isEnabled {
            dropDestination(for: DroppedContext.self) { items, _ in
                let drafts = ContextDecoder.decode(items)
                guard !drafts.isEmpty else { return }
                receive(drafts)
            }
            .pasteDestination(for: DroppedContext.self) { items in
                let drafts = ContextDecoder.decode(items)
                guard !drafts.isEmpty else { return }
                receive(drafts)
            }
        } else {
            self
        }
    }
}
