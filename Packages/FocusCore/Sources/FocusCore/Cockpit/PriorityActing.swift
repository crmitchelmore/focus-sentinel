import Foundation

/// A context item the user has just produced, before it has been stored.
///
/// The draft carries no identifier and no timestamp on purpose. Identity and `addedAt` are
/// stamped by whoever owns the store and the injected clock — which is what keeps every
/// timestamp in the programme reproducible and keeps a bare `Date()` out of `FocusUI`
/// entirely (R-26).
public struct ContextItemDraft: Sendable, Equatable, Hashable {
    public var kind: ContextItemKind
    /// The normalised subject: a bundle identifier, a `scheme://host[:port]` origin, a
    /// lowercased keyword, or the file's path at the moment it was added.
    public var value: String
    /// What the chip shows.
    public var displayName: String
    /// A security-scoped bookmark, for file drafts only.
    public var bookmark: Data?

    public init(kind: ContextItemKind, value: String, displayName: String, bookmark: Data? = nil) {
        self.kind = kind
        self.value = value
        self.displayName = displayName
        self.bookmark = bookmark
    }

    // MARK: - The four kinds, built correctly

    /// An application. The bundle identifier is the subject; the name is for the eye.
    public static func app(bundleID: String, displayName: String) -> ContextItemDraft? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ContextItemDraft(
            kind: .app,
            value: trimmed,
            displayName: name.isEmpty ? trimmed : name
        )
    }

    /// A web origin. **Returns `nil` when the URL has no origin**, which is what keeps a
    /// path, a query or a credential from ever reaching the store: there is no route from a
    /// full URL to a stored value that does not pass through the normaliser (SC-3).
    public static func domain(from url: URL) -> ContextItemDraft? {
        guard let origin = OriginNormalizer.normalize(url) else { return nil }
        return domain(origin: origin)
    }

    public static func domain(origin: String) -> ContextItemDraft? {
        guard let normalised = OriginNormalizer.normalize(origin) else { return nil }
        return ContextItemDraft(
            kind: .domain,
            value: normalised,
            displayName: ContextItemValue.displayName(forOrigin: normalised)
        )
    }

    /// A keyword. Trimmed and lowercased: "Proposal" and "proposal" are the same keyword and
    /// two chips saying so is clutter.
    public static func keyword(_ text: String) -> ContextItemDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return ContextItemDraft(kind: .keyword, value: trimmed, displayName: trimmed)
    }

    /// A file, held as a security-scoped bookmark (R-22).
    ///
    /// The bookmark is made here, at the moment the user chose the file, because that is the
    /// only moment the app is certain it can reach it. A bookmark that cannot be made leaves
    /// `bookmark == nil`, and the chip then renders as *missing* with a Locate… action rather
    /// than pretending the path alone is a durable handle — a path is not a file.
    public static func file(url: URL) -> ContextItemDraft {
        ContextItemDraft(
            kind: .file,
            value: url.path(percentEncoded: false),
            displayName: url.lastPathComponent,
            bookmark: try? SecurityScopedBookmark.create(for: url)
        )
    }
}

/// Everything the cockpit can *do*, as a protocol.
///
/// The cockpit renders a `CockpitState` and calls one of these verbs; it never opens a store,
/// never sees a `@Model` class and never learns which implementation it was handed.
/// `App/PriorityHost.swift` is the only type that implements it — it owns the `ModelContext`,
/// calls `PriorityStore` (and therefore registers every mutation on the undo journal), and
/// projects the result back into a new `CockpitState`. `FocusUITests` supply a recording
/// double, which is what makes every surface in the package testable with no container.
///
/// **Nothing here throws.** A store failure is a fact the user has to be told about, not an
/// exception a view can meaningfully catch: the host records it and the next `CockpitState`
/// reports it. A view that could `try?` a mutation would be a view that could swallow one.
@MainActor
public protocol PriorityActing: AnyObject {
    /// Capture a sentence and make it the one thing. The primary user action.
    func setPriority(intent: String, doneWhen: String?)

    /// Edit the intent in place. Bumps the task's revision.
    func editIntent(taskID: UUID, to intent: String)

    /// Set or clear the definition of done (F-08).
    func editDoneWhen(taskID: UUID, to doneWhen: String?)

    /// Set or clear the timebox, in seconds (F-12).
    func setTimebox(taskID: UUID, seconds: Int?)

    /// "Work on this again" (F-15): re-point the pointer at an existing task, restoring its
    /// stored context pack by construction rather than by copying.
    func activate(taskID: UUID)

    /// Finish it (F-22). Both reflection fields are optional and completion never waits for
    /// them.
    func complete(taskID: UUID, shipped: String?, restartPoint: String?)

    /// Put the priority down without completing or deleting anything.
    func clear()

    /// Add one item to the context pack (F-09).
    func addContext(taskID: UUID, item: ContextItemDraft)

    /// Remove one item. Never called automatically — a missing file stays on the board.
    func removeContext(id: UUID)

    /// Author a rule scoped to this priority (F-11).
    func addRule(
        taskID: UUID,
        scope: PriorityRuleScope,
        subject: String,
        verdict: PriorityRuleVerdict
    )

    /// Change your mind about a rule, keeping its identity and its place in the list.
    func changeRule(id: UUID, verdict: PriorityRuleVerdict)

    func removeRule(id: UUID)

    /// Accept an incoming `focus://` handoff — **only** ever called from the confirmation
    /// sheet's Replace button (F-142).
    func acceptHandoff(_ request: HandoffRequest)

    /// Dismiss the pending handoff without changing anything.
    func cancelHandoff()

    /// Record that today's ritual has been answered or dismissed, so it asks once (F-19).
    func dismissRitual()
}
