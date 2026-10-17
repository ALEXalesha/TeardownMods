-- Copy law from Alexey's in-game wish of 17.10: "choose an object by some key and it appears in the
-- catapult's bucket, a car or a pole, duplicated there".
-- The law: T with the tool in hand copies what the player aims at into the bucket of the nearest ready
-- catapult - a loose object whole (every shape of its body, a vehicle with its wheel bodies), a part of
-- the level only the shape that was hit; the original stays where it was; the copy is thrown by Q like
-- any load and the next load is a copy again, until an ammo key (1-4) brings the usual loads back.
-- Too big (over 8 m) or nothing aimed at: a plain message, the bucket keeps its load.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function sh() return T.env().shared end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("catapult")
T.frames(1)
T.press("usetool"); T.frames(90)
local c = srv().cats[1]
T.check(c ~= nil and c.state == "ready", "a catapult is placed and ready")
if not c then return end
T.runUntil(function() local g = c.groups and c.groups[1] return g and g.placed end, 120)

-- a "car": a hull with two shapes and a wheel body of its own, right in front of the player's eyes
local hull = H.addBody({ pos = V(0, 1.2, -4), half = V(0.9, 0.6, 1.8), mass = 800, shapes = 2 })
local wheel = H.addBody({ pos = V(0.9, 0.6, -3), half = V(0.3, 0.3, 0.3), mass = 20 })
H.addVehicle(hull, { wheel })
H.P(1).pos = V(0, 0, 0)
H.P(1).pitch = -10
local before = #srv().ammo
T.press("t"); T.frames(3)
T.check(c.ammo == 5, "T makes the copy the catapult's load (ammo 5, shown as \"Copy\")")
local g = c.groups and c.groups[1]
local copy = g and g.bodies and g.bodies[1]
T.check(copy ~= nil and copy ~= hull and copy ~= wheel, "the copy is a new body")
local cb = copy and H.bodies[copy]
local live = 0
if cb then for _, s in ipairs(cb.shapes) do if H.shapes[s] and H.shapes[s].valid then live = live + 1 end end end
T.check(live == 3, "the copy holds every shape of the car: hull 2 + wheel 1, and not the seed box it was spawned with (" .. live .. ")")
T.check(H.bodies[hull].valid and H.bodies[wheel].valid and math.abs(H.bodies[hull].pos[3] + 4) < 0.5, "the original car stays where it was")
T.runUntil(function() return g.placed end, 120)
if cb then
	local floor = srv().bucketFloor(c)
	T.check(math.abs(cb.pos[1] - floor[1]) < 2 and math.abs(cb.pos[3] - floor[3]) < 2, "the copy lies in the bucket")
end

-- thrown by Q like any load, and the next load is a copy again
H.P(1).pitch = 0
T.press("q"); T.frames(1)
T.runUntil(function() return c.state == "reset" end, 120)
T.check(c.lastLaunch and c.lastLaunch.held >= 1, "Q throws the copy")
T.runUntil(function() return c.state == "ready" end, 600)
T.frames(3)
local g2 = c.groups and c.groups[1]
local copy2 = g2 and g2.bodies and g2.bodies[1]
T.check(c.ammo == 5 and copy2 ~= nil and copy2 ~= copy and copy2 ~= hull, "the next load is a new copy of the same car")

-- an ammo key brings the usual loads back
T.press("1"); T.frames(3)
T.check(c.ammo == 1 and c.copyFrom == nil, "1 loads a boulder again and forgets the copy")
T.runUntil(function() local gg = c.groups and c.groups[1] return gg and gg.placed end, 120)

-- too big: refused with a message, the boulder stays
local big = H.addBody({ pos = V(-30, 6, -4), half = V(6, 6, 6), mass = 5000 })
H.P(1).pos = V(-30, 0, 8)
H.P(1).pitch = 0
local mn0 = sh().cp.mn
T.press("t"); T.frames(3)
T.check(sh().cp.mn ~= mn0 and sh().cp.msg == "copy_big", "a 12 m object is refused: \"too big\" (" .. tostring(sh().cp.msg) .. ")")
T.check(c.ammo == 1, "the bucket keeps its boulder")

-- nothing aimed at (the sky): a message, nothing changes
H.P(1).pos = V(0, 0, 0)
H.P(1).pitch = 80
mn0 = sh().cp.mn
T.press("t"); T.frames(3)
T.check(sh().cp.mn ~= mn0 and sh().cp.msg == "copy_none", "aiming at the sky says \"aim at an object\" (" .. tostring(sh().cp.msg) .. ")")
T.check(c.ammo == 1, "the load stays a boulder")
