#!/bin/zsh
# package-release.sh — the release artefact (D-09), and nothing else.
#
# WHAT IT MAKES. `FocusSentinel-<version>-<commit>.dmg`: a read-only compressed disk image
# holding exactly two things — the Release application this gate already built, and a README
# that says what a person will meet when they open it.
#
# WHAT IT DOES NOT DO, and these are guarantees rather than omissions:
#
#   * **It never builds.** It copies the product `build-release` produced. A packaging script
#     that builds is a script that can ship a different binary from the one every other stage
#     read.
#   * **It never signs, and never touches the keychain.** The app is ad-hoc signed by the build
#     (`CODE_SIGN_IDENTITY = "-"`), `ditto` preserves that signature, and `hdiutil` is not asked
#     to sign the image. `codesign` appears below only with `--verify` and `-dv`, which read.
#   * **It never claims the artefact is notarised, and never pretends Gatekeeper will like it.**
#     `spctl --assess` is RECORDED, and the reading on an ad-hoc-signed app is `rejected`. The
#     README says so in the same words, because a distribution posture a person discovers from a
#     scary dialog is a posture that was not stated.
#
# THE NAME CARRIES BOTH FACTS. The marketing version and the commit, read out of the built
# product's own Info.plist rather than from git — so an artefact whose name says `741449c` is an
# artefact whose bundle says `741449c`, and the gate's `release-artefact` stage checks that the
# bundle's hash is this tree's HEAD.
#
# usage: package-release.sh <path to Release FocusSentinel.app> <output directory>

set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

APP="${1:-}"
OUT_DIR="${2:-}"

if [[ -z "$APP" || -z "$OUT_DIR" ]]; then
    print -u2 "usage: ${0:t} <path to FocusSentinel.app> <output directory>"
    exit 2
fi
if [[ ! -d "$APP" ]]; then
    print -u2 "FAIL: no app bundle at $APP"
    exit 2
fi
mkdir -p -- "$OUT_DIR" || exit 1

PLIST="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null)
COMMIT=$(/usr/libexec/PlistBuddy -c 'Print :FocusGitHash' "$PLIST" 2>/dev/null)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null)

if [[ -z "$VERSION" ]]; then
    print -u2 "FAIL: the product carries no CFBundleShortVersionString, so the artefact has no name"
    exit 1
fi
if [[ -z "$COMMIT" ]]; then
    print -u2 "FAIL: the product carries no FocusGitHash — it was built without FOCUS_GIT_HASH,"
    print -u2 "      so the artefact could not say which commit it came from"
    exit 1
fi

DMG="$OUT_DIR/FocusSentinel-$VERSION-$COMMIT.dmg"
VOLUME="Focus Sentinel $VERSION"
STAGE=$(mktemp -d -t focus-release-stage) || exit 1
trap 'rm -rf -- "$STAGE"' EXIT INT TERM

print "== staging"
print "app:      $APP"
print "version:  $VERSION ($BUILD)"
print "commit:   $COMMIT"
print "image:    $DMG"
print

# `ditto` rather than `cp -R`: it preserves extended attributes and the code signature, which is
# the whole point of shipping the product rather than rebuilding it.
ditto -- "$APP" "$STAGE/FocusSentinel.app" || exit 1

# --- the readings, taken on the staged copy before it is sealed into the image ----------------
#
# Each is printed for the log AND written into the README, so the sentence a person reads is the
# output of a command rather than somebody's memory of what it said.
print "== codesign --verify --deep --strict"
codesign --verify --deep --strict --verbose=2 "$STAGE/FocusSentinel.app" 2>&1
verify_rc=$?
print "verify EXIT=$verify_rc"
if (( verify_rc != 0 )); then
    print -u2 "FAIL: the built product's own signature does not verify; packaging it would ship damage"
    exit 1
fi

print
print "== codesign -dv"
signature=$(codesign -dv "$STAGE/FocusSentinel.app" 2>&1)
print -r -- "$signature"
if ! print -r -- "$signature" | grep -q 'Signature=adhoc'; then
    print -u2 "FAIL: the product is not ad-hoc signed, which is the posture this artefact documents"
    exit 1
fi

print
print "== spctl --assess --type execute (recorded, never asserted green)"
assessment=$(spctl --assess --type execute --verbose=4 "$STAGE/FocusSentinel.app" 2>&1)
assess_rc=$?
print -r -- "$assessment"
print "spctl EXIT=$assess_rc"

# --- the README ------------------------------------------------------------------------------
#
# Written here rather than committed, because two of its sentences are readings taken above and a
# committed file would be a copy of them that can go stale.
cat > "$STAGE/README.txt" <<README
Focus Sentinel $VERSION ($BUILD)
Commit $COMMIT

WHAT THIS IS

A local Mac application. It watches which application is in front of you and asks, at most a
few times a day, whether what you are doing is the thing you said you were doing. It talks to
no server: there is no account, no sync and no network code in it at all, and the build gate
proves that on the shipped binary rather than in a promise.

Requires macOS 26.0 or later.

WHAT WILL HAPPEN WHEN YOU OPEN IT

macOS will refuse to open it on the first try, and will say something like "Focus Sentinel is
damaged and can't be opened" or "cannot be opened because the developer cannot be verified".
It is not damaged. This build is signed AD HOC — signed with no identity at all, which is what
a locally built Mac application is — rather than with a paid Apple Developer ID, and it has
not been through Apple's notary service.

This is what Gatekeeper says about it, verbatim, taken from the build that made this disk
image:

$assessment

  (spctl --assess --type execute --verbose=4, exit $assess_rc)

And this is the signature it does carry, which verifies:

$signature

TO OPEN IT ANYWAY

Drag Focus Sentinel to your Applications folder, then RIGHT-CLICK it (or Control-click) and
choose Open. The dialog you get from that route has an Open button; the one you get from
double-clicking does not. You will be asked once. After that it opens normally.

If macOS still refuses, the file carries a quarantine flag from having been downloaded, and
this removes it:

  xattr -d com.apple.quarantine /Applications/Focus\\ Sentinel.app

WHY IT IS NOT NOTARISED

Notarisation needs a paid Apple Developer ID, and this application is distributed as a local
build rather than through a store. Nothing here is hidden from you: the source, the build gate
and every assertion it makes are the artefact. If you would rather build it yourself, that is
the supported route and the one this project is set up for.

WHAT IT ASKS OF THE SYSTEM

Nothing, on first run. It requests no permission of any kind and it never calls
requestAuthorization — the gate asserts that on the shipped binary. It works with no grants at
all; features that would need one are drawn as unavailable and say why.
README

print
print "== hdiutil create"
rm -f -- "$DMG"
hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG"
create_rc=$?
if (( create_rc != 0 )); then
    print -u2 "FAIL: hdiutil create exited $create_rc"
    exit 1
fi

print
print "RELEASE ARTEFACT $DMG"
print "size $(du -h -- "$DMG" | cut -f1)"
exit 0
