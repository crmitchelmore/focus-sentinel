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
| `scripts/` | the build gate and its stages |
| `Tools/` | test drivers only; not part of the shipping app's package graph |

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

## Privacy posture

No accounts, no telemetry, no analytics, no third-party packages: every `Package.swift` in this
repository declares an empty `dependencies` array, and the check that asserts it is a gate
stage. The app ships with no network entitlement, and `FocusClassify` carries a
zero-networking assertion that fails closed.
