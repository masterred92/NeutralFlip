-- Compat.lua (shared helper; identical in each Kenny addon repo)
-- Every WoW client call goes through here. Each function is feature-tested before use, and any
-- secret value (Midnight-API "secret values") is treated as unknown: we return nil instead of
-- comparing, doing maths on, or formatting it. Written from scratch for this repo (MIT).
local _, ns = ...
local C = {}
ns.Compat = C

local isSecretFn = issecretvalue
function C.IsSecret(v)
  return isSecretFn ~= nil and v ~= nil and isSecretFn(v) == true
end

-- Returns v, or nil when v is a secret value.
function C.Safe(v)
  if C.IsSecret(v) then return nil end
  return v
end

local function safeNumber(v)
  v = C.Safe(v)
  if type(v) == "number" then return v end
  return nil
end
C.SafeNumber = safeNumber

function C.InCombat()
  if C_RestrictedActions and C_RestrictedActions.InCombatLockdown then
    return C_RestrictedActions.InCombatLockdown() == true
  end
  if UnitAffectingCombat then return UnitAffectingCombat("player") == true end
  return false
end

-- { name, sellPrice, classID, subClassID } or nil while the client is still loading the item.
function C.GetItemInfo(itemID)
  if not (C_Item and C_Item.GetItemInfo) or type(itemID) ~= "number" then return nil end
  local ok, name, _, _, _, _, _, _, _, _, _, sellPrice, classID, subClassID = pcall(C_Item.GetItemInfo, itemID)
  if not ok or name == nil then return nil end
  return { name = C.Safe(name), sellPrice = safeNumber(sellPrice), classID = safeNumber(classID), subClassID = safeNumber(subClassID) }
end

-- classID, subClassID without a server round trip.
function C.GetItemClass(itemID)
  if not (C_Item and C_Item.GetItemInfoInstant) or type(itemID) ~= "number" then return nil end
  local ok, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, itemID)
  if not ok then return nil end
  return safeNumber(classID), safeNumber(subClassID)
end

function C.GetItemName(itemID)
  if C_Item and C_Item.GetItemNameByID and type(itemID) == "number" then
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if ok then return C.Safe(name) end
  end
  return nil
end

function C.GetMoney()
  if GetMoney then return safeNumber(GetMoney()) end
  return nil
end

function C.GetZone()
  if GetRealZoneText then return C.Safe(GetRealZoneText()) end
  return nil
end

function C.Now() return time() end
function C.Clock() return GetTime() end

-- Bag contents as { [itemID] = count }. Slots whose data is secret are skipped.
function C.GetBagCounts()
  local counts = {}
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return counts end
  local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  for bag = 0, last do
    for slot = 1, (safeNumber(C_Container.GetContainerNumSlots(bag)) or 0) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local id = info and safeNumber(info.itemID)
      local n = info and safeNumber(info.stackCount)
      if id and n then counts[id] = (counts[id] or 0) + n end
    end
  end
  return counts
end

-- Auction house ------------------------------------------------------------------------

function C.AHReady()
  return C_AuctionHouse ~= nil and C_AuctionHouse.IsThrottledMessageSystemReady ~= nil and C_AuctionHouse.IsThrottledMessageSystemReady() == true
end

function C.AHReplicate()
  if C_AuctionHouse and C_AuctionHouse.ReplicateItems then C_AuctionHouse.ReplicateItems() return true end
  return false
end

function C.AHNumReplicate()
  return C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems and safeNumber(C_AuctionHouse.GetNumReplicateItems()) or 0
end

-- itemID, name, count, buyout for one full-scan row (0-based index), or nil.
function C.AHReplicateRow(i)
  if not (C_AuctionHouse and C_AuctionHouse.GetReplicateItemInfo) then return nil end
  local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAll = C_AuctionHouse.GetReplicateItemInfo(i)
  if C.Safe(hasAll) ~= true then return nil end
  itemID, count, buyout = safeNumber(itemID), safeNumber(count), safeNumber(buyout)
  if not (itemID and count and count > 0 and buyout and buyout > 0) then return nil end
  return itemID, C.Safe(name), count, buyout
end

-- { { itemID, minPrice, quantity } } from the current browse results.
function C.AHBrowse()
  local out = {}
  if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return out end
  for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
    local id = r.itemKey and safeNumber(r.itemKey.itemID)
    local p, q = safeNumber(r.minPrice), safeNumber(r.totalQuantity)
    if id and p and p > 0 then out[#out + 1] = { itemID = id, price = p, quantity = q or 0 } end
  end
  return out
end

-- Unit prices and quantities for a commodity search: { {price, quantity}, ... }
function C.AHCommodity(itemID)
  local out = {}
  if not (C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults and C_AuctionHouse.GetCommoditySearchResultInfo) then return out end
  for i = 1, (safeNumber(C_AuctionHouse.GetNumCommoditySearchResults(itemID)) or 0) do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    local p, q = r and safeNumber(r.unitPrice), r and safeNumber(r.quantity)
    if p and p > 0 then out[#out + 1] = { price = p, quantity = q or 0 } end
  end
  return out
end

-- Client / addon info for bug reports ------------------------------------------------------
function C.BuildInfo()
  if GetBuildInfo then
    local version, build, _, iface = GetBuildInfo()
    return tostring(version) .. " (" .. tostring(build) .. ") interface " .. tostring(iface)
  end
  return "unknown"
end

function C.Locale() return GetLocale and GetLocale() or "unknown" end

function C.RealmFaction()
  local realm = GetRealmName and C.Safe(GetRealmName()) or "realm"
  local faction = UnitFactionGroup and C.Safe(UnitFactionGroup("player")) or "faction"
  return tostring(realm) .. "-" .. tostring(faction)
end

function C.AddOnMeta(addon, field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, addon, field)
    if ok then return v end
  end
  return nil
end

-- Names of installed addons whose TOC carries `field` (plugin discovery).
function C.AddOnsWithField(field)
  local list = {}
  if not (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetAddOnInfo) then return list end
  for i = 1, C_AddOns.GetNumAddOns() do
    local name = C_AddOns.GetAddOnInfo(i)
    if name and C.AddOnMeta(name, field) then list[#list + 1] = name end
  end
  return list
end

function C.Money(copper)
  copper = safeNumber(copper)
  if not copper or copper <= 0 then return "-" end
  if GetMoneyString then return GetMoneyString(math.floor(copper), true) end
  return tostring(math.floor(copper)) .. "c"
end
