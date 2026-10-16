-- Aftershock stop law (independent review 16.10.2026). The description says "LMB starts an earthquake
-- (LMB again stops it)". During an aftershock LMB started a NEW full quake with new aftershocks instead.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -20
H.reg["savegame.mod.duration"] = 5
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("quake"); T.frames(1)
T.press("usetool"); T.frames(2)
T.check(sh().quake.active and sh().quake.after == 0, "main quake started")
T.runUntil(function() return not sh().quake.active end, 1200)
local pend0 = #srv().pending
T.runUntil(function() return sh().quake.active and sh().quake.after == 1 end, 3000)
T.check(sh().quake.after == 1, "aftershock running (pending before: " .. pend0 .. ")")
local n0 = sh().quake.n
T.press("usetool"); T.frames(2)
local q = sh().quake
print(string.format("after LMB during aftershock: active=%s after=%d n %d->%d preset=%d pending=%d", tostring(q.active), q.after, n0, q.n, q.preset, #srv().pending))
T.check(not q.active, "LMB during an aftershock stops it")
T.check(#srv().pending == 0, "and no further aftershocks are scheduled")
