package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
-- extra mock surface this addon uses
W.subzone, W.mapID, W.depositRate = "", nil, 0.3
GetSubZoneText = function() return W.subzone end
C_Map = { GetBestMapForUnit = function() return W.mapID end }
C_AuctionHouse.CalculateCommodityDeposit = function(id, _, q)
  local i = W.items[id]; return i and math.floor(i[4] * q * W.depositRate) end
W.items[785] = { "Mageroyal", 7, 9, 5 }

W.loadAddon(".", "NeutralFlip")
W.fire("PLAYER_LOGIN")
local NF, db = KennyNeutralFlip, KennyNeutralFlipDB
check(db.schema == 1 and db.houses and db.overrides and db.rates, "schema 1 tables")

-- Faction AH in Stormwind
W.zone, W.subzone = "Stormwind City", "Trade District"
W.bags[0] = { [1] = { 2447, 5 } }
W.fire("AUCTION_HOUSE_SHOW"); W.runTimers()
check(NF.CurrentKind() == "Alliance", "faction AH detected")
check(db.rates.faction and math.abs(db.rates.faction - 0.3) < 0.01, "faction deposit rate learned")
W.commodity[785] = { { unitPrice = 100, quantity = 40 }, { unitPrice = 150, quantity = 10 } }
W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 785)
local home = db.houses["TestRealm-Alliance"].items[785]
check(home and home.p == 100 and home.q == 40 and home.n == 50, "commodity search recorded min/qmin/total")
W.replicate = { { 2447, 10, 2000 }, { 2447, 5, 1000 }, { 2318, 1, 900 } }
W.fire("REPLICATE_ITEM_LIST_UPDATE"); W.runTimers()
local pb = db.houses["TestRealm-Alliance"].items[2447]
check(pb and pb.p == 200 and pb.q == 15 and pb.n == 15, "full scan min and qty at min")
W.fire("AUCTION_HOUSE_CLOSED")
check(#NF.Opportunities() == 0, "no flips with one house only")

-- Neutral AH in Booty Bay (by subzone name)
W.zone, W.subzone = "Stranglethorn Vale", "Booty Bay"
W.depositRate = 1.5
W.fire("AUCTION_HOUSE_SHOW"); W.runTimers()
check(NF.CurrentKind() == "Neutral", "neutral AH detected by name")
check(db.rates.neutral and db.rates.neutral > 1.4, "neutral deposit rate learned")
W.commodity[785] = { { unitPrice = 1900, quantity = 30 } }
W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 785)
W.browse = { { itemKey = { itemID = 2447 }, minPrice = 150, totalQuantity = 8 } }
W.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(db.houses["TestRealm-Alliance"].items[785].p == 100, "neutral prices kept in a separate bucket")

local list = NF.Opportunities()
local o = list[1]
check(o and o.itemID == 785 and o.from == "Alliance" and o.to == "Neutral", "Mageroyal: buy home, sell neutral")
-- list at 1899, 15% cut -> floor(1899*0.85)=1614, profit 1514 per unit, qty min(40, 30)=30
check(o and o.net == 1614 and o.profit == 1514 and o.qty == 30 and o.total == 1514 * 30, "net after 15% cut")
check(o and o.deposit == math.floor(db.rates.neutral * 5 * 30), "deposit at risk uses neutral rate")
-- Peacebloom: neutral 150 (qty unknown) vs home 200: list home at 199*0.95=189, profit 39 < minProfit 50 -> none
for _, x in ipairs(list) do check(x.itemID ~= 2447, "small Peacebloom gap filtered") end
check(not o.thin, "19x ratio not thin")
local text = NF.ListText()
check(text:find("BUY at Alliance AH") and text:find("LIST at neutral AH"), "list text: " .. text)

-- Reverse direction, outlier flag
W.commodity[2589] = { { unitPrice = 10, quantity = 100 } }
W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
db.houses["TestRealm-Alliance"].items[2589] = { p = 5000, q = 1, n = 1, t = W.now }
list = NF.Opportunities()
local rev
for _, x in ipairs(list) do if x.itemID == 2589 then rev = x end end
check(rev and rev.from == "Neutral" and rev.to == "Alliance" and rev.thin, "reverse route flagged thin")
check(list[#list].itemID == 2589, "thin routes sort last")

-- Tooltip: added lines only
local tt = W.tooltip(785)
check(tt:find("NeutralFlip") and tt:find("buy at Alliance, list at neutral"), "tooltip: " .. tt)
check(W.tooltip(249427) == "", "no tooltip line without data on either side")

-- Stale data ignored
W.now = W.now + 25 * 3600
check(#NF.Opportunities() == 0, "prices older than 24h ignored")

-- Cross-check warns when the zone guess disagrees with the deposit rate
W.zone, W.subzone = "Elwynn Forest", "Goldshire"
W.depositRate = 1.5
W.prints = {}
W.fire("AUCTION_HOUSE_SHOW"); W.runTimers()
local warned = false
for _, p in ipairs(W.prints) do if p:find("look like the NEUTRAL") then warned = true end end
check(NF.CurrentKind() == "Alliance" and warned, "deposit cross-check warns")
SlashCmdList.KENNYNEUTRALFLIP("here neutral")
check(NF.CurrentKind() == "Neutral" and db.overrides["Elwynn Forest/Goldshire"] == "neutral", "/nflip here override")
SlashCmdList.KENNYNEUTRALFLIP("here auto")
check(db.overrides["Elwynn Forest/Goldshire"] == nil, "override cleared")
-- map ID detection
W.zone, W.subzone, W.mapID = "Somewhere", "", 1446
W.fire("AUCTION_HOUSE_SHOW"); W.runTimers()
check(NF.CurrentKind() == "Neutral", "neutral by map id")
W.mapID = nil

-- Settings + scan cooldown + combat + secret values
SlashCmdList.KENNYNEUTRALFLIP("cut neutral 0.2")
check(math.abs(db.settings.cutNeutral - 0.2) < 1e-9, "cut setting stored")
SlashCmdList.KENNYNEUTRALFLIP("cut neutral 2")
check(math.abs(db.settings.cutNeutral - 0.2) < 1e-9, "invalid cut rejected")
W.replicateRequested = nil
SlashCmdList.KENNYNEUTRALFLIP("scan")
check(W.replicateRequested == 1, "scan requested")
W.replicate = { { 2447, 1, 100 } }; W.fire("REPLICATE_ITEM_LIST_UPDATE"); W.runTimers()
SlashCmdList.KENNYNEUTRALFLIP("scan")
check(W.replicateRequested == 1, "scan cooldown")
W.combat = true
W.browse = { { itemKey = { itemID = 2318 }, minPrice = 77, totalQuantity = 3 } }
W.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(db.houses["TestRealm-Neutral"].items[2318] == nil, "nothing recorded in combat")
W.combat = false
W.secret[77] = true; W.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); W.secret[77] = nil
check(db.houses["TestRealm-Neutral"].items[2318] == nil, "secret price ignored")
for _, c in ipairs({ "", "status", "report", "tooltip", "age 12", "margin 0.3", "bogus" }) do
  local ok, err = pcall(SlashCmdList.KENNYNEUTRALFLIP, c)
  check(ok, "command '" .. c .. "' " .. tostring(err))
end
-- Prune at login
W.now = W.now + 20 * 86400
W.fire("PLAYER_LOGIN")
check(next(db.houses) == nil, "old prices pruned")
W.done("NeutralFlip")
