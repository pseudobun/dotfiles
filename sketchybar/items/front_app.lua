local colors = require("colors")
local settings = require("settings")
local island = require("island")
local app_image = require("app_image")

local e1 = island.edge("left")
local front_app = sbar.add("item", "front_app", {
  position = "left",
  icon = { font = { family = settings.font.apps, style = "Regular", size = 14.0 }, color = colors.gold },
  label = { font = { family = settings.font.text, style = "SemiBold", size = 12.0 }, max_chars = 20 },
  updates = true,
})
local e2 = island.edge("left")

front_app:subscribe("front_app_switched", function(env)
  local app = env.INFO
  local glyph, image = app_image.icon(app)
  front_app:set({
    icon = {
      string = glyph,
      width = image and 20 or "dynamic",
      background = image and { drawing = true, image = { string = image, scale = 0.5 } } or { drawing = false },
    },
    label = { string = app },
  })
  -- The app's own colour from paw (picked from its icon); gold when it has none.
  sbar.exec("paw color '" .. app:gsub("'", "'\\''") .. "' 2>/dev/null", function(out)
    local c = tonumber(type(out) == "string" and out:match("0x%x+") or "")
    front_app:set({ icon = { color = c or colors.gold } })
  end)
end)

island.wrap("front_app.island", { e1, front_app.name, e2 })
island.gap("left")
