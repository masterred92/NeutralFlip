-- NeutralFlip: faction AH vs neutral AH price comparison for WoW: Forever. Written from scratch (MIT).
-- It never buys, posts, or clicks anything: it records prices you see at each auction house and tells
-- you which items are worth carrying from one house to the other after the auction house cut.
local ADDON, ns = ...
local C, Core = ns.Compat, ns.Core
local L = Core.L

local NF = {}
KennyNeutralFlip = NF

local SCHEMA = 1
local SCAN_COOLDOWN = 15 * 60
local NEUTRAL = "Neutral"
local DEFAULTS = {
  cutFaction = 0.05,   -- faction AH cut (ahledger.com/wow-forever/auction-house); override with /nflip cut
  cutNeutral = 0.15,   -- neutral AH cut (same source)
  maxAgeHours = 24,    -- ignore prices older than this when comparing
  minMargin = 0.20,    -- profit must be at least 20% of the buy price...
  minProfit = 50,      -- ...and at least this many copper per unit
  maxRatio = 20,       -- sell/buy above this is flagged "thin market, check by hand"
  keepDays = 14,       -- prices older than this are pruned at login
  tooltip = true,
  listSize = 15,
}
-- English names of the three goblin towns and their zones. The zone list matters because those
-- zones have no faction auctioneer, so any AH opened there is the neutral one.
NF.NEUTRAL_NAMES = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true,
  ["Tanaris"] = true, ["Winterspring"] = true, ["Stranglethorn Vale"] = true, ["The Cape of Stranglethorn"] = true }
-- Classic-era uiMapIDs (Stranglethorn Vale 1434, Tanaris 1446, Winterspring 1452). UNCONFIRMED for
-- Forever; names and /nflip here are the fallbacks.
NF.NEUTRAL_MAPS = { [1434] = true, [1446] = true, [1452] = true }

local db, settings
local ahOpen, house, scanToken, processing = false, nil, 0, false

local migrations = {
  [1] = function(old) return { houses = {}, overrides = {}, rates = {}, settings = old.settings or {} } end,
}

-- Location / house ------------------------------------------------------------------------

local function realmName()
  return tostring(GetRealmName and C.Safe(GetRealmName()) or "realm")
end

local function playerFaction()
  return tostring(UnitFactionGroup and C.Safe(UnitFactionGroup("player")) or "faction")
end

function NF.LocationKey()
  local zone = GetRealZoneText and C.Safe(GetRealZoneText()) or ""
  local sub = GetSubZoneText and C.Safe(GetSubZoneText()) or ""
  return tostring(zone) .. "/" .. tostring(sub), tostring(zone), tostring(sub)
end

-- "Neutral" or the player's faction, plus how we decided.
function NF.DetectKind()
  local key, zone, sub = NF.LocationKey()
  local o = db.overrides[key]
  if o == "neutral" then return NEUTRAL, "your /nflip here setting" end
  if o == "faction" then return playerFaction(), "your /nflip here setting" end
  local mapID = C_Map and C_Map.GetBestMapForUnit and C.SafeNumber(C_Map.GetBestMapForUnit("player"))
  if mapID and NF.NEUTRAL_MAPS[mapID] then return NEUTRAL, "map " .. mapID end
  if NF.NEUTRAL_NAMES[sub] or NF.NEUTRAL_NAMES[zone] then return NEUTRAL, "zone " .. key end
  return playerFaction(), "zone " .. key
end

local function houseData(kind)
  local key = realmName() .. "-" .. kind
  local h = db.houses[key]
  if not h then h = { items = {}, lastScan = 0 }; db.houses[key] = h end
  return h, key
end
NF.HouseData = function(kind) return houseData(kind) end

-- Price records: items[id] = { p = lowest unit price, q = units at that price (nil = unknown),
-- n = units listed in total, t = time seen }.
function NF.Record(h, itemID, p, q, n, t)
  if not (itemID and p and p > 0) then return end
  h.items[itemID] = { p = math.floor(p), q = q, n = n, t = t or C.Now() }
end

-- Deposit rate check ----------------------------------------------------------------------
-- Forever has no API that says "this is the neutral AH". The deposit is a multiple of vendor price
-- and differs between houses, so we learn deposit/vendor here and use it to double-check the zone.
-- Returns deposit/vendor for a 12h listing, measured on an item in your bags (stored by the caller).
function NF.ProbeDepositRate()
  if not (C_AuctionHouse and C_AuctionHouse.CalculateCommodityDeposit) then return nil end
  local tried = 0
  for itemID in pairs(C.GetBagCounts()) do
    local info = C.GetItemInfo(itemID)
    if info and info.sellPrice and info.sellPrice > 0 then
      tried = tried + 1
      local ok, dep = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, 1, 20)
      dep = ok and C.SafeNumber(dep) or nil
      if dep and dep > 0 then
        return dep / (info.sellPrice * 20)
      end
      if tried >= 10 then break end
    end
  end
  return nil
end

-- Returns a warning string when the learned deposit rates say this house is the other kind.
function NF.CrossCheck(kind, rate)
  local f, n = db.rates.faction, db.rates.neutral
  if not (rate and f and n) or math.abs(n - f) < 0.5 * math.min(n, f) then return nil end
  local looksNeutral = math.abs(rate - n) < math.abs(rate - f)
  if looksNeutral and kind ~= NEUTRAL then
    return "deposits here look like the NEUTRAL house. If so, type /nflip here neutral"
  elseif not looksNeutral and kind == NEUTRAL then
    return "deposits here look like a FACTION house. If so, type /nflip here faction"
  end
end

-- Capturing prices (only what the AH already shows you) -------------------------------------

function NF.ProcessReplicate()
  if processing or not house then return end
  local n = C.AHNumReplicate()
  if n == 0 then return end
  processing = true
  local h, acc, i, now = house, {}, 0, C.Now()
  local function finish()
    local k = 0
    for id, a in pairs(acc) do NF.Record(h, id, a.min, a.qmin, a.qty, now); k = k + 1 end
    h.lastScan = now
    processing = false
    Core.Print(("saved %d prices for the %s auction house."):format(k, NF.KindLabel(NF.CurrentKind())))
  end
  local function step()
    if C.InCombat() then C_Timer.After(1, step) return end
    local stop = math.min(i + 500, n)
    while i < stop do
      local itemID, _, count, buyout = C.AHReplicateRow(i)
      if itemID then
        local unit = math.floor(buyout / count)
        local a = acc[itemID]
        if not a then a = { min = unit, qmin = 0, qty = 0 }; acc[itemID] = a end
        if unit < a.min then a.min, a.qmin = unit, 0 end
        if unit == a.min then a.qmin = a.qmin + count end
        a.qty = a.qty + count
      end
      i = i + 1
    end
    if i < n then C_Timer.After(0, function() if not Core.SafeCall("scan", step) then processing = false end end) else finish() end
  end
  if not Core.SafeCall("scan", step) then processing = false end
end

local function OnBrowse()
  if not house then return end
  for _, r in ipairs(C.AHBrowse()) do NF.Record(house, r.itemID, r.price, nil, r.quantity) end
end

local function OnCommodity(itemID)
  itemID = C.SafeNumber(itemID)
  if not (house and itemID) then return end
  local minP, qmin, total = nil, 0, 0
  for _, r in ipairs(C.AHCommodity(itemID)) do
    if not minP or r.price < minP then minP, qmin = r.price, 0 end
    if r.price == minP then qmin = qmin + r.quantity end
    total = total + r.quantity
  end
  if minP then NF.Record(house, itemID, minP, qmin, total) end
end

-- The verdict -------------------------------------------------------------------------------

local currentKind
function NF.CurrentKind() return currentKind end
function NF.KindLabel(kind) return kind == NEUTRAL and "neutral" or (kind or "?") end

local function fresh(rec, now)
  return rec and (now - rec.t) <= settings.maxAgeHours * 3600
end

-- One route: buy at `from` for buy.p, list at `to` 1c under its lowest listing.
local function route(itemID, buy, sell, cut, from, to, now, bags)
  if not (buy and sell) then return nil end
  local listAt = sell.p - 1
  local net = math.floor(listAt * (1 - cut))
  local profit = net - buy.p
  if profit < settings.minProfit or profit < buy.p * settings.minMargin then return nil end
  local qty = buy.q and buy.q > 0 and buy.q or 1
  if sell.n and sell.n > 0 then qty = math.min(qty, sell.n) end -- don't carry more than the other side lists
  local info = C.GetItemInfo(itemID)
  local rate = db.rates[to == NEUTRAL and "neutral" or "faction"]
  return {
    itemID = itemID, name = (info and info.name) or C.GetItemName(itemID) or ("item " .. itemID),
    from = from, to = to, buy = buy.p, listAt = listAt, net = net, profit = profit, qty = qty,
    qtyKnown = buy.q ~= nil, total = profit * qty, carried = bags[itemID] or 0,
    thin = sell.p > buy.p * settings.maxRatio,
    deposit = (rate and info and info.sellPrice) and math.floor(rate * info.sellPrice * qty) or nil,
    age = math.max(now - buy.t, now - sell.t), buyAge = now - buy.t, sellAge = now - sell.t,
  }
end

-- Both routes for one item (0, 1 or 2 entries).
function NF.ItemRoutes(itemID, now, bags)
  local fac = playerFaction()
  local a, b = houseData(fac).items[itemID], houseData(NEUTRAL).items[itemID]
  local out = {}
  if fresh(a, now) and fresh(b, now) then
    out[#out + 1] = route(itemID, a, b, settings.cutNeutral, fac, NEUTRAL, now, bags)
    out[#out + 1] = route(itemID, b, a, settings.cutFaction, NEUTRAL, fac, now, bags)
  end
  return out
end

function NF.Opportunities(now)
  now = now or C.Now()
  local home, neu = houseData(playerFaction()), houseData(NEUTRAL)
  local bags, out = C.GetBagCounts(), {}
  for id in pairs(home.items) do
    if neu.items[id] then
      for _, o in ipairs(NF.ItemRoutes(id, now, bags)) do out[#out + 1] = o end
    end
  end
  table.sort(out, function(x, y)
    if x.thin ~= y.thin then return y.thin end
    if x.total ~= y.total then return x.total > y.total end
    return x.itemID < y.itemID
  end)
  return out
end

local function ago(sec)
  if sec < 3600 then return math.max(1, math.floor(sec / 60)) .. "m" end
  return math.floor(sec / 3600) .. "h"
end

function NF.FormatLine(i, o)
  local s = ("%d. %s: BUY at %s AH at %s or less (%s%d) -> LIST at %s AH at %s -> +%s each, about %s total"):format(
    i, o.name, NF.KindLabel(o.from), C.Money(o.buy), o.qtyKnown and "x" or "x?", o.qty,
    NF.KindLabel(o.to), C.Money(o.listAt), C.Money(o.profit), C.Money(o.total))
  local notes = { ("%s %s %s, %s %s %s"):format(NF.KindLabel(o.from), L["price"], ago(o.buyAge), NF.KindLabel(o.to), L["price"], ago(o.sellAge)) .. " " .. L["old"] }
  if o.deposit then notes[#notes + 1] = "deposit at risk " .. C.Money(o.deposit) end
  if o.carried > 0 then notes[#notes + 1] = "you carry " .. o.carried end
  if o.thin then notes[#notes + 1] = "THIN MARKET: check by hand" end
  return s .. " [" .. table.concat(notes, ", ") .. "]"
end

function NF.ListText(now)
  local list = NF.Opportunities(now)
  local lines = {}
  local fac = playerFaction()
  lines[1] = ("%s: %s AH vs neutral AH. Cuts %d%% / %d%%. Prices older than %dh ignored.")
    :format(realmName(), fac, settings.cutFaction * 100, settings.cutNeutral * 100, settings.maxAgeHours)
  if #list == 0 then
    lines[2] = L["Nothing worth carrying yet. Search or /nflip scan at BOTH your faction AH and a neutral AH (Booty Bay, Gadgetzan, Everlook), then check again."]
    local fresh1, fresh2 = houseData(fac).lastScan, houseData(NEUTRAL).lastScan
    lines[3] = ("%s: %s %s, %s %s"):format(L["Last full scan"], fac, fresh1 > 0 and date("%d %b %H:%M", fresh1) or L["never"],
      L["neutral"], fresh2 > 0 and date("%d %b %H:%M", fresh2) or L["never"])
  end
  for i = 1, math.min(#list, settings.listSize) do lines[#lines + 1] = NF.FormatLine(i, list[i]) end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "You press every buy and post. Prices are the lowest listing you last saw; they may have moved."
  return table.concat(lines, "\n"), #list
end

-- Tooltip: at most two lines, only added, never replacing anything another addon shows.
local function OnItemTooltip(tooltip, data)
  if not (settings and settings.tooltip) then return end
  local itemID = data and C.SafeNumber(data.id)
  if not itemID then return end
  local now, fac = C.Now(), playerFaction()
  local a, b = houseData(fac).items[itemID], houseData(NEUTRAL).items[itemID]
  if not (fresh(a, now) or fresh(b, now)) then return end
  local function part(label, r) return label .. " " .. (fresh(r, now) and C.Money(r.p) or "-") end
  if tooltip.Claim then tooltip.Claim("price.auction") end -- MatTooltip then skips its own AH price line
  tooltip:AddLine("|cff33ff99NeutralFlip|r " .. part(fac, a) .. " | " .. part("Neutral", b))
  for _, o in ipairs(NF.ItemRoutes(itemID, now, {})) do
    if not o.thin then
      tooltip:AddLine(("|cff33ff99  buy at %s, list at %s: +%s each|r"):format(NF.KindLabel(o.from), NF.KindLabel(o.to), C.Money(o.profit)))
      break
    end
  end
end

-- Events ----------------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
f:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
f:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")

function NF.OnAHShow()
  ahOpen = true
  local kind, why = NF.DetectKind()
  currentKind = kind
  house = houseData(kind)
  local _, n = NF.ListText()
  Core.Print(("this is the %s auction house (%s). %s"):format(NF.KindLabel(kind), why,
    n > 0 and (n .. " flips found: /nflip") or "Search or /nflip scan to record prices."))
  C_Timer.After(1, function()
    if not ahOpen then return end
    Core.SafeCall("deposit", function()
      local rate = NF.ProbeDepositRate()
      local warn = NF.CrossCheck(kind, rate)
      if warn then Core.Print(warn)
      elseif rate then db.rates[kind == NEUTRAL and "neutral" or "faction"] = rate end
    end)
  end)
end

f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    db = Core.Migrate(KennyNeutralFlipDB, migrations, SCHEMA)
    db.houses, db.overrides, db.rates = db.houses or {}, db.overrides or {}, db.rates or {}
    KennyNeutralFlipDB = db
    settings = Core.Settings(db.settings, DEFAULTS)
    -- Shared tooltip block with our other addons (prices first, then verdicts); works the same alone.
    ns.Hub.AddTooltip(ADDON, 20, function(tt, _, data) Core.SafeCall("tooltip", OnItemTooltip, tt, data) end)
    return
  end
  if not db then return end
  if event == "PLAYER_LOGIN" then
    local cutoff = C.Now() - settings.keepDays * 86400
    for key, h in pairs(db.houses) do
      for id, r in pairs(h.items) do if r.t < cutoff then h.items[id] = nil end end
      if next(h.items) == nil then db.houses[key] = nil end
    end
  elseif event == "AUCTION_HOUSE_SHOW" then Core.SafeCall("show", NF.OnAHShow)
  elseif event == "AUCTION_HOUSE_CLOSED" then ahOpen, house = false, nil
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    -- Also catches a full scan started by PriceLog or MatTooltip, so one scan feeds all three.
    scanToken = scanToken + 1
    local token = scanToken
    C_Timer.After(2, function() if token == scanToken then NF.ProcessReplicate() end end)
  elseif C.InCombat() then return
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then Core.SafeCall("browse", OnBrowse)
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then Core.SafeCall("commodity", OnCommodity, arg1)
  end
end)

-- Slash commands --------------------------------------------------------------------------

local function setNumber(key, v, lo, hi, label)
  v = tonumber(v)
  if not v or v < lo or v > hi then Core.Print(("%s must be a number from %s to %s."):format(label, lo, hi)) return end
  settings[key] = v
  Core.Print(label .. " set to " .. v .. ".")
end

local HELP = "/nflip (list flips) | scan | here neutral|faction|auto | status | cut faction|neutral 0.05"
  .. " | age <hours> | margin 0.2 | tooltip | way [bootybay|gadgetzan|everlook] | debug | report | wipe"

-- Startup self-check: one loud warning if Forever lacks an API we need; first-run guide; /nflip debug.
NF.REQUIRED_APIS = { "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetNumReplicateItems", "C_AuctionHouse.GetReplicateItemInfo",
  "C_AuctionHouse.GetBrowseResults", "C_AuctionHouse.GetNumCommoditySearchResults", "C_AuctionHouse.GetCommoditySearchResultInfo",
  "C_AuctionHouse.IsThrottledMessageSystemReady", "C_Container.GetContainerItemInfo", "TooltipDataProcessor.AddTooltipPostCall" }
Core.Setup({ cmd = "/nflip", required = NF.REQUIRED_APIS, optional = { "C_Map.GetBestMapForUnit", "TomTom", "LibStub", "KennyPriceLog" },
  db = function() return db end,
  firstRun = { L["Welcome! NeutralFlip compares your faction AH with the neutral AH. Three steps:"],
    L["1. At your faction AH: search your items, or /nflip scan (one full scan per 15 min)."],
    L["2. At a neutral AH (Booty Bay, Gadgetzan, Everlook; /nflip way for a TomTom arrow): do the same."],
    L["3. /nflip lists what to carry where. Prices older than 24h are ignored. /nflip debug checks your setup."] },
  debugLines = function()
    local out = { L["location"] .. ": " .. NF.LocationKey() .. " -> " .. NF.KindLabel((NF.DetectKind())) }
    for key, h in pairs(db.houses) do
      local n = 0
      for _ in pairs(h.items) do n = n + 1 end
      out[#out + 1] = ("%s: %d %s, %s %s"):format(key, n, L["prices"], L["last full scan"], h.lastScan > 0 and date("%d %b %H:%M", h.lastScan) or L["never"])
    end
    return out
  end })

-- Enrichment for our other addons (e.g. GoldPerSpot's per-item list): the best fresh flip for an item, or nil.
ns.Hub.Provide("flip", ADDON, function(itemID)
  if not db then return nil end
  for _, o in ipairs(NF.ItemRoutes(itemID, C.Now(), {})) do
    if not o.thin then return { profit = o.profit, from = NF.KindLabel(o.from), to = NF.KindLabel(o.to), buy = o.buy, listAt = o.listAt } end
  end
end)
Core.RegisterTextPanel("Flips", function() return (NF.ListText()) end) -- a tab in DEB's window when DEB hosts panels

SLASH_KENNYNEUTRALFLIP1 = "/nflip"
SLASH_KENNYNEUTRALFLIP2 = "/neutralflip"
SlashCmdList.KENNYNEUTRALFLIP = function(msg)
  if not db then return end
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "list" then
    Core.OpenView(function() Core.ShowText("List", "NeutralFlip: what to carry where (Ctrl+C copies)", (NF.ListText())) end)
  elseif cmd == "scan" then
    if not ahOpen then Core.Print("open an auction house first.") return end
    if C.InCombat() then Core.Print("not in combat.") return end
    local wait = SCAN_COOLDOWN - (C.Now() - (house.lastScan or 0))
    if wait > 0 then Core.Print(("full scan available in %d min. Your searches are still recorded."):format(math.ceil(wait / 60))) return end
    if not C.AHReady() then Core.Print("AH busy, try again shortly.") return end
    local mine, by, left = ns.Hub.ClaimScan(ADDON)
    if not mine then Core.Print(("%s %s; %s %d min. %s"):format(L["a full scan was already started by"], by or "?", L["next one in"], math.ceil(left / 60), L["Its results are recorded here too."])) return end
    C.AHReplicate()
    Core.Print("full scan requested. Stay at the AH until it reports.")
  elseif cmd == "here" then
    local key = NF.LocationKey()
    local v = rest:lower()
    if v == "neutral" or v == "faction" then db.overrides[key] = v
    elseif v == "auto" then db.overrides[key] = nil
    else Core.Print("usage: /nflip here neutral|faction|auto") return end
    Core.Print(("auction houses at %s are now treated as: %s."):format(key, v))
    if ahOpen then NF.OnAHShow() end
  elseif cmd == "cut" then
    local which, v = rest:match("^(%a+)%s+(%S+)$")
    if which == "faction" then setNumber("cutFaction", v, 0, 0.5, "faction cut")
    elseif which == "neutral" then setNumber("cutNeutral", v, 0, 0.5, "neutral cut")
    else Core.Print("usage: /nflip cut faction 0.05 | /nflip cut neutral 0.15") end
  elseif cmd == "age" then setNumber("maxAgeHours", rest, 1, 336, "max price age (hours)")
  elseif cmd == "margin" then setNumber("minMargin", rest, 0, 10, "minimum margin")
  elseif cmd == "tooltip" then
    settings.tooltip = not settings.tooltip
    Core.Print("tooltip lines " .. (settings.tooltip and "on." or "off."))
  elseif cmd == "status" then
    for key, h in pairs(db.houses) do
      local n = 0
      for _ in pairs(h.items) do n = n + 1 end
      Core.Print(("%s: %d prices, last full scan %s."):format(key, n, h.lastScan > 0 and date("%d %b %H:%M", h.lastScan) or "never"))
    end
    Core.Print(("deposit/vendor rate learned: faction %s, neutral %s."):format(
      db.rates.faction and ("%.2f"):format(db.rates.faction) or "?", db.rates.neutral and ("%.2f"):format(db.rates.neutral) or "?"))
  elseif cmd == "report" then
    local lines = { "schema " .. tostring(db.schema), "kind " .. tostring(currentKind), "location " .. NF.LocationKey() }
    for key, h in pairs(db.houses) do
      local n = 0
      for _ in pairs(h.items) do n = n + 1 end
      lines[#lines + 1] = key .. " items " .. n
    end
    Core.ShowReport(lines)
  elseif cmd == "debug" then Core.PrintDebug()
  elseif cmd == "way" then
    NF.Waypoint(rest)
  elseif cmd == "wipe" then
    db.houses = {}
    Core.Print("all recorded prices wiped.")
  else
    Core.Print(HELP)
  end
end
