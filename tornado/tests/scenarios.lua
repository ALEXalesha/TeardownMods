-- Harness scenarios for the Tornado.
local function V(x, y, z) return { x, y, z } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function first() for id, t in pairs(sh().t) do return id, t end end
local function callsOf(n) return H.calls[n] or 0 end

T.budget("ApplyBodyImpulse", 2 * 2 * 50)   -- two tornadoes, two physics steps at 30 fps
T.budget("QueryAabbBodies", 4)
T.budget("MakeHole", 2 * 2 * 2)
T.budget("QueryClosestPoint", 2 * 2 * 2 + 2)
T.budget("SpawnParticle", 80)
T.budget("DetachJointFromShape", 4)

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -20
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.tornado ~= nil and H.P(1).enabled.tornado, "tool registered and enabled")
T.select("tornado")
T.frames(1)
T.check(T.hasText("LMB: tornado"), "HUD hint")

-- spawn
T.press("usetool"); T.frames(2)
local id, t = first()
T.check(id ~= nil, "LMB spawns a tornado")
T.check(t and t.z < -2, "at the aim point")
T.check(T.soundsPlayed("spawn.ogg") == 1, "spawn thunder")
local c = V(t.x, t.y, t.z)

-- objects around it
local crates = {}
math.randomseed(2)
for i = 1, 40 do
	local a = math.random() * 6.28
	local r = 2 + math.random() * 8
	crates[i] = H.addBody { pos = V(c[1] + math.cos(a) * r, 0.25, c[3] + math.sin(a) * r), mass = 15 }
end
local car = H.addBody { pos = V(c[1] + 4, 0.8, c[3]), mass = 1300, half = V(1, 0.8, 2) }
local v = H.addVehicle(car, {})
local farBox = H.addBody { pos = V(c[1] + 60, 0.25, c[3]), mass = 15 }
H.addStaticBox(V(c[1] - 6, 0, c[3] + 3), V(c[1] + 6, 4, c[3] + 3.3), "wood")
local jA = H.addBody { pos = V(c[1] - 2, 2, c[3] - 2), mass = 5 }
local joint = H.addJoint(H.bodies[jA].shapes[1], 0, "rope")
H.P(1).pos = V(c[1] + 5, 0, c[3] + 1)
local holes0 = #H.holes

local maxY = {}
table.insert(T.frameHooks, function()
	for i = 1, #crates do
		local b = H.bodies[crates[i]]
		local m = math.max(b.pos[2] - 0.25, len(b.vel) * 0.5)
		if m > (maxY[i] or 0) then maxY[i] = m end
	end
end)
T.frames(360)
table.remove(T.frameHooks)
local lifted = 0
for i = 1, #crates do if (maxY[i] or 0) > 1.0 then lifted = lifted + 1 end end
local up = 0
for i = 1, #crates do if H.bodies[crates[i]].pos[2] > 1.0 then up = up + 1 end end
T.check(lifted > 15, "loose objects are pulled in or lifted (" .. lifted .. " of 40)")
T.check(len(H.bodies[farBox].vel) < 0.01, "far objects untouched")
T.check(len(H.bodies[car].vel) > 0, "vehicle affected (lift vehicles on)")
T.check(callsOf("SetPlayerVelocity") > 0, "player is pushed (lift player on)")
T.check(#H.holes > holes0, "weak walls torn (" .. (#H.holes - holes0) .. " holes)")
T.check(T.loopFrames("roar.ogg") > 100, "roar loop")
T.check(callsOf("ShakeCamera") > 50, "camera shake near the tornado")
T.check(H.particles > 1000, "funnel particles (" .. H.particles .. ")")
local moved = len(sub(V(sh().t[id].x, 0, sh().t[id].z), V(c[1], 0, c[3])))
T.check(moved > 5, string.format("tornado wanders (%.1f m in 6 s)", moved))

-- RMB dismisses
T.press("grab"); T.frames(2)
T.check(srv().t[id].dying, "RMB dismisses the tornado")
T.runUntil(function() return count(sh().t) == 0 end, 400)
T.check(count(sh().t) == 0, "tornado fades out and is removed")
T.check(T.soundsPlayed("dissipate.ogg") >= 1, "dissipate sound")
local l0 = T.loopFrames("roar.ogg")
T.frames(10)
T.check(T.loopFrames("roar.ogg") == l0, "roar stops")

-- max two at a time
for i = 1, 4 do T.press("usetool"); T.frames(2) end
T.check(count(sh().t) == 2, "at most two tornadoes")
for i = 1, 2 do T.press("grab"); T.frames(2) end
T.runUntil(function() return count(sh().t) == 0 end, 400)

-- follow mode: moves towards the aim point
H.reg["savegame.mod.follow"] = true
H.P(1).pos = V(0, 0, 0)
H.P(1).yaw = 0
T.press("usetool"); T.frames(2)
id, t = first()
local start = V(t.x, 0, t.z)
H.P(1).yaw = 90    -- look left: aim point moves to -x
T.frames(360)
id, t = first()
T.check(t.x < start[1] - 2, string.format("follow mode heads to the aim (x %.1f -> %.1f)", start[1], t.x))
T.press("grab"); T.runUntil(function() return count(sh().t) == 0 end, 400)
H.reg["savegame.mod.follow"] = false
H.P(1).yaw = 0

-- options off: no vehicles, no player, no damage
H.reg["savegame.mod.vehicles"] = false
H.reg["savegame.mod.player"] = false
H.reg["savegame.mod.damage"] = false
H.bodies[car].pos = V(0, 0.8, -8); H.bodies[car].vel = V(0, 0, 0)
H.P(1).pos = V(2, 0, -5)
local pv = callsOf("SetPlayerVelocity")
local h1 = #H.holes
T.press("usetool"); T.frames(180)
T.check(len(H.bodies[car].vel) < 0.5, "vehicles left alone when the option is off")
T.check(callsOf("SetPlayerVelocity") == pv, "player left alone when the option is off")
T.check(#H.holes == h1, "no building damage when the option is off")
T.press("grab"); T.runUntil(function() return count(sh().t) == 0 end, 400)

-- variable frame rate
T.press("usetool"); T.frames(90, 1 / 30); T.press("grab"); T.runUntil(function() return count(sh().t) == 0 end, 400, 1 / 30)
T.press("usetool"); T.frames(300, 1 / 144); T.press("grab"); T.runUntil(function() return count(sh().t) == 0 end, 1500, 1 / 144)
T.check(count(sh().t) == 0, "full cycles at 30 and 144 fps")

-- Russian
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("ЛКМ: торнадо"), "HUD in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Tornado"), "options: title")
H.uiClicks["Wanders on its own"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.follow"] == true, "options: follow mode")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.follow"] == false and H.reg["savegame.mod.size"] == 8, "options: reset")
