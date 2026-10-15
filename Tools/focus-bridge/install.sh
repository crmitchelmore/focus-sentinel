#!/bin/zsh
# Build focus-bridge and install it for the current user.
#
#   Tools/focus-bridge/install.sh [prefix]        # default prefix: ~/.local
#
# Puts the binary and FocusCore's resource bundle in <prefix>/libexec/focus-bridge and links
# <prefix>/bin/focus-bridge to it. Nothing is registered with Launch Services and nothing runs at
# login: the binary does nothing until a script or an MCP client starts it.
set -euo pipefail

HERE="${0:A:h}"
PREFIX="${1:-$HOME/.local}"
DEST="$PREFIX/libexec/focus-bridge"

cd "$HERE"
swift build -c release --product focus-bridge
BIN="$(swift build -c release --show-bin-path)"

mkdir -p "$DEST" "$PREFIX/bin"
rm -rf "$DEST/FocusCore_FocusCore.bundle"
cp -f "$BIN/focus-bridge" "$DEST/focus-bridge"
cp -Rf "$BIN/FocusCore_FocusCore.bundle" "$DEST/"
ln -sf "$DEST/focus-bridge" "$PREFIX/bin/focus-bridge"

print "installed $PREFIX/bin/focus-bridge -> $DEST/focus-bridge"
print "try: $PREFIX/bin/focus-bridge status"
