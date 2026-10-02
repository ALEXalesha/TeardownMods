-- Harness scenarios for Trampoline Floor.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function callsOf(n) return H.calls[n] or 0 end

T.budget("SetBodyVelocity", 60)
T.budget("QueryRaycast", 24 + 4)
T.budget("QueryAabbBodies", 12)
T.budget("Spawn", 1)

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -30
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.trampoline ~= nil and H.P(1).enabled.trampoline, "tool registered and enabled")
T.select("trampoline")
T.frames(1)
T.check(T.hasText("place a pad"), "hint")

-- place a pad
T.press("usetool"); T.frames(2)
T.check(#sh().tp.pads == 1, "LMB places a pad")
T.check(T.soundsPlayed("place.ogg") == 1, "place sound")
local pad = sh().tp.pads[1]
T.check(pad.z < -1, "pad on the ground ahead")
T.check(srv().pads[1].membrane ~= 0, "membrane shape found for the dip animation")

-- player lands on the pad and bounces
H.P(1).pos = V(pad.x, 6, pad.z)
H.P(1).vel = V(0, 0, 0)
T.runUntil(function() return H.P(1).vel[2] > 3 end, 120)
local up = H.P(1).vel[2]
T.check(up > 6, string.format("player bounces off the pad (vy %.1f)", up))
T.frames(2)
T.check(T.soundsPlayed("boing") >= 1, "boing sound")
T.check(H.particles > 0, "squash dust")
T.check(callsOf("SetShapeLocalTransform") > 0 and (H.sideCalls.client.SetShapeLocalTransform or 0) == 0, "membrane dips (server-side animation)")

-- object dropped on the pad bounces
local crate = H.addBody { pos = V(pad.x + 0.5, 5, pad.z), mass = 20 }
local f = T.runUntil(function() return H.bodies[crate].vel[2] > 3 end, 200)
T.check(f ~= nil, "crate dropped on the pad bounces")
-- elsewhere: no bounce
H.P(1).pos = V(pad.x + 10, 6, pad.z)
H.P(1).vel = V(0, 0, 0)
local bounced = T.runUntil(function() return H.P(1).vel[2] > 3 end, 120)
T.check(bounced == nil, "plain ground does not bounce in pad mode")

-- global mode
T.press("r"); T.frames(2)
T.check(sh().tp.global == true and T.hasText("ON"), "R turns the whole ground bouncy")
H.P(1).pos = V(pad.x + 10, 6, pad.z)
H.P(1).vel = V(0, 0, 0)
bounced = T.runUntil(function() return H.P(1).vel[2] > 3 end, 120)
T.check(bounced ~= nil, "plain ground bounces in global mode")
local car = H.addBody { pos = V(8, 4, -3), mass = 1200, half = V(1, 0.8, 2) }
H.addVehicle(car, {})
T.frames(5)
f = T.runUntil(function() return H.bodies[car].vel[2] > 3 end, 200)
T.check(f ~= nil, "a vehicle bounces too")
T.press("r"); T.frames(2)
T.check(sh().tp.global == false, "R again turns it off")

-- restitution option
H.reg["savegame.mod.restitution"] = 0.5
H.P(1).pos = V(pad.x, 6, pad.z)
H.P(1).vel = V(0, 0, 0)
T.runUntil(function() return H.P(1).vel[2] > 2 end, 120)
local up2 = H.P(1).vel[2]
T.check(up2 < up * 0.75, string.format("lower restitution bounces lower (%.1f < %.1f)", up2, up))
H.reg["savegame.mod.restitution"] = 1.05

-- players off
H.reg["savegame.mod.players"] = false
H.P(1).pos = V(pad.x, 6, pad.z)
H.P(1).vel = V(0, 0, 0)
bounced = T.runUntil(function() return H.P(1).vel[2] > 2 end, 100)
T.check(bounced == nil, "players do not bounce when the option is off")
H.reg["savegame.mod.players"] = true
H.P(1).pos = V(0, 0, 0)

-- max 8 pads, remove with RMB
for i = 1, 9 do H.P(1).yaw = i * 35; T.press("usetool"); T.frames(1) end
T.frames(1)
T.check(#sh().tp.pads == 8, "at most 8 pads (" .. #sh().tp.pads .. ")")
T.check(T.hasText("Maximum 8"), "message when full")
T.press("grab"); T.frames(2)
T.check(#sh().tp.pads == 7, "RMB removes the nearest pad")
T.check(T.soundsPlayed("remove.ogg") == 1, "remove sound")

-- aiming at the sky fails
H.P(1).pitch = 40
T.press("usetool"); T.frames(2)
T.check(T.hasText("flat ground"), "cannot place a pad in the air")
H.P(1).pitch = -30

-- Russian
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("поставить батут"), "hint in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Trampoline Floor"), "options: title")
H.uiSliderSet[1] = 260
T.drawOptions(1)
T.check(math.abs(H.reg["savegame.mod.restitution"] - 1.5) < 1e-6, "options: restitution to 1.5")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(math.abs(H.reg["savegame.mod.restitution"] - 1.05) < 1e-6, "options: reset")
