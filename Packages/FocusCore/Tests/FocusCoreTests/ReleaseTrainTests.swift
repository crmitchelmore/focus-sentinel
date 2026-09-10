import Foundation
import Testing
@testable import FocusCore

/// **Two trains, and every fact that keeps them apart is a row** (focus-h8jf).
@Suite("Release trains")
struct ReleaseTrainTests {
    @Test("every train carries every required key, and no value is empty")
    func catalogueIsComplete() {
        for train in ReleaseTrain.allCases {
            let row = ReleaseTrainCatalogue.values[train.rawValue]
            #expect(row != nil, "\(train.rawValue) has no row")
            for key in ReleaseTrain.requiredKeys {
                let value = row?[key] ?? ""
                #expect(!value.isEmpty, "\(train.rawValue).\(key) is empty")
            }
        }
        #expect(Set(ReleaseTrainCatalogue.values.keys) == Set(ReleaseTrain.allCases.map(\.rawValue)))
    }

    @Test("the two trains share nothing that would let one open the other's data or feed")
    func trainsAreApart() {
        let stable = ReleaseTrain.stable
        let alpha = ReleaseTrain.alpha
        #expect(stable.bundleIdentifier != alpha.bundleIdentifier)
        #expect(stable.applicationSupportDirectory != alpha.applicationSupportDirectory)
        #expect(stable.urlScheme != alpha.urlScheme)
        #expect(stable.feedURL != alpha.feedURL)
        #expect(stable.latestReleaseTag != alpha.latestReleaseTag)
        for train in ReleaseTrain.allCases {
            #expect(train.feedURL.hasPrefix("https://"), "\(train.rawValue) feed is not https")
        }
    }

    /// **The Stable row is the identity every earlier build had**, so nothing about an existing
    /// install moves: same bundle identifier, same store directory, same `focus://` scheme.
    @Test("Stable is the identity the app has always had")
    func stableIsUnchanged() {
        #expect(ReleaseTrain.stable.bundleIdentifier == "com.chrismitchelmore.FocusSentinel")
        #expect(ReleaseTrain.stable.applicationSupportDirectory == "com.chrismitchelmore.FocusSentinel")
        #expect(ReleaseTrain.stable.urlScheme == "focus")
        #expect(ReleaseTrain.stable.productName == "FocusSentinel")
    }

    @Test("a process with no metadata is Stable, and an Alpha identity is Alpha")
    func resolution() {
        #expect(ReleaseTrain.resolve(metadata: nil, bundleIdentifier: nil) == .stable)
        #expect(ReleaseTrain.resolve(metadata: nil, bundleIdentifier: "com.apple.dt.xctest.tool") == .stable)
        #expect(ReleaseTrain.resolve(metadata: "stable", bundleIdentifier: ReleaseTrain.stable.bundleIdentifier) == .stable)
        #expect(ReleaseTrain.resolve(metadata: "alpha", bundleIdentifier: ReleaseTrain.alpha.bundleIdentifier) == .alpha)
        // No metadata, Alpha identity: the identity decides, never Stable storage by default.
        #expect(ReleaseTrain.resolve(metadata: nil, bundleIdentifier: ReleaseTrain.alpha.bundleIdentifier) == .alpha)
    }

    @Test("this test process is Stable, so the store path and the scheme are the ones e01 shipped")
    func thisProcessIsStable() {
        #expect(ReleaseTrain.current == .stable)
        #expect(FocusStore.bundleIdentifier == "com.chrismitchelmore.FocusSentinel")
        #expect(FocusStore.applicationSupportDirectoryURL.lastPathComponent == "com.chrismitchelmore.FocusSentinel")
        #expect(HandoffRequest.scheme == "focus")
    }
}
