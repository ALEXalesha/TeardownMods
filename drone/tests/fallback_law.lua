-- Drone fallback law (in-game report after the first fix: "it still does not fly").
-- Failure model: the engine does not apply our SetBodyVelocity to the drone at all. The drone must
-- notice within about half a second of held input, switch to kinematic flight (moved with
-- SetBodyTransform each tick) and still fly: W for 2 s moves it >= 10 m along the view, Space
-- climbs, it does not fall without input. The on-screen debug line (on by default) shows the
-- mode and which keys the client and the server saw.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function me() return sh().d[1] end
local function copy(v) return { v[1], v[2], v[3] } end

H.addPlayer(1, V(0, 0, 0))
H.ignoreBodyVelocity = true
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("drone")
T.frames(1)
T.press("usetool"); T.frames(3)
local body = me().body
T.check(body ~= 0 and me().piloting, "drone launched")
T.check(T.hasText("drone: mode velocity"), "debug line on by default, velocity mode first")

local launchY = H.bodies[body].pos[2]
T.frames(60)
T.check(math.abs(H.bodies[body].pos[2] - launchY) < 0.6, string.format("with nothing pressed it does not sink away (%.2f m)", H.bodies[body].pos[2] - launchY))
local p0 = copy(H.bodies[body].pos)
T.press("up")
for i = 1, 120 do T.hold("up"); T.frames(1) end
T.check(T.hasText("mode kinematic"), "kinematic flight shown in the debug line")
T.check(T.hasText("client W") and T.hasText("server W"), "debug line shows W seen by client and server")
T.release("up"); T.frames(1)
local p1 = H.bodies[body].pos
T.check(p0[3] - p1[3] >= 10, string.format("W for 2 s flies %.1f m forward even when velocities are ignored", p0[3] - p1[3]))
T.check(math.abs(p1[2] - p0[2]) < 1.5, string.format("altitude kept (%.2f m)", p1[2] - p0[2]))
local y0 = p1[2]
T.press("jump")
for i = 1, 60 do T.hold("jump"); T.frames(1) end
T.release("jump"); T.frames(30)
T.check(H.bodies[body].pos[2] - y0 > 2, "Space climbs in kinematic mode")
local y1 = H.bodies[body].pos[2]
T.frames(120)
T.check(math.abs(H.bodies[body].pos[2] - y1) < 0.2, "hovers without input in kinematic mode")
T.check(me().body == body, "no crash from the mode switch")
-- the setting hides the debug line
H.reg["savegame.mod.debug"] = false
T.frames(2)
T.check(not T.hasText("drone: mode"), "debug line can be switched off")
