std = "lua51"
max_line_length = false
exclude_files = { "tests/**", "tools/**", ".release/**", ".lua/**", ".luarocks/**", "wow-ui/**", "index/**", "hosts/**" }
-- Our own globals (all Kenny-prefixed).
globals = { "KennyNeutralFlip", "KennyNeutralFlipDB", "SLASH_KENNYNEUTRALFLIP1", "SLASH_KENNYNEUTRALFLIP2", "SlashCmdList" }
-- WoW API (checked against Blizzard's UI source by tools/verify_api.py) and our other addons' optional globals.
read_globals = { "C_Item", "C_AuctionHouse", "C_Timer", "C_Container", "C_AddOns", "C_RestrictedActions", "C_Map",
  "CreateFrame", "UIParent", "GameTooltip", "ItemRefTooltip", "TooltipDataProcessor", "Enum",
  "GetMoneyString", "GetMoney", "GetTime", "GetRealZoneText", "GetSubZoneText", "GetBuildInfo", "GetLocale",
  "GetRealmName", "UnitFactionGroup", "UnitAffectingCombat", "issecretvalue", "NUM_BAG_SLOTS",
  "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "time", "date",
  "KennyPriceLog", "KennyMatTooltip", "LibStub", "TomTom" }
