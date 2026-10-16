-- Portal Gun vehicle law. Independent review 16.10.2026: a player driving a vehicle into a portal
-- was teleported out of the car (the player check ignored GetPlayerVehicle), leaving the car
-- behind. Now players sitting in a vehicle are skipped; a player on foot still passes.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function pr() return sh().pairs[1] end

H.addPlayer(1, V(0, 0, 0))
H.addStaticBox(V(-6, 0, -10.4), V(6, 5, -10), "masonry")
H.addStaticBox(V(10, 0, -16), V(10.4, 5, 4), "masonry")
local carBody = H.addBody { pos = V(0, 0.8, -7), mass = 1300, half = V(1, 0.8, 2) }
local car = H.addVehicle(carBody, {})
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("portalgun")
T.frames(1)
T.press("usetool"); T.frames(2)
H.P(1).yaw = -90
T.frames(1)
T.press("grab"); T.frames(2)
T.check(pr()[1].active and pr()[2].active, "both portals open")

-- the player sits in a car that drives into the blue portal
H.P(1).yaw = 0
H.P(1).vehicle = car
H.P(1).canUseTool = false
H.P(1).pos = V(0, 0, -9.65)
H.P(1).vel = V(0, 0, -3)
local passed = pr().passN
T.frames(1)
T.check(pr().passN == passed and H.P(1).pos[1] < 1, string.format("a player in a vehicle is not teleported out of it (x %.2f, passN %d -> %d)", H.P(1).pos[1], passed, pr().passN))

-- the same spot on foot still teleports
H.P(1).vehicle = 0
H.P(1).canUseTool = true
H.P(1).pos = V(0, 0, -9.65)
H.P(1).vel = V(0, 0, -3)
T.frames(1)
T.check(pr().passN == passed + 1 and H.P(1).pos[1] > 5, string.format("on foot the player passes (x %.2f)", H.P(1).pos[1]))
