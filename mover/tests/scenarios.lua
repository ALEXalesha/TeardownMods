-- Harness scenarios for the Mover.
local function V(x, y, z) return { x, y, z } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function srv() return T.env().server end
local function cli() return T.cenv().client end
local function sh() return T.sharedOf() end
local function callsOf(n) return H.calls[n] or 0 end
local function me() return sh().pl[1] end
local function validShapes(b)
	local o = {}
	for _, sh in ipairs(H.bodies[b].shapes) do if H.shapes[sh].valid then o[#o + 1] = sh end end
	return o
end

T.budget("ConstrainPosition", 4)
T.budget("GetShapeMaterialAtIndex", 2600 * 2 + 50)
T.budget("DrawShapeBox", 2600)
T.budget("QueryRaycast", 2)
T.budget("DrawBodyOutline", 40)

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -16
local crate = H.addBody { pos = V(0, 0.25, -5), mass = 30 }
local heavy = H.addBody { pos = V(6, 0.6, -6), mass = 1200, half = V(1, 0.6, 2) }
local wheel = H.addBody { pos = V(7, 0.4, -4), mass = 40 }
local vehicle = H.addVehicle(heavy, { wheel })

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.mover ~= nil and H.P(1).enabled.mover, "tool registered and enabled")

T.select("mover")
T.frames(2)
T.check(cli().aimBody == crate, "crate is aimed and outlined")
T.check(T.hasText("hold to grab"), "controls panel shown")

-- grab and carry
T.press("usetool"); T.frames(2)
T.check(me().held == crate, "LMB grabs the crate")
T.check(T.soundsPlayed("grab.ogg") == 1, "grab sound")
T.check(H.reg["game.input.locktool"] == true, "tool switching locked while holding")
H.P(1).pitch = 15
for i = 1, 60 do T.hold("usetool"); T.frames(1) end
T.check(H.bodies[crate].pos[2] > 1.5, string.format("crate follows the view up (y=%.2f)", H.bodies[crate].pos[2]))
T.check(T.hasText("Holding at"), "HUD shows the holding distance")

-- wheel pushes it away
local d0 = me().dist
H.P(1).values = { mousewheel = 3 }
T.hold("usetool"); T.frames(1)
H.P(1).values = { mousewheel = 0 }
T.check(me().dist > d0 + 1, string.format("wheel pushes: %.1f -> %.1f m", d0, me().dist))

-- smooth rotation with Q
local r0 = { H.bodies[crate].rot[1], H.bodies[crate].rot[2], H.bodies[crate].rot[3], H.bodies[crate].rot[4] }
T.press("q"); T.hold("usetool"); T.frames(1)
for i = 1, 30 do T.hold("q"); T.hold("usetool"); T.frames(1) end
T.release("q"); T.hold("usetool"); T.frames(2)
local r1 = H.bodies[crate].rot
local dq = math.abs(r1[1] - r0[1]) + math.abs(r1[2] - r0[2]) + math.abs(r1[3] - r0[3]) + math.abs(r1[4] - r0[4])
T.check(dq > 0.05, "Q rotates the held body")
local h = srv().held[1]
T.check(h and h.spin[1] == 0, "spin stops when Q is released")

-- release
T.release("usetool"); T.frames(2)
T.check(me().held == 0, "LMB release drops it")
T.check(T.soundsPlayed("release.ogg") == 1, "release sound")
T.check(len(H.bodies[crate].vel) <= 10.01, "dropped body speed capped")

-- freeze / move frozen / undo / unfreeze
T.frames(80)
H.P(1).pitch = -16
H.bodies[crate].pos = V(0, 0.25, -5)
H.bodies[crate].vel = V(0, 0, 0)
T.frames(1)
T.press("t"); T.frames(2)
T.check(H.bodies[crate].dynamic == false and sh().frozen[crate] == true, "T freezes the aimed body")
T.check(T.soundsPlayed("freeze.ogg") == 1, "freeze sound")
local before = { H.bodies[crate].pos[1], H.bodies[crate].pos[2], H.bodies[crate].pos[3] }
T.press("usetool"); T.frames(1)
H.P(1).pitch = 10
for i = 1, 20 do T.hold("usetool"); T.frames(1) end
T.check(len(sub(H.bodies[crate].pos, before)) > 0.5, "frozen body moves with SetBodyTransform")
T.check(H.bodies[crate].dynamic == false, "still frozen while carried")
T.release("usetool"); T.frames(2)
T.press("u"); T.frames(2)
T.check(len(sub(H.bodies[crate].pos, before)) < 0.01, "U restores the position before the move")
T.check(T.soundsPlayed("undo.ogg") == 1, "undo sound")
H.P(1).pitch = -16
T.frames(1)
T.press("t"); T.frames(2)
T.check(H.bodies[crate].dynamic == true and sh().frozen[crate] == nil, "T again unfreezes")

-- clone and undo the clone
local creates = callsOf("CreateShape")
local nb0 = H.nextHandle
T.press("p"); T.frames(2)
T.check(callsOf("CreateShape") == creates + #H.bodies[crate].shapes, "clone creates one shape per source shape")
T.check(callsOf("CopyShapeContent") >= 1, "clone copies voxel content")
local clone = nil
for hnd, b in pairs(H.bodies) do if hnd > nb0 and b.valid and #b.shapes > 0 and b.dynamic and b.spawnedXml then clone = hnd end end
T.check(clone ~= nil, "clone body exists")
T.check(clone and len(sub(H.bodies[clone].pos, H.bodies[crate].pos)) > 0.5, "clone placed next to the original")
T.press("u"); T.frames(2)
T.check(clone and not H.bodies[clone].valid, "undo removes the clone")

-- vehicles: grab moves the main body, clone refused
H.P(1).pitch = -10
H.P(1).yaw = -45
T.frames(1)
local aimed = cli().aimBody
T.press("p"); T.frames(2)
T.check(T.hasText("Not for vehicles") or aimed == 0, "cloning a vehicle is refused")
T.env().server.grab(1, wheel, 7, 0.4, -4, 8)
T.frames(2)
T.check(me().held == heavy, "grabbing a wheel holds the vehicle's main body")
T.env().server.release(1)
H.P(1).yaw = 0
H.P(1).pitch = -16
T.frames(2)

-- second player cannot take a held body
H.addPlayer(2, V(2, 0, 0))
T.frames(1)
T.press("usetool"); T.frames(2)
T.env().server.grab(2, crate, 0, 0.25, -5, 5)
T.frames(1)
T.check(sh().pl[2] and sh().pl[2].msg == "taken", "second player gets 'taken'")
T.release("usetool"); T.frames(2)

-- scale x2 then x0.5
local s0 = H.bodies[crate].shapes[1]
local sx0 = select(1, H.API.GetShapeSize(s0))
T.press("m"); T.frames(1)
T.check(me().job >= 0, "scale job started")
local f = T.runUntil(function() return me().job < 0 end, 600)
T.check(f ~= nil, "scale job finished (" .. tostring(f) .. " frames)")
T.check(not H.bodies[crate].valid, "old body replaced")
local big = nil
for hnd, b in pairs(H.bodies) do
	if b.valid and b.dynamic and #validShapes(hnd) == 1 and hnd > crate and b.spawnedXml then
		local sx = select(1, H.API.GetShapeSize(validShapes(hnd)[1]))
		if sx == sx0 * 2 then big = hnd end
	end
end
T.check(big ~= nil, "new body has shapes twice the size")
T.check(big and H.shapes[validShapes(big)[1]].layer == 1, "collision restored after scaling")
if big then
	H.bodies[big].pos = V(0, 1, -5)
	T.frames(1)
	T.env().server.scale(1, big, 0.5)
	T.runUntil(function() return me().job < 0 end, 600)
	local small = nil
	for hnd, b in pairs(H.bodies) do
		if b.valid and b.dynamic and #validShapes(hnd) == 1 and hnd > big and b.spawnedXml then
			if select(1, H.API.GetShapeSize(validShapes(hnd)[1])) == sx0 then small = hnd end
		end
	end
	T.check(small ~= nil, "x0.5 brings it back to the original size")
end

-- too big to scale
local huge = H.addBody { pos = V(-3, 0.5, -5), mass = 50 }
H.shapes[H.bodies[huge].shapes[1]].size = { 100, 100, 100 }
T.env().server.scale(1, huge, 2)
T.frames(2)
T.check(me().msg == "toobig", "big objects are refused")
T.check(T.hasText("Too big"), "HUD message 'Too big'")

-- clone disabled in options
H.reg["savegame.mod.clone"] = false
T.env().server.clone(1, huge)
T.frames(2)
T.check(me().msg == "clonedisabled", "clone respects the option")
H.reg["savegame.mod.clone"] = true

-- snapped rotation
H.reg["savegame.mod.rotsnap"] = 45.0
local c2 = H.addBody { pos = V(0, 0.25, -5), mass = 10 }
T.frames(1)
local target = cli().aimBody
T.press("usetool"); T.frames(2)
local ticks = T.soundsPlayed("tick.ogg")
T.press("r"); T.hold("usetool"); T.frames(2)
T.check(T.soundsPlayed("tick.ogg") == ticks + 1, "snapped rotation step plays a tick")
T.release("usetool"); T.frames(2)
H.reg["savegame.mod.rotsnap"] = 0.0

-- undo stack empty message
srv().undo[1] = {}
T.press("u"); T.frames(2)
T.check(me().msg == "undoempty", "empty undo stack reports it")

-- Russian panel
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("заморозить"), "controls panel in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Mover"), "options: title")
H.uiClicks["Off (smooth)"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.rotsnap"] == 15, "options: rotation snap 15")
H.uiClicks["Off"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.possnap"] == 0.1, "options: position snap 0.1")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.rotsnap"] == 0 and H.reg["savegame.mod.maxdist"] == 40, "options: reset")
