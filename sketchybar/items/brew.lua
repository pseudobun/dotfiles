-- Outdated count, cached by plugins/brew_refresh.sh (LaunchAgent sh.pseudobun.brew-refresh)
-- because brew overflows sketchybar's fd cap when run inside the bar.
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local island = require("island")

local cache = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/sketchybar/brew_outdated"

sbar.add("event", "brew_update")

local e1 = island.edge("left")
local brew = sbar.add("item", "brew", {
  position = "left",
  update_freq = 3600,
  icon = {
    string = icons.brew,
    font = { family = settings.font.symbols, style = "Regular", size = 14.0 },
  },
  label = { string = "?" },
})
local e2 = island.edge("left")

local function read_count()
  local f = io.open(cache, "r")
  if not f then return nil end
  local s = f:read("a"):gsub("%s", "")
  f:close()
  return s
end

local function update(env)
  if env and (env.SENDER == "routine" or env.SENDER == "forced") then
    sbar.exec("launchctl kickstart gui/$(id -u)/sh.pseudobun.brew-refresh >/dev/null 2>&1 &")
  end
  local raw = read_count() or "?"
  local stale = raw:sub(-1) == "!"
  local n = tonumber((raw:gsub("!", "")))
  local color, label = colors.muted, raw
  if stale or not n then color = colors.bad
  elseif n == 0 then color, label = colors.good, icons.check
  elseif n < 10 then color = colors.fg
  elseif n < 30 then color = colors.warn
  else color = colors.bad end
  brew:set({
    icon = { color = color },
    label = {
      string = label,
      color = color,
      font = n == 0 and { family = settings.font.symbols, style = "Bold", size = 12.0 }
        or { family = settings.font.text, style = "Bold", size = 12.0 },
    },
  })
end

brew:subscribe({ "routine", "forced", "brew_update" }, update)
brew:subscribe("mouse.clicked", function()
  sbar.exec("launchctl kickstart gui/$(id -u)/sh.pseudobun.brew-refresh >/dev/null 2>&1 &")
end)

island.wrap("brew.island", { e1, brew.name, e2 })
