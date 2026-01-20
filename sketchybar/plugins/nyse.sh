#!/bin/bash

TZ_NY="America/New_York"

OPEN_MIN=$((9 * 60 + 30))  # 09:30
CLOSE_MIN=$((16 * 60))     # 16:00

update() {
  # Load colors so we can color-code open (green) vs closed (red)
  source "$CONFIG_DIR/colors.sh"

  # Current time in New York
  local dow hour min total_min
  dow=$(TZ=$TZ_NY date +%u)   # 1 = Mon, ... 7 = Sun
  hour=$(TZ=$TZ_NY date +%H)
  min=$(TZ=$TZ_NY date +%M)

  # Strip any leading zeros for arithmetic safety
  total_min=$((10#$hour * 60 + 10#$min))

  local mins_left is_open days_ahead

  # Market open on weekdays between OPEN_MIN and CLOSE_MIN
  if [ "$dow" -ge 1 ] && [ "$dow" -le 5 ] && \
     [ "$total_min" -ge "$OPEN_MIN" ] && [ "$total_min" -lt "$CLOSE_MIN" ]; then
    is_open=1           # countdown to close
    mins_left=$((CLOSE_MIN - total_min))
  else
    # Countdown to next open
    is_open=0
    if [ "$dow" -ge 1 ] && [ "$dow" -le 4 ] && [ "$total_min" -ge "$CLOSE_MIN" ]; then
      # After close Mon–Thu -> next day
      days_ahead=1
    elif [ "$dow" -eq 5 ] && [ "$total_min" -ge "$CLOSE_MIN" ]; then
      # After close Friday -> Monday
      days_ahead=3
    elif [ "$dow" -eq 6 ]; then
      # Saturday -> Monday
      days_ahead=2
    elif [ "$dow" -eq 7 ]; then
      # Sunday -> Monday
      days_ahead=1
    else
      # Before open on a weekday
      days_ahead=0
    fi

    if [ "$days_ahead" -eq 0 ]; then
      mins_left=$((OPEN_MIN - total_min))
    else
      mins_left=$((days_ahead * 1440 - total_min + OPEN_MIN))
    fi
  fi

  if [ "$mins_left" -lt 0 ]; then
    mins_left=0
  fi

  local hours_left mins_only
  hours_left=$((mins_left / 60))
  mins_only=$((mins_left % 60))

  local label color
  if [ "$is_open" -eq 1 ]; then
    # Market is open – counting down until close (green)
    if [ "$hours_left" -gt 0 ]; then
      label=$(printf "Closes in %dh%02dm" "$hours_left" "$mins_only")
    else
      label=$(printf "Closes in %dm" "$mins_only")
    fi
    color=$GREEN
  else
    # Market is closed – counting down until next open (red)
    if [ "$hours_left" -gt 0 ]; then
      label=$(printf "Opens in %dh%02dm" "$hours_left" "$mins_only")
    else
      label=$(printf "Opens in %dm" "$mins_only")
    fi
    color=$RED
  fi

  sketchybar --set "$NAME" label="$label" label.color="$color"
}

case "$SENDER" in
  "routine" | "forced")
    update
    ;;
  "system_woke")
    sleep 10 && update
    ;;
esac

