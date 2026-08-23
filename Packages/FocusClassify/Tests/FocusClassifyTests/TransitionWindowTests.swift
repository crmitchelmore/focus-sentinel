import FocusCore
import Foundation
import Testing

@testable import FocusClassify

/// The bounded look-back (R-61, F-49, D-05).
///
/// D-05 downgraded F-49 to *"a bounded deterministic look-back over the F-40 event stream"*
/// with the worked example *"left IDE <90s ago for docs" ≠ drift*, and parked the learned form
/// as F-55. Both of D-05's cases are asserted below, and so is the property that makes the
/// whole thing safe: **the window can only ever make the app less likely to speak.**
@Suite("Transition window")
struct TransitionWindowTests {
    static let ide = "com.apple.dt.Xcode"
    static let docs = "com.apple.Safari"
    static let shorts = "com.google.Chrome"

    struct Driver {
        var window = TransitionWindow()
        var clock = TestClock()

        mutating func observe(_ verdict: Verdict, _ subject: String?, after seconds: Int = 0) {
            clock.advance(by: .seconds(seconds))
            window.record(
                DriftObservation(now: clock.elapsed, verdict: verdict, subject: subject)
            )
        }

        var threshold: Duration { window.effectiveThreshold(at: clock.elapsed) }
        var anchor: String? { window.returnAnchor(at: clock.elapsed) }
    }

    static let base = RelevancePolicy.sustainedDriftThreshold
    static let extended = RelevancePolicy.sustainedDriftThreshold + RelevancePolicy.detourExtension

    // MARK: - D-05's two cases

    /// **D-05's own example.** `IDE (relevant, 120 s) → docs (unrelated, 100 s) → IDE` is a
    /// detour, not drift: the anchor is present, the effective threshold is 180 s, and a
    /// hundred-second visit to the documentation never crosses it.
    @Test("IDE to docs and back is a detour, not drift")
    func d05DetourIsNotDrift() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.docs, after: 120)

        #expect(driver.anchor == Self.ide)
        #expect(driver.threshold == Self.extended)

        // A drift machine reading that threshold does not sustain at a hundred seconds.
        var machine = DriftMachine()
        machine.reduce(DriftObservation(
            now: .seconds(0), verdict: .relevant, subject: Self.ide,
            effectiveThreshold: Self.extended
        ))
        machine.reduce(DriftObservation(
            now: .seconds(120), verdict: .unrelated, subject: Self.docs,
            effectiveThreshold: Self.extended
        ))
        let state = machine.reduce(DriftObservation(
            now: .seconds(220), verdict: .unrelated, subject: Self.docs,
            effectiveThreshold: Self.extended
        ))
        #expect(!state.isSustained, "an anchored hundred-second detour must not sustain")
    }

    /// **D-05's other example.** `docs (uncertain, 40 s) → shorts (unrelated, 100 s)`: the
    /// preceding subject was never `relevant`, so there is no anchor, the threshold stays at 90
    /// seconds, and the drift is real.
    @Test("uncertain then a distraction has no anchor and stays at the base threshold")
    func d05UnanchoredDriftIsDrift() {
        var driver = Driver()
        driver.observe(.uncertain, Self.docs)
        driver.observe(.unrelated, Self.shorts, after: 40)

        #expect(driver.anchor == nil)
        #expect(driver.threshold == Self.base)

        var machine = DriftMachine()
        machine.reduce(DriftObservation(now: .seconds(0), verdict: .uncertain, subject: Self.docs))
        machine.reduce(DriftObservation(now: .seconds(40), verdict: .unrelated, subject: Self.shorts))
        let state = machine.reduce(
            DriftObservation(now: .seconds(140), verdict: .unrelated, subject: Self.shorts)
        )
        #expect(state.isSustained, "unanchored drift past the threshold must sustain")
    }

    // MARK: - What counts as an anchor

    /// Somewhere you *were*, not somewhere you glanced at.
    @Test("an anchor shorter than the dwell does not count")
    func aShortAnchorDoesNotCount() {
        var driver = Driver()
        driver.observe(.uncertain, Self.shorts)
        driver.observe(.relevant, Self.ide, after: 10)
        driver.observe(.unrelated, Self.docs, after: 20)

        #expect(driver.anchor == nil, "a 20-second visit is not somewhere you were working")
        #expect(driver.threshold == Self.base)
    }

    /// The boundary: 29 does not anchor, 30 does. `returnAnchorDwell` is inclusive on the
    /// anchoring side.
    @Test("the anchor-dwell boundary is inclusive: 29 no, 30 yes, 31 yes")
    func theAnchorBoundaryIsInclusive() {
        func anchor(held seconds: Int) -> String? {
            var driver = Driver()
            driver.observe(.uncertain, Self.shorts)
            driver.observe(.relevant, Self.ide, after: 10)
            driver.observe(.unrelated, Self.docs, after: seconds)
            return driver.anchor
        }

        #expect(anchor(held: 29) == nil)
        #expect(anchor(held: 30) == Self.ide)
        #expect(anchor(held: 31) == Self.ide)
    }

    /// An anchor still frontmost is measured against the present rather than against nothing.
    @Test("an anchor that is still frontmost is measured against now")
    func aStillFrontmostAnchorIsMeasuredAgainstNow() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        #expect(driver.anchor == nil, "no time has passed yet")

        driver.clock.advance(by: .seconds(60))
        #expect(driver.window.returnAnchor(at: driver.clock.elapsed) == Self.ide)
    }

    /// The **immediately preceding** relevant subject, not any earlier one. An older anchor
    /// belongs to a previous detour, and reusing it would extend a threshold on the strength of
    /// work somebody finished an hour ago.
    @Test("the anchor is the most recent relevant subject, not the first")
    func theAnchorIsTheMostRecentRelevantSubject() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.relevant, "com.apple.Notes", after: 40)
        driver.observe(.unrelated, Self.docs, after: 40)

        #expect(driver.anchor == "com.apple.Notes")
    }

    @Test("an empty window has no anchor and no extension")
    func anEmptyWindowAnchorsNothing() {
        let window = TransitionWindow()
        #expect(window.returnAnchor(at: .seconds(600)) == nil)
        #expect(window.effectiveThreshold(at: .seconds(600)) == Self.base)
        #expect(window.observations.isEmpty)
    }

    /// An unbundled process cannot be an anchor: there is nothing to name, and therefore
    /// nothing to have returned *to*.
    @Test("a relevant observation with no subject is not an anchor")
    func anUnbundledRelevantSubjectIsNotAnAnchor() {
        var driver = Driver()
        driver.observe(.relevant, nil)
        driver.clock.advance(by: .seconds(120))
        #expect(driver.window.returnAnchor(at: driver.clock.elapsed) == nil)
    }

    // MARK: - Bounded by both a span and a count

    /// Beyond `lookBackSpan`, yesterday is not evidence.
    @Test("observations older than the span are dropped")
    func theSpanBounds() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.relevant, Self.ide, after: 40)
        driver.observe(.unrelated, Self.docs, after: 200)

        #expect(driver.window.observations.count == 1, "the span is \(RelevancePolicy.lookBackSpan)")
        #expect(driver.anchor == nil, "an anchor 200 seconds back is not in the window")
    }

    /// …and the count bounds it even when everything is recent, so the cost is a constant.
    @Test("the window never holds more than the committed number of observations")
    func theCountBounds() {
        var window = TransitionWindow()
        for index in 0...(RelevancePolicy.maximumLookBackEvents * 2) {
            window.record(
                DriftObservation(
                    now: .milliseconds(index), verdict: .unrelated, subject: "com.example.Tool"
                )
            )
        }
        #expect(window.observations.count == RelevancePolicy.maximumLookBackEvents)
        // …and it kept the most recent ones.
        #expect(window.observations.last?.now == .milliseconds(RelevancePolicy.maximumLookBackEvents * 2))
    }

    /// Truncating a window to the committed bound changes no answer it gives, which is the
    /// shape R-74.4's sufficiency benchmark takes over the sequence fixtures.
    @Test("truncating to the committed bound changes no answer")
    func truncationChangesNoAnswer() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        for index in 1...20 {
            driver.observe(.unrelated, "com.example.Tool\(index)", after: 1)
        }

        let full = driver.window
        let truncated = full.truncated(to: RelevancePolicy.maximumLookBackEvents)
        #expect(
            full.returnAnchor(at: driver.clock.elapsed)
                == truncated.returnAnchor(at: driver.clock.elapsed)
        )
        #expect(
            full.effectiveThreshold(at: driver.clock.elapsed)
                == truncated.effectiveThreshold(at: driver.clock.elapsed)
        )
    }

    @Test("reset forgets everything")
    func resetForgetsEverything() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.docs, after: 60)
        driver.window.reset()
        #expect(driver.window.observations.isEmpty)
        #expect(driver.threshold == Self.base)
    }

    // MARK: - The property: it can only extend

    /// **Over a generated input space.** Every arrangement of five observations drawn from the
    /// three verdicts and three subjects, at every dwell, must produce a threshold that is one
    /// of exactly two values and never below the base — so there is no sequence anybody can
    /// construct that makes the app quicker to speak.
    @Test("no sequence of observations can shorten the threshold")
    func theWindowCanOnlyExtend() {
        let verdicts: [Verdict] = [.relevant, .unrelated, .uncertain]
        let subjects = [Self.ide, Self.docs, Self.shorts]
        var checked = 0

        for first in verdicts {
            for second in verdicts {
                for third in verdicts {
                    for gap in [0, 10, 29, 30, 31, 120] {
                        var driver = Driver()
                        driver.observe(first, subjects[0])
                        driver.observe(second, subjects[1], after: gap)
                        driver.observe(third, subjects[2], after: gap)

                        let threshold = driver.threshold
                        checked += 1
                        #expect(
                            threshold == Self.base || threshold == Self.extended,
                            "\(first)/\(second)/\(third) at \(gap)s produced \(threshold)"
                        )
                        #expect(threshold >= Self.base, "the window shortened the threshold")
                    }
                }
            }
        }
        #expect(checked == verdicts.count * verdicts.count * verdicts.count * 6)
    }

    /// And the extension is exactly one more grace period — D-05's worked example, as
    /// arithmetic rather than as a number.
    @Test("the extension is exactly one more grace period")
    func theExtensionIsOneMoreGracePeriod() {
        #expect(Self.extended == RelevancePolicy.sustainedDriftThreshold * 2)
        #expect(RelevancePolicy.detourExtension == RelevancePolicy.sustainedDriftThreshold)
    }

    /// The window produces no verdict and no band. Its whole public surface is an anchor, a
    /// threshold and a token — there is nothing on it that could flip a judgement.
    @Test("returning to the anchor is reported, and reports nothing else")
    func returningToTheAnchorIsReported() {
        var driver = Driver()
        driver.observe(.relevant, Self.ide)
        driver.observe(.unrelated, Self.docs, after: 60)

        #expect(driver.window.hasReturned(to: Self.ide, at: driver.clock.elapsed))
        #expect(!driver.window.hasReturned(to: Self.docs, at: driver.clock.elapsed))
        #expect(!driver.window.hasReturned(to: nil, at: driver.clock.elapsed))
        #expect(driver.window.anchorToken(at: driver.clock.elapsed)?.value == Self.ide.lowercased())
    }
}
