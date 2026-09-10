import Foundation
import SwiftData
import Testing

@testable import FocusCore

/// The four kinds, their round trip through the store, and what happens to a fifth.
@Suite("Context item kinds and values")
struct ContextItemValueTests {
    private let clock = FixedDateProvider.reference

    @Test("the four kinds round-trip their raw values, and there is no fifth")
    func knownKindsRoundTrip() {
        #expect(ContextItemKind.known.count == 4)
        for kind in ContextItemKind.known {
            #expect(ContextItemKind(rawValue: kind.rawValue) == kind)
            #expect(kind.isKnown)
        }
        #expect(Set(ContextItemKind.known.map(\.rawValue)) == ["app", "domain", "keyword", "file"])
        // Distinct silhouettes: the chip is told apart by shape, not only by colour.
        #expect(Set(ContextItemKind.known.map(\.symbolName)).count == 4)
    }

    @Test("a kind this build does not know keeps its own string and renders inert")
    func unknownKindIsPreserved() {
        let kind = ContextItemKind(rawValue: "personFromTheFuture")
        #expect(kind == .unknown("personFromTheFuture"))
        #expect(kind.isKnown == false)
        #expect(kind.rawValue == "personFromTheFuture", "an unknown kind must round-trip verbatim")
        #expect(kind.symbolName == "questionmark.square.dashed")
        #expect(ContextItemKind(rawValue: "") == .unknown(""))
    }

    @Test("every kind survives a round trip through the store, unknown included")
    @MainActor
    func kindsRoundTripThroughTheStore() throws {
        let container = try FocusStore.makeContainer(kind: .inMemory)
        let context = container.mainContext

        let task = FocusSchemaV3.PriorityTask(intent: "Hold some context", createdAt: clock.now)
        context.insert(task)

        let raws = ["app", "domain", "keyword", "file", "personFromTheFuture"]
        for raw in raws {
            context.insert(
                FocusSchemaV3.ContextItem(
                    kindRaw: raw,
                    value: "value-\(raw)",
                    displayName: "name-\(raw)",
                    addedAt: clock.now,
                    task: task
                )
            )
        }
        try context.save()

        let items = try context.fetch(FetchDescriptor<FocusSchemaV3.ContextItem>())
        #expect(items.count == 5, "a row was dropped rather than kept")
        #expect(Set(items.map(\.kindRaw)) == Set(raws))

        let projected = items.map { ContextItemValue($0) }
        let unknown = try #require(projected.first { !$0.kind.isKnown })
        #expect(unknown.kind == .unknown("personFromTheFuture"))
        #expect(unknown.availability == .unknownKind, "an unknown kind renders as an inert chip")
        #expect(projected.filter { $0.kind.isKnown }.allSatisfy { $0.availability == .available })

        // And mutating through the decoded accessor writes the raw value back.
        let first = try #require(items.first { $0.kindRaw == "keyword" })
        first.kind = .domain
        #expect(first.kindRaw == "domain")
    }

    @Test("an app chip keeps the bundle identifier as its subject")
    func appChip() {
        let item = ContextItemValue.app(
            bundleID: "com.apple.dt.Xcode",
            displayName: "Xcode",
            addedAt: clock.now
        )
        #expect(item.kind == .app)
        #expect(item.value == "com.apple.dt.Xcode")
        #expect(item.displayName == "Xcode")
        #expect(item.bookmark == nil)
        #expect(item.availability == .available)
    }

    @Test("a keyword chip is trimmed and lowercased, and an empty one is not a chip")
    func keywordChip() {
        let item = ContextItemValue.keyword("  Proposal  ", addedAt: clock.now)
        #expect(item?.kind == .keyword)
        #expect(item?.value == "proposal")
        #expect(item?.displayName == "proposal")

        #expect(ContextItemValue.keyword("", addedAt: clock.now) == nil)
        #expect(ContextItemValue.keyword("   \n ", addedAt: clock.now) == nil)
    }

    @Test("a file chip shows the file name and holds the path only for display")
    func fileChip() {
        let url = URL(fileURLWithPath: "/Users/someone/Documents/Q3 proposal.pages")
        let item = ContextItemValue.file(
            url: url,
            bookmark: Data([0x01]),
            addedAt: clock.now
        )
        #expect(item.kind == .file)
        #expect(item.displayName == "Q3 proposal.pages")
        #expect(item.value == "/Users/someone/Documents/Q3 proposal.pages")
        #expect(item.bookmark == Data([0x01]))
    }

    @Test("a domain chip shows the host, with a port only when there is one")
    func domainChipDisplayNames() {
        #expect(ContextItemValue.displayName(forOrigin: "https://example.com") == "example.com")
        #expect(ContextItemValue.displayName(forOrigin: "http://localhost:3000") == "localhost:3000")
        #expect(ContextItemValue.displayName(forOrigin: "not a url") == "not a url")
    }
}
