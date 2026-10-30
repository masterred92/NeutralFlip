-- KennyShared 2.0.0: checks the addon and its test mock against Blizzard's REAL API documentation for
-- WoW: Forever (Gethe/wow-ui-source, forever branch). It loads Blizzard's own generated Lua doc files,
-- so a function, event, struct field or return position we rely on must exist in the Forever client.
-- usage: lua tests/test_blizzard_docs.lua <wow-ui-source checkout> <AddonName>
package.path = "tests/?.lua;" .. package.path
local ui, addon = arg[1], arg[2]
if not ui or ui == "" then print("test_blizzard_docs: SKIP (no wow-ui-source path given)") os.exit(0) end
local docDir = ui .. "/Interface/AddOns/Blizzard_APIDocumentationGenerated/"

local systems = {}
-- Some doc files read Enum/Constants values at load time; give them permissive stand-ins.
local function anyTable() return setmetatable({}, { __index = function(t, k) local v = anyTable(); rawset(t, k, v); return v end,
  __call = function() return 0 end, __unm = function() return 0 end, __add = function() return 0 end, __sub = function() return 0 end,
  __mul = function() return 0 end, __div = function() return 0 end, __concat = function() return "" end }) end
Enum, Constants = anyTable(), anyTable()
APIDocumentation = { AddDocumentationTable = function(_, t) systems[#systems + 1] = t end }
local p = io.popen('ls "' .. docDir .. '"')
local nfiles = 0
for name in p:lines() do
  if name:match("%.lua$") then assert(loadfile(docDir .. name))(); nfiles = nfiles + 1 end
end
p:close()
assert(nfiles > 100, "too few Blizzard doc files loaded from " .. docDir)

local funcs, events, structs = {}, {}, {}
for _, s in ipairs(systems) do
  for _, fn in ipairs(s.Functions or {}) do
    funcs[(s.Namespace and (s.Namespace .. ".") or "") .. fn.Name] = fn
  end
  for _, e in ipairs(s.Events or {}) do events[e.LiteralName] = true end
  for _, t in ipairs(s.Tables or {}) do if t.Type == "Structure" then structs[t.Name] = t end end
end

local fails, passes = 0, 0
local function check(c, label) if c then passes = passes + 1 else fails = fails + 1; io.write("FAIL: ", label, "\n") end end
local function field(struct, name)
  for _, f in ipairs((structs[struct] or {}).Fields or {}) do if f.Name == name then return true end end
  return false
end
local function ret(fname, i) local f = funcs[fname]; return f and f.Returns and f.Returns[i] and f.Returns[i].Name end

-- 1. Every C_Namespace.Function and every registered event in the addon's own files exists in Forever.
local src = {}
for line in io.lines(addon .. ".toc") do
  line = line:gsub("\\", "/")
  if line:match("%.lua$") and not line:match("^#") then local fh = io.open(line); src[#src + 1] = fh:read("*a"); fh:close() end
end
local code = table.concat(src, "\n"):gsub("%-%-[^\n]*", "")
local seen = {}
for name in code:gmatch("(C_%w+%.%w+)") do
  if not seen[name] then seen[name] = true; check(funcs[name] ~= nil, "API not in Forever docs: " .. name) end
end
for ev in code:gmatch('RegisterEvent%("([%w_]+)"%)') do check(events[ev], "event not in Forever docs: " .. ev) end

-- 2. What Compat.lua reads from the AH must match the documented return order / struct fields.
check(ret("C_AuctionHouse.GetReplicateItemInfo", 3) == "count", "GetReplicateItemInfo return 3 is count")
check(ret("C_AuctionHouse.GetReplicateItemInfo", 10) == "buyoutPrice", "GetReplicateItemInfo return 10 is buyoutPrice")
check(ret("C_AuctionHouse.GetReplicateItemInfo", 17) == "itemID", "GetReplicateItemInfo return 17 is itemID")
check(ret("C_AuctionHouse.GetReplicateItemInfo", 18) == "hasAllInfo", "GetReplicateItemInfo return 18 is hasAllInfo")
check(field("BrowseResultInfo", "itemKey") and field("BrowseResultInfo", "minPrice") and field("BrowseResultInfo", "totalQuantity"),
  "BrowseResultInfo has itemKey/minPrice/totalQuantity")
check(field("CommoditySearchResultInfo", "unitPrice") and field("CommoditySearchResultInfo", "quantity"),
  "CommoditySearchResultInfo has unitPrice/quantity")
check(field("ContainerItemInfo", "itemID") and field("ContainerItemInfo", "stackCount"), "ContainerItemInfo has itemID/stackCount")

-- 3. The offline mock may only fake functions Forever really has (no mocks proving mocks).
Enum, Constants = nil, nil
local W = require("mock_wow"); W.install()
for k, v in pairs(_G) do
  if type(k) == "string" and k:match("^C_") and type(v) == "table" then
    for fname in pairs(v) do check(funcs[k .. "." .. fname] ~= nil, "mock fakes an API Forever lacks: " .. k .. "." .. fname) end
  end
end

io.write(("test_blizzard_docs (%d Forever doc files): %d passed, %d failed\n"):format(nfiles, passes, fails))
os.exit(fails == 0 and 0 or 1)
