#!/bin/zsh
# Build the decoy into a real, ad-hoc-signed `.app` bundle.
#
#   Tools/FocusDecoy/build.sh [output directory]
#
# The rig doctrine e03 established and e04 and e05 continued: a single `swiftc` invocation, a
# hand-assembled bundle, `codesign -s -`. **Not** a SwiftPM executable, because a SwiftPM binary is
# not an application — it has no bundle, no `Info.plist`, no `LSMinimumSystemVersion`, no activation
# policy that LaunchServices will honour, and therefore no window that can enter a real full-screen
# space. Every measurement in this epic's probe ledger was taken against a bundle assembled exactly
# like this one, and frame 15 re-runs one of them.
#
# It is a plain `.app` in a temporary directory: nothing is installed, nothing is registered with
# LaunchServices permanently, and nothing survives the run that does not survive in git.
set -u

HERE="${0:A:h}"
NAME="${HERE:t}"
OUT="${1:-${TMPDIR:-/tmp}/focus-decoys}"
APP="$OUT/$NAME.app"

mkdir -p -- "$APP/Contents/MacOS" || exit 1
cp -- "$HERE/Info.plist" "$APP/Contents/Info.plist" || exit 1

swiftc -O \
    -target arm64-apple-macos26.0 \
    -o "$APP/Contents/MacOS/$NAME" \
    "$HERE/main.swift" || exit 1

# Ad-hoc, exactly as every probe bundle in this programme is signed. The decoys hold no
# entitlement and are granted nothing; that is the whole point of them.
codesign --force -s - "$APP" > /dev/null 2>&1 || exit 1

print -r -- "$APP"
