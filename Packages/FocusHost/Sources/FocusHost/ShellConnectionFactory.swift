import FocusCore
import FocusUI
import Foundation

/// **The two connections the shell's windows are drawn from** (focus-2er, focus-h7h, focus-tzj.6).
///
/// A window used to read five properties off the composition root and pass them as five
/// arguments, each of which was a compiling one-line no-op away from a frozen placeholder in a
/// file no test bundle could import. Now it asks once, for one value, and every read is here —
/// beside the record of what was handed over, so that "what I gave you" and "what you drew" are
/// written down in one place and cannot drift apart.
///
/// Static over the root rather than a method on it, and the root is a parameter rather than a
/// stored property: the closures inside a connection capture the root **weakly**, exactly as they
/// did when they captured `self`, so a connection a window is still holding can never be the
/// reason a root outlives its process. `AppComposition.cockpitConnection()` and
/// `settingsConnection()` remain the public doors, so no scene, test or self-check reading moves.
@MainActor
enum ShellConnectionFactory {
    /// **Everything the cockpit window draws, as one value the scene cannot fabricate**
    /// (focus-2er).
    ///
    /// The scene used to read five properties off the root and pass them as five arguments,
    /// each of which was a compiling one-line no-op away from a frozen placeholder in a file no
    /// test bundle can import. Now it asks once. The five reads are here, where
    /// `AppCompositionConnectionTests` asserts every one of them against the live host, and the
    /// call itself is recorded — so a scene that stops asking fails the gate by name.
    static func cockpit(for root: AppComposition) -> CockpitConnection {
        root.note(.cockpitConnected)

        // Read once, into local values, and hand the **same** values to the window and to the
        // expectation (focus-h7h). Reading them twice — once for the connection and once for the
        // record — would make the comparison a race: `sessionElapsedSeconds` is taken from the
        // wall clock at the moment somebody asks, so two reads a few microseconds apart can
        // differ by a whole second at a boundary, and the gate would fail on the passage of time.
        let state = root.cockpitState
        let elapsed = root.sessionElapsedSeconds
        let actions = root.cockpitActions
        // The session host is the app's only `SessionActing`, and it is what the cockpit's
        // session controls and the four e03 menu commands both call — one code path for a click
        // and for a key equivalent.
        let sessions = root.sessionActions
        let generation = root.nextGeneration(for: .cockpit)

        root.expect(.priorityIntent, state.priority?.intent ?? "", for: .cockpit)
        root.expect(.priorityDetail, ShellValueDigest.describe(state.priority), for: .cockpit)
        root.expect(.status, state.status.rawValue, for: .cockpit)
        // The **string key** the footer's label was given, not the flag behind it. A boolean flip
        // told the person their store was unavailable when it was fine, and the flag alone would
        // have been reported truthfully by a footer drawing the opposite sentence (focus-7ow).
        //
        // **Three keys, not two** (focus-tzj.4). The footer tells "the store never opened" from
        // "the last write was refused" now, and this audit has to expect what the footer draws
        // or it would be green over a footer drawing the wrong one of the three.
        let expectedStoreKey: ShellStringKey =
            if !state.storeOpened {
                .cockpitStoreUnavailable
            } else if state.lastWriteFailed {
                .cockpitStoreWriteFailed
            } else {
                .cockpitStoreReady
            }
        root.expect(.storeStatus, expectedStoreKey.rawValue, for: .cockpit)
        // The banner is on screen when the state asks for it **and** a host can dismiss it.
        // The window draws that conjunction and reports what it drew; this expects the half that
        // can actually vary, because `cockpitActions` is non-optional — the root has no way to
        // hand over a cockpit with no mutation host, and `state.showsRitualPrompt && actions !=
        // nil` was a comparison the compiler could see was always true (focus-zrs). A connection
        // built with `actions: nil` still reports "hidden" against this "shown", which is the
        // asymmetry the check is for.
        root.expect(
            .ritualBanner,
            state.showsRitualPrompt ? "shown" : "hidden",
            for: .cockpit
        )
        root.expect(.recentCount, String(state.recent.count), for: .cockpit)
        root.expect(.recentDigest, ShellValueDigest.describe(state.recent), for: .cockpit)
        root.expect(.handoffTask, state.pendingHandoff?.task ?? "", for: .cockpit)
        root.expect(.handoffDetail, ShellValueDigest.describe(state.pendingHandoff), for: .cockpit)
        // **The commitment sections, which the window draws only while there is one.** The window
        // reports `noCommitment` for each of them when there is not, so a section somebody
        // deleted and a section there was nothing to draw stay two different readings.
        let hasCommitment = state.priority != nil
        root.expect(
            .priorityDoneWhen,
            hasCommitment
                ? (state.priority?.doneWhen ?? "")
                : ShellRenderedValues.noCommitment,
            for: .cockpit
        )
        root.expect(
            .sessionPhase,
            hasCommitment
                ? (state.session?.phase.rawValue ?? "none")
                : ShellRenderedValues.noCommitment,
            for: .cockpit
        )
        root.expect(
            .sessionDetail,
            hasCommitment
                ? ShellValueDigest.describe(state.session)
                : ShellRenderedValues.noCommitment,
            for: .cockpit
        )
        root.expect(
            .sessionElapsedSeconds,
            hasCommitment
                ? (elapsed.map { String(Int($0)) } ?? "none")
                : ShellRenderedValues.noCommitment,
            for: .cockpit
        )
        root.expect(
            .lastActiveApp,
            hasCommitment
                ? (root.lastActiveBundleID ?? "none")
                : ShellRenderedValues.noCommitment,
            for: .cockpit
        )
        root.expect(
            .launchAtLoginOffer,
            state.showsLaunchAtLoginOffer ? "shown" : "hidden",
            for: .cockpit
        )
        root.expect(
            .firstRunExplanation,
            state.showsFirstRunExplanation ? "shown" : "hidden",
            for: .cockpit
        )
        root.expect(.capabilityStates, state.capabilities.renderedDescription, for: .cockpit)
        root.expect(.sensingDetail, ShellValueDigest.describe(state.sensing), for: .cockpit)
        root.expect(
            .sensingSummary,
            SensingStatusView.renderedDescription(
                summary: state.sensing,
                capabilities: state.capabilities,
                showsReducedCapabilities: true
            ),
            for: .cockpit
        )
        // Both hosts are handed over, always. A cockpit given neither draws every control
        // disabled and no capture field at all — a window that looks finished and does nothing.
        root.expect(.mutationHostsAttached, "priority/session", for: .cockpit)

        let connection = CockpitConnection(
            state: state,
            actions: actions,
            sessionActions: sessions,
            sessionElapsedSeconds: elapsed,
            lastActiveBundleID: root.lastActiveBundleID,
            onLaunchAtLoginOffer: { [weak root] action in root?.perform(action) },
            onFirstRunExplanationDismissed: { [weak root] in
                root?.dismissFirstRunScreen()
            },
            onWalkthroughContinued: { [weak root] in
                root?.startWalkthroughTour()
            },
            generation: generation,
            didRender: { [weak root] in root?.note(.cockpitRendered) },
            didDraw: { [weak root] values in root?.record(values, for: .cockpit) }
        )
        root.audit(connection, for: .cockpit)
        return connection
    }

    /// **Everything the Settings window draws and every verb it can perform**, in the same shape
    /// and for the same reason (focus-2er).
    ///
    /// Two of the epic's four acceptance mutations lived in the arguments this replaces:
    /// `onInterventionAction` gutted to `{ _ in }`, which under U-1 is what decides whether the
    /// app may speak, and the appearance store write deleted from a `Binding`'s setter written
    /// by hand in a scene body. Both are verbs on this object now.
    static func settings(for root: AppComposition) -> ShellSettingsConnection {
        root.note(.settingsConnected)

        // The same values into the window and into the record, for the reason
        // `cockpitConnection()` reads its own once (focus-h7h).
        let preference = root.appearance.preference
        // What is being watched, and what this Mac lets the app do — read from the graph rather
        // than probed again for the occasion, so the Privacy pane and the cockpit's status line
        // are one answer rather than two opinions.
        let summary = root.sensingSummary
        let matrix = root.capabilities
        let currentVerdict = root.verdict
        let intervention = root.interventionSettings
        let generation = root.nextGeneration(for: .settings)

        let storeURL = FocusStore.applicationSupportURL
        // **The one bundle whose version means anything** (focus-odz.3). Read here rather than in
        // the pane, because `Bundle.main` in the unit lane is the test runner's and in a preview
        // is Xcode's — a pane that read its own would draw a different answer in every lane that
        // looks at it, and the gate would be pinning the harness rather than the product.
        let version = AppVersion.rendered(bundle: .main)

        root.expect(.appearancePreference, preference.rawValue, for: .settings)
        root.expect(.appVersion, version, for: .settings)
        // **Read from the service, every time this pane is built** (D-12, focus-odz.4). Never a
        // stored `Bool`: somebody who removes the app from Login Items in System Settings has
        // changed the truth, and a switch answering from its own memory would go on saying "on".
        let launchAtLogin = LaunchAtLogin(status: root.loginItem.status)
        root.expect(.launchAtLoginStatus, launchAtLogin.status.rawValue, for: .settings)
        // **The two facts that had a launch reader and no writer** (focus-d3g). Read from the
        // store every time this value is built, for `launchAtLogin`'s reason: a control answering
        // from its own memory would go on saying "on" after a delete-everything. The shortcut is
        // `storedHotKeySpec()`'s own answer rather than the raw columns, so the picker draws the
        // combination the platform was actually told rather than one an unregistrable row claims.
        let ritualEnabled = root.ritualEnabled
        let shortcut = root.storedHotKeySpec()
        root.expect(.ritualEnabled, ritualEnabled ? "on" : "off", for: .settings)
        root.expect(.quickCaptureShortcut, shortcut.glyphs, for: .settings)
        // **The update status, read once and expected whole** (focus-h8jf). Once, because the
        // updater's manual-check availability can move between two reads, and the receipt has to
        // be about the value the pane was handed.
        let softwareUpdates = root.softwareUpdateStatus
        root.expect(.softwareUpdates, ShellValueDigest.describe(softwareUpdates), for: .settings)
        root.expect(.privacyCapabilities, matrix.renderedDescription, for: .settings)
        // Where the Privacy pane tells the person their data lives, and what its Reveal in Finder
        // button opens. A mutation printed `/` and nothing anywhere noticed (focus-7ow).
        root.expect(.privacyStorePath, storeURL.path(percentEncoded: false), for: .settings)
        // **How long the app keeps what it wrote down** (F-115, focus-l7n). Read from the store
        // every time this value is built, for `ritualEnabled`'s reason — and expected as the
        // stored day count, which is the number the sweep reads rather than the button's word.
        let retention = FocusStore.privacyPreferences(in: root.modelContainer.mainContext).retention
        root.expect(.retentionWindow, String(retention.storedDays), for: .settings)
        root.expect(.verdictBand, currentVerdict?.band?.rawValue ?? "none", for: .settings)
        root.expect(.verdictDetail, ShellValueDigest.describe(currentVerdict), for: .settings)
        root.expect(.sensingDetail, ShellValueDigest.describe(summary), for: .settings)
        // **All seven fields of `InterventionSettings`** (focus-7ow). Two were expected before;
        // the other five could be replaced with anything at all while the gate stayed green, and
        // they are what the person is shown when they ask what this app will do to them.
        root.expect(.interventionVoice, intervention.voice.rawValue, for: .settings)
        root.expect(
            .reducedInterruption,
            intervention.reducedInterruption ? "on" : "off",
            for: .settings
        )
        root.expect(
            .reducedInterruptionForced,
            intervention.reducedInterruptionIsForced ? "forced" : "chosen",
            for: .settings
        )
        root.expect(.quietHours, ShellValueDigest.describe(intervention.quietHours), for: .settings)
        root.expect(.interruptionUsage, ShellValueDigest.describe(intervention.usage), for: .settings)
        root.expect(.policyTunings, ShellValueDigest.describe(intervention.tunings), for: .settings)
        root.expect(.sensingSettings, ShellValueDigest.describe(root.sensingHost.settings), for: .settings)
        root.expect(.grantOptIns, ShellValueDigest.describe(root.grantOptIns), for: .settings)
        // e08a. The refusal's own name, or `landed` — the same vocabulary the self-check
        // publishes, so the pane's receipt and the report cannot say two different words about
        // one display.
        root.expect(
            .notchCompanion,
            InterventionSettingsView.notchReceipt(intervention.notchRefusal),
            for: .settings
        )
        // **The exclusion list, and how many applications the add row offered** (F-121,
        // focus-62o, focus-u3w). Expected as the section's own rendering, so a pane handed the
        // list and drawing something else is visible to the receipt.
        root.expect(
            .presentationExclusions,
            PresentationExclusionSection.rendered(
                excluded: intervention.presentationExclusions,
                addable: intervention.addableApplications
            ),
            for: .settings
        )
        // Which pane is in front. The window reports it, and it is what makes the other readings
        // legible: a value missing because its pane was never selected is a different thing from
        // a value missing because the pane drew nothing.
        root.expect(.settingsTab, root.settingsTab.rawValue, for: .settings)
        // The Privacy pane draws the working as well as the sentence, which is what
        // `showsDetail` turns on — and it is what tells this field apart from the cockpit's.
        root.expect(
            .privacySummary,
            SensingStatusView.renderedDescription(
                summary: summary,
                capabilities: matrix,
                showsReducedCapabilities: false
            ),
            for: .settings
        )

        let connection = ShellSettingsConnection(
            preference: preference,
            setPreference: { [weak root] preference in
                root?.applyAppearancePreference(preference)
            },
            storeURL: storeURL,
            appVersion: version,
            launchAtLogin: launchAtLogin,
            ritualEnabled: ritualEnabled,
            quickCaptureShortcut: shortcut,
            summary: summary,
            capabilities: matrix,
            verdict: currentVerdict,
            intervention: intervention,
            onInterventionAction: { [weak root] action in root?.perform(action) },
            onLaunchAtLogin: { [weak root] action in root?.perform(action) },
            onCaptureAction: { [weak root] action in root?.perform(action) },
            retention: retention,
            sensing: root.sensingHost.settings,
            grants: root.grantOptIns,
            onPrivacyAction: { [weak root] action in root?.perform(action) },
            selectedTab: root.settingsTab,
            selectTab: { [weak root] tab in root?.selectSettingsTab(tab) },
            generation: generation,
            didRender: { [weak root] in root?.note(.settingsRendered) },
            didDraw: { [weak root] rendering in
                guard let root else { return }
                root.record(rendering.values, for: .settings)
                // **The two sinks the pane is actually holding**, kept so the self-check can
                // drive them and watch this object's own graph move. They cannot be pressed:
                // no lane in this programme holds the Accessibility grant it would take to
                // click a picker, which is exactly why `{ _ in }` in their place survived two
                // rounds of gates.
                root.noteSettingsRendering(rendering)
            },
            softwareUpdates: softwareUpdates,
            onSoftwareUpdateAction: { [weak root] action in root?.perform(action) }
        )
        root.audit(connection, for: .settings)
        return connection
    }
}
