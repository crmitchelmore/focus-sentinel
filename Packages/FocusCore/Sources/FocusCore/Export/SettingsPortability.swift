import Foundation
import SwiftData

/// Why an import was refused, in the person's terms rather than the parser's.
///
/// A closed vocabulary rather than a `String`, so the pane can name each one, the unit lane can
/// fold over every arm, and a new refusal cannot be added without a word for it.
public enum SettingsImportRefusal: Error, Sendable, Equatable, Hashable {
    /// The file parsed, but it is not a settings document at all — most likely a data export.
    case notASettingsDocument(String)
    /// A version this build does not know. The number is carried so the message can say it.
    case unknownVersion(Int)
    /// The bytes are not a settings document's JSON.
    case malformed
    /// A deck this build has never heard of. Refused rather than silently defaulted: an import
    /// that quietly changed the person's voice would be a settings file that lied.
    case unknownVoice(String)
    /// A retention window this build does not offer.
    case unknownRetentionWindow(Int)
    /// An exclusion row naming something that is not a bundle identifier.
    case unnormalisableSubject(String)
    /// A quick-capture combination this platform will not register.
    case unusableShortcut(String)

    public var reason: String {
        switch self {
        case .notASettingsDocument(let format): "not a settings document: \(format)"
        case .unknownVersion(let version): "settings document version \(version) is not readable"
        case .malformed: "the file is not a settings document"
        case .unknownVoice(let raw): "unknown voice: \(raw)"
        case .unknownRetentionWindow(let days): "unknown retention window: \(days)"
        case .unnormalisableSubject(let subject): "not an application identifier: \(subject)"
        case .unusableShortcut(let reason): "the quick-capture combination is unusable: \(reason)"
        }
    }
}

extension SettingsDocument {
    /// Read every travelling preference out of one store.
    @MainActor
    public static func read(from context: ModelContext, generatedAt: Date) -> SettingsDocument {
        let appearance = FocusStore.appearancePreference(in: context)
        let intervention = FocusStore.interventionPreferences(in: context)
        let privacy = FocusStore.privacyPreferences(in: context)
        let ritualEnabled = FocusStore.ritualEnabled(in: context)
        let shortcut = FocusStore.hotKeySpec(in: context)
        let sensing = FocusStore.sensingSettings(in: context)
        let exclusions = (try? SensitiveAppSeed.rows(in: context)) ?? []

        return SettingsDocument(
            format: formatName,
            version: formatVersion,
            generatedAt: generatedAt,
            appearanceRaw: appearance.rawValue,
            voiceRaw: intervention.voice.rawValue,
            reducedInterruption: intervention.reducedInterruption,
            quietHoursStartMinuteOfDay: intervention.quietHours?.startMinuteOfDay,
            quietHoursEndMinuteOfDay: intervention.quietHours?.endMinuteOfDay,
            retentionDays: privacy.retention.storedDays,
            ritualEnabled: ritualEnabled,
            hotKeyKeyCode: shortcut.keyCode,
            hotKeyModifierFlags: shortcut.modifierFlags,
            idleThresholdSeconds: sensing.idleThresholdSeconds,
            corroborationTickSeconds: sensing.corroborationTickSeconds,
            launchContextOnSessionStart: sensing.launchContextOnSessionStart,
            mediaSuppressionEnabled: sensing.mediaSuppressionEnabled,
            exclusions: exclusions
                .filter { !$0.isBuiltIn || !($0.kind?.isActive ?? true) }
                .map { Exclusion(bundleID: $0.bundleID, kindRaw: $0.kindRaw) }
                .sorted { ($0.bundleID, $0.kindRaw) < ($1.bundleID, $1.kindRaw) }
        )
    }
}

extension SettingsDocument {
    /// **Parse and validate, without touching the store.**
    ///
    /// Separate from `apply` on purpose: the pane wants to be able to say *why* a file was
    /// refused before anything has changed, and a validator that had already written half of
    /// what it read could not.
    public static func decode(_ data: Data) -> Result<SettingsDocument, SettingsImportRefusal> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(SettingsDocument.self, from: data) else {
            // A data export is the file somebody is most likely to pick by mistake, and it
            // deserves its own sentence rather than "malformed".
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let manifest = object["manifest"] as? [String: Any],
                let format = manifest["format"] as? String {
                return .failure(.notASettingsDocument(format))
            }
            return .failure(.malformed)
        }
        guard document.format == formatName else {
            return .failure(.notASettingsDocument(document.format))
        }
        guard readableVersions.contains(document.version) else {
            return .failure(.unknownVersion(document.version))
        }
        guard NudgeVoice.decode(document.voiceRaw).wasRecognised else {
            return .failure(.unknownVoice(document.voiceRaw))
        }
        guard RetentionWindow.decode(document.retentionDays).wasRecognised else {
            return .failure(.unknownRetentionWindow(document.retentionDays))
        }
        let shortcut = HotKeySpec(
            keyCode: document.hotKeyKeyCode,
            modifierFlags: document.hotKeyModifierFlags
        )
        if let refusal = shortcut.refusal {
            return .failure(.unusableShortcut(String(describing: refusal)))
        }
        for exclusion in document.exclusions {
            guard SensitiveEntryKind(rawValue: exclusion.kindRaw) != nil else {
                return .failure(.unnormalisableSubject(exclusion.kindRaw))
            }
            guard isApplicationIdentifier(exclusion.bundleID) else {
                return .failure(.unnormalisableSubject(exclusion.bundleID))
            }
        }
        return .success(document)
    }

    /// A bundle identifier and nothing else. The exclusion lists key on applications, so an
    /// origin, a path or a sentence in that column is a document this build refuses rather
    /// than one it silently drops a row from.
    static func isApplicationIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == value, !trimmed.isEmpty, trimmed.count <= 255 else { return false }
        guard !trimmed.hasPrefix("."), !trimmed.hasSuffix("."), trimmed.contains(".") else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"
            + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        return trimmed.unicodeScalars.allSatisfy(allowed.contains)
    }
}

extension SettingsDocument {
    /// **Apply the whole document, or none of it.**
    ///
    /// Validation happens in `decode(_:)` before this is reached, so by the time a document is
    /// here every value in it is one this build can write. What is left is one save: SwiftData's
    /// context is the transaction, so a throw before `save()` leaves the store as it was.
    ///
    /// Exclusions are **merged, never replaced.** An import is somebody saying *"also set this
    /// Mac up like that one"*, not *"forget what this Mac knows"* — and the built-in list is
    /// reseeded by the app on every launch anyway, so a replace would be a deletion that
    /// undid itself.
    @MainActor
    @discardableResult
    public static func apply(
        _ document: SettingsDocument,
        to context: ModelContext,
        now: Date
    ) throws -> Int {
        try FocusStore.setAppearancePreference(
            AppearancePreference(rawValue: document.appearanceRaw) ?? .matchSystem,
            in: context,
            now: now
        )
        try FocusStore.setInterventionPreferences(
            InterventionPreferences(
                voice: NudgeVoice.decode(document.voiceRaw).voice,
                reducedInterruption: document.reducedInterruption,
                quietHours: quietHours(of: document)
            ),
            in: context,
            now: now
        )
        try FocusStore.setRetentionWindow(
            RetentionWindow.decode(document.retentionDays).window,
            in: context,
            now: now
        )
        try FocusStore.setRitualEnabled(document.ritualEnabled, in: context, now: now)
        try FocusStore.setHotKeySpec(
            HotKeySpec(
                keyCode: document.hotKeyKeyCode,
                modifierFlags: document.hotKeyModifierFlags
            ),
            in: context,
            now: now
        )

        var sensing = FocusStore.sensingSettings(in: context)
        sensing.idleThresholdSeconds = document.idleThresholdSeconds
        sensing.corroborationTickSeconds = document.corroborationTickSeconds
        sensing.launchContextOnSessionStart = document.launchContextOnSessionStart
        sensing.mediaSuppressionEnabled = document.mediaSuppressionEnabled
        try FocusStore.setSensingSettings(sensing, in: context, now: now)

        var applied = 0
        for exclusion in document.exclusions {
            guard let kind = SensitiveEntryKind(rawValue: exclusion.kindRaw) else { continue }
            if kind.isActive {
                _ = try SensitiveAppSeed.add(
                    bundleID: exclusion.bundleID,
                    to: kind,
                    in: context,
                    now: now
                )
            } else {
                try SensitiveAppSeed.remove(
                    bundleID: exclusion.bundleID,
                    from: kind,
                    in: context
                )
            }
            applied += 1
        }
        return applied
    }
}

extension SettingsDocument {
    /// The window, or `nil` for no window — which is a real answer (R-85) rather than a gap, and
    /// is what a document carrying only one of the two offsets must also mean.
    static func quietHours(of document: SettingsDocument) -> QuietHoursWindow? {
        guard
            let start = document.quietHoursStartMinuteOfDay,
            let end = document.quietHoursEndMinuteOfDay
        else { return nil }
        return QuietHoursWindow(startMinuteOfDay: start, endMinuteOfDay: end)
    }
}

extension SettingsDocument {
    /// The document as bytes, deterministically. Same encoder contract as `StoreExport.json`:
    /// two exports of an unchanged store differ only in `generatedAt`.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Read one store, encode it. The verb the Settings pane and the File menu both reach.
    @MainActor
    public static func json(from context: ModelContext, generatedAt: Date) throws -> Data {
        try read(from: context, generatedAt: generatedAt).json()
    }

    /// **Validate and apply in one call, or refuse and change nothing.**
    ///
    /// The verb a surface should reach for: the two-step shape below it exists so a pane can say
    /// why *before* anything moves, and this is the composition of the two so no caller has to
    /// remember to do the first.
    @MainActor
    public static func `import`(
        _ data: Data,
        into context: ModelContext,
        now: Date
    ) -> Result<SettingsDocument, SettingsImportRefusal> {
        switch decode(data) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(let document):
            do {
                _ = try apply(document, to: context, now: now)
                return .success(document)
            } catch {
                return .failure(.malformed)
            }
        }
    }
}
