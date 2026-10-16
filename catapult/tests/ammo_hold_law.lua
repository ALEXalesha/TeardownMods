-- Catapult law from Alexey's in-game report of 11.10 (after 4a8ce13): "half of the ammo in it is not
-- shown, it does not fire".
-- Cause: the load is held in the bucket by ConstrainPosition towards a point taken in the very tick
-- the ammo was spawned, from GetBodyTransform and GetBodyCenterOfMass of the just-spawned bodies. A
-- just-spawned body's data is not ready in that tick (bounds, shapes and dynamics were already seen
-- late in the game, 04.10); with the centre of mass read as the body origin, every tick after pulls
-- the real centre of each crate 0.45 m down to that origin: the crates sink into the bucket floor and
-- into each other - half of them out of sight - and drift out of the place the throw takes them from.
-- The law: with the centre of mass not ready in the spawn tick (H.spawnModel.com) and the game's
-- pivot of a vox (the centre of its bottom face, as the game's door and lid prefabs show), the six
-- crates and a boulder stay where they were put, and a shot throws all of them.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "bottomcenter", physics = true, com = true }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("catapult")
T.frames(1)
T.press("usetool"); T.frames(60)
local c = srv().cats[1]
T.check(c ~= nil and c.state == "ready", "the catapult is placed and ready (" .. tostring(T.sharedOf().cp.reason) .. ")")
if c then
	local function settled(kind, n)
		for _, b in ipairs(srv().contents(c)) do A.Delete(b) end
		T.frames(2)
		T.press(kind); T.frames(5)              -- spawned, measured and laid into the bucket
		local bodies = {}
		for _, g in ipairs(c.groups or {}) do for _, b in ipairs(g.bodies) do bodies[#bodies + 1] = { b = b, p = A.VecCopy(H.bodies[b].pos) } end end
		T.check(#bodies == n, string.format("key %s loads %d bodies (%d)", kind, n, #bodies))
		T.frames(60)
		local worst = 0
		for _, x in ipairs(bodies) do worst = math.max(worst, A.VecLength(A.VecSub(H.bodies[x.b].pos, x.p))) end
		T.check(worst < 0.15, string.format("key %s: the load stays where it was put in the bucket (moved up to %.2f m in 1 s)", kind, worst))
		return bodies
	end
	settled("1", 1)
	local crates = settled("4", 6)
	T.check(#srv().contents(c) == 6, "all six crates are in the bucket")
	T.press("q"); T.frames(1)
	T.runUntil(function() return c.state ~= "swing" end, 240)
	T.frames(2)
	local thrown = 0
	for _, x in ipairs(crates) do if A.VecLength(H.bodies[x.b].vel) > 10 then thrown = thrown + 1 end end
	T.check(thrown == 6, "the shot throws all six crates (" .. thrown .. ")")
end
