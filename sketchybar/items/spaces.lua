local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local island = require("island")
local app_image = require("app_image")

-- Workspaces come from paw (`paw query --json`), not yabai. One long-lived `paw subscribe`
-- turns paw's events into sketchybar events (a snapshot first; it reconnects when paw
-- restarts), instead of a hook per event.
local IGNORED = { ["Screen Studio"] = true, ["Raycast"] = true, ["Dropover"] = true }
local SLOTS = 10
local APPS = 6 -- app icons per workspace
local slots, apps, names = {}, {}, {}
local first_edge = island.edge("left")

sbar.add("event", "paw_snapshot")
sbar.add("event", "paw_workspaceChanged")
sbar.add("event", "paw_windowsChanged")
sbar.add("event", "paw_zoomChanged")

-- "[p]aw" keeps pkill from matching its own shell; the old bridge goes when sketchybar loads.
sbar.exec("pkill -f '[p]aw subscribe.*--trigger paw_'", function()
  sbar.exec("nohup paw subscribe workspaceChanged,windowsChanged,zoomChanged --reconnect "
    .. "--exec 'sketchybar --trigger paw_$PAW_EVENT' >/dev/null 2>&1 &")
end)

local function focus(i, env)
  local name = names[i]
  if not name then return end
  if env.BUTTON == "right" then
    sbar.exec("paw 'workspace " .. name .. "; workspace close'")
  else
    sbar.exec("paw workspace " .. name)
  end
end

for i = 1, SLOTS do
  local slot = sbar.add("item", "space." .. i, {
    position = "left",
    drawing = false,
    icon = {
      string = tostring(i),
      font = { family = settings.font.text, style = "Bold", size = 12.0 },
      color = colors.dim,
      highlight_color = colors.gold,
      padding_left = 7,
      padding_right = 5,
    },
    label = { drawing = false },
    padding_left = 2,
    padding_right = 0,
  })
  slot:subscribe("mouse.clicked", function(env) focus(i, env) end)
  slots[i] = slot

  -- One item per app so each icon can have the app's own colour (paw picks it from the app icon).
  apps[i] = {}
  for j = 1, APPS do
    local app = sbar.add("item", "space." .. i .. ".app." .. j, {
      position = "left",
      drawing = false,
      icon = { drawing = false },
      label = {
        font = { family = settings.font.apps, style = "Regular", size = 13.0 },
        padding_left = 1,
        padding_right = 1,
        y_offset = 0,
      },
      padding_left = 0,
      padding_right = 0,
    })
    app:subscribe("mouse.clicked", function(env) focus(i, env) end)
    apps[i][j] = app
  end

  local members = { slot.name }
  for j = 1, APPS do members[#members + 1] = apps[i][j].name end
  slots[i].bracket = sbar.add("bracket", "space." .. i .. ".bg", members, {
    background = { color = colors.transparent, corner_radius = 7, height = 22 },
  })
end

local creator = sbar.add("item", "space.creator", {
  position = "left",
  icon = {
    string = icons.plus,
    font = { family = settings.font.symbols, style = "Semibold", size = 11.0 },
    color = colors.muted,
    padding_left = 7,
    padding_right = 7,
  },
  label = { drawing = false },
  padding_left = 0,
  padding_right = 0,
  display = "active",
  updates = true,
})
creator:subscribe("mouse.clicked", function()
  sbar.exec("paw workspace new")
end)

-- The app's colour from paw; full on the focused workspace, faded elsewhere.
local function app_color(w, selected)
  local c = tonumber(w.color or "")
  if not c then return selected and colors.fg or colors.dim end
  return selected and c or colors.alpha(c, 0.55)
end

-- Each bar shows its own workspaces: paw reports the display a workspace belongs to by
-- sketchybar's arrangement-id (0: none yet, shown on the active display).
local function display_of(ws)
  local a = math.tointeger(ws.arrangement or 0) or 0
  return a > 0 and tostring(a) or "active"
end

-- How far the workspace on screen is zoomed in (paw zoom in/out): its own island per display,
-- shown only while zoomed. Added after the spaces island below; filled in here.
local ZOOM_DISPLAYS = 4
local zooms = {}

local function update_zoom(workspaces)
  local level = {}
  for _, ws in ipairs(workspaces) do
    local a = math.tointeger(ws.arrangement or 0) or 0
    local z = math.tointeger(ws.zoom or 0) or 0
    if ws.visible and a > 0 and z > 0 then level[a] = z end
  end
  for d = 1, ZOOM_DISPLAYS do
    local z = level[d]
    for _, item in ipairs(zooms[d] or {}) do item:set({ drawing = z ~= nil }) end
    if z and zooms[d] then zooms[d][2]:set({ label = { string = tostring(z) } }) end
  end
end

-- retries: at login sketchybar can be up before paw, so keep asking until paw answers.
local function refresh(animate, retries)
  sbar.exec("paw query --json 2>/dev/null", function(workspaces)
    if type(workspaces) ~= "table" then
      if (retries or 0) > 0 then sbar.delay(2, function() refresh(animate, retries - 1) end) end
      return
    end
    local function apply()
      update_zoom(workspaces)
      for i = 1, SLOTS do
        local ws = workspaces[i]
        names[i] = ws and ws.name or nil
        local shown = {}
        if ws then
          local seen = {}
          for _, w in ipairs(ws.windows or {}) do
            if w.app and not IGNORED[w.app] and not seen[w.app] then
              seen[w.app] = true
              shown[#shown + 1] = w
            end
          end
          local display = display_of(ws)
          slots[i]:set({
            display = display,
            drawing = true,
            icon = { string = ws.name, highlight = ws.focused },
            padding_right = #shown == 0 and 2 or 0,
          })
          slots[i].bracket:set({ background = { color = ws.visible and colors.island_hi or colors.transparent } })
        else
          slots[i]:set({ drawing = false })
          slots[i].bracket:set({ background = { color = colors.transparent } })
        end
        for j = 1, APPS do
          local w = shown[j]
          if w then
            apps[i][j]:set({
              display = display_of(ws),
              drawing = true,
              label = { string = (app_image.icon(w.app)), color = app_color(w, ws.focused),
                        width = select(2, app_image.icon(w.app)) and 18 or "dynamic" },
              background = select(2, app_image.icon(w.app))
                and { drawing = true, image = { string = select(2, app_image.icon(w.app)), scale = 0.45 } }
                or { drawing = false },
              padding_right = j == #shown and 8 or 0,
            })
          else
            apps[i][j]:set({ drawing = false })
          end
        end
      end
    end
    if animate then sbar.animate("tanh", 12, apply) else apply() end
  end)
end

creator:subscribe("paw_workspaceChanged", function() refresh(true) end)
creator:subscribe({ "paw_snapshot", "paw_windowsChanged", "paw_zoomChanged", "system_woke" }, function() refresh(false) end)
creator:subscribe("display_change", function() refresh(false) end)
refresh(false, 60)

local last_edge = island.edge("left")
island.wrap("spaces.island", { first_edge, "/space\\..*/", last_edge })
island.gap("left")

for d = 1, ZOOM_DISPLAYS do
  local e1 = island.edge("left")
  local item = sbar.add("item", "zoom." .. d, {
    position = "left",
    icon = {
      string = "􀊫",
      font = { family = settings.font.symbols, style = "Semibold", size = 11.0 },
      color = colors.gold,
    },
    label = { font = { family = settings.font.text, style = "Bold", size = 12.0 }, color = colors.gold },
  })
  local e2 = island.edge("left")
  island.wrap("zoom." .. d .. ".island", { e1, item.name, e2 })
  local gap = island.gap("left").name
  zooms[d] = {}
  for _, name in ipairs({ e1, item.name, e2, gap }) do
    sbar.set(name, { display = d, drawing = false })
    zooms[d][#zooms[d] + 1] = { set = function(_, props) sbar.set(name, props) end }
  end
  zooms[d][2] = item
end
refresh(false)
