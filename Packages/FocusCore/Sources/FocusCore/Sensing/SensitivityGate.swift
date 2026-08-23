import Foundation

/// An activation that has passed the sensitivity gate.
///
/// **There is no public initialiser.** The memberwise one is `fileprivate`, and the only file
/// that can reach it is this one — which contains the gate and nothing else. Every deeper
/// reader in the shipping graph takes one of these rather than a bundle identifier: window
/// metadata, display geometry, presentation, and from e07 every Accessibility reader.
///
/// **A deeper read of a sensitive application therefore does not compile.** That is the whole
/// ruling. The requirement was "checked before any deeper read", and "remember to check first"
/// is a bug waiting for a refactor — so the ordering is enforced by the type system rather
/// than by call order, and it is worth the two types.
public struct ClearedActivation: Sendable, Equatable, Hashable {
    public let bundleIdentifier: String
    public let pid: pid_t
    public let at: Date

    fileprivate init(bundleIdentifier: String, pid: pid_t, at: Date) {
        self.bundleIdentifier = bundleIdentifier
        self.pid = pid
        self.at = at
    }
}

/// Why the gate stood down.
public enum SensitiveReason: String, Sendable, CaseIterable, Codable, Hashable {
    /// On the conservative list this app ships.
    case builtInList
    /// On the list this person added to.
    case userList
    /// The process has no bundle identifier, so there is nothing to check it against — and an
    /// unidentifiable process is exactly the one not to look at more closely.
    case unbundled
}

/// The gate's answer. There is no third case, and no way to get a `ClearedActivation` except
/// out of the first one.
public enum SensitiveScreenDecision: Sendable, Equatable, Hashable {
    case cleared(ClearedActivation)
    case suppressed(reason: SensitiveReason)

    public var clearedActivation: ClearedActivation? {
        switch self {
        case .cleared(let activation): activation
        case .suppressed: nil
        }
    }

    public var suppressionReason: SensitiveReason? {
        switch self {
        case .cleared: nil
        case .suppressed(let reason): reason
        }
    }
}

/// The check that runs **before** any deeper read, and the only producer of a
/// `ClearedActivation`.
///
/// ## Nothing is ever inferred from what is on the screen
///
/// "Is this banking?" is answered by a bundle identifier being on a list. It is never answered
/// by looking at a window, a title, a URL or a pixel — there is no code here that could, and
/// there is no capability in this epic that would allow it.
public struct SensitivityGate: Sendable {
    /// The conservative list this app ships. Marked built-in in the store, and every entry
    /// user-removable.
    public let builtIn: Set<String>
    /// What this person added. Their list is theirs.
    public let userAdded: Set<String>

    public init(builtIn: Set<String> = SensitivityGate.builtInSensitiveBundleIDs, userAdded: Set<String> = []) {
        self.builtIn = builtIn
        self.userAdded = userAdded
    }

    /// Decide whether anything deeper may look at this activation.
    ///
    /// A suppressed activation still writes **one** event carrying the bundle identifier and
    /// nothing else: the person is entitled to see that the app noticed and stood down.
    public func evaluate(_ activation: FrontmostActivation) -> SensitiveScreenDecision {
        guard let bundleIdentifier = activation.bundleIdentifier else {
            return .suppressed(reason: .unbundled)
        }
        if userAdded.contains(bundleIdentifier) {
            return .suppressed(reason: .userList)
        }
        if builtIn.contains(bundleIdentifier) {
            return .suppressed(reason: .builtInList)
        }
        return .cleared(
            ClearedActivation(
                bundleIdentifier: bundleIdentifier,
                pid: activation.pid,
                at: activation.at
            )
        )
    }

    /// The effective list, as the Privacy surface shows it.
    public var effectiveBundleIDs: Set<String> { builtIn.union(userAdded) }

    /// The seeded list. **Conservative by design**, bundle identifiers only, every entry
    /// `isBuiltIn` in the store and every entry user-removable — with removals surviving a
    /// reseed.
    ///
    /// Messages is **deliberately absent**. It is a private-messaging app and it is also a
    /// work tool for a great many people, so it is offered as a suggestion in Privacy settings
    /// rather than switched on for everyone. Deciding that for somebody would be the app
    /// having an opinion about who they talk to.
    public static let builtInSensitiveBundleIDs: Set<String> = [
        // password managers
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.dashlane.dashlanephonefinal",
        "com.callpodinc.keeper",
        "in.sinew.Enpass-Desktop",
        "com.strongbox.mac.Strongbox",
        "com.apple.keychainaccess",
        "com.apple.Passwords",

        // banking, payments and finance
        "com.apple.PassKit.WalletApp",
        "com.apple.stocks",
        "com.intuit.quickbooks.mac",
        "com.ynab.ynab4",

        // health
        "com.apple.Health",
        "com.apple.Fitness",

        // private messaging
        "org.whispersystems.signal-desktop",
        "net.whatsapp.WhatsApp",
        "ru.keepcoder.Telegram",
        "com.wickr.desktop",
        "org.getsession.desktop"
    ]

    /// Offered in Privacy settings as a suggestion, and **never** seeded.
    public static let suggestedSensitiveBundleIDs: Set<String> = [
        "com.apple.MobileSMS"
    ]
}
