import Foundation
import SwiftData
import Testing

@testable import FocusCore

@MainActor
struct ActivityEventStoreHarness {
    let container: ModelContainer
    let store: ActivityEventStore
    let clock: MovingDateProvider

    init(clock: MovingDateProvider = MovingDateProvider()) throws {
        container = try FocusStore.makeContainer(kind: .inMemory)
        self.clock = clock
        store = ActivityEventStore(context: container.mainContext, dateProvider: clock)
    }
}

@MainActor
@Suite("Activity event store")
struct ActivityEventStoreTests {
    /// The hostile corpus, in the shape a careless producer would hand it over: a window title,
    /// a full URL with a path and a query, a document name and an absolute file path.
    ///
    /// None of it can reach the store, and the reason is not this test — it is that
    /// `NormalisedDetail` has no `String` initialiser, so none of these values can be turned
    /// into the type `append` requires. This suite proves the enforcement rather than being it.
    static let hostileCorpus = [
        "Quarterly report — DRAFT — confidential.docx",
        "https://mail.example.com/u/0/#inbox/FMfcgzQbfKlmNpQrStUvWx?compose=new",
        "Salary review — Alex Chen.pdf",
        "/Users/someone/Documents/Personal/divorce-settlement.rtf",
        "Re: are you free on Thursday"
    ]

    // MARK: - Append and read back

    @Test("An appended row keeps its kind, subject and instant")
    func appendRoundTrips() throws {
        let harness = try ActivityEventStoreHarness()

        try harness.store.append(
            kind: .frontmostApplicationChanged,
            bundleID: "com.apple.TextEdit",
            detail: .measurement(.dwellSeconds, 42),
            dwellSeconds: 42
        )

        let rows = try harness.store.all()
        #expect(rows.count == 1)
        #expect(rows[0].kindRaw == "frontmostApplicationChanged")
        #expect(rows[0].bundleID == "com.apple.TextEdit")
        #expect(rows[0].at == harness.clock.now)
        #expect(rows[0].dwellSeconds == 42)
        #expect(rows[0].detail == "dwellSeconds=42")
    }

    @Test("A row with nothing to add stores no detail at all")
    func emptyDetailStoresNothing() throws {
        let harness = try ActivityEventStoreHarness()
        try harness.store.append(kind: .userIdle)

        #expect(try harness.store.all().first?.detail == nil)
    }

    @Test("An explicit instant is used rather than the clock being re-read")
    func explicitInstantWins() throws {
        let harness = try ActivityEventStoreHarness()
        let stamped = harness.clock.now.addingTimeInterval(-5)

        try harness.store.append(kind: .userActive, at: stamped)
        harness.clock.advance(by: 100)

        #expect(try harness.store.all().first?.at == stamped)
    }

    // MARK: - Ordering

    @Test("Rows read back oldest first")
    func rowsReadBackInOrder() throws {
        let harness = try ActivityEventStoreHarness()

        try harness.store.append(kind: .frontmostApplicationChanged, bundleID: "com.a")
        harness.clock.advance(by: 10)
        try harness.store.append(kind: .frontmostApplicationChanged, bundleID: "com.b")
        harness.clock.advance(by: 10)
        try harness.store.append(kind: .frontmostApplicationChanged, bundleID: "com.c")

        #expect(try harness.store.all().map(\.bundleID) == ["com.a", "com.b", "com.c"])
    }

    @Test("Rows stamped at one instant read back in one stable order")
    func simultaneousRowsHaveAStableOrder() throws {
        let harness = try ActivityEventStoreHarness()

        // What the corroboration tick produces: several observations of the same instant.
        for kind in [ActivityEventKind.presentationChanged, .displayChanged, .mediaActivityChanged] {
            try harness.store.append(kind: kind)
        }

        let first = try harness.store.all().map(\.kindRaw)
        let second = try harness.store.all().map(\.kindRaw)
        #expect(first == second)
        #expect(first.count == 3)
    }

    // MARK: - Querying

    @Test("A range query is half-open, so two windows partition the timeline exactly")
    func rangeQueryIsHalfOpen() throws {
        let harness = try ActivityEventStoreHarness()
        let origin = harness.clock.now

        try harness.store.append(kind: .userActive, bundleID: "before", at: origin.addingTimeInterval(-1))
        try harness.store.append(kind: .userActive, bundleID: "start", at: origin)
        try harness.store.append(kind: .userActive, bundleID: "inside", at: origin.addingTimeInterval(5))
        try harness.store.append(kind: .userActive, bundleID: "end", at: origin.addingTimeInterval(10))

        let window = try harness.store.events(from: origin, to: origin.addingTimeInterval(10))

        // The row on the lower boundary is in; the one on the upper boundary belongs to the
        // next window and to nothing else.
        #expect(window.map(\.bundleID) == ["start", "inside"])
    }

    @Test("Rows can be read back by session")
    func sessionQuery() throws {
        let harness = try ActivityEventStoreHarness()
        let mine = UUID()
        let other = UUID()

        try harness.store.append(kind: .sessionPhaseChanged, sessionID: mine)
        try harness.store.append(kind: .sessionPhaseChanged, sessionID: other)
        try harness.store.append(kind: .sessionPhaseChanged, sessionID: mine)

        #expect(try harness.store.events(ofSession: mine).count == 2)
        #expect(try harness.store.count() == 3)
    }

    // MARK: - The export (criterion 33)

    @Test("The export carries tokens, numbers, bundle identifiers and timestamps, and nothing else")
    func exportIsClean() throws {
        let harness = try ActivityEventStoreHarness()
        try harness.store.append(
            kind: .presentationChanged,
            bundleID: "com.apple.Keynote",
            detail: .tokens([.fullScreen, .secondaryDisplay]),
            sessionID: UUID(),
            dwellSeconds: 12.5,
            displayID: 3
        )

        let data = try harness.store.exportJSON()
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains("fullScreen"))
        #expect(text.contains("secondaryDisplay"))
        #expect(text.contains("com.apple.Keynote"))
        #expect(text.contains("12.5"))

        let decoded = try JSONDecoder.exportDecoder.decode(
            [ActivityEventStore.ExportedEvent].self,
            from: data
        )
        #expect(decoded.count == 1)
        #expect(decoded[0].tokens == ["fullScreen", "secondaryDisplay"])
        #expect(decoded[0].kind == "presentationChanged")
        #expect(decoded[0].displayID == 3)
    }

    @Test("A measurement exports as its kind and its integer")
    func measurementsExport() throws {
        let harness = try ActivityEventStoreHarness()
        try harness.store.append(kind: .userIdle, detail: .measurement(.hardwareIdleSeconds, 1536))

        let decoded = try JSONDecoder.exportDecoder.decode(
            [ActivityEventStore.ExportedEvent].self,
            from: try harness.store.exportJSON()
        )
        #expect(decoded[0].measurement == "hardwareIdleSeconds")
        #expect(decoded[0].measurementValue == 1536)
        #expect(decoded[0].tokens == nil)
    }

    @Test("A detail column this build cannot interpret exports as nothing at all")
    func unreadableDetailIsInert() throws {
        let harness = try ActivityEventStoreHarness()

        // A row as a **later build** would have written it, carrying a token this one has never
        // heard of. It is constructed rather than assigned: `.detail =` is banned outright by
        // the lint, with no allowlist and no exempted call site, and the ban is what makes the
        // store's own `append` the only way in. What is under test here is the *reader* — a row
        // from the future must be inert, not printed.
        let foreign = FocusSchemaV3.ActivityEvent(
            at: harness.clock.now,
            kindRaw: ActivityEventKind.userIdle.rawValue,
            detail: "aTokenFromTheFuture,anotherOne"
        )
        harness.container.mainContext.insert(foreign)
        try harness.container.mainContext.save()

        #expect(NormalisedDetail.inspect(foreign.detail) == .unreadable)

        let data = try harness.store.exportJSON()
        let text = try #require(String(data: data, encoding: .utf8))

        // Inert: not printed, not guessed at, not passed through.
        #expect(text.contains("aTokenFromTheFuture") == false)

        let decoded = try JSONDecoder.exportDecoder.decode(
            [ActivityEventStore.ExportedEvent].self,
            from: data
        )
        #expect(decoded[0].tokens == nil)
        #expect(decoded[0].measurement == nil)
    }

    @Test("An unknown token beside a known one is dropped and the known one survives")
    func unknownTokensAreDroppedFromAMixedList() {
        // The mixed case, straight through the reader: what a build understands it keeps, and
        // what it does not it discards rather than rendering.
        #expect(NormalisedDetail.inspect("fullScreen,aTokenFromTheFuture") == .tokens([.fullScreen]))
    }

    @Test("A kind this build cannot interpret exports as nothing rather than being guessed at")
    func unknownKindIsInert() throws {
        let harness = try ActivityEventStoreHarness()
        let foreign = FocusSchemaV3.ActivityEvent(
            at: harness.clock.now,
            kindRaw: "somethingALaterBuildInvented"
        )
        harness.container.mainContext.insert(foreign)
        try harness.container.mainContext.save()

        let decoded = try JSONDecoder.exportDecoder.decode(
            [ActivityEventStore.ExportedEvent].self,
            from: try harness.store.exportJSON()
        )
        #expect(decoded[0].kind == nil)
        #expect(ActivityEventKind.decode("somethingALaterBuildInvented") == nil)
    }

    @Test("Two exports of the same timeline are byte-identical")
    func exportIsDeterministic() throws {
        let harness = try ActivityEventStoreHarness()
        try harness.store.append(kind: .sensingPaused, detail: .tokens([.observersDetached]))
        harness.clock.advance(by: 5)
        try harness.store.append(kind: .sensingResumed, detail: .tokens([.observersAttached]))

        #expect(try harness.store.exportJSON() == (try harness.store.exportJSON()))
    }

    // MARK: - The hostile corpus (F-40, SC-3)

    @Test("Nothing in the hostile corpus can be turned into a detail in the first place")
    func hostileCorpusIsUnrepresentable() throws {
        let harness = try ActivityEventStoreHarness()

        // The only two constructors there are. A window title is neither a token from the
        // closed vocabulary nor an integer measurement, so there is no expression that turns
        // one into the argument `append` requires — which is why this loop appends tokens and
        // measurements rather than trying and failing to append the corpus.
        for (index, _) in Self.hostileCorpus.enumerated() {
            try harness.store.append(
                kind: .contextChanged,
                bundleID: "com.apple.Safari",
                detail: .measurement(.windowCount, index)
            )
        }

        let text = try #require(String(data: try harness.store.exportJSON(), encoding: .utf8))
        for hostile in Self.hostileCorpus {
            #expect(text.contains(hostile) == false)
        }
    }

    @Test("A suppressed activation writes one row carrying the bundle identifier and nothing else")
    func suppressionRowCarriesOnlyTheBundleIdentifier() throws {
        let harness = try ActivityEventStoreHarness()

        try harness.store.append(
            kind: .sensitiveAppSuppressed,
            bundleID: "com.1password.1password",
            detail: .tokens([.sensitiveApp])
        )

        let decoded = try JSONDecoder.exportDecoder.decode(
            [ActivityEventStore.ExportedEvent].self,
            from: try harness.store.exportJSON()
        )
        #expect(decoded.count == 1)
        #expect(decoded[0].bundleID == "com.1password.1password")
        #expect(decoded[0].tokens == ["sensitiveApp"])
        // Nothing was read, so there is nothing to report about what was on the screen.
        #expect(decoded[0].measurement == nil)
        #expect(decoded[0].displayID == nil)
        #expect(decoded[0].dwellSeconds == nil)
    }

    @Test("Every one of the fourteen kinds can be appended and read back")
    func everyKindRoundTrips() throws {
        let harness = try ActivityEventStoreHarness()

        for kind in ActivityEventKind.allCases {
            try harness.store.append(kind: kind)
            harness.clock.advance(by: 1)
        }

        let stored = try harness.store.all().map(\.kindRaw)
        #expect(stored == ActivityEventKind.allCases.map(\.rawValue))
        #expect(stored.count == 14)
    }
}

extension JSONDecoder {
    /// The mirror of the exporter's encoder, so a test decodes what the lane will read.
    static var exportDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
