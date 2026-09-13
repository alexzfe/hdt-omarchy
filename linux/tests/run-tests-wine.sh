#!/usr/bin/env bash
# Run the MSTest suites (HDTTests, HearthWatcher.Test) inside the Wine prefix with vstest.console,
# for machines without Windows. Downloads Microsoft.TestPlatform once into the cache directory.
#
# Usage: linux/tests/run-tests-wine.sh [Debug|Release] [extra vstest args, e.g. /Tests:WineTests]
# Env:   HDT_WINEPREFIX (default ~/Games/battlenet), HDT_PROTONPATH (GE-Proton),
#        HDT_TESTPLATFORM_VERSION (17.11.1), XDG_CACHE_HOME
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="${1:-Release}"; shift || true
PREFIX="${HDT_WINEPREFIX:-$HOME/Games/battlenet}"
TP_VERSION="${HDT_TESTPLATFORM_VERSION:-17.11.1}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/hdt-omarchy/testplatform-$TP_VERSION"
WINTMP_UNIX="$PREFIX/pfx/drive_c/users/steamuser/AppData/Local/Temp/hdt-tests"
WINTMP_WIN='C:\users\steamuser\AppData\Local\Temp\hdt-tests'

command -v umu-run >/dev/null 2>&1 || { echo "umu-run not found" >&2; exit 1; }
[ -d "$PREFIX/pfx" ] || { echo "Wine prefix not found: $PREFIX" >&2; exit 1; }

if [ ! -f "$CACHE/vstest.console.exe" ]; then
  echo "Downloading Microsoft.TestPlatform $TP_VERSION ..."
  mkdir -p "$CACHE"
  curl -fsSL -o "$CACHE/tp.nupkg" "https://www.nuget.org/api/v2/package/Microsoft.TestPlatform/$TP_VERSION"
  unzip -o -q "$CACHE/tp.nupkg" 'tools/net462/Common7/IDE/Extensions/TestPlatform/*' -d "$CACHE/unpacked"
  cp -r "$CACHE/unpacked/tools/net462/Common7/IDE/Extensions/TestPlatform/." "$CACHE/"
  rm -rf "$CACHE/unpacked" "$CACHE/tp.nupkg"
fi

export PATH="$HOME/.dotnet:$PATH" DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
for proj in HDTTests/HDTTests.csproj HearthWatcher.Test/HearthWatcher.Test.csproj; do
  echo "Building $proj ($CONFIG) ..."
  dotnet build "$REPO_ROOT/$proj" -c "$CONFIG" -p:EnableWindowsTargeting=true -p:Platform=x64 -p:HdtDisableSentry=true -v q -nologo
done

rm -rf "$WINTMP_UNIX"; mkdir -p "$WINTMP_UNIX/results"
cp -r "$CACHE" "$WINTMP_UNIX/vstest"
cp -r "$REPO_ROOT/HDTTests/bin/x64/$CONFIG" "$WINTMP_UNIX/HDTTests"
cp -r "$REPO_ROOT/HearthWatcher.Test/bin/x64/$CONFIG" "$WINTMP_UNIX/HearthWatcher.Test"

status=0
for suite in HDTTests HearthWatcher.Test; do
  echo "Running $suite under Wine ..."
  env WINEPREFIX="$PREFIX" PROTONPATH="${HDT_PROTONPATH:-GE-Proton}" GAMEID=umu-hdt-tests PROTON_VERB=run \
    umu-run "$WINTMP_UNIX/vstest/vstest.console.exe" "$WINTMP_WIN\\$suite\\$suite.dll" \
    /logger:trx "/ResultsDirectory:$WINTMP_WIN\\results" "$@" > "$WINTMP_UNIX/$suite.log" 2>&1 || true
  trx="$(ls -t "$WINTMP_UNIX/results"/*.trx 2>/dev/null | head -1)"
  if [ -z "$trx" ]; then
    echo "  no results file; see $WINTMP_UNIX/$suite.log" >&2; status=1; continue
  fi
  summary="$(grep -o '<Counters [^>]*>' "$trx" | head -1)"
  echo "  $summary"
  case "$summary" in *'failed="0"'*) ;; *) status=1 ;; esac
  mv "$trx" "$WINTMP_UNIX/$suite.trx"
done
echo "Results and logs: $WINTMP_UNIX"
exit $status
