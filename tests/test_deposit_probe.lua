-- NF.ProbeDepositRate under WoW: Forever's auction deposit rules. The minimum deposit per auction is 1 copper since
-- the November 17 maintenance (November 10 hotfix notes; it was 1 silver before), and a deposit is whole copper. The mock deposit follows that:
-- max(1, floor(vendor price x quantity x house rate)). A probe on a cheap item then measures the floor or the
-- rounding instead of the house's rate, which also skews the "deposit at risk" estimate and the house cross-check.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
GetSubZoneText = function() return "" end
C_Map = { GetBestMapForUnit = function() return nil end }
W.depositRate, W.depositCalls = 0.03, 0
FLOOR = 1 -- luacheck: ignore (tests are not linted)
C_AuctionHouse.CalculateCommodityDeposit = function(id, _, q)
  W.depositCalls = W.depositCalls + 1
  local i = W.items[id]
  if not i then return nil end
  return math.max(FLOOR, math.floor(i[4] * q * W.depositRate))
end
W.items[2678] = { "Mild Spices", 7, 0, 1 }       -- vendor 1c (Blizzard blue post, Nov 2026)
W.items[2589] = { "Linen Cloth", 7, 5, 13 }      -- vendor 13c
W.items[4306] = { "Silk Cloth", 7, 5, 150 }      -- vendor 1s 50c
-- SavedVariables from 0.3.2 with a rate that was really the 1s minimum deposit.
KennyNeutralFlipDB = { schema = 1, houses = {}, overrides = { ["A/B"] = "neutral" }, rates = { faction = 5, neutral = 1.5 } }
W.loadAddon(".", "NeutralFlip")
W.fire("PLAYER_LOGIN"); W.runTimers()
local NF, db = KennyNeutralFlip, KennyNeutralFlipDB
check(db.schema == 2 and next(db.rates) == nil and db.overrides["A/B"] == "neutral",
  "rates learned before 0.3.3 are forgotten, overrides kept")

-- The 0.3.2 probe, kept here to show what it measured: first bag item with a vendor price, any deposit above 0.
local function oldProbe()
  for _, e in pairs(W.bags[0]) do
    local itemID, i = e[1], W.items[e[1]]
    if i and i[4] > 0 then
      local dep = C_AuctionHouse.CalculateCommodityDeposit(itemID, 1, 20)
      if dep and dep > 0 then return dep / (i[4] * 20) end
    end
  end
end
local function near(a, b, tol) return a and math.abs(a - b) <= b * tol end

-- 1. Only a 1c item in the bags: 20 x 1c x 0.03 = 0.6c, so the deposit hits the 1c floor.
W.bags[0] = { [1] = { 2678, 20 } }
local old = oldProbe()
check(old and math.abs(old - 0.05) < 1e-9, "0.3.2 probe measured the 1c floor as 0.05, 67% above the true 0.03")
local r = NF.ProbeDepositRate()
check(r == nil or near(r, 0.03, 0.05), "floored deposit is not reported as the house rate (got " .. tostring(r) .. ", true 0.03)")
-- Two houses with different rates both hit the floor: they would look identical.
W.depositRate = 0.045
local r2 = NF.ProbeDepositRate()
check(r2 == nil or r ~= r2, "two different house rates are not measured as the same number")

-- 2. Rounding on a cheap item: 20 x 1c x 0.12 = 2.4c, deposit 2c, measured 0.10 (17% low).
W.depositRate = 0.12
r = NF.ProbeDepositRate()
check(r == nil or near(r, 0.12, 0.05), "rounding on a tiny deposit is not reported as the rate (got " .. tostring(r) .. ")")

-- 3. A cheap item and a dearer one in the bags: the probe uses an item whose deposit is well above the floor.
W.depositRate = 0.12
W.bags[0] = { [1] = { 2678, 20 }, [2] = { 2589, 20 }, [3] = { 4306, 5 } }
r = NF.ProbeDepositRate()
check(near(r, 0.12, 0.01), "rate measured on a deposit well above the floor (got " .. tostring(r) .. ")")
W.depositRate = 0.03
r = NF.ProbeDepositRate()
check(near(r, 0.03, 0.02), "low house rate measured exactly on Silk Cloth (got " .. tostring(r) .. ")")

-- 4. The probe is bounded: a bag of 40 different items costs at most 20 deposit queries.
W.bags[0] = {}
for i = 1, 40 do W.items[90000 + i] = { "Junk " .. i, 15, 0, 1 }; W.bags[0][i] = { 90000 + i, 1 } end
W.depositCalls = 0
r = NF.ProbeDepositRate()
check(r == nil and W.depositCalls <= 20, "only floored items: no rate, bounded number of queries")

-- 5. A per-auction floor of any size: with the old 1s floor, Linen Cloth (20 x 13c x 0.12 = 31c) is clamped to
-- 100c. That is above 20c, so a size check alone takes it (0.38, three times the rate); the doubling check does not.
FLOOR = 100
W.depositRate = 0.12
W.bags[0] = { [1] = { 2589, 20 } }
old = oldProbe()
check(old and old > 0.35, "0.3.2 probe measured the 1s floor as the rate (got " .. tostring(old) .. ")")
check(NF.ProbeDepositRate() == nil, "a clamped deposit above 20c is still not taken as the rate")
W.bags[0] = { [1] = { 2589, 20 }, [2] = { 4306, 5 } }
check(near(NF.ProbeDepositRate(), 0.12, 0.01), "1s floor: rate read on Silk Cloth, whose deposit is above it")
-- Rounding stays small on the reading it keeps: Silk at 0.0085 -> 20 units 25c (25.5), 40 units 51c.
W.depositRate = 0.0085
W.bags[0] = { [1] = { 4306, 5 } }
FLOOR = 1
check(near(NF.ProbeDepositRate(), 0.0085, 0.025), "reading kept within 2.5% of the rate")
-- A deposit that does not double (40 units cost the same as 20): no reading.
local keep2 = C_AuctionHouse.CalculateCommodityDeposit
C_AuctionHouse.CalculateCommodityDeposit = function(id) return id == 4306 and 500 or nil end
check(NF.ProbeDepositRate() == nil, "a flat deposit is not taken as a rate")
C_AuctionHouse.CalculateCommodityDeposit = keep2

-- 6. With no reading, the auction house visit warns about nothing and keeps the stored rates.
db.rates.faction, db.rates.neutral = 0.05, 0.25
W.bags[0] = { [1] = { 2678, 20 } }
W.prints = {}
W.fire("AUCTION_HOUSE_SHOW"); W.runTimers()
local warned = false
for _, p in ipairs(W.prints) do if p:find("deposits here look like") then warned = true end end
check(not warned and db.rates.faction == 0.05 and db.rates.neutral == 0.25, "no reading: no warning, rates unchanged")
W.fire("AUCTION_HOUSE_CLOSED")

-- 7. No API: nil, no error.
local keep = C_AuctionHouse.CalculateCommodityDeposit
C_AuctionHouse.CalculateCommodityDeposit = nil
check(NF.ProbeDepositRate() == nil, "no deposit API: nil")
C_AuctionHouse.CalculateCommodityDeposit = keep
W.done("NeutralFlip deposit probe")
