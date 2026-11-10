#!/bin/bash

# Computes the number of outdated Homebrew packages (formulae + casks) and caches
# it, then nudges sketchybar to redraw the brew item.
#
# WHY THIS EXISTS: sketchybar spawns its plugins with a hard file-descriptor cap
# of 4096 (soft 256) and the plugin inherits sketchybar's own open fds. A full
# `brew outdated` opens many files/sockets at once — the API metadata for every
# formula plus a `plutil` subprocess per installed cask — and blows past that
# cap. brew then aborts with a Ruby stacktrace ("undefined method 'exitstatus'
# for nil" in SystemCommand::Result), which was swallowed by 2>/dev/null, so the
# count silently came back 0 and the bar showed the green "up to date" checkmark.
#
# Run this from a normal login shell (fd limit ~1048576) instead: the fish `brew`
# wrapper calls it, and a LaunchAgent can call it on a timer. The sketchybar
# plugin only ever reads the cached number, never runs brew itself.
#
# Usage: brew_refresh.sh [--update]
#   --update  run `brew update` first so the count reflects fresh metadata
#             (used by the hourly LaunchAgent sh.pseudobun.brew-refresh).

# launchd starts jobs with a 256 soft fd limit too — lift it before brew runs.
ulimit -n 65536 2>/dev/null || ulimit -n "$(ulimit -Hn)" 2>/dev/null

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
CACHE_FILE="$CACHE_DIR/brew_outdated"

mkdir -p "$CACHE_DIR"

if [ "$1" = "--update" ]; then
  /opt/homebrew/bin/brew update --quiet >/dev/null 2>&1
fi

# On failure (e.g. unaccepted Xcode license) keep the last good count and mark
# it stale with "!" instead of caching a bogus 0 that renders as "up to date".
if OUTDATED="$(/opt/homebrew/bin/brew outdated 2>/dev/null)"; then
  COUNT="$(printf '%s' "$OUTDATED" | grep -c .)"
  printf '%s' "$COUNT" > "$CACHE_FILE"
else
  LAST="$(tr -d ' \n!' < "$CACHE_FILE" 2>/dev/null)"
  printf '%s!' "${LAST:-?}" > "$CACHE_FILE"
fi

# Redraw the bar item (no-op if sketchybar isn't running).
command -v sketchybar >/dev/null 2>&1 && sketchybar --trigger brew_update
