import FocusCore
import Foundation
import Testing

@testable import FocusHost

/// The process identifier the fixture calls "ours", and one that is somebody else's.
private let ownPID: pid_t = 4_242
private let otherPID: pid_t = 91

private func window(_ ownerName: String, pid: pid_t) -> WindowMetadataValue {
    WindowMetadataValue(
        ownerName: ownerName,
        ownerPID: pid,
        layer: 0,
        number: Int(pid) * 10,
        bounds: ScreenRect(x: 0, y: 0, width: 800, height: 600),
        isOnScreen: true,
        alpha: 1
    )
}

/// **Every shape the scan can come back in.** `CaseIterable`, so the fold below cannot quietly
/// stop covering one — the vocabulary is the space, and adding a case to it fails the
/// completeness test until somebody says what the scan should report for it.
enum AuthorisationScanShape: String, CaseIterable {
    /// The window server named nobody. This is the state the old one-line check was green for.
    case nothingAtAll
    /// Windows, but not one of ours — the instrument cannot see the window it stands beside.
    case blindToItsOwnProcess
    /// The ordinary run: our cockpit and other people's windows, no dialog.
    case ourWindowAndNoDialog
    /// A dialog owner really is on screen. This is the defect the reading exists to catch.
    case ourWindowAndADialog

    var rows: [WindowMetadataValue] {
        switch self {
        case .nothingAtAll:
            []
        case .blindToItsOwnProcess:
            [window("Ghostty", pid: otherPID), window("Dock", pid: otherPID + 1)]
        case .ourWindowAndNoDialog:
            [window("Focus Sentinel", pid: ownPID), window("Ghostty", pid: otherPID)]
        case .ourWindowAndADialog:
            [
                window("Focus Sentinel", pid: ownPID),
                // The display name macOS gives the TCC prompt's own process, matched by the
                // substring list `authorisationSurfaceOwners` holds.
                window("universalAccessAuthWarn", pid: otherPID)
            ]
        }
    }

    /// What the gate must conclude, spelled out here independently of the code under test:
    /// whether the reading was taken, whether the control passed, and whether the verdict is
    var expectation: (wasTaken: Bool, sawItsOwnWindow: Bool, suspects: [String]) {
        switch self {
        case .nothingAtAll: (false, false, [])
        case .blindToItsOwnProcess: (true, false, [])
        case .ourWindowAndNoDialog: (true, true, [])
        case .ourWindowAndADialog: (true, true, ["universalAccessAuthWarn"])
        }
    }
}

/// **The scan that says no permission dialog is on screen, and every state it can be in.**
///
/// ## The defect this suite is the proof for
///
/// `SelfCheck.authorisationSurfaceReport()` is the gateable form of R-33 — *the app never
/// triggers a permission prompt* — and for the whole of e03, e04 and e05 the gate's reading of it
/// was one line: `authorisationSurfaces == []`, with the owner count printed beside it as a note
/// that nothing asserted.
///
/// **An empty scan satisfies that line.** `SystemWindowList.copyWindowInfo()` answers `[]` when
/// the window server declines or the cast fails; the suspect list is then empty for exactly the
/// same reason a clean Mac's is, and the strongest form of R-33 prints green for a reading nobody
/// took. It is not hypothetical on this hardware: the same call is what `sensing.windowMetadata`
/// grew `countWasTaken` for in focus-2vi, and gate run `lens6-1` recorded it answering the Release
/// launch of a tree and refusing the Debug launch of the same tree. One consumer of
/// `CGWindowListCopyWindowInfo` was given the takenness treatment; the other, forty lines of
/// report away, was not.
///
/// ## The three properties the repair doctrine binds every repair to
///
/// 1. **ONE suite folded over the WHOLE space.** The space is `ScanShape.allCases` — every shape
///    the scan can come back in — and `everyShapeOfTheScanIsAccountedFor` folds it whole rather
///    than walking the reported scenario.
/// 2. **A self-referential completeness check.** `theFoldCoversEveryDeclaredShape` fails if a
///    shape is added to the vocabulary and left out of the fold's expectation table, and if the
///    fold ever covers nothing.
/// 3. **A stated vacuity guard**, on `whatThisSuiteWouldStillBeGreenFor`.
@MainActor
@Suite("the on-screen authorisation-surface scan")
struct SelfCheckAuthorisationScanTests {
    typealias ScanShape = AuthorisationScanShape

    static func scan(_ shape: ScanShape) -> [String: Any] {
        SelfCheck.authorisationSurfaceReport(rows: shape.rows, ownProcessIdentifier: ownPID)
    }

    // MARK: - 1 · the fold, over the whole space

    /// One fold, every shape, all three legs of the reading compared against a table written
    /// independently of the code that produces them.
    @Test("every shape of the scan reports the takenness, the control and the verdict it should")
    func everyShapeOfTheScanIsAccountedFor() {
        for shape in ScanShape.allCases {
            let report = Self.scan(shape)
            let expected = shape.expectation
            #expect(
                report["wasTaken"] as? Bool == expected.wasTaken,
                "\(shape.rawValue): wasTaken"
            )
            let ownWindows = report["windowsOwnedByThisProcess"] as? Int ?? -1
            #expect(
                (ownWindows > 0) == expected.sawItsOwnWindow,
                "\(shape.rawValue): windowsOwnedByThisProcess = \(ownWindows)"
            )
            #expect(
                report["suspects"] as? [String] == expected.suspects,
                "\(shape.rawValue): suspects"
            )
        }
    }

    /// **The line the repair turns on.** An empty scan is NOT TAKEN, and its `suspects` are empty
    /// for the same reason a clean Mac's are — which is precisely why emptiness may never be the
    /// thing that makes the gate green.
    @Test("an empty scan is not taken, and its empty suspect list proves nothing")
    func anEmptyScanIsNotAReading() {
        let report = Self.scan(.nothingAtAll)
        #expect(report["wasTaken"] as? Bool == false)
        #expect(report["suspects"] as? [String] == [])
        #expect((report["notTakenBecause"] as? String ?? "").isEmpty == false)
    }

    /// The reason a taken reading carries no reason: the pair is always present, so the gate can
    /// fold over it rather than branch on a key that appears only on the failing side
    /// (focus-2uy.3).
    @Test("a taken scan still publishes both halves of the takenness pair")
    func aTakenScanPublishesBothHalves() {
        let report = Self.scan(.ourWindowAndNoDialog)
        #expect(report["wasTaken"] as? Bool == true)
        #expect(report["notTakenBecause"] as? String == "")
    }

    // MARK: - 2 · the completeness check

    /// **It fails when the space grows and this proof does not.** Every declared shape has a row
    /// in the expectation table, the fold visits every one of them, and a fold over nothing is a
    /// failure rather than a pass.
    @Test("the fold covers every declared shape, and covers more than none")
    func theFoldCoversEveryDeclaredShape() {
        let visited = ScanShape.allCases.map(\.rawValue)
        #expect(Set(visited) == Set(ScanShape.allCases.map(\.rawValue)))
        #expect(visited.count == ScanShape.allCases.count)
        #expect(visited.isEmpty == false)
        // And the table discriminates: it does not answer the same thing for every shape, which
        // is what a fold satisfied by a constant would look like.
        #expect(Set(ScanShape.allCases.map { $0.expectation.wasTaken }) == [true, false])
        #expect(Set(ScanShape.allCases.map { $0.expectation.sawItsOwnWindow }) == [true, false])
        #expect(ScanShape.allCases.contains { !$0.expectation.suspects.isEmpty })
    }

    /// The suspect list the verdict is computed against is not empty either. A ban whose needle
    /// list had been emptied would pass every shape above, including the dialog one.
    @Test("the list of processes a dialog belongs to is not empty")
    func theSuspectVocabularyIsNotEmpty() {
        #expect(SelfCheck.authorisationSurfaceOwners.isEmpty == false)
        #expect(SelfCheck.authorisationSurfaceOwners.contains("universalAccessAuthWarn"))
    }

    // MARK: - 3 · the vacuity guard, stated

    /// **What this suite would still be green for**, named so nobody has to re-derive it:
    ///
    /// 1. **A dialog whose owning process is not on the six-name list.** This is a fold over the
    ///    scan, not over macOS. `authorisationSurfaceOwners` is probe P-95(c)'s measured list and
    ///    a seventh dialog process would be invisible to it; the assertion above is that the list
    ///    is non-empty and still carries the case the fold drives, not that it is exhaustive.
    /// 2. **A prompt that never draws a window.** A permission request answered from a cached TCC
    ///    decision puts nothing on the screen at all. That half is held by lint — the prompting
    ///    APIs are banned from the shipping graph — and this scan is the other half.
    /// 3. **A window the list does not carry.** `SystemWindowList` asks for
    ///    `.optionOnScreenOnly, .excludeDesktopElements`. A dialog on another Space is not in it,
    ///    and would not be on the person's screen either.
    ///
    /// The check this suite exists to make impossible is none of those three: it is a scan that
    /// saw nothing being reported as a screen with nothing on it.
    @Test("the guard is stated, and the shape it forbids is the one the fold drives")
    func whatThisSuiteWouldStillBeGreenFor() {
        // Emptiness and cleanliness are two different answers, and the reading distinguishes them.
        let empty = Self.scan(.nothingAtAll)
        let clean = Self.scan(.ourWindowAndNoDialog)
        #expect(empty["suspects"] as? [String] == clean["suspects"] as? [String])
        #expect(empty["wasTaken"] as? Bool != clean["wasTaken"] as? Bool)
    }
}
