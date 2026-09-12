#!/usr/bin/env bash
# Build HDT from source on Linux/macOS with the .NET SDK (no Windows or Wine needed for the build).
#
# Requires the .NET SDK 8+ on PATH (the project targets net472 and cross-compiles via
# EnableWindowsTargeting). If the build dependencies are missing, linux/fetch-deps.sh is run first.
#
# Usage: linux/build.sh [Debug|Release]   (default: Release)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Release}"
HDT_DIR="$REPO_ROOT/Hearthstone Deck Tracker"

if ! command -v dotnet >/dev/null 2>&1; then
  echo "error: the .NET SDK ('dotnet') is not on PATH." >&2
  echo "Install it (e.g. https://dot.net) and re-run. A user-local SDK in ~/.dotnet works;" >&2
  echo "add it with: export PATH=\"\$HOME/.dotnet:\$PATH\"" >&2
  exit 1
fi

if [ ! -f "$REPO_ROOT/lib/HearthMirror.dll" ]; then
  echo "Build dependencies not found; fetching..."
  "$REPO_ROOT/linux/fetch-deps.sh"
fi

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
echo "Building HDT ($CONFIG) ..."
dotnet build "$HDT_DIR/Hearthstone Deck Tracker.csproj" \
  -c "$CONFIG" -p:EnableWindowsTargeting=true -p:Platform=x64 -v q -nologo

OUT="$HDT_DIR/bin/x64/$CONFIG"
[ -f "$OUT/HearthstoneDeckTracker.exe" ] || { echo "build produced no exe" >&2; exit 1; }
echo "Built: $OUT/HearthstoneDeckTracker.exe"
