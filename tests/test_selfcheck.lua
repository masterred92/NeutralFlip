-- KennyShared 2.0.0: first-run message, loud missing-API warning and /<cmd> debug, for any addon using Core.Setup.
package.path = "tests/?.lua;" .. package.path
local W = require("mock_wow"); W.install()
local check = W.check
local toc = io.popen("ls *.toc"):read("*l")
local name = toc:gsub("%.toc$", "")
local ns = W.loadAddon(".", name)
local Core = ns.Core
check(Core.spec ~= nil and Core.spec.cmd ~= nil, "addon calls Core.Setup")
W.prints = {}
W.fire("PLAYER_LOGIN")
local all = table.concat(W.prints, "\n")
local hasFirstRun = Core.spec.firstRun and Core.spec.db and Core.spec.db()
if hasFirstRun then check(#W.prints >= 2, "first-run message printed") end
check(not all:find("WARNING", 1, true), "no warning when every API exists: " .. all)
W.prints = {}
Core.Startup()
if hasFirstRun then check(#W.prints == 0, "first-run message only once") end
-- remove the first required API: exactly one loud line naming it
local path = Core.spec.required[1]
local parent, key = _G, nil
for part in path:gmatch("[^.]+") do if key then parent = parent[key] end key = part end
local saved = parent[key]; parent[key] = nil
W.prints = {}
Core.Startup()
check(#W.prints == 1 and W.prints[1]:find("WARNING", 1, true) and W.prints[1]:find(path, 1, true), "one loud warning naming " .. path)
local dbg = table.concat(Core.DebugLines(), "\n")
check(dbg:find("MISSING " .. path, 1, true), "debug shows the missing API")
parent[key] = saved
dbg = table.concat(Core.DebugLines(), "\n")
check(dbg:find("OK      " .. path, 1, true), "debug shows API found")
W.prints = {}
SlashCmdList[next(SlashCmdList)]("debug")
check(#W.prints >= 2, "/" .. name .. " debug prints a self-check")
W.done(name .. " selfcheck")
