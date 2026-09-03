#!/bin/zsh
# Package boundaries and the zero-networking guarantee.
#
# The five packages exist so that the privacy posture is checkable at the dependency-graph
# level rather than by reading code. This script is what makes that true: the import matrix
# below is enforced, not documented.
#
#   package        may import                                  must never import
#   ------------   -----------------------------------------   -------------------------------------------------
#   FocusCore      Foundation, SwiftData, os                    AppKit, SwiftUI, networking, any sibling
#   FocusRules     Foundation, SwiftData, FocusCore             AppKit, SwiftUI, networking, Classify/Sensing/UI
#   FocusClassify  Foundation, NaturalLanguage, Core, Rules     ANY networking, AppKit, SwiftUI, Sensing, UI
#   FocusSensing   Foundation, AppKit, CoreGraphics, IOKit,     SwiftUI, networking, Classify, Rules, UI
#                  Carbon.HIToolbox, CoreAudio, CoreMediaIO,
#                  ServiceManagement, FocusCore
#   FocusUI        SwiftUI, AppKit, Observation, QuickLook,     SwiftData, networking, Sensing, Classify, Rules
#                  UniformTypeIdentifiers, FocusCore
#   FocusHost      Foundation, AppKit, SwiftData, Observation,   SwiftUI, networking
#                  ApplicationServices, os, ALL FIVE siblings
#
# The sixth row is the composition layer, and it is the one row that may import every sibling
# at once — because that is the whole of its job. It used to be the app target, where the same
# permission was granted implicitly and checked by nothing: `App/` is not a package, so no
# `swift package describe` could read its graph and no test bundle could import its module.
# Three mutations to `NudgeHost` survived a full green suite for exactly that reason. Making it
# a package puts its dependencies under this matrix and its wiring under a test target.
#
# It may **not** import SwiftUI. Views are FocusUI's, and a composition root able to declare
# one would be a second place surfaces are written. `ApplicationServices` is the self-check's,
# and only the read-only half: it is how `--focus-self-check` reports whether Accessibility has
# been granted without ever asking for it.
#
# The three e02 additions are rulings, not conveniences (plan R-14):
#
#   * **`SwiftData` for `FocusRules`.** The `RuleStore` protocol e01 shipped needed a durable
#     implementation, and putting it anywhere else would mean a second package knowing the rule
#     vocabulary.
#   * **`Carbon.HIToolbox` for `FocusSensing`**, in exactly one file. A global hot key is a
#     platform input adapter, which is what this package is for; the file-level allowlist and
#     its self-limiting assertion live in `check-forbidden.sh` (R-13).
#   * **`QuickLook` and `UniformTypeIdentifiers` for `FocusUI`.** `.quickLookPreview(_:in:)` is
#     the `_QuickLook_SwiftUI` cross-import overlay and appears only with `import QuickLook`
#     (P-62) — a boundary fact, not an implementation detail.
#
# The two e03 additions are the same kind of ruling (plan R-31), and both are measured rather
# than assumed:
#
#   * **`CoreAudio` for `FocusSensing`.** Whether a microphone is running somewhere is a
#     platform fact, and this package is where platform facts are read. Observing it was
#     measured prompt-free from an ad-hoc-signed bundle holding no TCC row: five devices
#     enumerated, `IsRunningSomewhere` read on every one, a property listener installed and
#     removed on every one, all at status `0`, with both TCC databases byte-identical
#     afterwards (probes P-94/P-95/P-104). Only devices reporting **input** channels are read —
#     an output device running is a person listening to music (P-96).
#   * **`CoreMediaIO` for `FocusSensing`.** The camera enumeration alone, which is the one call
#     that *was* measured prompt-free (P-97). The deeper camera path is compiled but held off
#     behind a flag set nowhere, because the rig has no camera and an unanswered question is not
#     a pass (P-104, R-40).
#
# The one addition Section 3 makes is a ruling of the same kind (D-12, focus-odz.4):
#
#   * **`ServiceManagement` for `FocusSensing`**, in exactly one file. Opening at login is a
#     platform registration, and this package is where platform facts are read and platform
#     adapters live — `SMAppService.mainApp` sits beside the Carbon hot key for the same reason.
#     It costs the matrix nothing it was protecting: the framework carries no networking, no
#     window list and no Accessibility surface, and `SMAppService.status` raises no TCC prompt of
#     any kind. What it *can* do is write into the person's Login Items, so the ban that matters
#     is not an import ban: nothing in any lane calls `register()` or `unregister()`. The
#     self-check reads the status and calls neither verb, and every test drives the offer through
#     `LoginItemControlling`, which is why that protocol exists.
#
# The one e05 addition is a ruling of the same kind (plan R-82, T137):
#
#   * **`UserNotifications` for `FocusUI`.** **The justification here named the rung U-2 deleted**
#     (focus-3vb, focus-484). It read "the top rung of the accusation ladder is a notification
#     where the person has authorised one" — and since U-2 no rung routes to a notification at
#     all, so this line was the enabling half of a ban nothing enforced: a reader checking why the
#     framework is permitted found a reason that had stopped being true.
#
#     What the allowance is actually for now is **listening**. A banner an earlier build posted
#     can still be sitting in Notification Centre for as long as the person leaves it there, and
#     `NudgeHost.resolveFromNotification(…)` must be able to name the surface it came from in
#     order to refuse the press. Two calls remain behind the `NotificationCentring` seam —
#     `getNotificationSettings`, which P-134 measured never prompting, and a delegate that
#     receives a press — and neither can post anything.
#
#     **The allowance is bounded at the artefact, not by this comment.** `check-forbidden.sh`'s
#     R-96s asserts the shipped Mach-O carries none of the five posting selectors, with the two
#     reading selectors as its non-vacuity control, on Debug and on Release. That is what makes
#     U-2 structural rather than remembered.
#     It costs the matrix nothing it was protecting: P-134 measured `getNotificationSettings`,
#     `setNotificationCategories` and `add(_:)` all obtainable at zero grants and **none of them
#     prompting**, and the one call that *would* prompt — `requestAuthorization` — is pinned by
#     `check-forbidden.sh`'s R-96g to a single named file, which is the settings pane's
#     user-initiated action and is not this one. The framework carries no networking, no window
#     list and no Accessibility surface.
#
# `mach_continuous_time` and `sysctl kern.boottime` need no row of their own: both are reachable
# through `Foundation` on macOS, so the restoration anchor costs the matrix nothing.
#
# Note what is **not** added: `ScreenCaptureKit`, `AVFoundation`, `CoreMedia`,
# `ApplicationServices`, `Accessibility`. Every one of those is either a prompt or a grant, and
# this epic is the zero-grant half of sensing.
#
# And one **subtraction**, which is the point of R-24: `FocusUI` may not import `SwiftData`.
# e01 left that unstated because nothing yet tempted the UI to open a store; e02 gives it a
# cockpit full of persisted values and a `PriorityActing` protocol to reach them through, so
# the rule stops being aspirational and becomes a lint.
#
# Four further assertions:
#
#   * **Zero third-party code.** Every declared package dependency must be a local
#     `fileSystem` path to a sibling inside `Packages/`. A remote dependency — a URL or a
#     registry identity — fails the gate. (A local sibling dependency is how the matrix
#     above is expressed at all: a package cannot `import FocusCore` without one.)
#   * **The matrix is exact.** Each library target's product dependencies must equal the
#     permitted set, not merely be a subset of it.
#   * **FocusClassify cannot reach the network at the binary level.** When a build product
#     exists, `nm -u FocusClassify.o` must contain no networking symbol at all.
#   * **No package imports a framework its row does not name.** The forbidden list catches the
#     imports somebody thought of; this catches the ones nobody did. A new framework in a
#     package is a boundary decision, so it fails the gate until the table above says so.
#
# e04 adds two more, both about the same object and both proved on the binary rather than in
# the source (plan R-70i/j):
#
#   * **`FocusClassify` probes no privacy boundary.** `nm -u FocusClassify.o` must name no
#     window-list, Accessibility or screen-capture symbol at all. The adversarial
#     private-browsing fixtures assert that an absent origin yields `uncertain`; a test can
#     only observe that the engine did not try another route, and the symbol table proves it
#     could not. Promoted from skip to failure by `FOCUS_REQUIRE_BINARY_CHECK=1`, exactly like
#     the zero-networking half above.
#   * **The `FocusClassify` framework row is unchanged from e01.** It is listed here *because
#     it needs no edit*: e04 puts a whole classification engine in that package and adds no
#     framework to it, and pinning the row is what turns "no new dependency" from a claim into
#     a check.
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

DERIVED_DATA="${FOCUS_DERIVED_DATA:-/tmp/focus-dd}"
rc=0

fail() {
    print -u2 "FAIL: $*"
    rc=1
}

# --- the matrix -------------------------------------------------------------------------

typeset -A ALLOWED_PRODUCTS
ALLOWED_PRODUCTS[FocusCore]=""
ALLOWED_PRODUCTS[FocusRules]="FocusCore"
ALLOWED_PRODUCTS[FocusClassify]="FocusCore FocusRules"
ALLOWED_PRODUCTS[FocusEvaluate]="FocusCore FocusRules FocusClassify"
ALLOWED_PRODUCTS[FocusSensing]="FocusCore"
ALLOWED_PRODUCTS[FocusUI]="FocusCore"
ALLOWED_PRODUCTS[FocusHost]="FocusClassify FocusCore FocusRules FocusSensing FocusUI"

typeset -A FORBIDDEN_IMPORTS
FORBIDDEN_IMPORTS[FocusCore]="AppKit SwiftUI Cocoa Network CFNetwork NetworkExtension FocusRules FocusClassify FocusSensing FocusUI"
FORBIDDEN_IMPORTS[FocusRules]="AppKit SwiftUI Cocoa Network CFNetwork NetworkExtension FocusClassify FocusSensing FocusUI"
FORBIDDEN_IMPORTS[FocusClassify]="AppKit SwiftUI Cocoa Network CFNetwork NetworkExtension FocusSensing FocusUI"
# The evaluation lane is not in the shipping graph, and this row is what keeps it out of one.
# It may reach the engine and the two packages beneath it and nothing else — no surface
# framework, no sensing, no networking. The three test-lane reads further down add the positive
# half over the same trees.
FORBIDDEN_IMPORTS[FocusEvaluate]="AppKit SwiftUI Cocoa Network CFNetwork NetworkExtension FocusSensing FocusUI"
FORBIDDEN_IMPORTS[FocusSensing]="SwiftUI Network CFNetwork NetworkExtension FocusClassify FocusRules FocusUI"
# SwiftData is on FocusUI's forbidden list from e02, and it is the enforcement point for R-24:
# the cockpit renders a `CockpitState` value and calls a `PriorityActing` protocol, both
# declared in `FocusCore`, and `FocusHost`'s `PriorityHost` is the only type that opens a store.
# That is what keeps every surface in this package snapshot-testable with no container.
FORBIDDEN_IMPORTS[FocusUI]="SwiftData Network CFNetwork NetworkExtension FocusSensing FocusClassify FocusRules"
# The composition layer's one prohibition. Everything else it is allowed precisely because it
# is the layer that assembles the others; SwiftUI is not, because a view here would be a view
# outside FocusUI.
FORBIDDEN_IMPORTS[FocusHost]="SwiftUI Cocoa Network CFNetwork NetworkExtension"

# The positive half of the matrix: every platform framework each package is permitted to
# import. Sibling packages are handled by ALLOWED_PRODUCTS above and are added to this set per
# package below, so a row here names frameworks only.
typeset -A ALLOWED_FRAMEWORKS
ALLOWED_FRAMEWORKS[FocusCore]="Foundation SwiftData os"
ALLOWED_FRAMEWORKS[FocusRules]="Foundation SwiftData os"
ALLOWED_FRAMEWORKS[FocusClassify]="Foundation NaturalLanguage os"
ALLOWED_FRAMEWORKS[FocusEvaluate]="Foundation os"
ALLOWED_FRAMEWORKS[FocusSensing]="Foundation AppKit CoreGraphics IOKit Carbon.HIToolbox CoreAudio CoreMediaIO ServiceManagement os"
ALLOWED_FRAMEWORKS[FocusUI]="Foundation SwiftUI AppKit Observation QuickLook UniformTypeIdentifiers UserNotifications os"
ALLOWED_FRAMEWORKS[FocusHost]="Foundation AppKit SwiftData Observation ApplicationServices os"

PACKAGES=(FocusCore FocusRules FocusClassify FocusEvaluate FocusSensing FocusUI FocusHost)

# Foundation networking types that are the usual accidental route onto the network.
NETWORK_SYMBOL_PATTERN='URLSession|URLRequest|URLConnection|NWConnection|NWListener|NWBrowser|CFStream|CFSocket'

print "== import matrix"
printf '%-16s %-28s %s\n' "package" "permitted products" "declared products"

for package in $PACKAGES; do
    dir="Packages/$package"

    if [[ ! -f "$dir/Package.swift" ]]; then
        fail "$package: no Package.swift at $dir"
        continue
    fi

    describe=$(cd "$dir" && swift package describe --type json 2>/dev/null)
    if [[ -z "$describe" ]]; then
        fail "$package: 'swift package describe --type json' produced nothing"
        continue
    fi

    # Dependencies: every one must be a local path inside this repository's Packages/.
    remote=$(print -r -- "$describe" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
bad = [d for d in doc.get("dependencies", []) if d.get("type") != "fileSystem"]
for d in bad:
    print(d.get("identity", "?"), d.get("type", "?"), d.get("url", d.get("path", "")))
')
    if [[ -n "$remote" ]]; then
        fail "$package declares a non-local dependency (zero third-party code is a product tenet):"
        print -u2 "$remote"
    fi

    outside=$(print -r -- "$describe" | python3 -c '
import json, os, sys
root = os.path.abspath(sys.argv[1])
doc = json.load(sys.stdin)
for d in doc.get("dependencies", []):
    path = os.path.abspath(d.get("path", ""))
    if not path.startswith(os.path.join(root, "Packages") + os.sep):
        print(d.get("identity", "?"), path)
' "$REPO_ROOT")
    if [[ -n "$outside" ]]; then
        fail "$package depends on a package outside Packages/:"
        print -u2 "$outside"
    fi

    declared=$(print -r -- "$describe" | python3 -c '
import json, sys
name = sys.argv[1]
doc = json.load(sys.stdin)
for t in doc.get("targets", []):
    if t.get("name") == name:
        print(" ".join(sorted(t.get("product_dependencies") or [])))
        break
else:
    print("<no such target>")
' "$package")

    permitted=$(print -r -- "${ALLOWED_PRODUCTS[$package]}" | tr ' ' '\n' | sort | tr '\n' ' ')
    permitted="${permitted%% }"
    permitted="${permitted## }"
    declared="${declared%% }"
    declared="${declared## }"

    printf '%-16s %-28s %s\n' "$package" "${permitted:-<none>}" "${declared:-<none>}"

    if [[ "$declared" != "$permitted" ]]; then
        fail "$package: product dependencies are '$declared' but the matrix permits exactly '$permitted'"
    fi

    # Source-level imports.
    forbidden_hits=""
    for module in ${=FORBIDDEN_IMPORTS[$package]}; do
        hits=$(grep -rnE "^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)?(public[[:space:]]+|internal[[:space:]]+|@_exported[[:space:]]+)?import[[:space:]]+${module}([[:space:]]|$|\.)" \
            "$dir/Sources" 2>/dev/null)
        if [[ -n "$hits" ]]; then
            forbidden_hits+="$hits"$'\n'
            fail "$package imports $module, which the matrix forbids"
        fi
    done
    if [[ -n "$forbidden_hits" ]]; then
        print -u2 "$forbidden_hits"
    fi

    # The positive half: everything this package actually imports must be named by its row.
    # `import Carbon.HIToolbox` is kept whole rather than truncated at the dot, because
    # `Carbon` and `Carbon.HIToolbox` are exactly the distinction R-13 turns on.
    #
    # Scoped to `Sources/<package>` — the package's own shipping target — rather than to the
    # whole of `Sources/`. e04 puts two TEST-LANE targets beside FocusClassify's
    # (`FocusEvaluateCore` and `FocusEvaluate`, R-75), and a row that had to name them would be
    # a row that no longer says what the SHIPPING library may import. R-70j pins that row to a
    # literal precisely so it cannot be widened; widening it to accommodate a target the
    # application does not link would be the same edit by another route. The test-lane targets
    # get their own scan below, and the forbidden-import half above still searches all of
    # `Sources/` — so nothing in this package may import AppKit, SwiftUI or networking wherever
    # it lives.
    imported=$(grep -rhE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)?(public[[:space:]]+|internal[[:space:]]+|@_exported[[:space:]]+)?import[[:space:]]+[A-Za-z_]' \
        "$dir/Sources/$package" --include='*.swift' 2>/dev/null \
        | sed -E 's/.*import[[:space:]]+//; s/[[:space:]].*//' | sort -u)

    # A package's own targets are inside the boundary its row draws, so a sibling target in
    # the same package is permitted the way `$package` itself always was. Read from `describe`
    # rather than assumed: for the six packages that carry one shipping target this is exactly
    # the old `"$package"` and nothing changes; for `FocusEvaluate`, whose executable imports
    # the `FocusEvaluateCore` library beside it, it is what makes the row checkable at all.
    own_targets=$(print -r -- "$describe" | python3 -c '
import json, sys
print(" ".join(t.get("name", "") for t in json.load(sys.stdin).get("targets", [])))
')
    permitted_modules=(${=ALLOWED_FRAMEWORKS[$package]} ${=ALLOWED_PRODUCTS[$package]} ${=own_targets})
    unlisted=()
    for module in ${(f)imported}; do
        [[ -z "$module" ]] && continue
        (( ${permitted_modules[(Ie)$module]} )) || unlisted+=("$module")
    done

    printf '%-16s %-28s %s\n' "  frameworks" "${ALLOWED_FRAMEWORKS[$package]}" "$(print -r -- ${(j:, :)${(f)imported}})"

    if (( ${#unlisted} )); then
        fail "$package imports ${(j:, :)unlisted}, which the R-14 matrix does not permit"
        print -u2 "    Add the framework to ALLOWED_FRAMEWORKS[$package] deliberately, or remove the import."
    fi
done

# --- FocusClassify: zero networking, twice over -----------------------------------------

print
print "== FocusClassify zero-networking"

classify_source_hits=$(grep -rnE "$NETWORK_SYMBOL_PATTERN" Packages/FocusClassify/Sources 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|///|\*)')
if [[ -n "$classify_source_hits" ]]; then
    fail "FocusClassify sources name a networking API:"
    print -u2 "$classify_source_hits"
else
    print "source: no networking API named"
fi

# **Both configurations, and a control** (focus-gtr).
#
# It read the Debug object alone. The artefact this programme ships is the Release one, and a
# whole-module-optimised object is not the same object — the guarantee that matters is the one
# about what shipped.
#
# And an absence check over an undefined-symbol table is satisfied by a table with nothing in it:
# an object that failed to emit, or whose sources moved to another module, lists no networking
# symbol for the same reason a clean one does. So the object must still be seen doing its job.
# P-120 measured exactly what that looks like here: `FocusClassify.o` names seven NaturalLanguage
# symbols and zero networking ones, and importing NaturalLanguage costs the zero-networking
# guarantee nothing at all. The seven are the control.
CLASSIFY_CONTROL_PATTERN='NLEmbedding|NLTagger|NLLanguageRecognizer'

check_classify_object() {
    local config="$1"
    local object="$DERIVED_DATA/Build/Products/$config/FocusClassify.o"
    if [[ ! -f "$object" ]]; then
        if [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
            # After a build there is no excuse for the object to be missing, and a silent skip
            # here would quietly retire the strongest form of the guarantee.
            fail "FOCUS_REQUIRE_BINARY_CHECK=1 but there is no build product at $object"
        else
            # Before a build the object does not exist yet. Say so plainly rather than reporting
            # a pass — the gate runs this script a second time after building, with
            # FOCUS_REQUIRE_BINARY_CHECK=1, and that run is the one that proves it.
            print "binary: SKIPPED — no build product at $object (the gate re-runs this after the build)"
        fi
        return
    fi

    local symbols undefined control
    symbols=$(nm -u "$object" 2>/dev/null)
    undefined=$(print -r -- "$symbols" \
        | grep -E 'nw_|CFNetwork|URLSession|CFURLConnection|SecureTransport')
    if [[ -n "$undefined" ]]; then
        fail "$config FocusClassify.o has undefined networking symbols:"
        print -u2 "$undefined"
    else
        print "binary: nm -u $object — 0 networking symbols"
    fi

    control=$(print -r -- "$symbols" | grep -cE "$CLASSIFY_CONTROL_PATTERN")
    if (( control > 0 )); then
        print "binary: control — $config FocusClassify.o still names $control NaturalLanguage symbol(s)"
    else
        fail "$config FocusClassify.o names no NaturalLanguage symbol at all"
        print -u2 "    The engine compiles into this object and reaches NLEmbedding and NLTagger."
        print -u2 "    An object that names neither is not the engine, so '0 networking symbols'"
        print -u2 "    is true of something other than the thing under test (P-120)."
    fi
}

for config in Debug Release; do
    check_classify_object "$config"
done

# --- FocusClassify probes no privacy boundary, proven on the object (e04 R-70i) -----------
#
# The adversarial private-browsing fixtures assert that an absent origin yields `uncertain`
# and that the engine makes no attempt to obtain one another way. A test can only observe
# that it did not; the symbol table proves it COULD not. `CGWindowListCopyWindowInfo`,
# the AXUIElement family and the ScreenCaptureKit stream classes all leave undefined symbols
# in an object that references them, and none of them may appear in this one.
#
# Note also what this stage does NOT need to check. P-120 measured an object that imports
# NaturalLanguage and calls NLEmbedding.distance and NLTagger.enumerateTags: its undefined
# symbols are seven NL names and nothing else — zero matches for nw_, CFNetwork, URLSession,
# CFURLConnection, SecureTransport or socket. Importing NaturalLanguage costs the
# zero-networking guarantee nothing at all.
print
print "== FocusClassify probes no privacy boundary"

PRIVACY_SYMBOL_PATTERN='CGWindowList|kCGWindow|AXUIElement|AXIsProcess|SCStream|SCShareableContent|CGDisplayStream|CGRequestScreenCapture|CGPreflightScreenCapture'

# **This block carries its own control** (focus-bkf). It did not: an absence over an empty symbol
# table is green, and the only thing standing between this reading and that was the NaturalLanguage
# control asserted about the same object *earlier in the run*, in a different block, under a
# different flag. A control that belongs to another assertion is a control this one does not have —
# delete the block above and this one goes on printing "0 window-list/AX/capture symbols" for an
# object that failed to emit. So the same seven symbols are asserted present here, per
# configuration, in the same breath as the absence they qualify.
for config in Debug Release; do
    classify_object="$DERIVED_DATA/Build/Products/$config/FocusClassify.o"
    if [[ -f "$classify_object" ]]; then
        classify_symbols=$(nm -u "$classify_object" 2>/dev/null)
        probing=$(print -r -- "$classify_symbols" | grep -E "$PRIVACY_SYMBOL_PATTERN")
        if [[ -n "$probing" ]]; then
            fail "$config FocusClassify.o names a window-list, Accessibility or capture symbol:"
            print -u2 "$probing"
        else
            print "binary: nm -u $classify_object — 0 window-list/AX/capture symbols"
        fi
        privacy_control=$(print -r -- "$classify_symbols" | grep -cE "$CLASSIFY_CONTROL_PATTERN")
        if (( privacy_control > 0 )); then
            print "binary: control — $config FocusClassify.o still names $privacy_control NaturalLanguage symbol(s)"
        else
            fail "$config FocusClassify.o names no NaturalLanguage symbol at all"
            print -u2 "    The engine compiles into this object. An object that names none of its"
            print -u2 "    symbols cannot certify that it probes no privacy boundary — the absence"
            print -u2 "    above would be true of an object with nothing in it (P-120)."
        fi
    elif [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
        fail "FOCUS_REQUIRE_BINARY_CHECK=1 but there is no build product at $classify_object"
    else
        print "binary: SKIPPED — no build product (the gate re-runs this after the build)"
    fi
done

# --- e05 R-96k: the nudge module reaches for no sensing API, proven on the object ----------
#
# The suppression stack consumes SensitivityGate, PresentationState, MediaActivity and
# IdleReading as VALUES produced by e03. A test can observe that it did not go and fetch
# them itself; the symbol table proves it COULD not. AXUIElement*,
# CGWindowListCopyWindowInfo, the ScreenCaptureKit stream classes and every networking
# symbol must be absent from `nm -u` over the built nudge object — the same instrument
# R-70i applied to FocusClassify, aimed at the module that decides whether to speak.
#
# ## Which object, and why it is named rather than globbed
#
# The module that decides whether to speak is `FocusCore/Nudge/` — the eligibility gates, the
# suppression stack, the ladder, the budget, the decider. It compiles into **FocusCore.o**,
# and that object is named here by path for exactly the reason `check-forbidden.sh` names its
# five: a glob plus an "at least one object was seen" counter is not the claim "the nudge
# object is clean". FocusCore is also the strongest possible object to aim this at — it is the
# package the R-14 matrix already forbids AppKit, SwiftUI and every sibling, so a sensing
# symbol appearing in it would mean two guarantees had failed at once.
#
# The nudge's **surfaces** are FocusUI's and are deliberately not asserted here: a panel needs
# AppKit and a menu bar needs a status item, and pretending otherwise would be a lint nobody
# could keep. What they must not do is *decide*, and R-96a/b/c/m are what hold that.
#
# The source half runs first and needs no build product, so a violation is caught in the inner
# loop rather than only after a full build.
print
print "== the nudge module reaches for no sensing API"

NUDGE_SOURCE_DIR="Packages/FocusCore/Sources/FocusCore/Nudge"
# The control for this object, in the shape `FocusClassify.o`'s is: the nudge module's own router
# is a defined symbol in it, so an object that has stopped containing the nudge cannot certify
# that the nudge reaches no sensing API. Named rather than counted — `SurfaceRouter` is the one
# type in this module every rung and every question goes through.
NUDGE_CONTROL_PATTERN='SurfaceRouter'

if [[ -d "$NUDGE_SOURCE_DIR" ]]; then
    nudge_source_hits=$(grep -rnE "$PRIVACY_SYMBOL_PATTERN|$NETWORK_SYMBOL_PATTERN" \
        "$NUDGE_SOURCE_DIR" --include='*.swift' 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|///|\*)')
    if [[ -n "$nudge_source_hits" ]]; then
        fail "a nudge source names a window-list, Accessibility, capture or networking API:"
        print -u2 "$nudge_source_hits"
    else
        print "source: $NUDGE_SOURCE_DIR names no sensing or networking API"
    fi
else
    fail "the nudge module has no source directory at $NUDGE_SOURCE_DIR"
fi

for config in Debug Release; do
    nudge_object="$DERIVED_DATA/Build/Products/$config/FocusCore.o"
    if [[ ! -f "$nudge_object" ]]; then
        if [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
            fail "FOCUS_REQUIRE_BINARY_CHECK=1 but there is no build product at $nudge_object"
        else
            print "binary: SKIPPED — no build product (the gate re-runs this after the build)"
        fi
        continue
    fi
    nudge_probing=$(nm -u "$nudge_object" 2>/dev/null \
        | grep -E "$PRIVACY_SYMBOL_PATTERN|nw_|CFNetwork|URLSession|CFURLConnection|SecureTransport")
    if [[ -n "$nudge_probing" ]]; then
        fail "the $config nudge object names a sensing or networking symbol:"
        print -u2 "$nudge_probing"
    else
        print "binary: nm -u $nudge_object — 0 window-list/AX/capture/networking symbols"
    fi
    nudge_control=$(nm "$nudge_object" 2>/dev/null | grep -c "$NUDGE_CONTROL_PATTERN")
    if (( nudge_control > 0 )); then
        print "binary: control — $config FocusCore.o still carries $nudge_control SurfaceRouter symbol(s)"
    else
        fail "$config FocusCore.o carries no SurfaceRouter symbol at all"
        print -u2 "    The nudge module compiles into this object. An object that no longer"
        print -u2 "    contains it cannot certify that the nudge reaches no sensing API — the"
        print -u2 "    absence above would be true of an object with nothing in it."
    fi
done

# --- e04 R-70j: the FocusClassify framework row is asserted UNCHANGED ----------------------
#
# The positive half of the matrix above already fails the gate on any framework a row does not
# name, so a drive-by `import CoreGraphics` in the engine is caught by machinery that already
# exists. What that machinery cannot catch is the row itself being widened — which is the edit
# somebody would make *in order to* add the import. e04 adds an engine to this package and
# needs exactly the frameworks e01 gave it, so the row is pinned to a literal here and a change
# to it becomes a deliberate, reviewed act rather than a quiet one (P-120).
print
print "== the FocusClassify framework row is unchanged from e01"
EXPECTED_CLASSIFY_FRAMEWORKS="Foundation NaturalLanguage os"
if [[ "${ALLOWED_FRAMEWORKS[FocusClassify]}" == "$EXPECTED_CLASSIFY_FRAMEWORKS" ]]; then
    print "ok   FocusClassify may import exactly: $EXPECTED_CLASSIFY_FRAMEWORKS"
else
    fail "the FocusClassify framework row has changed"
    print -u2 "    expected: $EXPECTED_CLASSIFY_FRAMEWORKS"
    print -u2 "    found:    ${ALLOWED_FRAMEWORKS[FocusClassify]}"
    print -u2 "    e04 adds an engine to this package and needs no new framework (R-70j, P-120)."
fi

# --- and the row is a fact about the BUILT OBJECT, not about this file (focus-bkf) ---------
#
# The comparison above reads one constant in this script against another constant in this script.
# It is worth keeping — it names the row and says why it is pinned — but nothing a product, a
# report or a log can do makes it fail, so on its own it is a restatement rather than coverage.
#
# What the object itself says: a Swift module that imports a framework emits
# `__swift_FORCE_LOAD_$_swift<Framework>` as an undefined symbol, so `nm -u` over
# `FocusClassify.o` names the overlay closure the engine actually links. Two readings, per
# configuration:
#
#   1. the closure is the committed one, both directions — an `import CoreGraphics` in the engine
#      adds a name here whatever the row says, and losing NaturalLanguage removes one;
#   2. every framework the ROW permits is one the object demonstrably links — which is what makes
#      widening the row red rather than quiet, because the widened row is then a promise about a
#      product that does not keep it.
#
# `os` is the documented exception to (2) and is spelled out rather than glossed: it is a clang
# module, `Logger` is inlined into the caller, and no overlay symbol is emitted for it.
EXPECTED_CLASSIFY_OVERLAYS='CoreFoundation Dispatch Foundation IOKit NaturalLanguage ObjectiveC XPC _Builtin_float'
CLASSIFY_FRAMEWORKS_WITHOUT_OVERLAY='os'

for config in Debug Release; do
    classify_object="$DERIVED_DATA/Build/Products/$config/FocusClassify.o"
    if [[ ! -f "$classify_object" ]]; then
        if [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
            fail "FOCUS_REQUIRE_BINARY_CHECK=1 but there is no build product at $classify_object"
        else
            print "binary: SKIPPED — no build product (the gate re-runs this after the build)"
        fi
        continue
    fi
    classify_overlays=$(nm -u "$classify_object" 2>/dev/null \
        | sed -n 's/^__swift_FORCE_LOAD_\$_swift//p' | LC_ALL=C sort -u | tr '\n' ' ')
    classify_overlays="${classify_overlays% }"
    if [[ "$classify_overlays" == "$EXPECTED_CLASSIFY_OVERLAYS" ]]; then
        print "binary: $config FocusClassify.o links exactly: $classify_overlays"
    else
        fail "the $config FocusClassify.o framework closure has changed"
        print -u2 "    expected: $EXPECTED_CLASSIFY_OVERLAYS"
        print -u2 "    found:    $classify_overlays"
        print -u2 "    A framework appearing here is an import the row above did not authorise;"
        print -u2 "    one disappearing means the object under test is no longer the engine."
    fi
    for framework in ${=ALLOWED_FRAMEWORKS[FocusClassify]}; do
        if [[ " $classify_overlays " == *" $framework "* ]]; then
            print "binary: control — the row's $framework is linked by $config FocusClassify.o"
        elif [[ " $CLASSIFY_FRAMEWORKS_WITHOUT_OVERLAY " == *" $framework "* ]]; then
            print "note   the row's $framework has no Swift overlay symbol and is not read here"
        else
            fail "the row permits $framework, which $config FocusClassify.o does not link"
            print -u2 "    A row widened to admit a framework the engine does not use is a"
            print -u2 "    permission granted in advance of the import that needs it (R-70j)."
        fi
    done
done

# --- e04 R-75/T103a: FocusEvaluate is a TEST-LANE product and is not in the shipping graph --
#
# R-75 moves the evaluation harness out of the test target, because a report emitted as a side
# effect of a test run is a report whose existence depends on a test having been scheduled — and
# because `xcodebuild` does not carry an environment value into a SwiftPM test target's process,
# so `$FOCUS_EVAL_OUT` and `$FOCUS_GATE_RUN_ID` can only reach the harness through a plain
# process. That buys the gate a real product and costs the shipping graph nothing, PROVIDED
# nothing in the application ever links it.
#
# "Provided" is the word this stage exists to remove. Three reads, in the three places a link
# could be introduced: the application's own sources, the project file that describes what the
# app links, and the classification package's target graph.
print
print "== FocusEvaluate is a test-lane product only"

EVALUATE_TARGETS='FocusEvaluate|FocusEvaluateCore'

app_evaluate_hits=$(grep -rnE "$EVALUATE_TARGETS" App --include='*.swift' 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|///|\*)')
if [[ -n "$app_evaluate_hits" ]]; then
    fail "an application source names an evaluation target:"
    print -u2 "$app_evaluate_hits"
else
    print "source: App/ names neither FocusEvaluate nor FocusEvaluateCore"
fi

project_evaluate_hits=$(grep -nE "$EVALUATE_TARGETS" FocusSentinel.xcodeproj/project.pbxproj 2>/dev/null)
if [[ -n "$project_evaluate_hits" ]]; then
    fail "the project file references an evaluation target — the app would link it:"
    print -u2 "$project_evaluate_hits"
else
    print "project: FocusSentinel.xcodeproj links neither"
fi

# And the shipping library must not reach sideways into the test-lane one. The dependency runs
# the other way round by construction — FocusEvaluateCore depends on FocusClassify — and this
# is what stops somebody inverting it to reuse the corpus loader from the engine.
classify_evaluate_hits=$(grep -rnE "^[[:space:]]*import[[:space:]]+($EVALUATE_TARGETS)" \
    Packages/FocusClassify/Sources/FocusClassify 2>/dev/null)
if [[ -n "$classify_evaluate_hits" ]]; then
    fail "FocusClassify imports its own test-lane library:"
    print -u2 "$classify_evaluate_hits"
else
    print "graph:   FocusClassify does not import FocusEvaluateCore"
fi

# The test-lane targets get the same positive treatment the shipping rows do — a closed list of
# what they may import — so "it is only the harness" never becomes a place a framework can be
# added without review. They may reach the engine and the two packages beneath it, and nothing
# else: no AppKit, no SwiftUI, no networking, and no sideways reach into Sensing or UI (which
# the forbidden-import half above already enforces across all of Sources/).
EVALUATE_ALLOWED_MODULES=(Foundation FocusCore FocusRules FocusClassify FocusEvaluateCore)
evaluate_imported=$(grep -rhE '^[[:space:]]*import[[:space:]]+[A-Za-z_]' \
    Packages/FocusEvaluate/Sources/FocusEvaluateCore \
    Packages/FocusEvaluate/Sources/FocusEvaluate --include='*.swift' 2>/dev/null \
    | sed -E 's/.*import[[:space:]]+//; s/[[:space:]].*//' | sort -u)
evaluate_unlisted=()
for module in ${(f)evaluate_imported}; do
    [[ -z "$module" ]] && continue
    (( ${EVALUATE_ALLOWED_MODULES[(Ie)$module]} )) || evaluate_unlisted+=("$module")
done
if (( ${#evaluate_unlisted} )); then
    fail "the evaluation targets import ${(j:, :)evaluate_unlisted}, which is not permitted"
else
    print "imports: the evaluation targets import only ${EVALUATE_ALLOWED_MODULES[*]}"
fi

# --- every package: no networking symbols anywhere in the shipping graph ----------------

print
print "== networking APIs across all package sources"
all_hits=$(grep -rnE "$NETWORK_SYMBOL_PATTERN" Packages/*/Sources 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|///|\*)')
if [[ -n "$all_hits" ]]; then
    fail "a package source names a networking API:"
    print -u2 "$all_hits"
else
    print "none"
fi

print
if (( rc == 0 )); then
    print "BOUNDARIES OK"
else
    print -u2 "BOUNDARIES FAILED"
fi
exit $rc
