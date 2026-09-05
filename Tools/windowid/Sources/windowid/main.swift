// windowid — a test driver for the live evidence lane.
//
//   windowid <owner name>   print "<windowNumber> <x> <y> <w> <h>" for each layer-0 window
//                           belonging to that application; exit 1 if it has none
//   windowid <owner name> --include-panels
//                           the same, for windows at *every* layer — panels included
//   windowid --grants       report whether this process can drive the live lane at all
//   windowid --window-owners
//                           print "<windowNumber>\t<ownerName>" for EVERY on-screen window, at
//                           every layer. The authorisation-surface baseline (focus-p3dl)
//
// ## Why `--include-panels` exists
//
// Layer 0 is the right default: it is what excludes menu-bar extras, tooltips and the Dock,
// so what comes back is the set a person would call "the app's windows". But the quick-capture
// panel is an `NSPanel` at `.floating`, which is **layer 3** — measured on this machine:
//
//     owner=Focus Sentinel layer=3 number=4629 bounds=680,241,560,121   ← the panel
//     owner=Focus Sentinel layer=0 number=4634 bounds=495,58,900,704    ← the cockpit
//
// A driver asking for the panel and being handed a layer-0-only list gets the cockpit, and if
// it falls back to "the front-most entry" it captures the cockpit and files it as a picture of
// the panel. That is exactly how `capture-panel.png` came to be a 900×704 shot of the main
// window. The tool now has an answer for the question the lane was really asking, so the
// driver can require a bounds match instead of guessing.
//
// ## Standing condition 1
//
// SC-1 bans `kCGWindowName` as a title source anywhere in the codebase. This tool asks
// `CGWindowListCopyWindowInfo` for exactly four keys — `kCGWindowOwnerName`,
// `kCGWindowLayer`, `kCGWindowNumber` and `kCGWindowBounds` — and never requests the window
// *name*. That distinction is the whole reason the tool is allowed to exist: owner, layer,
// number and bounds have never been permission-gated, while window names have required
// Screen Recording since 10.15, which is precisely why reading them would be both a privacy
// violation and a TCC dependency.
//
// ## Why this is a separate executable rather than app code
//
// `screencapture -l <id>` needs a window id, and the only public way to get one for another
// process is the window list. Putting that call inside the app would put a
// Screen-Recording-adjacent API in the shipping binary for a reason that exists only in the
// test lane. It lives here instead, outside the app's package graph, and the app never
// grows a capability it does not need.

import ApplicationServices
import CoreGraphics
import Foundation

/// One on-screen window, described only by what is readable without any permission.
struct WindowRecord {
    let number: Int
    let bounds: CGRect

    var line: String {
        let x = Int(bounds.origin.x.rounded())
        let y = Int(bounds.origin.y.rounded())
        let w = Int(bounds.size.width.rounded())
        let h = Int(bounds.size.height.rounded())
        return "\(number) \(x) \(y) \(w) \(h)"
    }
}

/// The form of an owner name that two spellings of the same application agree on.
///
/// `kCGWindowOwnerName` is the *display* name — `Focus Sentinel`, with a space — while the
/// product, the target, the scheme and the bundle executable are all `FocusSentinel`. Asking
/// for the name you build with and being told there is no such window is a trap worth
/// closing: matching is exact first, and falls back to this normalisation, which drops
/// whitespace and case so `FocusSentinel`, `focus sentinel` and `Focus Sentinel` are one key.
func normalized(_ name: String) -> String {
    name.lowercased().filter { !$0.isWhitespace }
}

/// Every on-screen window owned by `ownerName`, in front-to-back order.
///
/// By default only layer 0 — which is what excludes menu-bar extras, tooltips, the Dock and
/// the app's own panels, so what comes back is the set of windows a person would call "the
/// app's windows". With `includingPanels` the layer filter is dropped entirely, because the
/// quick-capture panel is a floating `NSPanel` and therefore lives at layer 3.
///
/// Returns the records and the owner name they were actually matched under, so a caller can
/// say which application it found when the match was not the literal argument.
func windows(
    ownedBy ownerName: String,
    includingPanels: Bool = false
) -> (records: [WindowRecord], matchedOwner: String) {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard
        let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else {
        return ([], ownerName)
    }

    let ownerKey = kCGWindowOwnerName as String
    let layerKey = kCGWindowLayer as String
    let numberKey = kCGWindowNumber as String
    let boundsKey = kCGWindowBounds as String

    /// Every candidate window, paired with its owner, so both matching passes read the same
    /// list rather than copying the window list twice and risking two different worlds.
    let candidates: [(owner: String, record: WindowRecord)] = raw.compactMap { entry in
        guard
            let owner = entry[ownerKey] as? String,
            let layer = entry[layerKey] as? Int, includingPanels || layer == 0,
            let number = entry[numberKey] as? Int,
            let boundsDictionary = entry[boundsKey],
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary as! CFDictionary)
        else {
            return nil
        }
        // A zero-sized window is an artefact of a window being torn down while the list was
        // being copied; capturing it would produce an empty PNG.
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        return (owner, WindowRecord(number: number, bounds: bounds))
    }

    let exact = candidates.filter { $0.owner == ownerName }
    if !exact.isEmpty {
        return (exact.map(\.record), ownerName)
    }

    let wanted = normalized(ownerName)
    let loose = candidates.filter { normalized($0.owner) == wanted }
    guard let first = loose.first else { return ([], ownerName) }
    return (loose.map(\.record), first.owner)
}

/// Every on-screen window there is, as `<number>\t<owner>`, at every layer.
///
/// **This is the authorisation-surface baseline** (focus-p3dl). The self-check's scan asks
/// whether a permission dialog is on the screen *while the app runs*, and until this round it
/// answered "yes" for a dialog that had been sitting there since before the app was launched and
/// belonged to somebody else entirely. The reading is only about the app if it is a **delta**, so
/// the launching script takes this list first and the app subtracts it.
///
/// Two decisions, both load-bearing:
///
/// * **Every layer.** A macOS permission dialog is not an ordinary layer-0 window — measured on
///   this machine, `UserNotificationCenter`'s alert sits above it — so the layer filter the rest
///   of this tool applies would hide exactly the windows the baseline exists to record.
/// * **Every owner, not the six suspect names.** The suspect list lives in
///   `SelfCheck.authorisationSurfaceOwners` and nowhere else. A copy of it here would be a second
///   place to change, and a baseline filtered by a stale copy would silently stop covering a
///   name the app had started watching for.
///
/// The window *number* is what makes the subtraction meaningful: an owner alone would let a
/// second dialog from the same process hide behind the first one's row.
func printEveryWindowOwner() -> Int32 {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard
        let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else {
        FileHandle.standardError.write(
            Data("windowid: the window server named nobody at all\n".utf8)
        )
        return 1
    }
    let ownerKey = kCGWindowOwnerName as String
    let numberKey = kCGWindowNumber as String
    var printed = 0
    for entry in raw {
        guard
            let owner = entry[ownerKey] as? String,
            let number = entry[numberKey] as? Int
        else {
            continue
        }
        print("\(number)\t\(owner)")
        printed += 1
    }
    // An empty list is NOT a baseline of "nothing was on screen": it is a reading nobody took,
    // and the caller has to be able to tell the two apart.
    return printed > 0 ? 0 : 1
}

/// Whether this process can drive the live lane.
///
/// Both are *preflight* calls: neither prompts, and neither is ever followed by its
/// requesting counterpart. A missing grant is a reason for the live lane to skip and exit
/// zero, never a reason to put a permission dialog in front of somebody.
func reportGrants() -> Int32 {
    let accessibility = AXIsProcessTrusted()
    let screenRecording = CGPreflightScreenCaptureAccess()

    print("accessibility=\(accessibility ? "yes" : "no")")
    print("screen-recording=\(screenRecording ? "yes" : "no")")

    return (accessibility && screenRecording) ? 0 : 1
}

func usage() -> Never {
    FileHandle.standardError.write(
        Data(
            """
            usage: windowid <owner name> [--include-panels]
                   windowid --grants
                   windowid --window-owners

            Prints "<windowNumber> <x> <y> <w> <h>" for each on-screen window owned by the
            named application, front to back. Window *names* are never requested (standing
            condition 1).

            Only layer 0 is listed by default — ordinary windows, no menu-bar extras and no
            panels. Pass --include-panels to list every layer: the quick-capture panel is a
            floating NSPanel at layer 3, so a driver looking for it must ask for it.

            The owner name is the application's display name — "Focus Sentinel". An exact
            match is tried first; failing that, whitespace and case are ignored, so
            "FocusSentinel" finds the same windows and says so on stderr.

            --window-owners prints "<windowNumber>\t<ownerName>" for every on-screen window at
            every layer, and exits 1 if there were none. That is the authorisation-surface
            baseline the self-check subtracts, so a permission dialog that was already on the
            screen before the app launched is not read as one the app put there.

            """.utf8
        )
    )
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let first = arguments.first, arguments.count <= 2 else { usage() }

let includePanels = arguments.dropFirst().contains("--include-panels")
guard arguments.count == 1 || includePanels else { usage() }

switch first {
case "--grants":
    guard arguments.count == 1 else { usage() }
    exit(reportGrants())
case "--window-owners":
    guard arguments.count == 1 else { usage() }
    exit(printEveryWindowOwner())
case "-h", "--help":
    usage()
default:
    let (found, matchedOwner) = windows(ownedBy: first, includingPanels: includePanels)
    guard !found.isEmpty else {
        let scope = includePanels ? "on-screen window" : "layer-0 on-screen window"
        FileHandle.standardError.write(
            Data("windowid: no \(scope) owned by \"\(first)\"\n".utf8)
        )
        exit(1)
    }
    if matchedOwner != first {
        FileHandle.standardError.write(
            Data("windowid: matched owner \"\(matchedOwner)\" for \"\(first)\"\n".utf8)
        )
    }
    for record in found {
        print(record.line)
    }
    exit(0)
}
