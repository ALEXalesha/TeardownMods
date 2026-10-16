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
T.press("usetool"); T.frames(60)
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
	-- since 16.10 the arm turns by script (no spawned joint): the hub sits around the axle, so the arm's
	-- shapes must not collide with the frame's, or the arm would jam on the axle
	local function band(a, b)
		local r, bit = 0, 1
		while a > 0 and b > 0 do
			if a % 2 == 1 and b % 2 == 1 then r = r + bit end
			a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
		end
		return r
	end
	local function collide(a, b)
		local la, ma = A.GetShapeCollisionFilter(a)
		local lb, mb = A.GetShapeCollisionFilter(b)
		return band(la, mb) ~= 0 and band(lb, ma) ~= 0
	end
	local jams = 0
	for _, sa in ipairs(A.GetBodyShapes(c.arm)) do
		for _, sf in ipairs(A.GetBodyShapes(c.frame)) do if collide(sa, sf) then jams = jams + 1 end end
	end
	T.check(jams == 0, "no arm shape collides with the frame or the axle (" .. jams .. " pairs)")
	T.check(srv().hubOffAxle(c) <= 0.05, string.format("the hub sits on the axle's axis (%.2f m)", srv().hubOffAxle(c)))
end
