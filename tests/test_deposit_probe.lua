-- NF.ProbeDepositRate under WoW: Forever's auction deposit rules. Since the November 10 hotfix the minimum deposit
-- per auction is 1 copper (was 1 silver), and a deposit is a whole number of copper. The mock deposit follows that:
-- max(1, floor(vendor price x quantity x house rate)). A probe on a cheap item then measures the floor or the
-- rounding instead of the house's rate, which also skews the "deposit at risk" estimate and the house cross-check.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
GetSubZoneText = function() return "" end
C_Map = { GetBestMapForUnit = function() return nil end }
W.depositRate, W.depositCalls = 0.03, 0
local FLOOR = 1
C_AuctionHouse.CalculateCommodityDeposit = function(id, _, q)
  W.depositCalls = W.depositCalls + 1
  local i = W.items[id]
  if not i then return nil end
  return math.max(FLOOR, math.floor(i[4] * q * W.depositRate))
end
W.items[2678] = { "Mild Spices", 7, 0, 1 }       -- vendor 1c (Blizzard blue post, Nov 2026)
W.items[2589] = { "Linen Cloth", 7, 5, 13 }      -- vendor 13c
W.items[4306] = { "Silk Cloth", 7, 5, 150 }      -- vendor 1s 50c
W.loadAddon(".", "NeutralFlip")
W.fire("PLAYER_LOGIN"); W.runTimers()
local NF = KennyNeutralFlip
local function near(a, b, tol) return a and math.abs(a - b) <= b * tol end

-- 1. Only a 1c item in the bags: 20 x 1c x 0.03 = 0.6c, so the deposit hits the 1c floor.
W.bags[0] = { [1] = { 2678, 20 } }
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

-- 5. No API: nil, no error.
local keep = C_AuctionHouse.CalculateCommodityDeposit
C_AuctionHouse.CalculateCommodityDeposit = nil
check(NF.ProbeDepositRate() == nil, "no deposit API: nil")
C_AuctionHouse.CalculateCommodityDeposit = keep
W.done("NeutralFlip deposit probe")
