-- Catapult law from Alexey's in-game report of 11.10 (after 4a8ce13): "it spawns, but does not
-- fire, does not move, works strangely".
-- Cause found in the layout: the 14.4 m beam was one piece running straight through the axle. So
--   1. the hinge point lay inside three shapes at once - the hub and the beam (both on the arm) and
--      the axle (on the frame). The game's own prefabs put a joint where its shape meets exactly one
--      other shape (door blade / frame, dumpster lid / bin); with two candidates the game may join
--      the hub to the beam of its own body, and then nothing holds the arm on the axle;
--   2. the dynamic beam overlapped the static axle for every angle of the arm. The joint switches off
--      collisions only between the two shapes it joins (hub and axle); beam against axle is a
--      permanent collision, and the arm jams on the axle - the motor cannot turn it.
-- The law: no arm shape other than the hub comes near the hinge axis (closer than the axle's half
-- diagonal plus a margin), and the hub is the only arm shape the joint sits in. The distance of a
-- point of the arm from the axis does not change while the arm turns, so one pose checks all.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "corner", physics = true, contentBounds = true, boundsDelay = 1, shapesDelay = 1, dynamicDelay = 1 }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("catapult")
T.frames(1)
T.press("usetool"); T.frames(40)
local c = srv().cats[1]
T.check(c ~= nil, "the catapult is assembled (" .. tostring(T.sharedOf().cp.reason) .. ")")
if c then
	local amn, amx = A.GetShapeBounds(c.axle)
	local P = A.VecLerp(amn, amx, 0.5)
	local axis = A.QuatRotateVec(A.GetBodyTransform(c.frame).rot, A.Vec(1, 0, 0))
	local ax, ay, az = A.GetShapeSize(c.axle)
	local t = { ax, ay, az } table.sort(t)
	local half = t[1] * 0.3 * 0.5
	local clear = half * math.sqrt(2) + 0.05            -- the axle's corners while the arm turns
	local hub = c.hub or (H.joints[c.joint] and H.joints[c.joint].shapes[1]) or 0
	T.check(hub ~= 0 and A.GetShapeBody(hub) == c.arm, "the hub is found on the arm")
	local function dist(p)
		local d = A.VecSub(p, P)
		return A.VecLength(A.VecSub(d, A.VecScale(axis, A.VecDot(d, axis))))
	end
	for _, sh in ipairs(A.GetBodyShapes(c.arm)) do
		if sh ~= hub then
			local sx, sy, sz, vs = A.GetShapeSize(sh)
			local wt = A.GetShapeWorldTransform(sh)
			local best = 1e9
			local nx, ny, nz = math.ceil(sx * vs / 0.1), math.ceil(sy * vs / 0.1), math.ceil(sz * vs / 0.1)
			for i = 0, nx do for j = 0, ny do for k = 0, nz do
				local p = A.TransformToParentPoint(wt, A.Vec(sx * vs * i / nx, sy * vs * j / ny, sz * vs * k / nz))
				best = math.min(best, dist(p))
			end end end
			T.check(best > clear, string.format("arm shape %dx%dx%d stays clear of the axle (closest %.2f m to the hinge axis, axle reaches %.2f m)", sx, sy, sz, best, clear))
		end
	end
	-- the hinge sits in the hub and in the axle only
	local jt = H.joints[c.joint]
	if jt then
		local b = H.bodies[jt.body]
		local jp = A.TransformToParentTransform(A.Transform(b.pos, b.rot), jt.localT).pos
		-- (the frame model's box holds the axle area too, but has no voxels there: arm shapes + axle only)
		local inside = {}
		local cand = { c.axle }
		for _, sh in ipairs(A.GetBodyShapes(c.arm)) do cand[#cand + 1] = sh end
		for _, sh in ipairs(cand) do
			local sx, sy, sz, vs = A.GetShapeSize(sh)
			local lp = A.TransformToLocalPoint(A.GetShapeWorldTransform(sh), jp)
			if lp[1] > 0 and lp[1] < sx * vs and lp[2] > 0 and lp[2] < sy * vs and lp[3] > 0 and lp[3] < sz * vs then inside[#inside + 1] = sh end
		end
		local ok = #inside == 2
		for _, sh in ipairs(inside) do if sh ~= hub and sh ~= c.axle then ok = false end end
		T.check(ok, "the hinge point lies in exactly the hub and the axle (" .. #inside .. " shapes of the arm and the axle)")
	else
		T.check(false, "the catapult has its hinge")
	end
end
