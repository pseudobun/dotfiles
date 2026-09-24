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

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar"
CACHE_FILE="$CACHE_DIR/brew_outdated"

mkdir -p "$CACHE_DIR"

COUNT="$(/opt/homebrew/bin/brew outdated 2>/dev/null | wc -l | tr -d ' ')"
[ -z "$COUNT" ] && COUNT=0

printf '%s' "$COUNT" > "$CACHE_FILE"

# Redraw the bar item (no-op if sketchybar isn't running).
command -v sketchybar >/dev/null 2>&1 && sketchybar --trigger brew_update
