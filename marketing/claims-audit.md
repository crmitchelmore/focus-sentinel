# Claims audit: site/index.html against the source

> **Superseded in part (2026-10-20).** The owner changed the privacy posture to *local first, opt in
> for more*: update checks and the Decision-1 remote judge are opt-in network uses, and opting in to
> the judge gives it everything the app knows. Rows W1, W2, V1, V6, V37, V38 and O18 below describe
> the earlier local-only posture; the site now says the new one (README ▸ Privacy posture).

Checked on 1 October 2026 against `main` at `9319f3b`. Every line in `site/index.html` that makes a
product claim was checked against the source code, the string catalogues and the GitHub API.

**Verdicts.** *Verified*: the code or the shipped copy supports the claim. *Wrong*: the code
contradicts it. *Unverifiable*: nothing in the repository proves it, or it depends on something
outside the repository. *Verified, nuance*: true, but the wording could mislead.

**Path shorthand.**

| short | full path |
|---|---|
| `UI.xcstrings` | `Packages/FocusUI/Sources/FocusUI/Resources/Localizable.xcstrings` |
| `Core.xcstrings` | `Packages/FocusCore/Sources/FocusCore/Resources/Localizable.xcstrings` |
| `PrivacySettingsView` | `Packages/FocusUI/Sources/FocusUI/Scenes/PrivacySettingsView.swift` |
| `RelevanceHost` | `Packages/FocusHost/Sources/FocusHost/RelevanceHost.swift` |
| `RuleCascade` | `Packages/FocusClassify/Sources/FocusClassify/Cascade/RuleCascade.swift` |
| `InterventionPolicy` | `Packages/FocusCore/Sources/FocusCore/Nudge/InterventionPolicy.swift` |
| `CommandRegistry` | `Packages/FocusUI/Sources/FocusUI/Commands/CommandRegistry.swift` |

Line numbers in a `.xcstrings` file point at the key. The English value is a few lines below it.

---

## 1. Fix before launch

These claims are wrong today. The site agent should change them first.

| # | site line | claim | verdict | evidence | suggested correction |
|---|---|---|---|---|---|
| W1 | 431 | "Focus goes online only if you turn on update checks. A check sends the app's name and version and nothing about you." | **Wrong** | `UI.xcstrings:3088` "Focus never connects to the internet."; `UI.xcstrings:3100` "It never checks for updates."; `PrivacySettingsView:460-473`; `README.md:422-439` (no updater, no Sparkle, no `SUFeedURL`); `App/FocusSentinel.entitlements` (no network entitlement); issue #12 keeps "local-only/manual-update scope". The words "update check" appear nowhere outside `site/`. | **No network.** "Focus never connects to the internet. It never checks for updates. The build gate checks the shipped binary for networking code on every run." |
| W2 | 481 | FAQ "Does it phone home? Only if you turn on update checks in General settings. They are off until you do…" | **Wrong** | As W1. `GeneralSettingsView` has no update control. | "No. Focus never connects to the internet, and it has no updater. That is the app's own sentence in Privacy settings." |
| W3 | 497 | "Updates arrive only if you switch update checks on." | **Wrong** | As W1. | "There is no automatic updater. When a new version is out, you download it from the release page yourself." |
| W4 | 400-401 | "A tour on the real window. The walkthrough highlights each control in turn and offers to do the step for you. Replay it from Help." | **Wrong** | The source has no tour, walkthrough or coach marks (no match for `tour`/`walkthrough`/`onboarding` anywhere outside `site/`). Help (⌘?) opens the Keyboard Shortcuts window (`CommandRegistry:577-582`, `UI.xcstrings:5032`). First launch shows a one-page sheet, "What Focus Sentinel watches" (`Packages/FocusUI/Sources/FocusUI/Scenes/FirstRunSheet.swift`, `UI.xcstrings:4756`). | Replace the card. Suggested: **"It tells you first."** "On first launch, one page says what Focus reads, what it never reads, and where your data is kept. Help lists every keyboard shortcut." |
| W5 | 275, 443, 506 | "Read the source" link; "The source is public under the MIT licence." Footer: "MIT licence". | **Wrong today** | GitHub API, `GET repos/crmitchelmore/focus-sentinel` on 1 Oct 2026: `"private": true`, `"license": null`. No `LICENSE` file in the repository. | Before launch: add `LICENSE` (MIT) and make the repository public. Until then: "The source will be published under the MIT licence when the first build ships." Remove the "Read the source" button or point it somewhere public. |
| W6 | 274, 497, 507 | Links to `…/issues/12` and `…/security/advisories/new` | **Wrong for visitors** | The repository is private, so these links return 404 for anyone without access. | Make the repository public, or link to a public page instead, such as a mailing-list signup or the blog. |
| W7 | 439 | "A minute without keyboard or mouse, or longer if you choose, and Focus stops counting…" | **Wrong** | The default is 180 s: `Packages/FocusCore/Sources/FocusCore/Store/FocusSchemaV3.swift:74`, `SensingSettings.swift:17-18`. The dial runs from 1 to 30 minutes: `PrivacySettingsView:390-393`. | "Three minutes without keyboard or mouse (you can choose anything from one to thirty), and Focus stops counting and stays quiet until you are back." |
| W8 | 371 | "The context pack: Apps, sites, keywords and files that belong to the priority." | **Wrong in effect** | A dragged app becomes a *file* item: `Packages/FocusUI/Sources/FocusUI/Context/ContextDropTarget.swift:46` → `Packages/FocusCore/Sources/FocusCore/Cockpit/PriorityActing.swift:71`. File items never match (`RuleCascade:470-474`). `ContextItemDraft.app` has no caller, so the UI cannot create an app item. Site items cannot match either, because the shipping judgement reads no site (see W10). Keywords do match (`RuleCascade:456-468`). Sites and files are opened by "Open the context pack when a session starts" (`UI.xcstrings:3712`). | "Keywords, sites and files that belong to the priority. Focus can open them when a session starts. Apps join when you answer a question or add a rule." Also, product bug: a dropped app should become an app item (see the note at the end). |
| W9 | 371 | "Add them on Details or drop them onto the window." | **Wrong (minor)** | The only drop target is the Context section (`Packages/FocusUI/Sources/FocusUI/Context/ContextChipRow.swift:84`). Paste (⌘V) and Add files… (⌘O) also work. | "Add them in Context on the Details tab: type a keyword, drop or paste a link or file, or press ⌘O." |
| W10 | 423, 477 | "If a browser shares its site without a permission prompt, the host name only." / "…where a browser shares it freely, the site's host name." | **Misleading** | This mirrors the app's own first-run copy (`UI.xcstrings:4744`), but no shipping code reads a site. `RelevanceHost:439` judges with `ClassificationInput(bundleIdentifier:)` only, and `ClassificationInput.swift:10-12` says origin and title tokens are "empty in every shipping code path". `README.md:1336-1337` agrees, and History draws browser time as unattributed (`README.md:925`). | "Which app is active: its name, never its windows. This version does not read which website a browser is showing." This is stronger and true. The first-run sentence in the app overstates in the same way, which is a copy fix for Chris. |
| W11 | 376 | "Mark an app or site related or unrelated, for this priority or this session only." | **Half wrong** | App rules work. Site rules are stored but cannot match, for the reason in W10. `priority.rules.scope.session` "This session only" (`UI.xcstrings:1348`) is real. | "Mark an app related or unrelated, for this priority or for this session only." |
| W12 | 477 | FAQ: "This version requests neither Screen Recording nor Accessibility" | **Wrong (since 9 Sep)** | Privacy settings have two switches, "Let Focus ask for Accessibility" and "Let Focus ask for Screen Recording" (`UI.xcstrings:3580`, `3628`; `Packages/FocusHost/Sources/FocusHost/SystemGrantRequester.swift`; `README.md:183-205`). Both are off by default, and nothing reads what they unlock (`UI.xcstrings:3616`). | "No. Focus asks macOS for Screen Recording or Accessibility only if you switch that on in Privacy settings, and nothing in this version reads what either would unlock." The app's own first-run line (`UI.xcstrings:4720`) is stale in the same way. |
| W13 | 334 | "Stopping early asks why; every field is optional." | **Wrong (minor)** | Finish session completes without asking (`Packages/FocusUI/Sources/FocusUI/Session/SessionControls.swift:261`). The reason sheet appears only through **Stop with a note…** (`UI.xcstrings:1828`, `2092`). | "Stop with a note to record what happened and where to pick up. Every field is optional." |
| W14 | 344-346 | Illustrated question: buttons "Yes, add it / No, it isn't / Not now". Reason: "Focus has not been told which apps this task lives in." Scope: "One answer covers the whole app, for this priority." | **Wrong (copy drift)** | Standard voice: "Yes, add it" / "No, it isn't" / "Ask later" (`Core.xcstrings:972`, `948`, `960`). Reason: "No apps have been added to this priority yet." (`Core.xcstrings:1032`). Scope: "Applies to this whole app for this priority." (`Core.xcstrings:984`). | Use the real strings. The panel heading "A small question." is correct. |
| W15 | 286 | Illustrated window title "Focus" | **Wrong (minor)** | The cockpit heading and window title are "Focus Sentinel" (`UI.xcstrings:3472`, `5378`). | "Focus Sentinel" |

---

## 2. Claims checked and true

| # | site line | claim | verdict | evidence | note or suggested wording |
|---|---|---|---|---|---|
| V1 | 8, 270 | Local-only companion for the Mac | Verified | `UI.xcstrings:3088`, `3268`; `App/FocusSentinel.entitlements`; `README.md:1306-1311` (no accounts, telemetry, analytics or third-party packages) | — |
| V2 | 271, 290-291 | Keeps one priority in view | Verified | `Packages/FocusUI/Sources/FocusUI/Scenes/CockpitTab.swift:3-10` ("the priority is never a tab away") | — |
| V3 | 272 | Watches which app is in front | Verified | `UI.xcstrings:4744`; `RelevanceHost:439` | — |
| V4 | 8, 272 | Asks before it assumes / asks instead of accusing | Verified | `README.md:681-688`: an uncertain verdict produces a question, never a nudge; `README.md:708-720` shows a question can never become a nudge | — |
| V5 | 272, 448 | Keeps no score; never praises, scores or scolds | Verified | `README.md:957-962` (ruling D-01: no score, streak or per-day tally). Nudge copy is descriptive: "%@ has been active for %@." (`Core.xcstrings`, `nudge.neutral.accusation.panel.body`) | Nudges settings do show today's counts against the daily limits (`UI.xcstrings:2524`). That is a budget, not a score. |
| V6 | 272 | Nothing it learns leaves your Mac | Verified | `UI.xcstrings:3088`. Exports go only to a folder you choose, and there is no share sheet (`README.md:451-456`). | — |
| V7 | 277, 506 | macOS 26 or later | Verified | `FocusSentinel.xcodeproj/project.pbxproj:163,181`; every `Package.swift` declares `.macOS(.v26)` | — |
| V8 | 277, 506 | Apple silicon required | **Unverifiable** | No `ARCHS`/`EXCLUDED_ARCHS` restriction in `project.pbxproj:171-185`, so Release builds standard architectures. The gate builds and tests arm64 only (`scripts/build-gate.sh:96`). | "Tested on Apple silicon", or restrict `ARCHS` to arm64 before calling it a requirement. |
| V9 | 277, 497 | Not released; a signed, notarised first build is planned | Verified | Issue #12 (open) lists #5, "Developer ID signed and notarised customer DMG". `HANDOVER.md:24`: today's DMG is ad-hoc signed. | — |
| V10 | 312, 381 | Timebox shows time left, then time over, and never stops you | Verified | `UI.xcstrings:1444` ("%@ over"), `priority.timebox.remaining`. Nothing terminates or hides other apps; the only `.hide()` calls are on Focus's own panel (`NudgeHost.swift`). | — |
| V11 | 327 | One priority; a new one replaces it, and the old one moves to Recent | Verified | `UI.xcstrings:1204` "Recent priorities"; `PriorityHost.swift:240-250` | — |
| V12 | 327 | No verb or no outcome → Focus offers a rewrite, and your wording wins | Verified | `UI.xcstrings:472` "Start with what you need to do.", `484` "Add what you want to finish or produce.", `580` "Keep my words" | — |
| V13 | 327 | Done when line | Verified | `priority.doneWhen.label` "Done when" | — |
| V14 | 333 | Sessions, timeboxed if you like | Verified | `Packages/FocusCore/Sources/FocusCore/Session/SessionKind.swift:8-14`: open-ended, fixed length, or finish-by-a-time | Finish-by-a-time (deadline) is not mentioned on the site. |
| V15 | 334 | Pause, break, detour, finish | Verified | `UI.xcstrings:1816` "Start a detour", plus `session.action.*` | — |
| V16 | 334 | The timer lives in the menu bar | Verified | `Packages/FocusUI/Sources/FocusUI/MenuBar/MenuBarPresentation.swift:266-270` (snooze, then timebox remaining, then elapsed) | — |
| V17 | 340 | Short drift changes the menu-bar mark and nothing else; longer drift brings a panel that names the app and offers a way back | Verified | `README.md:688` (glyph → panel); `Core.xcstrings:900` "Back to %@" | — |
| V18 | 340 | When unsure it asks, the answer becomes a rule, and it stops asking | Verified | `README.md:749-761` (one transaction writes a rule and a never-ask-again receipt) | — |
| V19 | 354 | History lists each nudge, where it was shown and what you answered | Verified, nuance | `README.md:907-940`; `history.surface.*`, `shell.history.answerLabel` | The History window shows today ("What Focus did today", `UI.xcstrings:5104`). Older records are in Export my data. |
| V20 | 354 | Say so when Focus should have spoken | Verified | `UI.xcstrings:5068` "This was a distraction"; `README.md:964-983` | — |
| V21 | 354 | Records older than your retention limit are deleted daily | Verified | `UI.xcstrings:3184`; `Packages/FocusCore/Sources/FocusCore/Store/RetentionPolicy.swift:36` (default 90 days); options 7 / 30 / 90 days / Forever | Answered-question receipts stay while their priority does, so the app never asks twice (`README.md:367-369`). |
| V22 | 371 | Recent priorities return with their pack and rules | Verified | `PriorityHost.swift:303` (`activate`); items and rules belong to the task. Also "New Priority, Same Context…" (`UI.xcstrings:988`, `PriorityHost.swift:252-283`). | — |
| V23 | 376 | Same facts, same answer, every time | Verified | `README.md:479-483` (a deterministic engine in every shipping composition) | — |
| V24 | 381 | Wall-clock sessions: an hour asleep is an hour spent, and the app says so | Verified | `Packages/FocusCore/Sources/FocusCore/Session/SessionRestoration.swift:21-30`; `session.cause.systemAsleep`; `UI.xcstrings:2260` | — |
| V25 | 386 | The mark shows what Focus believes; a click shows priority, timer, questions and session controls | Verified | `status.mark.*` (`Core.xcstrings`); `Packages/FocusUI/Sources/FocusUI/MenuBar/MenuBarPopoverView.swift:101, 462-465` | — |
| V26 | 386 | A global shortcut sets a new priority from any app | Verified | `UI.xcstrings:2380`; default ⌃⌥⌘Space (`FocusSchemaV3.swift:64,71`); Carbon registration needs no permission (`README.md:1063-1071`) | — |
| V27 | 391 | A daily cap on interruptions | Verified | `InterventionPolicy:169-199`: 8 interruptions, 6 nudges and 5 questions a day, and 4 questions per task. All adjustable (`UI.xcstrings:4036`). | — |
| V28 | 391, 489 | Silence while you present | Verified, nuance | Focus treats any full-screen app as presenting (`UI.xcstrings:3040`), and you can allow named apps | "…while an app is full screen, such as a presentation…" |
| V29 | 391, 489 | Silence while a microphone is live; switch the rule off and a nudge may arrive mid-call | Verified | `UI.xcstrings:3688`; on by default (`SensingSettings.swift:41`). The camera is never used (`sensing.camera.held`). | — |
| V30 | 391 | Silence while you are away | Verified | `suppression.reason.userIdle`; `SuppressionStack.swift:330` | Default is 3 minutes, not 1 (W7). |
| V31 | 391 | Quiet hours you set | Verified | `UI.xcstrings:2668`; off by default (`InterventionPolicy:237`) | Focus cannot read the Mac's own Focus mode, and the pane says so. |
| V32 | 396 | Interrupt me less sends nudges and questions to the menu bar; Reduce Motion turns it on | Verified | `UI.xcstrings:2764`, `2776`; `Packages/FocusUI/Sources/FocusUI/Scenes/InterventionSettingsView.swift:12` | — |
| V33 | 396 | Every panel can be answered, snoozed or closed | Verified | Nudge panel: Snooze, Dismiss, Back to, Relevant, Allow for this session. Question panel: Yes, No, Ask later (`Core.xcstrings`). Snoozes of 1, 5 and 20 minutes, or custom (`InterventionPolicy:211`). | — |
| V34 | 406, 493 | Export activity and settings as separate files, from the File menu | Verified | `UI.xcstrings:3112`; `CommandRegistry:465-479` (⇧⌘X, ⇧⌘B, ⇧⌘I); `README.md:441-449` | Import settings exists too. |
| V35 | 406, 493 | Delete everything from Privacy settings; Focus restarts empty; cannot be undone | Verified | `UI.xcstrings:2956`; `PrivacySettingsView:577-597` | — |
| V36 | 419 | "No account, no sync, no usage reports" is the app's own wording | Verified | `UI.xcstrings:3268` | — |
| V37 | 419 | The build gate checks the shipped binary against it | Verified, nuance | `README.md:430-439`, `1308-1319` (`nm -u` has no networking or Sparkle symbols; no network entitlement) | — |
| V38 | 427 | Never reads window titles, full web addresses, file paths, document names or typing | Verified | `UI.xcstrings:4732`; `check-forbidden.sh` bans `kCGWindowName`; `README.md:1332-1337` | It stores the paths of files you attach yourself. |
| V39 | 435, 463 | Permissions are off until you switch them on; Accessibility and Screen Recording are listed with notes | Verified | `UI.xcstrings:3580`, `3616`, `3628`; `PrivacySettingsView:305-336` | — |
| V40 | 443, 493 | One folder in Application Support, shown in the Finder from Privacy settings | Verified | `Packages/FocusCore/Sources/FocusCore/Store/FocusStore.swift:28-43` (`~/Library/Application Support/com.chrismitchelmore.FocusSentinel/FocusSentinel.store`); `UI.xcstrings:3256` | — |
| V41 | 463 | Every signal is listed | Verified | Capability table "Available on this Mac" (`UI.xcstrings:352`) | — |
| V42 | 485 | Blocks, hides and closes nothing | Verified | No `terminate`/`hide` of other apps in the source | — |
| V43 | 11 | og:image | Verified | `site/companion.png` exists; `site/og.png` is still to be made | — |
| V44 | 509 | Other open-source apps (Pasta, Just Speak to It) | Unverifiable | Outside this repository | Check the links resolve before launch. |

---

## 3. True features the site omits

Ordered by how well they would sell. All verified in source.

| # | feature | evidence | why it sells |
|---|---|---|---|
| O1 | **Private apps are never judged.** A built-in list of password managers, banking, health and private-messaging apps (1Password, Bitwarden, Keychain Access, Passwords, Wallet, Health, Signal, WhatsApp, Telegram…). When one is in front, Focus stops looking and the session pauses ("a private app came to the front"). | `Packages/FocusCore/Sources/FocusCore/Sensing/SensitivityGate.swift:63-140`; `UI.xcstrings:2008` | A privacy promise that is concrete and easy to show |
| O2 | **Shortcuts actions**: Set Focus priority, Start Focus session, Finish Focus session | `App/FocusAppIntents.swift:7,31,50,69`; `App/Localizable.xcstrings:52` | Automation users. Caveat: they run only in a properly signed build (`README.md:1244-1249`); confirm on the notarised candidate first. |
| O3 | **Daily question**: "What is the one thing today?", asked once a day when Focus first opens (can be turned off) | `UI.xcstrings:1240`, `2416` | A gentle daily ritual with no streak |
| O4 | **You can see why it decided.** "Current assessment" shows the verdict, the evidence strength and the reasons. "How Focus decides" lists the rule order. | `UI.xcstrings` `settings.verdict.*`, `cascade.precedence.*`; `PrivacySettingsView:631-646` | Answers "why did it nudge me?" |
| O5 | **Every number is a dial.** 31 timings and thresholds, each shown beside its shipped value, with one-click reset | `UI.xcstrings:3484`, `3496`; `Packages/FocusCore/Sources/FocusCore/Tunings/PolicyTunings.swift` | Power users; it is honest about the defaults |
| O6 | **Four voices**: Standard, Warm, Terse and Silent (Silent drops the sentence) | `UI.xcstrings:2884`; `nudge.{neutral,warm,direct,silentVisual}.*` in `Core.xcstrings` | Tone is personal |
| O7 | **Open the context pack when a session starts** (off by default) | `UI.xcstrings:3712`; `Packages/FocusHost/Sources/FocusHost/SessionHost.swift:340-343` | One click from "start" to set up |
| O8 | **New Priority, Same Context…** carries the context and rules forward | `UI.xcstrings:988`; `PriorityHost.swift:252-283` | Follow-on tasks |
| O9 | **Finish-by-a-time sessions** as well as fixed-length and open-ended ones | `SessionKind.swift:8-14` | Real deadlines |
| O10 | **Finishing asks what you shipped and where to restart** (both optional), and that note comes back next time | `UI.xcstrings` `priority.complete.*` | Easier restarts |
| O11 | **Deep link** `focus://start?task=…&doneWhen=…`, always confirmed before it replaces your priority | `Packages/FocusCore/Sources/FocusCore/Handoff/HandoffRequest.swift:100-106`; `UI.xcstrings:856` | Launchers and scripts, without an app hijacking your priority |
| O12 | **No notifications permission**: nudges stay inside Focus | `UI.xcstrings:2800` | Nothing lands in Notification Centre |
| O13 | **Keyboard-first**: answer questions (⌃⌘Y / ⌃⌘U / ⌃⌘L), open History (⌃⌘D), pause watching (⌃⌘E); quick capture ⌘↩ returns you to the app you were in | `CommandRegistry:409-571`; `UI.xcstrings:520` | Fits how Mac power users work |
| O14 | **Undo for everything** in the priority and rules (Edit menu) | `Core.xcstrings` `undo.*` | Safe to experiment |
| O15 | **Respects accessibility settings**: Increase Contrast, Reduce Transparency, Reduce Motion, larger text, VoiceOver descriptions of each status mark | `UI.xcstrings:2368`; `status.mark.*` in `Core.xcstrings` | Inclusive |
| O16 | **One global pause switch** that detaches every observer | `UI.xcstrings` `sensing.pause.*`; `README.md:226-230` | Instant trust control |
| O17 | **Honest about its limits**: it says Screen Sharing input cannot be seen; it cannot read macOS Focus modes | `UI.xcstrings:1636`, `2668` | It shows the voice |
| O18 | **Zero third-party dependencies; no network entitlement**; held to a 27-stage build gate | `README.md:1306-1311`, `114-150` | For HN and technical readers |
| O19 | **Notch companion**: a thin line under the notch of a built-in display | `UI.xcstrings:2596`; `README.md:829-906` | Only once it is verified on notch hardware (issue #7). It has no toggle yet. |
| O20 | **Settings travel**: export settings on one Mac and import them on another | `README.md:443-449` | — |

---

## 4. Risks outside the copy

* **Repository and licence.** The repository is private and has no licence (W5, W6). Every "open source" or "read the source" line depends on fixing that.
* **Mac App Store.** The app ships with App Sandbox **off** (`App/FocusSentinel.entitlements`). The App Store requires it, so the App Store-style copy in `launch-copy.md` is for listings only until that changes.
* **Product bug found while checking.** A dragged app becomes a file item, which never matches (W8). Fix it in `ContextDropTarget.swift` by mapping application bundles to `ContextItemDraft.app`. The site should avoid "drag an app" until then. The in-app empty state ("Drag an app, a link or a file here…", `UI.xcstrings:784`) has the same problem.
  **Fixed 2 October 2026 (focus-6ji4):** a dropped or ⌘O-chosen application is now an app item
  keyed by bundle identifier, so "drag an app" is true again. Site entry is hidden in this
  version (Chris's call): dropped and pasted links add nothing, the Rules pane offers apps only,
  and stored site rules and chips say "Not read in this version". W8, W9 and W11's suggested
  wording should drop sites and links; pasted paths and `file:`/`mailto:` text are no longer kept
  as keywords.
* **In-app copy that is stale.** The first-run line "Focus does not request Screen Recording or Accessibility permission in this version." (`UI.xcstrings:4720`) and the browser host-name line (`UI.xcstrings:4744`) overstate in the same ways as W10 and W12. Chris owns that copy (D-11 approvals).
