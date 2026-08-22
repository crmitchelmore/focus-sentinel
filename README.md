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
| `App/` | the thin app target — composition root, scenes, entitlements, string catalog |
| `Packages/FocusCore` | domain types, SwiftData schema, status tokens, clocks, appearance traits |
| `Packages/FocusRules` | the deterministic rule model |
| `Packages/FocusClassify` | the classification seam — no networking, ever |
| `Packages/FocusSensing` | macOS observation adapters |
| `Packages/FocusUI` | every SwiftUI view, scene, command and design token |
| `scripts/` | the build gate and its stages, plus the live evidence lane |
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
failed. It never short-circuits: a failing early stage does not hide a later one. The stages:

| # | stage | what it proves |
|---|---|---|
| 1 | `verify-project.sh` | the project file parses, and git has not been rewritten behind you |
| 2 | `check-boundaries.sh` | the package import matrix holds; zero third-party dependencies |
| 3 | `check-forbidden.sh` | no `kCGWindowName`, no Apple Events, no private APIs, no plan-less `ModelContainer` |
| 4 | `check-strings.sh` | no hardcoded user-visible string; the catalogs and the code agree both ways |
| 5 | Debug build | `EXIT=0` |
| 6 | Release build | `EXIT=0` |
| 7 | the unit lane | every package test target, headless |
| 7b | `check-boundaries.sh` again | `nm -u FocusClassify.o` has no networking symbol — the binary-level form of the assertion, which needs a build product to exist |
| 8 | `entitlement-check.sh` ×2 | no network entitlement, Debug **and** Release; and `get-task-allow` present in Debug, **absent** in Release |
| 9 | `self-check.sh` ×2 | the app's own zero-grant report of its menu bar, window and key equivalents |
| 10 | `verify-project.sh` again | the build did not rewrite the project |

---

## Verification

There are two kinds of check in this repository and the difference is not a matter of taste.

**The gate runs with zero TCC grants — for the app *and* for the shell that invokes it.**
Nothing above needs Accessibility, Screen Recording or Automation. Revoke every permission on
this Mac and the gate must still be green; that is the contract, and it is why the app reports
its own menu bar from inside its own process instead of being interrogated from outside.

**The live lane needs three grants and is therefore evidence, never a criterion.**
`scripts/live-shell-drive.sh` drives the real app with `osascript` and captures its windows
with `screencapture`, which works only because the driving shell holds Accessibility,
Automation and Screen Recording. No acceptance criterion may depend on a permission grant, so
what this lane produces is quality evidence a human reads. When a grant is missing it prints
`LIVE-LANE SKIPPED: <grant>` and exits `0`, and `build-gate.sh` never invokes it.

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

# the TCC-gated evidence lane — read the frames it captures; capturing them is not the point
scripts/live-shell-drive.sh
```

Never pipe any of it. Redirect unpiped to a log and gate on the explicit exit status.

### Environment contracts

| variable | used by | meaning |
|---|---|---|
| `FOCUS_DERIVED_DATA` | the gate, the live lane | build location. Default `/tmp/focus-dd` |
| `FOCUS_LOG_DIR` | the gate | where the stage logs are written. Default `/tmp` |
| `FOCUS_RESULT_BUNDLE` | the gate | the unit lane's `-resultBundlePath`. Default is unique per run; either way it is `rm -rf`'d immediately before the run |
| `FOCUS_EVIDENCE_DIR` | the gate, `self-check.sh`, the live lane | where the evidence set is assembled. Default for the live lane: `.agents/evidence/e01`. **Never committed** |
| `FOCUS_SNAPSHOT_OUT` | the snapshot lane, the gate | where snapshot renders are written. Default `$TMPDIR/focus-snapshots`. Note that `xcodebuild` does not forward its environment to a SwiftPM test process, so under the gate this names where to *look*, not where to write |
| `FOCUS_SNAPSHOT_RECORD=1` | the snapshot lane | re-record the committed baselines instead of comparing. `swift test` only, for the same reason. Recorded PNGs are read by eye before being committed |
| `FOCUS_FIXTURE_RECORD=1` | `MigrationFixtureTests` | rewrite the committed v1 store fixture instead of asserting against it |
| `FOCUS_SELFCHECK_JSON` | `self-check.sh` | where the app's self-check report is written |
| `FOCUS_LIVE_TEXT_SIZE=raised` | the live lane | capture `main-accessibility.png` — only meaningful once the system-wide Text Size has been raised by hand, because macOS has no injectable Dynamic Type |

### Evidence

With `FOCUS_EVIDENCE_DIR` set, the gate assembles `gate.log`, `build-debug.log`,
`build-release.log`, `test.log`, `project.log`, `boundaries.log`, `forbidden.log`,
`strings.log`, `entitlements.txt`, `selfcheck.json`, `selfcheck.log`, their Release
counterparts, and a `snapshots/` copy of every render. The live lane adds `menus.txt` and the
shell frames to the same directory when the grants exist. That directory is evidence, not
source: it is never committed.

---

## The project file

`FocusSentinel.xcodeproj/project.pbxproj` is **hand-authored source**, not generated output.
There is no generator and no regeneration command — by design.

* Object ids are stable and human-assigned from documented blocks; they are never randomised.
* File membership is directory-implicit through a `PBXFileSystemSynchronizedRootGroup`, so
  adding a Swift file under `App/` touches no project file at all. The project changes only
  when a target or a package reference is added.
* `scripts/verify-project.sh` proves the file still parses and then runs
  `git diff --exit-code -- FocusSentinel.xcodeproj Focus.xcworkspace`.

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
