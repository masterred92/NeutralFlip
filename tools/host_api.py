"""Host-addon and client names that are not in Blizzard's UI source, each checked by hand in the host's source.

Host checkouts used (cloned under /workspace/wow-hosts on 2026-10-26):
  DeadlyBossMods d31d9d4 (ReleaseRevision 20261026000000), BigWigs b26c019 (r427, 2026-10-23),
  Details-Damage-Meter d1e8ad7 (realversion 172, Details_Camelot.toc = 16001), Questie 12.3.1 (Questie_Camelot.toc),
  LibDataBroker-1.1, TomTom 4.3.13, Bagnon 12.1.7.
"""
HOST = {
    "KennyPriceLog": "our own PriceLog addon (github.com/masterred92/PriceLog), optional",
    "KennyMatTooltip": "our own MatTooltip addon (github.com/masterred92/MatTooltip), optional",
    "KennyNeutralFlip": "our own NeutralFlip addon (github.com/masterred92/NeutralFlip)",
    "KennyGoldPerSpot": "our own GoldPerSpot addon (github.com/masterred92/GoldPerSpot)",
    "PlaySoundFile": "client API; used on 16001 by BigWigs Core/PluginPrototype.lua and DBM (not in Blizzard's own UI source)",
    "DBM": "DBM-Core global (DBM-Core.lua); RegisterCallback/CreateBreakTimer/CreatePullTimer/CreatePizzaTimer/ReleaseRevision",
    "BigWigsLoader": "BigWigs Loader.lua global; RegisterMessage, GetReleaseString",
    "BigWigsAPI": "BigWigs API.lua global; RegisterBarStyle, RegisterCountdown, CreateBarFromAddon",
    "Details": "Details global (boot.lua); InstallPlugin, NewPluginObject, ToolBar, RegisterEvent, realversion",
    "DETAILSPLUGIN_ALWAYSENABLED": "Details core/plugins.lua constant",
    "Questie": "Questie global (Questie.lua); Questie.API.RegisterOnReady / RegisterForQuestUpdates",
    "LibStub": "LibStub (shipped by BigWigs, Details, Titan, Bagnon and most broker displays)",
    "TomTom": "TomTom global (TomTom.lua); TomTom:AddWaypoint(mapID, x, y, opts)",
    "Bagnon": "Bagnon global (Bagnon addon); Bagnon.Item.Update",
    "BagBrother": "BagBrother global (BagBrother addon, Bagnon's item data)",
}
HOST_METHODS = {
    "RegisterCallback": "DBM:RegisterCallback(event, func) DBM-Core.lua",
    "UnregisterCallback": "DBM:UnregisterCallback(event, func) DBM-Core.lua",
    "CreateBreakTimer": "DBM:CreateBreakTimer(minutes) DBM-Core/modules/UserTimers.lua",
    "CreatePullTimer": "DBM:CreatePullTimer(seconds) DBM-Core/modules/UserTimers.lua",
    "CreatePizzaTimer": "DBM:CreatePizzaTimer(time, text, broadcast, ...) DBM-Core/modules/UserTimers.lua",
    "AddVictorySound": "DBM:AddVictorySound(text, value, length) DBM-Core/modules/objects/Sounds.lua",
    "AddDefeatSound": "DBM:AddDefeatSound(text, value, length) DBM-Core/modules/objects/Sounds.lua",
    "GetReleaseString": "BigWigsLoader:GetReleaseString() Loader.lua",
    "RegisterBarStyle": "BigWigsAPI:RegisterBarStyle(key, styleData) API.lua",
    "RegisterCountdown": "BigWigsAPI:RegisterCountdown(id, name, data) API.lua",
    "InstallPlugin": "Details:InstallPlugin(type, name, icon, obj, absName, minVersion, author, version, defaults) core/plugins.lua",
    "NewPluginObject": "Details:NewPluginObject(frameName, flag, type) core/plugins.lua",
    "NewPluginToolbarButton": "Details.ToolBar:NewPluginToolbarButton(func, icon, name, tooltip, w, h, frameName) core/plugins_toolbar.lua",
    "ShowToolbarIcon": "Details:ShowToolbarIcon(button, effect) core/plugins_toolbar.lua",
    "HideToolbarIcon": "Details:HideToolbarIcon(button) core/plugins_toolbar.lua",
    "NewDataObject": "LibDataBroker-1.1 :NewDataObject(name, dataobj)",
    "Register": "LibSharedMedia-3.0 :Register(mediatype, key, data)",
    "AddWaypoint": "TomTom:AddWaypoint(m, x, y, opts) TomTom.lua",
    "RemoveWaypoint": "TomTom:RemoveWaypoint(uid) TomTom.lua",
    # LibCandyBar-3.0 bar methods (BigWigs Plugins/Bars.lua + BarStyles.lua use every one of these)
    "Get": "LibCandyBar bar:Get(key)", "Set": "LibCandyBar bar:Set(key, value)",
    "SetTextColor": "LibCandyBar bar:SetTextColor / FontString:SetTextColor",
    "SetShadowColor": "LibCandyBar bar:SetShadowColor / FontString:SetShadowColor",
    "SetBackgroundColor": "LibCandyBar bar:SetBackgroundColor (Plugins/Bars.lua CreateBar)",
    "AddLine": "GameTooltip:AddLine (LDB OnTooltipShow)",
}
