-- Harness scenarios for the Earthquake mod.
local function V(x, y, z) return { x, y, z } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function srv() return T.env().server end
local function cli() return T.cenv().client end
local function sh() return T.sharedOf() end
local function callsOf(n) return H.calls[n] or 0 end

T.budget("QueryAabbBodies", 1)
T.budget("ApplyBodyImpulse", 110) -- 55 per physics step, 2 steps per frame at 30 fps
T.budget("MakeHole", 10)
T.budget("QueryClosestPoint", 12)
T.budget("QueryAabbShapes", 1)
T.budget("DetachJointFromShape", 4)
T.budget("QueryRaycast", 40)
T.budget("SpawnParticle", 30)
T.budget("PlaySound", 4)

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -20
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.quake ~= nil, "tool registered")
T.check(H.P(1).enabled.quake == true, "tool enabled")

-- world: crates, hinged parts, walls of different materials
local crates = {}
math.randomseed(5)
for i = 1, 30 do crates[i] = H.addBody { pos = V(math.random() * 20 - 10, 0.25, -5 - math.random() * 20), mass = 30 } end
local car = H.addBody { pos = V(4, 0.8, -12), mass = 1400, half = V(1, 0.8, 2) }
local doorA = H.addBody { pos = V(-3, 1, -8), mass = 15 }
local joints = {}
for i = 1, 6 do
	local a = H.addBody { pos = V(-6 + i, 2, -9), mass = 5 }
	joints[i] = H.addJoint(H.bodies[a].shapes[1], H.bodies[doorA].shapes[1], "hinge")
end
H.addStaticBox(V(-10, 0, -15), V(10, 6, -14.6), "wood")
H.addStaticBox(V(-10, 0, -20), V(10, 6, -19.6), "masonry")
H.addStaticBox(V(6, 0, -18), V(6.1, 4, -10), "glass")

T.select("quake")
T.frames(2)
T.check(T.hasText("Strong"), "HUD shows the default preset Strong")
T.press("grab"); T.frames(2)
T.check(sh().presets[1] == 4, "RMB switches to preset 4")
T.check(T.hasText("Severe"), "HUD shows Severe")

T.press("usetool"); T.frames(2)
T.check(sh().quake.active, "LMB starts a quake")
T.check(T.soundsPlayed("click.ogg") == 1 and T.soundsPlayed("boom.ogg") == 1, "click and boom played")
local ep = V(sh().quake.x, sh().quake.y, sh().quake.z)
T.check(ep[3] < -2, "epicentre at the aim point (z=" .. string.format("%.1f", ep[3]) .. ")")
local holes0 = #H.holes
T.frames(180)
local moving = 0
for i = 1, #crates do
	local v = H.bodies[crates[i]].vel
	if math.abs(v[1]) + math.abs(v[3]) > 0.05 then moving = moving + 1 end
end
T.check(moving > 15, "crates are shaken (" .. moving .. " of 30)")
T.check(callsOf("ShakeCamera") > 100, "camera shakes")
T.check(T.loopFrames("rumble.ogg") > 100, "rumble loop plays")
T.check(#H.holes > holes0, "structures crack (" .. (#H.holes - holes0) .. " holes)")
local broken = 0
for i = 1, #joints do if H.joints[joints[i]].broken then broken = broken + 1 end end
T.check(broken > 0, "joints loosened (" .. broken .. " of 6)")
T.check(callsOf("SetPlayerVelocity") > 0, "player gets jolted")
T.check(H.particles > 100, "dust particles")
T.check(T.soundsPlayed("crack") > 0, "crack sounds")
T.check(len(H.bodies[car].vel) > 0, "vehicle-sized body is shaken too")
local ordered = true
for i = holes0 + 1, #H.holes do
	local h = H.holes[i]
	if h.r2 > h.r1 + 1e-6 or h.r1 > h.r0 + 1e-6 then ordered = false end
end
T.check(ordered, "MakeHole radii ordered soft >= medium >= hard")

T.runUntil(function() return not sh().quake.active end, 1200)
T.check(not sh().quake.active, "quake ends after its duration")
T.check(#srv().pending >= 2, "aftershocks scheduled (" .. #srv().pending .. ")")
local loops0 = T.loopFrames("rumble.ogg")
T.frames(30)
T.check(T.loopFrames("rumble.ogg") == loops0, "rumble stops after the quake")
local sawAfter = T.runUntil(function() return sh().quake.active and sh().quake.after == 1 end, 1800)
T.check(sawAfter ~= nil, "an aftershock happens")
T.frames(1)
T.check(T.hasText("Aftershock"), "HUD shows the aftershock")
T.runUntil(function() return not sh().quake.active end, 1200)

-- LMB stops a running quake and cancels pending aftershocks
T.press("usetool"); T.frames(30)
T.check(sh().quake.active, "second quake started")
T.press("usetool"); T.frames(2)
T.check(not sh().quake.active, "LMB stops the quake")
T.check(#srv().pending == 0, "stopping cancels aftershocks")

-- damage off: no holes, no detached joints
H.reg["savegame.mod.damage"] = false
local h1 = #H.holes
local d1 = callsOf("DetachJointFromShape")
T.press("usetool"); T.frames(240)
T.check(#H.holes == h1 and callsOf("DetachJointFromShape") == d1, "no damage when structural damage is off")
T.press("usetool"); T.frames(2)
H.reg["savegame.mod.damage"] = true

-- weak preset: shaking only
for i = 1, 2 do T.press("grab"); T.frames(1) end   -- 4 -> 5 -> 1
T.check(sh().presets[1] == 1, "preset cycles back to Weak")
local h2 = #H.holes
local pv = callsOf("SetPlayerVelocity")
T.press("usetool"); T.frames(240)
T.check(#H.holes == h2, "weak quake makes no holes")
T.check(callsOf("SetPlayerVelocity") == pv, "weak quake does not push the player")
T.press("usetool"); T.frames(2)

-- epicentre under the player
H.reg["savegame.mod.atplayer"] = true
H.P(1).pos = V(30, 0, 30)
T.press("usetool"); T.frames(2)
T.check(math.abs(sh().quake.x - 30) < 0.01 and math.abs(sh().quake.z - 30) < 0.01, "epicentre under the player")
T.press("usetool"); T.frames(2)

-- variable frame rate
T.press("usetool"); T.frames(200, 1 / 30); T.press("usetool"); T.frames(2, 1 / 30)
T.press("usetool"); T.frames(400, 1 / 144); T.press("usetool"); T.frames(2, 1 / 144)
T.check(not sh().quake.active, "start/stop at 30 and 144 fps")

-- Russian
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("Сила:"), "HUD in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Earthquake"), "options: title")
H.uiClicks["Under the player"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.atplayer"] == false, "options: epicentre toggles back to aim point")
H.uiSliderSet[1] = 260
T.drawOptions(1)
T.check(H.reg["savegame.mod.duration"] == 60, "options: duration slider to 60 s")
H.uiClicks["Strong"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.preset"] == 4, "options: preset cycles Strong -> Severe")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.duration"] == 15 and H.reg["savegame.mod.preset"] == 3, "options: reset")
