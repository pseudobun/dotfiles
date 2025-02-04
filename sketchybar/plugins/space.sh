#!/bin/bash

update() {
  source "$CONFIG_DIR/colors.sh"
  COLOR=$TRANSPARENT
  if [ "$SELECTED" = "true" ]; then
    COLOR=$GREY
  fi
  sketchybar --animate sin 30 --set $NAME \
    background.color=$COLOR \
    label.highlight=$SELECTED \
    icon.highlight=$SELECTED
}

mouse_clicked() {
  if [ "$BUTTON" = "right" ]; then
    yabai -m space --destroy $SID
  else
    yabai -m space --focus $SID 2>/dev/null
  fi
}

case "$SENDER" in
"mouse.clicked")
  mouse_clicked
  ;;
*)
  update
  ;;
esac
