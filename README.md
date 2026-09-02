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
| `App/` | the thin app target — `@main`, the scenes, the appearance observer, the entitlements, the icon, and a deliberately empty string catalog (see "Strings" below). It owns no host and no wiring: those are `Packages/FocusHost` |
| `Packages/FocusCore` | domain types, SwiftData schema, status tokens, clocks, appearance traits |
| `Packages/FocusRules` | the deterministic rule model |
| `Packages/FocusClassify` | the deterministic relevance engine and the classification seam — no networking, ever. It also holds `FocusEvaluateCore` and the `FocusEvaluate` product, which are test-lane only and which no application target links |
| `Packages/FocusSensing` | macOS observation adapters |
| `Packages/FocusUI` | every SwiftUI view, scene, command and design token |
| `Packages/FocusHost` | the composition layer — `AppComposition` and the five hosts. The only module that imports more than one sibling package, and the reason it is a package rather than the app target is that `App/` is not one: no test bundle could import it, so every claim about the wiring in it was a source scan (see "Why the composition layer is a package" below) |
| `Config/` | build inputs that are neither app source nor scripts. Exactly one file: `FocusSentinel-Info.plist`, the partial plist carrying `CFBundleURLTypes`. It lives here and **not** in `App/` — see "The project file" below |
| `scripts/` | the build gate and its twenty-two stages, plus the six live evidence lanes |
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
| 6b | `eval-clean` | **the only cleanup stage in the gate.** It removes `$FOCUS_EVAL_OUT` (default `$TMPDIR/focus-eval`) in its entirety and touches an mtime marker, immediately before `unit`. A missing directory is a pass; a failure to remove is a hard fail. See "The evaluation lane" below for why a gate needs one |
| 7 | the unit lane | every package test target, headless |
| 7' | `unit-counts` | **the gate can see a test bundle die.** Reads the unit lane's own log: no `Program crashed`, no `Restarting after unexpected exit`, no `Test Suite 'Selected tests' started` retry banner — *regardless of exit status*, because a retry that then passes exits `0` having run a fraction of the suite — six `Test run with N tests` summaries, and each `>=` its committed floor in `Config/test-floors.txt`, paired positionally with the scheme's testables. Floors, never equalities: adding a test may not redden the gate and losing one must. See `focus-jg7` |
| 7d | `evaluation` | runs the `FocusEvaluate` **product**, copies its report into this run's log directory *before* anything parses it, applies five binding checks to that copy, and only then reports the metric verdict. See "The evaluation lane" |
| 7b | `check-boundaries.sh` again | `nm -u FocusClassify.o` has no networking symbol — the binary-level form of the assertion, which needs a build product to exist |
| 7c | `check-forbidden.sh` again | the binary half of SC-1: `nm -u` finds no `_kCGWindowName` in **seven products named one by one** — the app binary, `FocusCore.o`, `FocusSensing.o`, `FocusRules.o`, `FocusClassify.o`, `FocusUI.o` and `Tools/windowid` — while the four sanctioned window-list symbols are asserted **present** in `windowid`, so the check cannot pass by the tool being gutted. Under `FOCUS_REQUIRE_BINARY_CHECK=1` a *missing* product is a failure, not a skipped line. `windowid` is built by the stage itself, because it lives outside the workspace scheme |
| 8 | `entitlement-check.sh` ×2 | no network entitlement, Debug **and** Release; and `get-task-allow` present in Debug, **absent** in Release |
| 9 | `self-check.sh` ×2 | the app's own zero-grant report of its menu bar, window and key equivalents — and, from e02, its declared URL schemes, its hot-key registration status, the Edit menu's undo title after one scripted in-process mutation, the pre-built capture panel's show latency, and the priority hero's point size against every other type role. From e03 it is **three launches**: the shell report, plus a session seeded back-dated ninety minutes into a store of its own and a **separate** launch that restores it. See "What the self-check adds in e03" below |
| 9a | `check-focus-steal.sh` | **the panel takes nothing.** Launches the Debug app with `open -g -a` — a background application that has never been frontmost, which is the posture a nudge really fires in — shows the panel and asserts all four of R-89's grant-free readings. See "The nudge loop" below |
| 9b | `check-notification-denied.sh` | **F-73's degraded path, and what discharges standing condition 5 for e05.** Zero grants, no prompt of any kind, and every rung of the ladder still reaches an in-app surface; `requestAuthorizationCallCount == 0` |
| 9c | `check-focus-steal.sh` again | the same stage against the **Release** product — the artefact this programme ships. A whole-module-optimised binary is not the same binary, which is why the boundary and forbidden stages read both configurations; until this stage existed, every geometry reading in `check-focus-steal.sh` held of a build nobody installs |
| 9d | `check-notification-denied.sh` again | the same, for the routing half: the 160-cell rung fold, the 80-cell question fold and `requestAuthorizationCallCount == 0`, read from the Release product |
| 10 | `verify-project.sh` again | the build did not rewrite the project |

**Twenty-two stages — it was twenty until `focus-steal-release` and
`notification-denied-release` were added.** Saying so plainly, because the epic's close
condition names the count: `project`, `boundaries`, `forbidden`, `strings`, `build-debug`,
`build-release`, `packaging`, `eval-clean`, `unit`, **`unit-counts`**, `evaluation`,
`boundaries-binary`, `forbidden-binary`, `entitlements-debug`, `entitlements-release`,
`selfcheck-debug`, **`focus-steal`**, **`notification-denied`**, `selfcheck-release`,
**`focus-steal-release`**, **`notification-denied-release`**, `project-post`.

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

## The relevance engine

The app has a judgement, and it is **deterministic**. There is no model: `FoundationModels` is
not imported, not linked, not probed and not availability-gated anywhere, and a lint fails the
gate on the mere mention of it. The heuristic layer is the *whole* engine, which is what makes
the charter's "fallback always present and independently tested" clause temporally true rather
than a promise about a later release.

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
| 6 | on-device model | from a later release | **no** |
| 7 | built-in "ask each time" | `uncertain` only | yes |
| 8 | nothing matched | `uncertain` only | yes |

Four readers, three of them mechanically checked: the runtime iterates `executableRungs` (the
unavailable rung is *not in the sequence*, rather than skipped by a special case); the
explanation builder switches exhaustively over the stages; the Settings precedence pane renders
the list in rank order against a committed snapshot baseline; and `check-strings.sh` asserts a
bijection between the stages and the `cascade.rung.*` catalog keys. Two rules that match at the
same authority **and** the same subject kind and disagree resolve to `uncertain` — never by
recency, and never to `unrelated`.

### The evaluation lane

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

---

## The nudge loop

The app speaks under exactly three postures, and the third one is a user ruling that inverts the
obvious default:

| verdict | what the app does |
|---|---|
| `relevant`, confidently derived | **silence** — and it is the *only* thing that buys silence |
| `uncertain` | **a question**: "Is *{subject}* part of *{task}*?", asked once and never again |
| `unrelated` | **the ladder**: silent glyph → non-activating panel → recommitment |

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
typed symbol — never a bare literal, never `String(format:)`. `scripts/check-strings.sh` is a
gate stage and checks both directions: no hardcoded user-visible literal, and no key that is
in a catalog but unused or used but missing.

There are four catalogs and each module resolves its own against its own bundle, so they are
checked separately:

| catalog | keys | who reads it |
|---|---|---|
| `Packages/FocusUI/Sources/FocusUI/Resources/Localizable.xcstrings` | `shell.`, `settings.`, `priority.`, `capture.`, `context.`, `handoff.`, `session.`, `sensing.`, `capability.` | `FocusUI`, and the app target through `ShellStrings` |
| `Packages/FocusCore/Sources/FocusCore/Resources/Localizable.xcstrings` | `status.` (the `FocusStatus` short labels), `undo.` (the action names the system Edit menu draws after "Undo"), and the relevance vocabulary — `cascade.`, `explanation.`, `suppression.`, `evidence.`, `rule.` | `FocusCore`, and `FocusUI` through the `…Resource` accessors each vocabulary exposes |
| `App/Localizable.xcstrings` | **none, by design** | nothing yet |
| `Packages/FocusHost/Sources/FocusHost/Resources/Localizable.xcstrings` | **none, by design** | nothing yet |

The app target's catalog is empty because the app target is a composition root: it declares
scenes and wires concrete types to protocols, and even its window titles are `FocusUI` keys
resolved from `FocusUI`'s bundle. The file is kept rather than deleted because it is the
declared home for anything the app target ever does own, and because deleting it would remove
the `App` row from the lint's table — the only check that would notice an app-target source
starting to name a catalog key that its bundle cannot resolve. So the lint asserts the
emptiness instead: `App` is listed in `EXPECTS_NO_STRINGS`, and a key appearing there fails
the gate with instructions to move it to `FocusUI` or to change the list on purpose.

`FocusHost` carries the same empty catalog and the same row for the same reason: the hosts
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

That assertion now has a fourth form and a companion. `nm -u FocusClassify.o` names no
networking symbol — and no window-list, Accessibility or screen-capture symbol either, which is
the **binary** proof that the private-browsing fixtures could not have cheated: a test can only
observe that the engine did not try another route, and the symbol table proves it could not.
`NLContextualEmbedding` is banned outright alongside it, not because it misbehaved but because
its API surface includes an asset *request*, and a package whose whole guarantee is that it
cannot reach the network may not name a type that can ask for a download.

Nothing the engine concludes can carry raw captured content. Every textual payload an
explanation can hold is a `NormalisedToken`, which has no public `String` initialiser and
rejects whitespace, control characters and every ASCII punctuation mark but `.`, `-` and `_` —
so a window title, a full URL, a document name or an absolute path is *unrepresentable* in an
explanation rather than forbidden. `ClassificationInput.origin` and `.titleTokens` exist, are
exercised by the golden corpus, and are **empty in every shipping code path in this version**.
