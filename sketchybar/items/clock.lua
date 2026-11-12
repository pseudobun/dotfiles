local colors = require("colors")
local settings = require("settings")
local island = require("island")

local e_r = island.edge("right")
local clock = sbar.add("item", "clock", {
  position = "right",
  update_freq = 15,
  icon = {
    font = { family = settings.font.text, style = "Medium", size = 11.5 },
    color = colors.muted,
    padding_right = 6,
  },
  label = {
    font = { family = settings.font.text, style = "Bold", size = 13.0 },
    color = colors.gold,
  },
})
local e_l = island.edge("right")

local function update()
  clock:set({ icon = { string = os.date("%a %d") }, label = { string = os.date("%H:%M") } })
end

clock:subscribe({ "routine", "forced", "system_woke" }, update)

-- Zen mode: click the clock to hide everything except spaces and the clock.
local ZEN = { "/front_app.*/", "/markets.*/", "/system.*/", "/cpu.*/", "/brew.*/", "/apple.*/" }
local zen = false
sbar.add("event", "zen_off") -- items that hide themselves (system.vpn) re-apply their state
clock:subscribe("mouse.clicked", function()
  zen = not zen
  for _, pattern in ipairs(ZEN) do
    sbar.set(pattern, { drawing = not zen })
  end
  if not zen then sbar.trigger("zen_off") end
end)

island.wrap("clock.island", { e_r, clock.name, e_l })
island.gap("right")
