import FocusCore
import Testing

@testable import FocusUI

/// **The Privacy pane's retention control** (F-115, focus-l7n).
///
/// The window itself is `FocusCore`'s and is proved there — that a stored seven days is the seven
/// days the sweep keeps. What this suite owns is the half that lives in the shell: that every
/// window a person can be offered has a word, that the words are a closed vocabulary rather than
/// a list somebody keeps in step by hand, and that the pane's reach is still a set a reader can
/// hold in their head.
@Suite("Retention control")
struct RetentionControlTests {
    /// Every window has a word, and no two share one.
    ///
    /// The `switch` in `RetentionWindow.titleKey` is exhaustive, so the compiler already refuses
    /// a window with no word. What it cannot refuse is two windows pointing at the same key,
    /// which would draw two buttons reading *90 days* and leave a person unable to say which one
    /// they had chosen.
    @Test("every retention window has its own word")
    func everyWindowHasItsOwnWord() {
        let keys = RetentionWindow.allCases.map(\.titleKey)
        #expect(Set(keys).count == RetentionWindow.allCases.count, "two windows share a word")
    }

    /// **The other direction**, which is the one that goes stale: a key added to the catalog's
    /// retention family that no window claims is a string nothing draws, and the string lint's
    /// reachability rule would let it through as long as its case name appeared anywhere.
    @Test("every retention string belongs to a window, a heading or the sentence")
    func everyRetentionStringIsClaimed() {
        let family = ShellStringKey.allCases.filter {
            $0.rawValue.hasPrefix("settings.privacy.retention.")
        }
        let claimed =
            Set(RetentionWindow.allCases.map(\.titleKey))
            .union([.settingsPrivacyRetentionHeading, .settingsPrivacyRetentionExplanation])
            // The tooltip every window button carries (focus-8ski): one sentence for the
            // family, drawn by `retentionButtons` and `retentionChoices` through `shellHelp`.
            .union([.settingsPrivacyRetentionHelp])
        #expect(Set(family) == claimed, "the retention string family and its readers disagree")
        // Four windows, a heading, a sentence and a tooltip — a count that moves when either
        // side does.
        #expect(family.count == 7)
    }

    /// The pane draws all six, so `StringCatalogTests` and the reachability lint both see them.
    @Test("the pane declares every retention string it draws")
    func theContentKeysCarryTheControl() {
        let keys = Set(PrivacySettingsView.contentKeys)
        #expect(keys.contains(.settingsPrivacyRetentionHeading))
        #expect(keys.contains(.settingsPrivacyRetentionExplanation))
        for window in RetentionWindow.allCases {
            #expect(keys.contains(window.titleKey), "the pane draws no word for \(window)")
        }
    }

    /// **The review's I-4, restated for five verbs.**
    ///
    /// The pane's reach is a closed set, and the published vocabulary is the set its cases
    /// actually produce rather than a literal somebody remembered to update. Both directions.
    @Test("the pane's action vocabulary is exactly its ten verbs")
    func theVocabularyIsWhatTheCasesProduce() {
        var produced: [String] = []
        for action in PrivacySettingsAction.allDeclared where !produced.contains(action.verb) {
            produced.append(action.verb)
        }
        #expect(produced == PrivacySettingsAction.vocabulary)
        #expect(produced == [
            "deleteEverything", "setRetentionWindow",
            "exportData", "exportSettings", "importSettings",
            "setSensingPaused", "setIdleThreshold", "setMediaSuppression",
            "setLaunchContextOnSessionStart", "setGrantOptIn"
        ])
        // One action per offered window, plus the destructive one and the three portability
        // verbs — so a window that could be stored but never asked for is a count that does not
        // add up.
        #expect(PrivacySettingsAction.allDeclared.count == RetentionWindow.ordered.count + 8 + GrantOptIn.allCases.count)
        #expect(Set(PrivacySettingsAction.allDeclared).count
            == PrivacySettingsAction.allDeclared.count)
    }

    /// **The two disclosure sentences are declared among the strings the pane draws**
    /// (F-122, F-137, focus-6n2), so the catalog-completeness suite and the reachability lint
    /// both see them and neither can be a key nothing says.
    @Test("the pane declares both disclosure sentences")
    func theContentKeysCarryTheDisclosures() {
        let keys = Set(PrivacySettingsView.contentKeys)
        #expect(keys.contains(.settingsPrivacyNoNetwork))
        #expect(keys.contains(.settingsPrivacyUpdateChecks))
        // And they are two sentences, not one said twice.
        #expect(ShellStringKey.settingsPrivacyNoNetwork != .settingsPrivacyUpdateChecks)
    }

    /// The order the pane draws is the order the type commits to, shortest first.
    @Test("the control offers the windows shortest first, with forever last")
    func theOrderIsCommitted() {
        #expect(RetentionWindow.ordered == [.sevenDays, .thirtyDays, .ninetyDays, .forever])
        #expect(RetentionWindow.ordered.map(\.storedDays) == [7, 30, 90, 0])
        #expect(RetentionWindow.ordered.last == .forever)
    }
}
