#!/bin/bash

update() {
    source "$CONFIG_DIR/env.local.sh"
    source "$CONFIG_DIR/colors.sh"
    source "$CONFIG_DIR/icons.sh"
    DATA=$(curl -s "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true")
    PRICE=$(echo "$DATA" | jq -r .bitcoin.usd | xargs env LC_ALL=en_US.UTF-8 printf "\$%'.0f\n")
    CHANGE=$(echo "$DATA" | jq -r .bitcoin.usd_24h_change | xargs printf "%.2f\n")
    if (($(echo "$CHANGE >= 0" | bc -l))); then
        COLOR=$GREEN
        ICON="▲"
    else
        COLOR=$RED
        ICON="▼"
    fi
    PADDING=0
    args=(--set $NAME label=$PRICE icon.color=$ORANGE)
    btc_price=(
        label="${CHANGE}%"
        icon="${ICON}"
        icon.padding_left="$PADDING"
        label.padding_right="$PADDING"
        icon.color=$COLOR
        label.color=$COLOR
        icon.background.color=$TRANSPARENT
        drawing=on
    )

    args+=(--set btc.price "${btc_price[@]}")

    sketchybar -m "${args[@]}" >/dev/null
}

popup() {
    sketchybar --set $NAME popup.drawing=$1
}

case "$SENDER" in
"routine" | "forced")
    update
    ;;
"system_woke")
    sleep 10 && update # Wait for network to connect
    ;;
"mouse.entered")
    popup on
    ;;
"mouse.exited" | "mouse.exited.global")
    popup off
    ;;
"mouse.clicked")
    popup toggle
    ;;
esac
