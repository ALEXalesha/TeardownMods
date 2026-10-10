-- Harness scenarios and laws for the Tsunami.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
local function callsOf(n) return H.calls[n] or 0 end

T.budget("ApplyBodyImpulse", 60)
T.budget("QueryAabbBodies", 2)
T.budget("MakeHole", 24)
T.budget("QueryRaycast", 30 + 6 + 2)
T.budget("SpawnParticle", 30)
T.budget("SetProperty", 8)
T.budget("DrawSprite", 280)

-- player at the origin looking along -z: the wave comes from -z and travels towards +z
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
local sea = H.addEntity("water", { wave = 0.3, ripple = 0.4, motion = 0.2, foam = 0.1, depth = 5 })
local crate = H.addBody { pos = V(3, 0.25, -30), mass = 40 }
local car = H.addBody { pos = V(-6, 0.8, -50), mass = 1200, half = V(1, 0.8, 2) }
H.addVehicle(car, {})
-- a crate up on a 25 m roof: above the water, must stay
H.addStaticBox(V(18, 0, -40), V(24, 25, -34), "masonry")
local roofCrate = H.addBody { pos = V(21, 25.25, -37), mass = 40 }
-- weak and strong structures in the wave's path
H.addCubes(V(-30, 0, -80), V(-14, 6, -78), 2, "wood")
H.addCubes(V(10, 0, -80), V(26, 6, -78), 2, "masonry")
H.addCubes(V(-30, 0, -100), V(-14, 6, -98), 2, "hardmasonry")

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.tsunami ~= nil and H.P(1).enabled.tsunami, "tool registered and enabled")
T.select("tsunami")
T.frames(1)
T.check(T.hasText("call a tsunami"), "hint")

-- call it
T.press("usetool"); T.frames(2)
local w = sh().ts
T.check(w.phase == "warning", "LMB starts the warning")
T.check(w.dz > 0.99, "the wave travels towards the player (from where he looks)")
T.check(T.soundsPlayed("horn.ogg") == 1, "horn")
T.frames(60)
T.check(T.hasText("TSUNAMI WARNING") and callsOf("UiSoundLoop") > 30, "warning text and siren while it rises")
T.check((H.sideCalls.client.SetProperty or 0) == 0, "only the server changes the level's water")
local c0 = { H.bodies[crate].pos[1], H.bodies[crate].pos[2], H.bodies[crate].pos[3] }
T.check(math.abs(H.bodies[crate].pos[3] - c0[3]) < 0.01, "nothing moves before the wave arrives")

-- the wave rolls in at the set speed
T.runUntil(function() return sh().ts.phase == "wave" end, 600)
T.check(H.entities[sea].props.wave > 0.8 and H.entities[sea].props.foam > 0.9, string.format("real water in the level turns rough (wave %.2f, foam %.2f)", H.entities[sea].props.wave, H.entities[sea].props.foam))
local s0 = sh().ts.s
T.frames(120)
local v = (sh().ts.s - s0) / 2
T.check(math.abs(v - 18) < 0.9, string.format("front moves at the set speed (%.1f m/s)", v))
local spritesMax, badDepth = 0, 0
-- the water has a body, not one flat card per segment (in-game 04.10: "2D, like a picture"):
-- the wave sprites spread back from the front face, and a back slope stands above the flood
local waveDepth, backSlope = 0, 0
T.frameHooks[#T.frameHooks + 1] = function()
	spritesMax = math.max(spritesMax, #H.sprites)
	for _, s in ipairs(H.sprites) do if not s.depthTest then badDepth = badDepth + 1 end end
	local ts = sh().ts
	if ts.phase ~= "wave" then return end
	local lo, hi = 1e9, -1e9
	for _, s in ipairs(H.sprites) do
		local along = (s.pos[1] - ts.ox) * ts.dx + (s.pos[3] - ts.oz) * ts.dz
		if s.path:find("wave.png") then lo = math.min(lo, along); hi = math.max(hi, along) end
		if s.path:find("flood.png") and s.pos[2] > ts.oy + 0.4 * ts.h and along < ts.s then backSlope = backSlope + 1 end
	end
	if hi > lo then waveDepth = math.max(waveDepth, hi - lo) end
end

-- it passes the player
local holes0 = #H.holes
local pp0 = { H.P(1).pos[1], H.P(1).pos[2], H.P(1).pos[3] }
local passed = T.runUntil(function() return sh().ts.s > 2 end, 2000)
T.check(passed ~= nil, "the wave reaches the player")
T.frames(2)
T.check(T.soundsPlayed("crash.ogg") == 1, "crash when it passes")
T.frames(120)
T.check(H.P(1).pos[3] - pp0[3] > 5, string.format("the player is carried along (%.1f m)", H.P(1).pos[3] - pp0[3]))
T.check(H.bodies[crate].pos[3] - c0[3] > 10, string.format("a crate is carried away (%.1f m)", H.bodies[crate].pos[3] - c0[3]))
T.check(H.bodies[car].pos[3] - (-50) > 3, string.format("a 1.2 t car is carried away (%.1f m)", H.bodies[car].pos[3] + 50))
T.check(math.abs(H.bodies[roofCrate].pos[3] + 37) < 0.05, "a crate up on a 25 m roof stays dry")
T.check(spritesMax > 10 and spritesMax <= 280 and badDepth == 0, string.format("the wall and the flood are drawn with depth-tested sprites (max %d per frame, cap 280)", spritesMax))
T.check(waveDepth >= 6, string.format("the wave has a body behind its face (%.1f m deep, need >= 6)", waveDepth))
T.check(backSlope > 0, "a back slope runs from the crest down to the flood")
T.check(T.loopFrames("roar.ogg") > 100, "roar of the wave")

-- weak structures torn, strong ones barely, hard ones not at all
local c = { 0, 0, 0 }
local tw, rw, tm, rm, th, rh = 0, 0, 0, 0, 0, 0
for _, cube in ipairs(H.cubes) do
	if cube.material == "wood" then tw = tw + 1 if not cube.alive then rw = rw + 1 end end
	if cube.material == "masonry" then tm = tm + 1 if not cube.alive then rm = rm + 1 end end
	if cube.material == "hardmasonry" then th = th + 1 if not cube.alive then rh = rh + 1 end end
end
T.check(rw / tw >= 0.4, string.format("wooden structures torn (%.0f %%)", 100 * rw / tw))
T.check(rm / tm >= 0.3, string.format("masonry breached too (%.0f %%)", 100 * rm / tm))
T.check(rh == 0, "hard masonry untouched")

-- backwash and the end
T.runUntil(function() return sh().ts.phase == "recede" end, 3000)
T.check(sh().ts.phase == "recede", "the water runs back")
T.frames(30)
T.check(T.loopFrames("recede.ogg") > 10, "backwash sound")
T.runUntil(function() return sh().ts.phase == "idle" end, 1200)
T.check(sh().ts.phase == "idle", "back to idle")
local props = H.entities[sea].props
T.check(props.wave == 0.3 and props.ripple == 0.4 and props.motion == 0.2 and props.foam == 0.1 and props.depth == 5, "the level's water is exactly as it was")
T.frameHooks[#T.frameHooks] = nil

-- RMB calls it off
T.press("usetool"); T.frames(30)
T.press("grab"); T.frames(2)
T.check(sh().ts.phase == "recede", "RMB calls the wave off")
T.runUntil(function() return sh().ts.phase == "idle" end, 1200)

-- no siren, no damage
H.reg["savegame.mod.siren"] = false
H.reg["savegame.mod.power"] = 0
local loops0 = callsOf("UiSoundLoop")
local mk0 = callsOf("MakeHole")
T.press("usetool")
T.runUntil(function() return sh().ts.phase == "idle" end, 4000)
T.check(callsOf("UiSoundLoop") == loops0, "siren can be switched off")
T.check(callsOf("MakeHole") == mk0, "damage can be switched off")
H.reg["savegame.mod.siren"] = true
H.reg["savegame.mod.power"] = 1

-- Russian
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("вызвать цунами"), "hint in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Tsunami"), "options: title")
H.uiSliderSet[1] = 0
T.drawOptions(1)
T.check(H.reg["savegame.mod.height"] == 3, "options: wave height 3 m")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.height"] == 14 and H.reg["savegame.mod.speed"] == 18, "options: reset")
