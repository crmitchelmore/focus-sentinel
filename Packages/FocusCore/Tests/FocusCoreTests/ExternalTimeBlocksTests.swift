import Foundation
import Testing
@testable import FocusCore

@Suite("External time blocks")
struct ExternalTimeBlocksTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static func file(_ blocks: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "source": "outlook", "updatedAt": "2026-10-16T09:00:00Z", "blocks": blocks])
    }

    private static func iso(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(offset))
    }

    private static var window: DateInterval {
        DateInterval(start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(3_600))
    }

    @Test("busy, away and tentative hold the question; focus and free do not")
    func kinds() {
        #expect(TimeBlockKind.allCases.filter(\.holdsTheQuestion) == [.busy, .away, .tentative])
    }

    @Test("the app reads only the kinds that hold the question, inside the window")
    func readsHoldingKinds() throws {
        let data = try Self.file([
            ["kind": "busy", "start": Self.iso(0), "end": Self.iso(1_800), "title": "Standup"],
            ["kind": "focus", "start": Self.iso(0), "end": Self.iso(1_800)],
            ["kind": "away", "start": Self.iso(-7_200), "end": Self.iso(-5_400)],
            ["kind": "teleport", "start": Self.iso(0), "end": Self.iso(600)],
            ["kind": "tentative", "start": Self.iso(600), "end": Self.iso(300)],
        ])
        let blocks = try #require(ExternalTimeBlocks.busyBlocks(from: data, in: Self.window))
        #expect(blocks == [CalendarBusyBlock(start: Self.now, end: Self.now.addingTimeInterval(1_800))])
    }

    @Test("a block given only as kind, start and end is enough")
    func minimalBlock() throws {
        let data = Data(#"{"blocks":[{"kind":"away","start":"\#(Self.iso(-60))","end":"\#(Self.iso(60))"}]}"#.utf8)
        let blocks = try #require(ExternalTimeBlocks.busyBlocks(from: data, in: Self.window))
        #expect(blocks.count == 1)
        #expect(CalendarAgenda(busy: blocks).outlook(at: Self.now).isInMeeting)
    }

    @Test("an unreadable file is nil, not an empty day")
    func unreadable() {
        #expect(ExternalTimeBlocks.busyBlocks(from: Data("nope".utf8), in: Self.window) == nil)
    }

    @Test("the file round-trips through the shared encoder and decoder")
    func roundTrip() throws {
        let block = TimeBlock(id: "a", kind: .busy, start: Self.now, end: Self.now.addingTimeInterval(900), title: "Review", detail: nil)
        let file = TimeBlockFile(source: "outlook", updatedAt: Self.now, blocks: [block])
        let data = try ExternalTimeBlocks.encoder().encode(file)
        #expect(try ExternalTimeBlocks.decoder().decode(TimeBlockFile.self, from: data) == file)
        #expect(ExternalTimeBlocks.busyBlocks(from: data, in: Self.window)?.count == 1)
    }

    @Test("sources are filename-safe")
    func sources() {
        #expect(ExternalTimeBlocks.isValidSource("outlook"))
        #expect(ExternalTimeBlocks.isValidSource("work.calendar-2_b"))
        #expect(!ExternalTimeBlocks.isValidSource(""))
        #expect(!ExternalTimeBlocks.isValidSource("../store"))
        #expect(!ExternalTimeBlocks.isValidSource(".hidden"))
        #expect(!ExternalTimeBlocks.isValidSource("Outlook"))
        #expect(!ExternalTimeBlocks.isValidSource(String(repeating: "a", count: 65)))
    }

    @Test("validation refuses backwards, overlong and wordy blocks")
    func validation() {
        let start = Self.now
        #expect(throws: TimeBlockError.endNotAfterStart) {
            try ExternalTimeBlocks.validate(TimeBlock(kind: .busy, start: start, end: start))
        }
        #expect(throws: TimeBlockError.tooLong(maximumDays: 31)) {
            try ExternalTimeBlocks.validate(TimeBlock(kind: .away, start: start, end: start.addingTimeInterval(32 * 86_400)))
        }
        #expect(throws: TimeBlockError.textTooLong(field: "title", maximum: 200)) {
            try ExternalTimeBlocks.validate(TimeBlock(kind: .busy, start: start, end: start.addingTimeInterval(60), title: String(repeating: "x", count: 201)))
        }
        let many = Array(repeating: TimeBlock(kind: .busy, start: start, end: start.addingTimeInterval(60)), count: 501)
        #expect(throws: TimeBlockError.tooManyBlocks(maximum: 500)) { try ExternalTimeBlocks.validate(many) }
    }

    @Test("dates parse with or without fractional seconds, or as local time")
    func dates() throws {
        #expect(ExternalTimeBlocks.parseDate("2026-10-16T09:00:00Z") != nil)
        #expect(ExternalTimeBlocks.parseDate("2026-10-16T09:00:00.250+01:00") != nil)
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(ExternalTimeBlocks.parseDate("2026-10-16T09:00", timeZone: utc) == ExternalTimeBlocks.parseDate("2026-10-16T09:00:00Z"))
        #expect(ExternalTimeBlocks.parseDate("tomorrow") == nil)
    }

    @Test("the directory sits beside the store")
    func directory() {
        let store = URL(filePath: "/tmp/x/FocusSentinel.store")
        #expect(ExternalTimeBlocks.directory(besideStore: store).path == "/tmp/x/TimeBlocks")
    }
}
