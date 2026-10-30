#!/usr/bin/env python3
"""KennyShared 2.0.0: check that every host-addon API our plugins call is really defined in the host's source.

usage: verify_hosts.py <dir with host checkouts> [Host ...]
Each host is a checkout folder name (DeadlyBossMods, BigWigs, Details-Damage-Meter, Questie). Only the hosts named
(default: every folder present) are checked; each check is a regex that must match a definition in the host source.
CI pins the host commits listed in PINS, the ones the plugins were built and tested against."""
import re, sys, pathlib

PINS = {  # host folder -> (GitHub repo, commit)
    "DeadlyBossMods": ("DeadlyBossMods/DeadlyBossMods", "d31d9d468f2c1b7c6cf384a3c1f8967c5ef145dd"),
    "BigWigs": ("BigWigsMods/BigWigs", "b26c01915ddb84db2a230b10321551e30ce6b0f4"),
    "Details-Damage-Meter": ("Tercioo/Details-Damage-Meter", "d1e8ad7226616b4a796eebc6ca3ed905ef410b64"),
    "Questie": ("Questie/Questie", "346e9576fbe9b20b00a98586681ecc089dbac273"),
}
CHECKS = {
    "DeadlyBossMods": [
        ("DBM:RegisterCallback", r"function DBM:RegisterCallback\("), ("DBM:UnregisterCallback", r"function DBM:UnregisterCallback\("),
        ("DBM:CreateBreakTimer", r"function DBM:CreateBreakTimer\("), ("DBM:CreatePullTimer", r"function DBM:CreatePullTimer\("),
        ("DBM:CreatePizzaTimer", r"function DBM:CreatePizzaTimer\("),
        ("DBM:AddVictorySound", r"function DBM:AddVictorySound\("), ("DBM:AddDefeatSound", r"function DBM:AddDefeatSound\("),
        ("DBM.ReleaseRevision", r"DBM\.ReleaseRevision\s*="), ("DBM_TimerBegin callback", r"\"DBM_TimerBegin\""),
    ],
    "BigWigs": [
        ("BigWigsAPI:RegisterBarStyle", r"function API:RegisterBarStyle\("), ("BigWigsAPI:RegisterCountdown", r"function API:RegisterCountdown\("),
        ("BigWigsLoader:RegisterMessage", r"function public:RegisterMessage\("), ("BigWigsLoader:GetReleaseString", r"function public:GetReleaseString\("), ("BigWigs_StartCountdown message", r"SendMessage\(\"BigWigs_StartCountdown\""),
    ],
    "Details-Damage-Meter": [
        ("Details:InstallPlugin", r"function Details:InstallPlugin\s*\("), ("Details:NewPluginObject", r"function Details:NewPluginObject\("),
        ("ToolBar:NewPluginToolbarButton", r"ToolBar:NewPluginToolbarButton\s*\("), ("ShowToolbarIcon", r"ShowToolbarIcon\s*\("),
    ],
    "Questie": [
        ("Questie.API.RegisterOnReady", r"function Questie\.API\.RegisterOnReady\("),
        ("Questie.API.RegisterForQuestUpdates", r"function Questie\.API\.RegisterForQuestUpdates\("),
        ("QuestUpdateTriggerReason.QUEST_UPDATED", r"QUEST_UPDATED\s*=\s*2"), ("profile.soundOnQuestComplete", r"soundOnQuestComplete"),
    ],
}
root = pathlib.Path(sys.argv[1]); hosts = sys.argv[2:] or [h for h in CHECKS if (root / h).is_dir()]
fails = total = 0
for h in hosts:
    src = "\n".join(p.read_text(errors="ignore") for p in (root / h).rglob("*.lua") if ".test." not in p.name and "/tests/" not in str(p))
    for label, rx in CHECKS[h]:
        total += 1
        ok = re.search(rx, src) is not None
        fails += not ok
        print(("OK   " if ok else "MISS ") + f"{h}: {label}")
print(f"{total - fails}/{total} host APIs verified")
sys.exit(1 if fails or not total else 0)
