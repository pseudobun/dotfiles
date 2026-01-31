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

  # Format time as 1d6h30m, 6h30m, or 45m
  local days_left hours_left mins_only time_part
  days_left=$((mins_left / 1440))
  hours_left=$(((mins_left % 1440) / 60))
  mins_only=$((mins_left % 60))

  if [ "$days_left" -gt 0 ]; then
    time_part=$(printf "%dd%dh%02dm" "$days_left" "$hours_left" "$mins_only")
  elif [ "$hours_left" -gt 0 ]; then
    time_part=$(printf "%dh%02dm" "$hours_left" "$mins_only")
  else
    time_part=$(printf "%dm" "$mins_only")
  fi

  local label color
  if [ "$is_open" -eq 1 ]; then
    label="Closes in $time_part"
    color=$GREEN
  else
    label="Opens in $time_part"
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

