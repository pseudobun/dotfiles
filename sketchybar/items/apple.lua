local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local island = require("island")

local apple = sbar.add("item", "apple", {
  position = "left",
  icon = {
    string = icons.apple,
    font = { family = settings.font.symbols, style = "Black", size = 15.0 },
    color = colors.fg,
    padding_left = 4,
    padding_right = 4,
  },
  label = { drawing = false },
  popup = { align = "left" },
})

local function entry(name, icon, label, cmd)
  local it = sbar.add("item", "apple." .. name, {
    position = "popup.apple",
    icon = { string = icon, font = { family = settings.font.symbols, style = "Regular", size = 13.0 }, color = colors.muted, padding_left = 4, padding_right = 8 },
    label = { string = label, padding_right = 8 },
  })
  it:subscribe("mouse.clicked", function()
    sbar.exec(cmd)
    apple:set({ popup = { drawing = false } })
  end)
end

entry("prefs", icons.prefs, "Settings", "open -a 'System Settings'")
entry("activity", icons.activity, "Activity Monitor", "open -a 'Activity Monitor'")
entry("lock", icons.lock, "Lock screen", "pmset displaysleepnow")

apple:subscribe("mouse.clicked", function() apple:set({ popup = { drawing = "toggle" } }) end)
apple:subscribe("mouse.exited.global", function() apple:set({ popup = { drawing = false } }) end)

island.gap("left")
