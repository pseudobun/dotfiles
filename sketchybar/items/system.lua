local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local island = require("island")

local symbols = { family = settings.font.symbols, style = "Regular", size = 15.0 }

local e_r = island.edge("right")

-- battery ------------------------------------------------------------------
local battery = sbar.add("item", "system.battery", {
  position = "right",
  update_freq = 120,
  updates = true,
  icon = { font = symbols },
  label = { font = { family = settings.font.text, style = "Medium", size = 11.0 }, color = colors.muted },
})

local function battery_update()
  sbar.exec("pmset -g batt", function(out)
    local pct = tonumber(out:match("(%d+)%%"))
    if not pct then
      battery:set({ drawing = false })
      return
    end
    local charging = out:find("AC Power") ~= nil
    local icon, color = icons.battery["100"], colors.fg
    if pct < 20 then icon, color = icons.battery["0"], colors.bad
    elseif pct < 30 then icon, color = icons.battery["25"], colors.warn
    elseif pct < 60 then icon, color = icons.battery["50"], colors.fg
    elseif pct < 90 then icon = icons.battery["75"] end
    if charging then icon, color = icons.battery.charging, colors.good end
    battery:set({ drawing = true, icon = { string = icon, color = color }, label = { string = pct .. "%" } })
  end)
end
battery:subscribe({ "routine", "forced", "power_source_change", "system_woke" }, battery_update)

-- wifi / vpn -----------------------------------------------------------------
local wifi = sbar.add("item", "system.wifi", {
  position = "right",
  -- SF Symbols wifi glyph ink overhangs its measured width by ~1pt; 2pt right
  -- padding keeps it inside the item window (label pad 3 keeps icon->label = 5)
  icon = { font = symbols, string = icons.wifi_off, padding_right = 2 },
  label = { width = 0, padding_left = 3, color = colors.muted, font = { family = settings.font.text, style = "Medium", size = 11.0 } },
})

local function wifi_update()
  sbar.exec("scutil --nwi", function(out)
    -- a VPN only counts when a utun interface carries IPv4 (macOS keeps idle utuns around)
    local v4 = out:match("IPv4 network interface information(.-)IPv6") or ""
    local vpn = v4:match("utun%d+%s*:") ~= nil
    local ip = v4:match("address%s*:%s*([%d%.]+)")
    local icon, color = icons.wifi_off, colors.dim
    if vpn then icon, color = icons.vpn, colors.wave
    elseif ip then icon, color = icons.wifi, colors.fg end
    wifi:set({ icon = { string = icon, color = color }, label = { string = vpn and "VPN" or (ip or "offline") } })
  end)
end
wifi:subscribe({ "wifi_change", "system_woke", "forced" }, wifi_update)
wifi:subscribe("mouse.clicked", function()
  local q = wifi:query()
  local open = q.label and tonumber(q.label.width) == 0
  sbar.animate("tanh", 15, function()
    wifi:set({ label = { width = open and "dynamic" or 0 } })
  end)
end)

-- cpu (mach helper pushes graph values + percent) ------------------------------
local helper_dir = (os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar")) .. "/helper"
sbar.exec(string.format(
  "killall helper 2>/dev/null; cd %q && make >/dev/null 2>&1; RED=%s ORANGE=%s YELLOW=%s LABEL_COLOR=%s ./helper git.felix.helper >/dev/null 2>&1 & "
    -- sketchybar looks the helper up only when mach_helper is set: at login the build can
    -- take longer than sketchybar's start, so point it at the helper again once it runs
    .. "sleep 1; sketchybar --set cpu.percent mach_helper=git.felix.helper",
  helper_dir, colors.hex(colors.bad), colors.hex(colors.warn), colors.hex(colors.gold), colors.hex(colors.muted)
))

-- top process (small, above) stacked over the total percent (below)
sbar.add("item", "cpu.top", {
  position = "right",
  width = 0,
  y_offset = 6,
  icon = { drawing = false },
  label = {
    string = "",
    color = colors.muted,
    align = "left",
    width = 58,
    font = { family = settings.font.text, style = "Medium", size = 8.5 },
  },
})

sbar.add("item", "cpu.percent", {
  position = "right",
  update_freq = 2,
  mach_helper = "git.felix.helper",
  y_offset = -5,
  padding_left = 2,
  icon = { drawing = false },
  label = {
    string = "––%",
    align = "left",
    width = 58,
    font = { family = settings.font.text, style = "Bold", size = 11.0 },
  },
})

-- graph sits inside its own rounded frame with a few points of inset, so the
-- line and fill never touch (or clip over) the frame's border
local inset_w, graph_w = 3, 42
local function inset(name)
  return sbar.add("item", name, {
    position = "right",
    width = inset_w,
    padding_left = 0,
    padding_right = 0,
    icon = { drawing = false },
    label = { drawing = false },
  }).name
end

-- The frame is a zero-width item whose background reaches left over the inset
-- spacers and the graph (an item can only belong to one bracket, and the graph's
-- own background would set the graph's height).
sbar.add("item", "cpu.graph.frame", {
  position = "right",
  width = 0,
  padding_left = 0,
  padding_right = 0,
  icon = { drawing = false },
  -- the frame lives on the label: an item background takes the item width (0)
  label = {
    string = "",
    width = graph_w + 2 * inset_w,
    padding_left = 0,
    padding_right = 0,
    background = {
      drawing = true,
      color = colors.alpha(colors.fg, 0.05),
      border_color = colors.alpha(colors.fg, 0.10),
      border_width = 1,
      corner_radius = 5,
      height = 17,
    },
  },
  background = { drawing = false },
})

local inset_r = inset("cpu.graph.inset_r")
sbar.add("graph", "cpu.graph", graph_w, {
  position = "right",
  padding_left = 0,
  padding_right = 0,
  graph = {
    color = colors.wave,
    fill_color = colors.alpha(colors.wave, 0.22),
    line_width = 1.2,
  },
  background = { drawing = true, color = colors.transparent, height = 11 },
  icon = { drawing = false },
  label = { drawing = false },
})
local inset_l = inset("cpu.graph.inset_l")

local e_l = island.edge("right")

island.wrap("system.island", { e_r, battery.name, wifi.name, "cpu.top", "cpu.percent", "cpu.graph.frame", inset_r, "cpu.graph", inset_l, e_l })
island.gap("right")
