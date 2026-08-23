import Foundation

/// The four signals the app may look at, in **cost order**.
///
/// Cheapest first is not an optimisation here; it is the privacy posture. The two cheap tiers
/// need no grant at all and were measured working from a bundle holding no TCC row. The two
/// expensive ones need Accessibility, which is a question the app has not yet earned the right
/// to ask, and which e07 will ask on a surface the user opened.
public enum SignalTier: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
    /// The bundle identifier, off the activation notification itself. Free.
    case frontmostApplication
    /// Owner, PID, layer and bounds from the window list. 0.296 ms at the median (probe P-76).
    case windowMetadata
    /// The window's title, through the Accessibility API, with consent. **e07.**
    case accessibilityWindowTitle
    /// The browser's normalised origin, through the Accessibility API, with consent. **e07.**
    case accessibilityBrowserContext

    /// The capability that must be `.available` before this tier may be used.
    public var requiredCapability: Capability {
        switch self {
        case .frontmostApplication: .frontmostApplication
        case .windowMetadata: .windowMetadata
        case .accessibilityWindowTitle, .accessibilityBrowserContext: .accessibilityWindowContext
        }
    }

    /// Where this tier sits in the cost order. Lower is cheaper.
    public var cost: Int {
        switch self {
        case .frontmostApplication: 0
        case .windowMetadata: 1
        case .accessibilityWindowTitle: 2
        case .accessibilityBrowserContext: 3
        }
    }

    public static func < (lhs: SignalTier, rhs: SignalTier) -> Bool { lhs.cost < rhs.cost }
}

/// What one tier's evidence produced.
///
/// `FocusClassify` owns the real `Verdict`; `FocusCore` may not import it, and does not need
/// to. What the policy needs is the distinction between **a decision** and **no decision**,
/// and that is what this carries.
public enum ClassificationOutcome: String, Sendable, CaseIterable, Codable, Hashable {
    case relevant
    case unrelated
    /// There is not enough evidence to say. **This is a decision** — the decision to say
    /// nothing — and it terminates the cascade like any other.
    case uncertain
    /// The tier produced no evidence at all. The only outcome that justifies looking harder.
    case undecided

    /// Whether the cascade may go on.
    ///
    /// Standing condition 6 lives here: `uncertain` is a decision, so declining to decide can
    /// never become a reason to look harder. An app that answered "I don't know" by reading
    /// more of your screen would have inverted the promise it is built on.
    public var isDecision: Bool { self != .undecided }
}

/// Cheapest-signal-first escalation, as a pure function.
///
/// ## In v1 the cascade terminates before it starts
///
/// The policy is written with all four tiers, and the two Accessibility ones report
/// `.notRequested` because e07 has not landed. So in this build `nextSignal` returns `nil`
/// after `.windowMetadata`, every time — and e07 turns them on by changing a **capability
/// probe** and nothing else. Writing two tiers now and switching them on later is what stops
/// e07 from being a change to this file.
public struct SignalEscalationPolicy: Sendable {
    public init() {}

    /// The first tier to try, or `nil` if not even the cheapest one is available.
    public func firstSignal(capabilities: CapabilityMatrix) -> SignalTier? {
        SignalTier.allCases
            .sorted()
            .first { capabilities.isAvailable($0.requiredCapability) }
    }

    /// The next tier to try after `tier`, or `nil` to stop.
    ///
    /// - Rule 1: escalate **only** when the outcome is `.undecided`. A decided verdict —
    ///   including `uncertain` — terminates the cascade.
    /// - Rule 2: never escalate to a tier whose capability is not `.available`. Such a tier is
    ///   **skipped silently** and the cascade continues past it; it is never re-asked, because
    ///   in this programme there is nothing to re-ask with.
    /// - Rule 3: the sensitivity gate is **not** a tier. It runs before the cascade begins,
    ///   and it is enforced by the type system rather than by ordering — every deeper reader
    ///   takes a `ClearedActivation`, so a deeper read of a sensitive application does not
    ///   compile.
    public func nextSignal(
        after tier: SignalTier,
        given outcome: ClassificationOutcome,
        capabilities: CapabilityMatrix
    ) -> SignalTier? {
        guard !outcome.isDecision else { return nil }

        return SignalTier.allCases
            .sorted()
            .first { candidate in
                candidate.cost > tier.cost
                    && capabilities.isAvailable(candidate.requiredCapability)
            }
    }

    /// The whole cascade this capability matrix permits, cheapest first.
    ///
    /// Used by the self-check and the Privacy surface to show the person exactly how far the
    /// app can look — which in v1 is two tiers and stops.
    public func availableCascade(capabilities: CapabilityMatrix) -> [SignalTier] {
        SignalTier.allCases
            .sorted()
            .filter { capabilities.isAvailable($0.requiredCapability) }
    }
}
