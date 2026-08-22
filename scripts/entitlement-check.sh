#!/bin/zsh
# Entitlement check — the product-level half of the no-network guarantee.
#
#   scripts/entitlement-check.sh <path to FocusSentinel.app>
#
# Reads the entitlements out of the *signed product*, not out of the source file. The source
# file says what we asked for; this says what shipped.
#
# Pass conditions:
#   * `com.apple.security.app-sandbox` is present. (It is `false` — the app needs NSWorkspace
#     and Accessibility depth that the sandbox forbids — but it must be declared, not
#     absent, so the posture is explicit.)
#   * None of the network or iCloud keys appear at all.
#
# `com.apple.security.get-task-allow` appears in Debug builds. The toolchain injects it so a
# debugger can attach; it is not a network entitlement and is expected. The check therefore
# asserts on the specific keys, never on dictionary equality.
#
# The full dump goes to stdout so the log doubles as evidence.
set -u

APP="${1:-}"
if [[ -z "$APP" ]]; then
    print -u2 "usage: ${0:t} <path to FocusSentinel.app>"
    exit 2
fi
if [[ ! -d "$APP" ]]; then
    print -u2 "FAIL: no app bundle at $APP"
    exit 2
fi

rc=0

print "== codesign -d --entitlements - $APP"
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
    print "note com.apple.security.get-task-allow present — expected in Debug, injected by the toolchain"
fi

print
if (( rc == 0 )); then
    print "ENTITLEMENTS OK"
else
    print -u2 "ENTITLEMENTS FAILED"
fi
exit $rc
