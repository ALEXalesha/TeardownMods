-- Harness scenarios for the Camera Drone.
local function V(x, y, z) return { x, y, z } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function srv() return T.env().server end
local function cli() return T.cenv().client end
local function sh() return T.sharedOf() end
local function me() return sh().d[1] end
local function callsOf(n) return H.calls[n] or 0 end
local function holdKey(k, n) for i = 1, n do T.hold(k); T.frames(1) end end

T.budget("ApplyBodyImpulse", 2 * 4)
T.budget("Spawn", 3)
T.budget("QueryRaycast", 8)
T.budget("ServerCall", 3)

H.addPlayer(1, V(0, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.drone ~= nil and H.P(1).enabled.drone, "tool registered and enabled")
T.select("drone")
T.frames(1)
T.check(T.hasText("launch the drone"), "hint on foot")

-- launch
T.press("usetool"); T.frames(2)
local body = me().body
T.check(body ~= 0 and H.bodies[body] and H.bodies[body].dynamic, "LMB launches a dynamic drone body")
T.check(me().piloting, "player is piloting")
T.check(T.soundsPlayed("deploy.ogg") == 1, "deploy sound")
T.frames(2)
T.check(H.camera ~= nil and H.cameraFov == 90, "camera moved to the drone (fov 90)")
T.check(callsOf("DisablePlayerInput") > 0, "player body frozen while flying")
T.check(T.hasText("BAT") and T.hasText("SIGNAL"), "telemetry HUD")
T.check(T.loopFrames("hum.ogg") > 0, "rotor hum plays")

-- hover with no input
local y0 = H.bodies[body].pos[2]
T.frames(120)
T.check(math.abs(H.bodies[body].pos[2] - y0) < 0.5, string.format("hovers in place (dy %.2f)", H.bodies[body].pos[2] - y0))

-- fly forward and up
local p0 = { H.bodies[body].pos[1], H.bodies[body].pos[2], H.bodies[body].pos[3] }
T.press("up"); holdKey("up", 120); T.release("up"); T.frames(1)
T.check(p0[3] - H.bodies[body].pos[3] > 3, string.format("W flies forward (%.1f m)", p0[3] - H.bodies[body].pos[3]))
local y1 = H.bodies[body].pos[2]
T.press("jump"); holdKey("jump", 60); T.release("jump"); T.frames(1)
T.check(H.bodies[body].pos[2] - y1 > 1.5, "Space climbs")
T.frames(60)

-- mouse look turns the drone heading
H.P(1).values = { camerax = -0.5 }
T.frames(3)
H.P(1).values = {}
T.frames(3)
T.check(math.abs(srv().d[1].yaw) > 20, string.format("mouse turns the heading (yaw %.0f)", srv().d[1].yaw))

-- target marker drawn
T.check(callsOf("DrawLine") > 20, "target marker drawn")

-- own bomb (grenade mod absent)
local spawns = callsOf("Spawn")
T.press("usetool"); T.frames(2)
T.check(callsOf("Spawn") == spawns + 1 and me().bombs == 2, "LMB drops a built-in bomb")
T.check(T.soundsPlayed("drop.ogg") == 1, "drop sound")
local ex0 = #H.explosions
T.runUntil(function() return #H.explosions > ex0 end, 400)
T.check(#H.explosions > ex0, "bomb explodes on impact")

-- Singularity Grenade through the registry
H.reg["level.singularity_grenade.available"] = true
H.reg["level.singularity_grenade.reqcount"] = 4
T.press("usetool"); T.frames(2)
T.check(H.reg["level.singularity_grenade.reqcount"] == 5 and H.reg["level.singularity_grenade.req.5.y"] ~= nil, "drop hands a Singularity Grenade request to the other mod")
T.check(me().bombs == 1, "bomb count decreases")
T.press("usetool"); T.frames(2)
T.press("usetool"); T.frames(2)
T.check(me().bombs == 0 and H.reg["level.singularity_grenade.reqcount"] == 6, "no drop when out of bombs")
H.reg["level.singularity_grenade.available"] = false

-- photo mode hides the HUD
T.press("p"); T.frames(2)
T.check(not T.hasText("BAT"), "photo mode hides the HUD")
T.press("p"); T.frames(1)

-- Q returns the view, drone hovers, LMB takes control again
T.press("q"); T.frames(2)
T.check(not me().piloting, "Q returns to the body")
H.camera = nil
T.frames(2)
T.check(H.camera == nil, "camera is the player's again")
T.check(H.bodies[body].valid, "drone keeps hovering")
T.press("usetool"); T.frames(2)
T.check(me().piloting and me().body == body, "LMB on foot takes control of the same drone")

-- range: weak signal, static, lost link
H.P(1).pos = V(0, 0, 130)
T.frames(5)
T.check(me().weak > 0.2, string.format("signal weakens near the edge (%.2f)", me().weak))
T.check(callsOf("UiSoundLoop") > 0, "static sound")
H.P(1).pos = V(0, 0, 200)
T.frames(5)
T.check(me().lost, "signal lost past the range")
T.check(T.hasText("SIGNAL LOST"), "HUD says SIGNAL LOST")
local yl = H.bodies[body].pos[2]
T.frames(120)
T.check(H.bodies[body].pos[2] < yl - 0.5, "lost drone descends")
H.P(1).pos = V(0, 0, 0)
T.frames(5)

-- battery empty -> falls -> crash
T.press("jump"); holdKey("jump", 120); T.release("jump")
srv().d[1].battery = 0.0001
local crash0 = me().crashN
local f = T.runUntil(function() return me().crashN > crash0 end, 400)
T.check(f ~= nil, "empty battery: drone falls and breaks (" .. tostring(f) .. " frames)")
T.check(not H.bodies[body].valid, "drone body removed")
T.frames(2)
T.check(T.soundsPlayed("crash.ogg") == 1, "crash sound")
T.check(not me().piloting and srv().d[1] == nil, "control returns to the player after the crash")
T.frames(2)

-- relaunch, pack up near, refuse when far
T.press("usetool"); T.frames(2)
local b2 = me().body
T.check(b2 ~= 0 and me().bombs == 3, "relaunch refills bombs")
T.press("q"); T.frames(2)
T.press("r"); T.frames(2)
T.check(me().body == 0 and not H.bodies[b2].valid, "R packs the drone up when close")
T.check(T.soundsPlayed("pack.ogg") == 1, "pack sound")
T.press("usetool"); T.frames(2)
local b3 = me().body
T.press("up"); holdKey("up", 120); T.release("up")
T.press("q"); T.frames(2)
T.press("r"); T.frames(2)
T.check(me().body == b3 and H.bodies[b3].valid, "R does nothing when the drone is far")

-- variable frame rate flight
T.press("usetool"); T.frames(1, 1 / 30)
local yv = H.bodies[b3].pos[2]
T.frames(60, 1 / 30)
T.check(math.abs(H.bodies[b3].pos[2] - yv) < 0.6, "hovers at 30 fps")
T.frames(120, 1 / 144)
T.check(math.abs(H.bodies[b3].pos[2] - yv) < 0.8, "hovers at 144 fps")

-- Russian HUD
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("СИГНАЛ"), "HUD in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Camera Drone"), "options: title")
H.uiClicks["Limited"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.battery"] == false, "options: unlimited battery")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.battery"] == true and H.reg["savegame.mod.range"] == 150, "options: reset")
