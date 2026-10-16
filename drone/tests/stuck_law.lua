-- Drone stuck-test law. Independent review 16.10.2026: the "body does not follow our velocity"
-- test in server.fly fired during normal flight and switched the drone to the kinematic fallback,
-- where the crash check is skipped: holding Ctrl until it lands (wanted -4 m/s, the ground stops
-- it), the planned -0.6 m/s descent after the signal is lost (it even snapped back up), and W into
-- a wall. Now the test is skipped when lost, when the wanted motion goes down, and when a short ray
-- toward the wanted motion hits something. A body that really ignores velocity still gets the
-- fallback (tests/fallback_law.lua), and the fallback hands back to velocity flight when it works.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function me() return sh().d[1] end
local function mode() local d = srv().d[1] return d and d.mode or "velocity" end
local function movePlayer(v)
	H.P(1).pos = v
	local d = srv().d[1]
	if d and d.pin then d.pin.pos = { v[1], v[2], v[3] } end
end
local function launch()
	T.press("usetool"); T.frames(3)
	return me().body
end

H.addPlayer(1, V(0, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("drone")
T.frames(1)

-- 1) Ctrl held until the drone sits on the ground
local body = launch()
T.frames(60)
T.check(mode() == "velocity", "velocity mode after launch")
T.press("crouch"); for i = 1, 300 do T.hold("crouch"); T.frames(1) end
T.release("crouch"); T.frames(5)
T.check(H.bodies[body].pos[2] < 0.5, string.format("Ctrl brings it down to the ground (y %.2f)", H.bodies[body].pos[2]))
T.check(mode() == "velocity", "landing with Ctrl held keeps velocity flight (mode " .. mode() .. ")")
T.press("jump"); for i = 1, 90 do T.hold("jump"); T.frames(1) end
T.release("jump"); T.frames(60)

-- 2) signal lost: the planned slow descent is not "stuck"
movePlayer(V(0, 0, 200))
local maxUp, prev = 0, H.bodies[body].pos[2]
local y0 = prev
for i = 1, 240 do
	T.frames(1)
	local y = H.bodies[body].pos[2]
	if y - prev > maxUp then maxUp = y - prev end
	prev = y
end
T.check(me().lost, "signal is lost")
T.check(mode() == "velocity", "lost signal keeps velocity flight (mode " .. mode() .. ")")
T.check(maxUp < 0.05, string.format("no jump up while descending (biggest %.2f m in one frame)", maxUp))
T.check(H.bodies[body].pos[2] < y0 - 1, string.format("it descends (%.2f m)", H.bodies[body].pos[2] - y0))
movePlayer(V(0, 0, 0))
T.frames(10)
T.check(mode() == "velocity", "back in range: velocity flight")

-- 3) a crash still breaks it after all that (the crash check runs only in velocity mode)
local crash0 = me().crashN
H.bodies[body].vel = V(0, 30, 0)
T.frames(2)
T.check(me().crashN == crash0 + 1, "a hard hit still breaks it")
T.frames(5)

-- 4) W into a wall right in front of the drone
H.cubeCollision = true
body = launch()
T.frames(30)
local p = H.bodies[body].pos
H.addCubes(V(-3, 0, p[3] - 2.0), V(3, 5, p[3] - 1.5), 0.5, "masonry")
H.addStaticBox(V(-3, 0, p[3] - 2.0), V(3, 5, p[3] - 1.5), "masonry")
T.press("up"); for i = 1, 120 do T.hold("up"); T.frames(1) end
T.release("up"); T.frames(5)
T.check(H.bodies[body].pos[3] > p[3] - 2.0, "the wall stops it")
T.check(mode() == "velocity", "W into a wall keeps velocity flight (mode " .. mode() .. ")")
H.cubeCollision = false
H.cubes, H.cubeGrid, H.boxes = {}, {}, {}

-- 5) the fallback hands back to velocity flight once velocities work again
local d = srv().d[1]
H.ignoreBodyVelocity = true
movePlayer(V(0, 0, 0))
T.press("up"); for i = 1, 60 do T.hold("up"); T.frames(1) end
T.release("up"); T.frames(1)
T.check(mode() == "kinematic", "a body that ignores velocity goes kinematic")
T.frames(60 * 10)
T.check(mode() == "kinematic", "still kinematic while velocity is ignored")
H.ignoreBodyVelocity = false
local f = T.runUntil(function() return mode() == "velocity" end, 60 * 20)
T.check(f ~= nil, "back to velocity flight when velocity works again (" .. tostring(f) .. " frames)")
T.check(H.bodies[body].dynamic, "the body is dynamic again")
local yb = H.bodies[body].pos[2]
T.frames(120)
T.check(math.abs(H.bodies[body].pos[2] - yb) < 0.3 and mode() == "velocity", "hovers in velocity mode after the hand-back")
T.check(me().body == body, "no crash from the hand-back")
