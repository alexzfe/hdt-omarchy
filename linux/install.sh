#!/usr/bin/env bash
# Build HDT (Release) and install it to a stable location, then install the launcher and menu entry.
#
#   Binary:   $HDT_INSTALL_DIR         (default ~/.local/share/hearthstone-deck-tracker/app)
#   Launcher: ~/.local/bin/launch-hdt
#   Menu:     ~/.local/share/applications/hearthstone-deck-tracker.desktop
#
# The launcher runs HDT inside the Battle.net Wine prefix so it shares a Wine session with the game.
# See linux/README.md for prefix setup. Override the prefix with HDT_WINEPREFIX (default ~/Games/battlenet).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${HDT_INSTALL_DIR:-$HOME/.local/share/hearthstone-deck-tracker/app}"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"

"$REPO_ROOT/linux/build.sh" Release

echo "Installing to $DEST ..."
mkdir -p "$DEST" "$BIN_DIR" "$APP_DIR"
rsync -a --delete "$REPO_ROOT/Hearthstone Deck Tracker/bin/x64/Release/" "$DEST/"

# Launcher: substitute the install dir, keep WINEPREFIX overridable at runtime.
sed "s|@HDT_INSTALL_DIR@|$DEST|g" "$REPO_ROOT/linux/launch-hdt.in" > "$BIN_DIR/launch-hdt"
chmod +x "$BIN_DIR/launch-hdt"

sed "s|@LAUNCHER@|$BIN_DIR/launch-hdt|g" "$REPO_ROOT/linux/hearthstone-deck-tracker.desktop.in" \
  > "$APP_DIR/hearthstone-deck-tracker.desktop"

echo "Installed."
echo "  binary:   $DEST"
echo "  launcher: $BIN_DIR/launch-hdt   (ensure $BIN_DIR is on PATH)"
echo "  menu:     $APP_DIR/hearthstone-deck-tracker.desktop"
