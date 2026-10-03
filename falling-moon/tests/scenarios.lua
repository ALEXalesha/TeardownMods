-- Harness scenarios for the Falling Moon.
local function V(x, y, z) return { x, y, z } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function callsOf(n) return H.calls[n] or 0 end

T.budget("ApplyBodyImpulse", 2 * 80)
T.budget("MakeHole", 45)
T.budget("QueryClosestPoint", 90)
T.budget("QueryAabbBodies", 2)
T.budget("SpawnFire", 4)
T.budget("SetEnvironmentProperty", 3)
T.budget("SpawnParticle", 40)

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
local wall = H.addStaticBox(V(-30, 0, -70), V(30, 10, -69), "masonry")
local bodies = {}
math.randomseed(7)
for i = 1, 150 do
	local a = math.random() * 6.28
	local r = 3 + math.random() * 120
	bodies[i] = H.addBody { pos = V(math.cos(a) * r, 0.25, -69 + math.sin(a) * r), mass = 10 + math.random() * 200 }
end
local orig = { H.env.skyboxtint[1], H.env.skyboxtint[2], H.env.skyboxtint[3] }

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.fallingmoon ~= nil and H.P(1).enabled.fallingmoon, "tool registered and enabled")
T.select("fallingmoon")
T.frames(1)
T.check(T.hasText("call the moon down"), "hint")

-- start; shorten the timeline for the test
T.press("usetool"); T.frames(2)
local m = sh().m
T.check(m.phase == "approach", "LMB starts the approach")
T.check(math.abs(m.z + 69) < 1.5, string.format("impact point at the aim point (z %.1f)", m.z))
T.check(T.soundsPlayed("chime.ogg") == 1, "start chime")
srv().ev.T = 20
sh().m.T = 20
T.frames(120)
T.check(callsOf("DrawSprite") > 100, "the moon is drawn in the sky")
T.check(T.hasText("IMPACT IN"), "countdown shown")
T.check(callsOf("UiSoundLoop") > 100, "rumble loop")
local imp0 = callsOf("ApplyBodyImpulse")
T.frames(600)
T.check(callsOf("ApplyBodyImpulse") > imp0, "tremors push bodies in the second half")
T.check(H.env.skyboxtint[2] < orig[2] - 0.1, string.format("sky turns red (tint g %.2f)", H.env.skyboxtint[2]))
T.check((H.sideCalls.client.SetEnvironmentProperty or 0) == 0, "sky tint set only by server code")
T.check(callsOf("ShakeCamera") > 100, "camera shakes")

-- impact
local ex0 = #H.explosions
local f = T.runUntil(function() return sh().m.phase == "impact" end, 600)
T.check(f ~= nil, "impact at the end of the countdown")
T.check(T.soundsPlayed("beep.ogg") >= 8, "countdown beeps (" .. T.soundsPlayed("beep.ogg") .. ")")
T.check(T.soundsPlayed("roar.ogg") == 1, "incoming roar")
T.check(#H.explosions > ex0, "explosion at the impact")
T.frames(60)
local ring = 0
local mr = sh().m.mr
for _, h in ipairs(H.holes) do
	local dx, dz = h.pos[1] - sh().m.x, h.pos[3] - sh().m.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d >= 0.8 * mr and d <= 1.35 * mr then ring = ring + 1 end
end
T.check(ring >= 50, "crater ring dug around the moon (" .. ring .. " holes)")
T.frames(2)
T.check(T.soundsPlayed("impact.ogg") == 1, "impact sound")
T.check(T.cenv().client.flash > 0.3, "blinding flash")

-- the shockwave works over several frames
local frames = T.runUntil(function() return sh().m.phase == "aftermath" end, 600)
T.check(frames ~= nil and frames > 30, "shockwave rolls out over " .. tostring(frames) .. " frames")
local out = 0
local c = V(sh().m.x, sh().m.y, sh().m.z)
for i = 1, #bodies do
	local b = H.bodies[bodies[i]]
	local d = sub(b.pos, c)
	if len(V(d[1], 0, d[3])) < 140 and (b.vel[1] * d[1] + b.vel[3] * d[3]) > 0 then out = out + 1 end
end
T.check(out > 30, "bodies thrown outwards (" .. out .. ")")
T.check(H.fires > 0, "fires started")
T.check(H.P(1).damage > 0, "player hit by the shockwave")
T.check(callsOf("MakeHole") > 50, "holes punched along the front (" .. callsOf("MakeHole") .. ")")

-- aftermath: sky comes back, state resets
T.runUntil(function() return sh().m.phase == "idle" end, 2200)
T.check(sh().m.phase == "idle", "back to idle after the aftermath")
T.check(math.abs(H.env.skyboxtint[2] - orig[2]) < 1e-6, "sky restored")

-- abort during the approach
local exAbort = #H.explosions
T.press("usetool"); T.frames(2)
srv().ev.T = 20
sh().m.T = 20
T.frames(700)
T.press("grab"); T.frames(2)
T.check(sh().m.phase == "recede", "RMB sends the moon back")
T.runUntil(function() return sh().m.phase == "idle" end, 400)
T.check(sh().m.phase == "idle" and math.abs(H.env.skyboxtint[2] - orig[2]) < 1e-6, "receded, sky restored")
T.check(#H.explosions == exAbort, "no impact after aborting")

-- countdown hidden
H.reg["savegame.mod.countdown"] = false
T.press("usetool"); T.frames(3)
T.check(not T.hasText("IMPACT IN"), "countdown can be hidden")
T.press("grab"); T.runUntil(function() return sh().m.phase == "idle" end, 400)
H.reg["savegame.mod.countdown"] = true

-- Russian
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("обрушить луну"), "hint in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Falling Moon"), "options: title")
H.uiSliderSet[1] = 0
T.drawOptions(1)
T.check(H.reg["savegame.mod.duration"] == 60, "options: time to impact 60 s")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.duration"] == 120 and H.reg["savegame.mod.radius"] == 150, "options: reset")
