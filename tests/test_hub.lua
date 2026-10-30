-- KennyShared 2.0.0: the shared hub (prices, scans, tooltips, launcher, voice lines, panels, enrichment).
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
local runTimers = W.runTimers or function() W.advance(0) end
local toc = io.popen("ls *.toc"):read("*l")
local name = toc:gsub("%.toc$", "")
local objs = {}
LibStub = setmetatable({}, { __call = function(_, lib, silent)
  if lib == "LibDataBroker-1.1" then return { NewDataObject = function(_, n, o) objs[n] = o; return o end } end
  assert(silent) end })
local ns = W.loadAddon(".", name)
local hub = ns.Hub
W.fire("PLAYER_LOGIN"); runTimers()
check(KennyAddonsHub == hub and hub.Has(name), "joined the shared hub")
-- prices: newest wins, own source can be excluded
hub.RegisterPrices("A", function() return { p = 100, t = 5 } end)
hub.RegisterPrices("B", function() return { p = 200, t = 9 } end)
check(hub.GetPrice(1).p == 200 and hub.GetPrice(1, "B").p == 100, "shared price lookup")
hub.prices.A, hub.prices.B = nil, nil
-- scans: one per 15 minutes for everyone
hub.lastScan = 0
check(hub.ClaimScan("X") == true, "first scan claim")
local ok, by = hub.ClaimScan("Y")
check(ok == false and by == "X", "second addon defers to the running scan")
-- voice lines never overlap
local played = 0
PlaySoundFile = function() played = played + 1; return true end
hub.voiceUntil = 0
check(hub.PlayVoice("a") == true and hub.PlayVoice("b") == false and played == 1, "voice lines do not overlap")
W.clock = W.clock + 10
check(hub.PlayVoice("c") == true, "voice plays again after the gap")
-- tooltip: ordered, deduplicated
local lines = {}
local tt = { AddLine = function(_, s) lines[#lines + 1] = s end, AddDoubleLine = function(_, a) lines[#lines + 1] = a end }
hub.tooltips = {}
hub.AddTooltip("Z", 30, function(t) if t.Claim("price.auction") then t:AddLine("Z price") end t:AddLine("Z verdict") end)
hub.AddTooltip("Y", 10, function(t) if t.Claim("price.auction") then t:AddLine("Y price") end end)
hub.RunTooltips(tt, { id = 5 })
check(table.concat(lines, ",") == "Y price,Z verdict", "one ordered tooltip block, no duplicate price: " .. table.concat(lines, ","))
-- launcher: one combined entry when several addons register
if #hub.launchers > 0 then check(hub.built == true, "launcher built after login") end
hub.built, hub.combined, hub.launchers = nil, nil, {}
objs = {}
local e1 = hub.Launcher("One", { type = "data source", text = "1", OnClick = function() end })
hub.Launcher("Two", { type = "data source", text = "2", OnClick = function() end })
runTimers()
check(objs.KennyAddons and not objs.One and not objs.Two, "one shared launcher instead of several")
e1.text = "one!"
check(objs.KennyAddons.text:find("one!", 1, true), "launcher text follows each addon")
-- panels: hosted when a host exists, own window otherwise
check(hub.ShowPanel(name) == false, "no host: addon uses its own window")
local added, shown = {}, nil
hub.SetHost({ AddPanel = function(p) added[#added + 1] = p.name end, Show = function(n) shown = n; return true end })
hub.RegisterPanel("P", "icon", function() end)
check(#added >= 1 and hub.ShowPanel("P") == true and shown == "P", "host shows registered panels as tabs")
hub.host = nil
-- enrichment
hub.Provide("test", "Q", function(id) if id == 1 then return "yes" end end)
check(hub.Ask("test", 1) == "yes" and hub.Ask("test", 2) == nil and hub.Ask("none") == nil, "enrichment only when data exists")
W.done(name .. " hub")
