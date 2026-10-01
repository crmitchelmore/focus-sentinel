import AppKit
import FocusCore
import FocusUI
import Foundation
import os

/// **The two files a person can take away, and the panels that write them** (F-110, F-134,
/// focus-ix9).
///
/// ## Why the panels are here and not in the pane
///
/// `NSSavePanel` and `NSOpenPanel` need the store to have something to write and somewhere to
/// put what they read, and the pane has neither: it emits a verb and the composition root
/// performs it, exactly as `deleteEverything` and the retention window do. What is left in the
/// pane is three buttons.
///
/// ## No grant, and no share sheet
///
/// The app is unsandboxed, so a save panel is an ordinary window rather than a Powerbox request,
/// and neither panel raises a TCC dialog: the person is choosing a location, which is not a
/// permission. The self-check proves it rather than asserting it — it drives the same two verbs
/// with the panel step replaced by a URL of its own, and takes the authorisation-surface scan on
/// both sides of the write (R-33, PD-1).
///
/// `NSSharingService` is deliberately absent. It routes a private file to a network service in
/// one click, at the exact surface whose job is to prove there are none.
///
/// ## Why the outcome is a value
///
/// `Outcome` is a closed vocabulary rather than a `Bool` and a log line, because the pane has to
/// be able to say *why* an import was refused and the gate has to be able to read what happened.
/// A refusal that only reached the log is a refusal the person never saw.
public enum DataPortabilityOutcome: Sendable, Equatable {
    /// Nothing has been asked for yet, or the person dismissed the panel.
    case none
    /// A file was written, and how many bytes went into it.
    case exported(name: String, bytes: Int)
    /// A settings file was read and applied whole.
    case imported(name: String)
    /// A settings file was refused, whole, with its reason.
    case refused(SettingsImportRefusal)
    /// A requested export failed. Keep the system error for its localised recovery advice.
    case failed(NSError)

    /// One line, for the log and for the self-check. Never the *path*: where somebody keeps their
    /// own files is theirs, and a receipt carrying it would put it in a gate log.
    public var summary: String {
        switch self {
        case .none: "none"
        case .exported(let name, let bytes): "exported \(name) (\(bytes) bytes)"
        case .imported(let name): "imported \(name)"
        case .refused(let refusal): "refused: \(refusal.reason)"
        case .failed(let error): "export failed (\(error.domain), \(error.code))"
        }
    }
}

/// The two document types, as the panels describe them.
enum PortableDocument {
    /// The suggested filename, without a directory. Dated, because a person who exports twice
    /// wants two files rather than a question about replacing one.
    static func dataFilename(on day: LocalDay) -> String {
        "Focus Sentinel Data \(day.key).json"
    }

    static func settingsFilename(on day: LocalDay) -> String {
        "Focus Sentinel Settings \(day.key).json"
    }
}

extension AppComposition {
    private var portabilityLogger: Logger {
        Logger(subsystem: FocusStore.bundleIdentifier, category: "portability")
    }

    /// **Write the person's data to a URL.** The half with no panel in it, so a lane can drive it.
    @MainActor
    @discardableResult
    public func writeDataExport(to url: URL) -> DataPortabilityOutcome {
        guard !hasDeletedEverything else { return .none }
        do {
            let data = try StoreExport.json(
                in: modelContainer.mainContext,
                generatedAt: dateProvider.now
            )
            try data.write(to: url, options: .atomic)
            return .exported(name: url.lastPathComponent, bytes: data.count)
        } catch {
            portabilityLogger.error(
                "the data export could not be written: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(error as NSError)
        }
    }

    /// **Write the person's settings to a URL.** Same shape, second document type.
    @MainActor
    @discardableResult
    public func writeSettingsExport(to url: URL) -> DataPortabilityOutcome {
        guard !hasDeletedEverything else { return .none }
        do {
            let data = try SettingsDocument.json(
                from: modelContainer.mainContext,
                generatedAt: dateProvider.now
            )
            try data.write(to: url, options: .atomic)
            return .exported(name: url.lastPathComponent, bytes: data.count)
        } catch {
            portabilityLogger.error(
                "the settings export could not be written: \(error.localizedDescription, privacy: .public)"
            )
            return .failed(error as NSError)
        }
    }

    /// **Read a settings file back, whole or not at all.**
    ///
    /// An import is untrusted input: it may have been written by a newer build, an older build, a
    /// text editor, or nothing at all. `SettingsDocument.import` validates before it writes, so a
    /// refusal here has changed nothing.
    @MainActor
    @discardableResult
    public func readSettingsImport(from url: URL) -> DataPortabilityOutcome {
        guard !hasDeletedEverything else { return .none }
        guard let data = try? Data(contentsOf: url) else {
            return .refused(.malformed)
        }
        switch SettingsDocument.import(
            data,
            into: modelContainer.mainContext,
            now: dateProvider.now
        ) {
        case .success:
            // Every host reads its settings when it is built, so the ones the import moved are
            // re-read here rather than left until the next launch.
            refreshCockpit()
            return .imported(name: url.lastPathComponent)
        case .failure(let refusal):
            portabilityLogger.notice(
                "a settings import was refused: \(refusal.reason, privacy: .public)"
            )
            return .refused(refusal)
        }
    }

    /// Where the export save panel starts: beside the active store, or `nil` when it is
    /// memory-only.
    var exportDirectoryURL: URL? { activeStoreURL?.deletingLastPathComponent() }

    /// The save panel for either document. Returns `nil` when the person dismissed it, which is
    /// an answer and not a failure.
    @MainActor
    func chooseSaveLocation(named name: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        // The app's own directory, so somebody who presses Return without looking gets a file
        // beside their store rather than in whatever folder AppKit last remembered. The store
        // this session is using (focus-k2in); a memory-only session has none, and AppKit's own
        // choice is then the honest one.
        panel.directoryURL = exportDirectoryURL
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The open panel for the settings document.
    @MainActor
    func chooseSettingsFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.urls.first : nil
    }

    /// **What the three Privacy verbs and the three File-menu items both reach.**
    ///
    /// The panel is the only part of this a lane cannot drive, so it is the only part that lives
    /// here: everything either side of it is a verb above, driven directly by the self-check.
    @MainActor
    public func performPortability(_ action: PrivacySettingsAction) {
        guard !hasDeletedEverything else { return }
        let today = LocalDay.today(calendar: calendar, dateProvider: dateProvider)
        let outcome: DataPortabilityOutcome
        switch action {
        case .exportData:
            guard let url = chooseSaveLocation(named: PortableDocument.dataFilename(on: today))
            else { return }
            outcome = writeDataExport(to: url)
        case .exportSettings:
            guard let url = chooseSaveLocation(named: PortableDocument.settingsFilename(on: today))
            else { return }
            outcome = writeSettingsExport(to: url)
        case .importSettings:
            guard let url = chooseSettingsFile() else { return }
            outcome = readSettingsImport(from: url)
        case .deleteEverything, .setRetentionWindow, .setSensingPaused, .setIdleThreshold,
             .setMediaSuppression, .setLaunchContextOnSessionStart, .setGrantOptIn:
            return
        }
        lastPortabilityOutcome = outcome
        portabilityLogger.notice("portability: \(outcome.summary, privacy: .public)")
        if case .refused(let refusal) = outcome {
            // The one thing a person must not have to read a log for. An alert rather than a line
            // in the pane because an import is a thing they just did, and the answer belongs
            // where they are looking.
            let alert = NSAlert()
            alert.messageText = PrivacySettingsAction.importRefusedTitle
            alert.informativeText = refusal.reason
            alert.alertStyle = .warning
            alert.runModal()
        } else if case .failed(let error) = outcome {
            NSAlert(error: error).runModal()
        }
    }
}
