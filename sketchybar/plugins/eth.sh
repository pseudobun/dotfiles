#!/bin/bash

update() {
    source "$CONFIG_DIR/env.local.sh"
    source "$CONFIG_DIR/colors.sh"
    source "$CONFIG_DIR/icons.sh"
    RAW_PRICE=$(curl -sf --max-time 10 "https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDT" | jq -r '.price // empty' 2>/dev/null)
    # Keep the last shown value if the API is unreachable
    [ -z "$RAW_PRICE" ] && return
    PRICE=$(env LC_ALL=en_US.UTF-8 printf "%'.2f\n" "$RAW_PRICE")
    GAS=$(curl -s "https://api.etherscan.io/v2/api?chainid=1&module=gastracker&action=gasoracle&apikey=${ETH_API_KEY}" | jq -r '.result.suggestBaseFee' | xargs printf "%.2f\n")
    COLOR=$GREEN
    ICON="$"
    PADDING=0
    args=(--set $NAME label=$GAS icon.color=$BLUE)
    eth_price=(
        label="$(echo "${PRICE}")"
        icon="${ICON}"
        icon.padding_left="$PADDING"
        label.padding_right="$PADDING"
        icon.color=$COLOR
        icon.background.color=$TRANSPARENT
        drawing=on
    )

    args+=(--set eth.price "${eth_price[@]}")

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
