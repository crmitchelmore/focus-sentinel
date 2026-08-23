import CoreGraphics
import FocusCore
import Foundation

/// The seam between this app and `CGWindowListCopyWindowInfo`.
///
/// It exists so that the decoder is testable against a **recorded corpus** — including rows
/// that carry the key this programme will never read — without a window server, and so that
/// the untyped `[String: Any]` the system hands back has exactly one place it can be seen.
///
/// `@MainActor` because the dictionaries are not `Sendable` and must not be moved between
/// isolation domains; the decode happens on the same actor that asked for them, and what
/// leaves this file is a typed value with no dictionary in it.
@MainActor
public protocol WindowListReading: AnyObject {
    /// The on-screen window list, as the system returns it.
    func copyWindowInfo() -> [[String: Any]]
}

/// The production window list.
///
/// The option set is **fixed in the type** and is `[.optionOnScreenOnly,
/// .excludeDesktopElements]`. `.optionAll` is deliberately not used: it returned 128 rows
/// including off-screen windows for no benefit, and the two extra names it surfaced belonged
/// to Window Server rather than to any application (probe P-75).
@MainActor
public final class SystemWindowList: WindowListReading {
    public init() {}

    /// Fixed. There is no initialiser parameter and no property that could widen it.
    public static let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

    public func copyWindowInfo() -> [[String: Any]] {
        CGWindowListCopyWindowInfo(Self.options, kCGNullWindowID) as? [[String: Any]] ?? []
    }
}

/// A window list pinned to a recorded corpus.
public final class RecordedWindowList: WindowListReading {
    private let rows: [[String: Any]]
    public private(set) var readCount = 0

    public init(rows: [[String: Any]]) {
        self.rows = rows
    }

    public func copyWindowInfo() -> [[String: Any]] {
        readCount += 1
        return rows
    }
}

/// The **only** file in the shipping graph permitted to call `CGWindowListCopyWindowInfo` —
/// and it is written so that standing condition 1 is a property of the type rather than a rule
/// somebody remembers.
///
/// ## There is nowhere to put a title
///
/// The decoder names **seven** keys and discards the rest of the dictionary. `WindowMetadataValue`
/// has no `title` field, no `name` field and no untyped accessor, so a consumer cannot reach a
/// key the decoder did not take even if a later row carries one. Fed a corpus that *includes*
/// the banned key, the value that comes out is identical to the value from a corpus without it.
///
/// The key is also worthless without a grant this app will never request: from a bundle holding
/// no TCC row it was present on **1 of 25** on-screen windows and on **2 of 128** with
/// `.optionAll`, and both of those two belonged to Window Server (probe P-75). With Screen
/// Recording granted, the same call returned 34 of 35. The whole difference is TCC.
///
/// ## Cost discipline
///
/// A call costs **0.296 ms** at the median, with a **2–4 ms cold first call** (probe P-76). So
/// the reader is warmed once at start-up and thereafter called on an accepted activation and on
/// the five-second corroboration tick — never on a faster timer.
///
/// ## Clearance is a parameter, not a convention
///
/// Every read takes a `ClearedActivation`, which only `SensitivityGate` can produce. A deeper
/// read of a sensitive application therefore does not compile (R-43).
@MainActor
public final class WindowMetadataReader {
    private let list: any WindowListReading

    public init(list: any WindowListReading = SystemWindowList()) {
        self.list = list
    }

    // MARK: - The seven keys, named once

    /// The keys this reader decodes, and the whole of what it takes from a row.
    ///
    /// Reported verbatim by `--focus-self-check`, which asserts both that this is the set and
    /// that no name key is in it — so the claim is checked on the shipped build at zero grants
    /// rather than only in a comment.
    public static let decodedKeys: [String] = [
        kCGWindowOwnerName as String,
        kCGWindowOwnerPID as String,
        kCGWindowLayer as String,
        kCGWindowNumber as String,
        kCGWindowBounds as String,
        kCGWindowIsOnscreen as String,
        kCGWindowAlpha as String
    ]

    /// The key families a decoded row must never contain.
    ///
    /// Used by the self-check to assert the absence positively rather than by silence. It is a
    /// substring test on the *decoded* key set, so it would catch a future key called
    /// something else that still meant "what the window is called".
    public static let forbiddenKeyFragments: [String] = ["Name", "Title"]

    /// Whether the decoded key set is clean: seven keys, none of which names a window.
    ///
    /// `kCGWindowOwnerName` is the **application's** name, which is public, is on every row at
    /// zero grants, and is not a title — so it is excluded from the fragment test by name
    /// rather than by the test being weakened.
    public static var decodedKeysAreTitleFree: Bool {
        let ownerName = kCGWindowOwnerName as String
        return decodedKeys.allSatisfy { key in
            key == ownerName || !forbiddenKeyFragments.contains { key.contains($0) }
        }
    }

    // MARK: - Reading

    /// Take the cold first call now, so it is not taken inside the first decision (probe P-76).
    public func warm() {
        _ = list.copyWindowInfo()
    }

    /// Every on-screen window, read on behalf of an activation that has passed the gate.
    ///
    /// The whole list rather than a filtered one, because the presentation quorum has to be
    /// able to see the decoys in order to reject them — the Dock's permanently display-sized
    /// window is the reason the PID filter exists at all (probe P-78).
    public func windows(for activation: ClearedActivation) -> [WindowMetadataValue] {
        _ = activation
        return Self.decode(list.copyWindowInfo())
    }

    /// The cleared application's own ordinary windows, and nothing else.
    ///
    /// `layer == 0` **and** an owner-PID match. Both halves are load-bearing:
    /// `.optionOnScreenOnly` is **not** scoped to the current Space — a third zero-grant process
    /// listed a full-screen app's window together with seven applications from another Space,
    /// 27 rows in one call (probe P-77) — so "is *some* window full-screen" is always the wrong
    /// question.
    public func applicationWindows(for activation: ClearedActivation) -> [WindowMetadataValue] {
        windows(for: activation).applicationWindows(of: activation.pid)
    }

    // MARK: - The decoder

    /// Decode a whole list, dropping any row that is not a window.
    public static func decode(_ rows: [[String: Any]]) -> [WindowMetadataValue] {
        rows.compactMap(decodeRow)
    }

    /// Decode one row into the seven fields, and discard everything else in the dictionary.
    ///
    /// A row missing one of the four keys the plan depends on is dropped rather than guessed
    /// at. On the rig all ten sanctioned keys were present on **100 % of 25 rows** (probe
    /// P-74), so a missing one is a change in the platform and not an ordinary case — and
    /// inventing a bounds rectangle for it would put a window somewhere it is not.
    public static func decodeRow(_ row: [String: Any]) -> WindowMetadataValue? {
        guard
            let ownerName = row[kCGWindowOwnerName as String] as? String,
            let ownerPID = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
            let layer = (row[kCGWindowLayer as String] as? NSNumber)?.intValue,
            let number = (row[kCGWindowNumber as String] as? NSNumber)?.intValue,
            let bounds = boundsRect(from: row[kCGWindowBounds as String])
        else {
            return nil
        }

        // The two soft fields. `isOnScreen` is absent on some system surfaces; the list was
        // asked for on-screen windows only, so absent means present.
        let isOnScreen = (row[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
        let alpha = (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1

        return WindowMetadataValue(
            ownerName: ownerName,
            ownerPID: ownerPID,
            layer: layer,
            number: number,
            bounds: bounds,
            isOnScreen: isOnScreen,
            alpha: alpha
        )
    }

    /// `kCGWindowBounds` is a CFDictionary of `X`, `Y`, `Width`, `Height` in **Quartz**
    /// coordinates. `ScreenRect` is what the domain layer holds, because `FocusCore` may not
    /// import CoreGraphics — the conversion happening here, at the one boundary, is the seam
    /// working rather than a workaround for it.
    static func boundsRect(from value: Any?) -> ScreenRect? {
        guard let value else { return nil }
        let dictionary = value as CFTypeRef
        guard
            CFGetTypeID(dictionary) == CFDictionaryGetTypeID(),
            let rect = CGRect(dictionaryRepresentation: unsafeBitCast(dictionary, to: CFDictionary.self))
        else {
            return nil
        }
        return ScreenRect(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }
}
