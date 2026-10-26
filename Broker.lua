-- LibDataBroker launcher for Titan Panel, ChocolateBar, Bazooka and other LDB displays (only if one is installed).
local _, ns = ...
local NF = KennyNeutralFlip
local C = ns.Compat
local obj

function NF.UpdateBroker()
  if not obj then return end
  local ok, list = pcall(NF.Opportunities)
  local n = ok and #list or 0
  obj.text = n > 0 and (n .. " flips") or "no flips"
  return list
end

local function tooltip(tt)
  tt:AddLine("NeutralFlip")
  local list = NF.UpdateBroker() or {}
  if #list == 0 then tt:AddLine("Nothing worth carrying yet. Record prices at both AHs.", 1, 1, 1, true) end
  for i = 1, math.min(5, #list) do
    local o = list[i]
    tt:AddDoubleLine(("%s  %s > %s"):format(o.name, NF.KindLabel(o.from), NF.KindLabel(o.to)), "+" .. C.Money(o.total), 1, 1, 1, 0.2, 1, 0.6)
  end
  tt:AddLine("Left-click: flip list. Right-click: TomTom arrow to a neutral AH.", 0.6, 0.6, 0.6, true)
end

function NF.InstallBroker()
  if obj then return obj end
  local ldb = type(LibStub) == "table" and LibStub("LibDataBroker-1.1", true)
  if not ldb then return nil end
  obj = ldb:NewDataObject("NeutralFlip", {
    type = "data source", text = "NeutralFlip", label = "NeutralFlip",
    icon = "Interface\\AddOns\\NeutralFlip\\media\\icon",
    OnClick = function(_, button)
      if button == "RightButton" then NF.Waypoint("") else SlashCmdList.KENNYNEUTRALFLIP("") end
    end,
    OnTooltipShow = tooltip,
  })
  NF.UpdateBroker()
  return obj
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then NF.InstallBroker() else NF.UpdateBroker() end
end)
