-- Harness scenarios for Telekinesis.
local function V(x, y, z) return { x, y, z } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function me() return sh().tk[1] end
local function callsOf(n) return H.calls[n] or 0 end
local function hold(n) for i = 1, n do T.hold("usetool"); T.frames(1) end end

T.budget("QueryAabbBodies", 1)
T.budget("ConstrainPosition", 2 * 20)
T.budget("SetBodyVelocity", 20)
T.budget("SpawnParticle", 20)

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -15
local near = {}
math.randomseed(4)
for i = 1, 12 do near[i] = H.addBody { pos = V(-1.5 + math.random() * 3, 0.25, -6.5 + math.random() * 2), mass = 20 } end
local heavy = H.addBody { pos = V(0.5, 0.6, -6.2), mass = 900, half = V(0.6, 0.6, 0.6) }
local far = H.addBody { pos = V(15, 0.25, -6), mass = 10 }

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.telekinesis ~= nil and H.P(1).enabled.telekinesis, "tool registered and enabled")
T.select("telekinesis")
T.frames(1)
T.check(T.hasText("lift the objects"), "hint")

-- lift
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(2)
local n = #me().held
T.check(n == 8, "LMB lifts up to 8 objects (" .. n .. ")")
T.check(T.soundsPlayed("grab.ogg") == 1, "grab sound")
local heldHeavy, heldFar = false, false
for _, b in ipairs(me().held) do
	if b == heavy then heldHeavy = true end
	if b == far then heldFar = true end
end
T.check(not heldHeavy, "objects over the mass limit stay")
T.check(not heldFar, "objects outside the radius stay")
T.frames(90)
local eye = H.eyeT(H.P(1))
local avg = 0
for _, b in ipairs(me().held) do avg = avg + len(sub(H.bodies[b].pos, eye.pos)) end
avg = avg / #me().held
T.check(avg > 1.5 and avg < 5.5, string.format("they hover in front of the player (avg %.1f m)", avg))
T.check(callsOf("DrawBodyOutline") > 50, "held objects glow")
T.check(T.loopFrames("hold.ogg") > 50, "hum loop")
T.check(me().energy < 1, "holding drains energy")
T.check(T.hasText("Holding 8"), "HUD shows the held count")

-- charge and throw
T.press("usetool"); hold(60)
T.check(me().charge > 0.8, string.format("holding LMB charges (%.2f)", me().charge))
local list = {}
for i, b in ipairs(me().held) do list[i] = b end
T.release("usetool"); T.frames(2)
T.check(#me().held == 0, "release throws")
T.check(T.soundsPlayed("throw.ogg") == 1, "throw sound")
T.frames(20)
local fast, forward = 0, 0
local fwd = H.API.TransformToParentVec(H.eyeT(H.P(1)), V(0, 0, -1))
for _, b in ipairs(list) do
	local v = H.bodies[b].vel
	if len(v) > 15 then fast = fast + 1 end
	if (v[1] * fwd[1] + v[2] * fwd[2] + v[3] * fwd[3]) > 10 then forward = forward + 1 end
end
T.check(fast >= 6, "thrown hard after a full charge (" .. fast .. " of 8)")
T.check(forward >= 6, "thrown along the view (" .. forward .. " of 8)")

-- drop gently with RMB
T.frames(60)
for i = 1, 12 do H.bodies[near[i]].pos = V(-1.5 + math.random() * 3, 0.25, -6.5 + math.random() * 2); H.bodies[near[i]].vel = V(0, 0, 0) end
T.frames(60)
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(40)
T.check(#me().held > 0, "lifted again")
T.press("grab"); T.frames(2)
T.check(#me().held == 0 and T.soundsPlayed("drop.ogg") >= 1, "RMB puts them down")

-- energy runs out while holding
H.reg["savegame.mod.capacity"] = 5.0
T.frames(200)
T.press("usetool"); T.frames(1); T.release("usetool")
local f = T.runUntil(function() return #me().held == 0 end, 900)
T.check(f ~= nil, "objects drop when energy runs out (" .. tostring(f) .. " frames)")
T.check(T.soundsPlayed("empty.ogg") >= 1, "empty sound")
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(2)
T.check(#me().held == 0, "no lifting with an empty meter")
H.reg["savegame.mod.capacity"] = 15.0

-- switching tools drops everything
H.reg["savegame.mod.energy"] = false
T.frames(10)
for i = 1, 12 do H.bodies[near[i]].pos = V(-1.5 + math.random() * 3, 0.25, -6.5 + math.random() * 2); H.bodies[near[i]].vel = V(0, 0, 0) end
T.frames(30)
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(10)
T.check(#me().held > 0, "lift with energy off")
T.select("sledge"); T.frames(2)
T.check(#me().held == 0, "putting the tool away drops the objects")
T.select("telekinesis")

-- client never touches the bodies
T.check((H.sideCalls.client.ConstrainPosition or 0) == 0 and (H.sideCalls.client.SetBodyVelocity or 0) == 0, "bodies moved only by server code")

-- Russian
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("поднять предметы"), "hint in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Telekinesis"), "options: title")
H.uiSliderSet[2] = 0
T.drawOptions(1)
T.check(H.reg["savegame.mod.maxbodies"] == 1, "options: max objects to 1")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.maxbodies"] == 8 and H.reg["savegame.mod.energy"] == true, "options: reset")
