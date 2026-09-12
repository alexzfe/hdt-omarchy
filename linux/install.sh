#!/usr/bin/env bash
# Build HDT (Release) and install it to a stable location, then install the launcher and menu entry.
#
#   Binary:   $HDT_INSTALL_DIR         (default ~/.local/share/hearthstone-deck-tracker/app)
#   Launcher: ~/.local/bin/launch-hdt
#   Menu:     ~/.local/share/applications/hearthstone-deck-tracker.desktop
#   Icon:     ~/.local/share/icons/hicolor/256x256/apps/hearthstone-deck-tracker.png
#   Shim:     $HDT_INSTALL_DIR/../lib/<arch>/libhdt-xerror-shim.so  (see linux/hdt-xerror-shim.c)
#   Hyprland: ~/.config/hypr/hearthstone-deck-tracker.lua + a require line in ~/.config/hypr/hyprland.lua
#
# The launcher runs HDT inside the Battle.net Wine prefix so it shares a Wine session with the game.
# See linux/README.md for prefix setup. Override the prefix with HDT_WINEPREFIX (default ~/Games/battlenet).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${HDT_INSTALL_DIR:-$HOME/.local/share/hearthstone-deck-tracker/app}"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

"$REPO_ROOT/linux/build.sh" Release

echo "Installing to $DEST ..."
mkdir -p "$DEST" "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
rsync -a --delete "$REPO_ROOT/Hearthstone Deck Tracker/bin/x64/Release/" "$DEST/"
cp "$REPO_ROOT/linux/hearthstone-deck-tracker.png" "$ICON_DIR/"

# X error shim (keeps Wine alive when XWayland disables an input device; see the .c file).
# Built for both architectures and installed under $LIB-style paths so the dynamic loader picks
# the right one per process (Wine runs 64- and 32-bit processes).
SHIM_ROOT="$(dirname "$DEST")"
SHIM_NAME="libhdt-xerror-shim.so"
if command -v cc >/dev/null 2>&1; then
  mkdir -p "$SHIM_ROOT/lib/x86_64-linux-gnu" "$SHIM_ROOT/lib/i386-linux-gnu"
  cc -m64 -shared -fPIC -O2 -Wall -o "$SHIM_ROOT/lib/x86_64-linux-gnu/$SHIM_NAME" "$REPO_ROOT/linux/hdt-xerror-shim.c" -lX11
  if cc -m32 -shared -fPIC -O2 -Wall -o "$SHIM_ROOT/lib/i386-linux-gnu/$SHIM_NAME" "$REPO_ROOT/linux/hdt-xerror-shim.c" -lX11 2>/dev/null; then
    :
  else
    echo "note: no 32-bit toolchain; 32-bit Wine helper processes run without the shim (harmless)" >&2
    rm -f "$SHIM_ROOT/lib/i386-linux-gnu/$SHIM_NAME"
  fi
  # Other $LIB spellings (lib, lib32, lib64) for host-side processes such as umu and pressure-vessel.
  ln -sfn "x86_64-linux-gnu/$SHIM_NAME" "$SHIM_ROOT/lib/$SHIM_NAME"
  ln -sfn lib/i386-linux-gnu "$SHIM_ROOT/lib32"
  ln -sfn lib/x86_64-linux-gnu "$SHIM_ROOT/lib64"
  SHIM="$SHIM_ROOT/lib/x86_64-linux-gnu/$SHIM_NAME"
else
  echo "warning: no C compiler found; skipping the X error shim (HDT may exit on XInput errors)" >&2
  rm -rf "$SHIM_ROOT/lib" "$SHIM_ROOT/lib32" "$SHIM_ROOT/lib64"; SHIM=""
fi

# Launcher: substitute the install dir, keep WINEPREFIX overridable at runtime.
sed "s|@HDT_INSTALL_DIR@|$DEST|g" "$REPO_ROOT/linux/launch-hdt.in" > "$BIN_DIR/launch-hdt"
chmod +x "$BIN_DIR/launch-hdt"

sed "s|@LAUNCHER@|$BIN_DIR/launch-hdt|g" "$REPO_ROOT/linux/hearthstone-deck-tracker.desktop.in" \
  > "$APP_DIR/hearthstone-deck-tracker.desktop"

echo "Installed."
echo "  binary:   $DEST"
echo "  launcher: $BIN_DIR/launch-hdt   (ensure $BIN_DIR is on PATH)"
echo "  menu:     $APP_DIR/hearthstone-deck-tracker.desktop"
[ -n "$SHIM" ] && echo "  shim:     $SHIM"

# Hyprland window rules (Omarchy's Lua config). The rules file is copied next to the user's config
# and loaded from hyprland.lua through Omarchy's require_optional, so removing the file later is
# harmless. Skipped when there is no Omarchy-style ~/.config/hypr/hyprland.lua.
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_MAIN="$HYPR_DIR/hyprland.lua"
HYPR_RULES="$HYPR_DIR/hearthstone-deck-tracker.lua"
HYPR_REQUIRE='require("default.hypr.require_optional").module("hypr.hearthstone-deck-tracker")'
if [ -f "$HYPR_MAIN" ]; then
  cp "$REPO_ROOT/linux/hyprland/hearthstone-deck-tracker.lua" "$HYPR_RULES"
  if ! grep -qF 'hypr.hearthstone-deck-tracker' "$HYPR_MAIN"; then
    cp "$HYPR_MAIN" "$HYPR_MAIN.bak.$(date +%s)"
    {
      echo
      echo "-- Hearthstone Deck Tracker (hdt-omarchy) window rules, installed by linux/install.sh."
      echo "$HYPR_REQUIRE"
    } >> "$HYPR_MAIN"
  fi
  echo "  hyprland: $HYPR_RULES (loaded from $HYPR_MAIN)"
  if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl reload >/dev/null 2>&1 || true
    ERRS="$(hyprctl configerrors 2>/dev/null || true)"
    if [ -n "$ERRS" ] && [ "$ERRS" != "No errors." ]; then
      echo "warning: hyprctl configerrors reports:" >&2
      echo "$ERRS" >&2
    fi
  fi
else
  echo "Tip (Hyprland): no $HYPR_MAIN found; add the rules from linux/hyprland/hearthstone-deck-tracker.lua"
  echo "  to your Hyprland config (see linux/README.md for the classic-syntax equivalent)."
fi
