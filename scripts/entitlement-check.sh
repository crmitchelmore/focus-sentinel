#!/bin/zsh
# Entitlement check — the product-level half of the no-network guarantee.
#
#   scripts/entitlement-check.sh <path to FocusSentinel.app> [Debug|Release]
#
# Reads the entitlements out of the *signed product*, not out of the source file. The source
# file says what we asked for; this says what shipped.
#
# The configuration is taken from the second argument, or inferred from the product's
# `Build/Products/<Configuration>/` directory when it is omitted. It matters, because one
# assertion below differs between the two.
#
# Pass conditions:
#   * `com.apple.security.app-sandbox` is present. (It is `false` — the app needs NSWorkspace
#     and Accessibility depth that the sandbox forbids — but it must be declared, not
#     absent, so the posture is explicit.)
#   * None of the network or iCloud keys appear at all.
#   * `com.apple.security.get-task-allow` is present in **Debug** and absent in **Release**.
#
# ## Why get-task-allow is configuration-sensitive rather than "expected everywhere"
#
# `get-task-allow` lets any process with the same uid attach a debugger to the app and read
# its memory. In a debug build that is the point. In the shipped artefact — and under this
# programme's local-app policy the Release product *is* the shipped artefact — it is a real
# weakening of the app's own process boundary, on an app whose entire premise is that what it
# observes never leaves the machine.
#
# Xcode's `ProcessProductPackaging` step merges the entitlements file with a set of injected
# "base entitlements", and under ad-hoc signing ("Sign to Run Locally") that set contains
# `get-task-allow` for *both* configurations — measured on this machine, Xcode 26.2. The fix
# is `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` in the Release build configuration, which was
# measured to produce a Release product carrying `com.apple.security.app-sandbox` alone,
# building and passing the zero-grant self-check unchanged. Debug keeps the injection, and
# keeps it explicitly (`= YES`), so the difference is a decision in the project file rather
# than a default nobody looked at.
#
# ## The set is PINNED, in both directions — it used to be searched (focus-gtr)
#
# This file used to say: *"The check asserts on named keys — never on dictionary equality — so a
# future toolchain that injects some new unrelated key does not fail the gate for no reason."*
# **That is the event this stage exists to catch.** An injected key is exactly how
# `get-task-allow` got into the Release product in the first place — the paragraph above is the
# record of it — and a membership test over five forbidden names is green for the sixth. The
# entitlement set of a signed product is a small, closed, *measured* set, so it is committed as a
# literal per configuration and compared whole: a key missing is red, a key appearing is red.
#
# The values are pinned too, and `app-sandbox` is why. It ships `false`, deliberately, and the
# grep this file used to run said only that the string appeared somewhere in the dump — so the
# sandbox flipping to `true`, which would break every NSWorkspace read the app is built on,
# passed. A key's presence is not its value.
#
# Non-vacuity is structural: the comparison is made against a **parsed plist**, and a dump that
# parses to nothing fails by name instead of satisfying five absence checks at once.
#
# The full dump goes to stdout so the log doubles as evidence.
set -u

APP="${1:-}"
CONFIGURATION="${2:-}"

if [[ -z "$APP" ]]; then
    print -u2 "usage: ${0:t} <path to FocusSentinel.app> [Debug|Release]"
    exit 2
fi
if [[ ! -d "$APP" ]]; then
    print -u2 "FAIL: no app bundle at $APP"
    exit 2
fi

# `Build/Products/Release/FocusSentinel.app` → `Release`. Only used when the caller did not
# say; an unrecognisable directory is an error rather than a guess, because guessing wrong
# would silently invert the assertion this script exists to make.
if [[ -z "$CONFIGURATION" ]]; then
    CONFIGURATION="${${APP:A:h}:t}"
fi
if [[ "$CONFIGURATION" != "Debug" && "$CONFIGURATION" != "Release" ]]; then
    print -u2 "FAIL: could not determine the build configuration for $APP"
    print -u2 "      Pass it explicitly: ${0:t} <app> Debug|Release"
    exit 2
fi

rc=0

print "== codesign -d --entitlements - $APP"
print "== configuration: $CONFIGURATION"
DUMP=$(codesign -d --entitlements - "$APP" 2>&1)
codesign_rc=$?
print -r -- "$DUMP"
if (( codesign_rc != 0 )); then
    print -u2 "FAIL: codesign could not read entitlements (exit $codesign_rc)"
    exit 1
fi

print
print "== assertions"

# The machine-readable form of the same signature. Two invocations rather than one parse of the
# human dump, because the human dump's shape is `codesign`'s to change and a check that depends on
# it would be a check on a formatter.
# One path and one trap: `"$(mktemp …).plist"` created a temp file and then wrote a *different*
# one beside it, so every run leaked the empty original and the trap removed the wrong name.
ENTITLEMENT_XML="$(mktemp -t focus-entitlements)"
trap 'rm -f -- "$ENTITLEMENT_XML"' EXIT
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENT_XML" 2>/dev/null

# The path rather than the bytes, and a **quoted** heredoc: interpolating a signature into a
# script is how a product's own content gets to decide what the script says.
python3 - "$CONFIGURATION" "$ENTITLEMENT_XML" <<'PYTHON'
import plistlib
import sys

configuration, xml_path = sys.argv[1], sys.argv[2]
try:
    with open(xml_path, "rb") as handle:
        raw = handle.read()
except OSError:
    raw = b""

failures = []


def check(condition, message, detail=None):
    if condition:
        print(f"ok   {message}")
        return
    line = f"FAIL {message}"
    if detail is not None:
        line += f"\n      got: {detail!r}"
    failures.append(line)
    print(line, file=sys.stderr)


# **The committed entitlement set, per configuration, measured on this tree.**
#
# Every key AND its value. `app-sandbox` is declared `false` on purpose — the app needs
# NSWorkspace and Accessibility depth the sandbox forbids — so the posture is explicit rather than
# absent; pinning the value is what makes "declared false" different from "declared".
COMMITTED = {
    # Debug keeps the injected base entitlements (CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES), and
    # `get-task-allow` is what a debugger attaches through. Its disappearance is a signing
    # configuration that changed without anyone deciding to.
    "Debug": {
        "com.apple.security.app-sandbox": False,
        "com.apple.security.get-task-allow": True,
    },
    # Release is the shipped artefact and carries the sandbox declaration alone. A
    # `get-task-allow` here lets any same-uid process attach a debugger and read the memory of an
    # app whose entire premise is that what it observes never leaves the machine.
    "Release": {
        "com.apple.security.app-sandbox": False,
    },
}

# The keys no configuration may ever carry. Implied by the exact comparison below and named
# anyway, because a reader of a red log is owed the *reason* and not only the diff — and because
# these five are the zero-networking guarantee spelled at the product level.
FORBIDDEN = [
    "com.apple.security.network.client",
    "com.apple.security.network.server",
    "com.apple.developer.networking",
    "com.apple.developer.icloud",
    "com.apple.developer.aps-environment",
]

try:
    parsed = plistlib.loads(raw) if raw.strip() else None
except Exception as error:  # noqa: BLE001 — any parse failure is the same verdict
    parsed = None
    print(f"note plist parse error: {error}")

# **The non-vacuity floor, and it comes first.** A dump that parsed to nothing satisfies every
# absence check below at once — which is a green stage for a signature nobody read.
check(
    isinstance(parsed, dict) and len(parsed) > 0,
    "the product's entitlements were read as a plist and are not empty",
    parsed,
)
entitlements = parsed if isinstance(parsed, dict) else {}

expected = COMMITTED.get(configuration)
check(expected is not None, f"there is a committed entitlement set for {configuration}", configuration)

if expected is not None and entitlements:
    # **Pinned in both directions.** A key missing is as red as a key appearing, and the symmetric
    # difference is what a reader needs to see.
    check(
        set(entitlements) == set(expected),
        f"the {configuration} product carries exactly the committed entitlement keys",
        sorted(set(entitlements) ^ set(expected)),
    )
    # And the values, because presence is not value: an app-sandbox flipped to true would pass
    # every key comparison and break every NSWorkspace read the app is built on.
    check(
        entitlements == expected,
        f"every committed {configuration} entitlement carries the value it was committed with",
        {k: v for k, v in sorted(entitlements.items()) if expected.get(k, "<absent>") != v},
    )

# Named individually as well, so a red log says *which* guarantee broke rather than "the set
# differs". These are a restatement of the comparison above and are deliberately not its
# substitute — that substitution is the defect this block replaced.
#
# **And they are labelled as restatements in the log** (focus-bkf). Not one of them can go red on
# its own: the whole-dictionary comparison above fails first for every edit that would falsify
# any of them, so counting these seven lines as seven readings would be counting one reading
# seven times. They are here to name the guarantee a reader is looking for; the coverage is the
# two rows above.
print("     the seven lines below RESTATE the comparison above; none can fail on its own")
for key in FORBIDDEN:
    check(key not in entitlements, f"restatement — absent: {key}")

check(
    "com.apple.security.app-sandbox" in entitlements,
    "restatement — present: com.apple.security.app-sandbox (declared, so the posture is explicit)",
    sorted(entitlements),
)
if configuration == "Debug":
    check(
        entitlements.get("com.apple.security.get-task-allow") is True,
        "restatement — present in Debug: com.apple.security.get-task-allow (a debugger can attach)",
        entitlements.get("com.apple.security.get-task-allow"),
    )
else:
    check(
        "com.apple.security.get-task-allow" not in entitlements,
        "restatement — absent in Release: com.apple.security.get-task-allow",
        "Release is the shipped artefact; set CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO",
    )

# **The vacuity guard, stated.** This proves what is SIGNED INTO the product, and nothing about
# what the system grants it at runtime: a TCC row is not an entitlement and no dump would show
# one. It also says nothing about entitlements a future macOS honours implicitly. What it can no
# longer be green for is the failure it exists to catch — a capability appearing in the shipped
# artefact that nobody declared.

print()
if failures:
    print(f"ENTITLEMENT SET FAILED — {len(failures)} assertion(s)", file=sys.stderr)
    sys.exit(1)
PYTHON
(( $? != 0 )) && rc=1

# --- e03: two usage-description keys that must be ABSENT --------------------------------------
#
# `NSMicrophoneUsageDescription` and `NSCameraUsageDescription` are the strings macOS shows in a
# permission dialog when an app *opens* a capture device. This app never opens one. It reads a
# property **about** a device — `kAudioDevicePropertyDeviceIsRunningSomewhere`, measured
# prompt-free from a bundle holding no TCC row of any kind (probes P-94/P-95) — and the camera
# path is switched off entirely on every Mac in v1.
#
# Declaring a usage string for a capture the app never performs would be a claim it cannot
# honour: the key is a promise about what the app will do with a microphone, and the honest
# answer is that it will never have one. So both are asserted absent from the **merged**
# Info.plist, on both configurations — the merged one, because only the built product can say
# whether the partial plist and the generated keys came together the way they were meant to.
print
print "== usage descriptions (must be absent)"
MERGED_PLIST="$APP/Contents/Info.plist"
if [[ ! -f "$MERGED_PLIST" ]]; then
    print -u2 "FAIL: no merged Info.plist at $MERGED_PLIST"
    rc=1
else
    for key in NSMicrophoneUsageDescription NSCameraUsageDescription; do
        if /usr/libexec/PlistBuddy -c "Print :$key" "$MERGED_PLIST" > /dev/null 2>&1; then
            print -u2 "FAIL: $key is declared in the merged Info.plist"
            print -u2 "      This app never opens a capture device — it reads a property about one."
            print -u2 "      A usage string for a capture it never performs is a claim it cannot honour."
            rc=1
        else
            print "ok   absent: $key"
        fi
    done
fi

print
if (( rc == 0 )); then
    print "ENTITLEMENTS OK ($CONFIGURATION)"
else
    print -u2 "ENTITLEMENTS FAILED ($CONFIGURATION)"
fi
exit $rc
