import FocusCore
import Testing

@testable import FocusUpdates

/// **The updater does nothing until it is asked** (focus-h8jf).
///
/// What a unit process can hold is the half that matters most: building the updater with the
/// shipped choice starts nothing. Starting it is not driven here — that is the one thing a
/// test must never do, because it opens a socket — so the start is proved by reading the flag
/// the shipped code sets and nothing else.
@Suite("The Sparkle updater")
@MainActor
struct SparkleUpdaterTests {
    @Test("built with checks off, it is not started and can still take a manual check")
    func offIsInert() {
        let updater = SparkleUpdater(train: .stable, checksAutomatically: false)
        #expect(!updater.isStarted)
        #expect(updater.canCheckForUpdates)
        #expect(updater.lastCheckDate == nil)
    }

    @Test("switching checks off on a never-started updater leaves it never started")
    func offOnUnstartedStaysUnstarted() {
        let updater = SparkleUpdater(train: .alpha, checksAutomatically: false)
        updater.setAutomaticChecks(false)
        #expect(!updater.isStarted)
    }

    @Test("the feed it would ask is the train's, per train")
    func feedIsTheTrains() {
        for train in ReleaseTrain.allCases {
            #expect(train.feedURL.hasPrefix("https://"), "\(train.rawValue) feed is not https")
        }
        #expect(ReleaseTrain.stable.feedURL != ReleaseTrain.alpha.feedURL)
    }
}
