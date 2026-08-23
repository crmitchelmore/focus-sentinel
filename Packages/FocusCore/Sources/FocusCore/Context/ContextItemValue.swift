import Foundation

/// Whether a context item can actually be reached right now.
///
/// Not a stored column: availability is a fact about the world at the moment the surface asks,
/// and storing it would mean a chip that stays wrong until something rewrites the row.
public enum ContextItemAvailability: Sendable, Equatable, Hashable {
    /// Nothing is wrong with it.
    case available
    /// A file whose bookmark no longer resolves. Renders as *missing*, with a Locate… action,
    /// and is never removed automatically.
    case missing
    /// A stored kind this build does not understand. Renders as an inert chip.
    case unknownKind
}

/// One item of a task's context pack, as a value.
///
/// The persistent representation is `FocusSchemaV3.ContextItem`; this is what the cockpit
/// renders and what `PriorityActing` passes around, so that `FocusUI` never has to touch a
/// `@Model` class or a `ModelContext` (R-24).
public struct ContextItemValue: Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public var kind: ContextItemKind
    /// The normalised subject: a bundle identifier, a `scheme://host[:port]` origin, a
    /// lowercased keyword, or a file path recorded when the item was added.
    public var value: String
    /// What the chip shows.
    public var displayName: String
    /// A security-scoped bookmark, for `file` items only.
    public var bookmark: Data?
    public var addedAt: Date
    public var availability: ContextItemAvailability

    public init(
        id: UUID = UUID(),
        kind: ContextItemKind,
        value: String,
        displayName: String,
        bookmark: Data? = nil,
        addedAt: Date,
        availability: ContextItemAvailability = .available
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.displayName = displayName
        self.bookmark = bookmark
        self.addedAt = addedAt
        self.availability = availability
    }

    /// Project a stored row, deciding availability from what the row actually contains.
    ///
    /// A `file` row's availability is *not* decided here: resolving a bookmark touches the
    /// disk, and a projection that did I/O per chip would make drawing the cockpit a
    /// file-system operation. The caller resolves and passes the answer in.
    public init(
        _ item: FocusSchemaV3.ContextItem,
        availability: ContextItemAvailability? = nil
    ) {
        let kind = item.kind
        self.init(
            id: item.id,
            kind: kind,
            value: item.value,
            displayName: item.displayName,
            bookmark: item.bookmark,
            addedAt: item.addedAt,
            availability: availability ?? (kind.isKnown ? .available : .unknownKind)
        )
    }

    // MARK: - The four kinds, built correctly

    /// An application chip. The bundle identifier is the subject; the name is for the eye.
    public static func app(
        bundleID: String,
        displayName: String,
        addedAt: Date,
        id: UUID = UUID()
    ) -> ContextItemValue {
        ContextItemValue(
            id: id,
            kind: .app,
            value: bundleID,
            displayName: displayName,
            addedAt: addedAt
        )
    }

    /// A domain chip, from a URL. **Returns `nil` when the URL has no origin**, which is what
    /// keeps a path, a query or a credential from ever reaching the store: there is no
    /// initialiser that takes a full URL and keeps it.
    public static func domain(
        from url: URL,
        addedAt: Date,
        id: UUID = UUID()
    ) -> ContextItemValue? {
        guard let origin = OriginNormalizer.normalize(url) else { return nil }
        return domain(origin: origin, addedAt: addedAt, id: id)
    }

    /// A domain chip from an already-normalised origin. Re-normalised anyway, because "already
    /// normalised" is a claim and this is the type that gets to check it.
    public static func domain(
        origin: String,
        addedAt: Date,
        id: UUID = UUID()
    ) -> ContextItemValue? {
        guard let normalised = OriginNormalizer.normalize(origin) else { return nil }
        return ContextItemValue(
            id: id,
            kind: .domain,
            value: normalised,
            displayName: displayName(forOrigin: normalised),
            addedAt: addedAt
        )
    }

    /// A keyword chip. Trimmed and lowercased, because "Proposal" and "proposal" are the same
    /// keyword and two chips saying so is clutter.
    public static func keyword(
        _ text: String,
        addedAt: Date,
        id: UUID = UUID()
    ) -> ContextItemValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return ContextItemValue(
            id: id,
            kind: .keyword,
            value: trimmed,
            displayName: trimmed,
            addedAt: addedAt
        )
    }

    /// A file chip. `value` is the path *at the time of adding* and is for display only; the
    /// durable handle is the bookmark.
    public static func file(
        url: URL,
        bookmark: Data?,
        addedAt: Date,
        id: UUID = UUID()
    ) -> ContextItemValue {
        ContextItemValue(
            id: id,
            kind: .file,
            value: url.path(percentEncoded: false),
            displayName: url.lastPathComponent,
            bookmark: bookmark,
            addedAt: addedAt
        )
    }

    /// What a domain chip shows: the host, without the scheme, because the scheme is not what
    /// a person recognises a site by.
    static func displayName(forOrigin origin: String) -> String {
        guard let components = URLComponents(string: origin), let host = components.host else {
            return origin
        }
        if let port = components.port { return "\(host):\(port)" }
        return host
    }
}
