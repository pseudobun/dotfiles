#!/bin/bash

source "$CONFIG_DIR/colors.sh"

# Homebrew can occasionally error with a Ruby stacktrace; suppress stderr so it
# doesn't spam sketchybar logs, and fall back to 0 when output is empty.
COUNT="$(brew outdated 2>/dev/null | wc -l | tr -d ' ')"
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
