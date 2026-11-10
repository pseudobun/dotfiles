#!/bin/bash
# paw hook: displaysChanged: "~/.config/sketchybar/plugins/displays_changed.sh"
# sketchybar doesn't reliably follow display changes: it can keep stale bar windows, or draw no
# bar on new displays, and its own --query can't tell (FelixKratz/SketchyBar#866). paw runs this
# once the displays have settled, so restart it right away (~1.5 s).
echo "$(date '+%F %T') paw ${PAW_DISPLAYS:-?}: restarting sketchybar" >>"$HOME/Library/Logs/paw-displays.log"
label=$(launchctl list 2>/dev/null | awk '/sketchybar/ { print $3; exit }')
if [[ -n "$label" ]]; then
    launchctl kickstart -k "gui/$(id -u)/$label"
else
    pkill -x sketchybar; sleep 0.5; sketchybar >/dev/null 2>&1 &
fi
