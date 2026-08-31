import FocusCore
import Testing

@testable import FocusHost

/// **Which of the two obstacles a gate suppression is** (focus-2uy.3).
///
/// `SensingHost.FrontmostReadingObstacle` exists because *"no deeper reading"* is two different
/// facts, and its own documentation says so: one is a stand-down the person is entitled to, the
/// other is this graph knowing nothing about the screen — *"a defect wearing the same clothes"*.
///
/// The mapping asked whether a `ClearedActivation` came back and called every `nil` a stand-down.
/// `SensitivityGate.evaluate(_:)` has **three** reasons and one of them, `.unbundled`, is the
/// second fact: the activation carried no bundle identifier, so no list was consulted and no
/// judgement was made. Measured in gate run lens6-1: `notTakenBecause` read
/// `theSensitivityGateStoodDown` with nothing frontmost at all, and the gate printed *"the
/// frontmost application was suppressed by the sensitivity gate"* — an excuse that was not true.
@Suite("A front with no bundle identifier is nothing frontmost, not a stand-down")
struct FrontmostReadingObstacleTests {
    /// The fold, over `SensitiveReason.allCases` rather than over the reasons a reader remembers.
    /// A fourth reason added to the gate lands here as a new case and the switch will not compile
    /// until somebody says which obstacle it is.
    @Test("every suppression reason maps to the obstacle it actually is", arguments: SensitiveReason.allCases)
    func everyReasonMapsToWhatItIs(reason: SensitiveReason) {
        let obstacle = SensingHost.FrontmostReadingObstacle(standingDownFor: reason)
        switch reason {
        case .builtInList, .userList:
            #expect(
                obstacle == .theSensitivityGateStoodDown,
                "a list the app or the person put an application on is the gate working"
            )
        case .unbundled:
            #expect(
                obstacle == .nothingIsFrontmost,
                "an activation with no bundle identifier was reported as a judgement about one"
            )
        }
    }

    /// **The completeness check** (repair doctrine, clause 2). The mapping's domain is the gate's
    /// own closed set and its range is this enum's; both are asserted against their own
    /// `allCases`, so growing either without growing the map fails here.
    ///
    /// And it is non-vacuous in the direction that matters: **both** obstacles must be reachable.
    /// The defect was a map whose range was one value, and a map that answered
    /// `theSensitivityGateStoodDown` for everything is exactly what this refuses.
    @Test("the map covers every reason and reaches every obstacle")
    func theMapCoversTheSpace() {
        #expect(SensitiveReason.allCases.count == 3)
        let reached = Set(SensitiveReason.allCases.map(SensingHost.FrontmostReadingObstacle.init(standingDownFor:)))
        #expect(
            reached == Set(SensingHost.FrontmostReadingObstacle.allCases),
            "a suppression can no longer produce every obstacle this enum declares"
        )
    }

    /// **What this proof would still be green for** (repair doctrine, clause 3).
    ///
    /// It says nothing about `frontmostReadingObstacle`'s *first* line — `seededCurrent()`
    /// answering `nil`, which is the other way `nothingIsFrontmost` is reached and needs a live
    /// graph to drive. It also says nothing about whether the gate stood down correctly; that is
    /// `SensitivityGateTests`' subject. This is the map alone, which is where the conflation was.
    @Test("the two obstacles are still two, with distinct raw values")
    func theTwoObstaclesAreStillTwo() {
        let raws = Set(SensingHost.FrontmostReadingObstacle.allCases.map(\.rawValue))
        #expect(raws.count == SensingHost.FrontmostReadingObstacle.allCases.count)
    }
}
