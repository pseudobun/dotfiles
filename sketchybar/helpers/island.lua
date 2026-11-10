-- "Islands": a rounded, filled bracket behind a group of items.
-- Padding model (keeps every island symmetric):
--   * every item: padding_left = padding_right = settings.item_pad
--   * icon: 0 left, settings.icon_gap right (0 when the item has no label)
--   * label: 0 / 0
--   * each island starts and ends with an edge spacer of settings.edge
--   so: island edge = edge + item_pad, gap between items = 2 * item_pad.
local colors = require("colors")
local settings = require("settings")

local M = {}
local n = 0

local function blank(name, position, width)
  return sbar.add("item", name, {
    position = position,
    width = width,
    padding_left = 0,
    padding_right = 0,
    icon = { drawing = false },
    label = { drawing = false },
    background = { drawing = false },
  })
end

function M.edge(position)
  n = n + 1
  return blank("edge." .. n, position, settings.edge).name
end

function M.gap(position)
  n = n + 1
  return blank("gap." .. n, position, settings.gap)
end

-- members: item names in the order they were added (edges included)
function M.wrap(name, members, opts)
  opts = opts or {}
  return sbar.add("bracket", name, members, {
    background = {
      color = opts.color or colors.island,
      border_color = colors.border,
      border_width = 1,
      corner_radius = settings.island_radius,
      height = settings.island_height,
    },
  })
end

return M
