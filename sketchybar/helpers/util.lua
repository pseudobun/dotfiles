local M = {}

-- 98412.3 -> "98,412"; decimals optional
function M.thousands(n, decimals)
  local s = string.format("%." .. (decimals or 0) .. "f", n)
  local int, frac = s:match("^(-?%d+)(%.?%d*)$")
  int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1")
  return int .. frac
end

function M.read_env_file(path)
  local env = {}
  local f = io.open(path, "r")
  if not f then return env end
  for line in f:lines() do
    local k, v = line:match('^%s*export%s+([%w_]+)%s*=%s*"?([^"]*)"?')
    if not k then k, v = line:match('^%s*([%w_]+)%s*=%s*"?([^"]*)"?') end
    if k then env[k] = v end
  end
  f:close()
  return env
end

return M
