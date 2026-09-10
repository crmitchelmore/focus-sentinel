import Foundation

/// **Which train this build belongs to** (focus-h8jf).
///
/// Two trains, and every fact that keeps them apart is a row in `Config/ReleaseTrains.json`:
/// the bundle identifier, the display name, the Application Support directory the store lives
/// in, the URL scheme a handoff arrives on, and the Sparkle feed an update is asked for from.
/// `ReleaseTrainCatalogue` is generated from that file by
/// `scripts/generate-release-train-config.py`, so the Swift and the release scripts read one
/// table rather than two copies of it.
///
/// ## How a build knows which it is
///
/// The merged Info.plist carries `FocusReleaseTrain`, substituted from the `FOCUS_RELEASE_TRAIN`
/// build setting the way `FocusGitHash` is. The bundle identifier is read beside it as a check
/// and not as a source: an Alpha identity that claimed Stable storage would open the Stable
/// store, and `resolve(metadata:bundleIdentifier:)` refuses that combination outright.
///
/// A process with no metadata at all is a unit process, a preview or a plain Xcode.app build,
/// and it is Stable, because Stable is what every build before this one was.
public enum ReleaseTrain: String, Sendable, CaseIterable, Hashable, Codable {
    case stable
    case alpha

    /// The Info.plist key the build setting lands in.
    public static let metadataKey = "FocusReleaseTrain"

    /// The train this process is running as.
    public static var current: ReleaseTrain {
        resolve(
            metadata: Bundle.main.object(forInfoDictionaryKey: metadataKey) as? String,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    /// Decide the train from the plist value and the bundle identifier.
    ///
    /// Total over its inputs: an unknown metadata value is a build error rather than a runtime
    /// guess, and an Alpha identifier with Stable metadata is the one combination that must
    /// never open a store.
    public static func resolve(metadata: String?, bundleIdentifier: String?) -> ReleaseTrain {
        let alphaIdentity = bundleIdentifier.map { $0 == Self.alpha.bundleIdentifier } ?? false
        if let metadata {
            guard let train = ReleaseTrain(rawValue: metadata) else {
                preconditionFailure("\(metadataKey) is '\(metadata)', which names no train")
            }
            precondition(
                !alphaIdentity || train == .alpha,
                "an Alpha identity may not run as Stable: it would open the Stable store"
            )
            return train
        }
        return alphaIdentity ? .alpha : .stable
    }

    /// The bundle identifier this train ships under.
    public var bundleIdentifier: String { value("bundleIdentifier") }
    /// The name the Finder and the menu bar show.
    public var displayName: String { value("displayName") }
    /// The directory under `~/Library/Application Support` the store lives in. Separate per
    /// train, so an Alpha and a Stable install on one Mac never read each other's rows.
    public var applicationSupportDirectory: String { value("applicationSupportDirectory") }
    /// The scheme a `focus://` handoff arrives on. Separate per train, so macOS routes a link to
    /// the train that made it rather than to whichever was registered last.
    public var urlScheme: String { value("urlScheme") }
    /// The Sparkle appcast this train asks for updates from, when update checks are on.
    public var feedURL: String { value("feedURL") }
    /// The `PRODUCT_NAME` the build writes, and therefore the `.app` name on the disk image.
    public var productName: String { value("productName") }
    /// The GitHub release tag the current build of this train is published under.
    public var latestReleaseTag: String { value("latestReleaseTag") }

    /// One catalogue value, or a build error: a train missing a row is a train nobody finished
    /// declaring, and a default would ship the other train's value under this one's name.
    public func value(_ key: String) -> String {
        guard let row = ReleaseTrainCatalogue.values[rawValue], let result = row[key], !result.isEmpty else {
            preconditionFailure("Config/ReleaseTrains.json has no \(rawValue).\(key)")
        }
        return result
    }

    /// Every key a train's row must carry. `ReleaseTrainTests` folds the catalogue over this.
    public static let requiredKeys: [String] = [
        "bundleIdentifier", "displayName", "applicationSupportDirectory", "urlScheme",
        "feedURL", "productName", "latestReleaseTag"
    ]
}
