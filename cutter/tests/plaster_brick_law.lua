-- Plaster over brick law (independent review 16.10.2026). The material was read once at the surface
-- point, so plaster in front of brick gave the soft radius only (r1 = 0) for the whole depth and the
-- brick behind it was never cut. The material must be read again at each depth step, and the
-- "Cuts concrete and brick" switch must still stop the saw at the brick.
local function V(x, y, z) return { x, y, z } end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
H.addPlayer(1, V(0, 0, 0))
-- wall A in front (z < 0): thin plaster skin (what the ray hits) over 0.3 m of brick cubes
H.addStaticBox(V(-1, 0.8, -3.1), V(1, 2.2, -3.0), "plaster")
H.addCubes(V(-1, 0.8, -3.4), V(1, 2.2, -3.1), 0.1, "masonry")
-- wall B behind (z > 0), the same build
H.addStaticBox(V(-1, 0.8, 3.0), V(1, 2.2, 3.1), "plaster")
H.addCubes(V(-1, 0.8, 3.1), V(1, 2.2, 3.4), 0.1, "masonry")
local function brickCut(sign)
	local n = 0
	for _, c in ipairs(H.cubes) do if not c.alive and c.c[3] * sign > 0 then n = n + 1 end end
	return n
end
local function cut(yaw0)
	H.P(1).yaw = yaw0; H.P(1).pitch = -5
	T.press("usetool"); T.frames(1)
	local started = T.env().server.players[1].holding
	for i = 1, 24 do H.P(1).yaw = yaw0 - i * 0.5; T.hold("usetool"); T.frames(1) end
	T.release("usetool"); T.frames(1)
	T.runUntil(function() return count(T.sharedOf().jobs) == 0 end, 900)
	return started
end
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("cutter")
T.frames(2)
local h0 = #H.holes
T.check(cut(6), "press on the plaster starts a cut")
local medium = 0
for i = h0 + 1, #H.holes do if H.holes[i].r1 > 0 then medium = medium + 1 end end
T.check(#H.holes > h0, "holes made: " .. (#H.holes - h0))
T.check(medium > 0, "holes with a medium (brick) radius: " .. medium)
T.check(brickCut(-1) > 0, "brick behind the plaster cut (" .. brickCut(-1) .. " brick cubes removed)")
-- with masonry off the plaster is still cut but the brick behind it is not
H.reg["savegame.mod.masonry"] = false
local h1 = #H.holes
T.check(cut(186), "press on the second wall starts a cut")
local medium2 = 0
for i = h1 + 1, #H.holes do if H.holes[i].r1 > 0 then medium2 = medium2 + 1 end end
T.check(#H.holes > h1, "masonry off: the plaster is still cut (" .. (#H.holes - h1) .. " holes)")
T.check(medium2 == 0 and brickCut(1) == 0, "masonry off: no brick cut behind the plaster (" .. medium2 .. " medium holes, " .. brickCut(1) .. " cubes)")
H.reg["savegame.mod.masonry"] = true
