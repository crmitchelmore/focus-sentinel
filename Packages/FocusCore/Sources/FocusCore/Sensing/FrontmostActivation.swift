import Foundation

/// One application becoming frontmost.
///
/// The bundle identifier comes off `NSWorkspaceApplicationKey` on the notification itself —
/// no window read, no `runningApplications` scan, no Accessibility call (probe P-79). This is
/// the whole payload of the cheapest signal in the cascade, and the only one e03 needs to
/// build a timeline.
///
/// ## Two clocks, deliberately different types
///
/// `at` is **wall-clock**, from an injected `DateProvider`, because it is persisted and has to
/// mean something to a person reading a timeline tomorrow. `dwellSeconds` is **monotonic**,
/// from an injected `MonotonicClock`, because it is a duration inside one process and the wall
/// clock moves when NTP corrects it. The two sources return different types so a call site
/// cannot confuse them; here they are both `Double`s and `Date`s, but they arrive from
/// protocols that cannot be substituted for one another.
public struct FrontmostActivation: Sendable, Equatable, Hashable {
    /// The activating application's bundle identifier, or `nil` for a process that has none.
    ///
    /// Six of ninety-two running processes had none when this was measured (probe P-83) —
    /// `universalaccessd`, two `npm exec` processes, a devtools helper, an SSO daemon and a
    /// VPN helper. **None of the `.regular` ones did**, so anything that can actually be
    /// frontmost has one, and this is a robustness measure rather than a feature.
    public let bundleIdentifier: String?
    /// What the application calls itself, if anything. Used only to synthesise a key for the
    /// `nil` case — never as a rule subject, because a rule keyed on a display name is not a
    /// rule.
    public let localizedName: String?
    public let pid: pid_t
    /// Wall clock, from the injected `DateProvider`.
    public let at: Date
    /// How long the *previous* application had been frontmost, in seconds. Monotonic, from
    /// the injected `MonotonicClock`. `nil` for the first activation of a run, which has no
    /// predecessor to have dwelt anywhere.
    public let dwellSeconds: Double?

    public init(
        bundleIdentifier: String?,
        localizedName: String? = nil,
        pid: pid_t,
        at: Date,
        dwellSeconds: Double? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.pid = pid
        self.at = at
        self.dwellSeconds = dwellSeconds
    }

    public var isUnbundled: Bool { bundleIdentifier == nil }

    /// The key this activation is filed under.
    ///
    /// A bundle identifier where there is one; otherwise `unbundled:<name>`, or
    /// `unbundled:unknown` where there is not even that. The event is **never dropped** — a
    /// dropped event is a hole in the timeline, and a hole is worse than a row that says
    /// "something without a bundle identifier was here".
    public var subjectKey: String {
        if let bundleIdentifier { return bundleIdentifier }
        return "unbundled:\(localizedName ?? "unknown")"
    }

    /// Whether this activation names the same application as `other`.
    ///
    /// Debouncing turns on this and on nothing else. Measured cause (probe P-82): entering
    /// full screen produced activate → deactivate → activate → deactivate for **one** bundle
    /// identifier inside 22 ms, so a re-activation of the application that is already current
    /// is not a new dwell and must not reset the clock.
    public func isSameSubject(as other: FrontmostActivation) -> Bool {
        subjectKey == other.subjectKey
    }
}
