#!/bin/zsh
# Forbidden symbols — the standing conditions, as a lint.
#
# These are conditions the programme is bound by for every epic, not just this one. They are
# installed now, before there is any surface that could violate them, so that the epic which
# first has a surface inherits an enforcing gate rather than a promise in a document.
#
#   SC-1  `kCGWindowName` is banned as a title source anywhere in the codebase. Window
#         titles come from the Accessibility API with the user's consent, never from the
#         window-list key that has been Screen-Recording-gated since 10.15.
#   SC-2  No Apple Events, no ScriptingBridge, no NSAppleScript in v1.
#   SC-8  No private APIs. `CGVirtualDisplay`, MediaRemote and the DoNotDisturb plist are
#         named exclusions.
#   R-05  Every `ModelContainer` is constructed through the migration plan. The plan-less
#         initialiser is forbidden so that no later epic can open the store by a route that
#         skips migration.
#
# ## What is excluded, and why
#
# * `Tools/` — test drivers, outside the shipping app's package graph. `Tools/windowid`
#   uses `CGWindowListCopyWindowInfo` deliberately, reading owner name, layer, number and
#   bounds only. It never requests `kCGWindowName`, which is what SC-1 actually bans.
# * `scripts/` — this file names every forbidden symbol by definition.
# * Comment lines and Markdown. The ban is on *using* a symbol. A comment saying "never use
#   this" is the opposite of a violation, and a lint that cannot tell the difference teaches
#   people to stop writing the comment.
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

rc=0

SEARCH_PATHS=(App Packages)

# Strip comment-only lines from grep output of the form path:line:text.
strip_comments() {
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|///|\*|/\*)'
}

check() {
    local condition="$1"
    local description="$2"
    local pattern="$3"

    local hits
    hits=$(grep -rnE "$pattern" "${SEARCH_PATHS[@]}" \
        --include='*.swift' --include='*.entitlements' --include='*.plist' \
        2>/dev/null | strip_comments)

    if [[ -n "$hits" ]]; then
        print -u2 "FAIL [$condition] $description"
        print -u2 "$hits" | sed 's/^/    /'
        rc=1
    else
        print "ok   [$condition] $description"
    fi
}

print "== forbidden symbols (searched: ${SEARCH_PATHS[*]}; excluded: Tools/, scripts/, comments)"

check "SC-1" "kCGWindowName is never used as a title source" \
    'kCGWindowName'

check "SC-2" "no Apple Events, ScriptingBridge or NSAppleScript" \
    'ScriptingBridge|NSAppleScript|NSAppleEventDescriptor|NSAppleEventManager|import[[:space:]]+Carbon'

check "SC-2" "no NSAppleEventsUsageDescription is declared" \
    'NSAppleEventsUsageDescription'

check "SC-8" "no CGVirtualDisplay" \
    'CGVirtualDisplay'

check "SC-8" "no MediaRemote" \
    'MediaRemote|MRMediaRemote'

check "SC-8" "no DoNotDisturb plist poking" \
    'com\.apple\.DoNotDisturb|com\.apple\.donotdisturb'

check "SC-8" "no private-framework dlopen" \
    'dlopen\([[:space:]]*"/System/Library/PrivateFrameworks'

# R-05 needs a different shape: it is a call that must *include* something, not a symbol
# that must be absent.
print
print "== every ModelContainer goes through the migration plan"
container_hits=$(grep -rnE 'ModelContainer\(' "${SEARCH_PATHS[@]}" --include='*.swift' 2>/dev/null \
    | strip_comments \
    | grep -v 'migrationPlan:')
if [[ -n "$container_hits" ]]; then
    print -u2 "FAIL [R-05] a ModelContainer is built without a migrationPlan:"
    print -u2 "$container_hits" | sed 's/^/    /'
    print -u2 "    Use FocusStore.makeContainer(kind:) — it is the only sanctioned route."
    rc=1
else
    print "ok   [R-05] no plan-less ModelContainer initialiser"
fi

# The entitlements file is small enough to assert on positively rather than by absence.
print
print "== entitlements source declares no networking key"
entitlement_hits=$(grep -nE 'com\.apple\.security\.network|com\.apple\.developer\.networking|com\.apple\.developer\.icloud|aps-environment' \
    App/FocusSentinel.entitlements 2>/dev/null)
if [[ -n "$entitlement_hits" ]]; then
    print -u2 "FAIL [SC-7] App/FocusSentinel.entitlements declares a networking or iCloud key:"
    print -u2 "$entitlement_hits" | sed 's/^/    /'
    rc=1
else
    print "ok   [SC-7] App/FocusSentinel.entitlements declares no networking or iCloud key"
fi

print
if (( rc == 0 )); then
    print "FORBIDDEN-SYMBOL LINT OK"
else
    print -u2 "FORBIDDEN-SYMBOL LINT FAILED"
fi
exit $rc
