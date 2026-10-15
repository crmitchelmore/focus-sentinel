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

    // MARK: - What a drop, a paste or the file picker becomes (focus-6ji4)

    /// A file the person dropped or chose — **or the application it is**.
    ///
    /// An application bundle arrives as a file URL like any other, and stored as a file item it
    /// was a chip that looked attached and did nothing: the engine matches an application by
    /// bundle identifier and never matches a file. So a bundle that names an identifier becomes
    /// an app item. One that names none stays a file, which at least opens with the session.
    public static func attachment(url: URL) -> ContextItemDraft {
        application(at: url) ?? file(url: url)
    }

    /// The application at `url` as an app draft, or `nil` when `url` is not an application
    /// bundle with a bundle identifier.
    ///
    /// `isApplicationKey` rather than a UTType test because `FocusCore` links Foundation only;
    /// the extension is the fallback for a volume that answers no resource values.
    public static func application(at url: URL) -> ContextItemDraft? {
        guard url.isFileURL else { return nil }
        let isApplication = (try? url.resourceValues(forKeys: [.isApplicationKey]).isApplication)
            ?? (url.pathExtension.caseInsensitiveCompare("app") == .orderedSame)
        guard isApplication, let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier
        else { return nil }

        let name = ["CFBundleDisplayName", "CFBundleName"]
            .lazy
            .compactMap { bundle.object(forInfoDictionaryKey: $0) as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return app(bundleID: bundleID, displayName: name ?? url.deletingPathExtension().lastPathComponent)
    }

    /// A site, from a dropped or pasted link — **`nil` while the shipping app reads no site**.
    ///
    /// A site chip in this version is neither matched nor opened (`ShippingObservation`), so a
    /// dropped link adds nothing rather than a chip that pretends to.
    public static func site(from url: URL) -> ContextItemDraft? {
        guard ContextItemKind.domain.isObserved else { return nil }
        return domain(from: url)
    }

    /// Text the person dropped or pasted.
    ///
    /// Prose becomes a keyword. Text **shaped like a location** never does, because a keyword
    /// is stored verbatim and "never stores file paths" has to hold for a paste as much as for
    /// a dropped `.url`. A location is one of:
    ///
    /// * a path — `/Users/…`, `~/…`;
    /// * a hierarchical URL — `file:///…`, `https://…`, `x-app://…`;
    /// * an address URL — `mailto:`, `tel:`, `sms:` and their kin;
    /// * a link with no scheme but a path — `docs.example.com/d/abc`;
    /// * or prose that carries a `file:` URL inside it.
    ///
    /// A location with an origin becomes a site through `site(from:)`; anything else yields
    /// `nil`. "note: draft", "re:invent" and "a/b testing" are not locations and stay keywords.
    public static func pasted(_ text: String) -> ContextItemDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch PastedLocation(trimmed) {
        case .none:
            return keyword(trimmed)
        case .url(let url):
            return site(from: url)
        case .path:
            return nil
        }
    }
}

/// Whether pasted text names a place rather than a topic (focus-6ji4). See
/// `ContextItemDraft.pasted(_:)` for the rules; this is their implementation.
enum PastedLocation {
    /// A location with a URL worth offering to the site path.
    case url(URL)
    /// A location with nothing to keep: a path, a `file:` or address URL, prose carrying one.
    case path

    /// `nil` when the text is not a location at all, which is what lets prose through.
    init?(_ text: String) {
        let lowered = text.lowercased()
        if lowered.hasPrefix("/") || lowered == "~" || lowered.hasPrefix("~/") || lowered.contains("file:/") {
            self = .path
            return
        }

        if lowered.range(of: #"^[a-z][a-z0-9+.\-]*:/"#, options: .regularExpression) != nil {
            self = URL(string: text).map(Self.url) ?? .path
            return
        }

        // Everything below is one token. "data: the March numbers" is a sentence, not a URL.
        guard !text.contains(where: \.isWhitespace) else { return nil }

        if let colon = lowered.firstIndex(of: ":"),
           Self.addressSchemes.contains(String(lowered[..<colon])) {
            self = .path
            return
        }

        // A link with no scheme: a host, then a path, a query or a fragment. A bare host
        // ("example.com") is left to be a keyword — it is a name, not a place on a disk.
        guard let cut = text.firstIndex(where: { "/?#".contains($0) })
        else { return nil }
        let host = String(text[..<cut])
        guard host.range(of: Self.hostPattern, options: .regularExpression) != nil else { return nil }
        self = URL(string: "https://" + text).map(Self.url) ?? .path
    }

    /// Schemes whose URLs carry an address rather than a host. Lowercased.
    static let addressSchemes: Set<String> = [
        "mailto", "tel", "sms", "facetime", "facetime-audio", "callto", "imessage", "message", "data"
    ]

    /// A host name with at least one dot and an alphabetic top-level label, or `localhost`,
    /// with an optional port.
    static let hostPattern =
        #"^(localhost|([A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,})(:[0-9]+)?$"#
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

    /// **A new priority on the same desk** (focus-1rj7). Sets `intent` as the new priority, as
    /// `setPriority(intent:doneWhen:)` does, and then copies every context item and every
    /// live rule of the task named by `taskID` onto it — the apps, sites, keywords, files and
    /// verdicts a person built up for one job and now needs for the next one. The old task keeps
    /// its own copies and stays in the history. Retired rule scopes are not copied: a rule
    /// nothing reads any more is not worth carrying forward.
    func setPriority(intent: String, doneWhen: String?, keepingContextOf taskID: UUID)

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
    /// sheet's Replace (start) or Add (context) button (F-142). A start sets a new priority and
    /// attaches its context items; a context handoff adds its items to the current priority,
    /// skipping any it already holds.
    func acceptHandoff(_ request: HandoffRequest)

    /// Dismiss the pending handoff without changing anything.
    func cancelHandoff()

    /// Record that today's ritual has been answered or dismissed, so it asks once (F-19).
    func dismissRitual()

    /// **The person has been told the store did not open** (focus-tzj.4).
    ///
    /// Called from the one button on the sheet the cockpit shows when `storeOpened` is `false`,
    /// and from nowhere else. It changes nothing about the store — there is nothing to change —
    /// and it lifts `CockpitState.capturingIsRefused`, which is what stops a day's work being
    /// captured into a container that evaporates at quit without anybody having said so.
    ///
    /// A verb on the host rather than a `@State` in the view, because the refusal is the host's:
    /// a rule enforced only by the surface that draws it is a rule the next surface will not
    /// have.
    func acknowledgeStoreFailure()
}

/// Everything the session surfaces can *do*, as a sibling protocol.
///
/// Deliberately a **second** protocol rather than ten more verbs on `PriorityActing`. A
/// priority and a session are different objects with different lifetimes — a task can span many
/// sessions and a session can outlive the priority it was started on — and the two hosts that
/// implement these are two objects for the same reason. A cockpit handed one and not the other
/// renders the half it can drive and disables the half it cannot, which is what the snapshot
/// lane does.
///
/// Same three rules as `PriorityActing`, and they matter more here rather than less:
///
/// * **Nothing throws.** A store failure is a fact the person has to be told, not an exception
///   a button's action can meaningfully catch.
/// * **Nothing returns.** The result of every verb is the next `CockpitState`, so a surface
///   cannot come to depend on a value the store might not have written.
/// * **A rejected transition is silent.** `SessionMachine` returns rejections as values, and a
///   rejection means what the person asked for was already true. The one rejection worth
///   surfacing — `notPausedForThatCause` — is surfaced *before* it happens rather than after:
///   `SessionSnapshot.userMayResume` is false while a cause the person cannot clear is still
///   held, so Resume is disabled with a named explanation instead of doing nothing when
///   pressed.
///
/// `setSensingPaused` lives here rather than on a third protocol because F-119's switch is one
/// stored value driving one detachment, and pausing sensing also drives a session pause with
/// cause `.globalPause`. Two surfaces for it would be two opinions about one row.
@MainActor
public protocol SessionActing: AnyObject {
    /// Begin a session on the active priority. Starting is not an event on an existing state —
    /// it creates one, in `.focus`.
    func startSession(kind: SessionKind, plannedSeconds: Int?, deadlineAt: Date?)

    /// The person's own pause. Sends `paused(cause: .user)`, and only a `.user` resume lifts it.
    func pauseSession()

    /// The person's own resume. Sends `resumed(cause:)` for each cause the person may clear —
    /// their own, and a restoration's `.relaunch` or `.systemRestart` (focus-mmty). The machine
    /// rejects `notPausedForThatCause` for a pause that belongs to the screen lock or the
    /// global switch, which is why the surface disables the control first.
    func resumeSession()

    func startDetour(reason: DetourReason)

    func endDetour()

    /// Take a break. A break may be started **only from focus**, so a surface that offers it
    /// during a detour ends the detour first and the machine records two transitions — which is
    /// what keeps the timeline honest about what actually happened.
    func startBreak(reason: BreakReason)

    func endBreak()

    /// Stop the session and capture why (F-101). Every field is optional and Complete is
    /// enabled with all of them empty: reflection is offered, never extracted.
    func interruptSession(reason: InterruptionReason, note: String?)

    func completeSession()

    /// F-119's one global switch, bound identically to every surface that shows it.
    func setSensingPaused(_ paused: Bool)
}
