-- Catapult law from Alexey's in-game check of 16.10 23:13 (bad3c72 code; the catapult did not change
-- after that): the catapult did not appear at all, the debug line read
--   catapult: none selected
--   refused: missing frame among 2 bodies / 7 shapes after 30 ticks
-- So the game created everything (2 bodies, all 7 parts), but the mod did not recognise the frame.
-- Since bad3c72 the parts were recognised by their size in voxels (GetShapeSize, sorted), and the
-- frame was expected as 26x32x38 - the size of its .vox file. The frame is the only part whose .vox
-- has empty columns (26 wide, filled x 2..23); the other six parts are filled to their edges and were
-- recognised. So the game reports the size of the filled voxels only (22x32x38), and the stand now
-- can do the same (H.spawnModel.trimEmpty).
-- The law: with the trimmed size every part is still recognised, the catapult is placed and ready,
-- every part within 5 cm of its designed place, no "refused".
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "field", physics = true, contentBounds = true, trimEmpty = true, boundsDelay = 1, shapesDelay = 1, dynamicDelay = 1, jointsAttach = false, com = true }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
H.reg["savegame.mod.debugline3"] = true
T.load("main.lua", "main")
T.init("main")
T.frames(2)

-- 0. the stand: the frame's size is that of its filled voxels, the others' that of their file
do
	local function one(file)
		local xml = "<prefab version='1.2.0'><group name='t' pos='0 0 0' rot='0 0 0'><body dynamic='false'><vox file='MOD/vox/" .. file .. ".vox' scale='3'/></body></group></prefab>"
		for _, e in ipairs(A.Spawn(xml, A.Transform(V(500, 0, 500)), true)) do if A.GetEntityType(e) == "shape" then return e end end
	end
	local f, b = one("frame"), one("bucket")
	local fx, fy, fz = A.GetShapeSize(f)
	local t = { fx, fy, fz }
	table.sort(t)
	T.check(t[1] == 22 and t[2] == 32 and t[3] == 38, string.format("stand: the frame reports its filled size 22x32x38 (%dx%dx%d)", t[1], t[2], t[3]))
	local bx, by, bz = A.GetShapeSize(b)
	t = { bx, by, bz }
	table.sort(t)
	T.check(t[1] == 5 and t[2] == 9 and t[3] == 9, string.format("stand: the bucket (filled to its edges) keeps 5x9x9 (%dx%dx%d)", t[1], t[2], t[3]))
	for h, bd in pairs(H.bodies) do if bd.valid and bd.spawnFrame and bd.pos[1] == 500 then A.Delete(h) end end
	T.frames(1)
end

-- 1. place a catapult
T.select("catapult")
T.frames(1)
T.press("usetool")
T.runUntil(function() local c = srv().cats[1] return c ~= nil and c.state == "ready" end, 400)
T.frames(5)
local c = srv().cats[1]
local reason = tostring(T.sharedOf().cp.reason)
T.check(c ~= nil and c.state == "ready", "the catapult is placed and ready (" .. reason .. ")")
T.check(not reason:find("refused", 1, true), "no refusal (" .. reason .. ")")
if not c then return end

-- 2. every part recognised and in place
local a = math.rad(55)
local u = V(0, -math.sin(a), math.cos(a))
local P = V(0, 9.6, 0)
local design = {
	frame = V(0, 4.8, 0), axle = P, hub = P,
	beam_long = A.VecAdd(P, A.VecScale(u, 0.9 + 4.5)), beam_short = A.VecSub(P, A.VecScale(u, 0.9 + 1.2)),
	bucket = A.VecAdd(A.VecAdd(P, A.VecScale(u, 10)), V(0, 0.3, 0)), weight = A.VecSub(P, A.VecScale(u, 3.4)),
}
local catT = A.Transform(c.base, A.QuatEuler(0, c.yaw, 0))
local shapes = { frame = c.frameShape, axle = c.axle, hub = c.hub, beam_long = c.beamLong, beam_short = c.beamShort, bucket = c.bucket, weight = c.weight }
for _, n in ipairs({ "frame", "axle", "hub", "beam_long", "beam_short", "bucket", "weight" }) do
	local sh = shapes[n] or 0
	local d = 99
	if sh ~= 0 and A.IsHandleValid(sh) then
		local mn, mx = A.GetShapeBounds(sh)
		d = A.VecLength(A.VecSub(A.VecLerp(mn, mx, 0.5), A.TransformToParentPoint(catT, design[n])))
	end
	T.check(d <= 0.05, string.format("%s recognised and within 5 cm of its designed place (%.2f m off)", n, d))
end
T.check(c.frameShape ~= c.axle and A.GetShapeBody(c.frameShape) == c.frame, "the frame shape is the frame body's other part, not the axle")
