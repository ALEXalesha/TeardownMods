-- Catapult law from Alexey's in-game screenshot of 16.10 (after d6fd1c5): "the ammo spawns crooked and
-- nothing works, as usual; F is the flashlight, by the way". The debug line read
--   pivot 0.50 0.50 0.74 | ... | hinge hub-nothing | arm 0.0 m/s, angle -51 | load 1/6 in bucket |
--   joint shapes 0 | parts off hub -0.0/0.0/0.1 beam_long -0.0/-1.5/1.1 beam_short -0.0/-0.2/0.2 ...
-- Causes:
--  1. the mod measured where the game puts a vox relative to its pos on a small probe (2x4x6) and
--     carried that fraction over to every part. The game's offset depends on the part's size: along
--     the model's MagicaVoxel y (the shape's z) the pivot lies floor(n/2)+1 voxels from the low side
--     (0.75 for 4 voxels, 0.63 for 8, 0.53 for 30). The 30-voxel beam came out 1.5 m low and 1.1 m back.
--     The stand now spawns voxes exactly like that (H.spawnModel.pivot = "field") and part 0 below
--     checks it against the screenshot's numbers;
--  2. the hinge from the spawn text held no shape at all (joint shapes 0, hub-nothing): nothing keeps
--     the arm on the axle (H.spawnModel.jointsAttach = false);
--  3. F is the game's flashlight key (data/input_settings.xml: flashlight = f; camera_view = c).
-- The law: every part within 5 cm of its designed place, the hub on the axle and staying there, the
-- debug line saying so, the load in the bucket and not sinking, F does not fire, Q fires and the arm
-- angle grows during the swing, all six crates are thrown.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "field", physics = true, contentBounds = true, boundsDelay = 1, shapesDelay = 1, dynamicDelay = 1, jointsAttach = false, com = true }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
H.reg["savegame.mod.debugline3"] = true
T.load("main.lua", "main")
T.init("main")
T.frames(2)

local function centre(sh) local mn, mx = A.GetShapeBounds(sh) return A.VecLerp(mn, mx, 0.5), mn, mx end

-- 0. the stand spawns like the game did on the screenshot (independent of the mod's code)
local function spawnOne(file, pos, rot)
	local xml = string.format("<prefab version='1.2.0'><group name='t' pos='0 0 0' rot='0 0 0'><body dynamic='false'><vox file='MOD/vox/%s.vox' scale='3' pos='%.4f %.4f %.4f' rot='%d 0 0'/></body></group></prefab>",
		file, pos[1], pos[2], pos[3], rot)
	for _, e in ipairs(A.Spawn(xml, A.Transform(V(500, 0, 500)), true)) do if A.GetEntityType(e) == "shape" then return e end end
end
do
	local axle = spawnOne("axle", V(0, 0, 0), 0)
	T.frames(2)
	local _, mn, mx = centre(axle)
	local f = {}
	for k = 1, 3 do f[k] = (({ 500, 0, 500 })[k] - mn[k]) / (mx[k] - mn[k]) end
	T.check(math.abs(f[1] - 0.5) < 0.02 and math.abs(f[2] - 0.5) < 0.02 and math.abs(f[3] - 0.74) < 0.02,
		string.format("stand: a 4-deep model reads pivot %.2f %.2f %.2f like the game's probe (0.50 0.50 0.74)", f[1], f[2], f[3]))
	-- the old placement (probe fraction carried over) reproduces the screenshot's offsets
	local probeF = V(0.5, 0.5, 0.74)
	for _, p in ipairs({ { "hub", { 6, 6, 6 }, 0, V(0, 0, 0.1) }, { "beam_long", { 2, 2, 30 }, 55, V(0, -1.5, 1.1) }, { "beam_short", { 2, 2, 8 }, 55, V(0, -0.2, 0.2) } }) do
		local sz = V(p[2][1] * 0.3, p[2][2] * 0.3, p[2][3] * 0.3)
		local pc = V((0.5 - probeF[1]) * sz[1], (0.5 - probeF[2]) * sz[2], (0.5 - probeF[3]) * sz[3])
		local want = V(0, 9.6, 0)
		local sh = spawnOne(p[1], A.VecSub(want, A.QuatRotateVec(A.QuatEuler(p[3], 0, 0), pc)), p[3])
		T.frames(2)
		local d = A.VecSub(centre(sh), A.VecAdd(V(500, 0, 500), want))
		T.check(A.VecLength(A.VecSub(d, p[4])) < 0.1, string.format("stand: old placement of %s is off %.1f/%.1f/%.1f like the screenshot (%.1f/%.1f/%.1f)",
			p[1], d[1], d[2], d[3], p[4][1], p[4][2], p[4][3]))
	end
	for h, b in pairs(H.bodies) do if b.valid and b.spawnFrame and b.pos[1] == 500 then A.Delete(h) end end
end

-- 1. place a catapult
T.select("catapult")
T.frames(1)
T.press("usetool")
T.runUntil(function() local c = srv().cats[1] return c ~= nil and c.state == "ready" end, 240)
T.frames(5)
local c = srv().cats[1]
T.check(c ~= nil and c.state == "ready", "the catapult is placed and ready (" .. tostring(T.sharedOf().cp.reason) .. ")")
if not c then return end

-- designed centres (catapult space), from the machine's dimensions, not from the mod's tables
local a = math.rad(55)
local u = V(0, -math.sin(a), math.cos(a))
local P = V(0, 9.6, 0)
local design = {
	frame = V(0, 4.8, 0), axle = P, hub = P,
	beam_long = A.VecAdd(P, A.VecScale(u, 0.9 + 4.5)), beam_short = A.VecSub(P, A.VecScale(u, 0.9 + 1.2)),
	bucket = A.VecAdd(A.VecAdd(P, A.VecScale(u, 10)), V(0, 0.3, 0)), weight = A.VecSub(P, A.VecScale(u, 3.4)),
}
local catT = A.Transform(c.base, A.QuatEuler(0, c.yaw, 0))
local frameShape = 0
for _, sh in ipairs(A.GetBodyShapes(c.frame)) do if sh ~= c.axle then frameShape = sh end end
local shapes = { frame = frameShape, axle = c.axle, hub = c.hub, beam_long = c.beamLong, beam_short = c.beamShort, bucket = c.bucket, weight = c.weight }
local function offsets()
	local out, worst = {}, 0
	for _, n in ipairs({ "frame", "axle", "hub", "beam_long", "beam_short", "bucket", "weight" }) do
		local sh = shapes[n] or 0
		local d = 99
		if sh ~= 0 and A.IsHandleValid(sh) then
			d = A.VecLength(A.VecSub(centre(sh), A.TransformToParentPoint(catT, design[n])))
		end
		out[n] = d
		worst = math.max(worst, d)
	end
	return out, worst
end
local off = offsets()
for _, n in ipairs({ "frame", "axle", "hub", "beam_long", "beam_short", "bucket", "weight" }) do
	T.check(off[n] <= 0.05, string.format("%s stands within 5 cm of its designed place (%.2f m off)", n, off[n]))
end

-- 2. the hinge: the hub sits on the axle's axis and stays there
local function hubOnAxle()
	if (c.hub or 0) == 0 or not A.IsHandleValid(c.hub) then return 99 end
	local ac = centre(c.axle)
	local axis = A.QuatRotateVec(A.GetBodyTransform(c.frame).rot, V(1, 0, 0))
	local d = A.VecSub(centre(c.hub), ac)
	return A.VecLength(A.VecSub(d, A.VecScale(axis, A.VecDot(d, axis))))
end
T.check(hubOnAxle() <= 0.05, string.format("the hub is on the axle (%.2f m from its axis)", hubOnAxle()))
T.frames(60)
T.check(hubOnAxle() <= 0.05, string.format("1 s later the arm still hangs on the axle (%.2f m)", hubOnAxle()))
local _, worst = offsets()
T.check(worst <= 0.05, string.format("1 s later every part is still in place (worst %.2f m)", worst))

-- 3. the debug line says the same
local function debugText()
	local t = {}
	for _, s in ipairs(T.texts()) do if tostring(s):find("catapult", 1, true) or tostring(s):find("parts off", 1, true) or tostring(s):find("load ", 1, true) or tostring(s):find("hinge", 1, true) then t[#t + 1] = tostring(s) end end
	return table.concat(t, " | ")
end
local line = debugText()
local parts = line:match("parts off([^|]*)")
local maxOff = -1
if parts then for num in parts:gmatch("%-?%d+%.%d+") do maxOff = math.max(maxOff, math.abs(tonumber(num))) end end
T.check(parts ~= nil and maxOff >= 0 and maxOff <= 0.05, string.format("debug line: parts off all within 0.05 m (max %.2f): %s", maxOff, tostring(parts)))
T.check(not line:find("joint shapes 0", 1, true) and not line:find("hub-nothing", 1, true) and line:find("hinge[^|]*hub%-axle") ~= nil,
	"debug line: the hinge holds the hub on the axle (" .. (line:match("hinge[^|]*") or "no hinge field") .. ")")
T.check(line:find("load 1/1 in bucket", 1, true) ~= nil, "debug line: load 1/1 in bucket (" .. (line:match("load %d+/%d+ in bucket") or "none") .. ")")

-- 4. crates: six of them, inside the bucket, not sinking into it
for _, b in ipairs(srv().contents(c)) do A.Delete(b) end
T.frames(2)
T.press("4"); T.frames(30)
local function crateCheck(tag)
	local bmn, bmx = select(2, centre(c.bucket))
	local floorY = bmn[2] + 0.3
	local list = srv().contents(c)
	local inside = 0
	local pos = {}
	for _, b in ipairs(list) do
		local mn, mx = V(1e9, 1e9, 1e9), V(-1e9, -1e9, -1e9)
		for _, sh in ipairs(A.GetBodyShapes(b)) do
			local smn, smx = A.GetShapeBounds(sh)
			for k = 1, 3 do mn[k] = math.min(mn[k], smn[k]) mx[k] = math.max(mx[k], smx[k]) end
		end
		local ok = mn[2] >= floorY - 0.05 and mn[2] <= floorY + 1.1
			and mn[1] >= bmn[1] + 0.25 and mx[1] <= bmx[1] - 0.25 and mn[3] >= bmn[3] + 0.25 and mx[3] <= bmx[3] - 0.25
		if ok then inside = inside + 1 end
		pos[#pos + 1] = { b = b, p = A.VecCopy(H.bodies[b].pos) }
	end
	T.check(#list == 6 and inside == 6, string.format("%s: six crates, all inside the bucket above its floor (%d found, %d inside)", tag, #list, inside))
	return pos
end
local pos = crateCheck("loaded")
T.frames(60)
crateCheck("1 s later")
local moved = 0
for _, x in ipairs(pos) do moved = math.max(moved, A.VecLength(A.VecSub(H.bodies[x.b].pos, x.p))) end
T.check(moved < 0.1, string.format("the crates stay where they lie (moved up to %.2f m in 1 s)", moved))
line = debugText()
T.check(line:find("load 6/6 in bucket", 1, true) ~= nil, "debug line: load 6/6 in bucket (" .. (line:match("load %d+/%d+ in bucket") or "none") .. ")")

-- 5. F is the game's flashlight: it must not fire; Q fires
local fire0 = T.sharedOf().cp.fireN
T.press("f"); T.frames(10)
T.check(c.state == "ready" and T.sharedOf().cp.fireN == fire0, "F (the game's flashlight) does not fire")
T.check(T.hasText("Q: fire"), "the hint names Q as the fire key")
local crates = {}
for _, b in ipairs(srv().contents(c)) do crates[#crates + 1] = b end
local psi0 = srv().psi(c)
T.press("q"); T.frames(1)
T.check(c.state == "swing", "Q fires")
local prev, grows, maxPsi = psi0, true, psi0
local lineAngles = {}
for i = 1, 240 do
	if c.state ~= "swing" then break end
	T.frames(1)
	local psi = srv().psi(c)
	if psi < prev - 0.5 then grows = false end
	prev = psi
	maxPsi = math.max(maxPsi, psi)
	local ang = debugText():match("angle ([%-%+]?%d+)")
	if ang then lineAngles[#lineAngles + 1] = tonumber(ang) end
end
T.check(grows and maxPsi > psi0 + 60, string.format("the arm angle grows during the swing (%.0f -> %.0f degrees)", psi0, maxPsi))
T.check(#lineAngles >= 2 and lineAngles[#lineAngles] > lineAngles[1] + 30, string.format("debug line: angle grows while firing (%s -> %s)", tostring(lineAngles[1]), tostring(lineAngles[#lineAngles])))
T.frames(2)
local thrown = 0
-- the mod throws fresh, awake copies of its load (in-game 17.10 the sleeping ones hung in the air)
for i, b in ipairs(crates) do local rep = srv().replaced or {} while rep[b] do b = rep[b] end crates[i] = b end
for _, b in ipairs(crates) do if A.IsHandleValid(b) and A.VecLength(H.bodies[b].vel) > 10 then thrown = thrown + 1 end end
T.check(thrown == 6, "all six crates are thrown (" .. thrown .. ")")
line = debugText()
T.check(line:find("last shot", 1, true) ~= nil, "debug line: the last shot is reported (" .. (line:match("last shot[^|]*") or "none") .. ")")
T.runUntil(function() return c.state == "ready" end, 600)
T.frames(10)
T.check(hubOnAxle() <= 0.05, string.format("after the shot the arm is back on the axle (%.2f m)", hubOnAxle()))
local _, worst2 = offsets()
T.check(worst2 <= 0.05, string.format("after the shot the arm is back at rest (worst part %.2f m off)", worst2))

-- an ammo key replaces the auto-loaded boulder (in-game the bucket "was not empty" and the key did nothing)
T.check(#srv().contents(c) == 6, "the crates are reloaded after the shot (" .. #srv().contents(c) .. ")")
T.press("1"); T.frames(30)
T.check(#srv().contents(c) == 1, "1 replaces the crates with a boulder (" .. #srv().contents(c) .. " bodies in the bucket)")
T.press("4"); T.frames(30)
T.check(#srv().contents(c) == 6, "4 replaces the boulder with six crates (" .. #srv().contents(c) .. ")")

-- 6. C is the game's camera key: it must not turn the machine
local yaw0 = c.yaw
for i = 1, 30 do T.hold("c"); T.frames(1) end
T.release("c"); T.frames(4)
T.check(math.abs(c.yaw - yaw0) < 0.01, "C (the game's camera view) does not turn the catapult")
