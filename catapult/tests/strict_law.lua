-- Catapult law under the strict spawn model (second in-game report: "no surface is accepted" -
-- every placement refused). In the spawn tick nothing is ready: bounds are zero, GetBodyShapes is
-- empty, a dynamic body does not count as dynamic yet; bounds cover only filled voxels.
-- First report: "something weird is placed and cannot be removed": two
-- short wooden towers and the iron axle floating high above them, no arm, no bucket).
-- Spawn model of that screenshot: a spawned vox is centred on its pos (so a frame placed for a
-- bottom pivot sinks half into the ground and the axle floats above it), a joint only attaches
-- where it lies inside another spawned shape, and a dynamic body spawned into the ground is
-- thrown away. The machine must still come out as designed:
--   the frame stands on the ground, the axle sits on the frame's bearings at 9.6 m, the hinge is
--   attached, the arm hangs still in its rest pose with the bucket above the ground.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local A = H.API
local MODEL = "strict"

H.spawnModel = { pivot = "corner", physics = true, contentBounds = true, boundsDelay = 1, shapesDelay = 1, dynamicDelay = 1 }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
H.reg["savegame.mod.debugline"] = true   -- the debug line is off by default since 10.10; this law reads it
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("catapult")
T.frames(1)
T.press("usetool"); T.frames(2)
T.check(T.hasText("placing:"), "the debug line shows the placement stage while it waits")
T.frames(38)
local c = srv().cats[1]
T.check(c ~= nil, "[" .. MODEL .. "] the catapult is registered (refusal: " .. tostring(T.sharedOf().cp.reason) .. ")")
if c then
	local function bounds(sh) local mn, mx = A.GetShapeBounds(sh) return mn, mx end
	local frameShape = nil
	for _, sh in ipairs(A.GetBodyShapes(c.frame)) do
		local sx, sy, sz = A.GetShapeSize(sh)
		if sx == 26 and sy == 32 and sz == 38 then frameShape = sh end
	end
	T.check(frameShape ~= nil, "[" .. MODEL .. "] frame shape found")
	local fmn, fmx = bounds(frameShape)
	T.check(math.abs(fmn[2] - 0) < 0.3, string.format("[%s] the frame stands on the ground (bottom at %.2f m)", MODEL, fmn[2]))
	local amn, amx = bounds(c.axle)
	local ay = (amn[2] + amx[2]) / 2
	T.check(math.abs(ay - 9.6) < 0.3, string.format("[%s] the axle is at 9.6 m (%.2f m)", MODEL, ay))
	T.check(amn[2] < fmx[2] + 0.05, string.format("[%s] the axle sits on the frame, not above it (axle bottom %.2f, frame top %.2f)", MODEL, amn[2], fmx[2]))
	local fcx, fcz = (fmn[1] + fmx[1]) / 2, (fmn[3] + fmx[3]) / 2
	local acx, acz = (amn[1] + amx[1]) / 2, (amn[3] + amx[3]) / 2
	T.check(math.abs(fcx - acx) < 0.3 and math.abs(fcz - acz) < 0.3, string.format("[%s] the axle is centred on the frame (%.2f, %.2f m off)", MODEL, fcx - acx, fcz - acz))
	T.check(c.joint ~= 0 and not A.IsJointBroken(c.joint), "[" .. MODEL .. "] the hinge is attached")
	local ab = H.bodies[c.arm]
	local sp = math.sqrt(ab.vel[1] ^ 2 + ab.vel[2] ^ 2 + ab.vel[3] ^ 2)
	T.check(not ab.flung and sp < 1, string.format("[%s] the arm hangs still (%.1f m/s, flung %s)", MODEL, sp, tostring(ab.flung)))
	local bmn, bmx = bounds(c.bucket)
	T.check(bmn[2] > 0.3 and bmn[2] < 1.5, string.format("[%s] the bucket hangs above the ground (bottom at %.2f m)", MODEL, bmn[2]))
	T.check(c.state == "ready" and c.loaded == "boulder", "[" .. MODEL .. "] ready and loaded")
end
