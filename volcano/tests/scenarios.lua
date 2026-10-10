-- Harness scenarios for the Volcano.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
local function callsOf(n) return H.calls[n] or 0 end

T.budget("Spawn", 2)
T.budget("MakeHole", 40 + 6 + 1)
T.budget("SpawnFire", 6)
T.budget("SpawnParticle", 50)
T.budget("SetBodyTransform", 7)
T.budget("ApplyBodyImpulse", 20)
T.budget("Explosion", 6)

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -20
local crates = {}
for i = 1, 20 do crates[i] = H.addBody { pos = V(-10 + i, 0.25, -40 + (i % 4)), mass = 30 } end

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.volcano ~= nil and H.P(1).enabled.volcano, "tool registered and enabled")
T.select("volcano")
T.frames(1)
T.check(T.hasText("raise a volcano"), "hint")

-- aiming at the sky does nothing
H.P(1).pitch = 30
T.press("usetool"); T.frames(2)
T.check(sh().v.phase == "idle" and T.hasText("Aim at the ground"), "aim at the ground message")
H.P(1).pitch = -20

-- place: grows layer by layer
T.press("usetool"); T.frames(2)
local v = sh().v
T.check(v.phase == "grow", "LMB starts growing a volcano")
T.check(T.soundsPlayed("place.ogg") == 1, "place sound")
local R = v.R
local dist = math.sqrt(v.x * v.x + v.z * v.z)
T.check(dist >= R + 3.9, string.format("cone kept away from the player (%.1f m, radius %.1f)", dist, R))
T.frames(45)
local mid = sh().v.layers
T.check(mid >= 1 and mid < 7, "layers appear one after another (" .. mid .. " after 0.8 s)")
T.check(T.loopFrames("grind.ogg") > 30, "grinding sound while it grows")
T.runUntil(function() return sh().v.phase == "rumble" end, 600)
T.check(sh().v.layers == 7, "all seven layers raised")
-- in-game 10.10 ("works great, the yellow debug line can be removed"): the debug line is a hidden
-- option now - off by default, on only when "Debug line" is switched on in the mod's options
T.frames(1)
T.check(not T.hasText("volcano: click") and not T.hasText("cone height"), "no debug line on screen by default")
H.reg["savegame.mod.debugline"] = true
T.frames(1)
T.check(T.hasText("volcano: click"), "debug line shown when switched on in the options")
H.reg["savegame.mod.debugline"] = nil
-- an old save from the builds with the line on by default ("Reset to defaults" wrote debug = true)
H.reg["savegame.mod.debug"] = true
T.frames(1)
T.check(not T.hasText("volcano: click"), "an old saved debug = true does not bring the line back")
H.reg["savegame.mod.debug"] = nil
local layers = srv().v.layers
local static, risen = true, true
for i = 1, #layers do
	local b = H.bodies[layers[i].body]
	if b.dynamic then static = false end
	if math.abs(layers[i].t - 0.7) > 1e-6 then risen = false end
end
T.check(static and risen, "layers are static and fully risen")
local finalY = H.bodies[layers[7].body].pos[2]
T.check(math.abs(H.bodies[layers[1].body].pos[2] - finalY) < 1e-6, "all layers end in the same frame (aligned)")
T.check((H.sideCalls.client.SetBodyTransform or 0) == 0 and (H.sideCalls.client.Spawn or 0) == 0, "only the server builds the cone")

-- rumble: tremors, smoke, glow up
T.frames(60)
T.check(callsOf("ApplyBodyImpulse") > 0, "tremors shake loose objects")
T.check(H.particles > 0, "smoke")
T.check(callsOf("SetShapeEmissiveScale") > 0 and (H.sideCalls.client.SetShapeEmissiveScale or 0) == 0, "lava glow set by the server")
T.check(T.hasText("Rumbling"), "phase shown")

-- eruption: bombs fly, land, punch craters, start fires
T.runUntil(function() return sh().v.phase == "erupt" end, 1200)
T.check(sh().v.phase == "erupt", "eruption starts")
local holes0 = #H.holes
T.frames(600)
T.check(sh().v.launchN >= 15, "lava bombs launched (" .. sh().v.launchN .. ")")
T.check(T.soundsPlayed("launch.ogg") >= 10, "launch sounds")
T.check(#H.holes - holes0 >= 5, "bombs punch craters (" .. (#H.holes - holes0) .. ")")
T.check(H.fires >= 5, "bombs start fires (" .. H.fires .. ")")
T.check(T.soundsPlayed("impact.ogg") >= 5, "impact sounds")
T.check(T.loopFrames("roar.ogg") > 300, "eruption roar")
T.check(#srv().bombs <= 30 + 24, "live bombs capped")
T.check(#H.lights > 0, "crater light")
T.check(T.hasText("final blast now"), "RMB hint during the eruption")

-- the final blast at the end of the eruption
local ex0 = #H.explosions
T.runUntil(function() return sh().v.phase == "cool" end, 3600)
T.check(sh().v.phase == "cool", "final blast at the end of the eruption")
T.check(#H.explosions - ex0 >= 6, "a ring of explosions (" .. (#H.explosions - ex0) .. ")")
local summit = false
for _, h in ipairs(H.holes) do if h.r2 > 1.5 and h.pos[2] > sh().v.top - 0.5 then summit = true end end
T.check(summit, "the summit is blown off (a big hole at the crater)")
T.frames(2)
T.check(T.soundsPlayed("blast.ogg") == 1, "blast sound")
T.check(T.cenv().client.flash > 0.3, "flash")

-- cooling, bombs vanish, idle; the cone stays
T.runUntil(function() return sh().v.phase == "idle" end, 1500)
T.check(sh().v.phase == "idle", "cools down to idle")
T.frames(1300)
T.check(#srv().bombs == 0, "cooled bombs are cleared after 20 s")
T.check(H.bodies[layers[1].body].valid, "the dead cone stays")

-- RMB: blast right away
H.P(1).yaw = 90
T.press("usetool"); T.frames(2)
T.runUntil(function() return sh().v.phase == "rumble" end, 600)
T.frames(10)
T.press("grab"); T.frames(2)
T.check(sh().v.phase == "cool", "RMB triggers the final blast at once")
T.runUntil(function() return sh().v.phase == "idle" end, 1500)

-- R removes the cones
T.press("r"); T.frames(3)
local any = false
for _, l in ipairs(layers) do if H.bodies[l.body].valid then any = true end end
T.check(not any and T.hasText("Cones removed"), "R removes the cones")

-- second volcano while one is running: refused
T.press("usetool"); T.frames(2)
T.press("usetool"); T.frames(2)
T.check(T.hasText("One volcano at a time"), "one volcano at a time")
T.press("grab")
T.runUntil(function() return sh().v.phase == "rumble" end, 600)
T.press("grab"); T.frames(2)
T.runUntil(function() return sh().v.phase == "idle" end, 1500)

-- options: weak and short, no fire
H.reg["savegame.mod.fire"] = false
H.reg["savegame.mod.strength"] = 0.5
H.reg["savegame.mod.size"] = 1
local f0 = H.fires
H.P(1).yaw = 200
T.press("usetool"); T.frames(2)
T.check(math.abs(sh().v.R - 73 * 0.3 * 0.5) < 1e-6, "size option: small cone")
T.runUntil(function() return sh().v.phase == "cool" end, 6000)
T.check(H.fires == f0, "no fires when switched off")
H.reg["savegame.mod.fire"] = true
H.reg["savegame.mod.strength"] = 1
H.reg["savegame.mod.size"] = 2

-- Russian
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("Остывает") or T.hasText("Гудит") or T.hasText("ИЗВЕРЖЕНИЕ") or T.hasText("убрать конусы"), "HUD in Russian")
H.reg["options.language"] = 0

-- options screen
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Volcano"), "options: title")
H.uiClicks["Medium (29 m)"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.size"] == 3, "options: large size")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.size"] == 2 and H.reg["savegame.mod.duration"] == 45, "options: reset")
