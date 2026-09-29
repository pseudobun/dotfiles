#!/bin/bash

update() {
    source "$CONFIG_DIR/env.local.sh"
    source "$CONFIG_DIR/colors.sh"
    source "$CONFIG_DIR/icons.sh"
    DATA=$(curl -sf --max-time 10 "https://api.binance.com/api/v3/ticker/24hr?symbol=BTCUSDT")
    RAW_PRICE=$(echo "$DATA" | jq -r '.lastPrice // empty' 2>/dev/null)
    RAW_CHANGE=$(echo "$DATA" | jq -r '.priceChangePercent // empty' 2>/dev/null)
    # Keep the last shown value if the API is unreachable
    [ -z "$RAW_PRICE" ] || [ -z "$RAW_CHANGE" ] && return
    PRICE=$(env LC_ALL=en_US.UTF-8 printf "\$%'.0f\n" "$RAW_PRICE")
    CHANGE=$(printf "%.2f\n" "$RAW_CHANGE")
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
