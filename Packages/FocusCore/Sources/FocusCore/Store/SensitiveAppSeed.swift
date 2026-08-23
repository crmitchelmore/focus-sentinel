import Foundation
import SwiftData

/// Which of the two lists a `SensitiveAppEntry` row belongs to — and whether it is still on it.
///
/// ## Why there are four raw values rather than two
///
/// The requirement is that **a user's removal of a built-in entry survives a reseed**. A seed
/// that inserted every built-in identifier not currently present would resurrect, on the next
/// launch, exactly the entry the person had just taken off the list — and an app that put a
/// setting back after you changed it is an app that is arguing with you.
///
/// So a removed built-in keeps its row as a **tombstone**: the row stays, its kind moves to the
/// `.removedByUser` variant, and it is not a member of any list. The seed refuses to insert a
/// built-in for which any row already exists, tombstone included, so the removal is permanent
/// without needing a column the schema does not have. A **user-added** entry has no tombstone —
/// removing it deletes the row outright, because there is nothing that would put it back.
public enum SensitiveEntryKind: String, Sendable, CaseIterable, Codable, Hashable {
    /// On the auto-pause list (F-118). The frontmost application is checked against this
    /// **before** any deeper read.
    case sensitive
    /// On the presentation-exclusion list (F-35), which seeds **empty** — seeding it with
    /// guesses would be a claim about applications this programme has not measured.
    case presentationExcluded
    /// A built-in auto-pause entry the person removed. A tombstone, not a list member.
    case sensitiveRemovedByUser = "sensitive.removedByUser"
    /// A built-in presentation exclusion the person removed. Declared for symmetry; nothing
    /// seeds that list in v1, so nothing can be tombstoned on it yet.
    case presentationExcludedRemovedByUser = "presentationExcluded.removedByUser"

    /// Whether a row of this kind is actually on its list.
    public var isActive: Bool {
        switch self {
        case .sensitive, .presentationExcluded: true
        case .sensitiveRemovedByUser, .presentationExcludedRemovedByUser: false
        }
    }

    /// The list this row belongs to, tombstone or not — which is what makes "does any row exist
    /// for this identifier on this list" a question the seed can ask.
    public var list: SensitiveEntryKind {
        switch self {
        case .sensitive, .sensitiveRemovedByUser: .sensitive
        case .presentationExcluded, .presentationExcludedRemovedByUser: .presentationExcluded
        }
    }

    /// What this kind becomes when the person removes it.
    public var tombstone: SensitiveEntryKind {
        switch self {
        case .sensitive, .sensitiveRemovedByUser: .sensitiveRemovedByUser
        case .presentationExcluded, .presentationExcludedRemovedByUser: .presentationExcludedRemovedByUser
        }
    }

    /// The one sanctioned decoder, in the same exhaustive-`switch` spirit as
    /// `SessionPhase.decode(_:)`. A kind this build does not recognise decodes to `nil` and the
    /// row is treated as belonging to no list — inert, never guessed at, and never deleted, so
    /// it survives the round trip to whichever build wrote it.
    public static func decode(_ raw: String?) -> SensitiveEntryKind? {
        switch raw {
        case "sensitive": .sensitive
        case "presentationExcluded": .presentationExcluded
        case "sensitive.removedByUser": .sensitiveRemovedByUser
        case "presentationExcluded.removedByUser": .presentationExcludedRemovedByUser
        default: nil
        }
    }
}

extension FocusSchemaV3.SensitiveAppEntry {
    /// The stored kind, decoded. `nil` for a row this build cannot interpret.
    public var kind: SensitiveEntryKind? {
        get { SensitiveEntryKind.decode(kindRaw) }
        set { if let newValue { kindRaw = newValue.rawValue } }
    }
}

/// The conservative built-in list, and the rules that keep it from arguing with the person.
///
/// ## It is data, not code
///
/// The list below is bundle identifiers and nothing else. **Nothing is ever inferred from what
/// is on the screen**: "is this banking?" is answered by an identifier being on a list, never by
/// looking at a window, a title, a URL or a pixel — and in this epic there is no capability that
/// would allow it even if somebody wanted to.
///
/// ## Messages is deliberately absent
///
/// It is a private-messaging application and it is also a work tool for a great many people, so
/// it is **offered as a suggestion** in Privacy settings rather than switched on for everyone.
/// Deciding that for somebody would be the app having an opinion about who they talk to.
@MainActor
public enum SensitiveAppSeed {
    /// Seed the built-in auto-pause list, once, and never argue with the person about it.
    ///
    /// Idempotent by construction: a built-in is inserted only when **no row at all** exists for
    /// that identifier on that list — so a second launch inserts nothing, and a launch after a
    /// removal inserts nothing either, because the tombstone is a row.
    ///
    /// The presentation-exclusion list is not seeded. It starts empty and stays empty until the
    /// person puts something on it.
    ///
    /// - Returns: how many rows this call actually inserted. Zero on every launch after the
    ///   first, which is what "idempotent" means as a number a test can read.
    @discardableResult
    public static func seed(
        in context: ModelContext,
        now: Date,
        bundleIDs: Set<String> = SensitivityGate.builtInSensitiveBundleIDs
    ) throws -> Int {
        let existing = try rows(in: context)
        let known = Set(
            existing
                .filter { $0.kind?.list == .sensitive }
                .map(\.bundleID)
        )

        var inserted = 0
        // Sorted so that a fresh store's rows are inserted in one deterministic order and two
        // seeded stores compare equal — a set's iteration order is not a promise.
        for bundleID in bundleIDs.sorted() where !known.contains(bundleID) {
            context.insert(
                FocusSchemaV3.SensitiveAppEntry(
                    bundleID: bundleID,
                    kindRaw: SensitiveEntryKind.sensitive.rawValue,
                    isBuiltIn: true,
                    addedAt: now
                )
            )
            inserted += 1
        }

        if inserted > 0 { try context.save() }
        return inserted
    }

    /// Every row, however this build reads it.
    public static func rows(in context: ModelContext) throws -> [FocusSchemaV3.SensitiveAppEntry] {
        try context.fetch(FetchDescriptor<FocusSchemaV3.SensitiveAppEntry>())
            .sorted { $0.bundleID < $1.bundleID }
    }

    /// The identifiers actually on one list right now — tombstones excluded.
    public static func activeBundleIDs(
        _ list: SensitiveEntryKind = .sensitive,
        in context: ModelContext
    ) throws -> Set<String> {
        Set(
            try rows(in: context)
                .filter { $0.kind?.isActive == true && $0.kind?.list == list.list }
                .map(\.bundleID)
        )
    }

    /// The gate, built from what is stored rather than from the compiled constant.
    ///
    /// The two halves are kept apart — a built-in row and a user's own row are different facts
    /// about the same decision, and the Privacy surface shows which is which so that "remove"
    /// means something different for each.
    public static func gate(in context: ModelContext) throws -> SensitivityGate {
        let all = try rows(in: context).filter {
            $0.kind?.isActive == true && $0.kind?.list == .sensitive
        }
        return SensitivityGate(
            builtIn: Set(all.filter(\.isBuiltIn).map(\.bundleID)),
            userAdded: Set(all.filter { !$0.isBuiltIn }.map(\.bundleID))
        )
    }

    /// Put an identifier on a list. The person's own entry, marked as theirs.
    ///
    /// Adding back something they had removed revives the tombstone rather than inserting a
    /// second row, so the list can never hold one identifier twice.
    @discardableResult
    public static func add(
        bundleID: String,
        to list: SensitiveEntryKind = .sensitive,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV3.SensitiveAppEntry {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = try rows(in: context).first(where: {
            $0.bundleID == trimmed && $0.kind?.list == list.list
        }) {
            existing.kind = list.list
            try context.save()
            return existing
        }

        let row = FocusSchemaV3.SensitiveAppEntry(
            bundleID: trimmed,
            kindRaw: list.list.rawValue,
            isBuiltIn: false,
            addedAt: now
        )
        context.insert(row)
        try context.save()
        return row
    }

    /// Take an identifier off a list.
    ///
    /// A **built-in** row is tombstoned, so the seed can never put it back. A **user's own** row
    /// is deleted outright, because nothing would put that one back and keeping a tombstone for
    /// it would be keeping a record of a choice they reversed.
    public static func remove(
        bundleID: String,
        from list: SensitiveEntryKind = .sensitive,
        in context: ModelContext
    ) throws {
        let matches = try rows(in: context).filter {
            $0.bundleID == bundleID && $0.kind?.list == list.list
        }
        guard !matches.isEmpty else { return }

        for row in matches {
            if row.isBuiltIn {
                row.kind = list.list.tombstone
            } else {
                context.delete(row)
            }
        }
        try context.save()
    }
}
