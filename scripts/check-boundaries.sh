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
#   FocusRules     Foundation, FocusCore                        AppKit, SwiftUI, networking, Classify/Sensing/UI
#   FocusClassify  Foundation, NaturalLanguage, Core, Rules     ANY networking, AppKit, SwiftUI, Sensing, UI
#   FocusSensing   Foundation, AppKit, CoreGraphics, IOKit,     SwiftUI, networking, Classify, Rules, UI
#                  FocusCore
#   FocusUI        SwiftUI, AppKit, FocusCore                   networking, Sensing, Classify, Rules
#
# Three further assertions:
#
#   * **Zero third-party code.** Every declared package dependency must be a local
#     `fileSystem` path to a sibling inside `Packages/`. A remote dependency — a URL or a
#     registry identity — fails the gate. (A local sibling dependency is how the matrix
#     above is expressed at all: a package cannot `import FocusCore` without one.)
#   * **The matrix is exact.** Each library target's product dependencies must equal the
#     permitted set, not merely be a subset of it.
#   * **FocusClassify cannot reach the network at the binary level.** When a build product
#     exists, `nm -u FocusClassify.o` must contain no networking symbol at all.
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
FORBIDDEN_IMPORTS[FocusUI]="Network CFNetwork NetworkExtension FocusSensing FocusClassify FocusRules"

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
