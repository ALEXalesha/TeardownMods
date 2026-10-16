-- Tool switch law (16.10.2026). Driving by remote went on after the player took another tool, so the
-- remote's Q (let go) and V (chase camera) also worked as the Mover's rotate / roll or the catapult's
-- fire / angle. Now putting the remote away lets the car go, like the Camera Drone ends its flight.
-- Every key of every mod: _shared/tdlib/keymap.py.
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
T.select("mover")
T.frames(3)
T.check(me().vehicle == 0, "taking another tool lets the car go")
local f0 = H.vehicles[car].driven.frame
T.frames(5)
T.check(H.vehicles[car].driven.frame == f0, "no more DriveVehicle after the tool switch")
T.release("up")
