#!/bin/zsh
# sign-and-notarise.sh — Developer ID signing, notarisation and stapling, in place (focus-h8jf).
#
#   scripts/sign-and-notarise.sh <FocusSentinel.app> [<identity>] [<notarytool keychain profile>]
#
# The identity and the profile default to Config/ReleasePipeline.json's `signing` block. Both
# must already be in a keychain on the search list of the Mac this runs on: the identity as a
# Developer ID Application certificate with its private key, the profile stored by
# `xcrun notarytool store-credentials <profile>`. This script asks for neither and stores
# nothing; a Mac without them fails at the first step, by name.
#
# The notarisation credentials may instead arrive as an App Store Connect API key, the way
# justspeaktoit's release workflow supplies them: FOCUS_NOTARY_KEY_PATH (a .p8 file),
# FOCUS_NOTARY_KEY_ID and FOCUS_NOTARY_ISSUER_ID. When all three are set they are used in place
# of the keychain profile. `release-mac.yml` sets them from the repository's secrets when those
# secrets exist, and leaves them unset otherwise.
#
# THE ORDER IS SPARKLE'S. The framework carries its own executables — Autoupdate and the
# Updater app, and XPC services where the distribution includes them — and every one of them has
# to be re-signed with the same identity, hardened runtime on, before the framework and then the
# app. `--preserve-metadata=entitlements` keeps the entitlements Sparkle shipped on its services.
# Signing the app with `--deep` instead would sign them all with the app's entitlements, which is
# the one thing Sparkle's documentation says not to do.
#
# It leaves behind exactly one file beside the app: a zip of it, which notarytool needs and
# which is removed on success.
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

APP="${1:-}"
IDENTITY="${2:-$(python3 -c 'import json;print(json.load(open("Config/ReleasePipeline.json"))["signing"]["identity"])')}"
PROFILE="${3:-$(python3 -c 'import json;print(json.load(open("Config/ReleasePipeline.json"))["signing"]["notarytoolKeychainProfile"])')}"
ENTITLEMENTS="App/FocusSentinel.entitlements"

if [[ -z "$APP" || ! -d "$APP" ]]; then
    print -u2 "usage: ${0:t} <FocusSentinel.app> [<identity>] [<notarytool profile>]"
    exit 2
fi
if ! security find-identity -v -p codesigning | grep -q -- "$IDENTITY"; then
    print -u2 "FAIL no '$IDENTITY' identity in the login keychain; nothing signed"
    exit 1
fi

sign() {
    # $1 path; the rest are extra codesign options.
    local path="$1"; shift
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@" -- "$path" || {
        print -u2 "FAIL codesign refused $path"; exit 1
    }
    print "signed   ${path#$APP/}"
}

FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$FRAMEWORK" ]]; then
    VERSIONED="$FRAMEWORK/Versions/B"
    for service in "$VERSIONED"/XPCServices/*.xpc(N); do
        sign "$service" --preserve-metadata=entitlements
    done
    [[ -d "$VERSIONED/Updater.app" ]] && sign "$VERSIONED/Updater.app"
    [[ -f "$VERSIONED/Autoupdate" ]] && sign "$VERSIONED/Autoupdate"
    sign "$FRAMEWORK"
else
    print -u2 "FAIL the app embeds no Sparkle.framework; this is not a release-train product"
    exit 1
fi

sign "$APP" --entitlements "$ENTITLEMENTS"

print
print "== codesign --verify --deep --strict"
codesign --verify --deep --strict --verbose=2 -- "$APP" || exit 1

print
print "== notarytool submit --wait"
ZIP="${APP%.app}.zip"
rm -f -- "$ZIP"
ditto -c -k --keepParent -- "$APP" "$ZIP" || exit 1
typeset -a NOTARY_AUTH
if [[ -n "${FOCUS_NOTARY_KEY_PATH:-}" && -n "${FOCUS_NOTARY_KEY_ID:-}" && -n "${FOCUS_NOTARY_ISSUER_ID:-}" ]]; then
    NOTARY_AUTH=(--key "$FOCUS_NOTARY_KEY_PATH" --key-id "$FOCUS_NOTARY_KEY_ID" --issuer "$FOCUS_NOTARY_ISSUER_ID")
    print "notarising with the App Store Connect API key $FOCUS_NOTARY_KEY_ID"
else
    NOTARY_AUTH=(--keychain-profile "$PROFILE")
    print "notarising with the keychain profile $PROFILE"
fi
xcrun notarytool submit "$ZIP" "${NOTARY_AUTH[@]}" --wait || {
    print -u2 "FAIL notarisation was not accepted; read the log with: xcrun notarytool log <id> <the same credentials>"
    exit 1
}
rm -f -- "$ZIP"

print
print "== stapler"
xcrun stapler staple -- "$APP" || exit 1

print
print "== spctl --assess --type execute"
spctl --assess --type execute --verbose=2 -- "$APP" || {
    print -u2 "FAIL Gatekeeper does not accept the stapled product"
    exit 1
}
print "ok   $APP is Developer ID signed, notarised and stapled"
