-- Harness scenarios for the Portal Gun.
local function V(x, y, z) return { x, y, z } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function pr() return sh().pairs[1] end
local function callsOf(n) return H.calls[n] or 0 end

T.budget("QueryAabbBodies", 4)
T.budget("SetBodyTransform", 6)
T.budget("DrawSprite", 12)
T.budget("QueryRaycast", 40)

H.addPlayer(1, V(0, 0, 0))
local wallA = H.addStaticBox(V(-6, 0, -10.4), V(6, 5, -10), "masonry")     -- facing +z
local wallB = H.addStaticBox(V(10, 0, -16), V(10.4, 5, 4), "masonry")      -- facing -x
local small = H.addStaticBox(V(-20, 1, -20.2), V(-19.6, 1.4, -20), "wood")  -- too small for a portal
local box = H.addBody { pos = V(-3, 0.25, -4), mass = 20 }

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.portalgun ~= nil and H.P(1).enabled.portalgun, "tool registered and enabled")
T.select("portalgun")
T.frames(1)
T.check(T.hasText("blue portal"), "HUD hint")

-- blue on the wall ahead
T.press("usetool"); T.frames(2)
local b = pr()[1]
T.check(b.active and math.abs(b.z + 9.98) < 0.05 and b.nz > 0.99, "LMB places the blue portal on the wall")
T.check(T.soundsPlayed("fire_blue.ogg") == 1 and T.soundsPlayed("open.ogg") == 1, "fire and open sounds")
T.check(callsOf("DrawSprite") > 0, "portal swirl and rim drawn")

-- orange on the right wall
H.P(1).yaw = -90
T.frames(1)
T.press("grab"); T.frames(2)
local o = pr()[2]
T.check(o.active and math.abs(o.x - 9.98) < 0.05 and o.nx < -0.99, "RMB places the orange portal on the right wall")
T.check(T.soundsPlayed("fire_orange.ogg") == 1, "orange fire sound")

-- failures: sky, too small surface, on top of the other portal
H.P(1).pitch = 60
T.press("usetool"); T.frames(2)
T.check(pr().failN == 1 and T.soundsPlayed("fail.ogg") == 1, "firing at the sky fizzles")
H.P(1).pitch = 0
H.P(1).pos = V(-19.8, -0.5, -18)
H.P(1).yaw = 0
T.press("usetool"); T.frames(2)
T.check(pr().failN == 2, "surface too small for a portal fizzles")
H.P(1).pos = V(0, 0, 0)
H.P(1).yaw = -90
T.press("usetool"); T.frames(2)
T.check(pr().failN == 3 and math.abs(pr()[1].z + 9.98) < 0.05, "cannot place a portal on top of the other one")

-- the player walks into the blue portal and comes out of the orange one
H.P(1).yaw = 0
H.P(1).pos = V(0, 0, -9.65)
H.P(1).vel = V(0, 0, -3)
T.frames(1)
local p = H.P(1)
T.check(p.pos[1] > 8.5 and p.pos[1] < 10, string.format("player exits the orange portal (x=%.2f)", p.pos[1]))
T.check(p.vel[1] < -1.5, string.format("velocity rotated out of the orange portal (vx=%.2f)", p.vel[1]))
T.check(math.abs(p.yaw - 90) < 5 or math.abs(p.yaw + 270) < 5, string.format("view turned to face out of the exit (yaw %.0f)", p.yaw))
T.frames(2)
T.check(T.soundsPlayed("pass.ogg") >= 1, "pass-through sound")
local px = p.pos[1]
T.frames(5)
T.check(p.pos[1] < 9.5, "no ping-pong right after the exit")

-- a thrown crate goes through
local crate = H.addBody { pos = V(0.2, 1.7, -8.5), mass = 20, vel = V(0, 0, -8) }
H.gravity = V(0, 0, 0)
T.runUntil(function() return H.bodies[crate].pos[1] > 8 end, 60)
H.gravity = V(0, -10, 0)
local cb = H.bodies[crate]
T.check(cb.pos[1] > 8.5, string.format("crate comes out of the orange portal (x=%.2f)", cb.pos[1]))
T.check(cb.vel[1] < -5, string.format("crate keeps its speed, rotated (vx=%.2f)", cb.vel[1]))

-- a body too big for the portal stays
local big = H.addBody { pos = V(0, 1.7, -8.0), mass = 100, half = V(1.5, 1.5, 0.5), vel = V(0, 0, -2) }
H.gravity = V(0, 0, 0)
T.frames(30)
H.gravity = V(0, -10, 0)
T.check(H.bodies[big].pos[1] < 5, "object larger than the portal does not pass")

-- floor portal: the player steps onto it and drops out of the wall portal
H.API.Delete(big)
H.P(1).pos = V(-3, 0, 2)
H.P(1).yaw = 0
H.P(1).pitch = -60
T.press("usetool"); T.frames(2)
b = pr()[1]
T.check(b.active and b.ny > 0.99, "blue portal on the floor")
H.P(1).pitch = 0
T.frames(30)   -- let the teleport cooldown run out
H.P(1).pos = V(b.x, 0, b.z)
H.P(1).vel = V(0, -1, 0)
T.frames(1)
T.check(H.P(1).pos[1] > 8.5, "standing on the floor portal drops the player out of the wall portal")

-- the wall under the orange portal is destroyed: it closes
local closes = pr().closeN
H.shapes[wallB].valid = false
T.frames(20)
T.check(not pr()[2].active and pr().closeN > closes, "portal closes when its surface is destroyed")
T.frames(2)
T.check(T.soundsPlayed("close.ogg") >= 1, "close sound")
H.shapes[wallB].valid = true

-- R closes both
H.P(1).pos = V(0, 0, 0)
H.P(1).yaw = -90
T.press("grab"); T.frames(2)
T.check(pr()[1].active and pr()[2].active, "both portals placed again")
T.press("r"); T.frames(2)
T.check(not pr()[1].active and not pr()[2].active, "R closes both portals")

-- objects disabled in options
H.reg["savegame.mod.bodies"] = false
H.P(1).yaw = 0
T.press("usetool"); T.frames(2)
H.P(1).yaw = -90
T.press("grab"); T.frames(2)
local c2 = H.addBody { pos = V(0.2, 1.7, -8.5), mass = 20, vel = V(0, 0, -8) }
H.gravity = V(0, 0, 0)
T.frames(30)
H.gravity = V(0, -10, 0)
T.check(H.bodies[c2].pos[1] < 5, "objects do not pass when the option is off")
H.reg["savegame.mod.bodies"] = true

-- Russian HUD
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("синий портал"), "HUD in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Portal Gun"), "options: title")
H.uiClicks["Normal"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.size"] == 3, "options: size Normal -> Large")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.size"] == 2 and H.reg["savegame.mod.range"] == 100, "options: reset")
