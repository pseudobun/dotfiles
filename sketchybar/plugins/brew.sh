#!/bin/bash

source "$CONFIG_DIR/colors.sh"

# Read the count cached by brew_refresh.sh (run from a full login shell — see the
# header of that script for why brew can't run inside a sketchybar plugin).
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar/brew_outdated"

if [ -r "$CACHE_FILE" ]; then
  COUNT="$(tr -d ' \n' < "$CACHE_FILE")"
else
  # No cache yet: fall back to a formula-only count, which is light enough to run
  # within sketchybar's fd cap (the cask path is what overflows it). Still shows a
  # useful number until the first full refresh populates the cache.
  export HOMEBREW_DOWNLOAD_CONCURRENCY=1
  COUNT="$(/opt/homebrew/bin/brew outdated --formula 2>/dev/null | wc -l | tr -d ' ')"
fi
[ -z "$COUNT" ] && COUNT=0

COLOR=$RED

case "$COUNT" in
  [3-5][0-9]) COLOR=$ORANGE
  ;;
  [1-2][0-9]) COLOR=$YELLOW
  ;;
  [1-9]) COLOR=$WHITE
  ;;
  0) COLOR=$GREEN
     COUNT=􀆅
  ;;
esac

sketchybar --set $NAME label=$COUNT icon.color=$COLOR
