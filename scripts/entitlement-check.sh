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
# The check asserts on named keys — never on dictionary equality — so a future toolchain that
# injects some new unrelated key does not fail the gate for no reason.
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

FORBIDDEN_KEYS=(
    "com.apple.security.network.client"
    "com.apple.security.network.server"
    "com.apple.developer.networking"
    "com.apple.developer.icloud"
    "com.apple.developer.aps-environment"
)

for key in $FORBIDDEN_KEYS; do
    if print -r -- "$DUMP" | grep -qF "$key"; then
        print -u2 "FAIL: forbidden entitlement present: $key"
        rc=1
    else
        print "ok   absent: $key"
    fi
done

if print -r -- "$DUMP" | grep -qF "com.apple.security.app-sandbox"; then
    print "ok   present: com.apple.security.app-sandbox"
else
    print -u2 "FAIL: com.apple.security.app-sandbox is not declared at all"
    rc=1
fi

if print -r -- "$DUMP" | grep -qF "com.apple.security.get-task-allow"; then
    task_allow=present
else
    task_allow=absent
fi

if [[ "$CONFIGURATION" == "Debug" ]]; then
    if [[ "$task_allow" == "present" ]]; then
        print "ok   present in Debug: com.apple.security.get-task-allow (injected so a debugger can attach)"
    else
        print -u2 "FAIL: com.apple.security.get-task-allow is absent from the Debug product."
        print -u2 "      Debug carries it deliberately (CODE_SIGN_INJECT_BASE_ENTITLEMENTS = YES);"
        print -u2 "      its disappearance means the signing configuration changed unnoticed."
        rc=1
    fi
else
    if [[ "$task_allow" == "absent" ]]; then
        print "ok   absent in Release: com.apple.security.get-task-allow"
    else
        print -u2 "FAIL: com.apple.security.get-task-allow is present in the Release product."
        print -u2 "      Release is the shipped artefact; that entitlement lets any same-uid"
        print -u2 "      process attach a debugger and read the app's memory. Set"
        print -u2 "      CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO in the Release configuration."
        rc=1
    fi
fi

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
