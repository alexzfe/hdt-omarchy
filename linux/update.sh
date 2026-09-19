#!/usr/bin/env bash
# Update the installed tracker: pull this checkout, fetch the latest HearthSim libraries, and rebuild
# and reinstall when anything changed.
#
# Card definitions refresh at run time, but HDT's code and the libraries it is built against
# (BobsBuddy's combat simulator, HearthMirror's game-memory reader, HearthDb) only change with a
# rebuild, and Battlegrounds or client patches can make old copies wrong or broken.
#
# Usage: linux/update.sh [--upstream] [--force]
#        linux/update.sh --check [--notify]
#        linux/update.sh --auto
#
#   --upstream  also merge HearthSim's master (remote "upstream", added if missing) into the current
#               branch; for maintaining the fork. A conflicting merge is aborted and left to you.
#   --force     rebuild and reinstall even if nothing changed
#   --check     change nothing: print what an update would bring in; exit 0 when up to date,
#               10 when an update is available, 1 on error
#   --notify    with --check: also send a desktop notification when an update is available
#   --auto      unattended mode, run by launch-hdt before the tracker starts: implies --upstream,
#               treats an unreachable network as "nothing to do", reports through notify-send, and
#               installs only a build that succeeded, so a failure leaves the working install alone.
#               It never discards uncommitted work: a merge that conflicts is aborted, and a merge
#               that builds badly stays in the checkout for you to look at, uninstalled.
#
# Environment: HDT_INSTALL_DIR (as for install.sh), plus everything install.sh reads.
#              HDT_AUTO_NO_UPSTREAM=1  --auto pulls the fork and the libraries but does not merge HearthSim.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${HDT_INSTALL_DIR:-$HOME/.local/share/hearthstone-deck-tracker/app}"
LIB="$REPO_ROOT/lib"
ETAGS="$LIB/.hearthsim-etags"
LIBS_BASE="https://libs.hearthsim.net/hdt"
UPSTREAM_URL="https://github.com/HearthSim/Hearthstone-Deck-Tracker.git"
UPSTREAM_REF="upstream/master"

die() { echo "error: $*" >&2; exit 1; }
note() { echo "$*"; }
g() { git -C "$REPO_ROOT" "$@"; }

UPSTREAM=0 FORCE=0 CHECK=0 NOTIFY=0 AUTO=0
for arg in "$@"; do
  case "$arg" in
    --upstream) UPSTREAM=1 ;;
    --force) FORCE=1 ;;
    --check) CHECK=1 ;;
    --notify) NOTIFY=1 ;;
    --auto) AUTO=1 ;;
    -h|--help) sed -n '2,/^set -e/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $arg (see --help)" ;;
  esac
done
[ "$NOTIFY" = 0 ] || [ "$CHECK" = 1 ] || die "--notify only goes with --check"
if [ "$AUTO" = 1 ]; then
  [ "$CHECK" = 0 ] || die "--auto and --check are opposites"
  [ -n "${HDT_AUTO_NO_UPSTREAM:-}" ] || UPSTREAM=1
fi

# In --auto nothing may block the launch: report and leave the working install in place.
notify() { # summary body
  [ "$AUTO" = 1 ] || return 0
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Hearthstone Deck Tracker" -i hearthstone-deck-tracker "$1" "$2" || true
}
give_up() { # reason
  echo "auto-update: $*" >&2
  notify "Tracker update failed" "$1"$'\n'"Launching the installed build. See linux/update.sh."
  exit 1
}
fail() { if [ "$AUTO" = 1 ]; then give_up "$*"; else die "$*"; fi; }

g rev-parse --git-dir >/dev/null 2>&1 || die "$REPO_ROOT is not a git checkout"

# Short commit of the installed build, from the VERSION line install.sh writes ("<describe> (<branch>) built <date>").
installed_commit() {
  [ -f "$DEST/VERSION" ] || return 0
  sed -n 's/^.*-g\([0-9a-f]\{7,\}\).*$/\1/p; s/^\([0-9a-f]\{7,\}\)\(-dirty\)\{0,1\} .*$/\1/p' "$DEST/VERSION" | head -n1
}

# Names of the HearthSim libraries whose server ETag differs from the one recorded by fetch-deps.sh.
changed_libs() {
  local name recorded remote
  [ -f "$ETAGS" ] || { echo "(no record of the fetched libraries; run linux/update.sh)"; return 0; }
  while read -r name recorded; do
    remote="$(curl -fsSI --max-time 15 "$LIBS_BASE/$name" | tr -d '\r' | sed -n 's/^[Ee][Tt][Aa][Gg]: *//p')" || continue
    [ -n "$remote" ] && [ "$remote" != "$recorded" ] && echo "$name"
  done < "$ETAGS"
  return 0
}

tracking_ref() { g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true; }

# --- check ----------------------------------------------------------------------------------------
if [ "$CHECK" = 1 ]; then
  pending=()
  track="$(tracking_ref)"
  if [ -n "$track" ]; then
    g fetch -q "${track%%/*}" 2>/dev/null || echo "warning: could not fetch ${track%%/*}" >&2
    n="$(g rev-list --count "HEAD..$track")"
    [ "$n" -gt 0 ] && pending+=("$n new commit(s) on $track")
  fi
  if g remote get-url upstream >/dev/null 2>&1; then
    g fetch -q upstream 2>/dev/null || echo "warning: could not fetch upstream" >&2
    n="$(g rev-list --count "HEAD..$UPSTREAM_REF" 2>/dev/null || echo 0)"
    [ "$n" -gt 0 ] && pending+=("$n new HearthSim commit(s) on $UPSTREAM_REF (merge with --upstream)")
  fi
  while read -r lib; do
    [ -n "$lib" ] && pending+=("new HearthSim library: $lib")
  done < <(changed_libs)
  inst="$(installed_commit)"
  if [ -z "$inst" ]; then
    pending+=("no installed build found at $DEST")
  elif ! g merge-base --is-ancestor "$(g rev-parse HEAD)" "$inst" 2>/dev/null; then
    pending+=("installed build ($inst) is older than this checkout ($(g rev-parse --short HEAD))")
  fi

  if [ "${#pending[@]}" -eq 0 ]; then
    note "Hearthstone Deck Tracker is up to date."
    exit 0
  fi
  note "Updates available:"
  printf '  %s\n' "${pending[@]}"
  note "Run: $REPO_ROOT/linux/update.sh"
  if [ "$NOTIFY" = 1 ] && command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Hearthstone Deck Tracker" -i hearthstone-deck-tracker "Deck Tracker update available" \
      "$(printf '%s\n' "${pending[@]}")"$'\n'"Run linux/update.sh in the hdt-omarchy checkout." || true
  fi
  exit 10
fi

# --- update ---------------------------------------------------------------------------------------
# install.sh replaces the binaries in place; Wine would keep running the old ones half-deleted.
if pgrep -f 'HearthstoneDeckTracker\.exe' >/dev/null; then
  die "Hearthstone Deck Tracker is running; close it and run this again."
fi

before="$(g rev-parse HEAD)"

track="$(tracking_ref)"
if [ -n "$track" ]; then
  # fetch + merge rather than pull: a pull.rebase setting would override --ff-only.
  note "Fetching $track ..."
  if ! g fetch -q "${track%%/*}"; then
    [ "$AUTO" = 1 ] || die "could not fetch ${track%%/*}"
    echo "auto-update: could not fetch ${track%%/*}; continuing with what is here" >&2
  elif [ "$(g rev-list --count "HEAD..$track")" -gt 0 ]; then
    g merge -q --ff-only "$track" || fail "could not fast-forward to $track (local commits diverge, or local changes overlap); resolve it with git and re-run"
  fi
fi

if [ "$UPSTREAM" = 1 ]; then
  g remote get-url upstream >/dev/null 2>&1 || g remote add upstream "$UPSTREAM_URL"
  note "Merging HearthSim $UPSTREAM_REF ..."
  if ! g fetch -q upstream; then
    [ "$AUTO" = 1 ] || die "could not fetch upstream"
    echo "auto-update: could not fetch upstream; continuing with what is here" >&2
  elif ! g merge -q --no-edit "$UPSTREAM_REF"; then
    conflicts="$(g diff --name-only --diff-filter=U)"
    g merge --abort
    fail "merging $UPSTREAM_REF conflicts in:"$'\n'"$conflicts"$'\n'"The merge was aborted. Run 'git merge $UPSTREAM_REF', resolve, commit, then re-run linux/update.sh."
  fi
fi

old_etags="$(cat "$ETAGS" 2>/dev/null || true)"
if ! "$REPO_ROOT/linux/fetch-deps.sh"; then
  [ "$AUTO" = 1 ] || die "fetching the HearthSim libraries failed"
  echo "auto-update: could not fetch the HearthSim libraries; keeping the ones here" >&2
fi
new_etags="$(cat "$ETAGS" 2>/dev/null || true)"

after="$(g rev-parse HEAD)"
inst="$(installed_commit)"
reasons=()
[ "$before" != "$after" ] && reasons+=("$(g rev-list --count "$before..$after") new commit(s)")
[ "$old_etags" != "$new_etags" ] && reasons+=("new HearthSim libraries")
[ -z "$inst" ] && reasons+=("nothing installed yet")
[ -n "$inst" ] && ! g merge-base --is-ancestor "$after" "$inst" 2>/dev/null && reasons+=("installed build $inst is older than the checkout")
[ "$FORCE" = 1 ] && reasons+=("--force")

if [ "${#reasons[@]}" -eq 0 ]; then
  note "Already up to date ($(cat "$DEST/VERSION"))."
  exit 0
fi
summary="$(IFS=,; echo "${reasons[*]}" | sed 's/,/, /g')"
note "Rebuilding: $summary"
notify "Updating the deck tracker" "$summary"$'\n'"The tracker starts when the build finishes."

# Build first and install only what built: a broken upstream merge then costs nothing but time,
# and the tracker keeps starting from the previous install.
"$REPO_ROOT/linux/build.sh" Release || fail "the build failed; the installed build is unchanged"
HDT_SKIP_BUILD=1 "$REPO_ROOT/linux/install.sh" || fail "installing the new build failed"
notify "Deck tracker updated" "$(cat "$DEST/VERSION" 2>/dev/null || echo "$summary")"
