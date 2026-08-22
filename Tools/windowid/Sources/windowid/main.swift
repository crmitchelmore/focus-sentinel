// windowid — a test driver for the live evidence lane.
//
//   windowid <owner name>   print "<windowNumber> <x> <y> <w> <h>" for each layer-0 window
//                           belonging to that application; exit 1 if it has none
//   windowid --grants       report whether this process can drive the live lane at all
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

/// Every layer-0 (ordinary, non-panel) on-screen window owned by `ownerName`.
///
/// Layer 0 is what excludes menu-bar extras, tooltips, the Dock and the app's own panels, so
/// what comes back is the set of windows a person would call "the app's windows".
///
/// Returns the records and the owner name they were actually matched under, so a caller can
/// say which application it found when the match was not the literal argument.
func windows(ownedBy ownerName: String) -> (records: [WindowRecord], matchedOwner: String) {
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
            let layer = entry[layerKey] as? Int, layer == 0,
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
            usage: windowid <owner name>
                   windowid --grants

            Prints "<windowNumber> <x> <y> <w> <h>" for each layer-0 on-screen window owned by
            the named application. Window *names* are never requested (standing condition 1).

            The owner name is the application's display name — "Focus Sentinel". An exact
            match is tried first; failing that, whitespace and case are ignored, so
            "FocusSentinel" finds the same windows and says so on stderr.

            """.utf8
        )
    )
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let first = arguments.first, arguments.count == 1 else { usage() }

switch first {
case "--grants":
    exit(reportGrants())
case "-h", "--help":
    usage()
default:
    let (found, matchedOwner) = windows(ownedBy: first)
    guard !found.isEmpty else {
        FileHandle.standardError.write(
            Data("windowid: no layer-0 on-screen window owned by \"\(first)\"\n".utf8)
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
