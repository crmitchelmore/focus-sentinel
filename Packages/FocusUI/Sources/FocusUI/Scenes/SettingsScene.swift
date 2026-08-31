import AppKit
import FocusCore
import SwiftUI

/// The tabs the Settings window offers.
///
/// Three from e05, and all three are full. No "coming soon" pane, no empty tab reserved for a
/// feature that does not exist: a surface ships when it has content, not before — which is why
/// the Intervention tab arrives in the epic that gives it something to configure rather than in
/// the one that first imagined it.
public enum SettingsTab: String, Sendable, CaseIterable, Hashable, Identifiable {
    case general
    case intervention
    case privacy

    public var id: String { rawValue }

    public var titleKey: ShellStringKey {
        switch self {
        case .general: .settingsGeneralTitle
        case .intervention: .interventionTitle
        case .privacy: .settingsPrivacyTitle
        }
    }

    /// The tab's SF Symbol. Standard Settings chrome draws these above the tab titles.
    public var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .intervention: "bell.badge"
        case .privacy: "hand.raised"
        }
    }
}

/// **Everything the Settings scene hands the Settings window, as one value** (focus-2er).
///
/// The scene passed seven separate arguments and built a `Binding` by hand, all inside a view
/// body in `App/` — which is not a package, so no test bundle can reach any of it. Two of the
/// epic's four acceptance mutations lived there and survived the whole gate: replacing
/// `onInterventionAction` with `{ _ in }`, which is what decides whether the app may speak at
/// all under U-1, and deleting the store write from the appearance binding's setter, so the
/// person's choice was forgotten the moment they quit.
///
/// Both are now `FocusHost` verbs on this value, assembled by `AppComposition.settingsConnection()`
/// where `AppCompositionSettingsTests` drives them, and the `Binding` is built here in `FocusUI`
/// rather than in a scene. What is left in `App/` is one argument that cannot be fabricated with
/// a placeholder — it carries two closures only the composition root can supply — and one
/// `.task`.
@MainActor
public struct ShellSettingsConnection {
    /// The appearance the person last chose, as the observer currently holds it.
    public let preference: AppearancePreference
    /// What a click on the Appearance picker performs: update the observer **and** write the
    /// store. One verb, in `FocusHost`, so there is nothing left in the scene to forget.
    public let setPreference: @MainActor (AppearancePreference) -> Void
    public let storeURL: URL
    public let summary: SensingSummary
    public let capabilities: CapabilityMatrix
    public let verdict: VerdictSnapshot?
    public let intervention: InterventionSettings
    /// What the Intervention pane's controls reach. Under U-1 this is what decides whether the
    /// app may speak, and it was `{ _ in }`-able in a file no lane could read.
    public let onInterventionAction: @MainActor (InterventionSettingsAction) -> Void
    /// **Which pane is on screen, decided by the composition root** (focus-7ow).
    ///
    /// A macOS `TabView` builds only the selected pane. Measured on the first run of the render
    /// receipts: the Privacy pane's own stamps never arrived at all, because nobody had clicked
    /// Privacy — so every value reported about the Settings window had to be reported from the
    /// *window*, in the same expression that constructs each pane, and a defect **inside** an
    /// unselected pane was invisible to every lane in the programme.
    ///
    /// Driving the selection from the root closes that: the self-check selects each pane in turn,
    /// each pane reports what it drew, and the reports accumulate against one issue of this
    /// connection.
    public let selectedTab: SettingsTab
    /// What a click on a tab performs. The root holds the selection, for the reason it holds the
    /// appearance preference: a `@State` in a window body is a value no lane can read.
    public let selectTab: @MainActor (SettingsTab) -> Void
    /// Called from the window's body: the far end of the scene's one wire.
    public let didRender: @MainActor () -> Void

    /// Which issue of this connection the window is drawing from (focus-h7h). See
    /// `CockpitConnection.generation`.
    public let generation: Int

    /// **What the window drew, and the two sinks its controls will actually reach**
    /// (focus-h7h).
    ///
    /// The values half is the preference channel, as everywhere else. The two closures are the
    /// half that could not be done any other way: `setPreference` and `onInterventionAction` are
    /// only ever called by a **click**, and no lane in this programme holds the Accessibility
    /// grant it would take to press a button headlessly — which is exactly why `{ _ in }` in
    /// their place survived two rounds of gates. So the window hands back the closures it is
    /// holding, and the composition root drives them itself and watches its own graph move. A
    /// sink that was replaced with a no-op reaches nothing, and the graph does not move.
    public let didDraw: @MainActor (ShellSettingsRendering) -> Void

    public init(
        preference: AppearancePreference,
        setPreference: @escaping @MainActor (AppearancePreference) -> Void,
        storeURL: URL,
        summary: SensingSummary,
        capabilities: CapabilityMatrix,
        verdict: VerdictSnapshot?,
        intervention: InterventionSettings,
        onInterventionAction: @escaping @MainActor (InterventionSettingsAction) -> Void,
        selectedTab: SettingsTab = .general,
        selectTab: @escaping @MainActor (SettingsTab) -> Void = { _ in },
        generation: Int = 0,
        didRender: @escaping @MainActor () -> Void = {},
        didDraw: @escaping @MainActor (ShellSettingsRendering) -> Void = { _ in }
    ) {
        self.preference = preference
        self.setPreference = setPreference
        self.storeURL = storeURL
        self.summary = summary
        self.capabilities = capabilities
        self.verdict = verdict
        self.intervention = intervention
        self.onInterventionAction = onInterventionAction
        self.selectedTab = selectedTab
        self.selectTab = selectTab
        self.generation = generation
        self.didRender = didRender
        self.didDraw = didDraw
    }
}

/// **Every field of the Settings connection, bound to the receipt that echoes it** (focus-7ow).
///
/// `intervention` descends, because the pane draws its six fields as six controls and four of
/// them — quiet hours, usage, the exclusion list, and whether Reduce Motion forced the switch —
/// were carried into a window that reported two of them.
extension ShellSettingsConnection: ShellDrawnConnection {
    public nonisolated static var connectionName: String { "ShellSettingsConnection" }

    public nonisolated static var fieldEchoes: [String: ShellFieldEcho] {
        [
            "preference": .drawn([.appearancePreference]),
            "setPreference": .undrawn(.sink),
            "storeURL": .drawn([.privacyStorePath]),
            "summary": .drawn([.privacySummary, .sensingDetail]),
            "capabilities": .drawn([.privacyCapabilities]),
            "verdict": .drawn([.verdictBand, .verdictDetail]),
            "intervention": .composite,
            "onInterventionAction": .undrawn(.sink),
            "selectedTab": .drawn([.settingsTab]),
            "selectTab": .undrawn(.sink),
            "generation": .undrawn(.generation),
            "didRender": .undrawn(.receipt),
            "didDraw": .undrawn(.receipt),

            "intervention.voice": .drawn([.interventionVoice]),
            "intervention.reducedInterruption": .drawn([.reducedInterruption]),
            "intervention.reducedInterruptionIsForced": .drawn([.reducedInterruptionForced]),
            "intervention.quietHours": .drawn([.quietHours]),
            "intervention.usage": .drawn([.interruptionUsage]),

            // --- one level down, and then to the leaves (focus-cxs) ------------------------
            //
            // Round 6 closed this boundary at the connection struct and named its own residue:
            // *"deeper structs are leaves"*. A `.drawn` binding stopped the walk, so a field
            // invented inside `InterventionSettings.usage` or inside `VerdictSnapshot` was reached
            // by nothing — and the whole-value digest that was meant to cover it is computed on
            // both sides from the same input, so it does not participate in the comparison either.
            //
            // The digest genuinely does contain every field below (`ShellValueDigest.describe` is
            // `Mirror` to the leaves), so these bindings are true. What they buy is **totality**:
            // a field added tomorrow has no line here, and a path with no line is a failure.
            "summary.isObserving": .drawn([.privacySummary, .sensingDetail]),
            "summary.isPausedByUser": .drawn([.privacySummary, .sensingDetail]),
            "summary.liveObserverCount": .drawn([.privacySummary, .sensingDetail]),
            "summary.redundantActivations": .drawn([.sensingDetail]),
            "summary.lifecycle": .drawn([.sensingDetail]),
            "summary.isUserIdle": .drawn([.sensingDetail]),
            "summary.media": .drawn([.sensingDetail]),
            "summary.media.microphoneRunning": .drawn([.sensingDetail]),
            "summary.media.cameraRunning": .drawn([.sensingDetail]),
            "summary.cameraReason": .drawn([.sensingDetail]),
            "summary.presentation": .drawn([.sensingDetail]),
            "summary.presentation.signals": .drawn([.sensingDetail]),
            "summary.presentation.signals.frontmostWindowFillsAScreen": .drawn([.sensingDetail]),
            "summary.presentation.signals.presentationOptionsSayFullScreen": .drawn([.sensingDetail]),
            "summary.presentation.signals.menuBarHidden": .drawn([.sensingDetail]),
            "summary.presentation.isUserExcluded": .drawn([.sensingDetail]),
            "summary.presentation.isPresenting": .drawn([.sensingDetail]),
            "summary.isOnSecondaryDisplay": .drawn([.sensingDetail]),

            // The matrix's one stored property. `CapabilityMatrix.renderedDescription` names every
            // capability and the state the pane drew it in.
            "capabilities.observations": .drawn([.privacyCapabilities]),

            // The inspector draws the band as its own row and the rest through the digest.
            "verdict.status": .drawn([.verdictDetail]),
            "verdict.stage": .drawn([.verdictDetail]),
            "verdict.band": .drawn([.verdictBand, .verdictDetail]),
            "verdict.drift": .drawn([.verdictDetail]),
            "verdict.eligibility": .drawn([.verdictDetail]),
            "verdict.explanation": .drawn([.verdictDetail]),
            // The inspector draws the explanation clause by clause; the digest carries the whole
            // of it, including which rung and which band produced the sentence.
            "verdict.explanation.stage": .drawn([.verdictDetail]),
            "verdict.explanation.band": .drawn([.verdictDetail]),
            "verdict.explanation.clauses": .drawn([.verdictDetail]),
            "verdict.explanation.stamp": .drawn([.verdictDetail]),
            // The engine stamp's seven components. `verdict.stampKey` above is the *cache key* it
            // reduces to — a different value, and one that can agree while a component underneath
            // it does not, which is why both are bound rather than one standing in for the other.
            "verdict.explanation.stamp.schemaVersion": .drawn([.verdictDetail]),
            "verdict.explanation.stamp.policyVersion": .drawn([.verdictDetail]),
            "verdict.explanation.stamp.lexiconVersion": .drawn([.verdictDetail]),
            "verdict.explanation.stamp.embeddingRevision": .drawn([.verdictDetail]),
            "verdict.explanation.stamp.promptVersion": .drawn([.verdictDetail]),
            "verdict.explanation.stamp.interventionVersion": .drawn([.verdictDetail]),
            "verdict.explanation.stamp.interventionDigest": .drawn([.verdictDetail]),
            "verdict.stampKey": .drawn([.verdictDetail]),

            "intervention.quietHours.startMinuteOfDay": .drawn([.quietHours]),
            "intervention.quietHours.endMinuteOfDay": .drawn([.quietHours]),
            "intervention.usage.queriesForPriorityToday": .drawn([.interruptionUsage]),
            "intervention.usage.queriesAllPrioritiesToday": .drawn([.interruptionUsage]),
            // **There is no `intervention.usage.interruptionsToday` here, and its absence is the
            // point** (focus-d6r). This map is a map of *stored properties* — the walk is
            // `Mirror` over the compiled type, and its whole claim is that it "knows only what
            // the type has". `InterruptionBudget.interruptionsToday` stopped being a field and
            // became an arithmetic: it is `queriesAllPrioritiesToday + accusationsToday`, so that
            // a day on which the shared budget is spent and neither counter has moved has no
            // spelling. An echo for it would be `strandedPaths`, which is this reading's name for
            // *"the map has drifted"* — and it did drift, which is how the totality lane caught
            // the change.
            //
            // The row it draws is not unwatched. All four usage rows report through the one
            // `ShellRenderedField.interruptionUsage`, which `ShellRenderFidelity` still compares,
            // and the two counters the fourth row is computed from are mapped immediately above
            // and below.
            "intervention.usage.accusationsToday": .drawn([.interruptionUsage])
        ]
    }
}

/// **What the Settings window drew, and what its controls are wired to** (focus-h7h).
///
/// Two halves, because the Settings window has two kinds of thing that can silently stop working
/// and only one of them is visible. What the panes *show* is a value, reported through the
/// preference channel like every other window's. What the panes *do* is a closure nobody can
/// press without a grant — so it is handed back, and driven.
@MainActor
public struct ShellSettingsRendering {
    /// Everything the three panes reported drawing.
    public let values: ShellRenderedValues
    /// What the General pane's Appearance picker writes through — the binding's own setter,
    /// which is the path a click takes and nothing beside it.
    ///
    /// Plain closures rather than `@Sendable` ones: this whole type is `@MainActor`, so there is
    /// nowhere else they can be called from, and requiring `@Sendable` would mean the view could
    /// not hand back the very closure its controls hold — which is the only thing this type is
    /// for.
    public let setPreference: (AppearancePreference) -> Void
    /// What the Intervention pane's Voice and Reduced-Interruption controls reach.
    public let onInterventionAction: (InterventionSettingsAction) -> Void

    public init(
        values: ShellRenderedValues,
        setPreference: @escaping (AppearancePreference) -> Void,
        onInterventionAction: @escaping (InterventionSettingsAction) -> Void
    ) {
        self.values = values
        self.setPreference = setPreference
        self.onInterventionAction = onInterventionAction
    }
}

/// The Settings window: standard chrome, a toolbar-style tab switcher, each pane sized to
/// its own content.
///
/// Reached by ⌘, and by `Settings…` in the app menu — both of which SwiftUI provides for
/// free from the `Settings` scene, which is exactly why the app declares one rather than
/// building a preferences window by hand.
public struct ShellSettingsView: View {
    /// The traits the window resolved, so it can report which ones actually reached it
    /// (focus-h7h). Read from the environment rather than from the connection, because the
    /// injection is a separate wire from the connection and is separately guttable.
    @Environment(\.appearanceTraits) private var traits

    @Binding private var preference: AppearancePreference
    private let storeURL: URL
    private let summary: SensingSummary
    private let capabilities: CapabilityMatrix
    private let verdict: VerdictSnapshot?
    private let intervention: InterventionSettings
    private let onInterventionAction: (InterventionSettingsAction) -> Void
    /// Which pane is on screen. A `Binding` over the composition root's own value, never a
    /// `@State`: the root drives it so each pane can be made to draw and report (focus-7ow).
    @Binding private var selectedTab: SettingsTab
    /// What the window reports when its body is evaluated. `nil` for every caller that builds
    /// it out of loose values — the snapshot lane, the preview, the unit tests.
    private let didRender: (@MainActor () -> Void)?

    /// Which issue of the connection this window is drawing from, and where what it drew is
    /// delivered (focus-h7h).
    private let generation: Int
    private let didDraw: (@MainActor (ShellSettingsRendering) -> Void)?

    public init(
        preference: Binding<AppearancePreference>,
        storeURL: URL,
        summary: SensingSummary = .inactive,
        capabilities: CapabilityMatrix = CapabilityMatrix(),
        verdict: VerdictSnapshot? = nil,
        intervention: InterventionSettings = InterventionSettings(),
        onInterventionAction: @escaping (InterventionSettingsAction) -> Void = { _ in },
        selectedTab: Binding<SettingsTab> = .constant(.general)
    ) {
        self._preference = preference
        self.storeURL = storeURL
        self.summary = summary
        self.capabilities = capabilities
        self.verdict = verdict
        self.intervention = intervention
        self.onInterventionAction = onInterventionAction
        self._selectedTab = selectedTab
        self.didRender = nil
        self.generation = 0
        self.didDraw = nil
    }

    /// **The application scene's initialiser, and the only one it can reach** (focus-2er).
    ///
    /// The `Binding` the Appearance picker writes through is built **here**, from the
    /// connection's value and its verb, rather than by hand in a scene body no lane can read.
    /// That is what moves the store write out of `App/`: the setter is one closure the
    /// composition root supplies, and a scene has nothing left to get wrong.
    public init(connection: ShellSettingsConnection) {
        self._preference = Binding(
            get: { connection.preference },
            set: { connection.setPreference($0) }
        )
        self.storeURL = connection.storeURL
        self.summary = connection.summary
        self.capabilities = connection.capabilities
        self.verdict = connection.verdict
        self.intervention = connection.intervention
        self.onInterventionAction = connection.onInterventionAction
        self._selectedTab = Binding(
            get: { connection.selectedTab },
            set: { connection.selectTab($0) }
        )
        self.didRender = connection.didRender
        self.generation = connection.generation
        self.didDraw = connection.didDraw
    }

    public var body: some View {
        // The far end of the scene's one wire (focus-2er), for the reason `CockpitView`'s is
        // where it is: a scene that asked the composition root and then drew something else must
        // fail the same assertion as one that never asked.
        let _ = didRender?()
        TabView(selection: $selectedTab) {
            GeneralSettingsView(preference: $preference)
                .tabItem { tabLabel(.general) }
                .tag(SettingsTab.general)

            InterventionSettingsView(
                settings: intervention,
                onAction: onInterventionAction
            )
            .tabItem { tabLabel(.intervention) }
            .tag(SettingsTab.intervention)

            PrivacySettingsView(
                storeURL: storeURL,
                summary: summary,
                capabilities: capabilities,
                verdict: verdict
            )
            .tabItem { tabLabel(.privacy) }
            .tag(SettingsTab.privacy)
        }
        .frame(minWidth: 460, minHeight: 520)
        // **The values are reported by the panes now, not by this window** (focus-7ow).
        //
        // They used to be reported here, and the reason was measured: a macOS `TabView` builds
        // only the selected pane, so on the first run of this mechanism the Privacy pane's own
        // stamps never arrived at all because nobody had clicked Privacy. Reporting from the
        // window bought coverage of the *arguments* at the price of the panes themselves — a
        // defect inside an unselected pane was invisible to every lane in the programme, and a
        // mutation that handed the Privacy pane `URL(fileURLWithPath: "/")` was reported as the
        // truth by a window stamping its own `storeURL`.
        //
        // So the selection is the composition root's, the self-check walks all three panes, and
        // each pane reports the values **it** drew. What is left here is the one fact only the
        // window knows — which pane is in front — and the traits it resolved.
        .shellRendered(.settingsTab, selectedTab.rawValue)
        // Escape backs out of Settings, which is what `CancelBehaviour.dismissWindow`
        // declares for both panes and what a Mac user expects of a preferences window.
        .onExitCommand {
            NSApp.keyWindow?.performClose(nil)
        }
        // The traits this window resolved out of its own environment — the far end of the
        // Settings scene's own `.appearanceTraits` injection, which is a third wire and was
        // separately guttable (focus-h7h).
        .shellRendered(.appearanceTraits, traits.renderedDescription)
        // **The collection point, and the two sinks handed back with it** (focus-h7h).
        //
        // `$preference.wrappedValue = $0` is the path a click on the Appearance picker takes and
        // nothing beside it: the binding this view holds, whose setter is the connection's
        // `setPreference`. `onInterventionAction` is the closure the Intervention pane's controls
        // were actually given. Neither can be pressed by a lane with no Accessibility grant, so
        // the composition root drives them and watches its own graph move.
        .environment(\.shellRenderGeneration, generation)
        .onPreferenceChange(ShellRenderedValuesKey.self) { values in
            MainActor.assumeIsolated {
                didDraw?(
                    ShellSettingsRendering(
                        values: values,
                        setPreference: { preference = $0 },
                        onInterventionAction: onInterventionAction
                    )
                )
            }
        }
    }

    private func tabLabel(_ tab: SettingsTab) -> some View {
        Label {
            ShellText(tab.titleKey)
        } icon: {
            Image(systemName: tab.systemImage)
        }
    }
}
