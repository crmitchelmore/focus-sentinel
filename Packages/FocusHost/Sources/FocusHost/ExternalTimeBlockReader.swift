import FocusCore
import Foundation

/// **Time an outside source has marked** (focus-ext), as the calendar host reads it.
///
/// `nil` means no source has written anything, which keeps a default install's agenda `.unread`.
@MainActor
protocol ExternalTimeReading: AnyObject {
    func busyBlocks(in interval: DateInterval) -> [CalendarBusyBlock]?
}

/// **Reads the provider files `focus-bridge` writes** (focus-ext): one JSON file per source in
/// `<Application Support>/<train>/TimeBlocks`.
///
/// Called on every cockpit tick and nudge check, so it lists the directory and re-reads the
/// files only when a name, size or modification date changed. Only the stretches that hold the
/// question are kept, and only as instants: titles stay in the provider's files.
@MainActor
final class ExternalTimeBlockReader: ExternalTimeReading {
    let directory: URL
    private var signature: [String] = []
    private var blocks: [CalendarBusyBlock] = []
    private var hasSources = false
    private(set) var fileReads = 0

    init(directory: URL) {
        self.directory = directory
    }

    func busyBlocks(in interval: DateInterval) -> [CalendarBusyBlock]? {
        refreshIfChanged()
        guard hasSources else { return nil }
        return blocks.filter { $0.end > interval.start && $0.start < interval.end }
    }

    private func refreshIfChanged() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let current = files.map { url -> String in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            return "\(url.lastPathComponent)|\(values?.fileSize ?? -1)|\(modified)"
        }
        guard current != signature else { return }
        signature = current
        // The whole of every file, so a window that moves on finds blocks already read.
        let everything = DateInterval(start: .distantPast, end: .distantFuture)
        var read: [CalendarBusyBlock] = []
        var anySource = false
        for url in files {
            guard let data = try? Data(contentsOf: url),
                  let found = ExternalTimeBlocks.busyBlocks(from: data, in: everything)
            else { continue }
            fileReads += 1
            anySource = true
            read.append(contentsOf: found)
        }
        blocks = read
        hasSources = anySource
    }
}
