import FocusCore
import Foundation
import Testing

@testable import FocusHost

/// The process identifier the fixture calls "ours", and one that is somebody else's.
private let ownPID: pid_t = 4_242
private let otherPID: pid_t = 91
/// The window number of a dialog that was on the screen before the app launched, and of one that
/// arrived while it ran. Two numbers, one owner — which is the whole point of focus-p3dl.
private let alreadyThereWindow = 282_862
private let arrivedWindow = 282_999

private func window(_ ownerName: String, pid: pid_t, number: Int? = nil) -> WindowMetadataValue {
    WindowMetadataValue(
        ownerName: ownerName,
        ownerPID: pid,
        layer: 0,
        number: number ?? Int(pid) * 10,
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
    /// **focus-p3dl.** The dialog was on the screen BEFORE the app launched — somebody else's
    /// tool asking somebody else's question — and the baseline says so. It is reported as
    /// pre-existing and the verdict is clean.
    case aDialogThatWasAlreadyThere
    /// **focus-p3dl, and the reason the subtraction is by window NUMBER.** One dialog from
    /// before, and a second one from the SAME process that arrived while the app ran. An
    /// owner-level baseline would excuse both; this one excuses exactly the first.
    case aSecondDialogFromTheSameProcess
    /// A dialog arrived, and the baseline could not be read at all. Nothing is subtracted, which
    /// is the behaviour this reading has always had — and `baselineWasTaken` says so.
    case aDialogAndNoBaselineAtAll

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
        case .aDialogThatWasAlreadyThere, .aDialogAndNoBaselineAtAll:
            [
                window("Focus Sentinel", pid: ownPID),
                window("UserNotificationCenter", pid: otherPID, number: alreadyThereWindow)
            ]
        case .aSecondDialogFromTheSameProcess:
            [
                window("Focus Sentinel", pid: ownPID),
                window("UserNotificationCenter", pid: otherPID, number: alreadyThereWindow),
                window("UserNotificationCenter", pid: otherPID, number: arrivedWindow)
            ]
        }
    }

    /// The baseline this shape is scanned against — what was on the screen before the app
    /// launched. NOT TAKEN for the shapes that predate focus-p3dl: no baseline, no subtraction,
    /// which is exactly the reading the gate had before this round.
    var baseline: SelfCheck.AuthorisationSurfaceBaseline {
        switch self {
        case .aDialogThatWasAlreadyThere, .aSecondDialogFromTheSameProcess:
            SelfCheck.AuthorisationSurfaceBaseline.parse(
                "\(alreadyThereWindow)\tUserNotificationCenter\n999\tDock\n",
                from: "(fixture)"
            )
        default:
            .notTaken("(fixture) no baseline was supplied")
        }
    }

    /// What the gate must conclude, spelled out here independently of the code under test:
    /// whether the reading was taken, whether the control passed, and whether the verdict is
    var expectation: (
        wasTaken: Bool,
        sawItsOwnWindow: Bool,
        suspects: [String],
        baselineWasTaken: Bool,
        preexistingWindows: Int
    ) {
        switch self {
        case .nothingAtAll: (false, false, [], false, 0)
        case .blindToItsOwnProcess: (true, false, [], false, 0)
        case .ourWindowAndNoDialog: (true, true, [], false, 0)
        case .ourWindowAndADialog: (true, true, ["universalAccessAuthWarn"], false, 0)
        // Already there before the app was: excused by name, and the verdict is clean.
        case .aDialogThatWasAlreadyThere: (true, true, [], true, 1)
        // One of the two was already there. The other arrived, and it is not excused by its
        // twin's row in the baseline.
        case .aSecondDialogFromTheSameProcess: (true, true, ["UserNotificationCenter"], true, 1)
        // No baseline is no subtraction — the pre-round reading, and it fails.
        case .aDialogAndNoBaselineAtAll: (true, true, ["UserNotificationCenter"], false, 0)
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
        SelfCheck.authorisationSurfaceReport(
            rows: shape.rows,
            ownProcessIdentifier: ownPID,
            baseline: shape.baseline
        )
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
            #expect(
                report["baselineWasTaken"] as? Bool == expected.baselineWasTaken,
                "\(shape.rawValue): baselineWasTaken"
            )
            #expect(
                report["preexistingAuthorisationSurfaceWindows"] as? Int
                    == expected.preexistingWindows,
                "\(shape.rawValue): preexistingAuthorisationSurfaceWindows"
            )
            // The arithmetic, per shape: everything the scan saw is either excused or accused.
            let seen = report["suspectWindowsOnScreen"] as? Int ?? -1
            let excused = report["preexistingAuthorisationSurfaceWindows"] as? Int ?? -1
            #expect(seen >= excused, "\(shape.rawValue): suspectWindowsOnScreen")
        }
    }

    // MARK: - 1a · the delta itself (focus-p3dl)

    /// **The line this round turns on.** A dialog that was on the screen before the app launched
    /// is reported as pre-existing — owner and count — and is not the app's fault.
    @Test("a dialog that was already on screen is excused, by owner and by count")
    func aPreexistingDialogIsNotTheApps() {
        let report = Self.scan(.aDialogThatWasAlreadyThere)
        #expect(report["suspects"] as? [String] == [])
        #expect(
            report["preexistingAuthorisationSurfaceOwners"] as? [String]
                == ["UserNotificationCenter"]
        )
        #expect(report["preexistingAuthorisationSurfaceWindows"] as? Int == 1)
        #expect(
            report["preexistingAuthorisationSurfaces"] as? [String]
                == ["UserNotificationCenter #\(alreadyThereWindow)"]
        )
        #expect(report["suspectWindowsOnScreen"] as? Int == 1)
    }

    /// **And the excuse does not generalise from the owner to the process.** A second dialog from
    /// the same process, with a number the baseline never saw, is the app's to answer for. This
    /// is why the subtraction is by window number: an owner-level baseline reports `[]` here.
    @Test("a second dialog from the same process is not excused by the first")
    func theExcuseIsPerWindowRatherThanPerOwner() {
        let report = Self.scan(.aSecondDialogFromTheSameProcess)
        #expect(report["suspects"] as? [String] == ["UserNotificationCenter"])
        #expect(report["preexistingAuthorisationSurfaceWindows"] as? Int == 1)
        #expect(report["suspectWindowsOnScreen"] as? Int == 2)
    }

    /// **No baseline is no subtraction**, and it says so rather than reporting a clean delta it
    /// never computed. A run with the variable unset gets the reading the gate had before this
    /// round: every dialog on screen is a finding.
    @Test("a scan with no baseline subtracts nothing, and publishes that it took none")
    func noBaselineSubtractsNothing() {
        let report = Self.scan(.aDialogAndNoBaselineAtAll)
        #expect(report["baselineWasTaken"] as? Bool == false)
        #expect((report["baselineNotTakenBecause"] as? String ?? "").isEmpty == false)
        #expect(report["suspects"] as? [String] == ["UserNotificationCenter"])
        #expect(report["preexistingAuthorisationSurfaces"] as? [String] == [])
    }

    /// The baseline is parsed from what `Tools/windowid --window-owners` really writes, and a
    /// file nobody could read is NOT TAKEN rather than an empty baseline.
    @Test("the baseline reads windowid's own output, and an unreadable one is not taken")
    func theBaselineParsesWhatTheToolWrites() {
        let parsed = SelfCheck.AuthorisationSurfaceBaseline.parse(
            "241272\tControl Centre\n282862\tUserNotificationCenter\n",
            from: "(fixture)"
        )
        #expect(parsed.wasTaken)
        #expect(parsed.windowCount == 2)
        #expect(parsed.contains(windowNumber: 282_862))
        #expect(parsed.contains(windowNumber: 1) == false)

        let empty = SelfCheck.AuthorisationSurfaceBaseline.parse("", from: "(fixture)")
        #expect(empty.wasTaken == false)
        #expect(empty.notTakenBecause.isEmpty == false)
        // A baseline nobody took excuses nothing — including a number it happens to hold.
        #expect(empty.contains(windowNumber: 282_862) == false)

        let missing = SelfCheck.AuthorisationSurfaceBaseline.fromEnvironment([:])
        #expect(missing.wasTaken == false)
        #expect(missing.notTakenBecause.contains("FOCUS_AUTHORISATION_BASELINE"))
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
        // And the baseline half discriminates too: a table that answered "not taken" everywhere
        // would pass every row above while proving nothing about the subtraction.
        #expect(Set(ScanShape.allCases.map { $0.expectation.baselineWasTaken }) == [true, false])
        #expect(ScanShape.allCases.contains { $0.expectation.preexistingWindows > 0 })
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
