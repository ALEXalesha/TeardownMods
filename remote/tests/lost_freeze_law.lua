-- Vehicle Remote lost-signal freeze law. Independent review 16.10.2026: during the 3 s of "signal
-- lost" before the car is released, DisablePlayerInput was not called, so the frozen body walked
-- off with the driving keys. Now the body stays frozen until the car is really released.
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

local before = H.calls.DisablePlayerInput or 0
H.P(1).pos = V(0, 0, 400)
T.frames(30)
T.check(me().lost and me().vehicle == car, "signal lost, car not released yet")
local n = (H.calls.DisablePlayerInput or 0) - before
T.check(n >= 29, "the body stays frozen while the signal is lost (" .. n .. " calls in 30 frames)")
T.frames(200)
T.check(me().vehicle == 0, "released after 3 s")
local after = H.calls.DisablePlayerInput or 0
T.frames(10)
T.check((H.calls.DisablePlayerInput or 0) == after, "no freeze after the release")
