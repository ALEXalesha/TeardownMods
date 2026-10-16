-- Vehicle Remote hop-input law. Independent review 16.10.2026: hopping to another car with W held
-- left the new car idle: the server starts every car with no input and the client only sends keys
-- when they change. Now the client sends its keys again whenever the controlled car changes.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
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
T.press("up"); for i = 1, 10 do T.hold("up"); T.frames(1) end
T.check(H.vehicles[car].driven.drive == 1, "W drives car 1")

-- hop with W still held (the chase camera finds nothing, so the body's eye aims; turn the body)
H.P(1).yaw = 63; H.P(1).pitch = -4
T.frames(1)
T.hold("up"); T.press("usetool"); T.frames(2)
for i = 1, 20 do T.hold("up"); T.frames(1) end
local dv = H.vehicles[car2].driven
T.check(me().vehicle == car2, "hopped to car 2")
T.check(dv and dv.drive == 1, "W still held drives the new car (drive " .. tostring(dv and dv.drive) .. ")")
T.release("up"); T.frames(2)
T.check(H.vehicles[car2].driven.drive == 0, "releasing W stops it")
