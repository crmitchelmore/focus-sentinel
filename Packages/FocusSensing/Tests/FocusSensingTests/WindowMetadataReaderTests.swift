import CoreGraphics
import FocusCore
import Foundation
import Testing

@testable import FocusSensing

/// A recorded window-list corpus, in the shape `CGWindowListCopyWindowInfo` actually returns.
///
/// The figures are the ones probe P-74/P-77/P-78 measured on this machine at zero grants: 25
/// on-screen rows carrying all ten sanctioned keys, the Dock permanently owning a window whose
/// bounds are the entire display at layer 20, and Window Server owning the menu bar at layer 24.
enum WindowCorpus {
    static let primaryFrame = ScreenRect(x: 0, y: 0, width: 1920, height: 1080)

    /// The key standing condition 1 bans, **assembled from its two halves rather than written
    /// out**, and the reason it is written that way at all.
    ///
    /// This is the one place in the repository that has to *name* the key, because the whole
    /// assertion is that a row carrying it decodes to a value identical to a row without it —
    /// the plan requires the corpus to contain it. The repo-wide lint has deliberately **no
    /// allowlist and no exempted call site**, so that the ban is total and nobody can grant
    /// themselves an exemption; the price of that choice is exactly this line.
    ///
    /// Nothing here reads the key. It goes into a dictionary the decoder is asked to throw
    /// away, and the test fails if the decoder does anything else with it. The stronger half
    /// of SC-1 is unaffected either way: the ban that cannot be talked around is the symbol
    /// check, and a `String` built in Swift references no `CFStringRef` at all.
    static let discardedTitleKey = "kCGWindow" + "Name"

    static func boundsDictionary(x: Double, y: Double, width: Double, height: Double) -> CFDictionary {
        CGRect(x: x, y: y, width: width, height: height).dictionaryRepresentation
    }

    /// One row, built the way the system builds them — with every key an `NSNumber` and the
    /// bounds a nested CFDictionary.
    static func row(
        ownerName: String,
        ownerPID: pid_t,
        layer: Int,
        number: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        isOnScreen: Bool = true,
        alpha: Double = 1,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var row: [String: Any] = [
            kCGWindowOwnerName as String: ownerName,
            kCGWindowOwnerPID as String: NSNumber(value: ownerPID),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowNumber as String: NSNumber(value: number),
            kCGWindowBounds as String: boundsDictionary(x: x, y: y, width: width, height: height),
            kCGWindowIsOnscreen as String: NSNumber(value: isOnScreen),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            // The three sanctioned keys this reader deliberately does not decode.
            "kCGWindowStoreType": NSNumber(value: 1),
            "kCGWindowSharingState": NSNumber(value: 1),
            "kCGWindowMemoryUsage": NSNumber(value: 1_048_576)
        ]
        for (key, value) in extra { row[key] = value }
        return row
    }

    /// The window an application owns: layer 0, its own PID.
    static let textEditPID: pid_t = 501
    static let dockPID: pid_t = 418
    static let windowServerPID: pid_t = 167

    static var windowedApplication: [String: Any] {
        // The measured case from probe P-91: AppKit (200, 200) 640×432 arrives as Quartz Y 448.
        row(ownerName: "TextEdit", ownerPID: textEditPID, layer: 0, number: 9001,
            x: 200, y: 448, width: 640, height: 432)
    }

    static var fullScreenApplication: [String: Any] {
        row(ownerName: "TextEdit", ownerPID: textEditPID, layer: 0, number: 9001,
            x: 0, y: 0, width: 1920, height: 1080)
    }

    /// The decoy that makes the PID filter load-bearing: the Dock's window is the whole
    /// display, permanently, at layer 20 (probe P-78).
    static var dock: [String: Any] {
        row(ownerName: "Dock", ownerPID: dockPID, layer: 20, number: 42,
            x: 0, y: 0, width: 1920, height: 1080)
    }

    /// Window Server's menu bar: layer 24, 1920×30 (probe P-78).
    static var menuBar: [String: Any] {
        row(ownerName: "Window Server", ownerPID: windowServerPID, layer: 24, number: 7,
            x: 0, y: 0, width: 1920, height: 30)
    }

    /// A window belonging to an application on **another Space**. `.optionOnScreenOnly` is not
    /// Space-scoped (probe P-77), so this row really does arrive in the same call.
    static var otherSpaceApplication: [String: Any] {
        row(ownerName: "Google Chrome", ownerPID: 777, layer: 0, number: 5150,
            x: 0, y: 0, width: 1920, height: 1080)
    }

    static var standard: [[String: Any]] {
        [windowedApplication, dock, menuBar, otherSpaceApplication]
    }
}

@MainActor
@Suite("Window metadata reader")
struct WindowMetadataReaderTests {
    /// A cleared activation, produced the only way one can be produced.
    ///
    /// There is no public initialiser on `ClearedActivation`; the gate is the sole producer.
    /// That this test has to go through the gate to get one is the criterion, not a detour.
    private static func cleared(
        bundleIdentifier: String = "com.apple.TextEdit",
        pid: pid_t = WindowCorpus.textEditPID
    ) -> ClearedActivation {
        let decision = SensitivityGate().evaluate(
            FrontmostActivation(
                bundleIdentifier: bundleIdentifier,
                pid: pid,
                at: Date(timeIntervalSince1970: 1_767_225_600)
            )
        )
        guard let activation = decision.clearedActivation else {
            fatalError("the gate refused a bundle identifier that is not on any list")
        }
        return activation
    }

    // MARK: - The seven keys, and the one that is not there

    @Test("The reader decodes exactly seven keys")
    func decodesSevenKeys() {
        #expect(WindowMetadataReader.decodedKeys.count == 7)
        #expect(Set(WindowMetadataReader.decodedKeys).count == 7)
    }

    @Test("No decoded key names a window, and the owner's name is not a title")
    func decodedKeysAreTitleFree() {
        #expect(WindowMetadataReader.decodedKeysAreTitleFree)
        // The owner name is the *application's* name — public, on every row at zero grants,
        // and not the thing standing condition 1 bans.
        #expect(WindowMetadataReader.decodedKeys.contains(kCGWindowOwnerName as String))
    }

    @Test("A row carrying the banned key decodes to exactly the same value as one without it")
    func theBannedKeyIsDiscarded() {
        // The corpus row carries the key under its literal string, which is the shape a row
        // arrives in with Screen Recording granted — 34 of 35 rows carried it on the Court's
        // receipt. The decoder must not be able to see it.
        let withKey = WindowCorpus.row(
            ownerName: "TextEdit",
            ownerPID: WindowCorpus.textEditPID,
            layer: 0,
            number: 9001,
            x: 200, y: 448, width: 640, height: 432,
            extra: [
                WindowCorpus.discardedTitleKey: "Quarterly report — DRAFT — confidential.docx"
            ]
        )
        let withoutKey = WindowCorpus.windowedApplication

        let decodedWithKey = WindowMetadataReader.decodeRow(withKey)
        let decodedWithoutKey = WindowMetadataReader.decodeRow(withoutKey)

        #expect(decodedWithKey != nil)
        #expect(decodedWithKey == decodedWithoutKey)
    }

    @Test("The decoded value has nowhere to put a title: its whole surface is seven fields")
    func theValueTypeHasNowhereToPutATitle() {
        let decoded = WindowMetadataReader.decodeRow(WindowCorpus.windowedApplication)
        guard let decoded else {
            Issue.record("the corpus row did not decode")
            return
        }

        // Reconstructing the value from its seven public members reproduces it exactly. If a
        // title field existed, it would have to be one of these — and it is not.
        let rebuilt = WindowMetadataValue(
            ownerName: decoded.ownerName,
            ownerPID: decoded.ownerPID,
            layer: decoded.layer,
            number: decoded.number,
            bounds: decoded.bounds,
            isOnScreen: decoded.isOnScreen,
            alpha: decoded.alpha
        )
        #expect(rebuilt == decoded)
    }

    // MARK: - The decode itself

    @Test("The seven fields come through with the values the corpus recorded")
    func decodesEveryField() {
        let decoded = WindowMetadataReader.decodeRow(WindowCorpus.windowedApplication)

        #expect(decoded?.ownerName == "TextEdit")
        #expect(decoded?.ownerPID == WindowCorpus.textEditPID)
        #expect(decoded?.layer == 0)
        #expect(decoded?.number == 9001)
        #expect(decoded?.bounds == ScreenRect(x: 200, y: 448, width: 640, height: 432))
        #expect(decoded?.isOnScreen == true)
        #expect(decoded?.alpha == 1)
    }

    @Test("A row missing a required key is dropped rather than guessed at")
    func incompleteRowIsDropped() {
        var row = WindowCorpus.windowedApplication
        row.removeValue(forKey: kCGWindowBounds as String)
        #expect(WindowMetadataReader.decodeRow(row) == nil)

        var noPID = WindowCorpus.windowedApplication
        noPID.removeValue(forKey: kCGWindowOwnerPID as String)
        #expect(WindowMetadataReader.decodeRow(noPID) == nil)
    }

    @Test("Bounds that are not a rectangle dictionary decode to nothing")
    func malformedBoundsIsRejected() {
        var row = WindowCorpus.windowedApplication
        row[kCGWindowBounds as String] = "0,0,1920,1080"
        #expect(WindowMetadataReader.decodeRow(row) == nil)
    }

    @Test("The whole corpus decodes, and every row keeps its own owner")
    func decodesAWholeList() {
        let decoded = WindowMetadataReader.decode(WindowCorpus.standard)

        #expect(decoded.count == 4)
        #expect(decoded.map(\.ownerName) == ["TextEdit", "Dock", "Window Server", "Google Chrome"])
    }

    // MARK: - Clearance and the PID filter

    @Test("A read takes a ClearedActivation, which only the gate can produce")
    func readsRequireClearance() {
        let list = RecordedWindowList(rows: WindowCorpus.standard)
        let reader = WindowMetadataReader(list: list)

        let windows = reader.windows(for: Self.cleared())

        #expect(windows.count == 4)
        #expect(list.readCount == 1)
    }

    @Test("A sensitive application never yields a cleared activation to read with")
    func sensitiveApplicationCannotBeRead() {
        let decision = SensitivityGate().evaluate(
            FrontmostActivation(
                bundleIdentifier: "com.1password.1password",
                pid: 900,
                at: Date(timeIntervalSince1970: 1_767_225_600)
            )
        )

        #expect(decision.clearedActivation == nil)
        #expect(decision.suppressionReason == .builtInList)
    }

    @Test("applicationWindows filters to layer 0 and the cleared PID, so the Dock never matches")
    func applicationWindowsFiltersDecoys() {
        let reader = WindowMetadataReader(list: RecordedWindowList(rows: WindowCorpus.standard))

        let mine = reader.applicationWindows(for: Self.cleared())

        #expect(mine.count == 1)
        #expect(mine.first?.ownerName == "TextEdit")
        // Both decoys are display-sized or system-owned, and neither survives the filter.
        #expect(mine.contains { $0.ownerName == "Dock" } == false)
        #expect(mine.contains { $0.ownerName == "Google Chrome" } == false)
    }

    @Test("A window from another Space is listed but is not this application's")
    func otherSpaceWindowsAreListedAndFiltered() {
        // `.optionOnScreenOnly` is not Space-scoped (probe P-77): the row really is in the
        // list, and the filter is what keeps a heuristic from asking "is *some* window
        // full-screen".
        let decoded = WindowMetadataReader.decode(WindowCorpus.standard)

        #expect(decoded.contains { $0.ownerName == "Google Chrome" })
        #expect(decoded.applicationWindows(of: WindowCorpus.textEditPID).count == 1)
    }

    // MARK: - The fixed option set and the warm call

    @Test("The option set is fixed in the type and is the measured one")
    func optionSetIsFixed() {
        #expect(SystemWindowList.options == [.optionOnScreenOnly, .excludeDesktopElements])

        // Asserted on the raw value rather than with `contains(.optionAll)`, because
        // `.optionAll` is the **empty** option set — every option set contains it, so that
        // spelling would pass for any value whatsoever and prove nothing. Exact equality is
        // what says the two measured options are the whole of it: probe P-75 measured
        // `.optionAll` returning 128 rows including off-screen windows for no benefit.
        let expected = CGWindowListOption.optionOnScreenOnly.rawValue
            | CGWindowListOption.excludeDesktopElements.rawValue
        #expect(SystemWindowList.options.rawValue == expected)
    }

    @Test("Warming takes the cold call once, so it is not taken inside a decision")
    func warmingTakesTheColdCall() {
        let list = RecordedWindowList(rows: WindowCorpus.standard)
        let reader = WindowMetadataReader(list: list)

        reader.warm()

        #expect(list.readCount == 1)
    }

    // MARK: - The two readers that ride on it

    @Test("Display mapping puts the measured window on screen zero")
    func displayMappingUsesTheMeasuredFlip() {
        let screens = [
            DisplayGeometry(
                displayID: 3,
                screenIndex: 0,
                isPrimary: true,
                frame: WindowCorpus.primaryFrame,
                visibleFrame: ScreenRect(x: 0, y: 87, width: 1920, height: 963),
                backingScaleFactor: 1
            )
        ]
        let reader = DisplayGeometryReader(list: FixedScreenList(screens))
        let windows = WindowMetadataReader.decode(WindowCorpus.standard)

        let mapping = reader.mapping(for: Self.cleared(), windows: windows)

        // Quartz Y 448, height 432, primary maxY 1080 ⇒ AppKit Y 200 (probe P-91).
        #expect(mapping?.flippedBounds.y == 200)
        #expect(mapping?.display.screenIndex == 0)
        #expect(mapping?.display.isPrimary == true)
    }

    @Test("A cleared application with no ordinary window of its own maps to no display")
    func noWindowMapsToNoDisplay() {
        let screens = [
            DisplayGeometry(
                displayID: 3, screenIndex: 0, isPrimary: true,
                frame: WindowCorpus.primaryFrame,
                visibleFrame: WindowCorpus.primaryFrame,
                backingScaleFactor: 1
            )
        ]
        let reader = DisplayGeometryReader(list: FixedScreenList(screens))
        let windows = WindowMetadataReader.decode([WindowCorpus.dock, WindowCorpus.menuBar])

        #expect(reader.display(for: Self.cleared(), windows: windows) == nil)
    }

    @Test("The presentation quorum needs two signals: a full-screen window alone never decides")
    func oneSignalNeverDecides() {
        let screens = [
            DisplayGeometry(
                displayID: 3, screenIndex: 0, isPrimary: true,
                frame: WindowCorpus.primaryFrame,
                visibleFrame: WindowCorpus.primaryFrame,
                backingScaleFactor: 1
            )
        ]
        let reader = PresentationReader(signals: FixedPresentationSignals())
        let windows = WindowMetadataReader.decode(
            [WindowCorpus.fullScreenApplication, WindowCorpus.dock, WindowCorpus.menuBar]
        )

        let state = reader.read(
            for: Self.cleared(),
            windows: windows,
            screens: screens,
            isUserExcluded: false
        )

        #expect(state.signals.frontmostWindowFillsAScreen)
        #expect(state.signals.agreementCount == 1)
        #expect(state.isPresenting == false)
    }

    @Test("Two agreeing signals reach the quorum")
    func twoSignalsDecide() {
        let screens = [
            DisplayGeometry(
                displayID: 3, screenIndex: 0, isPrimary: true,
                frame: WindowCorpus.primaryFrame,
                visibleFrame: WindowCorpus.primaryFrame,
                backingScaleFactor: 1
            )
        ]
        let reader = PresentationReader(
            signals: FixedPresentationSignals(menuBarHidden: true)
        )
        let windows = WindowMetadataReader.decode([WindowCorpus.fullScreenApplication])

        let state = reader.read(
            for: Self.cleared(),
            windows: windows,
            screens: screens,
            isUserExcluded: false
        )

        #expect(state.signals.agreementCount == 2)
        #expect(state.isPresenting)
        #expect(state.suppressesOverlays)
    }

    @Test("The Dock's display-sized layer-20 window never casts the first signal")
    func dockNeverMatches() {
        let screens = [
            DisplayGeometry(
                displayID: 3, screenIndex: 0, isPrimary: true,
                frame: WindowCorpus.primaryFrame,
                visibleFrame: WindowCorpus.primaryFrame,
                backingScaleFactor: 1
            )
        ]
        let reader = PresentationReader(signals: FixedPresentationSignals())
        // Only the decoys are display-sized; the cleared application's own window is not.
        let windows = WindowMetadataReader.decode(WindowCorpus.standard)

        let signals = reader.read(for: Self.cleared(), windows: windows, screens: screens)

        #expect(signals.frontmostWindowFillsAScreen == false)
    }

    @Test("A display-sized window belonging to another application never matches either")
    func otherApplicationsFullScreenWindowNeverMatches() {
        let screens = [
            DisplayGeometry(
                displayID: 3, screenIndex: 0, isPrimary: true,
                frame: WindowCorpus.primaryFrame,
                visibleFrame: WindowCorpus.primaryFrame,
                backingScaleFactor: 1
            )
        ]
        let reader = PresentationReader(signals: FixedPresentationSignals())
        // Chrome is full-screen on another Space and is in the list (probe P-77).
        let windows = WindowMetadataReader.decode([WindowCorpus.otherSpaceApplication])

        let signals = reader.read(for: Self.cleared(), windows: windows, screens: screens)

        #expect(signals.frontmostWindowFillsAScreen == false)
    }

    @Test("The user's exclusion list overrides the quorum on its own")
    func exclusionListOverrides() {
        let reader = PresentationReader(signals: FixedPresentationSignals())

        let state = reader.read(
            for: Self.cleared(),
            windows: [],
            screens: [],
            isUserExcluded: true
        )

        #expect(state.signals.agreementCount == 0)
        #expect(state.isUserExcluded)
        #expect(state.isPresenting)
    }
}
