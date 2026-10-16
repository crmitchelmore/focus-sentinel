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
| `App/` | the thin app target — `@main`, the scenes, the appearance observer, the entitlements, the icon, and the seven main-bundle App Intents metadata strings (see "Strings" below). It owns no host and no wiring: those are `Packages/FocusHost` |
| `Packages/FocusCore` | domain types, SwiftData schema, status tokens, clocks, appearance traits |
| `Packages/FocusRules` | the deterministic rule model |
| `Packages/FocusClassify` | the deterministic relevance engine and the classification seam — no networking, ever |
| `Packages/FocusEvaluate` | the evaluation lane: `FocusEvaluateCore` and the `FocusEvaluate` product, test-lane only, which no application target links. It sat inside `FocusClassify` until e06, which needed a model package that depends on the engine *and* an evaluation lane that depends on the model — a cycle, because SwiftPM dependencies are package-level |
| `Packages/FocusSensing` | macOS observation adapters |
| `Packages/FocusUI` | every SwiftUI view, scene, command and design token |
| `Packages/FocusUpdates` | the updater (focus-h8jf): `SparkleUpdater`, the one package that may import the one third-party framework this repository ships. Inert until the person switches update checks on in Settings ▸ General; see "Release trains" |
| `Packages/FocusHost` | the composition layer — `AppComposition` and the five hosts. The only module that imports more than one sibling package, and the reason it is a package rather than the app target is that `App/` is not one: no test bundle could import it, so every claim about the wiring in it was a source scan (see "Why the composition layer is a package" below) |
| `Config/` | the partial app plist, test-count floors, performance budgets and verification contracts. The plist lives here rather than in `App/` — see "The project file" below |
| `scripts/` | the build gate and its twenty-seven stages, plus the six live evidence lanes |
| `script/build_and_run.sh` | the local build-and-launch entrypoint; refuses to stop a different checkout's running app |
| `Tools/windowid` | a test driver: window ids for `screencapture -l`, read from the public window list without ever asking for a window *name*. Not part of the shipping app's package graph |

---

## Build

For the local run loop, use `script/build_and_run.sh`. It supports `--debug`, `--logs`,
`--telemetry` and `--verify`; the last confirms that the built executable stays running.
`FOCUS_DERIVED_DATA` and `FOCUS_LOG_DIR` override its workspace-local build and log paths.
Coordinate runtime and snapshot lanes with other agents before launching. The full release
verification remains `scripts/build-gate.sh`.

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
| 3 | `check-forbidden.sh` | no `kCGWindowName`, no Apple Events, no private APIs, no plan-less `ModelContainer`, and (R-97) no SwiftData fetch outside the counting wrappers — see "What the tick costs" |
| 4 | `check-strings.sh` | no hardcoded user-visible string; the catalogs and the code agree both ways |
| 4' | `glyphs` | **the five status marks are the app's own, and no two of them are alike at the size they ship at.** Two halves. `scripts/make-status-glyphs.py --check` re-renders the family from its own geometry on a 16-unit grid and compares the committed PNGs byte for byte, so a hand-edited asset — or two states' files swapped — cannot survive; the distance fold alone could not catch that, because a pairwise measure over a set is invariant under permuting the set. `scripts/glyph-distance.py` renders **all ten images the menu bar can draw** (five states × with and without the attention mark composited into the top-trailing corner), blurs them, and holds every pair above `Config/glyph-distance-floor.txt`. It is a sibling of `frame-ink.py`: the doctrine `FocusStatus` has stated since e01 — "silhouettes are deliberately unalike … even in monochrome at small sizes" — was a sentence and one person's reading of five SF Symbols that no longer ship, and is now a number. It earned its keep on the way in: the family the design canvas settled measured **1.43** on the tightest pair and the geometry was amended until it measured 10.75. **And it is what let the second silhouette go** (focus-w41.6): `StatusBadge` drew `StatusOutline(status.shape)` *behind* the mark, which was coherent while the mark was an SF Symbol and is two different marks for one state now that it is the family's own — `unrelated` was a three-quarter arc and its dot inside a triangle. The outline is no longer drawn; `FocusStatus.shape` stays as the vocabulary naming each mark's outline, which is what the accessibility description and this gate's own pair-naming read |
| 5 | Debug build | `EXIT=0` |
| 6 | Release build | `EXIT=0` |
| 6a | packaging | read from the two logs and the two products stages 5 and 6 just made: neither log contains `Copy Bundle Resources build phase contains`, neither product ships a `Contents/Resources/Info.plist`, and the merged `Contents/Info.plist` carries both the `focus` scheme and every generated key. See "The project file" |
| 6b | `eval-clean` | **the only cleanup stage in the gate.** It removes `$FOCUS_EVAL_OUT` (default `$TMPDIR/focus-eval`) in its entirety and touches an mtime marker, immediately before `unit`. A missing directory is a pass; a failure to remove is a hard fail. See "The evaluation lane" below for why a gate needs one |
| 7 | the unit lane | every package test target, headless |
| 7' | `unit-counts` | **the gate can see a test bundle die.** Reads the unit lane's own log: no `Program crashed`, no `Restarting after unexpected exit`, no `Test Suite 'Selected tests' started` retry banner — *regardless of exit status*, because a retry that then passes exits `0` having run a fraction of the suite — six `Test run with N tests` summaries, and each `>=` its committed floor in `Config/test-floors.txt`, paired positionally with the scheme's testables. Floors, never equalities: adding a test may not redden the gate and losing one must. See `focus-jg7`. **And the two wall-time budgets** (F-163): the same summary lines carry each bundle's own duration, and `FocusUITests` — the snapshot lane, the only one that renders — and the sum of all eight are held to `Config/performance-budgets.txt`. A lane reporting under 30 s is failed as *not run*, because every ceiling is satisfied by a lane that did nothing |
| 7d | `evaluation` | runs the `FocusEvaluate` **product**, copies its report into this run's log directory *before* anything parses it, applies five binding checks to that copy, and only then reports the metric verdict. See "The evaluation lane" |
| 7e | `evaluation-model` | **lane 2, and it is evidence rather than a gate on a model being present.** Runs `FocusEvaluate --model`, which writes `evaluation-model.json` and never touches lane 1's report. It exits on the *contract* half only — the bucket fold summing, the grid complete on both axes, no model answer reaching `unrelated`, no mandate moving, nothing answered on the classification path. The *quality* half (`seduced`, `rescueRecall`, `unstable`) is printed and archived and decides whether the tier is composed, which is a ruling made from an artefact. A Mac with Apple Intelligence off writes `{"status":"skipped","reason":"…"}` and exits 0, and the summary prints `SKIP` with the reason — an outcome, never a silent pass |
| 7b | `check-boundaries.sh` again | `nm -u FocusClassify.o` has no networking symbol — the binary-level form of the assertion, which needs a build product to exist |
| 7c | `check-forbidden.sh` again | the binary half of SC-1: `nm -u` finds no `_kCGWindowName` in **seven products named one by one** — the app binary, `FocusCore.o`, `FocusSensing.o`, `FocusRules.o`, `FocusClassify.o`, `FocusUI.o` and `Tools/windowid` — while the four sanctioned window-list symbols are asserted **present** in `windowid`, so the check cannot pass by the tool being gutted. Under `FOCUS_REQUIRE_BINARY_CHECK=1` a *missing* product is a failure, not a skipped line. `windowid` is built by the stage itself, because it lives outside the workspace scheme |
| 8 | `entitlement-check.sh` ×2 | no network entitlement, Debug **and** Release; and `get-task-allow` present in Debug, **absent** in Release |
| 9 | `self-check.sh` ×2 | the app's own zero-grant report of its menu bar, window and key equivalents — and, from e02, its declared URL schemes, its hot-key registration status, the Edit menu's undo title after one scripted in-process mutation, the pre-built capture panel's show latency, and the priority hero's point size against every other type role. From e03 it is **three launches**: the shell report, plus a session seeded back-dated ninety minutes into a store of its own and a **separate** launch that restores it. See "What the self-check adds in e03" below. From F-160 the first launch is **backgrounded and sampled**: `lsof -nP -i -a -p <pid>` every fifth of a second for as long as the process lives, the sample count held to a floor, every sample taken while it was alive, and not one socket — with the sampler first pointed at a process that opens a listening socket, so a clean reading cannot be a tool that cannot read |
| 9a | `check-focus-steal.sh` | **the panel takes nothing.** Launches the Debug app with `open -g -a` — a background application that has never been frontmost, which is the posture a nudge really fires in — shows the panel and asserts all four of R-89's grant-free readings. See "The nudge loop" below |
| 9b | `check-notification-denied.sh` | **F-73's degraded path, and what discharges standing condition 5 for e05.** Zero grants, no prompt of any kind, and every rung of the ladder still reaches an in-app surface; `requestAuthorizationCallCount == 0` — and, from focus-p3dl, *measured* as well as counted: the launch takes an authorisation-surface baseline before it starts and asserts that no dialog **arrived** while the ladder was driven |
| 9c | `check-focus-steal.sh` again | the same stage against the **Release** product — the artefact this programme ships. A whole-module-optimised binary is not the same binary, which is why the boundary and forbidden stages read both configurations; until this stage existed, every geometry reading in `check-focus-steal.sh` held of a build nobody installs |
| 9d | `check-notification-denied.sh` again | the same, for the routing half: the 160-cell rung fold, the 80-cell question fold and `requestAuthorizationCallCount == 0`, read from the Release product |
| 9e | `check-grants.sh` | **invariant I-3 — the app uses no grant it never asked for.** One fold over `Config/tcc-families.txt`, ten TCC-protected API families, and it reads both halves of the claim: no request selector in either configuration's Mach-O (`nm -u` ∪ `strings -a`), and, in this run's two self-check reports, no capability in a state the table does not allow, `requestAuthorizationCallCount == 0`, and no authorisation surface having **arrived** on screen while the app ran (the delta against a pre-launch baseline — focus-p3dl). See "What it says it does not do" |
| 10 | `verify-project.sh` again | the build did not rewrite the project |

**Twenty-seven stages — twenty until `focus-steal-release` and `notification-denied-release`
were added, twenty-three since e06 added `evaluation-model`, twenty-five since e10a added
`published-keys` and `release-artefact`, twenty-six since `grants`, and twenty-seven since e11b
added `glyphs`.** Saying so plainly, because the epic's close condition names the count:
`project`, `boundaries`, `forbidden`,
`strings`, **`glyphs`**, `build-debug`, `build-release`, `packaging`, `eval-clean`, `unit`, **`unit-counts`**,
`evaluation`, **`evaluation-model`**, `boundaries-binary`, `forbidden-binary`,
`entitlements-debug`, `entitlements-release`, `selfcheck-debug`, **`focus-steal`**,
**`notification-denied`**, `selfcheck-release`, **`focus-steal-release`**,
**`notification-denied-release`**, **`grants`**, **`published-keys`**, `project-post`,
**`release-artefact`**.

`published-keys` (R-168) exists because a quarter of what `SelfCheck` writes was read by nobody.
A fact nobody reads is not evidence; it is a number in a file. The read set is **instrumented**
rather than grepped — `scripts/keyreads.py` replaces every dictionary in a loaded report with one
that notes what is asked of it — because a grep over the readers over-counts (a name read in one
section counts as read in every section that spells it) and under-counts (`self-check.sh` indexes
dynamically, so the key is never a literal at the read site). Measured at the close of e10a: 772
keys published, 758 read, 14 listed with a reason in `Config/unasserted-keys.txt`, twelve of
which are properties of the machine the gate happens to run on. **Two were not** — the two that
named a bead rather than NONE-BY-DESIGN — and focus-psh closed both by *driving* the reading
rather than asserting harder about a value the run was handed: `sensing.wasRunningBeforeProbe` is
now one term of an asserted transition (`running → paused → running`, with `attachedForTheProbe`
naming which of the two starting worlds this run was in), and `relevance.verdict.band` is
asserted against the contract that gives it meaning (`band` is absent exactly when the verdict is
`uncertain`) beside a **driven** band: two snapshots the probe builds itself, one input, a
reverse-DNS subject no application on this Mac carries, and the band goes from absent to present
because of a rule the probe wrote. The list is now fourteen rows, every one NONE-BY-DESIGN.

`grants` (invariant I-3) exists because the zero-grant doctrine is cited by five epic plans and
was proved, until this round, by four unrelated readings about three families: SC-1's one
CoreGraphics key, R-33's eight source-level request calls, R-96s's five notification selectors in
the Mach-O, and one counter read out of the running app. Nothing said what the other seven
families were, and a family nobody names is a family nobody checks. `Config/tcc-families.txt` is
that enumeration — Accessibility, Screen Recording, Automation, notifications, camera,
microphone, input monitoring, location, contacts, calendar — and each row carries the selectors
that would mean the app can ask, the grant-free reading it really does make (the control, without
which "no request selector" is the same green a binary that dropped the framework would produce),
the capability it publishes, and the states that capability may be in. Five of the ten families
the app touches in no way at all; `microphoneActivity` reads `available` because
`kAudioDevicePropertyDeviceIsRunningSomewhere` is a device property any process may read and it
yields no audio.

**The doctrine became conditional on 2026-09-09** (`focus-exdi.4`, the owner's ruling of the day
before). PD-1's absolute form — *this app asks for no permission of any kind* — is replaced by:

> **The app asks for nothing unless the person switched that ask on.** On a default install
> nothing is asked, nothing prompts, and the capability table reads exactly as it did before.
> The only route from "not asked" to "asked" is a control the person operated.

Two grants may be switched on, in Settings ▸ Privacy: Accessibility and Screen Recording. Screen
Recording is read by nothing in this build — pixel capture is parked — and the pane says so beside
its switch, because a switch that takes a permission and spends it on nothing is the worst version
of this change. Accessibility is spent on one thing, described in the next paragraph. What
replaced the ban, rather than merely lifting it:

- the Screen Recording family's `banned` column names its **use** selectors, which are still
  absent from both configurations' Mach-O, because nothing reads what that grant unlocks; the
  Accessibility family's `banned` column now names only the write, act, observe and bulk-read selectors,
  and its use selectors are confined like the request selectors (next paragraph);
- their **request** selectors moved to `Config/grant-request-sites.txt`, which confines them to
  one named file — `SystemGrantRequester.swift` — and `check-grants.sh` proves that confinement
  from the source side while `check-forbidden.sh`'s R-33 proves it from the other, exempting that
  one path and nothing wider;
- the running-app reading is unchanged and still says what it always said: on a default install
  the request counter is zero and no consent dialog arrived while the app was up;
- `GrantGate` in `FocusCore` is the single place the rule lives, so "asked for something nobody
  switched on" is one function's behaviour rather than a property of every call site.

**A third grant, and the first this build spends: the calendar** (owner's request, 2026-09-12).
Settings ▸ Privacy carries a *Calendar* switch; turning it on is the only route to
`requestFullAccessToEvents`, confined to `SystemGrantRequester.swift` like the other two. Once
macOS answers yes, `EventKitCalendarReader` (FocusHost, the one package allowed EventKit) reads
the **start and end** of non-all-day, non-free events in a short window around now — never a
title, attendee, location or note — and the app stores none of it and writes nothing back. What
the busy times are spent on:

- **No timebox starts during a meeting or runs into one.** `CalendarAgenda.refusal` is the rule;
  `PriorityHost.setTimebox` refuses with no write, the timebox control disables the presets that
  would collide (the tooltip says why) and offers *Until the meeting* when there is room. Clearing
  a timebox is never refused.
- **Gate 13, `calendarMeeting`**, appended so gates 1–12 keep their numbers: while a meeting is
  on, questions and the nudge panel wait; the ambient glyph does not.
- The cockpit names the next meeting under the timebox, as a time, not a title.

The calendar row of `Config/tcc-families.txt` keeps the banned ways of asking that are not this
one (`requestAccessToEntityType`, write-only access, reminders) and the event-mutating selectors;
its `available` state is allowed for the same reason the other two opt-in rows allow it. A
hardened-runtime build needs `com.apple.security.personal-information.calendars`, so the
committed entitlement set carries it, and `NSCalendarsFullAccessUsageDescription` says in one
sentence what is read. On a default install nothing changes: the capability reads
`notRequested`, the request counter is zero.

**The Accessibility grant is now spent, on device, from 2026-10-15** (owner's ruling, issue #24).
A bundle identifier cannot tell one task from another inside a mixed-use application — GitHub
Copilot, a terminal, an editor, a browser — so a nudge that can only say "you are in Copilot" is
not accurate enough to be worth asking. Reading the *selected item* (the focused window's title,
the chat session, the project folder) is essential to accuracy, so the "nothing reads what the
grant unlocks" clause above is being replaced. What the replacement keeps:

- **still opt-in**: nothing is read unless the person switched Accessibility on in Settings ▸
  Privacy and macOS granted it; on a default install the capability table is unchanged;
- **on device only**: whatever is read stays on this Mac — no network, no export of raw titles,
  no telemetry; the socket readings above stay exactly as strict;
- **minimal and ephemeral**: only the focused window's title (and, where an app needs it, the
  selected row of its sidebar) of the frontmost application, read at nudge time, reduced to a
  short normalised subject before anything is stored; raw titles are never persisted;
- **confined**: the AX *use* selectors move out of `banned` into one registered reader file,
  proven by the same two-sided confinement the request selectors already have.

How it is built:

- `SelectedItemReader.swift` in `FocusHost` is the one file that calls
  `AXUIElementCreateApplication`, `AXUIElementCopyAttributeValue` and
  `AXUIElementSetMessagingTimeout`.
  `Config/grant-use-sites.txt` registers it; `check-grants.sh` proves the selectors appear there
  and nowhere else in source, and `check-forbidden.sh`'s R-33b exempts that one path from the
  ban the rest of the tree is held to;
- it reads only when the person's Accessibility opt-in is on and macOS reports the process
  trusted, and only from the frontmost application that e03's `SensitivityGate` already
  cleared — so a password manager or a private browser window is never read. Any other
  application may be read (the owner's follow-up widened the first round's short list to every
  app, because in practice every app is mixed-use);
- it looks inside the focused window before falling back to a window title,
  read-only, for a selected sidebar row (`AXSelectedRows` / `AXSelectedChildren`: a Mail
  mailbox, a Finder folder, a chat) or else the first heading of the main region (the Copilot
  app's "Session: …"). The walk is bounded: at most `SelectedItemSearch.maximumElements` (400)
  elements, depth 14, 150 ms in all, each message capped by a messaging timeout. One app's full
  tree took ten seconds to walk on the owner's Mac; the budget is why that never stalls a
  nudge. No other window, no other application; `kCGWindowName` stays banned (SC-1);
- **Browser content, not Safari as a catch-all** (owner's ruling, 2026-10-16): it reads the
  focused window's document URL, or the active web area's URL, never links within a page.
  `BrowserPage` keeps only the normalised HTTP(S) host and case-sensitive path: credentials,
  query and fragment are discarded before the value leaves the reader. This explicitly
  extends the earlier origin-only storage rule for learned browser rules, not activity rows.
  The question names that page. Before either **Yes** or **No**, its scope menu offers the
  exact page (the default), each enclosing path and its pages, or the whole domain. Subdomains,
  schemes and explicit ports remain distinct. “Exact page” ignores query and fragment.
  At the same rule authority, an exact page overrides its paths, the longest matching path
  overrides its domain, and the domain overrides an app-wide rule; contradictory equally
  specific rules stay uncertain. These are ordinary, removable task rules in the Rules pane;
- **No silent widening**: an unreadable browser URL never becomes a question about the whole
  browser. The shipping host also withholds app-wide questions when another application's
  session, document or selected view cannot be identified. The existing Privacy opt-in remains
  required; switching it off does not grant permission to guess. Failed browser reads do not
  reuse a previous tab's identity. Paths are redacted back to their origin in store exports;
- nothing writes, acts, observes or bulk-reads: an Electron app that exposes no tree until a
  client writes `AXManualAccessibility` stays unread below its title, by design;
- `SelectedItem.normalise` reduces the title, row or heading in memory to a label of at most 48
  characters — the app name, captions and editor decorations stripped, an uninformative text
  refused — and the raw text is dropped. The label is the `titleToken` subject
  `<bundle>::<label>` the question asks about and the rule the answer writes; a `titleToken` row
  in that form is live again, while a legacy single-word row stays retired;
- the decisions issue #27 asked for: the item is read on **every judgement**, not cached by
  time, because the dwell key is what notices a switch from one chat to another; a read that
  fails (a timeout, an exhausted budget) keeps the last non-browser item for **12 seconds**
  (`SelectedItemGrace`), per process, and an empty read or switching the opt-in off clears it;
  there are **no seed rules** — an item becomes a rule only when the person answers a question
  about it; and the label also reaches the engine as `titleTokens`, where it can only
  *corroborate* a relevant verdict (a context-pack keyword in the chat's name), never make one
  irrelevant (R-57: a label is prose, not evidence of distraction);
- Settings ▸ Privacy follows the grant once it is switched on: it says whether macOS allows it,
  offers *Open System Settings* (the exact list), *Check Again* and *Show Focus in Finder*, and
  explains the one failure macOS never does — a rebuilt or moved copy is a different app and has
  to be removed and added again. The pane re-reads the grant when the app becomes active and
  every half-second for two minutes after the person was sent to System Settings
  (`GrantAccessWatch`), reading without asking;
- the store export replaces every item subject's label with `selected-item`, so a label never
  leaves the Mac in an export either; the self-check publishes `accessibilityOptedIn` and
  `selectedItemReadCount`, and on a default store they read `false` and `0`.

`release-artefact` is the D-09 disk image, and it is described under **Distribution posture**
below.

The two Release twins exist because a gate audit on 2026-09-02 found that `focus-steal` and
`notification-denied` read the **Debug** product only, so `selfcheck-release` was the gate's
sole reader of a Release artefact and its versions of those readings are thinner. Every
assertion the two stages make now holds of the build that ships.

`unit-counts` exists because a gate run on 2026-09-02 went 19 stages green while a test bundle
died after its first suite: every test that ran passed, `xcodebuild` printed `** TEST FAILED **`
with no failing-test summary, and the run's total was 1729 against 1863 the run before. Nothing
compared those two numbers. A harness that can silently skip 177 tests and report green is a
proof that cannot fail, which is the thing this repository exists to be rid of.

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
* **Both idle sources, and the invariant that is actually true of them.** `.hidSystemState` and
  `.combinedSessionState` are both read and both published, at the `kCGAnyInputEventType`
  sentinel and again for each of four concrete event types — `.mouseMoved`, `.keyDown`,
  `.leftMouseDown`, `.scrollWheel`. The assertion is that **each concrete type's two figures
  agree within a second**, with a floor of four distinct types read so an empty list cannot
  satisfy it vacuously. This replaced a pin that asserted the hardware figure was never the
  smaller of the two, on the argument that the combined source counts a superset of the events
  the hardware one does. It does not: at the `~0` sentinel `.hidSystemState` returns
  IOHIDSystem's raw `HIDIdleTime`, which a HID device report resets even when no input event is
  produced, so the two sentinel figures can diverge by hours in either direction — measured on
  this Mac, 105.71 s against 14 850 s while nobody was in the room. That gap is still published,
  as a number rather than a verdict. `IdleReading.isIdle` now trusts
  `max(hardwareSeconds, sessionSeconds)`: either source having gone quiet for the threshold is
  enough to call the person away, because a silent counter is evidence of absence and a counter
  reset by a device nobody touched is not evidence of presence.
* **The camera path was never entered.** `cameraState` is `unavailable` unconditionally,
  `cameraRunning` is `false`, and `cameraListenersInstalled` is `0` — on every rig, camera or not.
  That is the assertion, rather than an assertion about this Mac happening to have no camera.
* **No authorisation surface arrived on screen, and it is a *delta*.** The grant-free scan of
  every on-screen window owner looks for `UserNotificationCenter`, `SecurityAgent`,
  `universalAccessAuthWarn`, `tccd`, `TCCAgent` and `CoreAuthUI` while the app runs. This is the
  gateable form of "the app never triggers a permission prompt" — and until focus-p3dl it was
  written as the different sentence *"no such window is on this Mac's screen"*. The difference was
  measured on 2026-09-05: an unrelated tool had a `UserNotificationCenter` alert open asking for
  access to a removable volume, and `selfcheck-debug`, `selfcheck-release` and `grants` all went
  red for a decision belonging to the person at the keyboard. A build gate does not get to dismiss
  somebody's permission dialog to make itself green. So every script that launches the app takes a
  **baseline** first — `Tools/windowid --window-owners`, every on-screen window as
  `<number>\t<owner>`, from a process that is not the one under test and before it exists — and
  names it in `FOCUS_AUTHORISATION_BASELINE`. A suspect window whose number is in the baseline is
  reported as **pre-existing**, by owner and count, and named in the assertion line so a reader can
  see what was excused; a suspect window that is not is a failure exactly as before. The
  subtraction is by window *number* rather than by owner, so a **second** dialog from the same
  process — one the app really did trigger — cannot hide behind the first one's row. The baseline
  carries its own takenness fact and the gate asserts it: a delta computed against a baseline
  nobody read is the whole suspect list under a kinder name.
* **The relaunch-mid-session proof, across two processes.** `--focus-session-seed` writes a
  session back-dated ninety minutes into a temporary store and exits; `--focus-session-restore`
  opens it in a **separate** launch and reports. Asserted: `startedAt` byte-identical, elapsed
  within two seconds of 5 400, `phase == paused`, `pauseCauses == ["relaunch"]`,
  `resumeTo == "focus"`, the same non-empty boot identity in both, and — the one thing no unit
  test can reach, because it cannot span a process boundary — the uptime anchor's difference
  between the two launches matching their wall-clock difference to within a second. Neither
  launch's composition root opens the person's store: a seed or restore launch gets an
  in-memory root, with or without `--focus-self-check`, unless `--focus-store` names a fixture
  (focus-k2in).
* **The key-equivalent probes changed nothing they do not own.** The stored watching switch is
  read before and after and asserted equal. That assertion is not decorative: it is what caught
  `Pause Watching` on ⇧⌘W being reached by a synthesised plain ⌘W and flipping the switch on
  three consecutive runs. The shortcut moved to ⌃⌘E, and no two shell actions now share a base
  character.

### What the self-check adds in e04

Two fields, and they are the third leg of a three-way agreement rather than a report:

* **`engineStamp`** — `EngineStamp.cacheKey`, read from the **live engine** so that its
  `embeddingRevision` component is the one the OS supplied at runtime. If Apple ships a new
  sentence-embedding asset in a point release, every distance the engine computes changes; a
  stamp that counted only our own edits would not say so, and the verdict cache e06 keys on it
  would serve stale answers for ever.
* **`policyDigest`** — the FNV-1a over the whole committed constant set.

Both are compared against the literals in `EngineStampTests` and `RelevancePolicyTests` — the
one place they are written down. The unit lane asserts them of the **test process**, gate stage
7d asserts them of the **evaluation report**, and `self-check.sh` asserts them of the **running
application** on both configurations. A report generated against a different policy version
therefore cannot certify this build, and neither can a product built against one.

Beside them the report carries what the engine actually did in that process, at zero grants: the
classifier the composition root published **is** the engine object (not a second one), the rule
snapshot was built and was built under the running policy, at least one judgement was made, the
session-rule box is empty because nothing in this epic writes to it — and **nothing is
mandated**, because there is nothing in this build to consume a mandate.

---

## What the tick costs

The five-second corroboration tick is the app's heartbeat, and until focus-tzj it fetched things
that could not have changed: the **whole** `PriorityTask` table, sorted in Swift, to draw a list
of eight; today's **whole** intervention log and a query receipt, both before gate 1 was
consulted, so somebody with no commitment at all paid for them twelve times a minute; and a
CoreAudio device enumeration, while a property listener sat on every one of those devices for
exactly that purpose. None of it shows in a stopwatch on a store with four rows in it, which is
why the reading is a **count** rather than a duration.

`StoreFetchCounter` takes that count inside `ModelContext.countedFetch(_:)` and
`countedFetchCount(_:)`, and `check-forbidden.sh`'s R-97 bans the bare calls everywhere in the
shipping sources but the file that defines them — so a fetch that is not counted does not compile
past the gate, and the reading can never become a number about *some* of the fetches.

`SelfCheck.tickFetchSurvey()` drives the tick's two store-touching halves on a store of its own,
in three states, ten ticks each, and publishes the first tick beside the nine after it; the first
is the non-vacuity control, because every other row is a ceiling on ticks that fetch almost
nothing. `self-check.sh` pins all of it in both lanes, and `TickFetchBudgetTests` asserts on the
same survey so the gate's number and the suite's cannot drift apart.

The popover has its own version of the same reading: an open popover was rebuilt — one hosting
controller for the content and two more to measure it — on every tick, whatever it was drawing.
`popover.rebuild` in the self-check report is the count of builds and of hosting controllers, over
twenty ticks in which the presentation moved exactly twice.

**The numbers are committed** (F-163). `Config/performance-budgets.txt` carries nine rows — the
three per-state tick budgets, the nudge and popover halves that must be zero, the two popover
rebuild budgets, and the two lane wall times — each beside the measurement it was derived from and
its headroom ratio. The binding rule is the roadmap's: they were read off a green run first and
committed before the checks that read them were written, and a budget is never weakened to make a
run green. A budget with more than 3× headroom has to justify itself in its own sentence or be
tightened, which is why seven of the nine sit at 1.0× or exactly zero: they are counts of things
that should not happen, and a count like that has no headroom to have.

**No `XCTCPUMetric`, no `os_signpost`, no `powermetrics`.** `powermetrics` needs root (Court
ruling, retained). The other two would measure the machine the gate happens to be running on. What
this app has instead is better: the tick's cost does not show up in a stopwatch on a store with
four rows in it, it shows up as a count of store fetches and of hosting controllers, and those
counts are the app's own and published every run.

## Retention

Three tables grew without bound, and the code that would have trimmed them —
`InterventionLog.purge(before:)`, `QueryLedger.purge(priorityID:)`, `purgeAll()` — had **zero
callers**. `RetentionSweep` is the caller, and it runs once at launch and once per local day from
the tick that already computes the day boundary.

**The window is the person's** (F-115). Settings ▸ Privacy offers 7 days, 30 days, 90 days and
forever; the choice is a column on the store's v8 `PrivacyPreferencesRecord`, and the sweep reads
it at the top of every run rather than being built with it. That distinction is the whole of the
feature: the number shipped as a constant baked into an object the app built once at launch, so a
control on top of it would have written a column nothing read. `RetentionSweep.Result` carries the
window the run kept, so *which* promise a sweep kept is a published fact. Ninety days remains the
committed default — an upgrading store has no row, answers ninety, and nobody's history is
shortened by the arrival of a picker. **Forever is a branch, not a distant date**: the sweep runs
and touches nothing, rather than computing a cutoff no row happens to fall before. Choosing a
window sweeps immediately in both directions, because a promise with a day's delay in it is not
the promise the sentence in the pane makes.

**Query receipts are the exception.** A receipt is what gate 11 reads, so deleting one puts a
question the person has already answered back on the ladder. A receipt goes only when it is old
*and* the priority it was written under is old. The self-check publishes the launch sweep's day
and row counts, and — because on a fresh machine those are three zeroes and a date — runs the
same sweep again over a store it seeds at 89 and 91 days, which is what makes the section able to
go red. Both of those readings would be identical if the sweep had gone back to a constant, since
ninety days is what an untouched store answers, so a **third** seeded store sets seven days
through the verb the pane's control calls and holds rows at 6 and 88 days — where the default
would remove neither. The gate also presses the control itself: the pane's own sink, the window
read back out of the store, the window the triggered sweep kept, and the person's own choice put
back afterwards.

## App Intents

Set Focus Priority, Start Focus Session and Finish Focus Session are exposed to Shortcuts.
Each launches the app and uses `FocusIntentRunner` through `FocusCommandCenter`. Session
commands call the same persistent host as the cockpit controls, with the same availability
rules as the File menu. They return success only after the write completes; a closed cockpit
cannot turn a command into a deferred success. Empty priorities and unavailable operations
return localised refusals.

Apple's metadata processor requires literal keys resolved against the main bundle. The
package-bundle approach was tested and rejected by the processor on 8 September 2026.
`App/FocusAppIntents.swift` therefore owns the framework declarations and seven metadata
keys; `FocusUI` owns the runner and refusal copy; `FocusHost` registers the existing writers.
The string lint permits exactly those seven app keys. The packaging gate reads the generated
metadata and compiled main-bundle translations in both Debug and Release, requiring all three
actions, shortcuts and the priority parameter. See `scripts/check-app-intents.py`.

## The list a person could not add to

`SensitivityGate` has a presentation-exclusion list, `SensingHost` consults it on every
judgement, and `SensitiveAppSeed.add` had **no shipping call site at all** (F-121, focus-62o).
The list seeds empty on purpose — seeding it with guesses would be a claim about applications
this programme has not measured — so it was empty for every person for ever, and the Remove
button beside a row was a button no row existed to carry. The section that drew it said *"Add an
app here when Focus mistakes its full-screen window for a presentation"* and offered no way to,
so it was deleted rather than reworded.

It is back with the half that was missing: the list, a Remove on each row, and an add row naming
the applications running right now by the name their own menus use. `NSWorkspace.runningApplications`
needs no grant — it names applications, reads no window and names no document — and the reading is
injected rather than taken in the pane, because a pane that scanned for itself would draw a
different list in every lane that looks at it. Ordinary windowed applications only, this one
excluded, one row per identifier, capped at twelve so a settings pane cannot grow without bound.

A list of buttons rather than a `Menu` or a `Picker`, and the reason is measured: an AppKit-backed
control does not rasterise under `ImageRenderer` — a picker renders as SwiftUI's unrenderable-view
placeholder glyph — so a picker here would make any committed baseline a picture of a broken
render.

The gate presses both verbs. It adds an identifier no application on this Mac carries, reads the
store back, checks the add row stops offering what is already listed, removes it, and asserts the
person's own list is exactly as it was found.

## What it says it does not do

Two sentences in Settings ▸ Privacy, directly under the statement about where the data lives and
with no heading of their own — a section headed *"what we do not do"* invites the list to grow,
and a list of denials reads as defensive rather than plain. *"Focus never connects to the
internet unless you turn on update checks in General settings."* (F-122) and *"Update checks are
off until you turn them on. When Focus checks, it sends its name and version and nothing about
you."* (F-137, focus-h8jf).

Until focus-h8jf the second sentence read *"It never checks for updates."* D-09 parked Sparkle
because this programme had no server, no remote and no deployment lane, so a feed would have
pointed at nothing. The release trains below give it a feed per train, and the sentence changed
with the product rather than ahead of it.

**Neither is a promise.** The first is linted of the shipped product by the gate's `boundaries`
stage — no networking symbol in any package source (Sparkle's own socket is Sparkle's, inside
`Sparkle.framework`, and `FocusUpdates` names no networking API of its own), and
`nm -u FocusClassify.o` naming none, with the object's seven NaturalLanguage symbols as the
control that stops an empty table passing. The second is linted in the same place, in the
opposite direction from before: `nm -u` over the Release app's own binary **names** the Sparkle
updater controller — the control, because "opt-in" is a claim about a framework that is really
there — while the merged `Info.plist` carries `SUEnableAutomaticChecks = false`, so Sparkle
neither prompts nor schedules on its own, carries `SUPublicEDKey`, so nothing unsigned can be
installed, and carries **no** `SUFeedURL`, because the feed is the train's and is answered by the
updater's delegate. The self-check adds the halves a lint cannot see: that the pane declares both
sentences among the strings it draws and both resolve to real text, and — read off the running
process on a default store — that the stored choice is off and the updater was never started
(`softwareUpdateChecksStored`, `softwareUpdaterStarted`).

## Setting and changing a priority

The cockpit shows **What are you working on?** and **Set priority** when no priority is
selected. Selecting a saved priority closes that form, leaving its completion, wording,
clearing and session controls. **Change priority** and **New priority, same context…** open
the form deliberately for the current priority; selecting another priority closes it again.
Edit the priority title directly: changes autosave after a short pause in typing, and pending
edits save when you leave the field or switch priorities. This changes the wording of the same
task, preserving its context, rules and timebox. Empty wording never replaces a saved title;
leaving an empty field restores the last saved wording.

The cockpit has two destinations (focus-g9iw). **Now** is the only place the current priority
and its session live. With no session open it is for planning: the priority, its definition of
done, its timebox and **Your priorities**, the standing shortlist to choose from. While a session
is running or paused it is for working: the same column without the shortlist, so the task, the
timer and every session verb (including Stop) have the eye; **Change priority** brings the list
back on purpose. A session belongs to the priority it started on. If the priority is cleared or
another is chosen mid-session, the session stays on Now with a note saying it began on another
priority (or on none), rather than presenting its timer as the new priority's. **History** holds earlier priorities, each one press from becoming
current again, and **Open History** for the day's full record.

What counts as work on a priority — its context items and its per-priority rules — sits behind
**Configure context…** on Now, beside a one-line count of each. It opens a sheet titled with
the priority that says what those settings are for; edits land as they are made, so the sheet
has one **Done** button and Escape is the same. ⌘O opens the sheet's file picker, and files and
apps are dropped onto the sheet. There is no daily *"What is the one thing today?"* prompt and
no setting for it: the capture field asks that question already. Old stores keep the retired
setting's columns for compatibility with existing data and settings imports; the app no longer
offers the prompt or records a day for it.

## The walkthrough (focus-u6de)

The first-run sheet is page one and says what the app watches; nothing else was ever on it.
Its *Continue* opens a tour of eleven steps on the real cockpit rather than a description of
one: a floating panel (`WalkthroughPanelController`) sits beside the control each step is
about, a borderless window (`WalkthroughHighlightWindow`) outlines the control with a nub
toward the panel, and the instruction asks the person to do the thing there — type the
priority and press Return, choose a timebox, press Start, press Configure context…, click the Focus mark
in the menu bar, press Open Settings. The cockpit's sections report where they were laid out
through `.walkthroughAnchor(_:)`, most specific first, so the priority step points at the
capture field while it is open and at *Change priority* while it is not, and the desk and rule
steps point into the context sheet while it is open and at *Configure context…* while it is not.

A step is done when the app's state says so, not when a button was pressed:
`FocusHost.WalkthroughTour` takes a reading on entering the step and compares it with the
priority host's state, the session host's snapshot, the popover's showing and the Settings
window's drawing on every later change. *Do it for me* performs the same host call the control
would, for somebody who would rather watch; the two nudge steps draw an accusation and a
question on a panel of the tour's own, whose buttons close it and write nothing. The demo
priority is a real task and stays in History; finishing — the last step's button, the panel's
close box or Escape — completes the session the tour started, if it started one, and
re-activates the priority that was active before, or clears.

Replay from Help ▸ Show walkthrough (⇧⌘T) or Settings ▸ General. The snapshot lane
photographs the sheet and every step at both text sizes (`walkthrough*.png`);
`WalkthroughTests` holds the step order, the anchors and the catalog bijection;
`WalkthroughTourTests` drives the tour through the composition root and holds that the
person's own action, not the tour's, is what marks a step done.

## Taking it away

Two documents, and they are deliberately not one scope of the same thing (F-110, F-134).
**Export My Data…** writes one JSON file: the commitments, what was attached to them, the rules,
the sessions, what was observed, what the app said and every question it asked. It is a file you
keep. **Export Settings…** writes a second: preferences and the person's own exclusion rows, with
a version stamp and no history in it at all. It is a file you carry to another Mac, and
**Import Settings…** reads it back. Both are reachable from Settings ▸ Privacy and from the File
menu (⇧⌘X, ⇧⌘B, ⇧⌘I).

**There is no share sheet.** `NSSharingService` routes a private file to a network service in one
click, at the exact surface whose job is to prove there are none. The only destination either
export offers is a folder the person picked in a panel they opened themselves — and because the
app is unsandboxed, that panel is an ordinary window rather than a Powerbox request. The gate
does not take that on trust: it drives the same verbs the panel's OK button reaches and takes the
on-screen authorisation-surface scan on both sides of the write.

**What never leaves is four columns**, and every one of them is a fact about *this Mac* rather
than about the person: the security-scoped bookmark, the boot identity and uptime anchor, and the
display id. The list is short because the store cannot hold the things an export usually has to
strip — a window title, a URL beyond a normalised origin, a document name, an observed file path
have no column to sit in. `Config/export-field-classification.txt` says so column by column and
`scripts/check-export-fields.sh` fails the build on a column nobody has classified; the exporter
reads none of it, so the two can disagree and the disagreement is what fails
(`ExportRegistryTests`). And the absence is **planted rather than assumed**: `StoreExportTests`
writes a title-shaped sentinel into every string column of every entity, through the raw model
classes and past every facade, and requires that no excluded column's poison reaches a byte —
with a control asserting the poison the export *is* allowed to carry is in the file eight times
over, because a test of an input that cannot fail is green for ever.

**An import is untrusted input.** A document whose format is not this one, whose version this
build does not know, whose voice is a deck it cannot read, whose retention window it does not
offer, whose exclusion row is not an application identifier, or whose quick-capture combination
the platform will not register is refused **whole**, with its own sentence, having changed
nothing. There is no partial import: a partly-applied settings file is a configuration nobody has
ever chosen. Every arm is driven in the unit lane, and each one is asserted to leave the store
byte-identical.

## The relevance engine

The app has a judgement, and it is **deterministic**. The heuristic layer is the *whole* engine
in every shipping composition, which is what makes the charter's "fallback always present and
independently tested" clause temporally true rather than a promise about a later release.

**There is an on-device model tier, it is measured, and it is not composed.** e06 built it: a
`FocusModel` package that is the only place in the repository naming `FoundationModels`, a port
declared in `FocusClassify` beside the heuristic seam, a cache the classification path reads
without ever awaiting, and a second evaluation lane that scores it against a 45-cell grid
somebody wrote by hand before the rung existed. On this rig, with Apple Intelligence on and
greedy sampling, the tier went quiet about **fifteen of the thirty cells the grid committed as
holds** — three prompt forms measured, `seduced` 14 / 20 / 15, and zero instability across
three passes of each, so it is a property of the tier rather than noise. A seduction is the app
going *silent* about something the person's own evidence said to hold, and under the default-deny
ruling silence is earned by confident relevance and by nothing else. So
`ModelTierRelease.composesTheRung` is `false`, the ladder is eight rungs, `byStage.onDeviceModel`
is zero, and the judgement a person gets is exactly the one measured over 202 corpus cases. One
green quality half flips the constant, in the same commit as the prompt revision that earns it.

**The mandate this engine emits is what the nudge ladder climbs.** `RelevanceHost` assigns the
eligibility once and hands the same value to two readers: to Settings ▸ Privacy, where the
verdict inspector explains it, and to `NudgeHost`, which folds it into the ladder. So the pane a
person reads and the rung they are shown are two views of one judgement — which is why
`settings.verdict.mandated` reading *"Nothing in this version can, so it does not"* was a
product defect and not a stale sentence (focus-lmy). This paragraph said the same thing for the
whole of e05.

### Three properties worth knowing before reading the code

**An `uncertain` verdict cannot reach an intervention, and that is a type rather than a test.**
`Verdict.permitsIntervention` does not exist. The only route from a judgement to an
authorisation is `InterventionEligibility.decide(…)`, whose `.mandated` case carries an
`InterventionMandate` with no public and no internal initialiser — its memberwise initialiser is
`fileprivate` and the file that declares it contains the sole producer. Every surface that can
interrupt takes one of those, so an unsuppressed `uncertain` is *unrepresentable*. A
4 320-combination cross-product test checks the guarantee; it is not the guarantee.

**Absence of lexical evidence may never, on its own, produce `unrelated`.** This is the most
consequential rule in the engine and it is the one a reader is most likely to mistake for a bug.
Take the priority *"Write the Q3 proposal for Acme"* and `com.microsoft.Excel` in front of it for
two minutes. The identifier tokens are `microsoft` and `excel`; overlap is empty; the similarity
signal may never say `unrelated` and never sees identifier tokens anyway. A naïve engine reaches
absence-plus-dwell and accuses somebody of slacking off *for doing the work*. So the heuristic
may produce `unrelated` only behind a **negative basis**: the priority must carry at least
`minimumPriorityContentTokens` content tokens **and** at least one context item whose kind is an
`app` or a `domain` identity, the observed subject must match none of them, and the dwell must
have passed `sustainedDriftThreshold`. A `keyword`-only or `file`-only context pack is *not* a
negative basis — a keyword can only ever match positively, and at zero grants the engine cannot
see which file is open. Any failure yields `uncertain`, whatever the dwell.

What that costs: the app stays quiet for a person who set a priority and named no context. What
it buys: **every `unrelated` the heuristic ever produces is grounded in something the user
themselves typed.** When Focus says nothing while you are clearly off task, look at the context
pack first — the inspector's explanation says so in as many words, and it is the only place in
the app whose copy carries an ask.

**The similarity signal is asymmetric.** It may corroborate `relevant` below a measured ceiling;
it may **never** produce `unrelated` at any distance. That is a measurement, not caution: over 62
labelled pairs the related and unrelated classes overlap, 28 of 32 unrelated pairs sit inside the
related range, and one pair inverts outright. There is no upper region the unrelated class
occupies alone, so there is nothing to accuse from. `NLEmbedding.wordEmbedding` is banned from
the shipping graph outright — its cross-domain separation measured **0.017** and it ranked a
distraction closer than a colleague — and bundle-identifier tokens never reach any similarity
function, enforced by a type split rather than a convention.

### How it decides

One ordered ladder, `CascadePrecedence.rungs`, and there is no second one anywhere in the
repository. Nine stages at integer ranks 0…8, of which **eight are executable in this build**:

| rank | rung | decisive? | in this build? |
|---|---|---|---|
| 0 | rule for this session | yes | yes |
| 1 | rule for this priority | yes | yes |
| 2 | rule for everything | yes | yes |
| 3 | context you attached | yes | yes |
| 4 | built-in default | yes | yes |
| 5 | what the words have in common | yes | yes |
| 6 | on-device model | `relevant` only, never `unrelated` | **built, measured, not composed** |
| 7 | built-in "ask each time" | `uncertain` only | yes |
| 8 | nothing matched | `uncertain` only | yes |

**Rank 6 is reachable only from two answers, and that distinction had to exist before a model
could.** The comment on the ladder used to say e06 would "flip one flag and supply an
implementation". It cannot: the heuristic at rank 5 *answers* `uncertain`, and an `uncertain`
answer terminates the walk, so a model rung inserted that way would have been consulted on
mixed-use applications — the one subject class it must never judge — and on nothing else. So a
rung answer now carries a `RungFinality`. Most answers are `decided`. Two are
`reviewable(by: .onDeviceModel)`: `noNegativeBasis` and `languageNotSupported`, which are not
decisions but the engine saying *"I lack the instrument"*. A reviewable answer consults **one**
named rung and only that one — never a general fall-through, which would let a rung *below* the
model overturn a provisional answer — and only if the composed ladder can execute it. A rung
marked reviewable about a browser, a chat client or a media player is narrowed back to `decided`,
because absence of information is not information about those. `RungFinalityTests` enumerates the
reviewable set by running six priorities against eight subjects against four context packs
against eight dwells and collecting finalities, so a third reviewable answer added without a
ruling fails the suite — and it is what found that the language gate, which fires above the
subject checks, was still handing browsers to the model.

Four readers, three of them mechanically checked: the runtime iterates `executableRungs` (the
unavailable rung is *not in the sequence*, rather than skipped by a special case); the
explanation builder switches exhaustively over the stages; the Settings precedence pane renders
the list in rank order against a committed snapshot baseline; and `check-strings.sh` asserts a
bijection between the stages and the `cascade.rung.*` catalog keys. Two rules that match at the
same authority **and** the same subject kind and disagree resolve to `uncertain` — never by
recency, and never to `unrelated`.

### The evaluation lane

**Two lanes.** Lane 1 is the deterministic composition and it is the shipping gate. Lane 2 is
the model composition and it is evidence — it can never redden a build for a fact about a
language model, and it can never be skipped without saying so. They share a process and share
nothing else; lane 2 has its own report type rather than a `status` field on lane 1's, because
adding a field to `EvaluationReport` would change the JSON the gate binds to.

`FocusEvaluate` is a **product**, not a test side effect, and stage 7d runs it. A report emitted
as a side effect of a test run is a report whose existence depends on a test having been
scheduled — and whose destination depends on an environment value `xcodebuild` does not carry
into a SwiftPM test target's process, which is the same constraint the snapshot lane documents.
A plain process does carry its environment, which is the whole reason the target exists. It is a
test-lane product: no application target links it, and `check-boundaries.sh` asserts that rather
than assuming it.

It writes `evaluation.json` — every rate, every latency percentile, the cascade depth
distribution, the per-rung and per-uncertainty-reason counts, the cache profile, the run token
and the corpus digest — and the gate archives it, so a closed epic is audited from an artefact
rather than from an assertion about one.

**The report is bound to the run that produced it.** The staging path is shared between runs, so
without this a report left behind by an earlier green tree would be parsed as today's evidence,
and a gate whose central number can be satisfied by a file nobody wrote today is not a gate.
Five binding checks run **before** any metric — a stale or foreign report is not a failing
number, it is no evidence at all:

| # | check | what it catches |
|---|---|---|
| B1 | `runID` equals this run's token | a report from any other run, even if the deletion silently no-ops |
| B2 | the report is newer than the `eval-clean` marker | a report that predates this run's `unit` stage |
| B3 | `stamp` and `policyDigest` equal the committed literals | a report produced by a different engine or a different policy version |
| B4 | `corpusDigest` equals one recomputed from the working tree | a report describing a corpus other than the one on disk |
| B5 | the parsed bytes are the per-run copy | asserting on the shared staging file instead of the archived one |

Then the committed metric thresholds. They live in exactly one place —
`FocusEvaluateCore.EvaluationGate` — which the product decides its exit status from and which
`EvaluationGateTests` asserts in the unit lane, so `swift test` alone still catches a metric
regression and the gate script does not restate a single number:

| metric | requirement | why this number |
|---|---|---|
| `overall.falseNudgeRate` | **`== 0.0`** | not "small". Every corpus case is one somebody wrote deliberately with an expectation; a single false nudge on a case somebody thought about is a product defect, and a non-zero budget is how a defect becomes a habit |
| `overall.missRate` | `≤ 0.25` | misses are cheap: a miss falls to `uncertain`, which suppresses |
| `overall.uncertaintyRate` | `≤ 0.45` | an engine that says "I don't know" to everything is safe and useless |
| `adversarial.uncertaintyRate` | **`≥ 0.90`** | the adversarial suite exists to be declined, computed over `caseCount − negativeControlCount` so a declared control cannot dilute it |
| `adversarial.familyCount` | `== 11` | with every per-family floor met |
| `latencyMs.p95` / `.max` | `≤ 25 ms` / `≤ 60 ms` | the worst realistic warm path is about 10 ms; the 60 ms ceiling is what proves `warmUp()` moved the 59 ms cold embedding load off the classification path |
| `cascade.maxDepth` | `≤ 8` | the executable ladder length |
| `cascade.declaredRungs` / `executableRungs` | `== 9` / `== 8` | with `byStage.onDeviceModel == 0`, so the three lengths stay distinguishable in the evidence and not only in the code |
| `caseCount` | `≥ 132` | **and every per-file floor separately.** The easiest way to make a false-nudge rate go to zero is to delete the case that produced one; the second easiest is to replace thirty adversarial cases with thirty baseline ones |
| `byUncertaintyReason.noNegativeBasis` | `> 0` | the rule above must be *exercised*, not merely present, or the family guarding it has stopped testing anything |
| `cache.hitRate` | `≥` its committed floor | so a workload regression is visible rather than inferred |
| `cache.capacity` | `== cache.recommendedCapacity` | `similarityCacheCapacity` is class **C** and its derivation rule was committed before the sweep was run — the smallest capacity whose p95 is within ten per cent of the best measured. A hit rate alone does not enforce that: a capacity nobody derived would pass it every time |
| `failures` | empty | a metric that fails without naming the case that failed it is a metric that costs an hour |

#### Lane 2 — `evaluation-model.json`, and the number the epic exists to fail on

`FocusEvaluate --model`, stage 7e. It loads `GoldenCorpus/Model/` — a **complete 6×6 grid** of
six priorities against six subjects, plus a 3×3 multilingual grid, 45 hand-written cells, every
one identity-free so it reaches `uncertain(.noNegativeBasis)` or `uncertain(.languageNotSupported)`
in lane 1 and nowhere else — runs each cell through **both** compositions three times, and folds
every case into exactly one bucket:

| bucket | definition | gate |
|---|---|---|
| `rescued` | deterministic `uncertain` → model `relevant`, and the cell said `rescue` | recall floor |
| `missedRescue` | the cell said `rescue`, the model declined | reported. Cheap: the app asks the question it would have asked anyway |
| `seduced` | the cell said `hold`, the model rescued it anyway | **zero.** The app going *quiet* about something the person's own evidence said to hold |
| `declined` | the cell said `hold`, the model declined | reported — the tier working |
| `impossible` | a mandate moved, or a model answer reached `unrelated` | **zero**, and unrepresentable: `ModelAnswer` has no `unrelated` case |

The buckets are asserted to sum to the cell count, so a case that fell out of the fold is not a
case that passed. **Both axes of the grid move**: every row carries a rescue and a hold, so a
model answering from the priority alone gets the whole row wrong, and every column does too, so
a model answering from the subject alone gets the whole column wrong. **The hold cells are the
mutation witness** — a yes-to-everything model scores 100 % recall and fails all thirty of them,
which `ModelLaneTests` demonstrates with a stub judge and no Apple Intelligence at all.

`corpus_entries` in `build-gate.sh` is an **explicit allow-list**, and that is load-bearing:
adding `GoldenCorpus/Model/` moves nothing in lane 1's `corpusDigest`. The model corpus carries
its own digest and a test asserts the two differ — if they ever agreed, somebody had generalised
the allow-list to a tree walk and broken every committed baseline at once.

**What it measured, and what that decided.** Three prompt forms on this rig, `.greedy`, three
passes each: `seduced` 14, 20 and 15 against a budget of zero, with `unstable` empty every time.
Narrowing the prompt raised recall and made the seductions worse. So the tier is not composed —
see "The relevance engine" — and the lane exists to re-measure that decision rather than to
argue it.

---

## The nudge loop

The app speaks under exactly three postures, and the third one is a user ruling that inverts the
obvious default:

| verdict | what the app does |
|---|---|
| `relevant`, confidently derived | **silence** — and it is the *only* thing that buys silence |
| `uncertain` | **a question**: "Is *{subject}* part of *{task}*?", asked once and never again |
| `unrelated` | **the ladder**: silent glyph → non-activating panel → recommitment |

### An accusation drawn beside a question is not chargeable (focus-6pr.4)

The menu-bar popover can carry both at once, and when it does the **question** is the decision:
U-1 licenses the interruption because the question is cheaply answerable, U-2 makes an accusation
wait behind an open question rather than displace it, and pinning both shelves together needed over
815 points against a 911-point ceiling at the largest text size. So the accusation scrolls with the
context, and `MenuBarPresentation.pins(_:)` is the one place that rule is written down — read by
the layout, by the controller's `offeredIdentifiers(of:)` and by the test lane alike.

The ledger follows the layout. A nudge that offers nothing is `DecisionSurfaceStanding.notOffered`,
never *"every one of no actions is reachable"*, so `PerceptibleChange.proven(…)` cannot produce a
receipt for it; and because that rung really is on screen in front of somebody,
`NudgeHost.proveOpenRung(at:)` writes it down as `deferred` with the fifth deferral reason,
`questionPinned` — once per rung, not once per redraw. It spends neither cap and does not advance
the ladder, and the moment the question is answered the accusation is unpinned and chargeable
again. The self-check's sixth launch drives the state and publishes the count, so the cell is
seeded rather than hoped for.

### The two authorisations, and why a question can never become an accusation

`InterventionMandate` and `QueryWarrant` are two types that share no protocol, no supertype and no
field the other needs. Each has a `fileprivate` initialiser and exactly one producer, and each
producer returns before reading anything else on the wrong verdict. Four independent facts stop a
question widening into an accusation, and each is sufficient on its own:

1. no shared protocol or supertype (lint-banned, `check-forbidden.sh` R-96d);
2. no source file names both producers (R-96b);
3. `QueryWarrant` carries no band and no stage, and the ladder needs both;
4. `LadderRung` has exactly one initialiser and it takes an `InterventionMandate` (R-96c).

`nudge.accusationsFromQuery == 0` asserts the same thing as a number, over the whole corpus, every
sequence fixture and every realistic day.

### The break ending is a state, not an event

`SessionEvent.breakEnded` and the break's own suppression have shipped since e03: the machine
knew a break began, knew it ended, and did nothing at all with the ending (F-67). A person who
takes fifteen minutes and comes back is who this app is for; a person who takes fifteen minutes
and then reads the news for twenty more had only the ordinary drift ladder waiting for them,
starting from scratch as though the break had never happened.

What ships is **one sentence on the ambient rung** — the menu-bar item's tooltip and the line
VoiceOver reads off it, which is also the first tooltip that item has ever had. Not a panel: U-2
left the app one, for an unrelated verdict, and a break ending must not spend the interruption
slot. Not a notification: PD-1 leaves none to post. Not praise and not a count (D-01). And not a
nag — it is a *state*, so it stops being true the moment the person is back on task, and there is
nothing to dismiss.

`RestartCue.state(phase:sinceBreakEnded:isBackOnTask:)` is the whole rule, and it is a fold over
`SessionPhase` rather than an `if`: a break ends into `focus`, but `focus` is also where a session
starts, and every other phase reaches the function too. Each has its own **named** silence, so a
test can require every phase to produce a reason rather than a `false` that covers six
situations, and the self-check publishes which one the running app is in. The grace is two
minutes — chosen rather than measured, and said so.

`.relevant` and nothing else counts as being back. Under U-1 an `uncertain` verdict is the app not
knowing, and treating not-knowing as *"they are back"* would silence the cue exactly where it is
most likely to be right.

### Two memories, two jobs

Answering a question performs **one atomic transaction that writes two records**:

* the **rule** — a task-authority `ScopedRuleValue`, visible in the Rules pane, deletable, undoable,
  and authoritative for future classification. Once it exists the subject answers at the `taskRule`
  rung and no `uncertain` verdict is produced, so no warrant can even be constructed;
* the **receipt** — an immutable `AskedQuestion` row, authoritative for never-ask-twice.

The rule is deletable *by design*, so the invariant cannot rest on it. Deleting a learned chip means
"that is not a fact about my work", never "ask me again": the subject returns to being
uncertain-and-already-asked, and gate 11 of the suppression stack reads the receipt. `seq-0027`
replays exactly that sequence, and live-lane frame 14b photographs it.

### The panel takes nothing

The nudge panel is a `.nonactivatingPanel` shown with `orderFrontRegardless()` and **never** made
key programmatically — `makeKeyAndOrderFront(` is lint-banned in the nudge module, because the safe
call and the unsafe call are one word apart in a diff. Probe P-139 measured why that matters:
`makeKeyAndOrderFront(nil)` on this style mask flips `NSApp.isActive` from `false` to `true` and
installs a key window **while `NSWorkspace.frontmostApplication` never moves**. A gate reading only
the frontmost application would have gone green over it. So "did not steal focus" is four readings,
not one:

| reading | required | what it catches |
|---|---|---|
| `NSWorkspace.frontmostApplication` | unchanged | the coarse theft a person would see |
| `NSApp.isActive` | `false` | the activation the frontmost reading is blind to |
| `panel.isKeyWindow` | `false` | the key window that would take the keyboard |
| `NSApp.keyWindow` | `nil` | the same fact from the application's side |

Stage 9a asserts all four, and takes reading 1 from an **independent observer process**
(`lsappinfo`) rather than from the app under test. The one thing it cannot prove — that a person
*typing* while the panel is up keeps their keystrokes — needs a synthetic key event and therefore an
Accessibility grant, so it is live-lane frame 17: read evidence, never a close condition.

### The split metric

`evaluation.json` gains a `nudge` object beside e04's `falseNudgeRate`. Read the names carefully,
because the naming is the point:

| metric | bound | kind |
|---|---|---|
| `accusationFalsePositiveRate` | `== 0.0`, **and** `== falseNudgeRate` | exact |
| `repeatQueryCount` | `== 0` | exact |
| `queryOnDecidableCount` | `== 0` | exact — asking about something the app had already been told |
| `queryOnUnaskableCount` | `== 0` | exact — the guard on `noEvidence` above all |
| `accusationsFromQuery` · `escalationsFromDeferred` | `== 0` | exact |
| `queryVolumeRate` | `≤ 0.17` | **volume**, derived from P-138's 28/165 — *not* a false-positive rate |
| `queriesPerFocusDay` | `≤ 5` | volume, day-level, max across three realistic-day fixtures |
| `interruptionsPerFocusDayMax` | `≤ 8` | volume, day-level |
| `queriesPerPriorityMax` | `≤ 4` | exact |
| `queryAnsweredRelevantShare` | **band `[0.25, 0.75]`, both ends fail** | honesty |
| `queryGroundTruthCoverage` | `≥ 1.0` | **fails closed** |
| `unaskableUncertaintyShare` | `≥ 0.34` | **floor** |

The band is two-sided on purpose. Gating *relevant answers ÷ delivered queries* with a ceiling alone
would invert the ruling the affordance exists to serve: a "yes" is the affordance **working** — one
click, a durable rule, a subject never asked about again — and a one-sided ceiling creates a direct
incentive to ask fewer of the questions the app is supposed to ask. Above 0.75 the recogniser is
under-performing; below 0.25 the app is using a polite question as a euphemism for an accusation it
had the evidence to make. Both are failures, and they are different failures.

The day-level numbers are measured by replaying three committed realistic days — priority changes,
breaks, a pause, a presentation, an idle span, a relaunch — and reported as the **maximum** across
days, never the mean: a metric that averages a bad day away is a metric that ships a bad day.

### The live lane

```
scripts/live-nudge-drive.sh          # TCC-gated evidence, never a gate; exits 0 when a grant is missing
```

Eighteen frames in **seven independently reset scenarios**, driving two committed decoy
applications (`Tools/FocusDecoy`, seeded unrelated for the ladder; `Tools/FocusDecoy2`, a neutral
identity that is the only way an `uncertain` verdict is reachable on demand, with a focusable text
field for frame 17). Frame numbers are stable identifiers rather than an execution order, and a
precondition that cannot be reached **aborts the scenario** with the observed state dumped — a live
lane that photographs whatever it happens to find is a live lane that proves nothing.

## The notch companion (e08a)

The notch companion is a **second renderer of the ambient rung**, not a fifth surface. It draws a
two-point line, the width of the housing, flush under the notch of the **built-in** display — no
glyph, no capsule, no text, no timer, no mark of any kind. It adds no `NudgeSurface` case, no
`PerceptionChannel` case, no `SurfaceObservation` field and no charge site, and the self-check
publishes `sensing.notch.chargeSites` as a fold over both closed vocabularies so that the day one
appears the gate fails on a number.

Two conjuncts hold it there, and `NotchCompanionPresentation.derive(…)` is the only place either
can be broken:

1. **marks** — the companion's mark is in `{.unmarked, presentation.attention}`, and in e08a it is
   `.unmarked` in every state;
2. **visibility** — a companion exists only where `menuBarVisible && itemVisible`.

The second is new law. `SurfaceRouter` defers the ambient rung on `menuBarVisible == false` alone,
and `MenuBarController.redraw(force:)` early-returns on `guard isItemVisible || force`, so
`glyphWriteCount` and `markOnTheItem` never move when the item is off screen — and
`PerceptibleChange.proven` needs exactly that increment plus that transition. **Status-item
overflow is not a suppression**, is invisible to `suppressesOverlays`, and is *more likely* on a
notched Mac because the housing eats the centre of the bar. Without conjunct 2 the companion would
be the only surface a rung reaches: a `noticing` line in plain view beside a ledger row reading
*"deferred, menuBarHidden"*. `NudgeUnseenAttemptTests` is where that tripwire is pulled, with the
companion pointed at a **synthetic** notched display so its silence is a measurement.

The window is `.floating`, never `.statusBar` — nothing in `Packages/*/Sources` uses `.statusBar`,
so the plan's "verified in this repo already" was false — and its collection behaviour never
carries `.fullScreenAuxiliary` (P-130, R-96n). On a full-screen space the companion is simply
absent, which conjunct 2 requires anyway.

### On the machine this was built on, nothing is ever drawn

This is a Mac mini (Mac16,10) with no built-in display. `NSScreen.safeAreaInsets` is zero,
`auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are **`nil` rather than degenerate rectangles**,
and `CGDisplayIsBuiltin` is false — so `NotchLanding.of(_:)` answers
`.refused(.noBuiltInDisplay)` and the strip is never placed. That is proven by numbers rather than
by inspection: `sensing.notch.companionWrites` is `0`, `companionVisible` is `false`, `inkFrame` is
`null`, `builtInDisplayCount` is `0`, and `landingRefusedBecause` is `"noBuiltInDisplay"` — the
first thing wrong with the display rather than the only word the app knows. There is **no
`hasNotch` boolean** anywhere (F-74): `NotchLanding.Refusal` is a closed `CaseIterable` of six
named reasons, published beside the answer so the gate's membership test cannot be satisfied by an
invented word.

Every fixture in the programme with an interesting housing is therefore labelled **`synthetic`**,
and stays so until P-e08-B.

### The Settings row is a reading, and there is no toggle

*Notch companion* in the Intervention pane renders from `NotchLanding` and from nothing else, so
what a person is told is what the display said. `.noBuiltInDisplay` gets its own sentence, because
*"this Mac has no notch"* is false for a Mac with no built-in panel at all.

There is deliberately **no switch**. A preference is only worth anything if it survives a relaunch,
and there is no column for this one — that is a schema stage. focus-40i is the round where a
setting held only in memory silently restored the panel for somebody who had asked for quiet, and
focus-wy0 and focus-1qm are the two rounds that deleted controls buying nothing. The row says what
is true and offers nothing until the receipt below arrives.

### What e08b is, and the exact receipt each part needs

e08a is the honest floor: the geometry spine, the collapsed hairline and the truthful row. Marks,
pulse and expansion are **e08b**, and none of them may be built before its receipt exists. The
receipts are hardware measurements the driver must produce on another machine — this rig cannot
take any of them.

| e08b item | the receipt that unblocks it |
|---|---|
| **Marks** — capsule, `StatusBadge` shapes, the timer under the housing | **P-e08-B**: measured `NSScreen.safeAreaInsets.top` and both `auxiliaryTop*Area` rectangles on a 14″ and a 16″ MacBook, at each backing scale, pasted into `focus-26b`. It replaces the `synthetic` labels on `NotchLandingTests.shapes`, `NotchCompanionPanelTests.notched` and `NudgeHostFixture.notchedDisplay`. |
| **Pulse** (F-78) | **P-e08-A**, level half: `screencapture -l` of the strip at each candidate window level on notch hardware, showing the companion *under* the housing and never over a menu-bar item — `.statusBar` is unmeasured here and the plan's claim that it was verified is false. **Plus** an extension to `scripts/frame-ink.py`: it computes luminance between *horizontally adjacent pixels within one frame* (`:86-87`) and prints one `ink=/verdict=` line per file (`:119-125`). There is no before/after diff, and a 2 pt hairline on a uniform strip is the low-`ink` case the tool calls `blank`, so the plan's S2 criterion is unimplementable as written. |
| **Expansion** (F-76) | **P-e08-A**, hover half: a real `NSTrackingArea` event count over the housing. **Plus** the ceiling fix — `SurfaceSizeCommitment.ceiling` reads `DisplayMapper.primaryScreen(in: screens)`, the *primary* display and not the surface's, and a docked MacBook's notched built-in is routinely not primary. It must be passed a one-element list holding the notched display through call-site arguments (the `MenuBarController.popoverContainers` pattern), so that the core diff stays zero and R-96w stays green. |
| **A stored "show the companion" preference, and the toggle that sets it** | A schema stage: `NudgePreferencesRecord` is declared by `FocusSchemaV5`, so a fourth column means the next version re-declaring that one class, its own stage, and that version's suite asserting the delta is exactly one class and one property (v8 is taken — it added the retention window's row and re-declared nothing). Worth doing **with** the marks, when there is something to turn off that a person can see. |
| **Any capture or sharing copy** | **P-e08-D**: `sharingType = .none` measured against ScreenCaptureKit. Runnable here now — nothing sets `sharingType` in `Packages/*/Sources`. Until it exists: no code and no copy. |
| **Both display projections agreeing about a notched Mac** | **P-e08-B** again. `DisplayGeometry.NotchReadings` makes an *omitted* reading a compile error and `NotchGeometrySeamTests` fails on any *divergence* between `SystemScreenList.geometry(of:)` and `NudgePanelController.currentScreens()`, but on a Mac with no built-in display "both readers wrong in the same way" publishes the same four values as "both readers right". That residual is stated in the test's own doc and in `Config/mutation-witnesses.md`. |

**The notch wording was approved by the user on 8 September 2026 (D-11).** The six catalogue
entries record that approval; the thirteen pending nudge entries were approved in the same review.

## History

History is a **fact ledger**, not a timeline. It lists what the app did today and why it said so,
row by row, with the person's own answers beside it — and it is reached from the **View menu**
(⌃⌘D, listed in the Keyboard Shortcuts window like every other bound verb), not from a sidebar.

A cockpit entry point is deliberately *not* in this epic. `FocusTraversal` commits the cockpit's
keyboard order as a pinned list, and adding a focusable control to it is a change to that order
and to the assertions over it — real work, and not the same work as building the surface.

### Why it is a ledger and not a replay

The epic plan asked for a day drawn by **replaying** the stored activity stream through the
relevance engine and colouring each interval `focused` / `unsure` / `off`. A verdict is a function
of `ClassificationInput`'s five fields, and three of them are not in the store:

| field | why replay cannot have it |
|---|---|
| `origin` | `ActivityEvent` has no origin column, and `NormalisedDetail`'s closed vocabulary has no origin token. Storing one would make "this epic records no new observation about a person" false, so it is **not stored**: browser intervals draw as *unattributed*. |
| `titleTokens` | not stored. Since issue #24 a window title may be *read* (opt-in, on device), but only its normalised label is kept, and only as a rule's subject — no activity row records which item was in front. |
| `priorityIntent` / `priorityDoneWhen` | reachable through `priorityID`, but `intent` is mutable and `revision` counts edits without keeping prior text. Replaying Tuesday would silently use **today's** wording. |

So a coloured timeline would be an assertion about the past that the data cannot support. What the
store *does* hold is the app's own conduct, and that is what History draws:

| row | what it says |
|---|---|
| `InterventionRecord` | every interruption — the rung and the surface that carried it, whether it was delivered, deferred, unopened or suppressed, what the person did about it, and which click wrote the rule the verdict rested on |
| `AskedQuestion` | every question, the person's own answer, and **the app's reason for asking** |
| `FocusSessionRecord` | the day's sessions and their phase changes |
| `ActivityEvent` | app identity and dwell for the intervals where the app said nothing |

Priority wording is labelled as **today's wording** on the surface, because that is the only wording
the store has. The replay-fidelity measurement that decides whether a future epic may draw a
timeline at all is published in the self-check as `historyReplay` and is deliberately **not**
gated: it is evidence about the plan, not a close condition. What it measured on the gate run that
shipped this section, over a seeded day of 28 judged moments:

| | |
|---|---|
| replay reached the verdict the app acted on | **8** |
| diverged, no origin column | 4 |
| diverged, the priority's wording has since been edited | 4 |
| diverged, no history of when the commitment changed | 6 |
| diverged, a correction written afterwards — *the legitimate case* | 6 |
| diverged with no known cause | **0** |

Read that as: **under a third of a modest day replays**, and only six of the twenty divergences are
the case a timeline is *supposed* to render. That is why History is a ledger.

### Why it is not a scoreboard

Ruling D-01 is binding here and is the reason there is no arithmetic on this surface. History shows
**no score, no streak, no total distracted time and no per-day tally** that could be read as a
grade. A count of rows by kind is published in the self-check for non-vacuity; nothing on the
surface aggregates a person's day into a number they could feel judged by.

### Correcting a silence

The one thing nothing else in the app can do: say *you were wrong to stay quiet*. An app interval
History drew without an interruption carries a "this was a distraction" action, and taking it writes
a **rule** — a task-authority `ScopedRuleValue` through `CorrectionAction`, scoped to the priority
that judgement ran under, never the current one, and byte-identical to an in-the-moment correction
but for its id and timestamp.

Three things it deliberately is not:

* **never a re-ask.** `CorrectionAction.outcome(…)` returns a rule *and* a receipt; History takes
  the rule half only, and is constructed with no `QueryLedger` reference at all — so a correction
  cannot settle or reopen a question retroactively. The ledger's row count is byte-identical before
  and after.
* **never an edit.** The log is append-only; `InterventionLog.complete(…)` fills an outcome once and
  refuses a second call. Disagreeing with a silence appends a rule, it does not rewrite the day.
* **never a widening.** A judgement whose priority has since been deleted has the affordance
  **withdrawn with a stated reason** rather than promoted to a global rule. The same withdrawal
  covers origin subjects, whose judgements are unreplayable and, before e09a, were mis-stored as
  application judgements.

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
| `scripts/live-verdict-drive.sh` | a real decoy application opened with `open -a` in front of a real priority, captured at three settle points across the grace period, once past `sustainedDriftThreshold`, and once after returning to the anchor | `verdict-timeline.txt`, `verdict-report.json`, `01-priority-set.png` … `06-returned-to-anchor.png`, plus a receipt for `07-context-removed.png` when nobody was at the keyboard |

**What is being read in the verdict frames is not "did it draw".** It is *is the explanation
restrained*: no window title, no URL, no file path, no similarity number, no accusation — the
clause list and nothing else. Frame 05 is the one to look at hardest, because it is the frame in
which the engine has authorised an interruption and **nothing appears on screen**; and the frame
after the context chip is removed is the one that shows the app falling silent when it has
nothing to judge against, which is the behaviour a reader will otherwise mistake for a bug.

This lane opens and closes applications with `open -a` and `pkill` rather than with `osascript`,
for the reason the e03 lanes do: `osascript -e 'quit app …'` blocks on Automation consent and
has to be killed, so following the plan's letter would make the lane hang on a Mac that has not
granted Automation — precisely the dependency that must never reach a criterion.

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
scripts/live-nudge-drive.sh
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
| `FOCUS_EVAL_OUT` | `FocusEvaluate`, the gate | where `evaluation.json` is written. Default `$TMPDIR/focus-eval`. Shared between runs, which is exactly why stage 6b deletes it and stage 7d refuses a report that is not this run's — see "The evaluation lane" |
| `FOCUS_GATE_RUN_ID` | the gate → `FocusEvaluate` | the run token stamped into the report. Minted from the per-run log directory's basename, so there is nothing new to collide. A run without one says `local-<pid>`, which can never be mistaken for gate evidence |
| `FOCUS_CORPUS_DIR` | `FocusEvaluate` | the golden corpus to evaluate. Defaults to the working tree's own copy, because the gate recomputes the digest from that tree and a bundled copy could diverge from it |
| `FOCUS_SNAPSHOT_RECORD=1` | the snapshot lane | re-record the committed baselines instead of comparing. `swift test` only, for the same reason. Recorded PNGs are read by eye before being committed |
| `FOCUS_SNAPSHOT_METRICS=0` | the snapshot lane | silence the phase table the lane prints to stderr at process exit — render, PNG encode, pixel decode, baseline read, baseline decode, ink, comparison, with counts and a per-call mean, plus the memo and fast-path hit rates. On by default: it is the measured witness `focus-tzj.5` is held to, and it is in the unit lane's own log |
| `SWT_SWIFT_ERROR_BACKTRACING_ENABLED=0`, `SWT_FOUNDATION_ERROR_BACKTRACING_ENABLED=0` | the gate, set by the `FocusUnitTests` scheme | **swift-testing's error-mapping cache, off.** Measured with `sample(1)` on a live `FocusUITests` run: two thirds of every parallel test task's time was blocked on one `os_unfair_lock`, and the rest inside the `Dictionary.filter` swift-testing runs over that cache *after every test case* — copying a weak reference per surviving entry. The work is quadratic in (test cases × live thrown errors) and had nothing to do with this app. Off, `FocusUITests` runs in minutes instead of the better part of an hour. The cost is that a test which fails by *throwing* no longer carries the backtrace of the throw site; the thrown error's own description, which is where this repository puts its failure sentences, is unaffected |
| `FOCUS_FIXTURE_RECORD=1` | `MigrationFixtureTests` | rewrite the committed v1 store fixture instead of asserting against it |
| `FOCUS_SELFCHECK_JSON` | `self-check.sh` | where the app's self-check report is written |
| `FOCUS_OPERATOR_TIMEOUT` | `live-sensing-drive.sh`, `live-session-drive.sh`, `live-verdict-drive.sh` | seconds to wait at each operator prompt before writing a `MANUAL_REQUIRED` receipt and continuing. Default 45. An unattended run has no terminal to read from and reaches the timeout at once, which is what should happen — the alternative is a lane that hangs a nightly run for ever |
| `FOCUS_LIVE_TEXT_SIZE=raised` | the live lanes | capture `main-accessibility.png` (shell lane) and `cockpit-accessibility.png` (capture lane) — only meaningful once the system-wide Text Size has been raised by hand, because macOS has no injectable Dynamic Type. The zero-grant equivalent is the snapshot lane's `ShellTextScale` matrix plus `DynamicTextResilienceTests` |

### Evidence

With `FOCUS_EVIDENCE_DIR` set, the gate assembles `gate.log`, `build-debug.log`,
`build-release.log`, `test.log`, `project.log`, `boundaries.log`, `forbidden.log`,
`strings.log`, `packaging.log`, `entitlements.txt`, `selfcheck.json`, `selfcheck.log`, their
Release counterparts, `eval-clean.log`, `evaluation.log`, `focus-evaluate.log`,
**`evaluation.json`**, and a `snapshots/` copy of every render. The live lanes add `menus.txt`,
the shell frames, the capture and handoff frames and their two transcripts to the same
directory when the grants exist. That directory is evidence, not source: it is never
committed.

---

## Strings

Every string a person can read comes from a String Catalog and is reached through a generated
typed symbol, except for the literal catalogue keys required by App Intents metadata. `scripts/check-strings.sh` is a
gate stage and checks both directions: no hardcoded user-visible literal, and no key that is
in a catalog but unused or used but missing.

There are four catalogs and each module resolves its own against its own bundle, so they are
checked separately:

| catalog | keys | who reads it |
|---|---|---|
| `Packages/FocusUI/Sources/FocusUI/Resources/Localizable.xcstrings` | `shell.`, `settings.`, `priority.`, `capture.`, `context.`, `handoff.`, `session.`, `sensing.`, `capability.` | `FocusUI`, and the app target through `ShellStrings` |
| `Packages/FocusCore/Sources/FocusCore/Resources/Localizable.xcstrings` | `status.` (the `FocusStatus` short labels), `undo.` (the action names the system Edit menu draws after "Undo"), and the relevance vocabulary — `cascade.`, `explanation.`, `suppression.`, `evidence.`, `rule.` | `FocusCore`, and `FocusUI` through the `…Resource` accessors each vocabulary exposes |
| `App/Localizable.xcstrings` | seven `shell.intent.*` metadata keys | App Intents and Shortcuts, which require the main bundle |
| `Packages/FocusHost/Sources/FocusHost/Resources/Localizable.xcstrings` | **none, by design** | nothing yet |

The app target's catalogue contains only the seven keys Apple's App Intents metadata processor
requires in the main bundle. `check-strings.sh` pins that exact set and checks every value and
reference; the packaging stage verifies the compiled resources against the actual exported
metadata. Scene and view strings remain in `FocusUI`.

`FocusHost` keeps an empty catalogue and remains in `EXPECTS_NO_STRINGS`: the hosts
moved out of the app target, and an assertion that quietly stopped applying because the code
it was about changed address is not an assertion.

## Why the composition layer is a package

`xcodebuild test` runs test bundles. The `FocusUnitTests` scheme lists package test targets and
nothing else, because Xcode's implicit package schemes cannot run package tests and an app
target's module cannot be imported by a bundle that is not hosted by it. `App/` was therefore
unreachable to every test in the programme, and the claims about the code in it were made by a
test that read the *source text* of `App/*.swift` and looked for the substrings the wiring
happened to be spelled with.

Three mutations to `NudgeHost` measured what that was worth. Replacing the readability reading
taken when a question goes up with a constant `.readable`, replacing the popover's readability
with a constant, and inverting the `panel.isVisible` fallback each left the entire lane
identical: build `EXIT=0`, 1 115 tests green, `check-focus-steal.sh` `EXIT=0`, an identical
self-check report. Each of the three reinstates a path by which the app writes an immutable
receipt about a question nobody was shown — and because `hasAsked(…)` is gate 11 of the
suppression stack, that silences the question for the life of the priority.

So the layer is `Packages/FocusHost`, and `FocusHostTests` is in the scheme. Its tests
instantiate `NudgeHost` against the real `NudgePanelController` and the real
`MenuBarController`, over an in-memory store, and drive it. The app target keeps only what an
app can own and reaches the package through a narrow surface on `AppComposition`, so the hosts
stay `internal`.

The alternative — an app-hosted unit-test bundle in `FocusSentinel.xcodeproj` — was rejected on
two counts. A hosted bundle runs *inside* the launched application, which here means a live
store in Application Support, a registered global hot key and an attached observer graph in
every test process. And the package route puts the layer's dependencies under
`check-boundaries.sh`'s import matrix, which the app target's imports were never subject to:
`FocusHost` is now the sixth row, the one row permitted every sibling, and forbidden `SwiftUI`
because a view here would be a view outside `FocusUI`.

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

The automated gate packages an **ad-hoc-signed local app**, without credentials. Shortcuts
can discover its actions but macOS refuses execution because it has no validated Apple team
identity. On 8 September 2026, signing the same Release code with this Mac's existing Apple
Development identity allowed all three actions to execute in Shortcuts; both invalid session
operations returned their intended refusals. The default local Run action also builds ad hoc.

For local Shortcuts use, sign a separate copy of the verified Release app with an existing
Apple Development identity, then explicitly select development packaging. Substitute the
identity SHA from `security find-identity -v -p codesigning`; the packager never signs or
selects credentials itself:

```sh
ditto "$RELEASE_APP" "$SIGNED_APP"
codesign --force --sign "$EXISTING_APPLE_DEVELOPMENT_IDENTITY" \
  --preserve-metadata=identifier,entitlements,flags "$SIGNED_APP"
codesign --verify --deep --strict "$SIGNED_APP"
scripts/package-release.sh "$SIGNED_APP" "$DEVELOPMENT_OUTPUT" --development
```

Use a separate output directory for this package. It requires an Apple Development authority
and a team identifier, and its README describes that exact signature and Gatekeeper result.
This is for the development Mac: it is not Developer ID distribution or notarisation. This
Mac currently has no Developer ID Application identity; public distribution remains separate.

Because the Release product *is* the shipped artefact, it does not carry
`com.apple.security.get-task-allow`. Ad-hoc signing injects that entitlement into both
configurations by default; the Release configuration sets
`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` to keep it out, Debug sets it to `YES` deliberately
so a debugger can still attach, and `scripts/entitlement-check.sh` asserts both directions.

### The artefact (D-09)

**Ad-hoc development download:** [0.1.0 content-aware development build](https://github.com/crmitchelmore/focus-sentinel/releases/tag/adhoc-0.1.0-46caf49).
This owner-approved download is not notarised, has no Developer ID, and may be refused by
macOS. Its release carries a SHA-256 checksum. It is separate from the signed production
trains and does not advance either update feed; manual checks can still report an unavailable
feed until the first production release is delivered. Requires an Apple silicon Mac running
macOS 26.0 or later.

`scripts/package-release.sh <app> <out>` makes `FocusSentinel-<version>-<commit>.dmg` from the
Release product the gate already built. It **never builds, never signs, and never touches the
keychain**: it `ditto`s the product (which preserves the supplied signature), writes a `README.txt`
beside it, and seals both into a read-only compressed image. `codesign` appears in it only with
`--verify` and `-dv`, which read.

The version and the commit are read out of the built product's own `Info.plist`, so an artefact
whose name says `741449c` is one whose bundle says `741449c`. The commit gets there by build
setting: `FOCUS_GIT_HASH` has an empty default in both configurations and
`Config/FocusSentinel-Info.plist` carries `$(FOCUS_GIT_HASH)`, which Xcode expands at the
process-plist step — **before** signing, so nothing edits a signed artefact. A plain Xcode.app
build therefore renders no hash and no dash, and Settings shows `0.1.0 (1)` rather than
`0.1.0 (1) · —`; the gate's `packaging` stage requires the key to be present and to equal
`git rev-parse --short HEAD` in both configurations.

**Gatekeeper rejects it, and the README on the image says so in Gatekeeper's own words.** An
ad-hoc-signed application is not notarised and has no Developer ID, so `spctl --assess` reads
`rejected`; the README quotes that verbatim, describes the normal macOS opening/approval
controls without promising they will accept every build, and states the macOS 26.0 requirement.
The gate's
`release-artefact` stage mounts the image read-only and asks six things of it: that it mounts;
that it holds exactly the application and the README; that the application inside is
**byte-identical** to the product every other stage read, by a digest of every file in both
trees; that `codesign --verify --deep --strict` passes; that `codesign -dv` still reads
`Signature=adhoc`; and that `spctl --assess` **exits non-zero**. The exit status is asserted and
the words are not — pinning a string Apple owns is `focus-652`'s shape, and the assertion would
be about macOS's copy rather than about this artefact. A Gatekeeper that *accepted* it would be
a failure, because it would mean either a local rule has made the reading meaningless or the
artefact is not the posture the README describes.

## Release trains (Alpha and Stable)

Two trains, modelled on the justspeaktoit release trains (focus-h8jf). Every fact that keeps them
apart is a row in `Config/ReleaseTrains.json`, and `scripts/generate-release-train-config.py`
renders it into `FocusCore`'s `ReleaseTrainCatalogue.swift`, which the `boundaries` stage checks
against the JSON so the app and the release scripts read one table:

| | Stable | Alpha |
|---|---|---|
| bundle identifier | `com.chrismitchelmore.FocusSentinel` | `com.chrismitchelmore.FocusSentinel.alpha` |
| display name | Focus Sentinel | Focus Sentinel Alpha |
| store directory | `~/Library/Application Support/com.chrismitchelmore.FocusSentinel` | `…/com.chrismitchelmore.FocusSentinel.alpha` |
| URL scheme | `focus://` | `focus-alpha://` |
| Sparkle feed | `releases/latest/download/appcast.xml` | `releases/download/alpha-latest/appcast.xml` |
| icon | `AppIcon` | `AppIconAlpha`, the Stable icon with its hue turned by `scripts/make-alpha-icon.swift` |

**How a build knows which it is.** The project has three configurations: `Debug` and `Release`
are Stable, and `Alpha` is the Release settings with the train's identity. `FOCUS_RELEASE_TRAIN`
and `FOCUS_URL_SCHEME` are build settings substituted into `Config/FocusSentinel-Info.plist` the
way `FOCUS_GIT_HASH` is, and `ReleaseTrain.current` reads the plist key back, refusing an Alpha
bundle identifier that claims Stable. A process with no train metadata — a unit process, a
preview, a plain Xcode.app build — is Stable, which is what every build before this one was.
`xcodebuild … -configuration Alpha` is the whole of building the other train.

**The updater is opt-in, per install.** `SparkleUpdater` (`Packages/FocusUpdates`) builds
Sparkle's standard controller with `startingUpdater: false` and starts it from exactly two verbs:
the *Check for updates automatically* switch in Settings ▸ General,
which stores the choice in `SoftwareUpdatePreferenceRecord` (schema v11) and is read back at the
next launch, and *Check for updates now* in Settings or the File menu. The manual check does not
enable automatic checks, including when Sparkle remembers an older opt-in. Off is the shipped
state, and no stored preference means off. A failed startup remains retryable rather than marking the updater as
started. Settings reports configuration, connection and unavailable-feed failures separately.
The feed
is `ReleaseTrain.current.feedURL`, answered by the delegate, so there is no `SUFeedURL` in the
plist and an Alpha install is never offered a Stable build or the reverse. Every enclosure is
verified against `SUPublicEDKey`; the private half of that key lives in the login keychain of the
Mac that signs releases under the Sparkle account `Focus Sentinel`, and is in no file in this
repository.

**The flow**, in `scripts/release-train.py` and four workflows on the self-hosted runner:

1. **Alpha.** `alpha-release.yml` allocates an immutable `alpha-build-N` tag with a manifest from
   a `main` commit (on dispatch while `Config/ReleasePipeline.json` says `"enabled": false`;
   on every green push to `main` once the owner flips it), then `release-mac.yml` builds the
   `Alpha` configuration, signs it with the Developer ID identity on the runner, notarises it,
   packages the DMG with `scripts/package-release.sh`, signs the appcast with `sign_update`, and
   uploads everything to a GitHub **prerelease**. Only then does the `alpha-latest` pointer
   release advance, which is what the Alpha feed reads.
2. **Prepare Stable.** `prepare-stable.yml` takes a tested `alpha-build-N` and a version, freezes
   them as a `stable-candidate-N` manifest, and rebuilds the `Release` configuration from the
   same source under the Stable identity into a **draft** release.
3. **Publish Stable.** `publish-stable.yml` takes the candidate and the SHA-256 of its reviewed
   manifest, and only the repository owner may run it. It publishes the draft as `vX.Y.Z`, marks
   it Latest — which is what the Stable feed reads — and records a receipt on the candidate.

Stable appcasts name the final public `vX.Y.Z` download, not the draft candidate. Alpha
appcasts name their immutable `alpha-build-N` download. The release worker checks both mappings
with `python3 scripts/test-release-train.py` before building.

Nothing in the flow signs with the gate's ad-hoc identity or claims Gatekeeper acceptance for
it. What the runner needs before either train can ship is in "What still gates the trains".

**What still gates the trains.** One thing the repository cannot supply: signing material.
`release-mac.yml` takes it either from the runner's login keychain — a *Developer ID Application*
identity plus a `notarytool` keychain profile named `focus-notary`, both named in
`Config/ReleasePipeline.json` — or from the same five repository secrets justspeaktoit's release
workflow uses (`APPLE_DEVELOPER_ID_APPLICATION` as a base64 `.p12`,
`APPLE_DEVELOPER_ID_APPLICATION_PASSWORD`, `APP_STORE_CONNECT_API_KEY` as a base64 `.p8`,
`APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`), imported into a temporary keychain
for the job and deleted afterwards.
The encrypted identity must include its matching private key; an Apple Development certificate
or a certificate-only export cannot replace it. The notarisation API key must include both its
Key ID and Issuer ID. Secret-availability flags are job-scoped so the import steps can evaluate
them before their step environments exist.

**Release hosting is public.** The feed and every enclosure must be readable over HTTPS
without GitHub credentials. The repository and its signed release assets are publicly hosted at
`crmitchelmore/focus-sentinel`; the Stable download is on
[the latest release](https://github.com/crmitchelmore/focus-sentinel/releases/latest).
A train's feed becomes available only after its first signed release is published. Signing in
to GitHub in a browser does not authenticate Sparkle. Never embed a GitHub token in the app,
and do not treat an unavailable feed as “you’re up to date”.

## Privacy posture

No accounts, no telemetry, no analytics, and one third-party package: every `Package.swift` in
this repository declares local siblings only, except `Packages/FocusUpdates`, which declares
Sparkle and nothing else, and the gate's `boundaries` stage asserts both halves — a remote
dependency anywhere else fails, and that package declaring anything but Sparkle fails
(focus-h8jf). The app ships with no network entitlement, and `FocusClassify` carries a
zero-networking assertion that fails closed.

That assertion now has a fourth form and a companion. `nm -u FocusClassify.o` names no
networking symbol — and no window-list, Accessibility or screen-capture symbol either, which is
the **binary** proof that the private-browsing fixtures could not have cheated: a test can only
observe that the engine did not try another route, and the symbol table proves it could not.
`NLContextualEmbedding` is banned outright alongside it, not because it misbehaved but because
its API surface includes an asset *request*, and a package whose whole guarantee is that it
cannot reach the network may not name a type that can ask for a download.

**`FoundationModels` gets the same treatment one package over.** It is named in exactly one
file in this repository — a count, not a ban, so moving the producer is a reviewed act — and
that file is in `Packages/FocusModel`, whose framework row is pinned to `Foundation
FoundationModels os` and whose forbidden set covers every networking type. The asset-pulling
surface is linted by name: `prewarm()`, `SystemLanguageModel.Adapter` and
`SystemLanguageModel(useCase:)` appear nowhere in `App/` or `Packages/`, so "we never trigger a
download" is a lint rather than a promise. It was also measured: `lsof -nP -i` sampled every
100 ms across a probe's whole life produced **zero** lines over eighty samples, `nettop -P` a
header and no data row, and the OS's own model daemon logged *"Unentitled inference allowed"* —
no entitlement is added, and none of `entitlement-check.sh`'s five forbidden keys is implicated.

Nothing the engine concludes can carry raw captured content. Every textual payload an
explanation can hold is a `NormalisedToken`, which has no public `String` initialiser and
rejects whitespace, control characters and every ASCII punctuation mark but `.`, `-` and `_` —
so a window title, a full URL, a document name or an absolute path is *unrepresentable* in an
explanation rather than forbidden. `ClassificationInput.origin` is exercised by the golden corpus and **empty in every shipping
code path in this version**. The window-derived inputs a shipping path supplies are
`ClassificationInput.selectedItem` and, carrying the same label, `.titleTokens` — an
already-normalised label read only with the person's Accessibility opt-in (issue #24), which can
corroborate a relevant verdict and nothing else.

### The opt-in remote judge (Decision-1)

**Off by default, behind a switch in Settings ▸ Privacy.** One file in this repository's own
code opens a connection: `Packages/FocusHost/Sources/FocusHost/RemoteJudge/DecisionOneJudge.swift`,
which asks Microsoft's Decision-1 (System One) model the model rung's question — *is this window
part of the priority I wrote down?* `check-boundaries.sh` exempts that one path from its
networking scan, fails if the file is gone, and still fails on any second file. The judge is
composed for the person's own store only, never under the in-memory store the unit lane uses and
never under `--focus-self-check`, so the gate's socket sampling still reads zero and
`composesTheRung` is still `false` for the on-device model. Composed is not on: until the person
switches *Ask Decision-1* on (`FocusRemoteJudgeEnabled`), every judgement declines before a
window is read.

Why it exists: on the 45-cell corpus the on-device model went quiet about fifteen holds and was
never released. Given the window's content, Decision-1 rescued all fifteen and was seduced by
none at threshold 0.6, at about 0.2 s and an estimated $46 per 1,000 users a month — the same
quality as `gpt-5.6-luna` at a quarter of the cost (`Tools/ContextSpike/README.md`).

What it sends, once per priority revision and per selected page or item, held in memory only:
the priority sentence, and — only while the application asked about is still frontmost, cleared
by e03's `SensitivityGate` (so never a password manager or a private window), and only with the
Accessibility opt-in on — the window's title, file path, web address reduced to host and path,
focused element and up to 6,000 characters of text, read in `SelectedItemReader.swift` through
the same three selectors. It can only rescue: there is no `unrelated` answer, and any failure is
a decline that leaves the deterministic verdict standing. A judge it could not reach (no token,
offline, 401/403/408/429/5xx) is not cached: it is asked again after a quiet minute
(`RemoteJudgeBackoff`), so a sign-in or a network that comes back is picked up without a relaunch.

To turn it on (the credential is an Entra token from a signed-in Azure CLI; nothing is stored):
`az login`, then switch on the Accessibility ask and *Ask Decision-1* in Settings ▸ Privacy. The
endpoint defaults to the measured deployment; another can be given in the app's defaults
(`FocusRemoteJudgeEndpoint`, HTTPS only; `FocusRemoteJudgeDeployment`;
`FocusRemoteJudgeThreshold`, 0.5–0.95), read at launch. Alpha builds read the
`com.chrismitchelmore.FocusSentinel.alpha` domain. The Privacy pane's network sentence names
this switch alongside update checks.

## License

MIT. See [LICENSE](LICENSE). Sparkle, the one third-party framework the app ships, is
distributed under its own MIT licence by the Sparkle Project.
