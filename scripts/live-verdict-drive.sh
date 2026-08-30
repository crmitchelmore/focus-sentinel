#!/bin/zsh
# The live verdict drive — TCC-GATED EVIDENCE, never a gate (§4.8).
#
#   scripts/live-verdict-drive.sh
#
# Runs the real app on this Mac, sets a real priority, opens a real decoy application in front
# of it, and captures the verdict surface at settle points across the grace period and past the
# sustained-drift threshold. The PNGs are then **read**, by eye. Capturing is not the point;
# reading is, and what is being read is not *"did it draw"* but *"is the explanation
# restrained"* — no title, no URL, no number, no accusation: the clause list and nothing else.
#
# ## Why this can never be a gate
#
# Standing condition 5: no acceptance criterion may depend on a TCC grant. Capturing another
# process's window needs Screen Recording on the **driving shell**, so a criterion that passed
# here would fail on a Mac where that is revoked, for a reason with nothing to do with the code.
# When a grant is missing this script prints `LIVE-LANE SKIPPED: <grant>` and exits **0**, and
# `scripts/build-gate.sh` never invokes it.
#
# The half of e04's contract that must hold regardless — the engine stamp, the policy digest,
# the snapshot having been built, the engine having actually judged, and the eligibility being
# exactly one of mandated or suppressed-with-a-reason — is asserted at zero grants by
# `scripts/self-check.sh`, which is stages 9a and 9b of the gate.
#
# ## Past the threshold, the ladder is raised — and this lane has not been re-captured since
#
# **This narration is e04's and its frames are e04's** (focus-lmy). It was written when the
# mandate was consumed by nobody, so step 5 below says the screen is unchanged past the
# threshold. That stopped being true at e05: `RelevanceHost` hands the same eligibility to
# `NudgeHost`, which enters the ladder at the ambient glyph and escalates to the panel. What
# appears in that frame now depends on the interruption budget and the slot, so this lane
# describes what it captured rather than asserting an outcome, and the committed PNGs under
# `.agents/evidence/e04/live` are from the older build. Re-capturing them is filed as focus-t3e.
#
# ## No `osascript`, anywhere, including here
#
# §4.8 of the plan says *"foregrounds a decoy by `osascript`"*. This lane does not, and the
# reason is measured rather than stylistic: probe P-103 reproduced e02's P-65 exactly —
# `osascript -e 'quit app "TextEdit"'` blocks on Automation consent and has to be killed — which
# is why e03's shipped lanes open applications with `open -a` (LaunchServices, no TCC) and
# terminate them with `pkill` (POSIX, no TCC). Following the plan's letter here would make the
# lane hang on a machine that has not granted Automation, which is precisely the dependency
# standing condition 5 exists to forbid. The *intent* — a real decoy really coming forward — is
# met exactly.
#
# ## Three labels, and this script behaves differently for each (plan R-51)
#
#   AUTOMATED               produced unattended, given Screen Recording
#   OPERATOR-ASSISTED       a human performs one physical action at a prompt; on timeout the
#                           script writes <artefact>.MANUAL_REQUIRED.txt naming what was not done
#
# A missing artefact with a receipt is honest; a missing artefact with silence is the failure
# this rule exists to prevent. No receipt ever affects the exit status.
#
# ## Why two of the steps need a person
#
# Setting a priority and attaching a context chip are things a person does in the cockpit, and
# with no sanctioned way to send a click or a keystroke (see the no-`osascript` note above) there
# is no way to do them unattended. The priority itself can at least be *offered* to the app
# through the shipped `focus://` handoff URL, which `open` delivers with no grant — but F-142 is
# explicit that there is no route from a URL to a store mutation that does not pass through a
# person pressing **Replace**, and that is a feature rather than an obstacle.
#
# **The unattended run is still worth having, and it is worth being precise about why.** With no
# priority and no context pack the engine reaches R-56.1's negative-basis gate and declines at
# every dwell — so an unattended run captures the *decline*, which is the single most important
# behaviour in this epic. The operator-assisted run captures the other half: the same engine
# resolving `unrelated` once the person has told it one thing they expect to be looking at.
#
# ## Environment
#
#   FOCUS_EVIDENCE_DIR   where the artefacts land   (default .agents/evidence/e04/live)
#   FOCUS_DERIVED_DATA   build location             (default /tmp/focus-dd)
#   FOCUS_LOG_DIR        log location               (default /tmp)
#   FOCUS_OPERATOR_TIMEOUT  seconds to wait at each operator prompt (default 45)
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

EVIDENCE_DIR="${FOCUS_EVIDENCE_DIR:-.agents/evidence/e04/live}"
DD="${FOCUS_DERIVED_DATA:-/tmp/focus-dd}"
LOG_DIR="${FOCUS_LOG_DIR:-/tmp}"
DESTINATION='platform=macOS,arch=arm64'
OPERATOR_TIMEOUT="${FOCUS_OPERATOR_TIMEOUT:-45}"

# Two names for the same application, both measured rather than assumed (e01's live lane):
# `CGWindowListCopyWindowInfo` reports "Focus Sentinel" in `kCGWindowOwnerName`, and the process
# `pkill -x` matches is "FocusSentinel".
WINDOW_OWNER='Focus Sentinel'
PROCESS_NAME='FocusSentinel'
APP="$DD/Build/Products/Debug/FocusSentinel.app"

# The decoy: a stock system application that is in no rule, no context pack and no seed row, and
# whose bundle-identifier tokens share nothing with the priority below. `open -a` starts it and
# `pkill` stops it; neither needs a grant of any kind.
DECOY='Calculator'

# The priority the operator is asked to accept, and the application they are asked to attach.
# Chosen to be the plan's own worked example, so the frames can be read against §4.8 directly.
PRIORITY_INTENT='Write the Q3 proposal for Acme'
PRIORITY_DONE_WHEN='sent to Dana'
CONTEXT_APP='TextEdit'

# The engine's own thresholds, restated here as *drive timings* rather than as policy. They are
# read from the committed constant set below rather than typed twice, so a lane that waits for a
# threshold cannot drift from the threshold it is waiting for.
POLICY='Packages/FocusCore/Sources/FocusCore/Relevance/RelevancePolicy.swift'

# `public static let <name>: Duration = .seconds(<n>)` → `<n>`. Empty when the constant is not
# found, which the preflight below turns into a loud failure rather than a silent zero — a lane
# that waited zero seconds for a ninety-second threshold would file frames of the wrong moment
# and call them evidence.
#
# The parentheses are backslash-escaped inside the pattern: in zsh a bare `(` in a `${…##pat}`
# pattern is a glob grouping metacharacter, not a literal, and an unescaped one is a
# `bad pattern` error rather than a non-match. Measured here the first time this ran.
policy_seconds() {
    local name="$1" line
    line=$(grep -E "static let ${name}\b" "$POLICY" 2>/dev/null | head -1)
    [[ -n "$line" ]] || return 0
    line="${line##*seconds\(}"
    print -r -- "${line%%\)*}"
}

SUSTAINED_DRIFT="$(policy_seconds sustainedDriftThreshold)"
DRIFT_RESET_GRACE="$(policy_seconds driftResetGrace)"

mkdir -p -- "$EVIDENCE_DIR" "$LOG_DIR" || exit 1

# --- the artefact ledger ------------------------------------------------------------------

typeset -a PRODUCED RECEIPTS
PRODUCED=()
RECEIPTS=()

note() { print "== $*" }
skip() { print "LIVE-LANE SKIPPED: $*"; exit 0 }

produced() {
    PRODUCED+=("$1")
    print "LIVE-ARTEFACT $2: $1"
}

manual_required() {
    local artefact="$1" reason="$2" steps="$3"
    RECEIPTS+=("$artefact")
    print "LIVE-ARTEFACT OPERATOR-ASSISTED: $artefact — $reason"
    {
        print "MANUAL_REQUIRED: $artefact"
        print "label:  OPERATOR-ASSISTED"
        print "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        print "host:   $(sw_vers -productVersion) ($(uname -m))"
        print
        print "why this run did not produce it"
        print -r -- "-------------------------------"
        print "$reason"
        print
        print "how to reproduce it"
        print -r -- "-------------------"
        print "$steps"
    } > "$EVIDENCE_DIR/${artefact}.MANUAL_REQUIRED.txt"
}

# One physical action, asked for once, with a timeout. An unattended run reaches the timeout
# immediately — there is no terminal to read from — and files the receipt, which is exactly what
# should happen: the alternative is a lane that hangs a nightly run for ever.
prompt_operator() {
    local instruction="$1"
    print
    print "OPERATOR: $instruction"
    print "OPERATOR: press Return within ${OPERATOR_TIMEOUT}s when it is done, or wait to skip."
    local answer
    if read -t "$OPERATOR_TIMEOUT" -r answer; then
        return 0
    fi
    print
    return 1
}

cleanup() {
    pkill -x "$PROCESS_NAME" 2>/dev/null
    pkill -x "$DECOY" 2>/dev/null
    pkill -x "$CONTEXT_APP" 2>/dev/null
    return 0
}
trap 'cleanup' EXIT INT TERM

SCREENCAPTURE="${commands[screencapture]:-/usr/sbin/screencapture}"
LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

# Nothing from a previous run may survive into this one. A frame this drive fails to take must
# be **absent**, not last week's picture of a different state.
ARTEFACTS=(
    verdict-timeline.txt
    verdict-report.json
    01-priority-set.png
    02-decoy-grace-1.png
    03-decoy-grace-2.png
    04-decoy-grace-3.png
    05-decoy-past-threshold.png
    06-returned-to-anchor.png
    07-context-removed.png
)
for artefact in $ARTEFACTS; do
    rm -f -- "$EVIDENCE_DIR/$artefact" "$EVIDENCE_DIR/${artefact}.MANUAL_REQUIRED.txt"
done

# --- 0 · preflight -------------------------------------------------------------------------
#
# `windowid --grants` calls `AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()`. Both
# are *preflight* calls: this script never puts a permission dialog in front of anybody.
#
# Only Screen Recording is required. Accessibility is not, which is the whole point of the
# no-`osascript` rule: this lane never drives another process, so it never needs to be trusted
# to.

if [[ -z "$SUSTAINED_DRIFT" || -z "$DRIFT_RESET_GRACE" ]]; then
    print -u2 "LIVE-LANE ERROR: could not read the drift thresholds out of $POLICY"
    exit 1
fi
print "thresholds read from the committed constant set:"
print "  sustainedDriftThreshold = ${SUSTAINED_DRIFT}s"
print "  driftResetGrace         = ${DRIFT_RESET_GRACE}s"

note "building the window-id test driver"
swift build --package-path Tools/windowid > "$LOG_DIR/focus-live-verdict-windowid.log" 2>&1
build_rc=$?
print "windowid build EXIT=$build_rc log=$LOG_DIR/focus-live-verdict-windowid.log"
(( build_rc == 0 )) || { print -u2 "LIVE-LANE ERROR: could not build Tools/windowid"; exit 1 }

WINDOWID="$(swift build --package-path Tools/windowid --show-bin-path 2>/dev/null)/windowid"
[[ -x "$WINDOWID" ]] || { print -u2 "LIVE-LANE ERROR: no windowid binary at $WINDOWID"; exit 1 }

note "TCC preflight"
grants="$("$WINDOWID" --grants)"
print "$grants"
[[ "$grants" == *"screen-recording=yes"* ]] || skip "Screen Recording not granted to the driving shell"
[[ -x "$SCREENCAPTURE" ]] || skip "no screencapture binary at $SCREENCAPTURE"

# --- 1 · build the app ---------------------------------------------------------------------

note "building the Debug app"
xcodebuild -workspace Focus.xcworkspace -scheme FocusSentinel \
    -configuration Debug -destination "$DESTINATION" -derivedDataPath "$DD" build \
    > "$LOG_DIR/focus-live-verdict-build.log" 2>&1
app_rc=$?
print "build EXIT=$app_rc log=$LOG_DIR/focus-live-verdict-build.log"
(( app_rc == 0 )) || { print -u2 "LIVE-LANE ERROR: the Debug build failed"; exit 1 }
[[ -d "$APP" ]] || { print -u2 "LIVE-LANE ERROR: no app bundle at $APP"; exit 1 }

BINARY="$APP/Contents/MacOS/FocusSentinel"

# --- helpers --------------------------------------------------------------------------------
#
# Never `local path=…` in zsh: `path` is tied to `PATH`, so a local assignment to it empties the
# command search path for the whole call. Measured the hard way in e01's live lane.

# Every layer-0 window the app owns, front to back, one id per line. Zero is a failure; several
# is fine here and is in fact what the interesting frames need — the cockpit **and** the
# Settings window carrying the verdict inspector.
app_window_ids() {
    local lines
    lines="$("$WINDOWID" "$WINDOW_OWNER" 2>/dev/null)"
    [[ -n "$lines" ]] || return 1
    print -r -- "$lines" | while read -r id rest; do print -r -- "$id"; done
}

# Capture every window the app owns into one frame set. The first window is filed under the
# artefact's own name; any further ones gain a `-2`, `-3` suffix, so a run in which the operator
# opened Settings ▸ Privacy files the inspector beside the cockpit rather than instead of it.
#
# **There is no "use the front-most entry" fallback anywhere in this file.** e02's lane learned
# that the hard way: a 900×704 picture of the cockpit filed as the quick-capture panel. A frame
# that shows the wrong window is worse than a missing frame.
capture_windows() {
    local artefact="$1" index=0 target rc=1 id
    for id in ${(f)"$(app_window_ids)"}; do
        (( index += 1 ))
        if (( index == 1 )); then
            target="$EVIDENCE_DIR/$artefact"
        else
            target="$EVIDENCE_DIR/${artefact%.png}-$index.png"
        fi
        "$SCREENCAPTURE" -x -o -l "$id" "$target" 2>/dev/null || continue
        [[ -s "$target" ]] || continue
        produced "${target:t}" "AUTOMATED"
        rc=0
    done
    return $rc
}

# What the app says about its own engine, at zero grants, from inside its own process.
#
# **Read what this is and is not.** It launches a *second, short-lived* instance, so the
# `judgementCount` and `verdict` blocks describe **that** process rather than the one being
# driven: a fresh launch has judged whatever was frontmost for a second or two, not the drift
# sequence below. What is process-independent — and is the reason this artefact exists — is the
# `engineStamp`, the `policyDigest`, `classifierIsEngine`, and the shape of the verdict block a
# reader compares the frames against.
#
# The second instance also comes to the front, which is an activation the running instance will
# observe. So it is called exactly twice: once before the drift sequence begins and once after
# it ends. Calling it between settle points would make the instrument change the thing it is
# measuring, which is a worse defect than the missing datum. **The drift sequence itself is read
# from the frames**, which is the charter's tmux-verify doctrine and the point of the lane.
export_verdict() {
    local destination="$1"
    "$BINARY" --focus-self-check "$destination" \
        > "$LOG_DIR/focus-live-verdict-report.log" 2>&1 || return 1
    [[ -s "$destination" ]] || return 1
    return 0
}

# One line of the timeline a reader checks the frames against.
timeline() {
    print -r -- "$1" >> "$EVIDENCE_DIR/verdict-timeline.txt"
    print -r -- "TIMELINE $1"
}

# --- 2 · launch ------------------------------------------------------------------------------

note "launching the app"
cleanup
sleep 1
open -a "$APP"
sleep 4

if ! app_window_ids > /dev/null; then
    print -u2 "LIVE-LANE ERROR: the app put no layer-0 window on screen"
    exit 1
fi

{
    print "LIVE VERDICT DRIVE — read evidence, never a gate (§4.8)"
    print "date:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    print "host:  $(sw_vers -productVersion) ($(uname -m))"
    print "app:   $APP"
    print
    print "sustainedDriftThreshold=${SUSTAINED_DRIFT}s  driftResetGrace=${DRIFT_RESET_GRACE}s"
    print
    print "What to read in each frame: the status glyph and label, the rung that decided, the"
    print "band, the drift clock, and the explanation clauses. What must NOT be in any of them:"
    print "a window title, a URL, a file path, a similarity number, or an accusation."
    print
} > "$EVIDENCE_DIR/verdict-timeline.txt"

# --- 3 · the priority and its context pack (OPERATOR-ASSISTED) --------------------------------
#
# Offered through the shipped `focus://` handoff, which `open` delivers with no grant. F-142 is
# explicit that the only non-rejection outcome of a parse is *show the sheet*: there is no route
# from a URL to a store mutation that does not pass through a person pressing Replace.

note "offering the priority through the shipped focus:// handoff"
# `focus://start?task=…&doneWhen=…` — the one verb the allowlist knows (F-142). The keys are
# `task` and `doneWhen`; `HandoffRequest.knownQueryKeys` is the source of truth and an unknown
# key is a rejection rather than a warning, so getting these wrong fails loudly.
HANDOFF="focus://start?task=${PRIORITY_INTENT// /%20}&doneWhen=${PRIORITY_DONE_WHEN// /%20}"
print "handoff URL: $HANDOFF"

# **Best effort, and a failure here is not an error.** Measured on this rig: a product sitting
# in a derived-data tree is not a LaunchServices handler for `focus://`, so `open` answers
# `kLSApplicationNotFoundErr` — which is e02's P-59 finding in a different costume (a bundle
# under a temporary path registers and still resolves to nothing). Registering it in place is
# offered because it costs nothing and sometimes works; when it does not, the operator sets the
# priority the way a person actually does, in the cockpit, and the prompt below says so.
#
# The whole `~/Applications` install-and-unregister apparatus e02's handoff lane needs is
# deliberately **not** reproduced here: this lane is about the verdict, not about URL binding,
# and leaving a stale registration behind so that a person's own `focus://` links point at a
# derived-data build would be a real cost for a convenience.
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$APP" > "$LOG_DIR/focus-live-verdict-lsregister.log" 2>&1
    print "lsregister -f EXIT=$? (best effort; the operator prompt does not depend on it)"
fi
if open "$HANDOFF" 2>> "$LOG_DIR/focus-live-verdict-handoff.log"; then
    print "the handoff sheet was offered — the operator still has to press Replace (F-142)"
else
    print "no LaunchServices handler for focus:// on this rig; set the priority by hand instead"
fi
sleep 2

HAS_PRIORITY=0
if prompt_operator "set the priority to “$PRIORITY_INTENT” — press Replace if the handoff sheet is up, otherwise press ⌃⌘Space and type it — then attach $CONTEXT_APP to the priority as an app context chip, then open Settings ▸ Privacy (⌘,) and scroll to 'What Focus thinks right now'."; then
    HAS_PRIORITY=1
    timeline "operator set the priority and attached one app context chip"
else
    manual_required "01-priority-set.png" \
        "no operator was at the keyboard, so this run neither set the priority nor attached a context chip. Whatever priority the app already held is what the frames below were taken against — read the timeline, which records what the engine actually reported rather than what this run intended." \
        "Run this script attended. At the prompt: press Replace (or ⌃⌘Space and type the priority), drag $CONTEXT_APP onto the context row, then press ⌘, and select Privacy. The remaining frames are still captured and still meaningful — with no negative basis the engine declines at every dwell (R-56.1), which is the behaviour those frames then show."
    timeline "UNATTENDED: this run set no priority and attached no context chip"
fi

note "recording what the engine concluded, before the drift sequence"
if export_verdict "$EVIDENCE_DIR/verdict-report.json"; then
    produced "verdict-report.json" "AUTOMATED"
    # Recorded rather than assumed. This lane cannot know what the app already held — the store
    # belongs to the person — so the timeline says what the engine *reported* instead of what
    # the run intended, and a reader checks the frames against that.
    timeline "$(python3 - "$EVIDENCE_DIR/verdict-report.json" <<'PYTHON'
import json, sys

report = json.load(open(sys.argv[1]))
relevance = report.get("relevance") or {}
verdict = relevance.get("verdict") or {}
print(
    "engine {stamp} · policy {digest} · verdict {status}"
    " · rung {stage} · band {band}"
    " · mandated {mandated} · clauses {clauses}".format(
        stamp=relevance.get("engineStamp", "?"),
        digest=relevance.get("policyDigest", "?"),
        status=verdict.get("status", "none"),
        stage=verdict.get("stage", "none"),
        band=verdict.get("band") or "none",
        mandated=verdict.get("isMandated"),
        clauses=",".join(verdict.get("clauses", [])) or "none",
    )
)
PYTHON
)"
else
    print -u2 "LIVE-LANE WARNING: could not export the app's own verdict report"
fi
# The export brought a second instance forward; give the running one a tick to settle back.
sleep 6

capture_windows "01-priority-set.png"
timeline "01 · priority set, nothing drifting yet"

# --- 4 · the decoy comes forward --------------------------------------------------------------
#
# A real application, really opened, really in front. It is in no rule, no context pack and no
# seed row, and its bundle-identifier tokens share nothing with the priority.

note "opening the decoy: $DECOY"
open -a "$DECOY"
sleep 2
timeline "decoy $DECOY brought forward"

# Three settle points across the grace period. The engine mandates at the first observation
# **strictly after** the threshold, so all three of these are inside it and none may nudge.
GRACE_STEPS=(
    "02-decoy-grace-1.png"
    "03-decoy-grace-2.png"
    "04-decoy-grace-3.png"
)
step_index=0
for artefact in $GRACE_STEPS; do
    (( step_index += 1 ))
    # Evenly spaced inside the threshold, computed from it rather than typed: a quarter, a half
    # and three quarters of the way to the line.
    sleep $(( SUSTAINED_DRIFT / 4 ))
    capture_windows "$artefact"
    timeline "$artefact · ~$(( SUSTAINED_DRIFT * step_index / 4 ))s of drift — inside the grace period, nothing may be said"
done

# Past the line. The engine may now speak and e05's ladder is what it speaks with, so this frame
# is whatever the ladder raised — the ambient glyph, or the panel if it had already escalated.
sleep $(( SUSTAINED_DRIFT / 4 + 6 ))
capture_windows "05-decoy-past-threshold.png"
timeline "05 · past ${SUSTAINED_DRIFT}s of drift — the engine may now speak, and the ladder is what it speaks with"

# --- 5 · the return ---------------------------------------------------------------------------
#
# Back to the application the person attached to the priority, held for longer than
# `driftResetGrace` — a return counts only once it has been *held*, which is R-60's ruling 1 and
# the single most obvious way a drift detector gets defeated when it is missing.

note "returning to the context application: $CONTEXT_APP"
open -a "$CONTEXT_APP"
sleep $(( DRIFT_RESET_GRACE + 6 ))
capture_windows "06-returned-to-anchor.png"
timeline "06 · returned to $CONTEXT_APP and held for more than ${DRIFT_RESET_GRACE}s — the accumulator clears"

# --- 6 · the most important frame in the set (OPERATOR-ASSISTED) ------------------------------
#
# The context chip is not decoration: under R-56.1 it **is** the negative basis, and without it
# the engine has nothing for an absence to be an absence *of*. Removing it and re-capturing is
# what shows the app falling silent when it has nothing to judge against — which is the
# behaviour a reader will otherwise mistake for a bug the first time it happens to them.

if (( HAS_PRIORITY )); then
    note "asking the operator to remove the context chip"
    if prompt_operator "remove the $CONTEXT_APP context chip from the priority, then bring $DECOY forward again and leave it there."; then
        sleep $(( SUSTAINED_DRIFT + 6 ))
        capture_windows "07-context-removed.png"
        timeline "07 · context chip removed, ${SUSTAINED_DRIFT}s+ on the decoy — uncertain(noNegativeBasis), because absence of lexical evidence may never alone accuse (R-56.1)"
    else
        manual_required "07-context-removed.png" \
            "no operator was at the keyboard for the second prompt." \
            "Run attended. Remove the app context chip from the priority, bring $DECOY forward, wait more than ${SUSTAINED_DRIFT}s, and read the inspector: it must say 'uncertain' with the noNegativeBasis clause, however long the dwell."
    fi
else
    timeline "07 · skipped: there was no context chip to remove (the whole run is already the decline)"
fi

note "recording what the engine concluded, after the drift sequence"
export_verdict "$LOG_DIR/focus-live-verdict-after.json" \
    && cp -- "$LOG_DIR/focus-live-verdict-after.json" "$EVIDENCE_DIR/verdict-report-after.json" \
    && produced "verdict-report-after.json" "AUTOMATED"

# --- 7 · the ledger ----------------------------------------------------------------------------

{
    print
    print "what this run produced"
    print -r -- "----------------------"
    for artefact in $PRODUCED; do print "  produced          $artefact"; done
    for artefact in $RECEIPTS; do print "  operator-assisted $artefact (receipt written)"; done
    print
    print "The frames are READ, by eye, and that reading is the evidence (charter tmux-verify"
    print "doctrine). What is being read is not 'did it draw' but 'is the explanation"
    print "restrained': no title, no URL, no number, no accusation — the clause list and"
    print "nothing else."
} >> "$EVIDENCE_DIR/verdict-timeline.txt"

produced "verdict-timeline.txt" "AUTOMATED"

print
print "== live verdict drive complete"
print "evidence: $EVIDENCE_DIR"
print "produced: ${#PRODUCED} artefact(s), ${#RECEIPTS} receipt(s)"
print
print "This lane is read evidence and never a close condition. It exits 0 whatever it produced."
exit 0
