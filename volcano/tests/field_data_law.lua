-- Volcano law from Alexey's in-game debug line on build a195f2f:
--   click -59.0 5.4 -107.6 | cone body -58.5 10.1 -107.7 | cone bounds centre -59.0 5.7 -107.6 (39.8 x 1.6 m) | off 0.00 m
-- What the game does there: the vox pivot is the model's CENTRE (body origin 4.7 m above the
-- click = half the 10.4 m model above the sunk bottom), and GetShapeBounds covers only the filled
-- voxels (a layer model is full cone size but holds one 1.6 m band). The cone came out 1.6 m tall:
-- all seven bands at the same height. Same spawn model here, on a raised ground like in that map.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "center", contentBounds = true, physics = true }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -4
H.reg["savegame.mod.debugline"] = true   -- the debug line is off by default since 10.10; this law reads it
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("volcano")
T.frames(1)
T.press("usetool"); T.frames(2)
T.runUntil(function() return sh().v.phase == "rumble" end, 900)
local layers = srv().v.layers
local bottoms, mn, mx = {}, V(1e9, 1e9, 1e9), V(-1e9, -1e9, -1e9)
for i, l in ipairs(layers) do
	local a, b = A.GetShapeBounds(l.shapes[1])
	bottoms[i] = a[2]
	for k = 1, 3 do mn[k] = math.min(mn[k], a[k]) mx[k] = math.max(mx[k], b[k]) end
end
local height = mx[2] - mn[2]
T.check(height >= 9.5, string.format("the cone is %.1f m high (designed 10.4, need >= 9.5)", height))
local rise = (bottoms[7] or 0) - (bottoms[1] or 0)
T.check(math.abs(rise - 6 * 4 * 0.4) < 0.3, string.format("the top layer starts %.1f m above the bottom layer (designed 9.6)", rise))
local bt = H.bodies[layers[1].body].pos
T.check(math.abs((bt[2] - mn[2]) - 5.2) < 0.3, string.format("body origin %.1f m above the cone bottom (the game's centre pivot: 5.2)", bt[2] - mn[2]))
T.check(T.hasText("cone height"), "the debug line shows the cone height")
