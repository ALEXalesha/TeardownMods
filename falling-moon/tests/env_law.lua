-- Falling Moon environment law (in-game report: "when the moon appears, only the sky flickers").
-- Cause: the sky properties were rewritten every 0.5 s during the whole approach. With the
-- optional red sky switched on, each sky property may be written exactly twice - once when the
-- moon is called and once to restore it at the end - only by the server, and the restored value
-- equals the original. Aborting with RMB restores it the same way.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
H.addStaticBox(V(-30, 0, -70), V(30, 10, -69), "masonry")
H.reg["savegame.mod.redsky"] = true
local orig = {}
for k, v in pairs(H.env) do orig[k] = { v[1], v[2], v[3], v[4] } end

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("fallingmoon")
T.frames(1)

local function check(label)
	local per, frames, sides = {}, {}, {}
	for _, e in ipairs(H.envLog) do
		per[e.key] = (per[e.key] or 0) + 1
		frames[e.key] = frames[e.key] or {}
		table.insert(frames[e.key], e.frame)
		sides[e.ctx] = true
	end
	local ok = true
	for k, n in pairs(per) do if n ~= 2 then ok = false end end
	T.check(next(per) ~= nil and ok, label .. ": each sky property written exactly twice (apply once, restore once)")
	T.check(sides.server and not sides.client, label .. ": a single writer (the server)")
	local restored = true
	for k, n in pairs(per) do
		local a, b = H.env[k], orig[k]
		if b then for i = 1, 3 do if math.abs((a[i] or 0) - (b[i] or 0)) > 1e-6 then restored = false end end end
	end
	T.check(restored, label .. ": sky restored exactly")
end

T.press("usetool"); T.frames(2)
srv().ev.T = 60
sh().m.T = 60
T.runUntil(function() return sh().m.phase == "idle" end, 9000)
check("full event")

H.envLog = {}
T.press("usetool"); T.frames(2)
srv().ev.T = 60
sh().m.T = 60
T.frames(300)
T.press("grab"); T.frames(2)
T.runUntil(function() return sh().m.phase == "idle" end, 1200)
check("called off")
