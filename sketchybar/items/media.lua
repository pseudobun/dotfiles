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
  update_freq = 3,
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

now:subscribe({ "routine", "forced" }, function()
  sbar.exec("media-control get 2>/dev/null | jq -c '{playing, title, artist}' 2>/dev/null", function(info)
    local was = playing
    if type(info) == "table" and info.title then
      playing = info.playing == true
      local text = info.artist and info.artist ~= "" and (info.artist .. " — " .. info.title) or info.title
      now:set({
        icon = { string = playing and icons.media.pause or icons.media.play },
        label = { string = text, color = playing and colors.fg or colors.muted },
      })
      -- keep showing a paused track; hide only when nothing is loaded
      playing = true
    else
      playing = false
    end
    if was ~= playing then apply() end
  end)
end)

now:subscribe("mouse.clicked", function() sbar.exec("media-control toggle-play-pause") end)
prev:subscribe("mouse.clicked", function() sbar.exec("media-control previous-track") end)
nxt:subscribe("mouse.clicked", function() sbar.exec("media-control next-track") end)
