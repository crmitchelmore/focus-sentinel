# Focus Sentinel

A local-only macOS focus guardian. Everything here is built, tested and verified from the
command line: **no step in this repository requires Xcode.app to be opened.**

Requirements: macOS 26+, Xcode 26.2 with the Swift 6.2 toolchain. Nothing else is installed
and nothing else may be introduced — in particular `xcodegen` is neither installed nor invoked,
and `tuist` is not used.

---

## Layout

| path | what it is |
|---|---|
| `FocusSentinel.xcodeproj/` | the **hand-authored, committed** Xcode project (see "The project file" below) |
| `Focus.xcworkspace/` | the workspace that owns the shared schemes; the unit lane lives here |
| `App/` | the thin app target — composition root, scenes, entitlements, and a deliberately empty string catalog (see "Strings" below) |
| `Packages/FocusCore` | domain types, SwiftData schema, status tokens, clocks, appearance traits |
| `Packages/FocusRules` | the deterministic rule model |
| `Packages/FocusClassify` | the classification seam — no networking, ever |
| `Packages/FocusSensing` | macOS observation adapters |
| `Packages/FocusUI` | every SwiftUI view, scene, command and design token |
| `Config/` | build inputs that are neither app source nor scripts. Exactly one file: `FocusSentinel-Info.plist`, the partial plist carrying `CFBundleURLTypes`. It lives here and **not** in `App/` — see "The project file" below |
| `scripts/` | the build gate and its fifteen stages, plus the five live evidence lanes |
| `Tools/windowid` | a test driver: window ids for `screencapture -l`, read from the public window list without ever asking for a window *name*. Not part of the shipping app's package graph |

---

## Build

```
xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/focus-dd build \
  > /tmp/focus-build.log 2>&1; echo "EXIT=$?"
```

Swap `-configuration Release` for the release build. **Never pipe a build's stdout** — redirect
it unpiped to a log file and gate on the explicit exit status. A build whose output was piped
into `tail` or `xcpretty` is not a verified build.

## Test

### The unit lane — this is the gate

```
RB="/tmp/focus-e01-$(date -u +%Y%m%dT%H%M%SZ)-$$.xcresult"; rm -rf -- "$RB"
xcodebuild -workspace Focus.xcworkspace -scheme FocusUnitTests \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/focus-dd \
  -resultBundlePath "$RB" \
  test > /tmp/focus-test.log 2>&1; echo "EXIT=$? RB=$RB"
```

The unique, freshly-removed `-resultBundlePath` is **part of the command, not decoration**:
`xcodebuild` refuses to write over an existing result bundle and exits `64` *before running a
single test*, which would make every second run fail for a reason that has nothing to do with
the code.

`FocusUnitTests` is a **committed shared scheme**. Xcode's implicit package schemes are not
configured for the test action and cannot run package tests at all, so the scheme is
hand-authored and lives at
`Focus.xcworkspace/xcshareddata/xcschemes/FocusUnitTests.xcscheme`.

### `swift test` — inner loop only, never trusted for localisation

```
cd Packages/FocusCore && swift test
```

This is the fast inner loop and nothing more. **It must never be treated as the gate.** SwiftPM
copies `.xcstrings` String Catalogs into the resource bundle *verbatim*, while `xcodebuild`
compiles them into `en.lproj/Localizable.strings`. Under `swift test` a localisation lookup
therefore returns the raw key and a localisation assertion is meaningless. Every
localisation-dependent test is gated on `LocalizationLane.catalogsAreCompiled` and reports
`skipped` here; the same tests run for real under `xcodebuild test`, and a further test — gated
on the scheme-injected `FOCUS_GATE_LANE=xcodebuild` — asserts that the gate lane really is the
compiling lane, so the mis-pass can never come back silently.

## The gate

```
scripts/build-gate.sh
```

Runs every stage, redirecting each one unpiped to its own log, and exits non-zero if any stage
failed. It never short-circuits: a failing early stage does not hide a later one.

**Every invocation owns its paths.** The derived-data tree, the log directory (and so the gate
log, every stage log and both self-check reports) and the result bundle are all derived from a
per-run token, so two gate runs at once cannot braid their output into one file that describes
neither of them. The cost is that a default run builds cold; set `FOCUS_DERIVED_DATA` to reuse
a warm tree when you are the only run.

**And every green invocation gives those paths back.** A per-run derived-data tree is about
750 MB, so a gate that only ever created them turned a green day into gigabytes of dead
scratch — and a build that then dies on a full volume does not fail a check, it produces no
exit status at all, which is the least legible way for a gate to break. A passing run therefore
deletes its own derived data and result bundle; a **failing** run keeps both, because the
inside of a failed build is what you need next. The log directory is never deleted either way —
the stage logs are the evidence, and they are kilobytes. A pinned `FOCUS_DERIVED_DATA` or
`FOCUS_RESULT_BUNDLE` is left alone (it belongs to whoever pinned it), and
`FOCUS_KEEP_DERIVED_DATA=1` keeps a green run's tree as well. The stages:

| # | stage | what it proves |
|---|---|---|
| 1 | `verify-project.sh` | the project file parses, and git has not been rewritten behind you |
| 2 | `check-boundaries.sh` | the package import matrix holds; zero third-party dependencies |
| 3 | `check-forbidden.sh` | no `kCGWindowName`, no Apple Events, no private APIs, no plan-less `ModelContainer` |
| 4 | `check-strings.sh` | no hardcoded user-visible string; the catalogs and the code agree both ways |
| 5 | Debug build | `EXIT=0` |
| 6 | Release build | `EXIT=0` |
| 6a | packaging | read from the two logs and the two products stages 5 and 6 just made: neither log contains `Copy Bundle Resources build phase contains`, neither product ships a `Contents/Resources/Info.plist`, and the merged `Contents/Info.plist` carries both the `focus` scheme and every generated key. See "The project file" |
| 7 | the unit lane | every package test target, headless |
| 7b | `check-boundaries.sh` again | `nm -u FocusClassify.o` has no networking symbol — the binary-level form of the assertion, which needs a build product to exist |
| 7c | `check-forbidden.sh` again | the binary half of SC-1: `nm -u` finds no `_kCGWindowName` in **seven products named one by one** — the app binary, `FocusCore.o`, `FocusSensing.o`, `FocusRules.o`, `FocusClassify.o`, `FocusUI.o` and `Tools/windowid` — while the four sanctioned window-list symbols are asserted **present** in `windowid`, so the check cannot pass by the tool being gutted. Under `FOCUS_REQUIRE_BINARY_CHECK=1` a *missing* product is a failure, not a skipped line. `windowid` is built by the stage itself, because it lives outside the workspace scheme |
| 8 | `entitlement-check.sh` ×2 | no network entitlement, Debug **and** Release; and `get-task-allow` present in Debug, **absent** in Release |
| 9 | `self-check.sh` ×2 | the app's own zero-grant report of its menu bar, window and key equivalents — and, from e02, its declared URL schemes, its hot-key registration status, the Edit menu's undo title after one scripted in-process mutation, the pre-built capture panel's show latency, and the priority hero's point size against every other type role. From e03 it is **three launches**: the shell report, plus a session seeded back-dated ninety minutes into a store of its own and a **separate** launch that restores it. See "What the self-check adds in e03" below |
| 10 | `verify-project.sh` again | the build did not rewrite the project |

**Fifteen stages.** The count matters because the epic's close condition names it: `project`,
`boundaries`, `forbidden`, `strings`, `build-debug`, `build-release`, `packaging`, `unit`,
`boundaries-binary`, `forbidden-binary`, `entitlements-debug`, `entitlements-release`,
`selfcheck-debug`, `selfcheck-release`, `project-post`.

### What the self-check adds in e03

Every one of these is asserted with **no TCC grant**, for the app or for the shell, which is why
they are part of the pass/fail contract rather than evidence:

* **The global switch detaches.** `SensingHost.pause()` removes every notification observer token,
  invalidates the corroboration tick and removes every CoreAudio property listener; the report
  carries the live observer count before, after and after resuming, and the checker asserts
  `n > 0 → 0 → n`. The graph is attached first where the person had the switch off, so the probe
  proves something whatever their setting is, and the stored setting itself is never touched.
* **Nothing named a window.** The seven decoded window-list keys, verbatim, with `kCGWindowName`
  asserted absent and no decoded key naming a window rather than its owning application.
* **Both idle sources.** `.hidSystemState` and `.combinedSessionState`, with the hardware figure
  asserted no smaller. The two are read microseconds apart, session first, so the elapsed time
  between them lands on the side the invariant wants it on.
* **The camera path was never entered.** `cameraState` is `unavailable` unconditionally,
  `cameraRunning` is `false`, and `cameraListenersInstalled` is `0` — on every rig, camera or not.
  That is the assertion, rather than an assertion about this Mac happening to have no camera.
* **No authorisation surface on screen.** The grant-free scan of every on-screen window owner
  finds none of `UserNotificationCenter`, `SecurityAgent`, `universalAccessAuthWarn`, `tccd`,
  `TCCAgent` or `CoreAuthUI` while the app runs. This is the gateable form of "the app never
  triggers a permission prompt".
* **The relaunch-mid-session proof, across two processes.** `--focus-session-seed` writes a
  session back-dated ninety minutes into a temporary store and exits; `--focus-session-restore`
  opens it in a **separate** launch and reports. Asserted: `startedAt` byte-identical, elapsed
  within two seconds of 5 400, `phase == paused`, `pauseCauses == ["relaunch"]`,
  `resumeTo == "focus"`, the same non-empty boot identity in both, and — the one thing no unit
  test can reach, because it cannot span a process boundary — the uptime anchor's difference
  between the two launches matching their wall-clock difference to within a second.
* **The key-equivalent probes changed nothing they do not own.** The stored watching switch is
  read before and after and asserted equal. That assertion is not decorative: it is what caught
  `Pause Watching` on ⇧⌘W being reached by a synthesised plain ⌘W and flipping the switch on
  three consecutive runs. The shortcut moved to ⌃⌘E, and no two shell actions now share a base
  character.

---

## Verification

There are two kinds of check in this repository and the difference is not a matter of taste.

**The gate runs with zero TCC grants — for the app *and* for the shell that invokes it.**
Nothing above needs Accessibility, Screen Recording or Automation. Revoke every permission on
this Mac and the gate must still be green; that is the contract, and it is why the app reports
its own menu bar from inside its own process instead of being interrogated from outside.

**The live lanes need three grants and are therefore evidence, never a criterion.** They drive
the real app with `osascript` and capture its windows with `screencapture`, which works only
because the driving shell holds Accessibility, Automation and Screen Recording. No acceptance
criterion may depend on a permission grant, so what these lanes produce is quality evidence a
human reads. When a grant is missing each one prints `LIVE-LANE SKIPPED: <grant>` and exits
`0`, and `build-gate.sh` never invokes any of them.

**Not a gate is not the same as not honest.** Once the grants are present and a drive begins,
`live-capture-drive.sh` and `live-handoff-drive.sh` check each frame's *semantic* precondition
before taking it — the frontmost window really is the surface the frame is named for, its
Accessibility frame really matches a window-list entry (there is no "use the front-most window"
fallback), no sheet is in front of a cockpit frame, the expected context chips are present and
the link chip shows an **origin**, Quick Look really opened, and the priority behind a cancelled
handoff really is unchanged. Every frame is deleted before the drive starts, so a stale PNG can
never stand in for one this run failed to take. A required frame that cannot be produced prints
`LIVE-FRAME FAILED` and the run **exits non-zero**; an optional one writes an explicit
`<frame>.SKIPPED.txt` marker saying why. A non-zero exit from these lanes means the evidence set
is incomplete — never that a gate failed, because they are not one.

| lane | what it drives | what it leaves to read |
|---|---|---|
| `scripts/live-shell-drive.sh` | the shell: window, menu bar, settings, appearance variants | `menus.txt` and the shell frames |
| `scripts/live-capture-drive.sh` | the **real global hot key** with another app frontmost, a vague intent answered constructively, the context pack, Quick Look, and the Edit menu's undo action name | `hotkey-untrusted.txt`, `capture-panel.png`, `capture-vague.png`, `cockpit-priority.png`, `context-chips.png`, `quicklook.png`, `undo.png` |
| `scripts/live-handoff-drive.sh` | `open 'focus://start?task=…'` against a **registered** copy of the product, then cancelling it | `handoff-confirm.png`, `handoff-transcript.txt` |
| `scripts/live-sensing-drive.sh` | two real decoy applications opened with `open -a`, a real screen lock (`pmset displaysleepnow` + `caffeinate -u`), the exported event stream, and both TCC databases before and after | `sensing-report.txt`, `activation-timeline.json`, `cockpit.png`, `idle-transition.json`, `lock-transition.json`, `tcc-diff.txt`, `no-prompt-frames/` — plus receipts for `pause-resume.png`, `fullscreen.*`, `space-change.json`, `media-transition-mic.json`, `media-transition-camera.json` and `sleep-wake.txt` |
| `scripts/live-session-drive.sh` | two separate process launches that seed and restore a session, then a `pkill` mid-session and a relaunch | `session-reconciliation.json`, `relaunch-mid-session.png` |

**The e03 lanes are not uniformly automated, and they say which parts are which.** Every artefact
carries one of three labels, and the scripts behave accordingly rather than implying unattended
generation:

| label | meaning | what the script does |
|---|---|---|
| **AUTOMATED** | produced unattended, given the grants | runs it, writes the artefact |
| **OPERATOR-ASSISTED** | a human must perform **one physical action** at a prompt — switch Space, enter full screen, open a microphone, press Start Session | prints the instruction, waits with a timeout, then captures; on timeout writes `<artefact>.MANUAL_REQUIRED.txt` naming the action that was not performed, and continues |
| **UNAVAILABLE ON THIS RIG** | this machine physically cannot produce it | **does not pretend to try**: writes the receipt immediately, stating the hardware or configuration fact, the exact steps to reproduce it elsewhere, and what the reader should confirm |

Two artefacts are permanently in the third category, and both receipts say so at length. A real
system **sleep** is not drivable here — this Mac is configured never to sleep, has not slept in
8.55 days, and forcing one would suspend the process running the lane — so the screen lock is
driven instead and the sleep is documented. A real **camera** transition cannot happen at all:
this Mac has no camera, CoreMediaIO enumerates zero devices, and the camera path is switched off
in this version on *every* Mac regardless, with the gate asserting the held path was never
entered. Turning it on needs a re-probe on camera hardware against a written checklist, and that
re-probe is explicitly **not** a close condition of this epic.

**Neither e03 lane uses `osascript`, and that is a rule rather than a preference.** Measured:
`osascript -e 'quit app "TextEdit"'` blocks on Automation consent and has to be killed. Decoys are
opened with `open -a` (LaunchServices, no TCC) and terminated with `pkill` (POSIX, no TCC). The
consequence is stated rather than worked around: with no Apple Events and no Accessibility, these
lanes cannot send a click or a keystroke, so an artefact that needs one is labelled
OPERATOR-ASSISTED instead of being faked. What is never lost by that is an *assertion* — every
claim those frames illustrate is already proved at zero grants by `scripts/self-check.sh`.

Two things about those lanes are not decoration.

**The hot-key lane is the only place the grant-free claim can honestly be made.** A process
`exec`'d from a shell that already holds Accessibility inherits that shell's TCC responsibility
and reports `AXIsProcessTrusted() == true`; `self-check.sh` launches the binary exactly that
way, so its `axIsProcessTrusted` field is **recorded and never asserted**. The honest form needs
the app to be its own responsible process (`open -n -a`) with its own approval cleared first
(`tccutil reset Accessibility com.chrismitchelmore.FocusSentinel`, which touches only this app's
row). That transcript is `hotkey-untrusted.txt`. The gateable half — registration returning
`noErr`, a second offer of the same combination returning `-9878`, the panel pre-built and
shown in under 250 ms — is asserted at zero grants by stage 9.

**The handoff lane mutates the machine, which is the second, independent reason it can never be
a gate step.** An app under `/private/tmp` registers with `bundle flags: in-temp-dir` and
resolves *no* handler for `focus:`, so the only way to drive the scheme for real is to copy the
product to `~/Applications` and `lsregister` it. The script does that under a name that marks it
as this lane's litter (`FocusSentinel-live-handoff.app`) and **unregisters and deletes the copy
on exit, including on failure**, through a `trap` armed before the copy is made. If it ever
cannot, the summary says so in the loudest terms it has. Nothing under `~/Applications` is ever
committed.

Reproducing each lane by hand:

```
# builds
xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/focus-dd build \
  > /tmp/focus-build.log 2>&1; echo "EXIT=$?"

# the unit lane (see the result-bundle rule above)
RB="/tmp/focus-e01-$(date -u +%Y%m%dT%H%M%SZ)-$$.xcresult"; rm -rf -- "$RB"
xcodebuild -workspace Focus.xcworkspace -scheme FocusUnitTests \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/focus-dd \
  -resultBundlePath "$RB" test > /tmp/focus-test.log 2>&1; echo "EXIT=$? RB=$RB"

# the static gates
scripts/verify-project.sh   > /tmp/focus-project.log    2>&1; echo "EXIT=$?"
scripts/check-boundaries.sh > /tmp/focus-boundaries.log 2>&1; echo "EXIT=$?"
scripts/check-forbidden.sh  > /tmp/focus-forbidden.log  2>&1; echo "EXIT=$?"
scripts/check-strings.sh    > /tmp/focus-strings.log    2>&1; echo "EXIT=$?"

# entitlements and the zero-grant self-check, on both configurations
scripts/entitlement-check.sh /tmp/focus-dd/Build/Products/Debug/FocusSentinel.app   Debug
scripts/entitlement-check.sh /tmp/focus-dd/Build/Products/Release/FocusSentinel.app Release
scripts/self-check.sh        /tmp/focus-dd/Build/Products/Debug/FocusSentinel.app
scripts/self-check.sh        /tmp/focus-dd/Build/Products/Release/FocusSentinel.app

# the TCC-gated evidence lanes — read the frames they capture; capturing them is not the point
scripts/live-shell-drive.sh
scripts/live-capture-drive.sh
scripts/live-handoff-drive.sh
scripts/live-sensing-drive.sh
scripts/live-session-drive.sh
```

Never pipe any of it. Redirect unpiped to a log and gate on the explicit exit status.

### Environment contracts

| variable | used by | meaning |
|---|---|---|
| `FOCUS_RUN_TOKEN` | the gate | the per-run suffix every default path is derived from. Default `<UTC timestamp>-<pid>` |
| `FOCUS_DERIVED_DATA` | the gate, `check-boundaries.sh`, the live lane | build location. Gate default `/tmp/focus-dd-$FOCUS_RUN_TOKEN`; the live lane's own default is `/tmp/focus-dd`. Pin it to reuse a warm tree — a pinned path is also never deleted by the gate |
| `FOCUS_LOG_DIR` | the gate | where the gate log, every stage log and both self-check reports are written. Default `/tmp/focus-gate-$FOCUS_RUN_TOKEN`. Never deleted: these logs are the evidence |
| `FOCUS_RESULT_BUNDLE` | the gate | the unit lane's `-resultBundlePath`. Default `$FOCUS_LOG_DIR/focus-e01-$FOCUS_RUN_TOKEN.xcresult`; either way it is `rm -rf`'d immediately before the run, and a green run removes it again afterwards unless it was pinned |
| `FOCUS_KEEP_DERIVED_DATA` | the gate | set to any value to keep a **green** run's derived data and result bundle. A failing run always keeps them |
| `FOCUS_EVIDENCE_DIR` | the gate, `self-check.sh`, the live lanes | where the evidence set is assembled, under the canonical names below. Default for `live-shell-drive.sh`: `.agents/evidence/e01`; for `live-capture-drive.sh` and `live-handoff-drive.sh`: `.agents/evidence/e02`. **Never committed** |
| `FOCUS_SNAPSHOT_OUT` | the snapshot lane, the gate | where snapshot renders are written. Default `$TMPDIR/focus-snapshots`. `xcodebuild` carries no value into a SwiftPM test target's environment — measured both by inheriting the shell's environment and by a scheme `<EnvironmentVariable>` expanding a command-line build setting, and neither reaches the test — so under the gate this names where to *look*, not where to write. The gate copies from it into `$FOCUS_LOG_DIR/snapshots` and collects evidence from the copy |
| `FOCUS_SNAPSHOT_RECORD=1` | the snapshot lane | re-record the committed baselines instead of comparing. `swift test` only, for the same reason. Recorded PNGs are read by eye before being committed |
| `FOCUS_FIXTURE_RECORD=1` | `MigrationFixtureTests` | rewrite the committed v1 store fixture instead of asserting against it |
| `FOCUS_SELFCHECK_JSON` | `self-check.sh` | where the app's self-check report is written |
| `FOCUS_OPERATOR_TIMEOUT` | `live-sensing-drive.sh`, `live-session-drive.sh` | seconds to wait at each operator prompt before writing a `MANUAL_REQUIRED` receipt and continuing. Default 45. An unattended run has no terminal to read from and reaches the timeout at once, which is what should happen — the alternative is a lane that hangs a nightly run for ever |
| `FOCUS_LIVE_TEXT_SIZE=raised` | the live lanes | capture `main-accessibility.png` (shell lane) and `cockpit-accessibility.png` (capture lane) — only meaningful once the system-wide Text Size has been raised by hand, because macOS has no injectable Dynamic Type. The zero-grant equivalent is the snapshot lane's `ShellTextScale` matrix plus `DynamicTextResilienceTests` |

### Evidence

With `FOCUS_EVIDENCE_DIR` set, the gate assembles `gate.log`, `build-debug.log`,
`build-release.log`, `test.log`, `project.log`, `boundaries.log`, `forbidden.log`,
`strings.log`, `packaging.log`, `entitlements.txt`, `selfcheck.json`, `selfcheck.log`, their
Release counterparts, and a `snapshots/` copy of every render. The live lanes add `menus.txt`,
the shell frames, the capture and handoff frames and their two transcripts to the same
directory when the grants exist. That directory is evidence, not source: it is never
committed.

---

## Strings

Every string a person can read comes from a String Catalog and is reached through a generated
typed symbol — never a bare literal, never `String(format:)`. `scripts/check-strings.sh` is a
gate stage and checks both directions: no hardcoded user-visible literal, and no key that is
in a catalog but unused or used but missing.

There are three catalogs and each module resolves its own against its own bundle, so they are
checked separately:

| catalog | keys | who reads it |
|---|---|---|
| `Packages/FocusUI/Sources/FocusUI/Resources/Localizable.xcstrings` | `shell.`, `settings.`, `priority.`, `capture.`, `context.`, `handoff.` | `FocusUI`, and the app target through `ShellStrings` |
| `Packages/FocusCore/Sources/FocusCore/Resources/Localizable.xcstrings` | `status.` (the `FocusStatus` short labels) and `undo.` (the action names the system Edit menu draws after "Undo") | `FocusCore` |
| `App/Localizable.xcstrings` | **none, by design** | nothing yet |

The app target's catalog is empty because the app target is a composition root: it declares
scenes and wires concrete types to protocols, and even its window titles are `FocusUI` keys
resolved from `FocusUI`'s bundle. The file is kept rather than deleted because it is the
declared home for anything the app target ever does own, and because deleting it would remove
the `App` row from the lint's table — the only check that would notice an app-target source
starting to name a catalog key that its bundle cannot resolve. So the lint asserts the
emptiness instead: `App` is listed in `EXPECTS_NO_STRINGS`, and a key appearing there fails
the gate with instructions to move it to `FocusUI` or to change the list on purpose.

## The project file

`FocusSentinel.xcodeproj/project.pbxproj` is **hand-authored source**, not generated output.
There is no generator and no regeneration command — by design.

* Object ids are stable and human-assigned from documented blocks; they are never randomised.
* File membership is directory-implicit through a `PBXFileSystemSynchronizedRootGroup`, so
  adding a Swift file under `App/` touches no project file at all. The project changes only
  when a target or a package reference is added.
* `scripts/verify-project.sh` proves the file still parses and then runs
  `git diff --exit-code -- FocusSentinel.xcodeproj Focus.xcworkspace`.

Scalar Info.plist keys are `INFOPLIST_KEY_*` build settings, so the project file stays their
single home. `CFBundleURLTypes` cannot be one — it is an array of dictionaries — so it ships as
a partial plist merged with the generated one: `GENERATE_INFOPLIST_FILE = YES` **and**
`INFOPLIST_FILE = Config/FocusSentinel-Info.plist`, two lines, one per configuration.

**That path is load-bearing.** `App/` is a `PBXFileSystemSynchronizedRootGroup`, so a plist
placed there is a target member by existence alone: it joins Copy Bundle Resources, the build
log gains `warning: The Copy Bundle Resources build phase contains this target's Info.plist
file …`, and the product ships a second, misleading `Info.plist` inside `Contents/Resources/`
— all of it while the build stays green. `EXCLUDED_SOURCE_FILE_NAMES = Info.plist` does not
suppress it. Keeping the file outside every synchronized group does, which is what `Config/` is
for, and gate stage 6a asserts the result on both configurations rather than trusting the exit
status.

Opening the project in Xcode.app for inspection is permitted. **If Xcode rewrites the project
or a shared scheme, that rewrite must be reverted, never committed** — restore it from git (or
from Appendix A of the epic plan, which carries the canonical bytes) and re-run
`scripts/verify-project.sh`.

## Distribution posture

This Mac holds exactly one code-signing identity (`Apple Development`) and zero
`Developer ID Application` identities, and the product policy is a local app. The shipped
artefact is an **ad-hoc-signed local `.app`**. There is no notarisation, no Developer ID
signing, no App Store submission and no hardened runtime — not in this epic and not in a later
one.

Because the Release product *is* the shipped artefact, it does not carry
`com.apple.security.get-task-allow`. Ad-hoc signing injects that entitlement into both
configurations by default; the Release configuration sets
`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` to keep it out, Debug sets it to `YES` deliberately
so a debugger can still attach, and `scripts/entitlement-check.sh` asserts both directions.

## Privacy posture

No accounts, no telemetry, no analytics, no third-party packages: every `Package.swift` in this
repository declares an empty `dependencies` array, and the check that asserts it is a gate
stage. The app ships with no network entitlement, and `FocusClassify` carries a
zero-networking assertion that fails closed.
