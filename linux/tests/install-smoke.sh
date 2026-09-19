#!/usr/bin/env bash
# Smoke test for linux/install.sh: runs it against a throwaway HOME with a fake build output and a
# fake Omarchy loader, and checks the files it writes, its idempotence, the delete guard, the
# no-Omarchy path and --uninstall. No build, no compositor, no shim compile.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$REPO_ROOT/linux/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
count_require() { grep -cF 'hypr.hearthstone-deck-tracker' "$1" || true; }

export HOME="$TMP/home"
mkdir -p "$HOME/.config/hypr"
unset XDG_CONFIG_HOME HYPRLAND_INSTANCE_SIGNATURE HDT_INSTALL_DIR
FAKE_OUT="$TMP/out"; mkdir -p "$FAKE_OUT"; echo fake > "$FAKE_OUT/HearthstoneDeckTracker.exe"
FAKE_OMARCHY="$TMP/omarchy"; mkdir -p "$FAKE_OMARCHY/default/hypr"; : > "$FAKE_OMARCHY/default/hypr/require_optional.lua"
echo '-- user config' > "$HOME/.config/hypr/hyprland.lua"
export HDT_SKIP_BUILD=1 HDT_BUILD_OUTPUT="$FAKE_OUT" HDT_SKIP_SHIM=1 HDT_NO_HYPR_RELOAD=1 OMARCHY_PATH="$FAKE_OMARCHY"

DEST="$HOME/.local/share/hearthstone-deck-tracker/app"
LAUNCHER="$HOME/.local/bin/launch-hdt"
DESKTOP="$HOME/.local/share/applications/hearthstone-deck-tracker.desktop"
ICON="$HOME/.local/share/icons/hicolor/256x256/apps/hearthstone-deck-tracker.png"
RULES="$HOME/.config/hypr/hearthstone-deck-tracker.lua"
MAIN="$HOME/.config/hypr/hyprland.lua"
BNET_LAUNCHER="$HOME/.local/bin/hdt-launch-battlenet"
HELPER="$HOME/.local/bin/hdt-wineserver"
BNET_DESKTOP="$HOME/.local/share/applications/battlenet.desktop"
mkdir -p "$(dirname "$BNET_DESKTOP")"
printf '[Desktop Entry]\nName=Battle.net\nExec=omarchy-launch-battlenet\nType=Application\n' > "$BNET_DESKTOP"

echo "1. fresh install"
"$INSTALL" > "$TMP/install1.log"
[ -f "$DEST/HearthstoneDeckTracker.exe" ] || fail "binary not installed"
[ -f "$DEST/.hdt-omarchy-install" ] || fail "marker missing"
[ -s "$DEST/VERSION" ] || fail "VERSION missing"
[ -x "$LAUNCHER" ] || fail "launcher missing or not executable"
grep -qF "$DEST/HearthstoneDeckTracker.exe" "$LAUNCHER" || fail "launcher does not point at the install dir"
grep -qF "$REPO_ROOT/linux/update.sh" "$LAUNCHER" || fail "launcher does not point at the checkout's update.sh"
! grep -q '@[A-Z_]*@' "$LAUNCHER" || fail "launcher has unfilled placeholders"
grep -q '@HDT_INSTALL_DIR@' "$LAUNCHER" && fail "launcher placeholder not substituted"
[ -f "$DESKTOP" ] || fail "desktop entry missing"
grep -qF "Exec=$LAUNCHER" "$DESKTOP" || fail "desktop entry Exec wrong"
[ -f "$ICON" ] || fail "icon missing"
[ -f "$RULES" ] || fail "hyprland rules file missing"
[ "$(count_require "$MAIN")" = 1 ] || fail "expected exactly one require line, got $(count_require "$MAIN")"
grep -q -- '-- user config' "$MAIN" || fail "user config content lost"
[ "$(ls "$MAIN".bak.* | wc -l)" = 1 ] || fail "expected one backup of hyprland.lua"
grep -qF "appended to $MAIN" "$TMP/install1.log" || fail "install did not report the appended line"
[ -x "$HELPER" ] || fail "hdt-wineserver missing or not executable"
[ -x "$BNET_LAUNCHER" ] || fail "hdt-launch-battlenet missing or not executable"
grep -q '@HDT_WINESERVER@' "$LAUNCHER" "$BNET_LAUNCHER" && fail "wineserver placeholder not substituted"
grep -qF "$HELPER" "$LAUNCHER" || fail "launch-hdt does not call hdt-wineserver"
grep -qF "$HELPER" "$BNET_LAUNCHER" || fail "hdt-launch-battlenet does not call hdt-wineserver"
grep -qxF "Exec=$BNET_LAUNCHER" "$BNET_DESKTOP" || fail "Battle.net menu entry not pointed at hdt-launch-battlenet"
grep -qxF 'Name=Battle.net' "$BNET_DESKTOP" || fail "Battle.net menu entry lost its other lines"

echo "2. second install is idempotent"
"$INSTALL" > /dev/null
[ "$(count_require "$MAIN")" = 1 ] || fail "require line duplicated on re-install"
[ "$(ls "$MAIN".bak.* | wc -l)" = 1 ] || fail "re-install made another backup"
[ -f "$DEST/.hdt-omarchy-install" ] || fail "marker lost on re-install"
[ "$(grep -c '^Exec=' "$BNET_DESKTOP")" = 1 ] || fail "Battle.net menu entry Exec duplicated"
grep -qxF "Exec=$BNET_LAUNCHER" "$BNET_DESKTOP" || fail "Battle.net menu entry changed on re-install"

echo "3. refuses to wipe a directory it did not create"
FOREIGN="$TMP/foreign"; mkdir -p "$FOREIGN"; echo keep > "$FOREIGN/keep"
if HDT_INSTALL_DIR="$FOREIGN" "$INSTALL" > /dev/null 2>&1; then fail "installed over a foreign non-empty directory"; fi
[ -f "$FOREIGN/keep" ] || fail "foreign directory was wiped"

echo "3b. upgrades an install made before the marker existed"
LEGACY="$TMP/legacy"; mkdir -p "$LEGACY"; echo old > "$LEGACY/HearthstoneDeckTracker.exe"; echo old > "$LEGACY/stale.dll"
HDT_INSTALL_DIR="$LEGACY" "$INSTALL" > /dev/null
[ -f "$LEGACY/.hdt-omarchy-install" ] || fail "legacy install not upgraded"
[ ! -e "$LEGACY/stale.dll" ] || fail "stale file survived the upgrade"

echo "4. installs into an empty directory given explicitly"
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
HDT_INSTALL_DIR="$EMPTY" "$INSTALL" > /dev/null
[ -f "$EMPTY/.hdt-omarchy-install" ] || fail "explicit empty install dir not used"

echo "5. no Omarchy loader: hyprland.lua is left alone"
HOME2="$TMP/home2"; mkdir -p "$HOME2/.config/hypr"; echo '-- plain lua config' > "$HOME2/.config/hypr/hyprland.lua"
HOME="$HOME2" OMARCHY_PATH="$TMP/nowhere" "$INSTALL" > "$TMP/install5.log"
[ "$(count_require "$HOME2/.config/hypr/hyprland.lua")" = 0 ] || fail "require line appended without an Omarchy loader"
[ ! -f "$HOME2/.config/hypr/hearthstone-deck-tracker.lua" ] || fail "rules file installed without an Omarchy loader"
grep -q "no Omarchy module loader" "$TMP/install5.log" || fail "no-loader tip not printed"

echo "6. uninstall"
"$INSTALL" --uninstall > /dev/null
[ ! -d "$DEST" ] || fail "install dir not removed"
[ ! -e "$LAUNCHER" ] || fail "launcher not removed"
[ ! -e "$DESKTOP" ] || fail "desktop entry not removed"
[ ! -e "$ICON" ] || fail "icon not removed"
[ ! -e "$RULES" ] || fail "rules file not removed"
[ ! -e "$HELPER" ] || fail "hdt-wineserver not removed"
[ ! -e "$BNET_LAUNCHER" ] || fail "hdt-launch-battlenet not removed"
grep -qxF 'Exec=omarchy-launch-battlenet' "$BNET_DESKTOP" || fail "Battle.net menu entry not restored"
[ "$(count_require "$MAIN")" = 0 ] || fail "require line not removed"
grep -q -- '-- user config' "$MAIN" || fail "user config content lost on uninstall"
[ "$(ls "$MAIN".bak.* | wc -l)" = 2 ] || fail "uninstall should have made a second backup"

echo "install smoke test passed"
