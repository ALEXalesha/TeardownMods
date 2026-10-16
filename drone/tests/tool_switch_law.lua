-- Drone tool-switch law. Independent review 16.10.2026: switching to another tool while piloting
-- kept the drone camera and HUD, and LMB with the other tool still dropped a bomb. Now piloting
-- ends as soon as the player holds another tool; the drone stays where it is.
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
T.check(me().piloting and H.camera ~= nil, "piloting, camera on the drone")

T.select("sledge"); T.frames(2)
T.check(not me().piloting, "another tool ends piloting")
T.check(H.camera == nil, "the camera is the player's again")
T.check(not T.hasText("BAT"), "no drone HUD")
local b0 = me().bombs
T.press("usetool"); T.frames(2)
T.check(me().bombs == b0, string.format("LMB with another tool drops no bomb (bombs %d -> %d)", b0, me().bombs))
T.check(H.bodies[body].valid and me().body == body, "the drone stays")
-- a drop request that still arrives for a pilot holding another tool is refused
srv().d[1].piloting = true
srv().drop(1)
T.check(me().bombs == b0, "server refuses a drop while another tool is held")
srv().d[1].piloting = false

T.select("drone"); T.frames(1)
T.press("usetool"); T.frames(2)
T.check(me().piloting and me().body == body, "LMB with the drone tool takes control again")
