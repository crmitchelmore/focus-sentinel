import Foundation

/// Something the app might be able to do, and might not.
///
/// Thirteen of them, named once here and nowhere else. Four belong to epics that have not landed
/// — they are declared now so that turning one on is a change to a probe rather than a change
/// to a table, and so that the fallback contract is total from the first day rather than from
/// the day somebody remembers to extend it.
///
/// Raw values are strings and are persisted as `CapabilityRecord.capabilityRaw`.
public enum Capability: String, Sendable, CaseIterable, Codable, Hashable {
    /// Which application is frontmost, from `NSWorkspace`'s own notification. Grant-free:
    /// sixteen observers installed and every activation delivered from a bundle holding no
    /// TCC row at all (probe P-79).
    case frontmostApplication
    /// Owner, PID, layer, bounds from `CGWindowListCopyWindowInfo` — and never a name.
    /// Grant-free: all ten sanctioned keys present on 100 % of 25 rows (probe P-74).
    case windowMetadata
    /// Seconds since the last input, from `CGEventSource`. Grant-free (probe P-84).
    case idle
    /// Screen lock, sleep and session state. Grant-free, with a **public** primary:
    /// `com.apple.loginwindow` becoming frontmost, 1.5 ms before the undocumented
    /// distributed notification (probe P-87).
    case systemLifecycle
    /// Which display a window is on. Grant-free (probes P-90/P-91).
    case displayGeometry
    /// Whether the frontmost app has taken over the screen. Grant-free (probe P-93).
    case presentation
    /// Whether an audio **input** device is running somewhere. Grant-free, and measured
    /// against four independent prompt instruments (probes P-94/P-95).
    case microphoneActivity
    /// Whether a camera is running somewhere.
    ///
    /// **Pinned `.unavailable` in v1, on every Mac.** The enumeration was measured
    /// prompt-free; the per-device read and the listener install never executed, because the
    /// rig has no camera (probes P-97/P-104). An unanswered question is not a pass, so this
    /// ships held rather than shipped on an extrapolation.
    case cameraActivity
    /// Window titles and browser context through the Accessibility API. e07's, with consent.
    case accessibilityWindowContext
    /// Pixel capture. Parked by the Feasibility Court (dissent D-04).
    case screenCapture
    /// User notifications. **Declared, read by nothing, and never asked for** (U-2, focus-wy0,
    /// focus-i1g).
    ///
    /// It was written down as *"e05's, and the first ask this programme ever makes"*. The
    /// programme makes no ask: `requestAuthorization` is nowhere in this repository, the
    /// notification rung went with the recommitment rung deferred to focus-5ab, and every cell of
    /// `CapabilityContract` for this capability is `.fullFunction` — nothing degrades when it is
    /// missing, because nothing consults it. What survives is a *reading* the self-check reports
    /// so the `notification-denied` gate stage can say which grant state this Mac was in while
    /// every rung still landed on an in-app surface.
    case notifications
    /// Apple's on-device model. e06's.
    case onDeviceModel
    /// **When the person is busy, from their own calendar** (focus-cal). Opt-in, through the
    /// Privacy pane's third grant switch, and read for nothing but busy intervals: a start, an
    /// end, and whether the time is marked busy. Never a title, a location, a note or an
    /// attendee, and nothing read is stored.
    ///
    /// Appended rather than placed beside the other grants, so every persisted raw value and
    /// every rendered order that already exists keeps its meaning.
    ///
    /// Not a call. `microphoneActivity` may never assert a meeting, because a running
    /// microphone is not one; a calendar entry is a separate, explicit statement the person made
    /// about their own time, and it is read as exactly that.
    case calendarEvents
}
