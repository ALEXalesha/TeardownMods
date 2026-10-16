-- Vehicle Remote dead-driver law. Independent review 16.10.2026: a player who died (health 0) while
-- driving by remote kept driving the car. Now death releases the car.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function me() return sh().rc[1] end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -8
local carBody = H.addBody { pos = V(0, 0.8, -10), mass = 1300, half = V(1, 0.8, 2) }
local car = H.addVehicle(carBody, {})
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("rcremote")
T.frames(1)
T.press("usetool"); T.frames(2)
T.check(me().vehicle == car, "driving the car")
T.press("up"); for i = 1, 5 do T.hold("up"); T.frames(1) end

H.P(1).health = 0
H.P(1).canUseTool = false
T.frames(3)
T.check(me().vehicle == 0, "a dead player lets go of the car")
local f0 = H.vehicles[car].driven.frame
T.frames(5)
T.check(H.vehicles[car].driven.frame == f0, "no more DriveVehicle for the dead player")
H.camera = nil
T.frames(1)
T.check(H.camera == nil, "no chase camera")
T.release("up")
