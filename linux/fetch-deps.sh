#!/usr/bin/env bash
# Fetch the build dependencies that the upstream Bootstrap project would normally download.
#
# HDT references several closed- or externally-hosted libraries (HearthDb, HearthMirror, HSReplay,
# BobsBuddy) plus the HDT-Localization strings. On Windows these are pulled in by Bootstrap.csproj.
# This script does the same thing on Linux so `dotnet build` can run standalone.
#
# The downloaded libraries are NOT redistributable and are gitignored; they are fetched fresh here.
# Each download's ETag is recorded in lib/.hearthsim-etags, which linux/update.sh --check compares
# with the server to tell when HearthSim has published a new build (e.g. BobsBuddy after a patch).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/lib"
HDT_DIR="$REPO_ROOT/Hearthstone Deck Tracker"
BASE="https://libs.hearthsim.net/hdt"
ETAGS="$LIB/.hearthsim-etags"

mkdir -p "$LIB"
: > "$ETAGS.new"

fetch() { # url dest
  echo "  $1"
  local etag
  etag="$(curl -fsSL -o "$2" -w '%header{etag}' "$1")"
  printf '%s %s\n' "$(basename "$1")" "$etag" >> "$ETAGS.new"
}

echo "Fetching HearthSim libraries into lib/ ..."
fetch "$BASE/HSReplay.dll" "$LIB/HSReplay.dll"
for zip in HearthDb.zip HearthMirror.x64.zip BobsBuddy.zip; do
  fetch "$BASE/$zip" "$LIB/$zip"
  unzip -o -q "$LIB/$zip" -d "$LIB"
  rm -f "$LIB/$zip"
done

mv "$ETAGS.new" "$ETAGS"

echo "Fetching HDT-Localization ..."
if [ -d "$REPO_ROOT/HDT-Localization/.git" ]; then
  git -C "$REPO_ROOT/HDT-Localization" fetch --depth=1 origin master -q
  git -C "$REPO_ROOT/HDT-Localization" reset --hard -q origin/master
else
  git clone --depth=1 -q https://github.com/HearthSim/HDT-Localization.git "$REPO_ROOT/HDT-Localization"
fi
cp "$REPO_ROOT/HDT-Localization"/*.resx "$HDT_DIR/Properties/"
cp "$REPO_ROOT/CHANGELOG.md" "$HDT_DIR/Resources/"

echo "Dependencies ready."
