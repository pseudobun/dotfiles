#!/bin/sh
# Bridges `media-control stream` to sketchybar: one media_update event per change.
# INFO = playing<US>title<US>artist (title empty when nothing is loaded).
media-control stream --no-diff --no-artwork --debounce=250 \
  | jq --unbuffered -r '.payload | [(.playing // false | tostring), (.title // ""), (.artist // "")] | join("\u001f")' \
  | while IFS= read -r l; do sketchybar --trigger media_update INFO="$l"; done
