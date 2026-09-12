#!/usr/bin/env bash
# Build HDT (Release) and install it to a stable location, then install the launcher, menu entry,
# icon, X error shim and (on Omarchy) the Hyprland window rules.
#
#   Binary:   $HDT_INSTALL_DIR         (default ~/.local/share/hearthstone-deck-tracker/app)
#   Launcher: ~/.local/bin/launch-hdt
#   Menu:     ~/.local/share/applications/hearthstone-deck-tracker.desktop
#   Icon:     ~/.local/share/icons/hicolor/256x256/apps/hearthstone-deck-tracker.png
#   Shim:     $HDT_INSTALL_DIR/../lib/<arch>/libhdt-xerror-shim.so  (see linux/hdt-xerror-shim.c)
#   Hyprland: ~/.config/hypr/hearthstone-deck-tracker.lua + a require line in ~/.config/hypr/hyprland.lua
#
# Usage: linux/install.sh [--uninstall]
#
# Environment:
#   HDT_INSTALL_DIR      install directory for the binaries (see above)
#   HDT_SKIP_BUILD=1     install what is already in the build output instead of building
#   HDT_BUILD_OUTPUT     build output directory (default "Hearthstone Deck Tracker/bin/x64/Release")
#   HDT_SKIP_SHIM=1      do not build/install the X error shim
#   HDT_NO_HYPR_RELOAD=1 do not run "hyprctl reload" after installing the Hyprland rules
#   OMARCHY_PATH         Omarchy installation (default: ~/.local/share/omarchy or /usr/share/omarchy)
#
# The launcher runs HDT inside the Battle.net Wine prefix so it shares a Wine session with the game.
# See linux/README.md for prefix setup. Override the prefix at run time with HDT_WINEPREFIX.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${HDT_INSTALL_DIR:-$HOME/.local/share/hearthstone-deck-tracker/app}"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
LAUNCHER="$BIN_DIR/launch-hdt"
DESKTOP="$APP_DIR/hearthstone-deck-tracker.desktop"
ICON="$ICON_DIR/hearthstone-deck-tracker.png"
MARKER=".hdt-omarchy-install"   # written into $DEST; install.sh only ever deletes directories carrying it

SHIM_ROOT="$(dirname "$DEST")"
SHIM_NAME="libhdt-xerror-shim.so"
SHIM64="$SHIM_ROOT/lib/x86_64-linux-gnu/$SHIM_NAME"
SHIM32="$SHIM_ROOT/lib/i386-linux-gnu/$SHIM_NAME"

HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_MAIN="$HYPR_DIR/hyprland.lua"
HYPR_RULES="$HYPR_DIR/hearthstone-deck-tracker.lua"
HYPR_REQUIRE='require("default.hypr.require_optional").module("hypr.hearthstone-deck-tracker")'
HYPR_COMMENT='-- Hearthstone Deck Tracker (hdt-omarchy) window rules, installed by linux/install.sh.'

die() { echo "error: $*" >&2; exit 1; }
note() { echo "$*"; }

# Omarchy provides the Lua module loader the require line uses. Without it the line would break
# the user's Hyprland config, so the rules are only installed when the loader is found.
omarchy_loader() {
  local candidates=("$HOME/.local/share/omarchy" "/usr/share/omarchy")
  [ -n "${OMARCHY_PATH:-}" ] && candidates=("$OMARCHY_PATH")   # explicit path: no fallback
  local d
  for d in "${candidates[@]}"; do
    if [ -f "$d/default/hypr/require_optional.lua" ]; then
      echo "$d/default/hypr/require_optional.lua"
      return 0
    fi
  done
  return 1
}

hypr_line_installed() { [ -f "$HYPR_MAIN" ] && grep -qF 'hypr.hearthstone-deck-tracker' "$HYPR_MAIN"; }

backup_hypr_main() { cp "$HYPR_MAIN" "$HYPR_MAIN.bak.$(date +%s.%N)"; }

hypr_reload() {
  [ -n "${HDT_NO_HYPR_RELOAD:-}" ] && return 0
  command -v hyprctl >/dev/null 2>&1 || return 0
  [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || return 0
  hyprctl reload >/dev/null 2>&1 || true
  local errs
  errs="$(hyprctl configerrors 2>/dev/null || true)"
  if [ -n "$errs" ] && [ "$errs" != "No errors." ]; then
    echo "warning: hyprctl configerrors reports:" >&2
    echo "$errs" >&2
  fi
}

uninstall() {
  note "Uninstalling Hearthstone Deck Tracker (hdt-omarchy) ..."
  if [ -d "$DEST" ]; then
    if [ -f "$DEST/$MARKER" ]; then
      rm -rf "${DEST:?}"
      note "  removed $DEST"
    else
      echo "warning: $DEST has no $MARKER file, not touching it" >&2
    fi
  fi
  rm -f "$LAUNCHER" "$DESKTOP" "$ICON"
  rm -rf "${SHIM_ROOT:?}/lib" "${SHIM_ROOT:?}/lib32" "${SHIM_ROOT:?}/lib64"
  rmdir "$SHIM_ROOT" 2>/dev/null || true
  rm -f "$HYPR_RULES"
  if hypr_line_installed; then
    backup_hypr_main
    { grep -vF -e 'hypr.hearthstone-deck-tracker' -e "$HYPR_COMMENT" "$HYPR_MAIN" || true; } > "$HYPR_MAIN.tmp"
    mv "$HYPR_MAIN.tmp" "$HYPR_MAIN"
    note "  removed the require line from $HYPR_MAIN (backup alongside)"
    hypr_reload
  fi
  note "Uninstalled. The Wine prefix and HDT's config/logs under it were left alone."
}

case "${1:-}" in
  --uninstall) uninstall; exit 0 ;;
  -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) die "unknown argument: $1 (try --help)" ;;
esac

# --- prerequisites ------------------------------------------------------------------------------
missing=()
command -v rsync >/dev/null 2>&1 || missing+=(rsync)
if [ ! -f "$REPO_ROOT/lib/HearthMirror.dll" ] && [ -z "${HDT_SKIP_BUILD:-}" ]; then
  for c in curl git unzip; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
fi
[ ${#missing[@]} -eq 0 ] || die "missing tools: ${missing[*]}. Install them and re-run."
if [ -z "${HDT_SKIP_SHIM:-}" ] && ! command -v cc >/dev/null 2>&1; then
  echo "warning: no C compiler found; the X error shim will not be built (HDT may exit on Proton's XInput error)." >&2
  echo "         Install gcc (and lib32-libx11 for the 32-bit half) and re-run, or set HDT_SKIP_SHIM=1 to silence this." >&2
fi

# --- build ----------------------------------------------------------------------------------------
BUILD_OUT="${HDT_BUILD_OUTPUT:-$REPO_ROOT/Hearthstone Deck Tracker/bin/x64/Release}"
if [ -z "${HDT_SKIP_BUILD:-}" ]; then
  "$REPO_ROOT/linux/build.sh" Release
fi
[ -f "$BUILD_OUT/HearthstoneDeckTracker.exe" ] || die "no build output at $BUILD_OUT"

# --- binaries -------------------------------------------------------------------------------------
# rsync --delete empties the target: refuse any existing, non-empty directory that is not an HDT
# install (marker file from this script, or HearthstoneDeckTracker.exe from an older install.sh),
# so a wrong HDT_INSTALL_DIR can never wipe something else.
if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST")" ] && [ ! -f "$DEST/$MARKER" ] && [ ! -f "$DEST/HearthstoneDeckTracker.exe" ]; then
  die "$DEST exists, is not empty and is not an HDT install (no $MARKER, no HearthstoneDeckTracker.exe). Choose another HDT_INSTALL_DIR or empty it yourself."
fi
note "Installing to $DEST ..."
mkdir -p "$DEST" "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
rsync -a --delete "$BUILD_OUT/" "$DEST/"
: > "$DEST/$MARKER"
VERSION="$(git -C "$REPO_ROOT" describe --always --dirty --long 2>/dev/null || echo unknown)"
BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
printf '%s (%s) built %s\n' "$VERSION" "$BRANCH" "$(date -Is)" > "$DEST/VERSION"
cp "$REPO_ROOT/linux/hearthstone-deck-tracker.png" "$ICON"

# --- X error shim ---------------------------------------------------------------------------------
# Keeps Wine alive when XWayland disables an input device (see the .c file). Built for both
# architectures and installed under $LIB-style paths so the dynamic loader picks the right one per
# process (Wine may run 64- and 32-bit processes). launch-hdt only preloads it when the 64-bit
# build exists; a missing 32-bit build costs one "cannot be preloaded" line per 32-bit process.
SHIM=""
if [ -n "${HDT_SKIP_SHIM:-}" ]; then
  :
elif command -v cc >/dev/null 2>&1; then
  mkdir -p "$(dirname "$SHIM64")" "$(dirname "$SHIM32")"
  cc -m64 -shared -fPIC -O2 -Wall -o "$SHIM64" "$REPO_ROOT/linux/hdt-xerror-shim.c" -lX11
  if ! cc -m32 -shared -fPIC -O2 -Wall -o "$SHIM32" "$REPO_ROOT/linux/hdt-xerror-shim.c" -lX11 2>/dev/null; then
    echo "note: no 32-bit toolchain (gcc -m32 with lib32-libx11); 32-bit Wine helper processes run without the shim" >&2
    rm -f "$SHIM32"
  fi
  # Other $LIB spellings (lib, lib32, lib64) for host-side processes such as umu and pressure-vessel.
  ln -sfn "x86_64-linux-gnu/$SHIM_NAME" "$SHIM_ROOT/lib/$SHIM_NAME"
  ln -sfn lib/i386-linux-gnu "$SHIM_ROOT/lib32"
  ln -sfn lib/x86_64-linux-gnu "$SHIM_ROOT/lib64"
  SHIM="$SHIM64"
else
  rm -rf "${SHIM_ROOT:?}/lib" "${SHIM_ROOT:?}/lib32" "${SHIM_ROOT:?}/lib64"
fi

# --- launcher and menu entry ----------------------------------------------------------------------
sed "s|@HDT_INSTALL_DIR@|$DEST|g" "$REPO_ROOT/linux/launch-hdt.in" > "$LAUNCHER"
chmod +x "$LAUNCHER"
sed "s|@LAUNCHER@|$LAUNCHER|g" "$REPO_ROOT/linux/hearthstone-deck-tracker.desktop.in" > "$DESKTOP"

note "Installed $VERSION"
note "  binary:   $DEST"
note "  launcher: $LAUNCHER   (ensure $BIN_DIR is on PATH)"
note "  menu:     $DESKTOP"
[ -n "$SHIM" ] && note "  shim:     $SHIM"

# --- Hyprland window rules (Omarchy) -------------------------------------------------------------
# The rules file is copied next to the user's config and loaded from hyprland.lua through Omarchy's
# require_optional, so removing the file later is harmless. Note that "omarchy refresh hyprland"
# rewrites hyprland.lua; re-run this script afterwards to put the line back.
if [ -f "$HYPR_MAIN" ] && LOADER="$(omarchy_loader)"; then
  cp "$REPO_ROOT/linux/hyprland/hearthstone-deck-tracker.lua" "$HYPR_RULES"
  if ! hypr_line_installed; then
    backup_hypr_main
    printf '\n%s\n%s\n' "$HYPR_COMMENT" "$HYPR_REQUIRE" >> "$HYPR_MAIN"
    note "  hyprland: appended to $HYPR_MAIN (backup alongside):"
    note "            $HYPR_REQUIRE"
  fi
  note "  hyprland: $HYPR_RULES (loader: $LOADER)"
  hypr_reload
elif [ -f "$HYPR_MAIN" ]; then
  note "Tip (Hyprland): $HYPR_MAIN found but no Omarchy module loader; the rules were not installed."
  note "  Add the rules from linux/hyprland/hearthstone-deck-tracker.lua to your config by hand"
  note "  (see linux/README.md for the classic-syntax equivalent)."
else
  note "Tip (Hyprland): no $HYPR_MAIN found; add the rules from linux/hyprland/hearthstone-deck-tracker.lua"
  note "  to your Hyprland config (see linux/README.md for the classic-syntax equivalent)."
fi
