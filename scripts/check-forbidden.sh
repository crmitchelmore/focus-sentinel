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
#   SC-2  No Apple Events, no ScriptingBridge, no NSAppleScript in v1 — and, from e02, no
#         bare `import Carbon` either, because it pulls in Carbon.AppleEvents. The one
#         narrow exemption is `Carbon.HIToolbox` in a single named file; see below.
#   SC-8  No private APIs. `CGVirtualDisplay`, MediaRemote and the DoNotDisturb plist are
#         named exclusions.
#   R-05  Every `ModelContainer` is constructed through the migration plan. The plan-less
#         initialiser is forbidden so that no later epic can open the store by a route that
#         skips migration.
#   R-18  `@Attribute(.unique)` appears only on `ActivePriority.slot` and on `id` fields.
#         Measured (e02 P-44): SwiftData resolves a unique collision by merging whole rows,
#         so the losing row is *deleted*. On `PriorityTask` that would silently destroy the
#         user's previous priority — every word, context item and rule of it — on every
#         swap. The invariant therefore lives on a pointer row, where a collision can only
#         ever cost a pointer.
#   R-19  `ModelContext.undoManager` is never assigned. Measured (e02 P-48): a group that
#         deletes the old active-priority pointer and inserts a new one undoes only the
#         insert, leaving *no* active priority rather than the previous one; and undoing an
#         insert whose row had been constraint-merged crashed the process. Undo ships as the
#         domain-level journal in `PriorityStore` instead.
#   R-22  `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` are
#         called from exactly one file, so that every start is paired with a `defer`red stop
#         in code that can be read in one sitting.
#   R-26  No bare `Date()` outside `FocusCore/Time/DateProvider.swift`, and no
#         `Calendar.current` / `TimeZone.current` outside `FocusCore/Time/`. Timestamps come
#         from an injected `DateProvider` and day keys from an injected calendar; that is
#         what makes the ritual, the timebox and the history ordering deterministic instead
#         of a function of the runner's clock and timezone.
#
# ## The Carbon.HIToolbox exemption, and why it is one file rather than one package
#
# e01's SC-2 pattern was `import[[:space:]]+Carbon`, which also banned `import
# Carbon.HIToolbox` — the API the Feasibility Court *selected* for the global hot key (F-06),
# precisely because `RegisterEventHotKey` is public and needs no TCC grant, where
# `NSEvent.addGlobalMonitor` would have bought an Accessibility prompt for no gain. Standing
# condition 2 is about Apple Events and ScriptingBridge, not about the HIToolbox event
# manager, so the lint was what was wrong, not the condition (e02 R-13, probes P-53…P-56).
#
# The exemption is therefore narrowed to one named file and made self-limiting:
#
#   * `Carbon.HIToolbox` in `$CARBON_ALLOWED_FILE` is permitted;
#   * the same import in any *other* file fails, including a second file in the same package
#     (a blanket package exemption would make the next Carbon import invisible);
#   * and the exemption fails if that file stops existing or stops importing it, so it
#     cannot outlive the reason it was granted.
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

# The single file permitted to reach the HIToolbox event manager (R-13).
CARBON_ALLOWED_FILE="Packages/FocusSensing/Sources/FocusSensing/HotKey/CarbonHotKeyRegistrar.swift"

# The single file permitted to open a security scope (R-22).
BOOKMARK_ALLOWED_FILE="Packages/FocusCore/Sources/FocusCore/Context/SecurityScopedBookmark.swift"

# The one sanctioned wall clock (R-26).
DATE_ALLOWED_FILE="Packages/FocusCore/Sources/FocusCore/Time/DateProvider.swift"

# The one directory permitted to read the current calendar or timezone (R-26).
CALENDAR_ALLOWED_DIR="Packages/FocusCore/Sources/FocusCore/Time/"

# The declaration that carries the single-active-priority invariant (R-18).
UNIQUE_SLOT_FILE="Packages/FocusCore/Sources/FocusCore/Store/FocusSchemaV2.swift"

# Strip comment-only lines from grep output of the form path:line:text.
strip_comments() {
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|///|\*|/\*)'
}

# check <condition> <description> <pattern> [exempt-path-prefix]
#
# The optional fourth argument names a path prefix whose hits are not violations — the one
# file or directory where the symbol is the sanctioned implementation rather than a misuse.
# It is a prefix of the `path:line:` form grep prints, so naming a file exempts that file and
# naming a directory (with its trailing slash) exempts everything beneath it.
check() {
    local condition="$1"
    local description="$2"
    local pattern="$3"
    local exempt="${4:-}"

    local hits
    hits=$(grep -rnE "$pattern" "${SEARCH_PATHS[@]}" \
        --include='*.swift' --include='*.entitlements' --include='*.plist' \
        2>/dev/null | strip_comments)

    if [[ -n "$exempt" && -n "$hits" ]]; then
        hits=$(print -r -- "$hits" | grep -vE "^${exempt}")
    fi

    if [[ -n "$hits" ]]; then
        print -u2 "FAIL [$condition] $description"
        print -u2 "$hits" | sed 's/^/    /'
        [[ -n "$exempt" ]] && print -u2 "    The only sanctioned location is $exempt"
        rc=1
    else
        if [[ -n "$exempt" ]]; then
            print "ok   [$condition] $description (exempt: $exempt)"
        else
            print "ok   [$condition] $description"
        fi
    fi
}

print "== forbidden symbols (searched: ${SEARCH_PATHS[*]}; excluded: Tools/, scripts/, comments)"

check "SC-1" "kCGWindowName is never used as a title source" \
    'kCGWindowName'

# SC-2 bans Apple Events, ScriptingBridge and AppleScript. It does **not** ban the HIToolbox
# event manager: the Court chose Carbon `RegisterEventHotKey` for F-06 precisely because it is
# public and needs no TCC grant, and the previous pattern — `import[[:space:]]+Carbon` —
# banned the one API the roadmap requires. Bare `import Carbon` stays banned because it pulls
# in Carbon.AppleEvents.
check "SC-2" "no Apple Events, ScriptingBridge or AppleScript" \
    'ScriptingBridge|NSAppleScript|NSAppleEventDescriptor|NSAppleEventManager|AEDesc|AESend|AEBuildAppleEvent|import[[:space:]]+Carbon[[:space:]]*$|import[[:space:]]+Carbon\.AppleEvents'

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

check "R-19" "no ModelContext.undoManager assignment (undo is the PriorityStore journal)" \
    '\.undoManager[[:space:]]*='

check "R-26" "no bare Date() outside DateProvider" \
    '\bDate\(\)' \
    "$DATE_ALLOWED_FILE"

check "R-26" "no Calendar.current or TimeZone.current outside FocusCore/Time" \
    'Calendar\.current|TimeZone\.current' \
    "$CALENDAR_ALLOWED_DIR"

check "R-22" "startAccessingSecurityScopedResource only in SecurityScopedBookmark.swift" \
    'startAccessingSecurityScopedResource|stopAccessingSecurityScopedResource' \
    "$BOOKMARK_ALLOWED_FILE"

# --- Carbon.HIToolbox: allowed in exactly one file, and only while that file needs it -----

print
print "== Carbon.HIToolbox is allowed in exactly one file"
carbon_hits=$(grep -rln 'import[[:space:]]\+Carbon\.HIToolbox' "${SEARCH_PATHS[@]}" --include='*.swift' 2>/dev/null)
carbon_unexpected=$(print -r -- "$carbon_hits" | grep -v "^${CARBON_ALLOWED_FILE}\$" | grep -v '^$')
if [[ -n "$carbon_unexpected" ]]; then
    print -u2 "FAIL [SC-2] Carbon.HIToolbox imported outside $CARBON_ALLOWED_FILE:"
    print -u2 "$carbon_unexpected" | sed 's/^/    /'
    print -u2 "    The global hot key is the only sanctioned Carbon use (plan R-13, probe P-55)."
    rc=1
elif ! grep -q 'import[[:space:]]\+Carbon\.HIToolbox' "$CARBON_ALLOWED_FILE" 2>/dev/null; then
    print -u2 "FAIL [SC-2] $CARBON_ALLOWED_FILE no longer imports Carbon.HIToolbox."
    print -u2 "    The allowlist must not outlive the reason for it — remove the exemption."
    rc=1
else
    print "ok   [SC-2] Carbon.HIToolbox appears only in $CARBON_ALLOWED_FILE"
fi

# --- R-18: the unique attribute is a pointer-row invariant, never a task column -----------

print
print "== @Attribute(.unique) placement"
unique_hits=$(grep -rnE '@Attribute\(\.unique\)' "${SEARCH_PATHS[@]}" --include='*.swift' 2>/dev/null \
    | strip_comments)
unique_unexpected=$(print -r -- "$unique_hits" \
    | grep -v '^$' \
    | grep -vE "^${UNIQUE_SLOT_FILE}:[0-9]+:[[:space:]]*@Attribute\(\.unique\)[[:space:]]+(public[[:space:]]+)?var slot: String[[:space:]]*\$" \
    | grep -vE '@Attribute\(\.unique\)[[:space:]]+(public[[:space:]]+)?var id[[:space:]]*:')
if [[ -n "$unique_unexpected" ]]; then
    print -u2 "FAIL [R-18] @Attribute(.unique) outside ActivePriority.slot and id fields:"
    print -u2 "$unique_unexpected" | sed 's/^/    /'
    print -u2 "    A unique collision in SwiftData merges whole rows and deletes the loser"
    print -u2 "    (probe P-44). On a task that destroys the user's words; the invariant"
    print -u2 "    belongs on the ActivePriority pointer row (plan R-18)."
    rc=1
else
    print "ok   [R-18] @Attribute(.unique) only on ActivePriority.slot and id fields"
fi

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
