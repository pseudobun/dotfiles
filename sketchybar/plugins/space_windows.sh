#!/bin/bash

if [ "$SENDER" = "space_windows_change" ]; then
  args=(--animate sin 10)

  space="$(echo "$INFO" | jq -r '.space')"
  apps="$(echo "$INFO" | jq -r '.apps | keys[]')"

  icon_strip=" "
  if [ "${apps}" != "" ]; then
    while read -r app; do
      if [ "$app" == "iTerm2" ] || [ "$app" == "Screen Studio" ] || [ "$app" == "Raycast" ] || [ "$app" == "Dropover" ] || [ "$app" == "Perplexity" ]; then
        continue
      fi
      icon_strip+=" $($CONFIG_DIR/plugins/icon_map.sh "$app")"
    done <<<"${apps}"
  fi
  args+=(--set space.$space label="$icon_strip")

  sketchybar -m "${args[@]}"
fi
