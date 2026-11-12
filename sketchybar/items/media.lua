-- Now playing in the centre — only on wide external displays (the built-in has the notch there).
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local island = require("island")

local symbols = { family = settings.font.symbols, style = "Regular", size = 12.0 }

local prev = sbar.add("item", "media.prev", {
  position = "center",
  icon = { string = icons.media.prev, font = symbols, color = colors.muted, padding_right = 0 },
  label = { drawing = false },
  drawing = false,
})
local now = sbar.add("item", "media.now", {
  position = "center",
  updates = true,
  icon = { string = icons.media.note, font = symbols, color = colors.gold },
  label = { max_chars = 48, font = { family = settings.font.text, style = "Medium", size = 12.0 } },
  drawing = false,
})
local nxt = sbar.add("item", "media.next", {
  position = "center",
  icon = { string = icons.media.next, font = symbols, color = colors.muted, padding_right = 0 },
  label = { drawing = false },
  drawing = false,
})
local bracket = island.wrap("media.island", { prev.name, now.name, nxt.name })

local MIN_WIDTH = 1800 -- points
local external = nil -- comma list of arrangement ids, or false when only the built-in is connected
local playing = false

local function apply()
  local show = playing and external and true or false
  for _, it in ipairs({ prev, now, nxt }) do
    it:set({ drawing = show, display = external or "active" })
  end
  bracket:set({ display = external or "active" })
end

local function detect_displays()
  sbar.exec("sketchybar --query displays", function(displays)
    if type(displays) ~= "table" then return end
    local ids = {}
    for _, d in ipairs(displays) do
      -- skip the notched built-in and narrow (e.g. portrait) screens where the centre collides with the right side
      local wide = type(d.frame) == "table" and tonumber(d.frame.w) and tonumber(d.frame.w) >= MIN_WIDTH
      if d.DirectDisplayID ~= settings.builtin_display and wide then
        ids[#ids + 1] = tostring(d["arrangement-id"])
      end
    end
    external = #ids > 0 and table.concat(ids, ",") or false
    apply()
  end)
end

-- Find the built-in display's id once (system_profiler is slow, so async).
sbar.exec(
  "system_profiler SPDisplaysDataType -json | jq -r '.SPDisplaysDataType[].spdisplays_ndrvs[]? | select(.spdisplays_connection_type==\"spdisplays_internal\") | ._spdisplays_displayID'",
  function(out)
    local id = tonumber(out and tostring(out):match("%d+"))
    if id then settings.builtin_display = id end
    detect_displays()
  end
)

now:subscribe("display_change", detect_displays)

-- One long-lived `media-control stream` pushes now-playing changes as a sketchybar event
-- (instead of polling `media-control get` every few seconds). INFO: playing<US>title<US>artist,
-- empty title when nothing is loaded. The old bridge goes when sketchybar loads.
local SEP = "\31"
sbar.add("event", "media_update")
local dir = os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar")
sbar.exec("pkill -f '[m]edia_stream.sh'; pkill -f '[m]edia-control stream'", function()
  sbar.exec(string.format("nohup %q >/dev/null 2>&1 &", dir .. "/plugins/media_stream.sh"))
end)

now:subscribe("media_update", function(env)
  local state, title, artist = tostring(env.INFO or ""):match("^([^" .. SEP .. "]*)" .. SEP .. "([^" .. SEP .. "]*)" .. SEP .. "(.*)$")
  local was = playing
  if title and title ~= "" then
    local is_playing = state == "true"
    local text = artist ~= "" and (artist .. " — " .. title) or title
    now:set({
      icon = { string = is_playing and icons.media.pause or icons.media.play },
      label = { string = text, color = is_playing and colors.fg or colors.muted },
    })
    -- keep showing a paused track; hide only when nothing is loaded
    playing = true
  else
    playing = false
  end
  if was ~= playing then apply() end
end)

now:subscribe("mouse.clicked", function() sbar.exec("media-control toggle-play-pause") end)
prev:subscribe("mouse.clicked", function() sbar.exec("media-control previous-track") end)
nxt:subscribe("mouse.clicked", function() sbar.exec("media-control next-track") end)
