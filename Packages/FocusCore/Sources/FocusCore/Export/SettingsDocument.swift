import Foundation
import SwiftData

/// **The settings a person carries to another Mac** (F-134, focus-ix9).
///
/// A second document type, deliberately not a scope of the data export. The two answer different
/// questions: `StoreExport` is *"give me what you have on me"* and is a file you keep;
/// this is *"set my other Mac up like this one"* and is a file you carry. Mixing them would mean
/// an import verb that could silently replace somebody's history, and a takeaway file that has to
/// be understood before it can be read.
///
/// ## What it carries, and what it refuses to
///
/// Preferences and rules of thumb: the appearance, the nudge voice and its two companions, the
/// retention window, the retired daily ritual's switch, the quick-capture combination, the four
/// sensing dials, and the applications the person added to the exclusion lists themselves.
///
/// It carries **none** of:
///
/// * **History.** Priorities, sessions, observations, interventions and receipts are the data
///   export's, and an import that wrote them would be an import that could destroy a day's work.
/// * **Permission state.** `CapabilityRecord` is what *this* Mac can do, read from this Mac. A
///   capability copied from another machine is a claim about hardware that is not here.
/// * **Machine identifiers.** No boot identity, no uptime anchor, no display id, no store path.
/// * **Built-in exclusion rows.** The app seeds those itself and re-seeds them on any Mac; what
///   travels is what the person chose — their own additions, and their removals of built-ins as
///   the tombstones that record them.
/// * **`sensingPaused`.** A stored preference, and deliberately left behind: it is a state a
///   person put the app into a moment ago, not a way they want their Macs set up, and restoring
///   an import as *not watching* is the one outcome nobody would ask for.
///
/// ## An import is untrusted input
///
/// It is a file that may have been written by a newer build, an older build, a text editor, or
/// nothing at all. So it is validated whole and applied whole: a document whose `format` is not
/// this one, whose `version` this build does not know, whose voice is a deck this build cannot
/// read, or whose subject cannot be normalised is **refused with a stated reason and applies
/// nothing**. There is no partial import, because a partly-applied settings file is a
/// configuration nobody has ever chosen.
public struct SettingsDocument: Codable, Sendable, Equatable {
    public static let formatName = "focus-sentinel.settings"
    /// The document format's own version. Bumped when a field is added, removed or re-meant.
    public static let formatVersion = 1
    /// Every version this build can read. A document outside it is refused by number, and the
    /// refusal names the number — never "malformed", which would send somebody looking for a
    /// corruption that is not there.
    public static let readableVersions: Set<Int> = [1]

    public let format: String
    public let version: Int
    public let generatedAt: Date

    public let appearanceRaw: String
    public let voiceRaw: String
    public let reducedInterruption: Bool
    public let quietHoursStartMinuteOfDay: Int?
    public let quietHoursEndMinuteOfDay: Int?
    public let retentionDays: Int
    /// The retired daily ritual's switch (focus-g9iw). Carried so a document round-trips between
    /// builds; nothing in the app reads it any more.
    public let ritualEnabled: Bool
    public let hotKeyKeyCode: Int
    public let hotKeyModifierFlags: Int
    public let idleThresholdSeconds: Int
    public let corroborationTickSeconds: Int
    public let launchContextOnSessionStart: Bool
    public let mediaSuppressionEnabled: Bool
    /// The exclusion rows the person owns: their own additions, and the tombstones that record a
    /// built-in they removed.
    public let exclusions: [Exclusion]

    public struct Exclusion: Codable, Sendable, Equatable, Hashable {
        public let bundleID: String
        public let kindRaw: String

        public init(bundleID: String, kindRaw: String) {
            self.bundleID = bundleID
            self.kindRaw = kindRaw
        }
    }
}
