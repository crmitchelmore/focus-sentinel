import Foundation
import Testing

@testable import FocusCore

private let now = Date(timeIntervalSince1970: 1_767_225_600)
private let policy = SignalEscalationPolicy()

/// The matrix this build actually ships at zero grants: two tiers live, two not requested.
private let v1Capabilities = CapabilityMatrix.zeroGrantExpectation(at: now)

/// A hypothetical future in which e07 has landed and Accessibility is granted.
private let allTiersAvailable = StaticCapabilityProbe(everything: .available).probe(at: now)

@Suite("Cheapest-signal-first escalation")
struct SignalEscalationPolicyTests {
    @Test("the four tiers are declared in cost order, cheapest first")
    func tiersAreInCostOrder() {
        #expect(SignalTier.allCases.sorted() == [
            .frontmostApplication, .windowMetadata,
            .accessibilityWindowTitle, .accessibilityBrowserContext
        ])
        #expect(SignalTier.frontmostApplication < SignalTier.windowMetadata)
        #expect(SignalTier.windowMetadata < SignalTier.accessibilityWindowTitle)
    }

    /// Rule 1. Only "I found nothing" justifies looking harder.
    @Test("escalation happens only on .undecided")
    func escalatesOnlyOnUndecided() {
        for outcome in ClassificationOutcome.allCases {
            let next = policy.nextSignal(
                after: .frontmostApplication,
                given: outcome,
                capabilities: allTiersAvailable
            )
            if outcome == .undecided {
                #expect(next == .windowMetadata, "an undecided tier must escalate")
            } else {
                #expect(next == nil, "\(outcome) is a decision and must terminate the cascade")
            }
        }
    }

    /// **Standing condition 6, at the level of the policy.** Declining to decide can never
    /// become a reason to read more of somebody's screen. This is the assertion that says so.
    @Test("uncertain terminates the cascade exactly like relevant and unrelated")
    func uncertainTerminatesTheCascade() {
        #expect(ClassificationOutcome.uncertain.isDecision)
        for tier in SignalTier.allCases {
            #expect(
                policy.nextSignal(after: tier, given: .uncertain, capabilities: allTiersAvailable) == nil,
                "uncertain escalated from \(tier)"
            )
        }
        #expect(!ClassificationOutcome.undecided.isDecision)
    }

    /// Rule 2. A tier the app may not use is stepped over in silence — and in this programme
    /// "never re-asked" is trivially true, because there is nothing to ask with: every
    /// prompting API is banned from the shipping graph.
    @Test("a denied tier is skipped silently and the cascade continues past it")
    func deniedTierIsSkipped() {
        let windowMetadataDenied = StaticCapabilityProbe([
            .frontmostApplication: .available,
            .windowMetadata: .denied,
            .accessibilityWindowContext: .available
        ]).probe(at: now)

        #expect(
            policy.nextSignal(
                after: .frontmostApplication,
                given: .undecided,
                capabilities: windowMetadataDenied
            ) == .accessibilityWindowTitle
        )
    }

    /// Every non-available state is skipped the same way, because the policy asks "may I use
    /// this", not "why can I not".
    @Test("every non-available state skips its tier, not only .denied")
    func everyNonAvailableStateSkips() {
        for state in CapabilityState.allCases where state != .available {
            let capabilities = StaticCapabilityProbe([
                .frontmostApplication: .available,
                .windowMetadata: state,
                .accessibilityWindowContext: .available
            ]).probe(at: now)
            #expect(
                policy.nextSignal(
                    after: .frontmostApplication,
                    given: .undecided,
                    capabilities: capabilities
                ) == .accessibilityWindowTitle,
                "\(state) did not skip its tier"
            )
        }
    }

    /// **Rule 3, as this build actually ships.** F-30/F-31 are parked and e07 has not landed,
    /// so the two Accessibility tiers report `.notRequested` and the cascade stops at window
    /// metadata — every time, whatever the evidence says.
    @Test("the v1 cascade terminates at .windowMetadata")
    func v1CascadeStopsAtWindowMetadata() {
        #expect(policy.firstSignal(capabilities: v1Capabilities) == .frontmostApplication)
        #expect(
            policy.nextSignal(
                after: .frontmostApplication,
                given: .undecided,
                capabilities: v1Capabilities
            ) == .windowMetadata
        )
        #expect(
            policy.nextSignal(
                after: .windowMetadata,
                given: .undecided,
                capabilities: v1Capabilities
            ) == nil,
            "the cascade reached an Accessibility tier in a build that has not asked for it"
        )
        #expect(policy.availableCascade(capabilities: v1Capabilities) == [
            .frontmostApplication, .windowMetadata
        ])
    }

    /// e07 turns them on by changing a **capability probe** and nothing else. This is that
    /// claim, exercised against a probe that says Accessibility is granted.
    @Test("granting Accessibility extends the cascade without touching the policy")
    func e07TurnsOnByProbeAlone() {
        #expect(policy.availableCascade(capabilities: allTiersAvailable) == SignalTier.allCases.sorted())
        #expect(
            policy.nextSignal(
                after: .windowMetadata,
                given: .undecided,
                capabilities: allTiersAvailable
            ) == .accessibilityWindowTitle
        )
        #expect(
            policy.nextSignal(
                after: .accessibilityWindowTitle,
                given: .undecided,
                capabilities: allTiersAvailable
            ) == .accessibilityBrowserContext
        )
        #expect(
            policy.nextSignal(
                after: .accessibilityBrowserContext,
                given: .undecided,
                capabilities: allTiersAvailable
            ) == nil,
            "there is no fifth tier"
        )
    }

    @Test("with nothing available at all there is no first signal")
    func nothingAvailableMeansNoCascade() {
        let nothing = StaticCapabilityProbe(everything: .unavailable).probe(at: now)
        #expect(policy.firstSignal(capabilities: nothing) == nil)
        #expect(policy.availableCascade(capabilities: nothing).isEmpty)
    }

    @Test("escalation never goes backwards or sideways")
    func escalationOnlyMovesForward() {
        for tier in SignalTier.allCases {
            let next = policy.nextSignal(
                after: tier,
                given: .undecided,
                capabilities: allTiersAvailable
            )
            if let next {
                #expect(next.cost > tier.cost, "\(tier) escalated to \(next)")
            }
        }
    }
}
