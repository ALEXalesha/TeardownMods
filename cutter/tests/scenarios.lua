-- Harness scenarios for the Cutter.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
local function cli() return T.cenv().client end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function callsOf(n) return H.calls[n] or 0 end
local function hold(n) for i = 1, n do T.hold("usetool"); T.frames(1) end end

T.budget("MakeHole", 4 * 40 * 2)    -- per frame: 4 jobs x 40 budget, 2 physics steps at 30 fps
T.budget("QueryRaycast", 200)
T.budget("SpawnParticle", 60)
T.budget("PointLight", 8)

H.addPlayer(1, V(0, 0, 0))
-- walls in front: wood at z=-3, concrete at z=-3 to the right, hard metal further right
local wood = H.addStaticBox(V(-2, 0, -3.4), V(0, 3, -3.0), "wood")
local concrete = H.addStaticBox(V(0, 0, -3.4), V(2, 3, -3.0), "masonry")
local hard = H.addStaticBox(V(2, 0, -3.4), V(4, 3, -3.0), "hardmetal")

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.cutter ~= nil and H.P(1).enabled.cutter, "tool registered and enabled")
T.select("cutter")
T.frames(2)
T.check(T.hasText("Hold LMB on a surface"), "HUD hint")

-- cut in the wood wall: press at yaw 20 (left), sweep to yaw 10
H.P(1).yaw = 25
H.P(1).pitch = -5
T.press("usetool"); T.frames(1)
local st = srv().players[1]
T.check(st.holding and math.abs(st.a[3] + 3.0) < 0.05, "press on the wall starts a cut line")
T.check(T.soundsPlayed("spinup.ogg") == 1, "motor spins up")
for i = 1, 20 do H.P(1).yaw = 25 - i * 0.5; T.hold("usetool"); T.frames(1) end
T.check(sh().pl[1].holding and sh().pl[1].len > 0.3, string.format("preview line while holding (%.2f m)", sh().pl[1].len))
T.check(T.hasText("release to cut"), "HUD shows the length")
local holes0 = #H.holes
T.release("usetool"); T.frames(1)
T.check(count(sh().jobs) == 1, "release queues a cut job")
local f = T.runUntil(function() return count(sh().jobs) == 0 end, 600)
T.check(f ~= nil, "cut finished in " .. tostring(f) .. " frames")
local n = #H.holes - holes0
T.check(n > 10, "cut made " .. n .. " holes")
local throughZ, maxR = 0, 0
for i = holes0 + 1, #H.holes do
	local h = H.holes[i]
	if h.pos[3] < -3.35 then throughZ = throughZ + 1 end
	if h.r0 > maxR then maxR = h.r0 end
	if h.r1 ~= 0 then T.fail("wood cut used a medium radius") break end
end
T.check(throughZ > 0, "holes reach the back of the 0.4 m wall")
T.check(math.abs(maxR - 0.1) < 1e-6, "kerf radius 0.1 (0.2 m kerf)")
T.frames(2)
T.check(T.soundsPlayed("spindown.ogg") >= 1, "motor spins down after the cut")
T.check(H.particles > 0, "sawdust particles")

-- concrete is slower than wood (same length)
local function cutAt(yawA, yawB)
	H.P(1).yaw = yawA
	T.press("usetool"); T.frames(1)
	for i = 1, 10 do H.P(1).yaw = yawA + (yawB - yawA) * i / 10; T.hold("usetool"); T.frames(1) end
	T.release("usetool"); T.frames(1)
	local h0 = #H.holes
	local frames = T.runUntil(function() return count(sh().jobs) == 0 end, 900)
	return frames, #H.holes - h0
end
local fWood = cutAt(20, 12)
local fConc, hConc = cutAt(-10, -20)
T.check(fConc and fWood and fConc > fWood, string.format("concrete takes longer (%s vs %s frames)", tostring(fConc), tostring(fWood)))
local med = 0
for i = #H.holes - hConc + 1, #H.holes do if H.holes[i].r1 > 0 then med = med + 1 end end
T.check(med > 0, "concrete holes use the medium radius")

-- hard metal is off by default
local fHard, hHard = cutAt(-40, -50)
T.check(hHard == 0, "hard metal is not cut by default")
H.reg["savegame.mod.hard"] = true
local _, hHard2 = cutAt(-40, -50)
T.check(hHard2 > 0, "hard metal cut when enabled")
H.reg["savegame.mod.hard"] = false

-- masonry off
H.reg["savegame.mod.masonry"] = false
local _, hc = cutAt(-10, -20)
T.check(hc == 0, "concrete skipped when disabled")
H.reg["savegame.mod.masonry"] = true

-- max length clamp
H.reg["savegame.mod.maxlen"] = 0.5
H.P(1).yaw = 25
T.press("usetool"); T.frames(1)
for i = 1, 30 do H.P(1).yaw = 25 - i; T.hold("usetool"); T.frames(1) end
T.check(sh().pl[1].len <= 0.5001, "line length clamped to the option")
T.release("usetool"); T.runUntil(function() return count(sh().jobs) == 0 end, 600)
H.reg["savegame.mod.maxlen"] = 4.0

-- pressing at the sky does nothing and shows a message
H.P(1).yaw = 180
H.P(1).pitch = 30
T.press("usetool"); T.frames(2); T.release("usetool"); T.frames(2)
T.check(count(sh().jobs) == 0 and not srv().players[1].holding, "no cut without a surface")
T.check(T.hasText("Aim at a surface"), "message when aiming at nothing")
H.P(1).pitch = -5

-- job queue limit
for k = 1, 6 do
	H.P(1).yaw = 25
	T.press("usetool"); T.frames(1)
	H.P(1).yaw = 15; T.hold("usetool"); T.frames(1)
	T.release("usetool"); T.frames(1)
end
T.check(count(sh().jobs) <= 4, "at most 4 queued cuts per player (" .. count(sh().jobs) .. ")")
T.runUntil(function() return count(sh().jobs) == 0 end, 2000)
T.check(count(sh().jobs) == 0, "queue drains")

-- Russian
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("Зажмите ЛКМ"), "HUD in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Cutter"), "options: title")
H.uiSliderSet[1] = 260
T.drawOptions(1)
T.check(math.abs(H.reg["savegame.mod.kerf"] - 0.4) < 1e-6, "options: kerf slider to 0.4")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(math.abs(H.reg["savegame.mod.kerf"] - 0.2) < 1e-6, "options: reset")
