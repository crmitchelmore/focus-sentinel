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
#                  FocusCore
#   FocusUI        SwiftUI, AppKit, Observation, QuickLook,     SwiftData, networking, Sensing, Classify, Rules
#                  UniformTypeIdentifiers, FocusCore
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
ALLOWED_PRODUCTS[FocusSensing]="FocusCore"
ALLOWED_PRODUCTS[FocusUI]="FocusCore"

typeset -A FORBIDDEN_IMPORTS
FORBIDDEN_IMPORTS[FocusCore]="AppKit SwiftUI Cocoa Network CFNetwork NetworkExtension FocusRules FocusClassify FocusSensing FocusUI"
FORBIDDEN_IMPORTS[FocusRules]="AppKit SwiftUI Cocoa Network CFNetwork NetworkExtension FocusClassify FocusSensing FocusUI"
FORBIDDEN_IMPORTS[FocusClassify]="AppKit SwiftUI Cocoa Network CFNetwork NetworkExtension FocusSensing FocusUI"
FORBIDDEN_IMPORTS[FocusSensing]="SwiftUI Network CFNetwork NetworkExtension FocusClassify FocusRules FocusUI"
# SwiftData is on FocusUI's forbidden list from e02, and it is the enforcement point for R-24:
# the cockpit renders a `CockpitState` value and calls a `PriorityActing` protocol, both
# declared in `FocusCore`, and `App/PriorityHost.swift` is the only type that opens a store.
# That is what keeps every surface in this package snapshot-testable with no container.
FORBIDDEN_IMPORTS[FocusUI]="SwiftData Network CFNetwork NetworkExtension FocusSensing FocusClassify FocusRules"

# The positive half of the matrix: every platform framework each package is permitted to
# import. Sibling packages are handled by ALLOWED_PRODUCTS above and are added to this set per
# package below, so a row here names frameworks only.
typeset -A ALLOWED_FRAMEWORKS
ALLOWED_FRAMEWORKS[FocusCore]="Foundation SwiftData os"
ALLOWED_FRAMEWORKS[FocusRules]="Foundation SwiftData os"
ALLOWED_FRAMEWORKS[FocusClassify]="Foundation NaturalLanguage os"
ALLOWED_FRAMEWORKS[FocusSensing]="Foundation AppKit CoreGraphics IOKit Carbon.HIToolbox CoreAudio CoreMediaIO os"
ALLOWED_FRAMEWORKS[FocusUI]="Foundation SwiftUI AppKit Observation QuickLook UniformTypeIdentifiers os"

PACKAGES=(FocusCore FocusRules FocusClassify FocusSensing FocusUI)

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
    imported=$(grep -rhE '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)?(public[[:space:]]+|internal[[:space:]]+|@_exported[[:space:]]+)?import[[:space:]]+[A-Za-z_]' \
        "$dir/Sources" --include='*.swift' 2>/dev/null \
        | sed -E 's/.*import[[:space:]]+//; s/[[:space:]].*//' | sort -u)

    permitted_modules=(${=ALLOWED_FRAMEWORKS[$package]} ${=ALLOWED_PRODUCTS[$package]} "$package")
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

CLASSIFY_OBJECT="$DERIVED_DATA/Build/Products/Debug/FocusClassify.o"
if [[ -f "$CLASSIFY_OBJECT" ]]; then
    undefined=$(nm -u "$CLASSIFY_OBJECT" 2>/dev/null \
        | grep -E 'nw_|CFNetwork|URLSession|CFURLConnection|SecureTransport')
    if [[ -n "$undefined" ]]; then
        fail "FocusClassify.o has undefined networking symbols:"
        print -u2 "$undefined"
    else
        print "binary: nm -u $CLASSIFY_OBJECT — 0 networking symbols"
    fi
elif [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
    # After a build there is no excuse for the object to be missing, and a silent skip here
    # would quietly retire the strongest form of the guarantee.
    fail "FOCUS_REQUIRE_BINARY_CHECK=1 but there is no build product at $CLASSIFY_OBJECT"
else
    # Before a build the object does not exist yet. Say so plainly rather than reporting a
    # pass — the gate runs this script a second time after building, with
    # FOCUS_REQUIRE_BINARY_CHECK=1, and that run is the one that proves it.
    print "binary: SKIPPED — no build product at $CLASSIFY_OBJECT (the gate re-runs this after the build)"
fi

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

if [[ -f "$CLASSIFY_OBJECT" ]]; then
    probing=$(nm -u "$CLASSIFY_OBJECT" 2>/dev/null | grep -E "$PRIVACY_SYMBOL_PATTERN")
    if [[ -n "$probing" ]]; then
        fail "FocusClassify.o names a window-list, Accessibility or capture symbol:"
        print -u2 "$probing"
    else
        print "binary: nm -u $CLASSIFY_OBJECT — 0 window-list/AX/capture symbols"
    fi
elif [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
    fail "FOCUS_REQUIRE_BINARY_CHECK=1 but there is no build product at $CLASSIFY_OBJECT"
else
    print "binary: SKIPPED — no build product (the gate re-runs this after the build)"
fi

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
