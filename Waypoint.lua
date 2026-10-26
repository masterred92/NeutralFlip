-- /nflip way: a TomTom arrow to a neutral auction house. Only if TomTom is installed; it just sets a waypoint.
-- Coordinates are approximate (town centre / AH building on the Classic-era zone maps) and get you to the town.
local _, ns = ...
local NF = KennyNeutralFlip
local Core = ns.Core

NF.NEUTRAL_AH = {
  bootybay = { map = 1434, x = 0.27, y = 0.77, title = "Booty Bay auction house (neutral)" },
  gadgetzan = { map = 1446, x = 0.515, y = 0.285, title = "Gadgetzan auction house (neutral)" },
  everlook = { map = 1452, x = 0.61, y = 0.38, title = "Everlook auction house (neutral)" },
}
local KALIMDOR, EASTERN_KINGDOMS = 1414, 1415

-- Which continent is the player on? Walks the map parents; nil if unknown.
function NF.Continent()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
  local id = C_Map.GetBestMapForUnit("player")
  for _ = 1, 8 do
    if type(id) ~= "number" or id == KALIMDOR or id == EASTERN_KINGDOMS then return id end
    local info = C_Map.GetMapInfo(id)
    id = info and info.parentMapID
  end
end

local current
function NF.Waypoint(which)
  which = (which or ""):lower():gsub("%s", "")
  if type(TomTom) ~= "table" or type(TomTom.AddWaypoint) ~= "function" then
    Core.Print("install TomTom for a waypoint arrow. The neutral AHs are in Booty Bay, Gadgetzan and Everlook.")
    return nil
  end
  if which == "" then which = (NF.Continent() == KALIMDOR) and "gadgetzan" or "bootybay" end
  local spot = NF.NEUTRAL_AH[which]
  if not spot then Core.Print("usage: /nflip way [bootybay|gadgetzan|everlook]") return nil end
  if current and type(TomTom.RemoveWaypoint) == "function" then pcall(TomTom.RemoveWaypoint, TomTom, current) end
  local ok, uid = pcall(TomTom.AddWaypoint, TomTom, spot.map, spot.x, spot.y, { title = spot.title, from = "NeutralFlip" })
  current = ok and uid or nil
  Core.Print(ok and ("TomTom arrow set: " .. spot.title .. ".") or "TomTom refused the waypoint.")
  return current
end
