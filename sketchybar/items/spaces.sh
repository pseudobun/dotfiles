#!/bin/bash

SPACE_ICONS=("1" "2" "3" "4" "5" "6" "7" "8" "9" "10" "11" "12")

# Destroy space on right click, focus space on left click.
# New space by left clicking separator (>)

sid=0
spaces=()
for i in "${!SPACE_ICONS[@]}"; do
  sid=$(($i + 1))

  space=(
    space=$sid
    icon="${SPACE_ICONS[i]}"
    icon.padding_left=10
    icon.padding_right=2
    padding_left=2
    padding_right=2
    label.padding_right=20
    icon.highlight_color=$WHITE
    icon.color=$LIGHT_GREY
    label.color=$LIGHT_GREY
    label.highlight_color=$WHITE
    label.font="sketchybar-app-font:Regular:12.0"
    label.y_offset=-1
    background.height=24
    background.border_width=0
    background.color=$TRANSPARENT
    background.corner_radius=4
    script="$PLUGIN_DIR/space.sh"
  )

  sketchybar --add space space.$sid left \
    --set space.$sid "${space[@]}" \
    --subscribe space.$sid mouse.clicked \
    space_change
done

space_creator=(
  icon=􀆊
  icon.font="$FONT:Regular:16.0"
  label.drawing=off
  display=active
  click_script='yabai -m space --create'
  script="$PLUGIN_DIR/space_windows.sh"
  icon.color=$WHITE
)

sketchybar --add item space_creator left \
  --set space_creator "${space_creator[@]}" \
  --subscribe space_creator space_windows_change
