#!/bin/zsh
# generate-appcast.sh — one Sparkle appcast for one train, signed (focus-h8jf).
#
#   scripts/generate-appcast.sh <version> <build> <dmg> <feed-url> <download-url> [notes.html]
#
# Prints the appcast XML on stdout. `sparkle:version` is the BUILD NUMBER, because that is what
# Sparkle compares — `sparkle:shortVersionString` is for display — and the build number is the
# train's allocation number (`alpha-build-N`), so it climbs with every build the train cuts.
#
# THE SIGNATURE. `security` reads the EdDSA private key from the login keychain under the
# Sparkle account named in Config/ReleasePipeline.json (`Focus Sentinel`), which is where
# `generate_keys --account "Focus Sentinel"` put it on the Mac that cuts releases. Set
# SPARKLE_PRIVATE_KEY to the exported key to sign from a machine without that keychain item; it
# is written to a temporary file that is removed on every exit path, and never echoed.
#
# THE TOOL. `sign_update` ships inside the Sparkle SwiftPM artifact, which Xcode resolves into
# <derived data>/SourcePackages/artifacts/sparkle/Sparkle/bin. FOCUS_DERIVED_DATA names that
# derived data; a `swift package resolve` in Packages/FocusUpdates puts a second copy under its
# .build. Nothing is downloaded here: a signing tool fetched at signing time is a tool nobody
# checked.
set -u

REPO_ROOT="${0:A:h}/.."
cd "$REPO_ROOT" || exit 1

VERSION="${1:-}"; BUILD="${2:-}"; DMG="${3:-}"; FEED_URL="${4:-}"; DOWNLOAD_URL="${5:-}"; NOTES="${6:-}"
if [[ -z "$VERSION" || -z "$BUILD" || -z "$DMG" || -z "$FEED_URL" || -z "$DOWNLOAD_URL" ]]; then
    print -u2 "usage: ${0:t} <version> <build> <dmg> <feed-url> <download-url> [notes.html]"
    exit 2
fi
if [[ ! -f "$DMG" ]]; then
    print -u2 "FAIL no disk image at $DMG"
    exit 1
fi

ACCOUNT=$(python3 -c 'import json;print(json.load(open("Config/ReleasePipeline.json"))["signing"]["sparkleKeychainAccount"])')
MINIMUM=$(python3 -c 'import json;print(json.load(open("Config/ReleasePipeline.json"))["minimumSystemVersion"])')

SIGN_UPDATE=""
for candidate in \
    "${FOCUS_DERIVED_DATA:-/nonexistent}/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
    "Packages/FocusUpdates/.build/artifacts/sparkle/Sparkle/bin/sign_update"; do
    if [[ -x "$candidate" ]]; then SIGN_UPDATE="$candidate"; break; fi
done
if [[ -z "$SIGN_UPDATE" ]]; then
    print -u2 "FAIL sign_update not found; resolve Sparkle (xcodebuild, or swift package resolve in Packages/FocusUpdates) first"
    exit 1
fi

KEY_FILE=""
cleanup() { [[ -n "$KEY_FILE" ]] && rm -f -- "$KEY_FILE"; }
trap cleanup EXIT INT TERM

umask 077
KEY_FILE=$(mktemp) || exit 1
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    print -rn -- "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE" || exit 1
else
    # Use the installed system tool rather than asking a newly resolved executable for access.
    security find-generic-password -s "https://sparkle-project.org" -a "$ACCOUNT" -w > "$KEY_FILE" || {
        print -u2 "FAIL cannot read the existing '$ACCOUNT' Sparkle key; authorise access on the runner or provide SPARKLE_PRIVATE_KEY"
        exit 1
    }
fi
if ! SIGNATURE_LINE=$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" -p "$DMG" 2>/dev/null); then
    print -u2 "FAIL sign_update could not sign $DMG; no appcast emitted"
    exit 1
fi
# `-p` prints the raw signature only; without it the tool prints the whole attribute string.
SIGNATURE="${SIGNATURE_LINE//[[:space:]]/}"
if [[ -z "$SIGNATURE" ]]; then
    print -u2 "FAIL sign_update produced no signature for $DMG (is the '$ACCOUNT' key in this login keychain?)"
    exit 1
fi
if ! print -rn -- "$SIGNATURE" | python3 -c 'import base64,sys; s=sys.stdin.read(); sys.exit(0 if len(base64.b64decode(s,validate=True))==64 else 1)' 2>/dev/null; then
    print -u2 "FAIL sign_update returned an invalid EdDSA signature; no appcast emitted"
    exit 1
fi

LENGTH=$(stat -f%z -- "$DMG")
PUB_DATE=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')
if [[ -n "$NOTES" && -s "$NOTES" ]]; then
    NOTES_HTML=$(cat -- "$NOTES")
else
    NOTES_HTML="<p>Focus Sentinel ${VERSION} (build ${BUILD}). Release notes are on the GitHub release this build was published from.</p>"
fi

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Focus Sentinel updates</title>
    <link>${FEED_URL}</link>
    <description>Builds of Focus Sentinel on this train</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MINIMUM}</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <description><![CDATA[
        ${NOTES_HTML}
      ]]></description>
      <enclosure
        url="${DOWNLOAD_URL}"
        sparkle:edSignature="${SIGNATURE}"
        length="${LENGTH}"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
