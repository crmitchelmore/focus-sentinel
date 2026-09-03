import Foundation
import SwiftData

/// **What the shell remembers about itself between launches**, as one value.
///
/// A value rather than a live row, for the reason `InterventionPreferences` is one: whatever
/// reads these — the composition root at launch, the cockpit's footer, a second launch — should
/// be handed a snapshot it can compare and test, not a `@Model` object whose fields change
/// underneath it.
///
/// It is deliberately **not** a preference. Nobody sets any of it. Keeping it apart from
/// `AppSettingsRecord` and `NudgePreferencesRecord` is what stops a "reset my settings" verb in a
/// later epic from also forgetting that somebody has already read the explanation.
public struct ShellState: Sendable, Equatable, Hashable {
    /// When the first-run explanation was shown, or `nil` while it is still owed (focus-odz.7).
    public var firstRunExplanationShownAt: Date?
    /// When the launch-at-login offer was last put in front of somebody (D-12, focus-odz.4).
    public var launchAtLoginOfferedAt: Date?
    /// The scene ids open at the last recorded quit, or `nil` when no quit has been recorded
    /// (focus-odz.6). An empty array is *"everything was closed"*, which is a different fact.
    public var openWindowsAtLastQuit: [String]?

    public init(
        firstRunExplanationShownAt: Date? = nil,
        launchAtLoginOfferedAt: Date? = nil,
        openWindowsAtLastQuit: [String]? = nil
    ) {
        self.firstRunExplanationShownAt = firstRunExplanationShownAt
        self.launchAtLoginOfferedAt = launchAtLoginOfferedAt
        self.openWindowsAtLastQuit = openWindowsAtLastQuit
    }

    /// **What a store the app has never opened before answers**: nothing shown, nothing offered,
    /// nothing recorded. It is the state that owes a first-run explanation, and the v5 → v6
    /// migration exists so that no *upgraded* store is ever in it.
    public static let neverUsed = ShellState()

    /// Whether the first-run explanation is still owed.
    public var owesFirstRunExplanation: Bool { firstRunExplanationShownAt == nil }

    /// Whether the launch-at-login offer has already been made (D-12: it is made once).
    public var hasOfferedLaunchAtLogin: Bool { launchAtLoginOfferedAt != nil }
}

extension FocusStore {
    /// The shell's remembered state, or `neverUsed` when the store has no row.
    @MainActor
    public static func shellState(in context: ModelContext) -> ShellState {
        guard let row = shellStateRow(in: context) else { return .neverUsed }
        return ShellState(
            firstRunExplanationShownAt: row.firstRunExplanationShownAt,
            launchAtLoginOfferedAt: row.launchAtLoginOfferedAt,
            openWindowsAtLastQuit: row.openWindowsAtLastQuit
        )
    }

    /// Write all three, creating the row if this store has never had one.
    ///
    /// `now` is passed in rather than read from a clock here, so every timestamp in this
    /// programme comes from an injected one and a test can pin it.
    @MainActor
    @discardableResult
    public static func setShellState(
        _ state: ShellState,
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV6.ShellStateRecord {
        let row: FocusSchemaV6.ShellStateRecord
        if let existing = shellStateRow(in: context) {
            row = existing
        } else {
            row = FocusSchemaV6.ShellStateRecord(touchedAt: now)
            context.insert(row)
        }

        row.firstRunExplanationShownAt = state.firstRunExplanationShownAt
        row.launchAtLoginOfferedAt = state.launchAtLoginOfferedAt
        row.openWindowsAtLastQuit = state.openWindowsAtLastQuit
        row.touchedAt = now

        try context.save()
        return row
    }

    /// Record that the first-run explanation has been shown, leaving the other two alone.
    ///
    /// A named verb rather than a read-modify-write at each call site, for the reason
    /// `setNudgeVoice(_:in:now:)` is one: a partial write from a surface that had read one field
    /// would silently reset the two it never drew.
    @MainActor
    @discardableResult
    public static func recordFirstRunExplanationShown(
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV6.ShellStateRecord {
        var state = shellState(in: context)
        // **Never re-stamped.** The question this column answers is *"has it been shown?"*, and a
        // second write would move the date to the day of the second showing — which is the one
        // day it must be impossible for it to be.
        guard state.firstRunExplanationShownAt == nil else {
            return try setShellState(state, in: context, now: now)
        }
        state.firstRunExplanationShownAt = now
        return try setShellState(state, in: context, now: now)
    }

    /// Record that the launch-at-login offer has been made, leaving the other two alone.
    @MainActor
    @discardableResult
    public static func recordLaunchAtLoginOffered(
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV6.ShellStateRecord {
        var state = shellState(in: context)
        guard state.launchAtLoginOfferedAt == nil else {
            return try setShellState(state, in: context, now: now)
        }
        state.launchAtLoginOfferedAt = now
        return try setShellState(state, in: context, now: now)
    }

    /// Record which windows were open, leaving the other two alone.
    @MainActor
    @discardableResult
    public static func recordOpenWindows(
        _ ids: [String],
        in context: ModelContext,
        now: Date
    ) throws -> FocusSchemaV6.ShellStateRecord {
        var state = shellState(in: context)
        state.openWindowsAtLastQuit = ids
        return try setShellState(state, in: context, now: now)
    }

    /// The shell-state row, if the store has one.
    @MainActor
    public static func shellStateRow(
        in context: ModelContext
    ) -> FocusSchemaV6.ShellStateRecord? {
        var descriptor = FetchDescriptor<FocusSchemaV6.ShellStateRecord>(
            sortBy: [SortDescriptor(\.touchedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try? context.countedFetch(descriptor).first
    }
}
