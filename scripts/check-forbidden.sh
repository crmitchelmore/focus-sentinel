#!/bin/zsh
# Forbidden symbols — the standing conditions, as a lint.
#
# These are conditions the programme is bound by for every epic, not just this one. They are
# installed now, before there is any surface that could violate them, so that the epic which
# first has a surface inherits an enforcing gate rather than a promise in a document.
#
#   SC-1  `kCGWindowName` is banned as a title source anywhere in the codebase. Window
#         titles come from the Accessibility API with the user's consent, never from the
#         window-list key that has been Screen-Recording-gated since 10.15. From e03 this
#         is the one condition whose search set is the WHOLE REPOSITORY rather than the
#         shipping graph, and it has a binary half as well as a source one (R-32).
#   R-33  No API that can raise a TCC prompt appears in the shipping graph at all. e03 is
#         the zero-grant half of sensing: every API it uses was measured prompt-free from
#         an ad-hoc-signed bundle holding no TCC row (P-74, P-84, P-94/P-95, P-97), so the
#         guarantee is made structural rather than behavioural.
#   R-41  `ActivityEvent.detail` may only ever be assigned from a `NormalisedDetail`.
#   R-45  `SessionPhase` and `ResumablePhase` are decoded through their exhaustive
#         `switch`es, never through `init(rawValue:)`.
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
#   **SC-1 is the exception**: from e03 it searches `Tools/` and `scripts/` too, because a
#   title source in a test driver is still a title source in this repository.
# * `scripts/` — this file names every forbidden symbol by definition. SC-1's repo-wide
#   sweep therefore skips **this one file** by name; see `SC1_SELF` below.
# * Comment lines and Markdown. The ban is on *using* a symbol. A comment saying "never use
#   this" is the opposite of a violation, and a lint that cannot tell the difference teaches
#   people to stop writing the comment. SC-1's sweep reaches shell and Python files as well
#   as Swift, so it strips `#` comments too — see `strip_hash_comments`.
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

# The declarations that carry the single-active-priority invariant (R-18).
#
# One per versioned schema, and no others: every schema version that has an `ActivePriority`
# row must keep the constraint on it, and a version that quietly dropped it would be a
# migration target where two priorities could coexist. The pattern is therefore the family of
# schema files rather than one named file — which is what stopped it going stale when v3
# landed and would have made a lint failure the only way to notice.
UNIQUE_SLOT_FILE="Packages/FocusCore/Sources/FocusCore/Store/FocusSchemaV[0-9]+\.swift"

# Where the gate's build products live. Only SC-1's binary half reads this.
DERIVED_DATA="${FOCUS_DERIVED_DATA:-/tmp/focus-dd}"

# Strip comment-only lines from grep output of the form path:line:text.
strip_comments() {
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|///|\*|/\*)'
}

# The same, for `#` comments. Only SC-1 uses it, because only SC-1 searches shell scripts
# and Python. It is deliberately *not* folded into `strip_comments`: every other check
# searches Swift, where a line beginning with `#` is `#if`, `#Predicate` or `#expect` — code,
# not commentary — and blinding those checks to it would be a real hole.
strip_hash_comments() {
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
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
print "   SC-1 alone is searched repository-wide, in source and in the built objects (R-32)"

# SC-1 is the one standing condition whose scope is the WHOLE REPOSITORY rather than the
# shipping graph. `kCGWindowName` has required Screen Recording since 10.15, and at zero
# grants it returns nothing worth having: measured from an ad-hoc-signed bundle launched with
# `open -a`, it was present on 1 of 25 on-screen windows and 2 of 128 with `.optionAll` — and
# both values belonged to Window Server ("Menubar", "Wallpaper-"), not to any application
# (probe P-75). With the grant, the same call returned 34 of 35 names. The key is therefore
# useless without a permission this app will never request and forbidden with it.
#
# Comments and Markdown prose are stripped, as everywhere else in this script: a comment
# saying "never use this" is the opposite of a violation.
#
# ## Why this file is skipped, and only this file
#
# The sweep includes `scripts/`, and this script names the banned symbol in its own grep
# pattern — a line that is code, not a comment, so no amount of comment-stripping removes it.
# A lint that fails on its own definition is a lint nobody can run. The skip is therefore one
# named path rather than a directory, so `scripts/live-shell-drive.sh` and every future lane
# stay in scope. Measured before the widening: the repository's eight `kCGWindowName` hits
# were four in this file, one each in `Packages/FocusSensing/Package.swift`,
# `Tools/windowid/.../main.swift`, `scripts/live-shell-drive.sh` and `README.md` — every one
# of the latter four a comment or Markdown prose (probe P-102).
SC1_SEARCH=(App Packages Tools scripts Config README.md)
SC1_SELF="scripts/check-forbidden.sh"

print
print "== SC-1: kCGWindowName, repository-wide"
sc1_hits=$(grep -rnE 'kCGWindowName' "${SC1_SEARCH[@]}" \
    --exclude-dir='.git' --exclude-dir='.build' --exclude-dir='DerivedData' \
    --exclude-dir='.agents' --exclude-dir='xcuserdata' 2>/dev/null \
    | strip_comments \
    | strip_hash_comments \
    | grep -vE "^${SC1_SELF}:[0-9]+:" \
    | grep -vE '^[^:]+\.md:[0-9]+:')
if [[ -n "$sc1_hits" ]]; then
    print -u2 "FAIL [SC-1] kCGWindowName appears outside a comment:"
    print -u2 "$sc1_hits" | sed 's/^/    /'
    print -u2 "    Window titles come from the Accessibility API with consent (e07), never"
    print -u2 "    from the window-list key (standing condition 1, dissent D-02, probe P-75)."
    rc=1
else
    print "ok   [SC-1] kCGWindowName appears nowhere in the repository outside comments"
fi

print

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

# R-33: this epic must never make the app ask for anything. Every API it uses was measured
# prompt-free from a zero-grant bundle (P-74, P-84, P-94/P-95, P-97), so the guarantee is made
# structural: the asking calls are not in the binary, therefore no code path can reach one.
# `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()` stay permitted — reading trust
# state is not requesting it. `requestAuthorization` is banned graph-wide in e03 and narrows to
# a single named file when e05 ships notification consent, in the same self-limiting shape as
# the Carbon.HIToolbox exemption above.
check "R-33" "no API that can raise a TCC prompt" \
    'AXIsProcessTrustedWithOptions|kAXTrustedCheckOptionPrompt|CGRequestScreenCaptureAccess|SCShareableContent|AVCaptureDevice\.requestAccess|requestAuthorization|requestAccess\(for:|CGRequestPostEventAccess|CGRequestListenEventAccess|IOHIDRequestAccess'

# R-45: `SessionPhase(rawValue:)` would silently turn a legacy "running" row into a phase this
# build does not recognise. Every decode goes through SessionPhase.decode(_:), which carries
# the alias table.
#
# This check has NO allowlist and NO exempted call site, and it does not need one: decode(_:)
# and ResumablePhase.phase are both exhaustive switches over string literals, so the banned
# pattern appears nowhere in the repository — including inside the sanctioned decoder. That is
# deliberate. The totality of the switches is held by tests, not by the compiler:
# SessionMachineTests asserts decode(phase.rawValue) == phase for every case.
check "R-45" "SessionPhase is decoded through decode(_:), never init(rawValue:)" \
    '(SessionPhase|ResumablePhase)\(rawValue:'

# R-41: ActivityEvent.detail may only ever hold a NormalisedDetail.
#
# `NormalisedDetail` has no `String` initialiser, so captured content cannot *become* a
# detail. The route this check closes is the other one: assigning to the model's column
# directly, which is a plain `String?` because that is what a column is.
#
# **This bans the shape, not a list of spellings.** The first form of the check matched a
# literal or one of five property names (`.title`, `.name`, `.url`, `.absoluteString`,
# `.path`), which meant `row.detail = capturedText` and `row.detail = makeDetail()` both
# passed while the green line claimed the property was "only ever assigned a
# NormalisedDetail". A lint that enumerates five spellings of the mistake catches the careless
# and misses everyone else, and an overstated green line is worse than no line at all. So
# every assignment to `.detail` is a violation except one sanctioned form:
#
#     self.detail = detail
#
# a model initialiser forwarding its own parameter — and that parameter reaches it only from
# `ActivityEventStore.append`, whose signature takes a `NormalisedDetail` and whose only
# expression for the column is `detail.storedValue`.
#
# Belt and braces, because a lint is a rule and a type is a fact:
# `FocusSchemaV3.ActivityEvent.detail` is declared `public internal(set)`, so no package
# outside `FocusCore` can perform the assignment this check forbids — it does not compile.
# This check covers what is left, which is `FocusCore` itself.
print
print "== R-41: every assignment to ActivityEvent.detail"
detail_hits=$(grep -rnE '\.detail[[:space:]]*=[^=]' "${SEARCH_PATHS[@]}" \
    --include='*.swift' 2>/dev/null \
    | strip_comments \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*self\.detail[[:space:]]*=[[:space:]]*detail[[:space:]]*$')
if [[ -n "$detail_hits" ]]; then
    print -u2 "FAIL [R-41] ActivityEvent.detail is assigned something that is not a NormalisedDetail:"
    print -u2 "$detail_hits" | sed 's/^/    /'
    print -u2 "    Write through ActivityEventStore.append, whose parameter is a"
    print -u2 "    NormalisedDetail — a closed token vocabulary or a typed measurement, and"
    print -u2 "    nothing a window title, a URL or a document name can be turned into (R-41)."
    rc=1
else
    print "ok   [R-41] ActivityEvent.detail is only ever assigned a NormalisedDetail"
fi

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

# --- SC-1, the binary half ----------------------------------------------------------------
#
# The grep above can be defeated by building the string at runtime. The symbol cannot:
# `kCGWindowName` is an exported CFStringRef, so any reference to it leaves `_kCGWindowName`
# in the object's undefined-symbol table. Measured (P-101): a binary that reads the key lists
# it; Tools/windowid, which reads owner, layer, number and bounds and nothing else, lists
# exactly those four and not the name.
#
# The object list is EXPLICIT, not a glob, and mirrors check-boundaries.sh naming
# FocusClassify.o by path. P-108 measured that the five below are the complete set of package
# objects, identically in Debug and Release. A glob plus an "at least one binary was seen"
# counter is not the claim "every package object is clean": a build that emits four objects,
# or a sixth package whose product is not named Focus*, would slip through it in silence.
# Adding a package therefore fails this gate until its object is named here — which is exactly
# the review moment a new package deserves (R-31).
print
print "== SC-1: the binary half"
SC1_REQUIRED=(
    "$DERIVED_DATA/Build/Products/Debug/FocusSentinel.app/Contents/MacOS/FocusSentinel"
    "$DERIVED_DATA/Build/Products/Debug/FocusCore.o"
    "$DERIVED_DATA/Build/Products/Debug/FocusSensing.o"
    "$DERIVED_DATA/Build/Products/Debug/FocusRules.o"
    "$DERIVED_DATA/Build/Products/Debug/FocusClassify.o"
    "$DERIVED_DATA/Build/Products/Debug/FocusUI.o"
    Tools/windowid/.build/release/windowid
)

sc1_binaries_seen=0
for binary in $SC1_REQUIRED; do
    if [[ ! -f "$binary" ]]; then
        # Under the flag there is no excuse for a build product to be missing, and a silent
        # skip would quietly retire the strongest form of the guarantee for that object.
        if [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
            print -u2 "FAIL [SC-1] FOCUS_REQUIRE_BINARY_CHECK=1 but $binary does not exist"
            rc=1
        else
            print "     [SC-1] $binary not built yet — the gate re-runs this after the build"
        fi
        continue
    fi
    sc1_binaries_seen=$(( sc1_binaries_seen + 1 ))
    if nm -u "$binary" 2>/dev/null | grep -q '^_kCGWindowName$'; then
        print -u2 "FAIL [SC-1] $binary references kCGWindowName at the symbol level"
        rc=1
    else
        print "ok   [SC-1] $binary does not reference kCGWindowName"
    fi
done

# The tool must still do its job. An SC-1 check that passes because windowid was gutted is a
# check that proves nothing.
if [[ -f Tools/windowid/.build/release/windowid ]]; then
    for symbol in _kCGWindowBounds _kCGWindowLayer _kCGWindowNumber _kCGWindowOwnerName; do
        if nm -u Tools/windowid/.build/release/windowid 2>/dev/null | grep -q "^${symbol}\$"; then
            print "ok   [SC-1] windowid still reads $symbol"
        else
            print -u2 "FAIL [SC-1] windowid no longer reads $symbol — the tool has been gutted"
            rc=1
        fi
    done
fi

if (( sc1_binaries_seen == 0 )) && [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" != "1" ]]; then
    print "     [SC-1] binary half SKIPPED — nothing built yet (the gate re-runs this after the build)"
fi

print
if (( rc == 0 )); then
    print "FORBIDDEN-SYMBOL LINT OK"
else
    print -u2 "FORBIDDEN-SYMBOL LINT FAILED"
fi
exit $rc
