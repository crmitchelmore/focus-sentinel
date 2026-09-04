import FocusCore
import Foundation
import SwiftUI

/// Where every user-visible string in the shell comes from.
///
/// `FocusUI` owns a String Catalog of its own (`Sources/FocusUI/Resources/Localizable.xcstrings`)
/// and every key in it is resolved through here, against this package's bundle rather than
/// the app's. That matters twice over: the views work identically whether they are hosted by
/// the app or by a test process, and the snapshot lane can render them without an app bundle
/// existing at all.
public enum ShellStrings {
    /// This package's resource bundle — where the compiled catalog lives.
    ///
    /// Exposed because the localisation tests need to ask the *package* what a key resolves
    /// to, and `Bundle.module` inside a test target means the test bundle, not this one.
    public static var bundle: Bundle { .module }

    /// A catalog entry, as a resource the UI can draw.
    public static func resource(_ key: ShellStringKey) -> LocalizedStringResource {
        LocalizedStringResource(
            String.LocalizationValue(key.rawValue),
            bundle: .atURL(bundle.bundleURL)
        )
    }

    /// A catalog entry, resolved to a plain `String`.
    ///
    /// Under `swift test` this returns the key itself, because SwiftPM copies String
    /// Catalogs instead of compiling them. That is exactly the trap `LocalizationLane`
    /// exists to gate assertions on — see `FocusCore.LocalizationLane`.
    public static func string(_ key: ShellStringKey) -> String {
        String(localized: resource(key))
    }

    /// A catalog entry with **one** argument — the user's own words, and nothing else.
    ///
    /// This is the whole of standing condition 4's mechanism for the refinement strip: the
    /// sentence around the suggestion is authored, translated text from the catalog, and the
    /// only thing substituted into it is a phrase the user typed. No prose is composed at
    /// runtime, by a model or by anything else, here or in e06.
    public static func string(_ key: ShellStringKey, argument: String) -> String {
        String(format: string(key), argument)
    }
}

/// Every user-visible string `FocusUI` owns, as a typed key.
///
/// One enum rather than literals scattered through the views, for three reasons: the string
/// lint can find every key by reading this file, the catalog-completeness test can iterate
/// `allCases` instead of hardcoding a list, and a key can never be misspelled at a call site
/// without the compiler saying so.
public enum ShellStringKey: String, Sendable, CaseIterable, Hashable {
    // Window titles
    case cockpitWindowTitle = "shell.window.cockpit.title"
    case helpWindowTitle = "shell.window.help.title"
    /// e09a. The ledger of what the app did today, reached from the cockpit and the View menu —
    /// deliberately a window rather than a sidebar row (the shell has two destinations and no
    /// split view; see `CommandRegistry.shell`).
    case historyWindowTitle = "shell.window.history.title"

    // Menu commands
    case commandCloseWindow = "shell.command.closeWindow"
    case commandHelp = "shell.command.help"
    case commandNewPriority = "shell.command.newPriority"
    case commandAddFilesToContext = "shell.command.addFilesToContext"
    /// The app menu's About item, replacing SwiftUI's — which draws a title this app's catalog
    /// does not own and opens a panel with nothing in it (focus-odz.3).
    case commandAbout = "shell.command.about"
    /// F-119's switch, as a menu verb. The cockpit's control reads positively ("Watch what I
    /// am working on"); a menu item has to name the *act*, so this one does.
    case commandPauseSensing = "shell.command.pauseSensing"
    // The e05 verbs. "Pause" and "Change priority" are deliberately absent: they are
    // `shell.command.*` entries this registry already has, under the names the rest of the app
    // uses for them.
    case commandThisIsRelevant = "shell.command.thisIsRelevant"
    case commandSnoozeNudge = "shell.command.snoozeNudge"
    case commandHideOverlays = "shell.command.hideOverlays"
    case commandShowMenuBar = "shell.command.showMenuBar"
    // The e07a verbs: a question's three answers, from the View menu, because the panel that
    // draws them can never carry a keystroke (see `CommandRegistry.shell`).
    case commandAnswerYes = "shell.command.answerYes"
    case commandAnswerNo = "shell.command.answerNo"
    case commandAnswerNotNow = "shell.command.answerNotNow"
    // e09a: History, in the View menu beside the other things a person can look at.
    case commandShowHistory = "shell.command.showHistory"

    // History (e09a) — what the app did today, and the one place a person can say
    // *you were wrong to stay quiet*.
    case historyHeading = "shell.history.heading"
    case historyIntroduction = "shell.history.introduction"
    /// The sentence that stops the surface implying a person was shown these words at the time.
    /// `PriorityTask.revision` counts edits and keeps no prior text, so today's wording is all
    /// there is — and saying so is the difference between a record and a claim.
    case historyWordingNote = "shell.history.wordingNote"
    case historyEmpty = "shell.history.empty"
    /// `nil` explanation kinds: the app did not record why. **Not** "no reasons", which would be
    /// a claim about the verdict rather than about the record.
    case historyReasonNotRecorded = "shell.history.reasonNotRecorded"
    case historyAnswerLabel = "shell.history.answerLabel"
    /// What the person DID about an interruption, which is a different sentence from what they
    /// ANSWERED a question — "You said · You closed it" is not English.
    case historyOutcomeLabel = "shell.history.outcomeLabel"
    case historyUnderLabel = "shell.history.underLabel"
    case historyRowAccusation = "shell.history.rowAccusation"
    case historyRowQuestion = "shell.history.rowQuestion"
    case historyRowSession = "shell.history.rowSession"
    case historyRowSilence = "shell.history.rowSilence"
    case historyCorrectAction = "shell.history.correctAction"
    case historyCorrectionWritten = "shell.history.correctionWritten"

    // Cockpit
    case cockpitHeading = "shell.cockpit.heading"
    case cockpitStoreReady = "shell.cockpit.store.ready"
    /// **The store did not open at all.** Distinct from the line below, and the distinction is
    /// the whole of focus-tzj.4: one of these two states costs a person a day's work.
    case cockpitStoreUnavailable = "shell.cockpit.store.unavailable"
    /// The store opened and refused the last write. Transient, and what is on disk is intact.
    case cockpitStoreWriteFailed = "shell.cockpit.store.writeFailed"
    /// The About panel's credits paragraph (focus-odz.3).
    case aboutCredits = "shell.about.credits"
    // The first-run explanation, shown once on a store the app has never opened (focus-odz.7).
    case firstRunTitle = "shell.firstRun.title"
    case firstRunObserves = "shell.firstRun.observes"
    case firstRunNever = "shell.firstRun.never"
    case firstRunPermissions = "shell.firstRun.permissions"
    case firstRunStoreLabel = "shell.firstRun.storeLabel"
    case firstRunDismiss = "shell.firstRun.dismiss"
    // The cockpit's one-time launch-at-login offer (D-12, focus-odz.4).
    case cockpitLaunchAtLoginOffer = "shell.cockpit.launchAtLogin.offer"
    case cockpitLaunchAtLoginAccept = "shell.cockpit.launchAtLogin.accept"
    case cockpitLaunchAtLoginDismiss = "shell.cockpit.launchAtLogin.dismiss"
    case cockpitStoreSheetTitle = "shell.cockpit.store.sheet.title"
    case cockpitStoreSheetWhatHappened = "shell.cockpit.store.sheet.whatHappened"
    case cockpitStoreSheetLocation = "shell.cockpit.store.sheet.location"
    case cockpitStoreSheetConsequence = "shell.cockpit.store.sheet.consequence"
    case cockpitStoreSheetAcknowledge = "shell.cockpit.store.sheet.acknowledge"
    case cockpitOpenSettings = "shell.cockpit.openSettings"

    // The priority itself
    case priorityHeroEmpty = "priority.hero.empty"
    case priorityDoneWhenLabel = "priority.doneWhen.label"
    case priorityDoneWhenPrompt = "priority.doneWhen.prompt"
    case priorityActionComplete = "priority.action.complete"
    case priorityActionClear = "priority.action.clear"
    case priorityActionChange = "priority.action.change"
    case priorityActionEditIntent = "priority.action.editIntent"
    case priorityIntentEditLabel = "priority.intent.edit.label"
    case priorityIntentEditPrompt = "priority.intent.edit.prompt"
    case priorityTimeboxLabel = "priority.timebox.label"
    case priorityTimeboxNone = "priority.timebox.none"
    case priorityTimeboxRemaining = "priority.timebox.remaining"
    case priorityTimeboxOvertime = "priority.timebox.overtime"
    case priorityRulesHeading = "priority.rules.heading"
    case priorityRulesEmpty = "priority.rules.empty"
    case priorityRulesSubjectPrompt = "priority.rules.subject.prompt"
    case priorityRulesScopeApp = "priority.rules.scope.app"
    case priorityRulesScopeDomain = "priority.rules.scope.domain"
    case priorityRulesScopeTitleToken = "priority.rules.scope.titleToken"
    /// The caption a stored rule of a retired scope carries (e07a): kept, deletable, not read.
    case priorityRulesScopeRetired = "priority.rules.scope.retired"
    case priorityRulesScopeSession = "priority.rules.scope.session"
    case priorityRulesVerdictRelevant = "priority.rules.verdict.relevant"
    case priorityRulesVerdictUnrelated = "priority.rules.verdict.unrelated"
    case priorityRulesVerdictUncertain = "priority.rules.verdict.uncertain"
    case priorityRulesActionAddRelated = "priority.rules.action.addRelated"
    case priorityRulesActionAddUnrelated = "priority.rules.action.addUnrelated"
    case priorityRulesActionRemove = "priority.rules.action.remove"
    case priorityRecentHeading = "priority.recent.heading"
    case priorityRecentActionAgain = "priority.recent.action.again"
    case priorityRecentContextItems = "priority.recent.contextItems"
    case priorityRecentCompleted = "priority.recent.completed"
    case priorityRitualMessage = "priority.ritual.message"
    case priorityRitualActionSet = "priority.ritual.action.set"
    case priorityRitualActionDismiss = "priority.ritual.action.dismiss"
    case priorityCompleteHeading = "priority.complete.heading"
    case priorityCompleteShippedLabel = "priority.complete.shipped.label"
    case priorityCompleteShippedPrompt = "priority.complete.shipped.prompt"
    case priorityCompleteRestartLabel = "priority.complete.restart.label"
    case priorityCompleteRestartPrompt = "priority.complete.restart.prompt"
    case priorityCompleteNote = "priority.complete.note"
    case priorityCompleteActionConfirm = "priority.complete.action.confirm"
    case priorityCompleteActionCancel = "priority.complete.action.cancel"

    // Capture, and the deterministic refinement strip
    case captureFieldLabel = "capture.field.label"
    case captureFieldPrompt = "capture.field.prompt"
    case captureActionSet = "capture.action.set"
    case captureActionRefine = "capture.action.refine"
    case captureRefineHeading = "capture.refine.heading"
    case captureFindingNoLeadingVerb = "capture.finding.noLeadingVerb"
    case captureFindingTooShort = "capture.finding.tooShort"
    case captureFindingNounOnlyPhrase = "capture.finding.nounOnlyPhrase"
    case captureFindingNoOutcome = "capture.finding.noOutcome"
    case captureSuggestionStartWithVerb = "capture.suggestion.startWithVerb"
    case captureSuggestionSayMore = "capture.suggestion.sayMore"
    case captureSuggestionNameTheOutcome = "capture.suggestion.nameTheOutcome"
    case captureSuggestionDoneWhen = "capture.suggestion.doneWhen"
    case captureSuggestionDoneWhenLabel = "capture.suggestion.doneWhenLabel"
    case captureSuggestionUse = "capture.suggestion.use"
    case captureSuggestionKeep = "capture.suggestion.keep"
    case capturePanelTitle = "capture.panel.title"
    case capturePanelHint = "capture.panel.hint"

    // The focus:// handoff confirmation
    case handoffHeading = "handoff.confirm.heading"
    case handoffExplanation = "handoff.confirm.explanation"
    case handoffCurrentLabel = "handoff.confirm.current.label"
    case handoffCurrentNone = "handoff.confirm.current.none"
    case handoffIncomingLabel = "handoff.confirm.incoming.label"
    case handoffActionReplace = "handoff.confirm.action.replace"
    case handoffActionCancel = "handoff.confirm.action.cancel"
    case handoffFlagTaskTruncated = "handoff.flag.taskTruncated"
    case handoffFlagDoneWhenTruncated = "handoff.flag.doneWhenTruncated"
    case handoffFlagControlCharacters = "handoff.flag.controlCharacters"
    case handoffFlagDuplicateKeys = "handoff.flag.duplicateKeys"
    case handoffFlagUnknownItems = "handoff.flag.unknownItems"

    // The context pack
    case contextHeading = "context.pack.heading"
    case contextEmpty = "context.pack.empty"
    case contextKeywordPrompt = "context.keyword.prompt"
    case contextActionAddKeyword = "context.action.addKeyword"
    case contextActionAddFiles = "context.action.addFiles"
    case contextActionRemove = "context.action.remove"
    case contextActionLocate = "context.action.locate"
    case contextFileMissing = "context.file.missing"
    case contextAppNotInstalled = "context.app.notInstalled"
    case contextKindApp = "context.kind.app"
    case contextKindDomain = "context.kind.domain"
    case contextKindKeyword = "context.kind.keyword"
    case contextKindFile = "context.kind.file"
    case contextKindUnknown = "context.kind.unknown"

    // Keyboard shortcuts reference
    case helpHeading = "shell.help.heading"
    case helpIntroduction = "shell.help.introduction"
    case helpColumnAction = "shell.help.column.action"
    case helpColumnShortcut = "shell.help.column.shortcut"
    case helpGroupFile = "shell.help.group.file"
    case helpGroupHelp = "shell.help.group.help"
    /// The View menu's heading in the Keyboard Shortcuts window. e05 is the first epic to put
    /// an action in that menu, and the rule the registry test holds is that a populated
    /// placement is a named one.
    case helpGroupView = "shell.help.group.view"

    // Settings
    case settingsGeneralTitle = "settings.general.title"
    case settingsPrivacyTitle = "settings.privacy.title"
    case settingsAppearanceLabel = "settings.appearance.label"
    case settingsAppearanceMatchSystem = "settings.appearance.matchSystem"
    case settingsAppearanceLight = "settings.appearance.light"
    case settingsAppearanceDark = "settings.appearance.dark"
    case settingsAppearanceNote = "settings.appearance.note"
    /// The label beside the build a person is looking at (focus-odz.3).
    case settingsGeneralVersion = "settings.general.version"
    // Opening at login (D-12, focus-odz.4). Four keys, because the switch has four states and
    // two of them need a sentence: an approval only the person can give, and a copy of the app
    // the system cannot find.
    case settingsLaunchAtLogin = "settings.general.launchAtLogin"
    // e09a (focus-d3g): the two facts the launch read at every start and nothing could write.
    case settingsRitualEnabled = "settings.general.ritualEnabled"
    case settingsRitualEnabledNote = "settings.general.ritualEnabledNote"
    case settingsQuickCaptureShortcut = "settings.general.quickCaptureShortcut"
    case settingsQuickCaptureShortcutNote = "settings.general.quickCaptureShortcutNote"
    case settingsLaunchAtLoginApproval = "settings.general.launchAtLoginApproval"
    case settingsLaunchAtLoginOpenSettings = "settings.general.launchAtLoginOpenSettings"
    case settingsLaunchAtLoginUnavailable = "settings.general.launchAtLoginUnavailable"
    // The presentation-exclusion list (F-121, focus-62o, focus-u3w). The section was deleted at
    // a081d64 because it instructed a person to add an application the app offered no way to
    // add; these are its copy back, with the affordance that was missing.
    case interventionExclusionHeading = "settings.intervention.exclusion.heading"
    case interventionExclusionExplanation = "settings.intervention.exclusion.explanation"
    case interventionExclusionEmpty = "settings.intervention.exclusion.empty"
    case interventionExclusionAddHeading = "settings.intervention.exclusion.addHeading"
    case interventionExclusionNoneRunning = "settings.intervention.exclusion.noneRunning"
    case interventionExclusionRemove = "settings.intervention.exclusion.remove"
    case settingsPrivacyStatement = "settings.privacy.statement"
    // The two things this app does not do, said plainly where a person asks what it does
    // (F-122, F-137, focus-6n2). Both are linted true of the shipped binary rather than
    // promised: `boundaries-binary` for the network, `nm -u` for the updater.
    case settingsPrivacyNoNetwork = "settings.privacy.noNetwork"
    case settingsPrivacyNoUpdateCheck = "settings.privacy.noUpdateCheck"
    case settingsPrivacyStoreLabel = "settings.privacy.storeLabel"
    case settingsPrivacyReveal = "settings.privacy.reveal"
    // The retention window (F-115, focus-l7n): a heading, the sentence that says what choosing
    // one means, and one label per window. The labels are a closed vocabulary over
    // `RetentionWindow` — `RetentionWindow.titleKey` is the only mapping, and it is a bijection
    // both ways in `RetentionWindowVocabularyTests`.
    case settingsPrivacyRetentionHeading = "settings.privacy.retention.heading"
    case settingsPrivacyRetentionExplanation = "settings.privacy.retention.explanation"
    case settingsPrivacyRetentionSevenDays = "settings.privacy.retention.sevenDays"
    case settingsPrivacyRetentionThirtyDays = "settings.privacy.retention.thirtyDays"
    case settingsPrivacyRetentionNinetyDays = "settings.privacy.retention.ninetyDays"
    case settingsPrivacyRetentionForever = "settings.privacy.retention.forever"
    // Taking it away (F-110, F-134, focus-ix9): one heading, one sentence, three verbs. The same
    // three titles are the File menu's, so a person finds them in both places under one name.
    case settingsPrivacyPortabilityHeading = "settings.privacy.portability.heading"
    case settingsPrivacyPortabilityExplanation = "settings.privacy.portability.explanation"
    case settingsPrivacyExportData = "settings.privacy.portability.exportData"
    case settingsPrivacyExportSettings = "settings.privacy.portability.exportSettings"
    case settingsPrivacyImportSettings = "settings.privacy.portability.importSettings"
    /// The title of the one alert this pane can raise: an import the app refused, with the
    /// reason beside it. A refusal that only reached the log is a refusal nobody saw.
    case settingsPrivacyImportRefused = "settings.privacy.portability.importRefused"
    // Delete everything (e07a, focus-6pr.3): the pane's one destructive control and its sheet.
    case settingsPrivacyDeleteHeading = "settings.privacy.delete.heading"
    case settingsPrivacyDeleteExplanation = "settings.privacy.delete.explanation"
    case settingsPrivacyDeleteEverything = "settings.privacy.delete.button"
    case settingsPrivacyDeleteConfirmHeading = "settings.privacy.delete.confirm.heading"
    case settingsPrivacyDeleteConfirmBody = "settings.privacy.delete.confirm.body"
    case settingsPrivacyDeleteCancel = "settings.privacy.delete.confirm.cancel"
    case settingsPrivacyDeleteConfirm = "settings.privacy.delete.confirm.action"

    // The session runtime (F-98, F-99, F-101).
    //
    // `FocusCore` owns the machine and returns typed values; every word for those values lives
    // here, which is what keeps the session reducer free of user-visible strings (plan R-52).
    case sessionHeading = "session.pane.heading"
    case sessionNone = "session.pane.none"
    case sessionElapsed = "session.pane.elapsed"
    case sessionBadgeFocus = "session.badge.focus"
    case sessionBadgeDetour = "session.badge.detour"
    case sessionBadgeBreak = "session.badge.break"
    case sessionBadgePaused = "session.badge.paused"
    case sessionBadgeInterrupted = "session.badge.interrupted"
    case sessionBadgeComplete = "session.badge.complete"
    case sessionActionStart = "session.action.start"
    case sessionActionPause = "session.action.pause"
    case sessionActionResume = "session.action.resume"
    case sessionActionDetourStart = "session.action.detourStart"
    case sessionActionDetourEnd = "session.action.detourEnd"
    case sessionActionBreakStart = "session.action.breakStart"
    case sessionActionBreakEnd = "session.action.breakEnd"
    case sessionActionInterrupt = "session.action.interrupt"
    case sessionActionComplete = "session.action.complete"
    // Every pause carries the cause that made it, and only that cause can lift it — so the
    // surface names them one by one rather than saying "paused".
    case sessionCauseHeading = "session.cause.heading"
    case sessionCauseUser = "session.cause.user"
    case sessionCauseSensitiveApp = "session.cause.sensitiveApp"
    case sessionCauseGlobalPause = "session.cause.globalPause"
    case sessionCauseScreenLocked = "session.cause.screenLocked"
    case sessionCauseDisplaysAsleep = "session.cause.displaysAsleep"
    case sessionCauseSystemAsleep = "session.cause.systemAsleep"
    case sessionCauseSessionInactive = "session.cause.sessionInactive"
    case sessionCauseRelaunch = "session.cause.relaunch"
    case sessionCauseSystemRestart = "session.cause.systemRestart"
    case sessionResumeBlocked = "session.resume.blocked"
    case sessionNoteRebooted = "session.note.rebooted"
    case sessionNoteStale = "session.note.stale"
    case sessionNoteClockAnomaly = "session.note.clockAnomaly"
    case sessionInterruptHeading = "session.interrupt.heading"
    case sessionInterruptExplanation = "session.interrupt.explanation"
    case sessionInterruptReasonLabel = "session.interrupt.reasonLabel"
    case sessionInterruptReasonUser = "session.interrupt.reason.user"
    case sessionInterruptReasonPriorityChanged = "session.interrupt.reason.priorityChanged"
    case sessionInterruptReasonAppQuit = "session.interrupt.reason.appQuit"
    case sessionInterruptReasonSystemRestart = "session.interrupt.reason.systemRestart"
    case sessionInterruptReasonTimeboxAbandoned = "session.interrupt.reason.timeboxAbandoned"
    case sessionInterruptNoteLabel = "session.interrupt.noteLabel"
    case sessionInterruptNotePrompt = "session.interrupt.notePrompt"
    case sessionInterruptLastActiveLabel = "session.interrupt.lastActiveLabel"
    case sessionInterruptLastActiveNone = "session.interrupt.lastActiveNone"
    case sessionInterruptConfirm = "session.interrupt.action.confirm"
    case sessionInterruptCancel = "session.interrupt.action.cancel"

    // What the app is watching (F-119) — and what it is not.
    case sensingHeading = "sensing.pane.heading"
    case sensingStatusWatching = "sensing.status.watching"
    case sensingStatusPaused = "sensing.status.paused"
    case sensingStatusDetached = "sensing.status.detached"
    case sensingObserversLabel = "sensing.detail.observers"
    case sensingRedundantLabel = "sensing.detail.redundant"
    case sensingPauseLabel = "sensing.pause.label"
    case sensingPauseExplanation = "sensing.pause.explanation"
    case sensingIdleAway = "sensing.idle.away"
    case sensingIdlePresent = "sensing.idle.present"
    case sensingMicRunning = "sensing.mic.running"
    case sensingMicIdle = "sensing.mic.idle"
    case sensingCameraNoDevices = "sensing.camera.noDevices"
    case sensingCameraHeld = "sensing.camera.held"
    case sensingPresentationOn = "sensing.presentation.on"
    case sensingPresentationOff = "sensing.presentation.off"
    case sensingDisplaySecondary = "sensing.display.secondary"
    case sensingDisplayPrimary = "sensing.display.primary"
    // Every lifecycle line ends "as far as macOS tells us". That is a Court condition, not a
    // hedge: no copy anywhere may claim exact screen-lock detection.
    case sensingLifecycleActive = "sensing.lifecycle.active"
    case sensingLifecycleScreenLocked = "sensing.lifecycle.screenLocked"
    case sensingLifecycleDisplaysAsleep = "sensing.lifecycle.displaysAsleep"
    case sensingLifecycleSystemAsleep = "sensing.lifecycle.systemAsleep"
    case sensingLifecycleSessionInactive = "sensing.lifecycle.sessionInactive"
    case sensingLifecyclePoweringOff = "sensing.lifecycle.poweringOff"
    /// The known limitation, stated in Settings rather than hidden: Screen Sharing produces
    /// only synthetic events, so this app will consider such a person idle (plan R-36).
    case sensingLimitationScreenSharing = "sensing.limitation.screenSharing"

    // The graceful-degradation matrix (F-126, F-127).
    case capabilityHeading = "capability.pane.heading"
    case capabilityExplanation = "capability.pane.explanation"
    case capabilityNameFrontmostApplication = "capability.name.frontmostApplication"
    case capabilityNameWindowMetadata = "capability.name.windowMetadata"
    case capabilityNameIdle = "capability.name.idle"
    case capabilityNameSystemLifecycle = "capability.name.systemLifecycle"
    case capabilityNameDisplayGeometry = "capability.name.displayGeometry"
    case capabilityNamePresentation = "capability.name.presentation"
    case capabilityNameMicrophoneActivity = "capability.name.microphoneActivity"
    case capabilityNameCameraActivity = "capability.name.cameraActivity"
    case capabilityNameAccessibilityWindowContext = "capability.name.accessibilityWindowContext"
    case capabilityNameScreenCapture = "capability.name.screenCapture"
    case capabilityNameNotifications = "capability.name.notifications"
    case capabilityNameOnDeviceModel = "capability.name.onDeviceModel"
    case capabilityStateAvailable = "capability.state.available"
    case capabilityStateDenied = "capability.state.denied"
    case capabilityStateRestricted = "capability.state.restricted"
    case capabilityStateUnavailable = "capability.state.unavailable"
    case capabilityStateNotRequested = "capability.state.notRequested"
    /// **The fallback sentences are predicates, and their subject is the row's consumer list**
    /// (focus-doc).
    ///
    /// They were whole sentences with no subject — *"Nothing depends on it."*, *"That part of
    /// the app does not run."* — and the matrix draws every DISTINCT fallback a capability
    /// produces across its ten consumers, so under *"Which app is in front"* it printed four of
    /// them at once. Each was true of the consumer it came from; together they contradicted, and
    /// *"Nothing depends on it"* was plainly false of an app whose own Watching section two
    /// inches above says the app in front is watched.
    ///
    /// So every one of them now begins mid-sentence and is drawn through
    /// `capability.fallback.attributed` under the names of the consumers it is true of. A line
    /// that cannot be read as an app-level claim cannot contradict the line beside it.
    case capabilityFallbackAttributed = "capability.fallback.attributed"
    case capabilityFallbackFullFunction = "capability.fallback.fullFunction"
    case capabilityFallbackDegraded = "capability.fallback.degraded"
    case capabilityFallbackFeatureAbsent = "capability.fallback.featureAbsent"
    case capabilityFallbackSuppressOnly = "capability.fallback.suppressOnly"
    case capabilityFallbackShowUnavailable = "capability.fallback.showUnavailable"

    /// The ten things the app does with a signal, named so a fallback line has a subject.
    case capabilityConsumerActivationTimeline = "capability.consumer.activationTimeline"
    case capabilityConsumerDwellAttribution = "capability.consumer.dwellAttribution"
    case capabilityConsumerDisplayFairness = "capability.consumer.displayFairness"
    case capabilityConsumerPresentationSuppression = "capability.consumer.presentationSuppression"
    case capabilityConsumerMediaSuppression = "capability.consumer.mediaSuppression"
    case capabilityConsumerLifecyclePause = "capability.consumer.lifecyclePause"
    case capabilityConsumerIdlePause = "capability.consumer.idlePause"
    case capabilityConsumerClassification = "capability.consumer.classification"
    case capabilityConsumerNudgeLadder = "capability.consumer.nudgeLadder"
    case capabilityConsumerAnalytics = "capability.consumer.analytics"

    // The verdict inspector (F-46, F-52, R-71).
    //
    // The *vocabulary* it draws — the rung names, the clause sentences, the suppression
    // reasons, the evidence bands — is `FocusCore`'s, because `FocusUI` may not import
    // `FocusClassify` and the whole classification vocabulary moved beside the status it
    // mirrors (R-53). What is here is only this pane's own chrome: the headings and the labels
    // that introduce those values.
    case verdictHeading = "settings.verdict.heading"
    case verdictExplanation = "settings.verdict.explanation"
    /// `nil` is a real answer: the engine has concluded nothing, and saying so is not the same
    /// as saying `relevant`.
    case verdictNothingJudged = "settings.verdict.nothingJudged"
    case verdictRungLabel = "settings.verdict.rungLabel"
    case verdictBandLabel = "settings.verdict.bandLabel"
    case verdictDriftLabel = "settings.verdict.driftLabel"
    case verdictReasonsLabel = "settings.verdict.reasonsLabel"
    case verdictSilenceLabel = "settings.verdict.silenceLabel"
    /// What the pane says when the engine has authorised an interruption. e05's ladder is what
    /// consumes it, so this sentence names the rung that is being raised (focus-lmy).
    case verdictMandated = "settings.verdict.mandated"
    case verdictEngineLabel = "settings.verdict.engineLabel"

    // The nudge surfaces' own chrome (e05).
    //
    // **The nudge's *words* are not here.** Every sentence a nudge says comes from one of the
    // four static decks in `FocusCore`'s catalog, through `NudgeVoice → NudgeCopyKey`, because
    // D-11 requires the intervention copy to be human-authored and checkable and R-96l asserts
    // the deck matrix as a bijection. What is here is the chrome around those sentences: the
    // close affordance's label, the countdown's spoken form and the one line that tells somebody
    // the top rung wants an answer.
    case nudgeDismiss = "shell.nudge.dismiss"
    case nudgeSnoozeCountdown = "shell.nudge.snoozeCountdown"

    // The menu-bar command centre (F-82, F-83, R-91).
    //
    // The popover reuses the priority, session, sensing and verdict keys the cockpit already
    // owns rather than declaring a second set: the menu bar is a second *place* to see the same
    // facts, and two keys reading "Pause" would be two things to keep in step for no gain.
    // What is here is only what the command centre itself introduces.
    case menuBarStatusItem = "shell.menuBar.statusItem"
    case menuBarOpenCockpit = "shell.menuBar.openCockpit"
    case menuBarSnoozedHeading = "shell.menuBar.snoozed"
    case menuBarCancelSnooze = "shell.menuBar.cancelSnooze"
    case menuBarPendingQuestion = "shell.menuBar.pendingQuestion"
    // The status item's secondary menu (focus-odz.2). *Pause Watching* is deliberately absent:
    // it is `commandPauseSensing`, which the app menu draws for the same act, and a second key
    // reading "Pause Watching" would be a second thing to keep in step.
    case menuBarResumeWatching = "shell.menuBar.resumeWatching"
    case menuBarSettings = "shell.menuBar.settings"
    case menuBarQuit = "shell.menuBar.quit"
    /// The **ladder** rung, not the cascade rung. `settings.verdict.rungLabel` reads "Decided
    /// by" and belongs to e04's precedence ladder; a nudge rung answers a different question —
    /// what the app would do next — so it gets a label of its own rather than borrowing one
    /// that would make the popover say "Decided by: a small panel you can answer".
    case menuBarNudgeRung = "shell.menuBar.nudgeRung"

    // The Intervention settings pane (R-98, F-132, F-148).
    //
    // The pane's own chrome. The *numbers* it draws are read from `InterventionPolicy` and
    // the routing table it draws is `SurfaceRouter.table(...)` itself, so neither has a key
    // here: a threshold written down twice is a threshold that drifts.
    case interventionTitle = "settings.intervention.title"
    case interventionVoiceLabel = "settings.intervention.voice.label"
    case interventionVoiceNeutral = "settings.intervention.voice.neutral"
    case interventionVoiceWarm = "settings.intervention.voice.warm"
    case interventionVoiceDirect = "settings.intervention.voice.direct"
    case interventionVoiceSilentVisual = "settings.intervention.voice.silentVisual"
    case interventionReducedLabel = "settings.intervention.reduced.label"
    case interventionReducedExplanation = "settings.intervention.reduced.explanation"
    case interventionReducedForced = "settings.intervention.reduced.forced"
    case interventionQuietHoursLabel = "settings.intervention.quietHours.label"
    case interventionQuietHoursOff = "settings.intervention.quietHours.off"
    case interventionQuietHoursTurnOn = "settings.intervention.quietHours.turnOn"
    case interventionQuietHoursTurnOff = "settings.intervention.quietHours.turnOff"
    case interventionQuietHoursStartEarlier = "settings.intervention.quietHours.startEarlier"
    case interventionQuietHoursStartLater = "settings.intervention.quietHours.startLater"
    case interventionQuietHoursEndEarlier = "settings.intervention.quietHours.endEarlier"
    case interventionQuietHoursEndLater = "settings.intervention.quietHours.endLater"
    case interventionQuietHoursExplanation = "settings.intervention.quietHours.explanation"
    /// The window's two boundaries, each already a locale-formatted time, joined by the
    /// separator this entry authors (focus-43k). `%1$@ – %2$@`: the dash was an authored
    /// literal in a format string for three epics, which no catalog could reach.
    case interventionQuietHoursRange = "settings.intervention.quietHours.range"
    // The notch companion's row (e08a). **Five sentences and no control**: the row is a reading
    // of `NotchLanding`, so a person is told what the geometry said rather than what a preference
    // is set to — which is the difference between an honest "not available" and a switch
    // asserting a surface is real on a Mac with no built-in panel.
    case interventionNotchHeading = "settings.intervention.notch.heading"
    /// The geometry landed: there is a housing, and a strip under it.
    case interventionNotchLanded = "settings.intervention.notch.landed"
    /// **This rig's answer.** Its own sentence, because "this Mac has no notch" is false for a
    /// Mac with no built-in display at all (e08 review §6).
    case interventionNotchNoBuiltInDisplay = "settings.intervention.notch.noBuiltInDisplay"
    /// A built-in panel with no notch — every notchless MacBook.
    case interventionNotchNoNotch = "settings.intervention.notch.noNotch"
    /// A built-in panel whose auxiliary areas the app could not make sense of. One sentence for
    /// three refusals, because a person cannot act on the difference between them.
    case interventionNotchUnreadable = "settings.intervention.notch.unreadable"
    /// The same second sentence in every case: whatever the geometry answered, the ambient state
    /// is on the menu-bar glyph.
    case interventionNotchExplanation = "settings.intervention.notch.explanation"
    case interventionRoutingHeading = "settings.intervention.routing.heading"
    case interventionRoutingExplanation = "settings.intervention.routing.explanation"
    /// **Three surfaces, and there were five** (focus-pzl). `…surface.notification` read *"A
    /// notification"* four lines under the routing explanation's promise that the app *"never
    /// sends a notification, and never asks for permission to"*, and `…surface.unavailable` read
    /// *"Nowhere right now"*. `SurfaceRouter.table(…)` can produce neither route, so both were
    /// sentences in the shipped binary that no click could reach — and each was blessed by
    /// `check-strings.sh` because a switch arm three files away mentioned its key.
    case interventionSurfaceMenuBar = "settings.intervention.surface.menuBar"
    case interventionSurfacePanel = "settings.intervention.surface.panel"
    case interventionSurfacePopoverBadge = "settings.intervention.surface.popoverBadge"
    case interventionCapsHeading = "settings.intervention.caps.heading"
    case interventionCapsQueriesPriority = "settings.intervention.caps.queriesPriority"
    case interventionCapsQueriesDay = "settings.intervention.caps.queriesDay"
    case interventionCapsAccusations = "settings.intervention.caps.accusations"
    case interventionCapsInterruptions = "settings.intervention.caps.interruptions"
    case interventionCapsExplanation = "settings.intervention.caps.explanation"
    case interventionThresholdsHeading = "settings.intervention.thresholds.heading"
    case interventionThresholdQueryDwell = "settings.intervention.thresholds.queryDwell"
    case interventionThresholdQueryCooldown = "settings.intervention.thresholds.queryCooldown"
    case interventionThresholdAccusationCooldown = "settings.intervention.thresholds.accusationCooldown"
    case interventionThresholdEscalation = "settings.intervention.thresholds.escalation"
    case interventionThresholdSnooze = "settings.intervention.thresholds.snooze"
}

/// A transform applied to a resolved string immediately before it is drawn.
///
/// The shell ships exactly one implementation — `identity` — and that is not a hedge. The
/// seam exists so the pseudo-localisation lane can push ~2× expanded strings through the
/// *same* accessor the real views use, instead of rendering a parallel set of views that
/// prove nothing about the shipping ones. Translation itself is parked (no translator in the
/// loop); pseudo-localisation is the sanctioned substitute, and it needs this hook.
public struct ShellStringTransform: Sendable {
    /// Named so a snapshot filename and a test failure can both say which transform ran.
    public let name: String
    private let body: @Sendable (String) -> String

    public init(name: String, body: @escaping @Sendable (String) -> String) {
        self.name = name
        self.body = body
    }

    public func callAsFunction(_ string: String) -> String { body(string) }

    /// The shipping transform: the catalog's own text, untouched.
    public static let identity = ShellStringTransform(name: "identity") { $0 }
}

extension EnvironmentValues {
    /// The string transform in force for this subtree. `identity` everywhere in the app.
    @Entry public var shellStringTransform: ShellStringTransform = .identity
}

extension View {
    /// Render this subtree's strings through `transform`. Used only by the
    /// pseudo-localisation lane; the app never calls it.
    public func shellStringTransform(_ transform: ShellStringTransform) -> some View {
        environment(\.shellStringTransform, transform)
    }
}

/// How large the shell draws its text.
///
/// macOS has no injectable Dynamic Type — measured on this machine, an injected
/// `dynamicTypeSize` changes neither font size nor `@ScaledMetric` output — so the shell
/// carries its own scale. `standard` is the system's own typography, which already follows
/// the Mac's system-wide Text Size setting; the larger scale is what the snapshot and
/// pseudo-localisation lanes inject to prove the layout grows instead of truncating.
public enum ShellTextScale: String, Sendable, CaseIterable, Hashable {
    /// The system's typography, unmodified. What the app always runs at.
    case standard
    /// Roughly twice the system size — the largest accessibility text size, simulated.
    case accessibilityLarge

    public var multiplier: CGFloat {
        switch self {
        case .standard: 1
        case .accessibilityLarge: 2
        }
    }
}

extension EnvironmentValues {
    /// The text scale in force for this subtree. `standard` everywhere in the app.
    @Entry public var shellTextScale: ShellTextScale = .standard
}

extension View {
    /// Draw this subtree's text at a given scale. Used by the snapshot and
    /// pseudo-localisation lanes; the app never calls it.
    public func shellTextScale(_ scale: ShellTextScale) -> some View {
        environment(\.shellTextScale, scale)
    }
}

/// A piece of user-visible text.
///
/// Every string the shell draws goes through this view. It resolves the catalog entry, hands
/// it to whatever transform is in force, applies the shell's type role at the scale in
/// force, and draws the result — which is what makes the pseudo-localisation and
/// large-text passes properties of the real views rather than of a test-only copy of them.
public struct ShellText: View {
    private let resource: LocalizedStringResource
    private let role: DesignTokens.FontRole
    /// The substitutions, for the format-string entries. Empty for every plain entry.
    private let arguments: [String]
    /// Whether digits are drawn at a fixed advance, so a clock a person steps with two buttons
    /// does not jitter as its digits change (e07a, focus-43k). Off for every plain entry.
    private var monospacedDigits = false

    @Environment(\.shellStringTransform) private var transform
    @Environment(\.shellTextScale) private var scale

    /// A string from `FocusUI`'s own catalog.
    public init(_ key: ShellStringKey, role: DesignTokens.FontRole = .body) {
        self.resource = ShellStrings.resource(key)
        self.role = role
        self.arguments = []
    }

    /// A format entry from the catalog with the user's own phrase substituted into it.
    ///
    /// The transform runs on the *format* and the argument is substituted afterwards, so the
    /// pseudo-localisation lane expands the authored half and leaves the user's words alone —
    /// which is exactly what a real translation does.
    public init(_ key: ShellStringKey, role: DesignTokens.FontRole = .body, argument: String) {
        self.resource = ShellStrings.resource(key)
        self.role = role
        self.arguments = [argument]
    }

    /// A format entry with **several** positional slots, in the order the format declares them.
    ///
    /// `NudgeText` has taken `arguments:` since e05; the capability matrix is what needed it
    /// here (focus-doc). Its fallback lines read *"<the consumers that answer this way>: <what
    /// they do instead>"*, and **both halves are authored catalog entries** — which is why this
    /// is one format entry with `%1$@` and `%2$@` rather than two views with a hardcoded colon
    /// between them. A translation is then free to put the list after the verb.
    public init(
        _ key: ShellStringKey,
        role: DesignTokens.FontRole = .body,
        arguments: [String]
    ) {
        self.resource = ShellStrings.resource(key)
        self.role = role
        self.arguments = arguments
    }

    /// A string from some other package's catalog — the status labels, which `FocusCore`
    /// owns, are the e01 case.
    ///
    /// Labelled `resource:` deliberately. Xcode generates a typed
    /// `LocalizedStringResource` symbol for every catalog entry, so an unlabelled overload
    /// makes `ShellText(.settingsAppearanceLabel)` ambiguous between this initialiser and
    /// the key one — under `xcodebuild` only, where those symbols exist. The label is what
    /// keeps the two lanes compiling the same source.
    public init(resource: LocalizedStringResource, role: DesignTokens.FontRole = .body) {
        self.resource = resource
        self.role = role
        self.arguments = []
    }

    /// The same entry, with its digits at a fixed advance. A `Text`-level modifier, so it is
    /// offered here rather than lost behind the view — the quiet-hours row is the one caller.
    public func monospacedDigit() -> ShellText {
        var copy = self
        copy.monospacedDigits = true
        return copy
    }

    public var body: some View {
        let format = transform(String(localized: resource))
        let drawn = arguments.isEmpty ? format : String(format: format, arguments: arguments)
        let text = Text(verbatim: drawn)
            .font(DesignTokens.font(role, scale: scale))
        return (monospacedDigits ? text.monospacedDigit() : text)
    }
}

/// **The word for each retention window** (F-115, focus-l7n).
///
/// The mapping lives in `FocusUI` rather than on the type, because `FocusCore` owns the window
/// and this package owns every word a person reads — the same split `NudgeVoice` and the e04
/// vocabularies keep. It is an exhaustive `switch`, so a window added without a word does not
/// compile, and `RetentionWindowVocabularyTests` folds it the other way: every
/// `settings.privacy.retention.` key in the catalog belongs to exactly one window.
extension RetentionWindow {
    public var titleKey: ShellStringKey {
        switch self {
        case .sevenDays: .settingsPrivacyRetentionSevenDays
        case .thirtyDays: .settingsPrivacyRetentionThirtyDays
        case .ninetyDays: .settingsPrivacyRetentionNinetyDays
        case .forever: .settingsPrivacyRetentionForever
        }
    }
}
