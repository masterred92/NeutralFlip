-- KennyShared 2.0.0 Core.lua. Canonical copy: github.com/masterred92/wow-forever-addons lib/KennyShared.
-- Copied into each addon's Libs/KennyShared by tools/sync_lib.sh; CI fails if a copy differs. Do not edit a copy.
-- SavedVariables with defaults in code + schema migrations, a pcall error ring buffer,
-- a copyable bug-report window, and plugin registration helpers. Written from scratch (MIT).
local ADDON, ns = ...
local Core = { addon = ADDON, errors = {} }
ns.Core = Core
local C = ns.Compat

Core.MAX_ERRORS = 5
Core.REPORT_LIMIT = 2000
Core.LIB_VERSION = "2.0.0"
-- The addon's repo comes from its TOC (## X-Website), so this file is identical in every addon.
Core.ISSUES_URL = (C.AddOnMeta(ADDON, "X-Website") or ("https://github.com/masterred92/" .. ADDON)) .. "/issues"

-- Localisation: Core.L["text"] returns the translation for the client locale, or the English text itself.
-- Locales/enUS.lua lists every string; other locales add Locales/<locale>.lua calling Core.AddLocale.
Core.L = setmetatable({}, { __index = function(_, k) return k end })
function Core.AddLocale(locale, strings)
  if locale ~= "enUS" and locale ~= C.Locale() then return end
  for k, v in pairs(strings) do if v ~= true then rawset(Core.L, k, v) end end
end

function Core.Version()
  return C.AddOnMeta(ADDON, "Version") or "dev"
end

-- Error ring buffer: only filled from our own pcall sites, never a global error handler.
function Core.RecordError(where, err)
  local e = Core.errors
  e[#e + 1] = { t = date("%H:%M:%S"), where = tostring(where), msg = tostring(err) }
  while #e > Core.MAX_ERRORS do table.remove(e, 1) end
end

function Core.SafeCall(where, fn, ...)
  local res = { pcall(fn, ...) }
  if not res[1] then Core.RecordError(where, res[2]) return false end
  return true, unpack(res, 2)
end

-- Settings proxy: reads fall back to the default, writing a value equal to its default stores nil.
function Core.Settings(store, defaults)
  return setmetatable({}, {
    __index = function(_, k)
      local v = store[k]
      if v == nil then return defaults[k] end
      return v
    end,
    __newindex = function(_, k, v)
      if v == defaults[k] then store[k] = nil else store[k] = v end
    end,
  })
end

-- Runs migrations[n] for every n in (db.schema, latest]. Returns the (possibly replaced) db.
function Core.Migrate(db, migrations, latest)
  db = type(db) == "table" and db or {}
  local from = tonumber(db.schema) or 0
  if from > latest then
    Core.RecordError("migrate", ("SavedVariables schema %d is newer than this version supports (%d)"):format(from, latest))
    return db, false
  end
  for v = from + 1, latest do
    local m = migrations[v]
    if m then
      local ok, newdb = pcall(m, db)
      if not ok then Core.RecordError("migrate " .. v, newdb) return db, false end
      db = newdb or db
    end
    db.schema = v
  end
  db.settings = db.settings or {}
  return db, true
end

-- Plugin registry -------------------------------------------------------------------------
-- spec must include id (string) and format (number <= maxFormat). Calls are pcall-wrapped by
-- Core.CallPlugin; a plugin is switched off after 3 errors.
function Core.NewRegistry(kind, maxFormat, requiredFns)
  local reg = { kind = kind, list = {}, byId = {}, rejected = {} }
  function reg.Register(spec)
    local reason
    if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then reason = "missing id"
    elseif reg.byId[spec.id] then reason = "duplicate id"
    elseif type(spec.format) ~= "number" or spec.format > maxFormat then
      reason = ("format %s not supported (max %d)"):format(tostring(spec and spec.format), maxFormat)
    else
      for _, fname in ipairs(requiredFns) do
        if type(spec[fname]) ~= "function" then reason = "missing function " .. fname break end
      end
    end
    if reason then
      local id = type(spec) == "table" and tostring(spec.id) or "?"
      reg.rejected[id] = reason
      Core.RecordError(kind .. " " .. id, "rejected: " .. reason)
      return false, reason
    end
    local p = { spec = spec, errors = 0, enabled = true, priority = tonumber(spec.priority) or 100 }
    reg.byId[spec.id] = p
    reg.list[#reg.list + 1] = p
    table.sort(reg.list, function(a, b) return a.priority < b.priority end)
    return true
  end
  function reg.Call(p, fname, ...)
    if not p.enabled then return nil end
    local ok, a, b = Core.SafeCall(kind .. " " .. p.spec.id .. "." .. fname, p.spec[fname], ...)
    if ok then return a, b end
    p.errors = p.errors + 1
    if p.errors >= 3 then p.enabled = false end
    return nil
  end
  function reg.Describe()
    local lines = {}
    for _, p in ipairs(reg.list) do
      lines[#lines + 1] = ("%s %s v%s by %s: %s%s"):format(kind, p.spec.id, tostring(p.spec.version or "?"),
        tostring(p.spec.author or "?"), p.enabled and "on" or "OFF (errors)", p.errors > 0 and (", " .. p.errors .. " errors") or "")
    end
    for id, why in pairs(reg.rejected) do lines[#lines + 1] = kind .. " " .. id .. ": REJECTED, " .. why end
    for _, name in ipairs(C.AddOnsWithField("X-KennyAddons-Plugin")) do
      local known = false
      for _, p in ipairs(reg.list) do if p.spec.addon == name then known = true end end
      if not known then lines[#lines + 1] = "installed plugin addon " .. name .. " (not registered with " .. ADDON .. ")" end
    end
    if #lines == 0 then lines[1] = "no " .. kind .. " plugins" end
    return lines
  end
  return reg
end

-- Bug report ------------------------------------------------------------------------------
function Core.BuildReport(stateLines)
  local lines = {
    ("%s %s bug report"):format(ADDON, Core.Version()),
    "Client: " .. C.BuildInfo() .. ", locale " .. C.Locale(),
    "What happened? (describe here)",
    "State:",
  }
  for _, l in ipairs(stateLines or {}) do lines[#lines + 1] = "  " .. tostring(l) end
  lines[#lines + 1] = "Recent errors (" .. #Core.errors .. "):"
  for _, e in ipairs(Core.errors) do lines[#lines + 1] = ("  [%s] %s: %s"):format(e.t, e.where, e.msg) end
  lines[#lines + 1] = "Report at " .. Core.ISSUES_URL
  local text = table.concat(lines, "\n")
  if #text > Core.REPORT_LIMIT then text = text:sub(1, Core.REPORT_LIMIT - 12) .. "\n[trimmed]" end
  return text
end

-- A movable, selectable text window (used for bug reports and CSV export).
local windows = {}
function Core.ShowText(key, title, text)
  local w = windows[key]
  if not w then
    w = CreateFrame("Frame", "Kenny" .. ADDON .. key .. "Window", UIParent, "BackdropTemplate")
    w:SetSize(560, 380)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetClampedToScreen(true)
    w:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    w:SetBackdropColor(0, 0, 0, 0.92)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.title:SetPoint("TOPLEFT", 12, -10)
    w.title:SetPoint("RIGHT", -12, 0)
    w.title:SetJustifyH("LEFT")
    local scroll = CreateFrame("ScrollFrame", nil, w, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 40)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(500)
    edit:SetScript("OnEscapePressed", function() w:Hide() end)
    scroll:SetScrollChild(edit)
    w.edit = edit
    local close = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    close:SetSize(80, 22)
    close:SetPoint("BOTTOMRIGHT", -12, 10)
    close:SetText("Close")
    close:SetScript("OnClick", function() w:Hide() end)
    windows[key] = w
  end
  w.title:SetText(title)
  w.edit:SetText(text)
  w:Show()
  w.edit:SetFocus()
  w.edit:HighlightText()
  return w
end

function Core.ShowReport(stateLines)
  return Core.ShowText("Report", ADDON .. " bug report: Ctrl+C to copy, paste into a GitHub issue", Core.BuildReport(stateLines))
end

function Core.Print(msg)
  print("|cff33ff99" .. ADDON .. "|r: " .. tostring(msg))
end

-- Startup self-check, first-run message and /<cmd> debug -----------------------------------
-- spec = { cmd = "/nflip", required = { "C_AuctionHouse.ReplicateItems", ... }, optional = { "TomTom", ... },
--          db = function() return savedVariablesTable end, firstRun = { "line", ... }, debugLines = function() return {...} end }
local spec
function Core.Setup(s)
  spec = s
  Core.spec = s
  if ns.Hub then ns.Hub.Join(ADDON, Core.Version()) end
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LOGIN")
  f:SetScript("OnEvent", function()
    f:UnregisterEvent("PLAYER_LOGIN")
    Core.SafeCall("startup", Core.Startup)
  end)
end

-- One clear warning for missing client APIs (never silent), then the first-run message once per install.
function Core.Startup()
  if not spec then return end
  local L = Core.L
  local missing = C.MissingAPIs(spec.required)
  if #missing > 0 then
    Core.Print("|cffff4040" .. L["WARNING: this client is missing APIs this addon needs:"] .. "|r " .. table.concat(missing, ", ")
      .. ". " .. L["Some features are switched off. Type"] .. " " .. spec.cmd .. " debug.")
  end
  local db = spec.db and spec.db()
  if type(db) == "table" and not db.firstRunDone then
    db.firstRunDone = Core.Version()
    for _, line in ipairs(spec.firstRun or {}) do Core.Print(line) end
  end
  return missing
end

-- Lines for /<cmd> debug: version, client, every API found or missing, then the addon's own lines.
function Core.DebugLines()
  local L = Core.L
  local lines = { ("%s %s, KennyShared %s, %s %s, %s %s"):format(ADDON, Core.Version(), Core.LIB_VERSION,
    L["client"], C.BuildInfo(), L["locale"], C.Locale()) }
  local function list(names, label)
    for _, n in ipairs(names or {}) do
      lines[#lines + 1] = (C.HasAPI(n) and "  OK      " or ("  " .. label .. " ")) .. n
    end
  end
  list(spec and spec.required, "MISSING")
  list(spec and spec.optional, "absent ")
  if spec and spec.debugLines then
    local ok, extra = pcall(spec.debugLines)
    if ok and type(extra) == "table" then for _, l in ipairs(extra) do lines[#lines + 1] = "  " .. tostring(l) end end
  end
  if ns.Hub then
    local others = {}
    for _, n in ipairs(ns.Hub.Members()) do if n ~= ADDON then others[#others + 1] = n end end
    lines[#lines + 1] = "  " .. L["working together with"] .. ": " .. (#others > 0 and table.concat(others, ", ") or L["none (works on its own)"])
  end
  lines[#lines + 1] = ("  %s: %d"):format(L["recent errors"], #Core.errors)
  return lines
end

function Core.PrintDebug()
  for _, l in ipairs(Core.DebugLines()) do Core.Print(l) end
end

-- Host panels (see Hub.lua): register a simple read-only text panel for a host addon such as DEB.
-- textFn() returns the panel text. Returns nothing useful when no host exists; the addon keeps its own UI.
function Core.RegisterTextPanel(title, textFn)
  if not ns.Hub then return end
  local icon = "Interface\\AddOns\\" .. ADDON .. "\\media\\icon"
  return ns.Hub.RegisterPanel(ADDON, icon, function(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 8, -8); fs:SetPoint("BOTTOMRIGHT", -8, 8)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    local function refresh() local ok, text = pcall(textFn); fs:SetText(ok and text or ("error: " .. tostring(text))) end
    refresh()
    return refresh
  end, { title = title })
end

-- Open this addon's view: inside the host window when one exists, otherwise via fallback() (own window).
function Core.OpenView(fallback)
  if ns.Hub and ns.Hub.ShowPanel(ADDON) then return true end
  fallback()
  return false
end
