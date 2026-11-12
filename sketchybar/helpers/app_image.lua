-- Apps sketchybar-app-font has no glyph for (paw, hop, …) show their own icon instead:
-- sketchybar draws "app.<bundle id>" images. Bundle ids are looked up once, asynchronously
-- (osascript is slow and would block the event loop), and cached.
local app_icons = require("app_icons")

local M = {}
-- bundle id, or false when the app has none sketchybar can draw
local ids = { ["paw"] = "com.pseudobun.paw", ["hop"] = "lutra-labs.hop" }
local waiting = {}

local function lookup(app)
  local q = app:gsub('"', '\\"'):gsub("'", "'\\''")
  sbar.exec(
    "osascript -e 'set i to id of application \"" .. q .. "\"' "
      .. "-e 'return i & \"|\" & POSIX path of (path to application \"" .. q .. "\")' 2>/dev/null",
    function(out)
      local id, path = tostring(out or ""):match("^([^|\n]+)|([^\n]+)")
      -- only real .app bundles: agents inside frameworks (SecurityAgent.bundle, …) have an id
      -- but sketchybar cannot load an image for them
      ids[app] = (id and path and path:match("%.app/$")) and id or false
      local cbs = waiting[app] or {}
      waiting[app] = nil
      for _, cb in ipairs(cbs) do cb() end
    end
  )
end

-- The glyph to show and, when the font has none, the image to show instead.
-- On a cache miss it returns the default glyph and calls on_ready once the lookup is done.
function M.icon(app, on_ready)
  local glyph = app_icons.get(app)
  if glyph ~= app_icons.default then return glyph, nil end
  local id = ids[app]
  if id == nil then
    local first = waiting[app] == nil
    waiting[app] = waiting[app] or {}
    if on_ready then table.insert(waiting[app], on_ready) end
    if first then lookup(app) end
    return glyph, nil
  end
  if id then return "", "app." .. id end
  return glyph, nil
end

return M
