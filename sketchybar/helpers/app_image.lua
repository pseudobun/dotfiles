-- Apps sketchybar-app-font has no glyph for (paw, hop, …) show their own icon instead:
-- sketchybar draws "app.<bundle id>" images. Bundle ids are looked up once and cached.
local app_icons = require("app_icons")

local M = {}
local ids = { ["paw"] = "com.pseudobun.paw", ["hop"] = "lutra-labs.hop" }

function M.bundle_id(app)
  if ids[app] ~= nil then return ids[app] or nil end
  local f = io.popen("osascript -e 'id of app \"" .. app:gsub('"', '\\"'):gsub("'", "'\\''") .. "\"' 2>/dev/null")
  local id = f and f:read("*l") or nil
  if f then f:close() end
  ids[app] = (id and id ~= "") and id or false
  return ids[app] or nil
end

-- The glyph to show and, when the font has none, the image to show instead.
function M.icon(app)
  local glyph = app_icons.get(app)
  if glyph ~= app_icons.default then return glyph, nil end
  local id = M.bundle_id(app)
  return id and "" or glyph, id and ("app." .. id) or nil
end

return M
