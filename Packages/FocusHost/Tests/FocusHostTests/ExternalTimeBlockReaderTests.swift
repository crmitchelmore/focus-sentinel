import FocusCore
import Foundation
import Testing
@testable import FocusHost

/// **Outside sources' time blocks reach the agenda** (focus-ext), read from a directory the test
/// owns. Pure: no window, no composition root.
@Suite("External time blocks in the calendar host", .serialized)
@MainActor
struct ExternalTimeBlockReaderTests {
    private static let now = NudgeHostFixture.reference

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "focus-time-blocks-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func write(_ blocks: [TimeBlock], source: String, to directory: URL) throws {
        let file = TimeBlockFile(source: source, updatedAt: now, blocks: blocks)
        try ExternalTimeBlocks.encoder().encode(file)
            .write(to: ExternalTimeBlocks.fileURL(for: source, in: directory), options: .atomic)
    }

    private static func block(_ kind: TimeBlockKind, _ from: TimeInterval, _ to: TimeInterval) -> TimeBlock {
        TimeBlock(kind: kind, start: now.addingTimeInterval(from), end: now.addingTimeInterval(to), title: "Private title")
    }

    @Test("no file leaves the agenda unread; a file makes it read")
    func noFileIsUnread() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = CalendarHost()
        host.useExternal(ExternalTimeBlockReader(directory: directory))
        #expect(host.agenda(at: Self.now) == .unread)

        try Self.write([Self.block(.focus, 0, 600)], source: "rota", to: directory)
        let agenda = host.agenda(at: Self.now)
        #expect(agenda.isRead)
        #expect(agenda.busy.isEmpty, "focus time silenced the app")
    }

    @Test("a busy block from a source is a meeting, and is seen as soon as the file changes")
    func busyIsAMeeting() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = CalendarHost()
        let reader = ExternalTimeBlockReader(directory: directory)
        host.useExternal(reader)

        try Self.write([Self.block(.busy, -300, 1_500)], source: "outlook", to: directory)
        #expect(host.agenda(at: Self.now).outlook(at: Self.now).isInMeeting)
        _ = host.agenda(at: Self.now.addingTimeInterval(5))
        #expect(reader.fileReads == 1, "an unchanged directory was read again")

        try Self.write([Self.block(.away, 1_800, 3_600)], source: "outlook", to: directory)
        let outlook = host.agenda(at: Self.now.addingTimeInterval(10)).outlook(at: Self.now)
        #expect(!outlook.isInMeeting)
        #expect(outlook.refusal(forTimeboxSeconds: 60 * 60) != nil, "a timebox ran into time a source marked away")

        try FileManager.default.removeItem(at: ExternalTimeBlocks.fileURL(for: "outlook", in: directory))
        #expect(host.agenda(at: Self.now.addingTimeInterval(15)) == .unread)
    }

    @Test("sources merge with each other and with the calendar")
    func merges() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = CalendarHost()
        host.useExternal(ExternalTimeBlockReader(directory: directory))
        host.use(ScriptedCalendar(busy: [CalendarBusyBlock(start: Self.now, end: Self.now.addingTimeInterval(600))]))
        try Self.write([Self.block(.busy, 600, 1_200)], source: "a", to: directory)
        try Self.write([Self.block(.tentative, 1_200, 1_800)], source: "b", to: directory)
        try Data("not json".utf8).write(to: directory.appending(path: "broken.json"))

        let agenda = host.agenda(at: Self.now)
        #expect(agenda.busy == [CalendarBusyBlock(start: Self.now, end: Self.now.addingTimeInterval(1_800))])
    }
}
