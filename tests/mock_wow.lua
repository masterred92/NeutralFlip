-- Minimal mock of the WoW client for offline tests. Not Blizzard code; just enough surface.
local M = {}
M.now, M.clock, M.combat, M.money = 1790000000, 1000, false, 0
M.items = { -- itemID -> { name, classID, subClassID, sellPrice } (IDs checked on auctionhouse.fyi Forever data)
  [2318] = { "Light Leather", 7, 6, 15 }, [2447] = { "Peacebloom", 7, 9, 10 },
  [249427] = { "Pristine Leather", 7, 6, 500 }, [249399] = { "Frilled Lichen", 7, 9, 300 },
  [2589] = { "Linen Cloth", 7, 5, 13 } }
M.bags = { [0] = {} }       -- bag -> { slot -> {itemID, count} }
M.replicate, M.browse, M.commodity = {}, {}, {}
M.secret = {}               -- values listed here are "secret"
M.timers, M.hooks, M.frames, M.tooltipLines = {}, {}, {}, {}
M.prints = {}

local function frameObj(name)
  local fr = { events = {}, scripts = {}, shown = true, name = name, points = {} }
  local mt = {}
  mt.__index = function(t, k)
    if k == "RegisterEvent" then return function(_, e) t.events[e] = true end end
    if k == "UnregisterEvent" then return function(_, e) t.events[e] = nil end end
    if k == "SetScript" then return function(_, s, fn) t.scripts[s] = fn end end
    if k == "IsShown" then return function() return t.shown end end
    if k == "Show" then return function() t.shown = true end end
    if k == "Hide" then return function() t.shown = false end end
    if k == "SetShown" then return function(_, v) t.shown = v and true or false end end
    if k == "SetText" then return function(_, v) t.text_ = v end end
    if k == "GetPoint" then return function() return "LEFT", nil, "LEFT", 30, 50 end end
    if k == "SetPoint" then return function(_, ...) t.points[#t.points + 1] = { ... } end end
    if k == "CreateFontString" then return function() return frameObj() end end
    return function() end -- every other widget method is a no-op
  end
  return setmetatable(fr, mt)
end

function M.install(env)
  env = env or _G
  env.issecretvalue = function(v) return M.secret[v] == true end
  env.Enum = { TooltipDataType = { Item = 0 } }
  env.time = function() return M.now end
  env.date = os.date
  env.GetTime = function() return M.clock end
  env.GetMoney = function() return M.money end
  env.GetRealZoneText = function() return M.zone or "Elwynn Forest" end
  env.GetBuildInfo = function() return "1.60.1", "70374", "Oct 13 2026", 16001 end
  env.GetLocale = function() return "enUS" end
  env.GetRealmName = function() return "TestRealm" end
  env.UnitFactionGroup = function() return "Alliance" end
  env.GetMoneyString = function(c) return tostring(c) .. "c" end
  env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 5
  env.C_RestrictedActions = { InCombatLockdown = function() return M.combat end }
  env.C_Timer = { After = function(_, fn) M.timers[#M.timers + 1] = fn end,
                  NewTicker = function() return {} end }
  env.C_Item = {
    GetItemInfoInstant = function(id) local i = M.items[id]; if i then return id, "", "", "", 0, i[2], i[3] end end,
    GetItemInfo = function(id) local i = M.items[id]; if i then return i[1], "link", 1, 1, 1, "", "", 1, "", 0, i[4], i[2], i[3] end end,
    GetItemNameByID = function(id) local i = M.items[id]; return i and i[1] end }
  env.C_Container = {
    GetContainerNumSlots = function(bag) local b = M.bags[bag]; return b and 20 or 0 end,
    GetContainerItemInfo = function(bag, slot) local b = M.bags[bag]; local e = b and b[slot]
      if e then return { itemID = e[1], stackCount = e[2] } end end }
  env.C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return true end,
    ReplicateItems = function() M.replicateRequested = (M.replicateRequested or 0) + 1 end,
    GetNumReplicateItems = function() return #M.replicate end,
    GetReplicateItemInfo = function(i) local r = M.replicate[i + 1]
      return M.items[r[1]] and M.items[r[1]][1] or "x", 0, r[2], 1, true, 1, "", 0, 0, r[3], 0, nil, nil, nil, nil, 0, r[1], true end,
    GetBrowseResults = function() return M.browse end,
    GetNumCommoditySearchResults = function(id) return #(M.commodity[id] or {}) end,
    GetCommoditySearchResultInfo = function(id, i) return M.commodity[id][i] end }
  env.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "test" end end,
    GetNumAddOns = function() return 0 end, GetAddOnInfo = function() end }
  env.TooltipDataProcessor = { AddTooltipPostCall = function(t, fn) M.hooks[#M.hooks + 1] = { t, fn } end }
  env.GameTooltip = { AddLine = function(_, s) M.tooltipLines[#M.tooltipLines + 1] = s end,
    AddDoubleLine = function(_, a, b) M.tooltipLines[#M.tooltipLines + 1] = a .. ": " .. b end }
  env.ItemRefTooltip = {}
  env.UIParent = frameObj("UIParent")
  env.SlashCmdList = {}
  env.CreateFrame = function(_, name) local f = frameObj(name); M.frames[#M.frames + 1] = f
    if name then env[name] = f end; return f end
  env.print = function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
    M.prints[#M.prints + 1] = table.concat(t, " ") end
  env.unpack = env.unpack or table.unpack
end

-- Load an addon the way the client does: each TOC file gets (addonName, privateTable).
function M.loadAddon(dir, name)
  local ns = {}
  for line in io.lines(dir .. "/" .. name .. ".toc") do
    line = line:gsub("\\", "/")
    if line:match("%.lua$") then assert(loadfile(dir .. "/" .. line))(name, ns) end
  end
  M.fire("ADDON_LOADED", name)
  return ns
end

function M.fire(event, ...)
  for _, f in ipairs(M.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

function M.runTimers()
  for _ = 1, 1000 do
    if #M.timers == 0 then return end
    local t = M.timers; M.timers = {}
    for _, fn in ipairs(t) do fn() end
  end
end

function M.tooltip(id)
  M.tooltipLines = {}
  for _, h in ipairs(M.hooks) do h[2](GameTooltip, { id = id }) end
  return table.concat(M.tooltipLines, " | ")
end

M.fails, M.passes = 0, 0
function M.check(cond, label)
  if cond then M.passes = M.passes + 1 else M.fails = M.fails + 1; io.write("FAIL: ", label, "\n") end
end
function M.done(name)
  io.write(("%s: %d passed, %d failed\n"):format(name, M.passes, M.fails))
  os.exit(M.fails == 0 and 0 or 1)
end
return M
