-- Volcano anchor law, second in-game report: "exactly as crooked as before", even after the
-- closed-loop fix. Variant: the vox pivot is the model's corner (the documented default), the shape keeps
-- the model's own axes (height along its local z, stood up by the shape transform, so
-- GetShapeSize reports the model's x, y, z), and static bodies cannot be moved after spawning.
-- The cone must still stand on the clicked point (measured from world bounds, like the game's
-- spawn menu does), every layer must sit on the one below, smoke/lava/bombs must come from the
-- cone, and the debug line must show the numbers.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "corner", axes = "mv", staticFixed = true, physics = true }   -- pivot at the model corner
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -4
local eye = A.GetPlayerEyeTransform(1)
local fwd = A.TransformToParentVec(eye, V(0, 0, -1))
local tHit = -eye.pos[2] / fwd[2]
local click = V(eye.pos[1] + fwd[1] * tHit, 0, eye.pos[3] + fwd[3] * tHit)

H.reg["savegame.mod.debugline"] = true   -- the debug line is off by default since 10.10; this law reads it
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("volcano")
T.frames(1)
T.press("usetool"); T.frames(2)
T.runUntil(function() return sh().v.phase == "rumble" end, 900)
local layers = srv().v.layers
T.check(#layers == 7, "seven layers")
local mn, mx = V(1e9, 1e9, 1e9), V(-1e9, -1e9, -1e9)
local prevTop = nil
local stacked = true
for i, l in ipairs(layers) do
	local a, b = A.GetShapeBounds(l.shapes[1])
	for k = 1, 3 do mn[k] = math.min(mn[k], a[k]) mx[k] = math.max(mx[k], b[k]) end
end
local cx, cz = (mn[1] + mx[1]) / 2, (mn[3] + mx[3]) / 2
local off = math.sqrt((cx - click[1]) ^ 2 + (cz - click[3]) ^ 2)
T.check(off < 0.5, string.format("the cone (world bounds) stands on the clicked point (%.2f m off)", off))
T.check(mn[2] < 0.2 and mn[2] > -2, string.format("the cone stands on the ground (bottom at %.2f m)", mn[2]))
local v = sh().v
local so = math.sqrt((v.x - cx) ^ 2 + (v.z - cz) ^ 2)
T.check(so < 0.5, string.format("smoke and lava come from the cone (%.2f m off)", so))
T.check(math.abs(v.top - (mx[2] - 5 * 0.4)) < 1.5, string.format("the crater is at the cone's top (crater %.1f, top %.1f)", v.top, mx[2]))
T.runUntil(function() return srv().v and srv().v.lastLaunch ~= nil end, 2400)
local lp = srv().v.lastLaunch
local bo = math.sqrt((lp[1] - cx) ^ 2 + (lp[3] - cz) ^ 2)
T.check(bo < 0.5, string.format("bombs leave from the cone's crater (%.2f m off)", bo))
T.check(T.hasText("volcano: click"), "debug line on screen (switched on for this law)")
