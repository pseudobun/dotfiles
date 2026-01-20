#!/bin/bash

nyse_timer=(
  icon=󰠟
  icon.font="$FONT:Regular:22.0"
  icon.padding_left=4
  icon.padding_right=2
  label.align=left
  update_freq=60
  script="$PLUGIN_DIR/nyse.sh"
)

# Standalone item on the right side of the bar, placed near ETH.
sketchybar --add item nyse.timer right \
  --set nyse.timer "${nyse_timer[@]}" \
  --subscribe nyse.timer system_woke

