local colors = require("colors")
local settings = require("settings")

sbar.bar({
  height = settings.bar_height,
  color = colors.bar,
  position = "top",
  sticky = true,
  topmost = "window",
  shadow = false,
  -- line the outer edges up with paw's window edges (34: stack indicator 26 + 4 gaps):
  -- left = 34 - apple item pad (5) - apple icon pad (4); right = clock island edge
  padding_left = 25,
  padding_right = 34,
  margin = 0,
  y_offset = 0,
  notch_width = 210,
})

sbar.default({
  updates = "when_shown",
  icon = {
    font = { family = settings.font.text, style = "Bold", size = 13.0 },
    color = colors.fg,
    padding_left = 0,
    padding_right = settings.icon_gap,
  },
  label = {
    font = { family = settings.font.text, style = "Medium", size = 12.0 },
    color = colors.fg,
    padding_left = 0,
    padding_right = 0,
  },
  background = { height = settings.island_height, corner_radius = settings.island_radius },
  popup = {
    background = {
      color = colors.popup,
      border_color = colors.border,
      border_width = 1,
      corner_radius = 10,
      shadow = { drawing = true },
    },
    blur_radius = 30,
  },
  padding_left = settings.item_pad,
  padding_right = settings.item_pad,
  scroll_texts = true,
})

-- left
require("items.apple")
require("items.spaces")
require("items.front_app")
require("items.brew") -- left: the right side has no room left before the notch
-- center (external displays only — the built-in has the notch there)
require("items.media")
-- right, rightmost first
require("items.clock")
require("items.system")
require("items.markets")
