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

# The one file permitted to call `ModelContext.fetch` / `fetchCount` directly (R-97,
# focus-tzj.2): it is where the counting wrappers live.
FETCH_ALLOWED_FILE="Packages/FocusCore/Sources/FocusCore/Store/StoreFetchCounter.swift"
# Where R-97 applies. Shipping sources only: a test bundle that fetches directly is not a tick,
# and counting its reads would put the suite's own housekeeping into a number that is supposed
# to describe the product.
FETCH_SEARCH_PATHS=(App Packages/*/Sources)

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

# `=` and not `==`, because R-19 bans an **assignment** and `===` is a comparison. The old
# pattern matched `window.undoManager === manager` — the identity check that proves the journal
# registers on the manager the key window hands to the responder chain (F-93), which is the
# opposite of the thing being banned. A lint that fires on the proof of a rule is a lint that
# gets the rule turned off.
check "R-19" "no ModelContext.undoManager assignment (undo is the PriorityStore journal)" \
    '\.undoManager[[:space:]]*=([^=]|$)'

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
# **`requestAuthorization` is banned by R-96g below rather than by this list**, and the ban is
# back to graph-wide (focus-wy0). e03 banned it here; e05 narrowed it to one named file when it
# shipped notification consent; that consent asked for a permission no rung could spend and was
# deleted, so the bound went back to zero. It stays in R-96g rather than returning to this
# pattern for one reason: the needle must carry a trailing `(`, or it fires on
# `requestAuthorizationCallCount` — the honest reporting name the self-check publishes, and the
# number whose being zero is what §3.F.37 and the `notification-denied` stage actually assert.
# A lint that made the app unable to *report* it had never asked would be a lint working against
# the thing it exists to prove.
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

# --- R-97: every fetch the shipping code makes is counted (focus-tzj.2) ----------------------
#
# `StoreFetchCounter` is what makes "the tick fetches nothing when nothing has changed" a number
# the self-check publishes and the gate pins, rather than a claim. A counter that a new fetch
# could quietly not join would be worth nothing at all — the reading would stay at its pinned
# value while the tick got slower — so the count is taken inside `countedFetch`/`countedFetchCount`
# and the bare calls are banned outside the file that defines them.
#
# Both directions, like every other allow-list here: the exemption must not outlive its reason,
# so the permitted file is required to still contain the calls it is permitted to make.
print
print "== every SwiftData fetch in the shipping code is counted"
fetch_hits=$(grep -rnE '\.fetch(Count)?\(' "${FETCH_SEARCH_PATHS[@]}" --include='*.swift' 2>/dev/null \
    | strip_comments \
    | grep -vE '\.countedFetch(Count)?\(' \
    | grep -v "^${FETCH_ALLOWED_FILE}:")
if [[ -n "$fetch_hits" ]]; then
    print -u2 "FAIL [R-97] a bare ModelContext.fetch/fetchCount outside $FETCH_ALLOWED_FILE:"
    print -u2 "$fetch_hits" | sed 's/^/    /'
    print -u2 "    Use countedFetch(_:) / countedFetchCount(_:). An uncounted fetch makes the"
    print -u2 "    self-check's per-tick fetch reading a number about some of the fetches,"
    print -u2 "    which is a reading that cannot go red when the tick gets heavier."
    rc=1
elif ! grep -qE '\.fetch(Count)?\(' "$FETCH_ALLOWED_FILE" 2>/dev/null; then
    print -u2 "FAIL [R-97] $FETCH_ALLOWED_FILE no longer calls fetch at all."
    print -u2 "    The allow-list must not outlive the reason for it — remove the exemption,"
    print -u2 "    or put the counting wrappers back."
    rc=1
else
    print "ok   [R-97] every SwiftData fetch goes through the counting wrappers"
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
    Packages/FocusClassify/Sources Packages/FocusEvaluate/Sources

# R-70f  Every numeric threshold lives in RelevancePolicy.swift and nowhere else. This is what
#        makes "no magic numbers" mechanical instead of a habit. Excepted: 0 and 1, and
#        comparisons against `count`/`isEmpty`.
#
#        A SECOND excepted file, and the reason it is not a weakening. R-75 moves the evaluation
#        harness into `FocusEvaluateCore` — emission has to be a
#        product rather than a test side effect, and this search path predates that decision by
#        two phases. A percentile rank, a cache-sweep capacity and a corpus floor are all
#        numbers, and none of them is a threshold about a person: they size the evidence, not
#        the judgement. So the harness tree gets exactly the same discipline the engine tree has
#        — ONE file in which a literal may appear, every constant named, doc-commented and
#        traceable to the ruling that fixed it — and `EvaluationPolicy.swift` is that file. The
#        engine's own exception list is untouched, and a threshold cannot be introduced anywhere
#        a reviewer would not think to look in either tree.
check_literals "R-70f" "no numeric literal outside RelevancePolicy" \
    Packages/FocusClassify/Sources Packages/FocusEvaluate/Sources \
    Packages/FocusCore/Sources/FocusCore/Relevance \
    --except Packages/FocusCore/Sources/FocusCore/Relevance/RelevancePolicy.swift \
    --except Packages/FocusEvaluate/Sources/FocusEvaluateCore/EvaluationPolicy.swift

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
#        * `Packages/FocusClassify/Tests` and `Packages/FocusEvaluate/Tests` — R-72.3 requires
#          the *engine* side to prove the skip
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
    --allow Packages/FocusEvaluate/Tests \
    --allow Packages/FocusEvaluate/Sources/FocusEvaluateCore/CorpusRunner.swift \
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
# R-96o  **The sentence names the app; the key stays a key** (focus-ebv). Two halves:
#
#          * every line in a nudge SURFACE that draws text and names a subject must draw
#            `displayName`. Not the value, not the description — the display half, by name;
#          * no such line may name `identifier`;
#          * and the three files that do nothing BUT draw a nudge — the two panels and the
#            popover — may not name `identifier` anywhere at all. A line-based rule alone can
#            be walked around by aliasing the key into a local first; this half is what makes
#            that walk fail, because the local's own definition names it.
#
#        This is the condition the bead asked for: `grep -n "subject" scripts/check-strings.sh`
#        returned nothing, so the one slot whose content is the whole product had no lint over
#        it at all — while THREE test files pinned the raw bundle identifier as the expected
#        user-facing sentence. A defect with proofs guarding it needs a lint that is about the
#        shape rather than about the case.
#
#        Line-based, and honestly so: an `arguments:` list split across lines so that the slot
#        expression sits on a line of its own would pass. That is a visible act in a diff, which
#        is the most a grep can offer here; the totality claim is `SubjectSentenceTests`, which
#        renders every deck crossed with every subject shape and asserts both directions.
#
# R-96p  **The charge has exactly one producer, and it is a measurement** (focus-1b5,
#        focus-nrl). `PerceptibleChange(` may appear in exactly one file, and that file is
#        `PerceptibleChange.swift` — the type whose only public producer,
#        `proven(on:from:to:)`, takes two readings of the real surfaces and answers `nil`
#        unless the person was shown something. `NudgeHost` cannot spend a unit of anybody's
#        day without holding one, so charging while invisible is unrepresentable rather than
#        merely tested for.
#
#        In the shape R-96c pins `LadderRung(`, and for the identical reason: the rung is the
#        unit of escalation and its provenance IS the no-escalation invariant, and this is the
#        unit of *spending* — its provenance IS the invariant that the app charges only for
#        what it showed. Three consecutive rounds fixed one instance each of "charged while
#        invisible" and left the shape intact, because the rule lived in a doc comment beside
#        the code that broke it.
#
# R-96s  **A reading becomes evidence in exactly one place, and it is the end of a turn**
#        (focus-my0). `SettledObservation(` may appear in exactly one file, and that file is
#        `PerceptibleChange.swift` — where the memberwise initialiser is `fileprivate` and
#        `SurfaceTurn.Seam.settled(_:)` is the only producer. R-96p's own shape, one level
#        down, and it exists because R-96p held while its purpose was defeated: the receipt
#        really was produced by `proven(on:from:to:)`, from two real readings of real
#        surfaces, and the *after* reading had been taken in the middle of a call stack that
#        went on to undo everything it recorded. Measured on the shipping loop, taking a break
#        with a badge question pending charged an accusation for a mark that was put on the
#        item and taken off it before AppKit composited anything, and wrote the row
#        `accusation/delivered/menuBar/ignored` on a day nobody clicked anything.
#
#        A second construction site is that defect's next costume: it would let any call site
#        bless its own mid-turn reading, which is exactly what the type exists to stop.
#
# R-96r  **The budget has exactly one construction site, and every move through it is a
#        sentence** (focus-d6r). `InterruptionBudget(` may appear in exactly one file, and that
#        file is `InterruptionBudget.swift` — where the memberwise initialiser is private,
#        `interruptionsToday` is DERIVED from the two per-kind counters, and `spending(_:)` is
#        the only mover. R-96p's twin, on the other side of the road: that one makes "charged
#        for something nobody saw" unrepresentable, and this one makes "spent a unit of the
#        day and said nothing" unrepresentable.
#
#        The shape it forbids is the one that produced the bead. Three files answered *"what
#        did that rung cost?"* independently — `InterventionLog.budget` summed stored rows,
#        `InterruptionBudget.spending(_:)` stepped a value, and `NudgeWorld.recordAccusation`
#        counted the replayed day — and focus-ndh's repair reached one of the three. The other
#        two went on charging the ambient glyph, so eight glyph landings made
#        `permits(.accusation)` and `permits(.query)` alike answer false on a day the app had
#        accused nobody and asked nobody anything.
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
# R-96g  `requestAuthorization(` appears in NO file (focus-wy0). It was pinned to one — the
#        Intervention pane's enable button — until that button was found to be asking for a
#        permission no rung can spend. P-134 proved the router needs only
#        getNotificationSettings, which never prompts; the app now needs not even that to
#        decide anything, so SC-5 is discharged by the call not existing.
#
# R-96s  **The shipped Mach-O carries no notification-POSTING selector** (focus-3vb). R-96g is a
#        source grep and every source grep can be defeated by building the string at runtime;
#        this is the same claim measured on the artefact. U-2 is a user ruling — no rung routes
#        to a notification, because the app asks for no system permission of any kind — and
#        until this line the ruling had no enforcement at the binary at all: the router fold
#        proves nothing about a path that reaches UNUserNotificationCenter without asking the
#        router. Non-vacuity is a CONTROL rather than an argument: the reading half of the
#        boundary must still be present in the same binary, so a check that passes because the
#        framework was dropped fails instead.
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
# R-96q  **A command reaches the cockpit's channel from the menu bar and from nowhere else**
#        (focus-mwm). `FocusCommandCenter.send(...)` delivers to a handler that only
#        `CockpitView.onAppear` registers, so a caller outside the menu is a caller whose click
#        does nothing whenever the person has closed the main window — which for a menu-bar app
#        is the ordinary state, not an edge. Measured: the popover's Open / Start / Pause /
#        Complete and the nudge panel's Pause and Change priority, six controls, all silent with
#        the cockpit shut, and Pause additionally wrote a completed correction and let the
#        session run on.
#
#        Pinned to `FocusCommands.swift` — the menu bar itself, which is only reachable while
#        this application is active and which is where the raise is now performed. Every other
#        surface calls the host it means (`sessionHost`, `nudgeHost`, `quickCapturePanel`) or
#        asks for the window by name (`requestCockpit()`), and a seventh control that reaches
#        for the buffer instead is a diff in this line.
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
#   * **R-96g** is a plain ban now (focus-wy0), so it is a `check` rather than a count. It spent
#     the epic as `count_at_most … 1` — a bound plus an identity, so the one sanctioned prompt
#     could not migrate into a router. The prompt has been deleted, and a bound of one over an
#     empty set is an invitation rather than a guard, so the bound is zero.
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

# The files that DRAW a nudge. R-96o is about these: `FocusCore/Nudge` is deliberately absent,
# because it draws nothing and holds the two halves' definitions.
NUDGE_SURFACES=(
    Packages/FocusUI/Sources/FocusUI/Nudge
    Packages/FocusUI/Sources/FocusUI/MenuBar
)

# The three files that do nothing but draw a nudge, and may therefore name no key at all
# (R-96o). The rest of `NUDGE_SURFACES` is excluded for named reasons: `SubjectNaming` is the
# seam that RESOLVES a name and has to take a key to do it, `NotificationDelivery`'s
# identifiers are `UNNotificationRequest`'s and have nothing to do with a subject, and
# `MenuBarPresentation` declares the value types whose halves these are — it holds
# `MenuBarSnooze`, which is identified and cancelled by `subject.identifier` while it draws
# `subject.displayName`, so it names a key by construction and cannot be in this list
# (focus-tzj.6 moved it out of `MenuBarController`, which draws nothing either).
NUDGE_DRAWING_FILES=(
    Packages/FocusUI/Sources/FocusUI/Nudge/QueryPanelView.swift
    Packages/FocusUI/Sources/FocusUI/Nudge/AccusationPanelView.swift
    Packages/FocusUI/Sources/FocusUI/MenuBar/MenuBarPopoverView.swift
)

# The one file permitted to show the panel (R-96m). It arrives in T133.
PANEL_SHOW_FILE="Packages/FocusUI/Sources/FocusUI/Nudge/NudgePanelController.swift"

# The one file permitted to construct a `PerceptibleChange` — the receipt without which nothing
# may be charged (R-96p, focus-1b5, focus-nrl).
PERCEPTION_FILE="Packages/FocusCore/Sources/FocusCore/Nudge/PerceptibleChange.swift"

# The one file permitted to bless a reading as taken at a seam — the same file, because the seam
# and the receipt it feeds are one invariant (R-96s, focus-my0).
SETTLED_READING_FILE="Packages/FocusCore/Sources/FocusCore/Nudge/PerceptibleChange.swift"

# The one file permitted to construct an `InterruptionBudget` — the value whose every move is a
# sentence somebody was actually made (R-96r, focus-d6r).
BUDGET_FILE="Packages/FocusCore/Sources/FocusCore/Nudge/InterruptionBudget.swift"

# The one file permitted to ADD `.fullScreenAuxiliary` to a collection behaviour (R-96n).
PANEL_BEHAVIOUR_FILE="Packages/FocusUI/Sources/FocusUI/Nudge/NudgePanel.swift"

# **No file is permitted to ask for notification authorisation** (R-96g, focus-wy0), so there is
# no `AUTHORISATION_ALLOWED_FILE` to name. It was the Intervention settings pane; the button it
# held asked for a permission no rung could spend, and went with the section that drew it.

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

# R-96p — **the charge has exactly one producer, and it is a measurement** (focus-1b5,
# focus-nrl). `PerceptibleChange` is the receipt `NudgeHost` must hold before it may spend a unit
# of the person's day, and `PerceptibleChange.proven(on:from:to:)` is the only thing that makes
# one. Pinned in the shape R-96c pins the ladder's unit, and for the identical reason: three
# consecutive rounds fixed one instance of "charged while invisible" and left the shape that
# produces it, because the rule lived in a doc comment beside the code that broke it. A second
# construction site is the round-five version of this defect, and it is a diff in this line.
count_files "R-96p" "PerceptibleChange is constructed in exactly one file" \
    'PerceptibleChange(' 1 App Packages
# And that file is the type's own, which is also the only file permitted to read a raw
# observation into a verdict. Comment-stripped, exactly as `count_files` counts.
perception_files=(${(f)"$(grep -rnF --include='*.swift' --exclude-dir='.build' -- 'PerceptibleChange(' App Packages 2>/dev/null | strip_comments | cut -d: -f1 | sort -u)"})
if (( ${#perception_files} == 0 )) || [[ -z "${perception_files[1]}" ]]; then
    print -u2 "FAIL [R-96p] nothing constructs a PerceptibleChange — the charge has no receipt"
    rc=1
else
    for perception_file in $perception_files; do
        if [[ "$perception_file" == "$PERCEPTION_FILE" ]]; then
            print "ok   [R-96p] $perception_file is the sanctioned producer"
        else
            print -u2 "FAIL [R-96p] $perception_file constructs a PerceptibleChange"
            print -u2 "    A charge is proven by measuring a surface, in $PERCEPTION_FILE alone."
            rc=1
        fi
    done
fi

# R-96u — **an accusation's charge is DERIVED from the rung it landed on, never stated**
# (focus-uru). `InterruptionCharge` has two initialisers and only one of them asks the question:
# `init(_ kind:)` is total, and `init?(_ event:)` answers `nil` for a rung that spoke to nobody.
#
# The total one cannot go — a question always speaks, carries no rung, and has no
# `InterventionEvent` at the moment the fatigue reducer is folded — so the pin is on the KIND
# rather than on the initialiser. Four rounds gave the derivation to one more consequence and
# left the next: focus-ndh gave it `dailyAccusationCap`, focus-d6r `dailyInterruptionCap` one
# line above it, focus-2yy the cap gate, and focus-uru `RelevancePolicy.mandateCooldown` one line
# BELOW the charge, where both production lanes read
#
#     if let charge = InterruptionCharge(event, …) { charges.append(charge) }
#     fatigue = FatigueController.reduce(fatigue, event: .delivered(.accusation), now: now)
#
# `FatigueEvent.delivered` now takes the charge, which makes the pair one decision. This is what
# stops the fifth round writing the charge out by hand instead: an accusation whose charge is
# stated has not been asked whether it spoke to anybody, and the glyph is the answer that differs.
check_set "R-96u" "no delivery states an accusation's charge instead of deriving it from its rung" \
    '\.delivered\(InterruptionCharge\(\.accusation' App Packages

# R-96s — **a reading becomes evidence in exactly one place, and it is the end of a turn**
# (focus-my0). `PerceptibleChange.proven(on:from:to:)` takes a `SettledObservation` as its *after*
# half and nothing else will do, so this is the rule that says where one can come from: a
# `fileprivate` initialiser and `SurfaceTurn.Seam.settled(_:)`, which is handed out by nothing but
# the end of a turn. Without it every call site could bless its own mid-turn reading again, and
# the charge for a mark that was put up and taken down inside one call stack — measured, with the
# row `accusation/delivered/menuBar/ignored` — comes straight back.
count_files "R-96s" "SettledObservation is constructed in exactly one file" \
    'SettledObservation(' 1 App Packages
settled_files=(${(f)"$(grep -rnF --include='*.swift' --exclude-dir='.build' -- 'SettledObservation(' App Packages 2>/dev/null | strip_comments | cut -d: -f1 | sort -u)"})
if (( ${#settled_files} == 0 )) || [[ -z "${settled_files[1]}" ]]; then
    print -u2 "FAIL [R-96s] nothing blesses a reading as settled — no charge can be proven"
    rc=1
else
    for settled_file in $settled_files; do
        if [[ "$settled_file" == "$SETTLED_READING_FILE" ]]; then
            print "ok   [R-96s] $settled_file is the sanctioned producer"
        else
            print -u2 "FAIL [R-96s] $settled_file blesses its own reading as settled"
            print -u2 "    A reading is evidence only at a turn's seam, in $SETTLED_READING_FILE."
            rc=1
        fi
    done
fi

# R-96r — **the budget has exactly one construction site** (focus-d6r). R-96p's twin: that rule
# makes a charge without a perceptible change unrepresentable, and this one makes a unit of the
# day spent on nothing unrepresentable. The initialiser is private, `interruptionsToday` is
# derived from the two per-kind counters, and `spending(_:)` is the only mover — so a second
# construction site is the one diff that could put the fourth field, and the three disagreeing
# summations, back.
count_files "R-96r" "InterruptionBudget is constructed in exactly one file" \
    'InterruptionBudget(' 1 App Packages
budget_files=(${(f)"$(grep -rnF --include='*.swift' --exclude-dir='.build' -- 'InterruptionBudget(' App Packages 2>/dev/null | strip_comments | cut -d: -f1 | sort -u)"})
if (( ${#budget_files} == 0 )) || [[ -z "${budget_files[1]}" ]]; then
    print -u2 "FAIL [R-96r] nothing constructs an InterruptionBudget — the day has no budget"
    rc=1
else
    for budget_file in $budget_files; do
        if [[ "$budget_file" == "$BUDGET_FILE" ]]; then
            print "ok   [R-96r] $budget_file is the sanctioned producer"
        else
            print -u2 "FAIL [R-96r] $budget_file constructs an InterruptionBudget"
            print -u2 "    A day's spend is folded from InterruptionCharges, in $BUDGET_FILE alone."
            rc=1
        fi
    done
fi

# R-96q — the cockpit's channel has one shipping caller, and it is the menu bar.
#
# `FocusCommandCenter` is a `@MainActor` singleton reached as `.shared`, so the two shapes a new
# caller can take are `FocusCommandCenter.shared.send(` and `<some>commandCenter.send(`. Both are
# matched. `requestCockpit()` is deliberately NOT matched: it is the verb a surface uses to ask
# for the window by name, it opens one rather than storing a command against one, and it reports
# whether anything could.
check_outside "R-96q" "only the menu bar sends a command down the cockpit's channel" \
    '(FocusCommandCenter\.shared|[Cc]ommandCenter)\.send\(' \
    App Packages/*/Sources \
    --allow Packages/FocusUI/Sources/FocusUI/Commands/FocusCommands.swift

# R-96d — no shared abstraction over the two authorisations, and no retroactive conformance
# added to either of them. The elegant refactor is the one that would destroy the guarantee.
check_set "R-96d" "no shared authorisation protocol over the two types" \
    'NudgeAuthorisation|NudgeAuthorization|InterventionAuthorisation|AnyAuthorisation|extension[[:space:]]+(QueryWarrant|InterventionMandate)[[:space:]]*:' \
    App Packages

# R-96e — the shipping app is .regular, so every one of these steals focus. Pinned to the two
# shipped, deliberately user-summoned call sites; a third one anywhere fails the gate. The
# nudge module's own absolute ban is asserted below, with no allow-list at all.
#
# The third entry is a **test-lane** file and is not shipped. `NSPopover.show(…)` does nothing
# unless the application is active, so the only way to read the badge route's three wires with
# the popover really open is for the test process to activate itself. It is one file with one
# function in it, named here for the same reason the two shipping call sites are: so that a
# second one anywhere still fails the gate.
check_outside "R-96e" "NSApp.activate appears only where the person summoned the app" \
    'NSApp\.activate\(|NSApplication\.shared\.activate\(|activateIgnoringOtherApps' \
    App Packages \
    --allow Packages/FocusUI/Sources/FocusUI/Capture/QuickCapturePanelController.swift \
    --allow Packages/FocusHost/Sources/FocusHost/SelfCheck.swift \
    --allow Packages/FocusHost/Tests/FocusHostTests/MenuBarStage.swift

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

# R-96o — the subject slot's content, which nothing guarded (focus-ebv).
#
# A "drawing line" is one carrying `arguments:` — the slot list every deck line is substituted
# through — or `Text(verbatim:`, which is how the popover's Snoozed row draws its subject. A
# drawing line that names a subject must name the display half and must not name the key.
check_subject_slot() {
    local paths
    paths=(${(f)"$(existing_paths "${NUDGE_SURFACES[@]}")"})
    if (( ${#paths} == 0 )) || [[ -z "${paths[1]}" ]]; then
        print -u2 "FAIL [R-96o] no nudge surface files to search — the check would pass vacuously"
        rc=1
        return
    fi
    print "     [R-96o] searching: ${paths[*]}"

    local drawn
    drawn=$(grep -rnE --include='*.swift' --exclude-dir='.build' \
        'arguments:|Text\(verbatim:' "${paths[@]}" 2>/dev/null \
        | strip_comments | grep -i 'subject')

    if [[ -z "$drawn" ]]; then
        # Non-vacuity. Four user-visible surfaces draw a subject; a search that finds none has
        # lost its target and must not report success.
        print -u2 "FAIL [R-96o] no drawn subject found in any nudge surface — the check is blind"
        rc=1
        return
    fi

    local without_name with_key
    without_name=$(print -r -- "$drawn" | grep -v 'displayName')
    with_key=$(print -r -- "$drawn" | grep 'identifier')

    if [[ -n "$without_name" ]]; then
        print -u2 "FAIL [R-96o] a nudge draws a subject without its display half"
        print -u2 "$without_name" | sed 's/^/    /'
        print -u2 "    A rule keyed on a display name is not a rule — and a SENTENCE naming a"
        print -u2 "    storage key is not a sentence. Draw subject.displayName (focus-ebv)."
        rc=1
    else
        print "ok   [R-96o] every drawn subject draws its display half"
    fi

    if [[ -n "$with_key" ]]; then
        print -u2 "FAIL [R-96o] a nudge draws a subject's bundle identifier"
        print -u2 "$with_key" | sed 's/^/    /'
        rc=1
    else
        print "ok   [R-96o] no drawn subject names the key it is filed under"
    fi

    # The third half. A view that never names a key cannot draw one, however the expression is
    # spelled or aliased. Each file is required to exist: a renamed view that quietly dropped
    # out of this list would take its ban with it.
    local file keys
    for file in $NUDGE_DRAWING_FILES; do
        if [[ ! -f "$file" ]]; then
            print -u2 "FAIL [R-96o] the nudge drawing file $file is missing"
            rc=1
            continue
        fi
        # `-H`, not `-n` alone: `strip_comments` matches on grep's `path:line:` form, and a
        # single-file grep omits the path — so without this every doc comment quoting the rule
        # would be read as a violation of it.
        keys=$(grep -HnE '\.identifier\b|identifier:' "$file" | strip_comments | grep '[^[:space:]]')
        if [[ -n "$keys" ]]; then
            print -u2 "FAIL [R-96o] $file names a storage key"
            print -u2 "$keys" | sed 's/^/    /'
            print -u2 "    A view draws names and reports values; which half keys a rule is the"
            print -u2 "    host's business (focus-ebv)."
            rc=1
        else
            print "ok   [R-96o] $file names no storage key"
        fi
    done
}

check_subject_slot

# R-96g — **nowhere, now** (focus-wy0). It was `count_at_most … 1`: the call was permitted in the
# Intervention pane's user-initiated button and nowhere else. The button asked for a permission
# this app cannot use — no rung has routed to a notification since U-2 — so it was deleted, and
# the bound is tightened to zero rather than left at one with nothing under it. A bound of one
# over an empty set is an invitation: the next round that wants a prompt finds the lint already
# green and adds one. focus-5ab, which brings the recommitment rung back, must amend this line
# deliberately and beside the rung that would justify it.
#
# The pattern keeps its trailing `(` so it cannot fire on `requestAuthorizationCallCount`, the
# honest reporting name the self-check publishes and the number this whole condition exists to
# make meaningful.
check "R-96g" "requestAuthorization is called nowhere in the repository" \
    'requestAuthorization\('

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
# ## Two corrections, both measured on this tree (focus-gtr)
#
# **1. The Debug row was reading a 58 KB dyld stub.** The list named
# `Build/Products/Debug/FocusSentinel.app/Contents/MacOS/FocusSentinel`, and on this toolchain
# that file is not the app: Xcode's debug-dylib layout leaves a launcher there whose entire
# undefined-symbol table is thirty libSystem names — `_dlopen`, `_printf`, `_memcpy` — and puts
# every line of the application in `FocusSentinel.debug.dylib` beside it. So the strongest form of
# standing condition 1 printed `ok … does not reference kCGWindowName` on every gate run for a
# file that references nothing at all, and would have gone on printing it with the banned key
# written into `App/` in plain sight. The Release product is the merged one and does carry the
# seven sanctioned symbols, and **Release was not in the list**.
#
# So the app's executable code is *resolved* per configuration rather than named, both files are
# banned when both exist, and the **control below is what proves one of them is code**.
#
# **2. `FocusHost.o` was missing.** The comment here read "P-108 measured that the five below are
# the complete set of package objects". Six packages ship: `FocusHost` — the composition root,
# which is where the on-screen authorisation-surface scan reads the window list — was added after
# that measurement and inherited no row.
#
# The object list is EXPLICIT, not a glob. A glob plus an "at least one binary was seen" counter
# is not the claim "every package object is clean": a build that emits five objects, or a seventh
# package whose product is not named Focus*, would slip through it in silence. Adding a package
# therefore fails this gate until its object is named here — which is exactly the review moment a
# new package deserves (R-31).
print
print "== SC-1: the binary half"

# The app's executable code, per configuration, resolved rather than assumed. Both files are
# checked when both exist; which one carries the code is what the control decides.
app_code_files() {
    local config="$1" app path
    app="$DERIVED_DATA/Build/Products/$config/FocusSentinel.app/Contents/MacOS"
    for path in "$app/FocusSentinel" "$app/FocusSentinel.debug.dylib"; do
        [[ -f "$path" ]] && print -r -- "$path"
    done
}

SC1_REQUIRED=()
for config in Debug Release; do
    SC1_REQUIRED+=(${(f)"$(app_code_files $config)"})
    SC1_REQUIRED+=(
        "$DERIVED_DATA/Build/Products/$config/FocusCore.o"
        "$DERIVED_DATA/Build/Products/$config/FocusSensing.o"
        "$DERIVED_DATA/Build/Products/$config/FocusRules.o"
        "$DERIVED_DATA/Build/Products/$config/FocusClassify.o"
        "$DERIVED_DATA/Build/Products/$config/FocusUI.o"
        "$DERIVED_DATA/Build/Products/$config/FocusHost.o"
    )
done
SC1_REQUIRED+=(Tools/windowid/.build/release/windowid)
SC1_REQUIRED=(${SC1_REQUIRED:#})

# The four keys the sanctioned readers really do take. Present-ness is asserted, not merely
# absence of the banned one — see the control below.
SC1_SANCTIONED_SYMBOLS=(
    _kCGWindowBounds _kCGWindowLayer _kCGWindowNumber _kCGWindowOwnerName
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
        print "ok   [SC-1] ${binary:t} (${binary:h:t}) does not reference kCGWindowName"
    fi
done

# --- the control, and it is what the Debug row was missing -------------------------------------
#
# An absence check over an undefined-symbol table is satisfied by a table with nothing in it. The
# `windowid` half of this control has existed since e03 — *"an SC-1 check that passes because
# windowid was gutted is a check that proves nothing"* — and the identical hazard on the app's own
# product was uncovered by nothing, which is how a 58 KB launcher came to be the file the gate
# read. So every artefact that is *supposed* to reach the window list must still be seen reaching
# it, by name, with the four sanctioned symbols the reader really takes.
#
# `FocusSensing.o` is where `SystemWindowList` compiles to. The app's code is wherever this
# toolchain put it, so the assertion is that **at least one** of the resolved app files per
# configuration carries all four — which is the reading that makes the ban above a statement about
# code rather than about a stub.
sc1_control_run=0
for symbol in $SC1_SANCTIONED_SYMBOLS; do
    if [[ -f Tools/windowid/.build/release/windowid ]]; then
        sc1_control_run=1
        if nm -u Tools/windowid/.build/release/windowid 2>/dev/null | grep -q "^${symbol}\$"; then
            print "ok   [SC-1] control: windowid still reads $symbol"
        else
            print -u2 "FAIL [SC-1] windowid no longer reads $symbol — the tool has been gutted"
            rc=1
        fi
    fi
done

for config in Debug Release; do
    sensing_object="$DERIVED_DATA/Build/Products/$config/FocusSensing.o"
    if [[ -f "$sensing_object" ]]; then
        sc1_control_run=1
        sensing_symbols=$(nm -u "$sensing_object" 2>/dev/null)
        for symbol in $SC1_SANCTIONED_SYMBOLS; do
            if print -r -- "$sensing_symbols" | grep -q "^${symbol}\$"; then
                print "ok   [SC-1] control: $config FocusSensing.o still reads $symbol"
            else
                print -u2 "FAIL [SC-1] $config FocusSensing.o no longer reads $symbol"
                print -u2 "    The object the window reader compiles into has stopped naming the"
                print -u2 "    keys it takes, so the ban above is a statement about nothing."
                rc=1
            fi
        done
    fi

    app_files=(${(f)"$(app_code_files $config)"})
    app_files=(${app_files:#})
    if (( ${#app_files} == 0 )); then
        if [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
            print -u2 "FAIL [SC-1] FOCUS_REQUIRE_BINARY_CHECK=1 but the $config app has no executable"
            rc=1
        fi
        continue
    fi
    sc1_control_run=1
    carrier=""
    for candidate in $app_files; do
        candidate_symbols=$(nm -u "$candidate" 2>/dev/null)
        missing=0
        for symbol in $SC1_SANCTIONED_SYMBOLS; do
            print -r -- "$candidate_symbols" | grep -q "^${symbol}\$" || missing=1
        done
        (( missing == 0 )) && carrier="$candidate"
    done
    if [[ -n "$carrier" ]]; then
        print "ok   [SC-1] control: the $config app's code is in ${carrier:t} and it reads the"
        print "     four sanctioned window keys — so the ban above was applied to code"
    else
        print -u2 "FAIL [SC-1] no $config app file reads the four sanctioned window keys"
        print -u2 "    Files examined: ${app_files:t}"
        print -u2 "    Every one of them is a launcher or a stub, so 'does not reference"
        print -u2 "    kCGWindowName' was true of a file with no application code in it. That is"
        print -u2 "    the defect focus-gtr found: the Debug row read a 58 KB dyld shim."
        rc=1
    fi
done

if (( sc1_control_run == 0 )) && [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
    print -u2 "FAIL [SC-1] the non-vacuity control ran against nothing at all"
    rc=1
fi

if (( sc1_binaries_seen == 0 )) && [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" != "1" ]]; then
    print "     [SC-1] binary half SKIPPED — nothing built yet (the gate re-runs this after the build)"
fi

# --- R-96s: SC-5's binary half — the shipped app cannot post a notification -------------------
#
# **What this exists to stop, and why the source lint is not enough.** U-2 ruled that no rung
# routes to a notification. Three proofs already cover the ROUTER — the 160-cell fold the binary
# runs, `SurfaceRouterTests.noCellReachesANotification`, and the pinned `surfacesARungCanReach`
# — and not one of them says anything about a path that reaches `UNUserNotificationCenter`
# *without* asking the router. `check-boundaries.sh` still permits `UserNotifications` for
# `FocusUI`, because the boundary must go on decoding a press on a banner an earlier build
# posted. So a future round could reinstate a posting call, pass every fold in the programme,
# and fail nothing.
#
# Selectors, not source text. An Objective-C selector referenced by Swift is emitted into
# `__TEXT,__objc_methname`, so it survives every way of spelling the call. Measured on the
# Release Mach-O of this tree: all five banned names absent; `currentNotificationCenter` 2,
# `getNotificationSettingsWithCompletionHandler:` 2, `UNUserNotificationCenter` 14.
#
# **Both configurations**, and the Release one is the artefact this programme ships — the whole
# finding behind this rule is that the Release lane's readings were the weakest in the gate.
print
print "== R-96s: SC-5's binary half — no notification-posting selector in the shipped app"

# The names a posting path cannot avoid: the two `add(_:)` selectors, the category registration
# the app stopped making, the request that would prompt, and the two content/request classes a
# banner has to be built out of.
NOTIFICATION_POSTING_SELECTORS=(
    addNotificationRequest
    setNotificationCategories
    requestAuthorizationWithOptions
    UNMutableNotificationContent
    UNNotificationRequest
)
# The control, and it is the load-bearing half of this check. A binary that dropped
# UserNotifications entirely would carry none of the banned names either, and would pass a ban
# that had become a statement about nothing. The app's remaining relationship with the
# notification centre is LISTENING, and these are what listening leaves behind.
NOTIFICATION_READING_SELECTORS=(
    currentNotificationCenter
    getNotificationSettingsWithCompletionHandler
)

# **The app's executable code, resolved rather than named** — the same correction SC-1 above
# needed and for the same measured reason. Naming `Contents/MacOS/FocusSentinel` would aim the
# Debug half of this ban at a 58 KB dyld launcher whose whole symbol table is libSystem, and the
# control below would then fail for the launcher rather than pass for the app. `app_code_files`
# returns both files when the debug-dylib layout is in use, so the ban covers the launcher too and
# the control finds the code wherever the toolchain put it.
#
# **And the control is judged per configuration, not once for the pair.** A single flag across
# both lanes is satisfied by whichever lane still carries a reading selector, so a Release build
# that dropped `UserNotifications` entirely would pass a ban that had become a statement about
# nothing — vouched for by the Debug binary beside it. The Release product is the artefact this
# programme ships and it must answer for itself.
r96s_binaries_seen=0
for config in Debug Release; do
    r96s_config_binaries=(${(f)"$(app_code_files $config)"})
    r96s_config_binaries=(${r96s_config_binaries:#})
    if (( ${#r96s_config_binaries} == 0 )); then
        r96s_config_binaries=(
            "$DERIVED_DATA/Build/Products/$config/FocusSentinel.app/Contents/MacOS/FocusSentinel"
        )
    fi

    r96s_config_files_seen=0
    r96s_reading_seen=0
    for binary in $r96s_config_binaries; do
        if [[ ! -f "$binary" ]]; then
            if [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" == "1" ]]; then
                print -u2 "FAIL [R-96s] FOCUS_REQUIRE_BINARY_CHECK=1 but $binary does not exist"
                rc=1
            else
                print "     [R-96s] $binary not built yet — the gate re-runs this after the build"
            fi
            continue
        fi
        r96s_binaries_seen=$(( r96s_binaries_seen + 1 ))
        r96s_config_files_seen=$(( r96s_config_files_seen + 1 ))
        binary_strings=$(strings -a -- "$binary" 2>/dev/null)

        # The configuration is named in every line, because `${binary:t}` is `FocusSentinel` in
        # both lanes and a log in which Debug and Release read identically is a log in which one
        # of them can go missing unnoticed.
        for selector in $NOTIFICATION_POSTING_SELECTORS; do
            hits=$(print -r -- "$binary_strings" | grep -c -F -- "$selector")
            if (( hits > 0 )); then
                print -u2 "FAIL [R-96s] ${binary:t} ($config) carries $selector ($hits) — it can post a notification"
                rc=1
            else
                print "ok   [R-96s] ${binary:t} ($config) carries no $selector"
            fi
        done

        # The control, counted per FILE and judged per CONFIGURATION below. A launcher carries
        # neither the banned names nor the reading ones, so demanding the control of every file
        # would fail for the stub while the ban passed for it — the two halves of one wrong subject.
        for selector in $NOTIFICATION_READING_SELECTORS; do
            hits=$(print -r -- "$binary_strings" | grep -c -F -- "$selector")
            if (( hits > 0 )); then
                print "ok   [R-96s] control: ${binary:t} ($config) still reads the centre via $selector ($hits)"
                r96s_reading_seen=1
            fi
        done
    done

    # The control's verdict, for THIS configuration. At least one of the files examined for it
    # must still carry the reading half of the boundary: a binary that dropped
    # `UserNotifications` entirely would carry none of the banned names either, and would pass a
    # ban that had become a statement about nothing.
    if (( r96s_config_files_seen > 0 )) && (( r96s_reading_seen == 0 )); then
        print -u2 "FAIL [R-96s] no examined $config binary carries a notification-READING selector"
        print -u2 "    The app's remaining relationship with the notification centre is listening —"
        print -u2 "    getNotificationSettings and a delegate that receives a press. With neither in"
        print -u2 "    the artefact, the ban above is true of a binary that has no boundary at all."
        rc=1
    fi
done

if (( r96s_binaries_seen == 0 )) && [[ "${FOCUS_REQUIRE_BINARY_CHECK:-0}" != "1" ]]; then
    print "     [R-96s] SKIPPED — nothing built yet (the gate re-runs this after the build)"
fi

print
if (( rc == 0 )); then
    print "FORBIDDEN-SYMBOL LINT OK"
else
    print -u2 "FORBIDDEN-SYMBOL LINT FAILED"
fi
exit $rc
