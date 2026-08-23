import Foundation

/// Which boot this is — a grant-free string that says whether a persisted uptime anchor means
/// anything.
///
/// ## Why a session needs one at all
///
/// The restoration anchor is **seconds since boot** (`UptimeClock`). Measured across two
/// separate process launches two seconds apart (probe P-106): `741532.264` and `741534.294`, a
/// delta matching the wall delta to 0.1 ms — so the anchor really is comparable across
/// processes. But it is comparable only *on the same boot*: after a restart the counter starts
/// again from zero and differencing the two is arithmetic on unrelated numbers. `kern.boottime`
/// read `1786742847.869178` **byte-identically** in both launches, which is what makes it the
/// discriminator.
///
/// The reconciler uses it exactly that way: same identity ⇒ the anchor is usable and a drift
/// beyond tolerance is a clock anomaly; different identity ⇒ the anchor is discarded, **no
/// drift is computed at all**, and the session is restored paused with cause `.systemRestart`.
/// A spurious "the clock changed" beside a reboot would misname what actually happened.
///
/// ## It needs no grant, and could not be flattered by one
///
/// `sysctl kern.boottime` is not a TCC-guarded surface. Unlike a window read, this is a
/// measurement the invoking shell's grants cannot have improved.
public enum BootIdentity {
    /// The sysctl this reads. Named once, so the string is not scattered.
    public static let sysctlName = "kern.boottime"

    /// This boot, as `"<seconds>.<microseconds>"`.
    ///
    /// Both halves, deliberately. The seconds alone would be identical for two boots a
    /// sub-second apart, which cannot happen on real hardware but can in a test rig or a
    /// virtual machine restarted in a loop — and an identity that can collide is not one.
    ///
    /// Empty when the sysctl fails, which is a state that must not be mistaken for a match:
    /// `SessionRestoration` compares the stored identity against this one, and an empty string
    /// stored beside an empty string would compare equal and revive a dead anchor. Callers
    /// persist the identity only when it is non-empty, and the self-check asserts it is.
    public static func current() -> String {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname(sysctlName, &boot, &size, nil, 0) == 0 else { return "" }
        return "\(boot.tv_sec).\(boot.tv_usec)"
    }

    /// Read an identity back into its two halves, for a surface or an evidence lane that wants
    /// to show the boot instant rather than the opaque string.
    ///
    /// `nil` for anything this build cannot interpret — including the empty string — so that a
    /// row written by a future version cannot be rendered as a date it does not mean.
    public static func parse(_ raw: String?) -> (seconds: Int, microseconds: Int)? {
        guard let raw, !raw.isEmpty else { return nil }
        let halves = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard
            halves.count == 2,
            let seconds = Int(halves[0]),
            let microseconds = Int(halves[1])
        else {
            return nil
        }
        return (seconds, microseconds)
    }

    /// Whether two identities name the same boot.
    ///
    /// An empty identity matches nothing, **including another empty one**. That is the whole
    /// reason this is a function rather than `==` at the call site: a failed sysctl on both
    /// sides must not be allowed to look like agreement.
    public static func isSameBoot(_ stored: String?, as current: String) -> Bool {
        guard let stored, !stored.isEmpty, !current.isEmpty else { return false }
        return stored == current
    }
}
