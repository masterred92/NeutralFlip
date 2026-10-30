package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
GetSubZoneText = function() return "" end
W.mapID = 1440
local maps = { [1440] = { parentMapID = 1414 }, [1429] = { parentMapID = 1415 } }
C_Map = { GetBestMapForUnit = function() return W.mapID end, GetMapInfo = function(id) return maps[id] end }
C_AuctionHouse.CalculateCommodityDeposit = function() return 1 end
local ldbObjs = {}
LibStub = setmetatable({}, { __call = function(_, name, silent) if name == "LibDataBroker-1.1" then return { NewDataObject = function(_, n, o) ldbObjs[n] = o; return o end } end assert(silent) end })
local tt = { lines = {} }
function tt:AddLine(s) self.lines[#self.lines + 1] = tostring(s) end
function tt:AddDoubleLine(a, b) self.lines[#self.lines + 1] = tostring(a) .. ": " .. tostring(b) end
local function ttText(o) tt.lines = {}; o.OnTooltipShow(tt); return table.concat(tt.lines, " | ") end
W.loadAddon(".", "NeutralFlip")
W.fire("PLAYER_LOGIN"); W.runTimers()
local NF = KennyNeutralFlip
local o = ldbObjs.NeutralFlip
check(o and o.type == "data source" and o.text == "no flips", "LDB object registered at login")
check(ttText(o):find("Nothing worth carrying"), "LDB tooltip with no data")
-- TomTom absent
check(NF.Waypoint("") == nil and W.prints[#W.prints]:find("install TomTom"), "no TomTom: friendly hint")
-- TomTom present
local added, removed = {}, 0
TomTom = { AddWaypoint = function(_, m, x, y, opts) added[#added + 1] = { m, x, y, opts }; return { m, x, y } end,
  RemoveWaypoint = function() removed = removed + 1 end }
NF.Waypoint("")
check(added[1] and added[1][1] == 1446 and added[1][4].title:find("Gadgetzan"), "Kalimdor: Gadgetzan arrow")
W.mapID = 1429; NF.Waypoint("")
check(added[2][1] == 1434 and removed == 1, "Eastern Kingdoms: Booty Bay arrow, old one removed")
SlashCmdList.KENNYNEUTRALFLIP("way everlook")
check(added[3][1] == 1452, "/nflip way everlook")
NF.Waypoint("narnia")
check(#added == 3 and W.prints[#W.prints]:find("usage"), "unknown spot: usage")
o.OnClick(nil, "RightButton")
check(#added == 4, "LDB right-click sets an arrow")
W.done("NeutralFlip extras")
