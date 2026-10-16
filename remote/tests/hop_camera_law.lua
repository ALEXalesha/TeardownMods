-- Vehicle Remote hop-aim law. Independent review 16.10.2026: while driving with the chase camera,
-- LMB on another car aimed from the frozen body's eye, not from the camera the player looks
-- through, so the car in the middle of the screen was not the one it hopped to. Now the hop ray
-- starts at the chase camera (the client sends it, the server checks that it starts near the
-- driven car and casts it itself); the white outline marks the same target. The chase camera looks
-- down at its own car, so a car further away sits above the middle of the picture: a car within
-- 10 degrees of the view counts when the middle ray finds none.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function cli() return T.cenv().client end
local function me() return sh().rc[1] end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -8
local carBody = H.addBody { pos = V(0, 0.8, -10), mass = 1300, half = V(1, 0.8, 2) }
local car = H.addVehicle(carBody, {})
local car2Body = H.addBody { pos = V(-12, 0.8, -6), mass = 1300, half = V(1, 0.8, 2) }
local car2 = H.addVehicle(car2Body, {})
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("rcremote")
T.frames(1)
T.press("usetool"); T.frames(2)
T.check(me().vehicle == car, "driving car 1")

-- turn the chase camera with the mouse until it looks at car 2 (the body still faces car 1)
local best = -2
for i = 1, 400 do
	H.P(1).values = { camerax = 0.02 }
	T.frames(1)
	local cam = H.camera
	local fw = H.API.QuatRotateVec(cam.rot, { 0, 0, -1 })
	local d = { H.bodies[car2Body].pos[1] - cam.pos[1], 0, H.bodies[car2Body].pos[3] - cam.pos[3] }
	local dl = math.sqrt(d[1] ^ 2 + d[3] ^ 2)
	local fl = math.sqrt(fw[1] ^ 2 + fw[3] ^ 2)
	local a = (fw[1] * d[1] + fw[3] * d[3]) / dl / fl
	if a > best then best = a end
	if a > 0.995 then break end
end
H.P(1).values = {}
T.frames(1)
T.check(best > 0.995, string.format("the chase camera faces car 2 (alignment %.3f)", best))
T.check(cli().aim == car2, "the outline marks car 2, the one in the camera")
T.press("usetool"); T.frames(2)
T.check(me().vehicle == car2, "LMB hops to the car in the chase camera")

-- the server checks where the ray starts: not from far away from the driven car
local far = V(200, 1, 200)
srv().hop(1, far[1], far[2], far[3], -1, 0, -1)
T.check(me().vehicle == car2, "a hop ray that does not start at the chase camera is refused")
