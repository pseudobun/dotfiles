#!/bin/bash

btc_icon=(
    popup.horizontal=on
    padding_right=6
    update_freq=60
    icon=$BTC
    label=?
    icon.font="$FONT:Regular:15.0"
    icon.color=$ORANGE
    popup.align=right
    script="$PLUGIN_DIR/btc.sh"
)

btc_price=(
    drawing=off
    background.corner_radius=12
    padding_left=7
    padding_right=7
)

sketchybar --add event btc.update \
    --add item btc.icon right \
    --set btc.icon "${btc_icon[@]}" \
    \
    --add item btc.price popup.btc.icon \
    --set btc.price "${btc_price[@]}" \
    --subscribe btc.icon mouse.entered \
    mouse.exited \
    mouse.exited.global \
    system_woke \
    btc.update
