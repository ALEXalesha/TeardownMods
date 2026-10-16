-- Drone dead-pilot law. Independent review 16.10.2026: a player who died while piloting (health 0)
-- kept the drone camera and the server kept pinning the dead body in place. Now death ends piloting
-- and drops the pin.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function me() return sh().d[1] end

H.addPlayer(1, V(0, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("drone")
T.frames(1)
T.press("usetool"); T.frames(3)
local body = me().body
T.frames(30)
T.check(me().piloting and srv().d[1].pin ~= nil, "piloting, body pinned")

H.P(1).health = 0
H.P(1).canUseTool = false
T.frames(3)
T.check(not me().piloting, "a dead player stops piloting")
T.check(srv().d[1] and srv().d[1].pin == nil, "the pin is dropped")
H.camera = nil
T.frames(1)
T.check(H.camera == nil, "no drone camera for the dead player")
local calls = H.calls.SetPlayerTransform or 0
H.P(1).pos = V(4, 0, 0)
T.frames(10)
T.check((H.calls.SetPlayerTransform or 0) == calls and H.P(1).pos[1] > 3, "the dead body is not held in place")
T.check(H.bodies[body].valid, "the drone stays")

-- respawned: control comes back with LMB
H.P(1).health = 1
H.P(1).canUseTool = true
T.frames(1)
T.press("usetool"); T.frames(2)
T.check(me().piloting and me().body == body, "after respawn LMB takes control again")
