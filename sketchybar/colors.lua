-- Palette shared with olympus-dashboard (dark) and ~/repos/me.
local M = {
  -- surfaces (dashboard --background / --card / --muted)
  bar = 0x00000000,
  island = 0xeb1d1d16,
  island_hi = 0xff2b2b22,
  popup = 0xf01d1d16,
  border = 0x1affffff,

  -- text
  fg = 0xfffbfbf9,
  muted = 0xffabab9c,
  dim = 0xff5f5f52,

  -- accents (~/repos/me)
  gold = 0xffead186, -- cappuccino
  wave = 0xff8698eb, -- wave
  deep = 0xff3a4c9e,

  -- status (dashboard --good / --warn / --destructive / --info)
  good = 0xff43d58f,
  warn = 0xfffcb52c,
  bad = 0xffff6467,
  info = 0xff55b8f8,
  violet = 0xffac79ff,

  transparent = 0x00000000,
}

function M.alpha(color, a)
  return (color & 0x00ffffff) | (math.floor(a * 255) << 24)
end

-- 0xAARRGGBB -> "0xAARRGGBB" for shell consumers (cpu helper)
function M.hex(color)
  return string.format("0x%08x", color)
end

return M
