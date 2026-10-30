-- KennyShared 2.0.0 Hub: lets Kenny's addons work together when several are installed, and stay silent when
-- one is alone. Every addon embeds this file; they share one global table (KennyAddonsHub), the newest copy's
-- code wins, and its state survives. Nothing here is required: each addon calls it and falls back to its own
-- behaviour when a sibling is missing. Do not edit a copy; edit wow-forever-addons/lib/KennyShared.
local _, ns = ...
-- luacheck: globals KennyAddonsHub
-- luacheck: read globals GetServerTime GetTime PlaySoundFile MenuUtil LibStub TooltipDataProcessor Enum C_Timer
local HUB_VERSION = 1
local hub = _G.KennyAddonsHub
if type(hub) ~= "table" then hub = {}; _G.KennyAddonsHub = hub end
ns.Hub = hub
hub.members = hub.members or {}      -- addon name -> version, for /<cmd> debug and "works with" checks
hub.tooltips = hub.tooltips or {}    -- { name, order, fn }
hub.launchers = hub.launchers or {}  -- { name, spec, entry }
hub.prices = hub.prices or {}        -- name -> function(itemID) -> { p = copper, t = time, src = "..." }
hub.voiceUntil = hub.voiceUntil or 0
hub.lastScan = hub.lastScan or 0
if (hub.version or 0) >= HUB_VERSION and hub.Join then return end
hub.version = HUB_VERSION

local function now() return (GetServerTime and GetServerTime()) or time() end

function hub.Join(name, version) hub.members[name] = version or true end
function hub.Has(name) return hub.members[name] ~= nil end
function hub.Members()
  local out = {}
  for name in pairs(hub.members) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- Prices: PriceLog registers itself as the canonical store; the others ask here first and use their own
-- data only when it has nothing (or nothing newer). DEB can plug in with hub.RegisterPrices too.
function hub.RegisterPrices(name, fn) hub.prices[name] = fn end
function hub.GetPrice(itemID, exclude)
  local best
  for name, fn in pairs(hub.prices) do
    if name ~= exclude then
      local ok, rec = pcall(fn, itemID)
      if ok and type(rec) == "table" and rec.p and (not best or (rec.t or 0) > (best.t or 0)) then best = rec end
    end
  end
  return best
end

-- One full AH scan (ReplicateItems) per 15 minutes for all of us: every addon listens to the same
-- REPLICATE_ITEM_LIST_UPDATE, so one scan feeds all. ClaimScan returns false, who, secondsLeft if taken.
hub.SCAN_COOLDOWN = 15 * 60
function hub.ClaimScan(name)
  local left = hub.SCAN_COOLDOWN - (now() - hub.lastScan)
  if left > 0 then return false, hub.lastScanBy, left end
  hub.lastScan, hub.lastScanBy = now(), name
  return true
end
-- True while a scan started by any of us is still streaming in (2 minutes is generous).
function hub.ScanActive() return now() - hub.lastScan < 120 end

-- Voice lines: one at a time across BRBoss, WipeAndWin, QuestieJobsDone and GruntCount.
hub.VOICE_GAP = 4
function hub.PlayVoice(file, channel, seconds)
  local t = GetTime and GetTime() or now()
  if t < hub.voiceUntil then return false, "busy" end
  local ok, willPlay = pcall(PlaySoundFile, file, channel or "Master")
  if ok and willPlay ~= false then hub.voiceUntil = t + (seconds or hub.VOICE_GAP) end
  return ok and willPlay ~= false, ok and willPlay or "error"
end

-- A host addon (DBM's victory/defeat sound, a BigWigs countdown) is about to speak: keep our lines quiet meanwhile.
function hub.MarkVoiceBusy(seconds)
  local t = (GetTime and GetTime() or now()) + (seconds or hub.VOICE_GAP)
  if t > hub.voiceUntil then hub.voiceUntil = t end
end
-- LibSharedMedia: one entry per sound file across our addons (WipeAndWin and QuestieJobsDone share "Job's done!").
hub.sounds = hub.sounds or {}
function hub.ClaimSound(fileID, name)
  if hub.sounds[fileID] then return false, hub.sounds[fileID] end
  hub.sounds[fileID] = name
  return true
end

-- Tooltips: one post-call for all of us, so our lines form one block in a fixed order (lowest first).
-- A provider is fn(tt, itemID, data); tt.Claim("key") returns false if an earlier provider already showed
-- that line (e.g. "price.auction"), so the same price never appears twice.
local function runTooltips(tooltip, data)
  local itemID = data and data.id
  if not itemID or not tooltip or not tooltip.AddLine then return end
  local claimed = {}
  local proxy = setmetatable({ Claim = function(key) if claimed[key] then return false end claimed[key] = true; return true end },
    { __index = function(_, k) local v = tooltip[k]; if type(v) == "function" then return function(_, ...) return v(tooltip, ...) end end return v end })
  for _, p in ipairs(hub.tooltips) do
    local ok, err = pcall(p.fn, proxy, itemID, data)
    if not ok and p.onError then pcall(p.onError, err) end
  end
end
function hub.AddTooltip(name, order, fn, onError)
  for i = #hub.tooltips, 1, -1 do if hub.tooltips[i].name == name then table.remove(hub.tooltips, i) end end
  hub.tooltips[#hub.tooltips + 1] = { name = name, order = order or 50, fn = fn, onError = onError }
  table.sort(hub.tooltips, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.name < b.name end)
  if not hub.tooltipHooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    hub.tooltipHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data) runTooltips(tt, data) end)
  end
end
hub.RunTooltips = runTooltips

-- Launcher: one LibDataBroker entry ("Kenny's addons") with a menu when several of us are installed,
-- the addon's own entry when it is alone. Returns an entry table; set entry.text to update the display.
local function ldb() return type(LibStub) == "table" and LibStub("LibDataBroker-1.1", true) end
local function combinedText()
  local parts = {}
  for _, l in ipairs(hub.launchers) do if l.entry.text and l.entry.text ~= "" and l.entry.text ~= l.name then parts[#parts + 1] = l.entry.text end end
  return #parts > 0 and table.concat(parts, " | ") or "Kenny's addons"
end
local function refresh()
  if hub.combined then hub.combined.text = combinedText() end
end
hub.RefreshLauncher = refresh
local function buildLaunchers()
  local lib = ldb()
  if not lib or hub.built then return end
  hub.built = true
  if #hub.launchers == 1 then
    local l = hub.launchers[1]
    l.object = lib:NewDataObject(l.name, l.spec)
    if l.object and l.entry.text then l.object.text = l.entry.text end
    return
  end
  hub.combined = lib:NewDataObject("KennyAddons", {
    type = "data source", label = "Kenny's addons", text = combinedText(),
    icon = hub.launchers[1] and hub.launchers[1].spec.icon,
    OnClick = function(frame, button)
      if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(frame, function(_, root)
          root:CreateTitle("Kenny's addons")
          for _, l in ipairs(hub.launchers) do
            local sub = root:CreateButton(l.name, function() l.spec.OnClick(frame, "LeftButton") end)
            sub:CreateButton(l.spec.leftHint or "Open", function() l.spec.OnClick(frame, "LeftButton") end)
            if l.spec.rightHint then sub:CreateButton(l.spec.rightHint, function() l.spec.OnClick(frame, "RightButton") end) end
          end
        end)
      elseif hub.launchers[1] then hub.launchers[1].spec.OnClick(frame, button) end
    end,
    OnTooltipShow = function(tt)
      for i, l in ipairs(hub.launchers) do
        if i > 1 then tt:AddLine(" ") end
        if l.spec.OnTooltipShow then pcall(l.spec.OnTooltipShow, tt) else tt:AddLine(l.name) end
      end
      tt:AddLine("Click: menu for each addon.", 0.6, 0.6, 0.6, true)
    end,
  })
end
function hub.Launcher(name, spec)
  for _, l in ipairs(hub.launchers) do if l.name == name then return l.entry end end
  local rec = { name = name, spec = spec }
  local values = {} -- kept outside the entry so every assignment reaches __newindex
  rec.entry = setmetatable({}, { __index = values, __newindex = function(_, k, v)
    values[k] = v
    if k == "text" then
      if rec.object then rec.object.text = v end
      refresh()
    end
  end })
  rec.entry.text = spec.text
  hub.launchers[#hub.launchers + 1] = rec
  table.sort(hub.launchers, function(a, b) return a.name < b.name end)
  if hub.built then -- a sibling loaded late: join the combined entry if there is one, else stand alone
    local lib = ldb()
    if hub.combined then refresh() elseif lib then rec.object = lib:NewDataObject(name, spec); if rec.object and rec.entry.text then rec.object.text = rec.entry.text end end
  elseif not hub.pending and C_Timer then
    hub.pending = true
    C_Timer.After(0, function() hub.pending = false; buildLaunchers() end) -- after every sibling has registered
  end
  return rec.entry
end
hub.BuildLaunchers = buildLaunchers

-- Panels: a host addon (Dwarf Explorer's Bible, later) can show our windows as tabs in its own window.
-- An addon calls hub.RegisterPanel(name, icon, buildFn) where buildFn(parentFrame) fills a frame and may return
-- a refresh function. When an addon would open its own window it calls hub.ShowPanel(name) first: true means a
-- host showed it as a tab (so the addon keeps its own window hidden); false means no host, use your own window.
-- Host contract: hub.SetHost({ AddPanel = function(panel) end, Show = function(name) return true end }).
hub.panels = hub.panels or {}
function hub.RegisterPanel(name, icon, buildFn, opts)
  local panel = { name = name, icon = icon, build = buildFn, opts = opts or {} }
  hub.panels[name] = panel
  if hub.host and hub.host.AddPanel then pcall(hub.host.AddPanel, panel) end
  return panel
end
function hub.SetHost(host)
  hub.host = host
  for _, panel in pairs(hub.panels) do pcall(host.AddPanel, panel) end
end
function hub.HasHost() return hub.host ~= nil end
function hub.ShowPanel(name)
  if not (hub.host and hub.host.Show and hub.panels[name]) then return false end
  local ok, shown = pcall(hub.host.Show, name)
  return ok and shown == true
end

-- Enrichment: an addon offers data it owns under a kind ("flip", "trend", "verdict"...), and others show it in
-- their views only when it exists. hub.Ask returns the first non-nil answer and who gave it, or nil.
hub.providers = hub.providers or {}
function hub.Provide(kind, name, fn)
  hub.providers[kind] = hub.providers[kind] or {}
  hub.providers[kind][name] = fn
end
function hub.Ask(kind, ...)
  for name, fn in pairs(hub.providers[kind] or {}) do
    local ok, v = pcall(fn, ...)
    if ok and v ~= nil then return v, name end
  end
end
