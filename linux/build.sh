#!/usr/bin/env bash
# Build HDT from source on Linux/macOS with the .NET SDK (no Windows or Wine needed for the build).
#
# Requires the .NET SDK 8+ on PATH (the project targets net472 and cross-compiles via
# EnableWindowsTargeting). If the build dependencies are missing, linux/fetch-deps.sh is run first.
#
# Usage: linux/build.sh [Debug|Release]   (default: Release)
#
# Crash reporting: the build leaves HDT's Sentry DSN empty, so the fork never reports crashes to
# HearthSim's Sentry project. Set HDT_SENTRY_DSN to report to a project of your own instead.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Release}"
HDT_DIR="$REPO_ROOT/Hearthstone Deck Tracker"

# A distribution "dotnet" may be a runtime without an SDK; fall back to a user-local SDK in ~/.dotnet.
if [ -z "$(dotnet --list-sdks 2>/dev/null)" ] && [ -x "$HOME/.dotnet/dotnet" ]; then
  export PATH="$HOME/.dotnet:$PATH"
fi
if [ -z "$(dotnet --list-sdks 2>/dev/null)" ]; then
  echo "error: no .NET SDK found ('dotnet --list-sdks' is empty or dotnet is not on PATH)." >&2
  echo "Install it (e.g. https://dot.net) and re-run. A user-local SDK in ~/.dotnet works;" >&2
  echo "add it with: export PATH=\"\$HOME/.dotnet:\$PATH\"" >&2
  exit 1
fi

if [ ! -f "$REPO_ROOT/lib/HearthMirror.dll" ]; then
  echo "Build dependencies not found; fetching..."
  "$REPO_ROOT/linux/fetch-deps.sh"
fi

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
SENTRY_PROPS=(-p:HdtDisableSentry=true)
if [ -n "${HDT_SENTRY_DSN:-}" ]; then
  SENTRY_PROPS=("-p:SENTRY_DSN=$HDT_SENTRY_DSN")
  echo "Building HDT ($CONFIG) with crash reporting to $HDT_SENTRY_DSN ..."
else
  echo "Building HDT ($CONFIG, crash reporting disabled) ..."
fi
dotnet build "$HDT_DIR/Hearthstone Deck Tracker.csproj" \
  -c "$CONFIG" -p:EnableWindowsTargeting=true -p:Platform=x64 "${SENTRY_PROPS[@]}" -v q -nologo

OUT="$HDT_DIR/bin/x64/$CONFIG"
[ -f "$OUT/HearthstoneDeckTracker.exe" ] || { echo "build produced no exe" >&2; exit 1; }
echo "Built: $OUT/HearthstoneDeckTracker.exe"
