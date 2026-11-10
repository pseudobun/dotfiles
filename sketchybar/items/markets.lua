-- One island: BTC price + 24h, ETH price + 24h, ETH base fee (gwei), NYSE open/close countdown.
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local island = require("island")
local util = require("util")

local dir = os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar")
local env = util.read_env_file(dir .. "/env.local.sh")

local glyph = { family = settings.font.text, style = "Regular", size = 16.0 }
local small = { family = settings.font.text, style = "Medium", size = 10.5 }

local function chg_item(name)
  return sbar.add("item", name, {
    position = "right",
    icon = { drawing = false },
    label = { font = small },
    padding_left = 0,
  })
end

-- added right-to-left
local e_r = island.edge("right")
local nyse = sbar.add("item", "markets.nyse", {
  position = "right",
  icon = { string = icons.nyse, font = glyph, color = colors.muted },
})
local gas = sbar.add("item", "markets.gas", {
  position = "right",
  icon = { string = icons.gas, font = { family = settings.font.text, style = "Regular", size = 14.0 }, color = colors.violet, padding_right = 3 },
  label = { string = "–" },
})
local eth_chg = chg_item("markets.eth.chg")
local eth = sbar.add("item", "markets.eth", {
  position = "right",
  icon = { string = icons.eth, font = glyph, color = colors.wave, padding_right = 3 },
  label = { string = "–" },
  padding_right = 3,
})
local btc_chg = chg_item("markets.btc.chg")
local btc = sbar.add("item", "markets.btc", {
  position = "right",
  update_freq = 60,
  icon = { string = icons.btc, font = glyph, color = colors.gold, padding_right = 3 },
  label = { string = "–" },
  padding_right = 3,
})
local e_l = island.edge("right")

local function set_pair(price_item, chg_item_, t, decimals)
  local price, pct = tonumber(t.lastPrice), tonumber(t.priceChangePercent)
  if not price or not pct then return end
  price_item:set({ label = { string = "$" .. util.thousands(price, decimals) } })
  chg_item_:set({
    label = {
      string = (pct >= 0 and icons.up or icons.down) .. string.format("%.1f%%", math.abs(pct)),
      color = pct >= 0 and colors.good or colors.bad,
    },
  })
end

local function fetch_prices()
  sbar.exec(
    "curl -sf --max-time 10 'https://api.binance.com/api/v3/ticker/24hr?symbols=%5B%22BTCUSDT%22,%22ETHUSDT%22%5D'",
    function(res)
      if type(res) ~= "table" then return end -- keep last values when offline
      for _, t in ipairs(res) do
        if t.symbol == "BTCUSDT" then set_pair(btc, btc_chg, t, 0) end
        if t.symbol == "ETHUSDT" then set_pair(eth, eth_chg, t, 0) end
      end
    end
  )
end

local function fetch_gas()
  if not env.ETH_API_KEY or env.ETH_API_KEY == "" then
    gas:set({ drawing = false })
    return
  end
  sbar.exec(
    "curl -sf --max-time 10 'https://api.etherscan.io/v2/api?chainid=1&module=gastracker&action=gasoracle&apikey="
      .. env.ETH_API_KEY .. "'",
    function(res)
      local fee = type(res) == "table" and type(res.result) == "table" and tonumber(res.result.suggestBaseFee)
      if not fee then return end
      gas:set({ label = { string = string.format(fee < 10 and "%.2f" or "%.0f", fee) } })
    end
  )
end

local OPEN, CLOSE = 9 * 60 + 30, 16 * 60

local function fmt(mins)
  local d, h, m = mins // 1440, (mins % 1440) // 60, mins % 60
  if d > 0 then return string.format("%dd%dh", d, h) end
  if h > 0 then return string.format("%dh%02dm", h, m) end
  return string.format("%dm", m)
end

local function update_nyse()
  sbar.exec("TZ=America/New_York date +%u,%H,%M", function(out)
    local dow, hh, mm = out:match("(%d),(%d+),(%d+)")
    dow, hh, mm = tonumber(dow), tonumber(hh), tonumber(mm)
    if not dow then return end
    local now = hh * 60 + mm
    local open, left = false, 0
    if dow <= 5 and now >= OPEN and now < CLOSE then
      open, left = true, CLOSE - now
    else
      local ahead
      if dow <= 4 and now >= CLOSE then ahead = 1
      elseif dow == 5 and now >= CLOSE then ahead = 3
      elseif dow == 6 then ahead = 2
      elseif dow == 7 then ahead = 1
      else ahead = 0 end
      left = ahead == 0 and (OPEN - now) or (ahead * 1440 - now + OPEN)
    end
    nyse:set({
      icon = { color = open and colors.good or colors.dim },
      label = { string = fmt(math.max(left, 0)), color = open and colors.good or colors.muted },
    })
  end)
end

local function refresh()
  fetch_prices()
  fetch_gas()
  update_nyse()
end

btc:subscribe({ "routine", "forced" }, refresh)
btc:subscribe("system_woke", function()
  sbar.delay(10, refresh) -- give the network a moment
end)

-- click a price to open a chart
btc:subscribe("mouse.clicked", function() sbar.exec("open 'https://www.tradingview.com/chart/?symbol=BINANCE:BTCUSDT'") end)
eth:subscribe("mouse.clicked", function() sbar.exec("open 'https://www.tradingview.com/chart/?symbol=BINANCE:ETHUSDT'") end)
gas:subscribe("mouse.clicked", function() sbar.exec("open 'https://etherscan.io/gastracker'") end)

island.wrap("markets.island", { e_r, nyse.name, gas.name, eth_chg.name, eth.name, btc_chg.name, btc.name, e_l })
