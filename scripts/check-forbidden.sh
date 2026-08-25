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

# check_set <condition> <description> <pattern> <path> [<path>…]
#
# `check` above searches the whole shipping graph and takes an *exempt prefix* as its fourth
# argument. Three of e04's assertions need the other thing — a narrower **search set** — and
# passing one to `check` would be silently catastrophic rather than merely wrong: with
# `exempt="Packages"`, every hit under `Packages/` is filtered out of the result and the check
# prints `ok` however many violations it found. So a search set gets its own helper, and the
# two shapes cannot be confused at a call site.
check_set() {
    local condition="$1"
    local description="$2"
    local pattern="$3"
    shift 3

    local hits
    hits=$(grep -rnE --include='*.swift' --exclude-dir='.build' "$pattern" "$@" 2>/dev/null | strip_comments)

    if [[ -n "$hits" ]]; then
        print -u2 "FAIL [$condition] $description"
        print -u2 "$hits" | sed 's/^/    /'
        rc=1
    else
        print "ok   [$condition] $description (searched: $*)"
    fi
}

# count_files <condition> <description> <fixed-string> <expected-count> <path> [<path>…]
#
# Not "is it absent" but "how many files contain it". The `fileprivate` initialiser already
# makes a second construction site a compile error; this makes the COUNT visible, so moving a
# producer becomes a deliberate, reviewed act rather than a quiet one. The pattern is matched
# as a FIXED string, because the shapes this is used on end in `(`.
count_files() {
    local condition="$1"
    local description="$2"
    local pattern="$3"
    local expected="$4"
    shift 4

    local files count
    files=$(grep -rnF --include='*.swift' --exclude-dir='.build' -- "$pattern" "$@" 2>/dev/null \
        | strip_comments | cut -d: -f1 | sort -u)
    count=$(print -r -- "$files" | grep -c '[^[:space:]]')

    if [[ "$count" != "$expected" ]]; then
        print -u2 "FAIL [$condition] $description — expected $expected file(s), found $count"
        print -u2 "$files" | sed 's/^/    /'
        rc=1
    else
        print "ok   [$condition] $description ($count file)"
    fi
}

# check_outside <condition> <description> <pattern> <search-path> --allow <path> [--allow <path>…]
#
# The same shape as R-41's `.detail` lint: the construction is sanctioned in named places and
# forbidden everywhere else. An allowed path is a prefix of grep's `path:line:` output, so
# naming a directory allows everything beneath it.
check_outside() {
    local condition="$1"
    local description="$2"
    local pattern="$3"
    shift 3

    local -a paths allowed
    while (( $# )); do
        if [[ "$1" == "--allow" ]]; then
            allowed+=("$2")
            shift 2
        else
            paths+=("$1")
            shift
        fi
    done

    local hits
    hits=$(grep -rnE --include='*.swift' --exclude-dir='.build' "$pattern" "${paths[@]}" 2>/dev/null | strip_comments)
    local allow
    for allow in $allowed; do
        [[ -n "$hits" ]] && hits=$(print -r -- "$hits" | grep -vE "^${allow}")
    done

    if [[ -n "$hits" ]]; then
        print -u2 "FAIL [$condition] $description"
        print -u2 "$hits" | sed 's/^/    /'
        print -u2 "    Sanctioned locations: ${allowed[*]}"
        rc=1
    else
        print "ok   [$condition] $description (allowed: ${allowed[*]})"
    fi
}

# check_literals <condition> <description> <path> [<path>…] --except <file> [--except <file>…]
#
# R-70f, and the reason it is a script rather than a grep: a numeric literal has to be found in
# *code*, not in a comment, a doc comment, a string or an identifier such as `FocusSchemaV3`,
# `UInt64` or `BCP47`. Excepted: the literals `0` and `1` anywhere, and any line comparing
# against `count` or `isEmpty` — the two shapes where a small number is arithmetic about a
# collection rather than a threshold about a person.
check_literals() {
    local condition="$1"
    local description="$2"
    shift 2

    local -a paths excepted
    while (( $# )); do
        if [[ "$1" == "--except" ]]; then
            excepted+=("$2")
            shift 2
        else
            paths+=("$1")
            shift
        fi
    done

    local hits
    hits=$(python3 "$REPO_ROOT/scripts/find-numeric-literals.py" \
        --paths "${paths[@]}" --except "${excepted[@]}" 2>&1)
    local literal_rc=$?

    if (( literal_rc != 0 )); then
        print -u2 "FAIL [$condition] $description"
        print -u2 "$hits" | sed 's/^/    /'
        print -u2 "    Every threshold in the engine lives in RelevancePolicy.swift, is named,"
        print -u2 "    is classed B/C/S, is digested and carries a mutation witness (R-59, R-74)."
        rc=1
    else
        print "ok   [$condition] $description (searched: ${paths[*]})"
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
# state is not requesting it.
#
# **`requestAuthorization` has left this pattern, and it has been replaced by something
# stronger, not weaker.** e03 banned it graph-wide and said in this paragraph that it would
# narrow to a single named file when e05 shipped notification consent. That is what R-96g does
# below, and it is a *bound plus an identity*: the call may appear in at most one file and that
# file must be the Intervention settings pane's user-initiated action. A blanket ban here plus a
# narrowed check there would have been the same assertion twice, with the blanket one failing on
# the honest reporting name the self-check publishes — `requestAuthorizationCallCount`, the
# number whose being zero is what §3.F.37 and the `notification-denied` gate stage actually
# assert. A lint that made the app unable to *report* it had never asked would be a lint working
# against the thing it exists to prove.
check "R-33" "no API that can raise a TCC prompt" \
    'AXIsProcessTrustedWithOptions|kAXTrustedCheckOptionPrompt|CGRequestScreenCaptureAccess|SCShareableContent|AVCaptureDevice\.requestAccess|requestAccess\(for:|CGRequestPostEventAccess|CGRequestListenEventAccess|IOHIDRequestAccess'

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

# ---- e04 -------------------------------------------------------------------------------
#
# Nine assertions, landing in Phase B — **before** the engine they constrain exists. That
# ordering is e03's doctrine and it is the whole point: a lint that forbids a shape must exist
# before the shape could be written, or the first green gate proves nothing.

print
print "== e04: the shapes the relevance engine must not take"

# R-70a  `Verdict.permitsIntervention` is DELETED. The Bool was the collapse hazard —
#        `if v.permitsIntervention || confidence > 0.9` compiles and defeats standing
#        condition 6 — so the guarantee moved to a type with no reachable initialiser
#        (`InterventionMandate`) and the member is banned so it cannot come back.
check_set "R-70a" "no permitsIntervention on a Verdict" \
    'Verdict\.permitsIntervention|verdict\.permitsIntervention' \
    App Packages

# R-70b  `InterventionMandate` has a fileprivate memberwise initialiser, so a second
#        construction site is already a compile error. This makes the COUNT visible: moving
#        the producer becomes a deliberate, reviewed act rather than a quiet one.
count_files "R-70b" "InterventionMandate is constructed in exactly one file" \
    'InterventionMandate(' 1 App Packages

# R-70c  `NLEmbedding.wordEmbedding` is banned. Measured (P-112): cross-domain separation of
#        0.017 on code~programming vs code~cooking, and it INVERTS on proposal~invoice (1.2665,
#        both work) vs proposal~game (1.2629, a distraction). A signal that ranks a distraction
#        closer than a colleague is not a signal.
check_set "R-70c" "no NLEmbedding.wordEmbedding" \
    'wordEmbedding' \
    App Packages

# R-70d  `NLContextualEmbedding` is banned outright. It is asset-gated and its surface includes
#        an asset REQUEST. A package whose whole guarantee is that it cannot reach the network
#        may not name a type that can ask for a download (SC-7).
check_set "R-70d" "no NLContextualEmbedding or asset request" \
    'NLContextualEmbedding|requestEmbeddingAssets|hasAvailableAssets' \
    App Packages

# R-70e  No timer in FocusClassify. The drift machine and the transition window are pure
#        reducers on an injected MonotonicClock reading (R-60); that is what makes every
#        sequence fixture an exact assertion rather than a flaky one. A timer inside a
#        replayable reducer is a non-determinism no fixture can catch.
check_set "R-70e" "no timer or sleep in the classification package" \
    'Timer\(|DispatchSourceTimer|Task\.sleep|asyncAfter|RunLoop\.' \
    Packages/FocusClassify/Sources

# R-70f  Every numeric threshold lives in RelevancePolicy.swift and nowhere else. This is what
#        makes "no magic numbers" mechanical instead of a habit. Excepted: 0 and 1, and
#        comparisons against `count`/`isEmpty`.
#
#        A SECOND excepted file, and the reason it is not a weakening. R-75 moves the evaluation
#        harness into `Packages/FocusClassify/Sources/FocusEvaluateCore/` — emission has to be a
#        product rather than a test side effect, and this search path predates that decision by
#        two phases. A percentile rank, a cache-sweep capacity and a corpus floor are all
#        numbers, and none of them is a threshold about a person: they size the evidence, not
#        the judgement. So the harness tree gets exactly the same discipline the engine tree has
#        — ONE file in which a literal may appear, every constant named, doc-commented and
#        traceable to the ruling that fixed it — and `EvaluationPolicy.swift` is that file. The
#        engine's own exception list is untouched, and a threshold cannot be introduced anywhere
#        a reviewer would not think to look in either tree.
check_literals "R-70f" "no numeric literal outside RelevancePolicy" \
    Packages/FocusClassify/Sources Packages/FocusCore/Sources/FocusCore/Relevance \
    --except Packages/FocusCore/Sources/FocusCore/Relevance/RelevancePolicy.swift \
    --except Packages/FocusClassify/Sources/FocusEvaluateCore/EvaluationPolicy.swift

# R-70g  NormalisedToken and Explanation are constructed only where they are declared — the
#        same shape as R-41's ActivityEvent.detail lint, applied to the other end of the
#        pipeline. Together with their private initialisers this is what makes raw captured
#        content in an explanation UNREPRESENTABLE rather than merely forbidden.
check_outside "R-70g" "NormalisedToken and Explanation are built only in their own files" \
    'NormalisedToken\(|Explanation\(' App Packages \
    --allow Packages/FocusCore/Sources/FocusCore/Relevance/NormalisedToken.swift \
    --allow Packages/FocusCore/Sources/FocusCore/Relevance/Explanation.swift

# R-70h  No model, anywhere, in any form — not even behind an availability check. e04 is the
#        DETERMINISTIC-FIRST epic: the heuristic layer is proven before a model exists, which
#        is what makes the charter's always-present-fallback clause temporally true rather
#        than a promise about a later epic. FoundationModels arrives in e06 and not before.
check_set "R-70h" "no FoundationModels in this epic" \
    'import FoundationModels|SystemLanguageModel|LanguageModelSession' \
    App Packages

# R-70n  A persisted rule with scopeRaw == "session" has NO subject kind: the shipped RuleScope
#        makes `.session` mutually exclusive with app/domain/titleToken, so nothing in the row
#        says whether its subject is a bundle identifier, an origin or a title token. e04 skips
#        and counts such rows (R-72.3) rather than guessing, and session-lived rules are owned
#        by SessionRuleBox instead. This lint stops the ambiguous shape being revived: the next
#        person who needs a session rule must reach for the box, not for the enum case.
#
#        Two notes on the allow-list, both deliberate and both self-limiting:
#
#        * `Packages/FocusRules` — the store implementations that must still be able to write
#          and wipe the legacy shape (`clearSessionRules()` keeps its shipped behaviour
#          exactly), and their tests, which plant one to prove the builder skips it.
#        * `Packages/FocusClassify/Tests` — R-72.3 requires the *engine* side to prove the skip
#          too: `RuleSnapshotBuilder` must drop a legacy row into `skippedRuleCount`, the
#          cascade must treat it as absent rather than as contradicting, and the golden corpus
#          carries a `legacySessionScopedRows` block for exactly that. A fixture that plants the
#          ambiguous shape in order to prove it reaches no rung is the opposite of a violation —
#          the same reason `Packages/FocusRules/Tests` is on this list, applied to the package
#          that consumes what that one stores.
#        * `PrioritySnapshotTests.swift` — a **FocusUI** fixture that builds a cockpit
#          `PriorityRuleValue`, not a `FocusRules.RelevanceRuleValue`. It never reaches the
#          cascade; it feeds a committed snapshot baseline that renders a legacy row. The
#          pattern cannot tell the two vocabularies apart because the line reads `scope:
#          .session,` with the type three lines above it, so the exemption is one named file
#          rather than a looser pattern.
#        * `FocusEvaluateCore/CorpusRunner.swift` — the golden corpus's `legacySessionScopedRows`
#          block plants exactly this row in order to prove `RuleSnapshotBuilder` drops it into
#          `skippedRuleCount` and that the cascade treats it as absent rather than as
#          contradicting. It is the same fixture machinery as the two Tests entries above,
#          living in a library only because R-75 requires the `FocusEvaluate` product to be able
#          to run the corpus too. `FocusEvaluateCore` is a test-lane target: no application
#          target links it, and `check-boundaries.sh` asserts that rather than assuming it.
check_outside "R-70n" "no rule is constructed with the session scope" \
    'scope: \.session|RuleScope\.session' App Packages \
    --allow Packages/FocusRules/Sources/FocusRules/SwiftDataRuleStore.swift \
    --allow Packages/FocusRules/Sources/FocusRules/InMemoryRuleStore.swift \
    --allow Packages/FocusRules/Tests \
    --allow Packages/FocusClassify/Tests \
    --allow Packages/FocusClassify/Sources/FocusEvaluateCore/CorpusRunner.swift \
    --allow Packages/FocusUI/Tests/FocusUITests/PrioritySnapshotTests.swift

# ---- e05 -------------------------------------------------------------------------------
#
# Eleven assertions, and every one of them lands BEFORE the code it constrains exists (e03's
# ordering doctrine). A lint that forbids a thing must exist before the thing could have been
# written, or the first green gate proves nothing.
#
# R-96a  `QueryWarrant(` appears in exactly ONE source file in the shipping graph — the same
#        guarantee R-70b gives `InterventionMandate(`, applied to the second authorisation
#        U-1 created. The count is the point: moving the producer becomes a reviewed act.
#
# R-96b  No source file names BOTH `QueryWarrant(` and `InterventionMandate(`. The adapter
#        that would widen a question into an accusation has to be written somewhere, and
#        this is the somewhere. U-1 retains e04's invariant in its true form: an uncertain
#        verdict gains the query affordance and NOTHING ELSE.
#
# R-96c  `LadderRung(` appears in exactly one file; that file names `InterventionMandate`
#        and does not name `QueryWarrant`. The rung is the unit of escalation, so its
#        provenance IS the no-escalation invariant.
#
# R-96d  No shared protocol over the two authorisations. `: NudgeAuthorisation`-shaped
#        conformances are banned outright — a shared abstraction is the elegant refactor
#        that would quietly destroy the guarantee while looking like an improvement.
#
# R-96e  `NSApp.activate(`, `NSApplication.shared.activate(` and `activateIgnoringOtherApps`
#        are banned. P-135 measured them harmless in an .accessory probe with no activatable
#        window; the shipping app is .regular (F-01, F-85), so that reading does not
#        transfer and the ban stands on the policy, not on the measurement.
#
#        Two search sets, because the ruling is about the NUDGE and the repository already
#        contains two activations that are not nudges and were shipped deliberately:
#
#          * **Absolute in the nudge module.** Return-to-task is
#            `NSRunningApplication.activate()` falling back to `NSWorkspace.openApplication`
#            (R-88), both measured at zero grants from a never-active app, and the nudge has
#            no other reason to bring anything forward. No allow-list, ever.
#          * **Pinned to two named files everywhere else.** e02's quick-capture panel
#            activates because the **person pressed the global hot key** (F-06) — an app that
#            did not come forward when summoned would be broken, and this is the opposite of
#            stealing focus; and `SelfCheck.comeForward` activates so the zero-grant shell
#            has a readable window to photograph, in a mode `--focus-self-check` alone
#            reaches. Neither is re-opened here (both are shipped e01–e03 rulings); both are
#            pinned, so a THIRD activation anywhere in the repository fails the gate.
#
# R-96f  No string under `nudge.*.query.*` matches the accusatory word list. D-11 made the
#        copy static precisely so it could be checked; tone is the product.
#
# R-96g  `requestAuthorization(` appears in exactly one file, the Intervention settings
#        pane's user-initiated action. P-134 proved the router needs only
#        getNotificationSettings, which never prompts — so SC-5 is discharged structurally.
#
# R-96h  `hidesOnDeactivate = true` and a `canBecomeMain` returning true are banned on any
#        NSPanel subclass in the nudge module. Both are silent failures: the first makes
#        the nudge vanish exactly when it is needed, the second activates the app.
#
# R-96i  No timer, DispatchSourceTimer, Task.sleep or Timer.scheduledTimer in the nudge
#        reducers. R-70e's doctrine applied to the third and fourth state machines.
#
# R-96j  Every numeric literal in nudge code lives in InterventionPolicy.swift — the second
#        and last such file. Excepted: 0, 1, and comparisons against count/isEmpty.
#
# R-96m  The panel's show path is ONE function. `makeKeyAndOrderFront(` and `makeKey(` are
#        banned outright in the nudge module; `orderFrontRegardless` may appear only in
#        NudgePanelController's show function; `becomesKeyOnlyIfNeeded = false` is banned.
#        P-139 measured makeKeyAndOrderFront flipping NSApp.isActive false -> true while
#        NSWorkspace.frontmostApplication never moved — a focus theft invisible to the one
#        instrument the original gate read. The two calls look identical in a diff, so the
#        difference is held by a lint rather than by a reviewer's memory.
#
# R-96n  `.fullScreenAuxiliary` is CONDITIONAL, and the condition is the presentation gate.
#        The flag may be ADDED to a collection behaviour in exactly one file and on exactly
#        one expression — the true branch of `collectionBehavior(presentationIsClear:)` — it
#        may never appear in `baseCollectionBehavior`, and `withdrawForPresentation()` must
#        drop it BEFORE it orders the window out.
#
#        **The dissent this rule records, and why the rule is not the one two reviewers
#        asked for.** Both adversarial reviewers of the e05 plan asked for
#        `.fullScreenAuxiliary` to be removed from the programme entirely: P-130 measured a
#        flagged panel drawn plainly on top of a real full-screen space, the window server
#        will not protect a presentation for us, and a flag that can stomp a presentation is
#        a flag with a hazard nobody can fully fence. The driver REJECTED that, and the plan
#        (lines 572, 1171) stands: a blanket ban makes the app silent over a full-screen
#        YouTube — the archetypal distraction — and U-1 exists precisely to end that silence.
#        The reviewers' position is recorded verbatim in the plan's Review dispositions and is
#        not erased by this lint. What the reviewers were RIGHT about is that nothing in
#        scripts/ enforced any rule about the flag at all: a conditional use is only safer
#        than an unconditional one if the condition is checkable, and until now it was held by
#        a comment and a reviewer's memory. This is that condition, as a lint.
#
# ## Two shapes these assertions need that the helpers above do not have
#
# `count_files` answers "how many files contain this", which is exactly R-96a's and R-96c's
# question. Two of the eleven ask something else:
#
#   * **R-96b** asks whether any ONE file contains two different things. An intersection, not
#     a count, and getting it wrong in the safe-looking direction (two separate `check`s, each
#     passing) would leave the adapter's home unguarded.
#   * **R-96g** has to hold BEFORE its one sanctioned call site exists. A `count_files … 1`
#     would fail today, when the count is legitimately zero, and the honest assertion is
#     "at most one, and if there is one it is that file" — which is what `count_at_most`
#     below says. It is a bound plus an identity, never a bare "at most", because "at most
#     one call site, anywhere" would let the prompt move into a router.
#
# The nudge module's search set is named once, in NUDGE_SOURCES, and paths that do not exist
# yet are dropped rather than making grep error — Phase B lands before Phase E, so
# `FocusUI/Nudge` is legitimately absent today. `existing_paths` prints what survives and the
# checks print what they searched, so an empty set is visible rather than a silent pass.

# Every path a nudge decision or a nudge surface may live in. FocusCore/Nudge is the
# decision module; the other three arrive in Phases E and F.
NUDGE_SOURCES=(
    Packages/FocusCore/Sources/FocusCore/Nudge
    Packages/FocusUI/Sources/FocusUI/Nudge
    Packages/FocusUI/Sources/FocusUI/MenuBar
)

# The reducers alone — no surface, no AppKit. R-96i and R-96j are about these.
NUDGE_REDUCERS=(Packages/FocusCore/Sources/FocusCore/Nudge)

# The one file permitted to show the panel (R-96m). It arrives in T133.
PANEL_SHOW_FILE="Packages/FocusUI/Sources/FocusUI/Nudge/NudgePanelController.swift"

# The one file permitted to ADD `.fullScreenAuxiliary` to a collection behaviour (R-96n).
PANEL_BEHAVIOUR_FILE="Packages/FocusUI/Sources/FocusUI/Nudge/NudgePanel.swift"

# The one file permitted to ask for notification authorisation (R-96g). It arrives in T138.
AUTHORISATION_ALLOWED_FILE="Packages/FocusUI/Sources/FocusUI/Scenes/InterventionSettingsView.swift"

# The String Catalog the decks live in (R-96f).
NUDGE_CATALOG="Packages/FocusCore/Sources/FocusCore/Resources/Localizable.xcstrings"

# Echo the arguments that name something that exists. A check whose whole search set has
# vanished prints so rather than passing in silence.
existing_paths() {
    local path
    for path in "$@"; do
        [[ -e "$path" ]] && print -r -- "$path"
    done
}

# check_not_both <condition> <description> <fixed-string-a> <fixed-string-b> <path>…
#
# R-96b. Fails on any single file containing both needles. Fixed strings, because both shapes
# end in `(`.
check_not_both() {
    local condition="$1"
    local description="$2"
    local first="$3"
    local second="$4"
    shift 4

    local files_first files_second both
    files_first=$(grep -rlF --include='*.swift' --exclude-dir='.build' -- "$first" "$@" 2>/dev/null | sort -u)
    files_second=$(grep -rlF --include='*.swift' --exclude-dir='.build' -- "$second" "$@" 2>/dev/null | sort -u)
    both=$(comm -12 <(print -r -- "$files_first") <(print -r -- "$files_second") | grep '[^[:space:]]')

    if [[ -n "$both" ]]; then
        print -u2 "FAIL [$condition] $description"
        print -u2 "$both" | sed 's/^/    /'
        print -u2 "    A file that can build both authorisations is a file that can adapt one"
        print -u2 "    into the other. U-1 gives an uncertain verdict the query affordance and"
        print -u2 "    NOTHING ELSE (R-76)."
        rc=1
    else
        print "ok   [$condition] $description"
    fi
}

# count_at_most <condition> <description> <fixed-string> <max> <allowed-file> <path>…
#
# R-96g's shape: a bound plus an identity. Zero files is a pass and says so — the sanctioned
# call site has not been written yet — one file is a pass only when it is the sanctioned one,
# and two is a failure whatever they are.
count_at_most() {
    local condition="$1"
    local description="$2"
    local pattern="$3"
    local maximum="$4"
    local allowed="$5"
    shift 5

    local files count
    files=$(grep -rlF --include='*.swift' --exclude-dir='.build' -- "$pattern" "$@" 2>/dev/null | sort -u)
    count=$(print -r -- "$files" | grep -c '[^[:space:]]')

    if (( count > maximum )); then
        print -u2 "FAIL [$condition] $description — at most $maximum file(s), found $count"
        print -u2 "$files" | sed 's/^/    /'
        rc=1
        return
    fi

    local file
    for file in ${(f)files}; do
        [[ -z "$file" ]] && continue
        if [[ "$file" != "$allowed" ]]; then
            print -u2 "FAIL [$condition] $description — found in $file"
            print -u2 "    The only sanctioned location is $allowed"
            rc=1
            return
        fi
    done

    if (( count == 0 )); then
        print "ok   [$condition] $description (0 call sites; the sanctioned one is $allowed)"
    else
        print "ok   [$condition] $description ($count file: $allowed)"
    fi
}

print
print "== e05: the nudge, the two authorisations and the panel's show path"

# R-96a — the second authorisation has exactly one producer, as the first one does.
count_files "R-96a" "QueryWarrant is constructed in exactly one file" \
    'QueryWarrant(' 1 App Packages

# R-96b — and no file can build both.
check_not_both "R-96b" "no file constructs both a QueryWarrant and an InterventionMandate" \
    'QueryWarrant(' 'InterventionMandate(' App Packages

# R-96c — the rung's provenance IS the no-escalation invariant, so its construction site is
# pinned and that site's contents are asserted: it must name the authorisation a rung is built
# from, and must not name the one it is not.
count_files "R-96c" "LadderRung is constructed in exactly one file" \
    'LadderRung(' 1 App Packages
# Comment-stripped, exactly as `count_files` counts: a doc comment that quotes the constructor
# in order to explain the rule is the opposite of a violation.
ladder_files=(${(f)"$(grep -rnF --include='*.swift' --exclude-dir='.build' -- 'LadderRung(' App Packages 2>/dev/null | strip_comments | cut -d: -f1 | sort -u)"})
if (( ${#ladder_files} == 0 )) || [[ -z "${ladder_files[1]}" ]]; then
    print -u2 "FAIL [R-96c] no file constructs a LadderRung — the ladder has lost its unit"
    rc=1
else
    # Every such file, not the first: `head -1` would let a second construction site pass its
    # content check by happening to sort after the sanctioned one.
    for ladder_file in $ladder_files; do
        if grep -HnF 'InterventionMandate' "$ladder_file" | strip_comments | grep -q .; then
            print "ok   [R-96c] $ladder_file names InterventionMandate"
        else
            print -u2 "FAIL [R-96c] $ladder_file builds a rung without naming InterventionMandate"
            print -u2 "    A rung is built from a mandate and from nothing else (R-76.3)."
            rc=1
        fi
        if grep -HnF 'QueryWarrant' "$ladder_file" | strip_comments | grep -q .; then
            print -u2 "FAIL [R-96c] $ladder_file names QueryWarrant beside the rung constructor"
            print -u2 "    This is the file an escalation adapter would have to be written in."
            rc=1
        else
            print "ok   [R-96c] $ladder_file does not name QueryWarrant"
        fi
    done
fi

# R-96d — no shared abstraction over the two authorisations, and no retroactive conformance
# added to either of them. The elegant refactor is the one that would destroy the guarantee.
check_set "R-96d" "no shared authorisation protocol over the two types" \
    'NudgeAuthorisation|NudgeAuthorization|InterventionAuthorisation|AnyAuthorisation|extension[[:space:]]+(QueryWarrant|InterventionMandate)[[:space:]]*:' \
    App Packages

# R-96e — the shipping app is .regular, so every one of these steals focus. Pinned to the two
# shipped, deliberately user-summoned call sites; a third one anywhere fails the gate. The
# nudge module's own absolute ban is asserted below, with no allow-list at all.
check_outside "R-96e" "NSApp.activate appears only where the person summoned the app" \
    'NSApp\.activate\(|NSApplication\.shared\.activate\(|activateIgnoringOtherApps' \
    App Packages \
    --allow Packages/FocusUI/Sources/FocusUI/Capture/QuickCapturePanelController.swift \
    --allow App/SelfCheck.swift

# R-96f — the question never accuses.
#
# The word list is small and blunt on purpose. Tone is the product: the Court's default voice
# asks "Is {subject} part of {task}?", and the whole difference between this app and the ones
# people uninstall is that the question does not carry an accusation inside it. D-11 made the
# copy static precisely so a property like this could be checked at all.
#
# It reads the committed **catalog** rather than the source, because the string a person sees is
# the catalog's; and it is inline here rather than in a script of its own so that the word list
# exists in exactly one place in the repository.
print
print "== R-96f: no line under a nudge query key accuses anybody"
python3 - "$NUDGE_CATALOG" <<'PYTHON'
import json
import sys

# Second-person accusation, in the shapes a well-meaning copy edit reaches for. Every entry is
# lower-cased and matched as a substring, so "You're wasting time" and "wasted" both hit.
ACCUSATORY = (
    "distract", "off task", "off-task", "wasting", "waste of", "wasted",
    "procrastinat", "you should", "you shouldn", "slacking", "goofing",
    "avoiding", "supposed to", "not working", "get back to work", "stop it",
    "focus up", "no excuse", "again?",
)

path = sys.argv[1]
with open(path) as handle:
    catalog = json.load(handle)

failures = []
checked = 0
for key, entry in sorted(catalog.get("strings", {}).items()):
    if not key.startswith("nudge.") or ".query." not in key:
        continue
    unit = entry.get("localizations", {}).get("en", {}).get("stringUnit", {})
    value = unit.get("value", "")
    checked += 1
    lowered = value.lower()
    for word in ACCUSATORY:
        if word in lowered:
            failures.append(f"{key}: {value!r} contains {word!r}")

if checked == 0:
    print("FAIL [R-96f] no nudge query keys found in the catalog at all", file=sys.stderr)
    sys.exit(1)

for failure in failures:
    print(f"    {failure}", file=sys.stderr)

if failures:
    print(
        "FAIL [R-96f] the question accuses somebody. The accusation never says "
        '"you are distracted"; the question never says "you should be working" (R-90, D-11).',
        file=sys.stderr,
    )
    sys.exit(1)

print(f"ok   [R-96f] {checked} nudge query line(s) checked, none accusatory")
PYTHON
tone_rc=$?
(( tone_rc != 0 )) && rc=1

# R-96g — the routing path must be provably prompt-free, and the assertion has to hold before
# the one sanctioned call site is written.
count_at_most "R-96g" "requestAuthorization appears only in the settings pane's action" \
    'requestAuthorization(' 1 "$AUTHORISATION_ALLOWED_FILE" App Packages

# R-96n's two structural halves, which no grep over single lines can express.
#
# **Half one: the add is guarded by the gate.** `.fullScreenAuxiliary` may be unioned into a
# behaviour only on an expression that names `presentationIsClear`. The union sits on the
# ternary's true branch, one line below the condition, so the window under test is the matching
# line plus the two above it — enough to see the condition, and far too small to accidentally
# find a `presentationIsClear` belonging to some other statement.
#
# **Half two: the flag is dropped before the window goes.** `withdrawForPresentation()` exists
# because a panel shown while the gate was clear is still on screen, and still flagged, when
# somebody starts presenting a minute later. It must set the behaviour with
# `presentationIsClear: false` and must do so BEFORE `orderOut(`: in the other order there is an
# instant in which a still-visible panel is eligible to join the space it is being removed from.
check_full_screen_auxiliary() {
    local behaviour_file="$PANEL_BEHAVIOUR_FILE"
    local show_file="$PANEL_SHOW_FILE"

    if [[ ! -f "$behaviour_file" ]]; then
        print -u2 "FAIL [R-96n] the panel's behaviour table is missing at $behaviour_file"
        rc=1
        return
    fi
    if [[ ! -f "$show_file" ]]; then
        print -u2 "FAIL [R-96n] the panel's show path is missing at $show_file"
        rc=1
        return
    fi

    local unguarded
    unguarded=$(awk '
        { window = previous2 " " previous1 " " $0 }
        /(union|formUnion|insert)\([[:space:]]*\.fullScreenAuxiliary/ &&
            window !~ /presentationIsClear/ { printf "%s:%d:%s\n", FILENAME, NR, $0 }
        { previous2 = previous1; previous1 = $0 }
    ' "$behaviour_file")

    if [[ -n "$unguarded" ]]; then
        print -u2 "FAIL [R-96n] the full-screen flag is added without the presentation gate"
        print -u2 "$unguarded" | sed 's/^/    /'
        rc=1
    else
        print "ok   [R-96n] every full-screen-flag add is guarded by presentationIsClear"
    fi

    # The base behaviour is what a panel starts from, so the flag being absent from it is the
    # whole of "conditional". The declaration wraps, so the three lines from it are read.
    local base_violation
    base_violation=$(awk '
        /static let baseCollectionBehavior/ { remaining = 3 }
        remaining > 0 {
            if ($0 ~ /\.fullScreenAuxiliary/) { printf "%s:%d:%s\n", FILENAME, NR, $0 }
            remaining--
        }
    ' "$behaviour_file")

    if [[ -n "$base_violation" ]]; then
        print -u2 "FAIL [R-96n] baseCollectionBehavior carries the full-screen flag unconditionally"
        print -u2 "$base_violation" | sed 's/^/    /'
        rc=1
    else
        print "ok   [R-96n] baseCollectionBehavior never carries the full-screen flag"
    fi

    # Half two, read as an ORDER rather than as two independent presences.
    local withdraw
    withdraw=$(awk '
        /func withdrawForPresentation\(\)/ { inside = 1 }
        inside { print }
        inside && /^    \}/ { inside = 0 }
    ' "$show_file")

    if [[ -z "$withdraw" ]]; then
        print -u2 "FAIL [R-96n] there is no withdrawForPresentation() to drop the flag"
        rc=1
        return
    fi

    local drop_line order_line
    drop_line=$(print -r -- "$withdraw" | grep -nE 'collectionBehavior\(presentationIsClear:[[:space:]]*false\)' | head -1 | cut -d: -f1)
    order_line=$(print -r -- "$withdraw" | grep -nE 'orderOut\(' | head -1 | cut -d: -f1)

    if [[ -z "$drop_line" ]]; then
        print -u2 "FAIL [R-96n] withdrawForPresentation() never drops the full-screen flag"
        rc=1
    elif [[ -z "$order_line" ]]; then
        print -u2 "FAIL [R-96n] withdrawForPresentation() never takes the panel off screen"
        rc=1
    elif (( drop_line >= order_line )); then
        print -u2 "FAIL [R-96n] withdrawForPresentation() orders the panel out before dropping the flag"
        print -u2 "    drop at body line $drop_line, orderOut at body line $order_line"
        rc=1
    else
        print "ok   [R-96n] withdrawForPresentation() drops the flag before ordering the panel out"
    fi
}

print
nudge_paths=(${(f)"$(existing_paths $NUDGE_SOURCES)"})
if (( ${#nudge_paths} == 0 )); then
    print -u2 "FAIL [R-96h/i/j/m] the nudge module has no source directory at all"
    rc=1
else
    print "   nudge module: ${nudge_paths[*]}"

    # R-96e, the half with no allow-list: a nudge never brings this application forward.
    check_set "R-96e" "no nudge surface activates the application" \
        'NSApp\.activate\(|NSApplication\.shared\.activate\(|activateIgnoringOtherApps' \
        $nudge_paths

    # R-96h — the two silent failures of R-89's panel. `hidesOnDeactivate = true` makes the
    # nudge vanish exactly when it is needed; a `canBecomeMain` returning true activates the
    # application.
    check_set "R-96h" "no panel hides on deactivate or becomes main" \
        'hidesOnDeactivate[[:space:]]*=[[:space:]]*true|canBecomeMain[^!=<>]*=[[:space:]]*true|canBecomeMain[[:space:]]*:[[:space:]]*Bool[[:space:]]*\{[[:space:]]*true' \
        $nudge_paths

    # R-96m — the show path is one function, and the call that takes focus is banned outright.
    check_set "R-96m" "no nudge surface makes a window key programmatically" \
        'makeKeyAndOrderFront\(|makeKey\(|becomesKeyOnlyIfNeeded[[:space:]]*=[[:space:]]*false' \
        $nudge_paths

    check_outside "R-96m" "orderFrontRegardless appears only in the panel's show function" \
        'orderFrontRegardless' $nudge_paths \
        --allow "$PANEL_SHOW_FILE"

    # R-96n — the conditional flag, and the condition.
    #
    # An ADD is the thing under test, never a read: `properties` legitimately asks
    # `behavior.contains(.fullScreenAuxiliary)` so the unit lane and the self-check can assert
    # the flag's state, and a lint that could not tell a read from an add would either ban the
    # instrument or pass everything.
    check_outside "R-96n" "the full-screen-auxiliary flag is added in one file only" \
        '(union|formUnion|insert)\([[:space:]]*\.fullScreenAuxiliary' \
        $nudge_paths --allow "$PANEL_BEHAVIOUR_FILE"

    # A collection behaviour assembled as a literal that names the flag would add it without
    # ever calling `union`, so the literal shape is banned across the whole module — including
    # the one file the union is allowed in.
    check_set "R-96n" "no collection behaviour literal carries the full-screen flag" \
        'collectionBehavior[^=]*=[^=]*\.fullScreenAuxiliary|\[[^]]*\.fullScreenAuxiliary[^]]*\]' \
        $nudge_paths

    check_full_screen_auxiliary
fi

reducer_paths=(${(f)"$(existing_paths $NUDGE_REDUCERS)"})
if (( ${#reducer_paths} == 0 )); then
    print -u2 "FAIL [R-96i/j] the nudge reducers have no source directory"
    rc=1
else
    # R-96i — a replayable reducer is what makes a sequence fixture an exact assertion rather
    # than a flaky one. R-70e's doctrine, applied to the ladder and the fatigue controller.
    check_set "R-96i" "no timer or sleep in the nudge reducers" \
        'Timer\(|DispatchSourceTimer|Task\.sleep|asyncAfter|Timer\.scheduledTimer|RunLoop\.' \
        $reducer_paths

    # R-96j — InterventionPolicy.swift is the second and last file in which a numeric literal
    # may appear. Scoped to the reducers rather than to the surfaces: a panel has a frame and a
    # menu bar has a cadence, and neither is a threshold about a person.
    check_literals "R-96j" "no numeric literal outside InterventionPolicy" \
        $reducer_paths \
        --except Packages/FocusCore/Sources/FocusCore/Nudge/InterventionPolicy.swift
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
