-- Harness scenarios for the Singularity Grenade (run by _shared/harness/run.py).
-- Runs twice: in one VM (host) and with separate server/client VMs.

local function V(x, y, z) return { x, y, z } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end

local function srv() return T.env().server end
local function cli() return T.cenv().client end
local function sh() return T.sharedOf() end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function firstGrenade()
	for id, g in pairs(sh().g) do return id, g end
	return nil
end
local function callsOf(name) return H.calls[name] or 0 end

-- per-frame budgets (worst case: 4 grenades at once + blast wave)
T.budget("QueryAabbBodies", 6)
T.budget("ApplyBodyImpulse", 4 * 40 + 50 + 10)
T.budget("MakeHole", 4 * 4 + 4)
T.budget("QueryRaycast", 30)
T.budget("GetShapeMaterialAtPosition", 20)
T.budget("SpawnParticle", 200)
T.budget("PointLight", 12)
T.budget("Spawn", 1)
T.budget("Paint", 4)
T.budget("ShakeCamera", 2)
T.budget("PlaySound", 12)

H.addPlayer(1, V(0, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(3)

-- 1. registration -----------------------------------------------------------
local reg = H.toolsRegistered.singularity
T.check(reg ~= nil, "tool 'singularity' registered")
T.check(reg and reg.file == "MOD/prefab/tool.xml", "tool uses the prefab with hand locations")
T.check(reg and reg.locations and reg.locations.fp_action ~= nil and reg.locations.tp_action_rh ~= nil, "prefab has fp_action and tp_action_rh locations")
T.check(H.P(1).enabled.singularity == true, "tool enabled for the player")
T.check(H.P(1).ammo.singularity == 5, "default ammo is 5")

-- 2. nothing happens without the tool selected ----------------------------------
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(5)
T.check(count(sh().g) == 0, "no grenade thrown while another tool is selected")

-- 3. charged throw ----------------------------------------------------------------
T.select("singularity")
T.frames(2)
T.press("usetool")
T.frames(1)
for i = 1, 30 do T.hold("usetool"); T.frames(1) end
local chargeSeen = cli().charge
T.check(chargeSeen > 0.4 and chargeSeen < 0.6, "client charge mirror ~0.5 after 0.5 s hold (" .. string.format("%.2f", chargeSeen) .. ")")
T.check(T.hasText("Hold LMB"), "HUD hint shown while tool is selected")
T.release("usetool")
T.frames(2)
local id, g = firstGrenade()
T.check(id ~= nil, "grenade spawned after releasing LMB")
T.check(H.P(1).ammo.singularity == 4, "ammo decreased to 4")
T.check(T.soundsPlayed("throw.ogg") == 1, "throw sound played once")
T.check(g and g.phase == "fly", "grenade is flying")
local body = g and g.body
T.check(body and H.bodies[body] and H.bodies[body].dynamic, "grenade is a dynamic body")
T.check(body and H.bodies[body].tags.singularity_grenade ~= nil, "grenade body tagged singularity_grenade")
local v0 = body and H.bodies[body].vel or V(0, 0, 0)
T.check(v0[3] < -12, "throw goes forward with charged speed (vz=" .. string.format("%.1f", v0[3]) .. ")")

-- 4. flight, bounce, rest, fuse, open --------------------------------------------
local frames = T.runUntil(function() local _, gg = firstGrenade() return gg and gg.phase == "open" end, 600)
T.check(frames ~= nil, "grenade opened (after " .. tostring(frames) .. " frames)")
T.frames(1) -- the client sees the new phase on the next frame
T.check(T.soundsPlayed("bounce.ogg") >= 1, "bounce sound played (" .. T.soundsPlayed("bounce.ogg") .. ")")
T.check(T.soundsPlayed("beep.ogg") >= 3, "arming beeps played (" .. T.soundsPlayed("beep.ogg") .. ")")
T.check(T.soundsPlayed("open.ogg") == 1, "open sound played once")
id, g = firstGrenade()
local center = V(g.cx, g.cy, g.cz)
T.check(g.cy > 0.8, "singularity hovers above the ground (y=" .. string.format("%.2f", g.cy) .. ")")

-- test objects around the singularity
local crate = H.addBody { pos = V(center[1] + 5, 0.25, center[3]), mass = 20, material = "wood" }
local heavy = H.addBody { pos = V(center[1] - 4, 0.8, center[3]), mass = 1500, half = V(1, 0.8, 2), material = "metal" }
local far = H.addBody { pos = V(center[1], 0.25, center[3] + 14), mass = 20 }
local debris = {}
math.randomseed(3)
for i = 1, 160 do
	local a = math.random() * 6.28
	local r = 1 + math.random() * 6
	debris[i] = H.addBody { pos = V(center[1] + math.cos(a) * r, 0.05, center[3] + math.sin(a) * r), mass = 0.5, half = V(0.05, 0.05, 0.05) }
end
local woodWall = H.addStaticBox(V(center[1] - 6, 0, center[3] - 3.2), V(center[1] + 6, 5, center[3] - 3.0), "wood")
local concrete = H.addStaticBox(V(center[1] - 6, 0, center[3] + 3.0), V(center[1] + 6, 5, center[3] + 3.2), "masonry")
local glassPane = H.addStaticBox(V(center[1] + 2.9, 0, center[3] - 3), V(center[1] + 3.0, 3, center[3] + 3), "glass")
-- the player stands inside the radius
H.P(1).pos = V(center[1] - 5, 0, center[3] + 1)
local holesBefore = #H.holes
local d0crate = len(sub(H.bodies[crate].pos, center))
local p0heavy = { H.bodies[heavy].pos[1], H.bodies[heavy].pos[2], H.bodies[heavy].pos[3] }
local farVel0 = len(H.bodies[far].vel)
local pv0 = callsOf("SetPlayerVelocity")

T.frames(60)
local d1crate = len(sub(H.bodies[crate].pos, center))
T.check(d1crate < d0crate - 1.0, string.format("crate pulled in: %.2f m -> %.2f m", d0crate, d1crate))
local heavyMoved = len(sub(H.bodies[heavy].pos, p0heavy))
T.check(heavyMoved < (d0crate - d1crate), string.format("1.5 t body moves less than the crate (%.2f m)", heavyMoved))
T.check(math.abs(len(H.bodies[far].vel) - farVel0) < 0.01, "body outside the radius untouched")
T.check(callsOf("SetPlayerVelocity") > pv0, "player inside the radius is pulled")
local tracked = #srv().grenades[id].tracked
T.check(tracked <= 120, "tracked bodies capped at 120 (" .. tracked .. ")")
T.check(cli().vignette > 0.05, "screen vignette while inside the radius")
T.check(T.loopFrames("hum.ogg") > 30, "hum loop playing")

T.frames(120)
local holes = {}
for i = holesBefore + 1, #H.holes do holes[#holes + 1] = H.holes[i] end
T.check(#holes > 0, "singularity tore holes (" .. #holes .. ")")
local onConcrete = 0
for _, h in ipairs(holes) do
	if h.pos[3] > center[3] + 2.9 and h.pos[1] > center[1] - 6 and h.pos[1] < center[1] + 2.8 then onConcrete = onConcrete + 1 end
	if h.r1 ~= 0 or h.r2 ~= 0 then T.fail("MakeHole touched medium/hard materials") end
end
T.check(onConcrete == 0, "no holes on the concrete wall")
local closeDebris = 0
for i = 1, #debris do if len(sub(H.bodies[debris[i]].pos, center)) < 2.5 then closeDebris = closeDebris + 1 end end
T.check(closeDebris > 20, "debris gathered near the core (" .. closeDebris .. " of 160)")

-- 5. collapse ------------------------------------------------------------------
local paints0 = H.paints
frames = T.runUntil(function() local _, gg = firstGrenade() return gg and gg.phase == "done" end, 400)
T.check(frames ~= nil, "singularity collapsed")
T.check(T.soundsPlayed("collapse.ogg") == 1, "collapse sound played once (" .. T.soundsPlayed("collapse.ogg") .. ")")
T.check(H.paints > paints0, "scorch mark painted")
T.check(not H.bodies[body].valid, "grenade body consumed")
T.frames(4)
T.check(cli().flash > 0.1, "white flash on screen")
local outward = 0
local n = 0
for i = 1, #debris do
	local b = H.bodies[debris[i]]
	local d = sub(b.pos, center)
	if len(d) < 6 then
		n = n + 1
		if dot(b.vel, d) > 0 then outward = outward + 1 end
	end
end
T.check(n > 0 and outward / n > 0.7, string.format("blast throws debris outward (%d of %d)", outward, n))
T.runUntil(function() return count(sh().g) == 0 end, 200)
T.check(count(sh().g) == 0 and count(srv().grenades) == 0, "state cleaned up after the blast")
local loopsBefore = T.loopFrames("hum.ogg")
T.frames(10)
T.check(T.loopFrames("hum.ogg") == loopsBefore, "hum loop stops after collapse")
T.check(H.bodies[crate].valid, "crate still exists after the blast")

-- 6. RMB drop at feet -------------------------------------------------------------
H.P(1).pos = V(0, 0, 0)
T.press("grab")
T.frames(2)
id, g = firstGrenade()
T.check(id ~= nil, "RMB throws a grenade")
local gp = H.bodies[g.body].pos
T.check(len(sub(V(gp[1], 0, gp[3]), V(0, 0, 0))) < 1.5, "RMB grenade lands at the feet")
T.check(H.P(1).ammo.singularity == 3, "ammo 3 after RMB throw")
T.runUntil(function() return count(sh().g) == 0 end, 900)
T.check(count(sh().g) == 0, "RMB grenade finished its cycle")

-- 7. player pull off: no SetPlayerVelocity ------------------------------------
H.reg["savegame.mod.pullplayer"] = false
H.reg["savegame.mod.impact"] = true
H.reg["savegame.mod.radius"] = 4.0
H.reg["savegame.mod.duration"] = 2.0
T.frames(40)
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(2)
id, g = firstGrenade()
T.check(g and g.r == 4.0 and g.dur == 2.0, "new settings used by the next throw (radius 4, 2 s)")
local tOpen = T.runUntil(function() local _, gg = firstGrenade() return gg and gg.phase == "open" end, 300)
T.check(tOpen ~= nil and tOpen < 90, "impact mode opens right after the first hit (" .. tostring(tOpen) .. " frames)")
id, g = firstGrenade()
H.P(1).pos = V(g.cx + 1.5, 0, g.cz)
local pvA = callsOf("SetPlayerVelocity")
T.frames(60)
T.check(callsOf("SetPlayerVelocity") == pvA, "player not pulled when the option is off")
T.check(H.P(1).damage > 0, "low damage applied in the core by default")
T.runUntil(function() return count(sh().g) == 0 end, 400)
H.P(1).pos = V(0, 0, 0)

-- 8. out of ammo ---------------------------------------------------------------
H.reg["savegame.mod.pullplayer"] = true
H.P(1).ammo.singularity = 1
T.frames(40)
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(40)
local spawns = callsOf("Spawn")
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(3)
T.check(callsOf("Spawn") == spawns, "no throw with zero ammo")
T.check(H.P(1).ammo.singularity == 0, "ammo is 0")
T.check(T.hasText("Out of grenades"), "HUD says 'Out of grenades'")
T.runUntil(function() return count(sh().g) == 0 end, 400)

-- 9. max alive grenades ------------------------------------------------------
H.P(1).ammo.singularity = 20
H.reg["savegame.mod.impact"] = false
H.reg["savegame.mod.duration"] = 8.0
H.P(1).pitch = 60   -- throw up so the grenades fly long
for i = 1, 7 do
	T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(36)
end
local alive = 0
for _, gg in pairs(sh().g) do if gg.phase ~= "done" then alive = alive + 1 end end
T.check(alive <= 4, "at most 4 grenades alive (" .. alive .. ")")
T.check(H.P(1).ammo.singularity == 20 - alive, "ammo only spent on real throws")
T.check(T.hasText("Too many singularities"), "HUD warns about the limit")
H.P(1).pitch = 0
T.runUntil(function() return count(sh().g) == 0 end, 2000)
T.check(count(sh().g) == 0, "all grenades finished")

-- 10. unlimited ammo (sandbox) ------------------------------------------------
H.reg["level.unlimitedammo"] = true
H.P(1).ammo.singularity = 9999
T.frames(40)
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(2)
T.check(H.P(1).ammo.singularity == 9999, "sandbox ammo is not spent")
T.runUntil(function() return count(sh().g) == 0 end, 1200)

-- 11. variable frame rates -------------------------------------------------
H.reg["savegame.mod.duration"] = 3.0
T.press("usetool"); T.frames(1, 1 / 30); T.release("usetool")
T.runUntil(function() return count(sh().g) == 0 end, 900, 1 / 30)
T.check(count(sh().g) == 0, "full cycle at 30 fps")
T.press("usetool"); T.frames(1, 1 / 144); T.release("usetool")
T.runUntil(function() return count(sh().g) == 0 end, 3000, 1 / 144)
T.check(count(sh().g) == 0, "full cycle at 144 fps")

-- 12. Russian UI -------------------------------------------------------------
H.reg["options.language"] = 7
T.frames(2)
T.check(T.hasText("Удерживайте ЛКМ"), "HUD hint in Russian")
H.reg["options.language"] = 0

-- 13. switching tools mid-charge cancels the throw ---------------------------
local sp0 = callsOf("Spawn")
T.press("usetool"); T.frames(10); T.hold("usetool"); T.select("sledge"); T.frames(5); T.release("usetool"); T.frames(3)
T.check(callsOf("Spawn") == sp0, "switching tool while charging cancels the throw")
T.select("singularity")

-- 14. options.lua --------------------------------------------------------------
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Singularity Grenade"), "options: title")
T.check(H.uiButtonsSeen["Close"] and H.uiButtonsSeen["Reset to defaults"], "options: close and reset buttons")
H.uiClicks["1.5 s after stopping"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.impact"] == true, "options: trigger toggled to impact")
H.uiSliderSet[1] = 260 -- radius slider to the right end
T.drawOptions(1)
T.check(math.abs((H.reg["savegame.mod.radius"] or 0) - 20) < 0.01, "options: radius slider sets 20 m")
H.uiSliderSet[4] = 0 -- ammo slider to the left end
T.drawOptions(1)
T.check(H.reg["savegame.mod.ammo"] == 1, "options: ammo slider sets 1")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.radius"] == 8 and H.reg["savegame.mod.impact"] == false and H.reg["savegame.mod.ammo"] == 5, "options: reset restores defaults")
H.uiClicks["Close"] = true
T.drawOptions(1)
local closed = false
for _, l in ipairs(H.log) do if l:find("Menu() called", 1, true) then closed = true end end
T.check(closed, "options: Close calls Menu()")
H.reg["options.language"] = 7
T.drawOptions(1)
T.check(T.hasText("Гравитационная граната"), "options: Russian title")
H.reg["options.language"] = 0

-- 15. cross-mod requests (used by the camera drone) ----------------------------
T.check(H.reg["level.singularity_grenade.available"] == true, "grenade mod announces itself in the registry")
T.runUntil(function() return count(sh().g) == 0 end, 2000)
local ammoBefore = H.P(1).ammo.singularity
local k = "level.singularity_grenade.req.1"
H.reg[k .. ".x"] = 3.0; H.reg[k .. ".y"] = 6.0; H.reg[k .. ".z"] = -8.0
H.reg[k .. ".vx"] = 0.0; H.reg[k .. ".vy"] = -1.0; H.reg[k .. ".vz"] = 0.0
H.reg[k .. ".owner"] = 1
H.reg["level.singularity_grenade.reqcount"] = 1
T.frames(2)
local rid, rg = firstGrenade()
T.check(rid ~= nil and math.abs(rg.x - 3) < 0.5 and rg.phase == "fly", "registry request spawns a grenade at the given point")
T.check(H.reg[k .. ".x"] == nil, "request keys are cleared")
T.check(H.P(1).ammo.singularity == ammoBefore, "requested grenades do not spend the player's ammo")
T.frames(2)
T.check(count(sh().g) == 1, "a request is processed only once")
T.runUntil(function() return count(sh().g) == 0 end, 1500)
T.check(count(sh().g) == 0, "requested grenade completes its cycle")
