-- Catapult laws, part 2: impacts, ammo, controls, limits.
--  * a boulder hitting a wood wall and a brick wall at >= 30 m/s breaks a hole in each;
--  * crates, barrel and car are loaded and thrown; the barrel explodes where it lands;
--  * E on the machine fires it; Z/X turn it; V/B set the angle; a destroyed hub stops it;
--  * no runaway spawning: at most 4 catapults, at most 24 mod ammo bodies, 3 cars;
--  * R removes every catapult and all its ammo; per-frame work stays bounded.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end

T.budget("Spawn", 7)                -- a volley of 6 crates is thrown as 6 fresh, awake copies in one update
T.budget("MakeHole", 8)
T.budget("SpawnParticle", 40)
T.budget("QueryRaycast", 80)
T.budget("ConstrainPosition", 30)

H.spawnModel = { pivot = "center", physics = true }
H.cubeCollision = true
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("catapult")
T.frames(1)

-- two catapults side by side, a wooden wall in front of one, a brick wall in front of the other
T.press("usetool"); T.frames(60)
H.P(1).pos = V(30, 0, 0)
T.press("usetool"); T.frames(60)
H.P(1).pos = V(15, 0, 20)
local c1, c2 = srv().cats[1], srv().cats[2]
T.check(c1 and c2 and c1.state == "ready" and c2.state == "ready", "two catapults ready")
H.addCubes(V(-5, 0, -137), V(5, 30, -136), 1, "wood")
H.addCubes(V(25, 0, -137), V(35, 30, -136), 1, "brick")
local function removed(x0, x1)
	local n = 0
	for _, cube in ipairs(H.cubes) do if not cube.alive and cube.c[1] > x0 and cube.c[1] < x1 then n = n + 1 end end
	return n
end
for _, c in ipairs({ c1, c2 }) do c.power = 0.5 end
srv().sync()
T.frames(2)
local imp0 = #srv().impacts
srv().fire(c1)
srv().fire(c2)
T.runUntil(function() return #srv().impacts >= imp0 + 2 end, 900)
local hits = {}
for i = imp0 + 1, #srv().impacts do hits[#hits + 1] = srv().impacts[i] end
local fast = 0
for _, h in ipairs(hits) do if h.speed >= 30 and h.pos[3] < -100 then fast = fast + 1 end end
T.check(fast >= 2, string.format("both boulders hit their walls at >= 30 m/s (%s)", table.concat((function() local t = {} for _, h in ipairs(hits) do t[#t + 1] = string.format("%.0f m/s at z %.0f", h.speed, h.pos[3]) end return t end)(), ", ")))
local wood, brick = removed(-6, 6), removed(24, 36)
T.check(wood >= 10, "the wooden wall is broken through: " .. wood .. " m2 of 1 m blocks (need >= 10)")
T.check(brick >= 5, "the brick wall is broken through: " .. brick .. " m2 of 1 m blocks (need >= 5)")
T.runUntil(function() return c1.state == "ready" and c2.state == "ready" end, 600)
T.frames(3)

-- controls on the selected (nearest) catapult
H.P(1).pos = V(0, 0, 0)
T.frames(2)
local yaw0 = c1.yaw
T.press("z")
for i = 1, 60 do T.hold("z"); T.frames(1) end
T.release("z"); T.frames(4)
T.check(c1.yaw - yaw0 > 20, string.format("Z turns the catapult (%.0f degrees in 1 s)", c1.yaw - yaw0))
local fr = H.bodies[c1.frame].rot
local fwd = H.API.QuatRotateVec(fr, V(0, 0, -1))
T.check(math.abs(math.deg(math.atan2(-fwd[1], -fwd[3])) - c1.yaw) < 1, "the frame really turned")
T.press("x")
for i = 1, 60 do T.hold("x"); T.frames(1) end
T.release("x"); T.frames(4)
T.check(math.abs(c1.yaw - yaw0) < 3, string.format("X turns it back (%.0f degrees off)", c1.yaw - yaw0))
T.check(srv().hubOffAxle(c1) <= 0.05, "after turning the arm still hangs on the axle")
T.press("v"); T.frames(3)
T.check(c1.angle == 40, "V lowers the angle (" .. c1.angle .. ")")
T.press("b"); T.frames(3)
T.check(c1.angle == 45, "B raises it again")

-- crates: all six are thrown together
local function emptyBucket(c)
	for _, b in ipairs(srv().contents(c)) do H.API.Delete(b) end
	T.frames(2)
end
emptyBucket(c1)
T.press("4"); T.frames(3)
local crates = srv().contents(c1)
T.check(#crates == 6, "4 loads a pile of 6 crates (" .. #crates .. ")")
T.press("q")
T.runUntil(function() return c1.state == "reset" end, 120)
T.check(c1.lastLaunch and c1.lastLaunch.held == 6, "all six crates are thrown (" .. (c1.lastLaunch and c1.lastLaunch.held or 0) .. ")")
T.runUntil(function() return c1.state == "ready" end, 600)
T.frames(3)

-- barrel: explodes where it lands
emptyBucket(c1)
T.press("2"); T.frames(3)
local ex0 = #H.explosions
T.press("q")
T.runUntil(function() return #H.explosions > ex0 end, 900)
T.check(#H.explosions > ex0, "the explosive barrel explodes where it lands")
T.runUntil(function() return c1.state == "ready" end, 600)
T.frames(3)

-- car: the game's small car prefab (or the mod's car body) is loaded and thrown
emptyBucket(c1)
T.press("3"); T.frames(3)
local cars = 0
for _, a in ipairs(srv().ammo) do if a.kind == "car" and H.API.IsHandleValid(a.body) then cars = cars + 1 end end
T.check(cars >= 1, "3 loads a car (" .. cars .. " bodies)")
T.press("q")
T.runUntil(function() return c1.state == "reset" end, 120)
T.check(c1.lastLaunch and c1.lastLaunch.held >= 1, "the car is thrown")
T.runUntil(function() return c1.state == "ready" end, 600)
T.frames(3)

-- E (the game's interact) on the machine does nothing: in-game 17.10 "the shot on E does not work, remove it"
H.P(1).interactBody = c1.arm
local fire0 = sh().cp.fireN
T.press("interact"); T.frames(2)
T.check(sh().cp.fireN == fire0, "E on the catapult does not fire it (only Q does)")
H.P(1).interactBody = nil
T.runUntil(function() return c1.state == "ready" end, 600)
T.frames(3)

-- no runaway spawning: six volleys of crates (36 bodies) leave at most 24 mod bodies alive
for v = 1, 6 do
	emptyBucket(c1)
	T.press("4"); T.frames(3)
	srv().fire(c1)
	T.runUntil(function() return c1.state == "ready" end, 900)
	T.frames(3)
end
local alive6 = 0
for _, a in ipairs(srv().ammo) do if H.API.IsHandleValid(a.body) then alive6 = alive6 + 1 end end
T.check(alive6 <= 24, "after six crate volleys at most 24 mod bodies are alive (" .. alive6 .. ")")
for i = 1, 40 do T.press(tostring((i % 4) + 1)); T.frames(1) end
for i = 1, 30 do T.press("grab"); T.frames(1) end
local alive, carsAlive = 0, 0
for _, a in ipairs(srv().ammo) do if H.API.IsHandleValid(a.body) then alive = alive + 1 if a.kind == "car" then carsAlive = carsAlive + 1 end end end
T.check(alive <= 24 and carsAlive <= 3, string.format("mod ammo stays bounded (%d bodies, %d car bodies)", alive, carsAlive))
for i = 1, 6 do H.P(1).pos = V(-60 - 30 * i, 0, 0); T.press("usetool"); T.frames(6) end
T.check(#srv().cats == 4, "at most 4 catapults (" .. #srv().cats .. ")")
T.check(T.hasText("At most 4"), "message when full")

-- a destroyed hub (the arm's hinge part) stops the machine
H.API.Delete(c2.hub)
T.frames(2)
T.check(c2.state == "broken", "a destroyed hub marks the catapult broken")
local f0 = sh().cp.fireN
srv().fire(c2)
T.check(sh().cp.fireN == f0, "a broken catapult does not fire")

-- R only puts the catapult away, Delete removes everything (18.10: "removing them all should be on another key")
H.P(1).pos = V(0, 0, 0)
local nCats = #srv().cats
T.press("r"); T.frames(3)
T.check(H.P(1).tool ~= "catapult" and #srv().cats == nCats, string.format("R puts the catapult away (tool %s), the catapults stay (%d)", H.P(1).tool, #srv().cats))
T.select("catapult"); T.frames(2)
local bodies = {}
for _, c in ipairs(srv().cats) do bodies[#bodies + 1] = c.frame bodies[#bodies + 1] = c.arm end
for _, a in ipairs(srv().ammo) do bodies[#bodies + 1] = a.body end
T.press("delete"); T.frames(3)
local left = 0
for _, b in ipairs(bodies) do if H.API.IsHandleValid(b) then left = left + 1 end end
T.check(#srv().cats == 0 and left == 0, "Delete removes every catapult and all mod ammo (" .. left .. " left)")
T.check(T.hasText("Catapults removed"), "message after removal")

-- Russian, options
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("поставить катапульту"), "hint in Russian")
H.reg["options.language"] = 0
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Catapult"), "options: title")
H.uiClicks["Boulder"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.ammo"] == 2, "options: start ammo")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.ammo"] == 1 and H.reg["savegame.mod.falldamage"] == false, "options: reset")
