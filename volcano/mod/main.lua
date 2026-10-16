#version 2
-- Volcano / Вулкан
-- Magma core tool. LMB on the ground: a volcano grows there in a few seconds (seven
-- rock layers rise out of the ground one after another), then erupts in phases:
-- rumble and smoke, lava bombs (glowing rocks thrown in arcs that punch craters and
-- start fires; some roll down the slopes as lava flows), and a final blast that blows
-- the summit off. Then it cools down and stays as a dead cone.
-- RMB during the eruption: final blast now. R (no eruption running): remove the cones.
--
-- Server: cone layers (spawned static, raised with SetBodyTransform), bombs (dynamic
-- bodies), holes, fires, explosions, glow of the server-spawned shapes, tremors.
-- Client: sounds, smoke/sparks/ash particles, light, camera shake, HUD.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "volcano"
local LAYERS = 7
local CONE_W, CONE_H = 73, 26          -- voxels (cone vox: 73 x 26 x 73 in Teardown axes)
local CRATER_D = 5                     -- crater depth in voxels
local LAYER_TIME = 0.7                 -- s per layer rising
local GROW_TIME = LAYERS * LAYER_TIME
local MAX_BOMBS = 40
local MAX_CONES = 4
local HOLES_PER_UPDATE = 6
local FIRES_PER_UPDATE = 6
local BLAST_RADII = 2.5               -- the final blast levels everything within this many cone radii
local BLAST_SPEED = 30                -- m/s, how fast the blast front runs out
local BLAST_DENSITY = 0.12            -- destruction probes per m^2
local BLAST_R2_BUDGET = 900           -- per physics step: sum of hole radius^2
local BLAST_HOLES = 40
local BLAST_PROBES = 100
local TREMOR_PER_UPDATE = 20
local COOL_TIME = 15
local CONE_FILES = { "MOD/vox/cone_1.vox", "MOD/vox/cone_2.vox", "MOD/vox/cone_3.vox", "MOD/vox/cone_4.vox",
	"MOD/vox/cone_5.vox", "MOD/vox/cone_6.vox", "MOD/vox/cone_7.vox" }
local SIZES = { 3, 4, 6 }              -- vox scale per size setting (voxel = 0.1 * scale m)

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function rnd(a, b) return a + (b - a) * math.random() end
local function smooth(a, b, x) local t = clamp((x - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getI(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetInt(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		size = math.floor(clamp(getI("size", 2), 1, 3)),
		strength = clamp(getF("strength", 1), 0.5, 2),
		duration = clamp(getF("duration", 45), 20, 120),
		fire = getB("fire", true),
		ash = getB("ash", true),
		debug = getB("debugline", false),   -- hidden diagnostics, off by default since 10.10 (new key: old saves may hold debug=true)
	}
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Volcano", "Вулкан"), "MOD/prefab/tool.xml", 6)
	server.v = nil
	server.cones = {}          -- every cone body ever raised (for R)
	server.coneGroups = {}     -- the layer bodies of each volcano, oldest first (MAX_CONES kept)
	server.bombs = {}
	shared.v = { phase = "idle", t = 0, T = 1, x = 0, y = 0, z = 0, top = 0, R = 0, k = 0, n = 0, layers = 0,
		launchN = 0, impN = 0, ix = 0, iy = 0, iz = 0, blastN = 0, bombs = {}, msg = "", mn = 0 }
end

local function message(kind)
	shared.v.msg = kind
	shared.v.mn = shared.v.mn + 1
end

function server.tick(dt)
	for p in PlayersAdded() do SetToolEnabled(TOOL, true, p) end
	for p in Players() do
		if GetPlayerTool(p) == TOOL and GetPlayerCanUseTool(p) and GetPlayerVehicle(p) == 0 then
			if InputPressed("usetool", p) then server.place(p) end
			if InputPressed("grab", p) and server.v and (server.v.phase == "rumble" or server.v.phase == "erupt") then server.blast(server.v) end
		end
	end
end

function server.place(p)
	if server.v then message("busy") return end
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	QueryRejectPlayer(p)
	QueryRequire("physical static")
	local hit, dist, n = QueryRaycast(eye.pos, fwd, 150)
	if not hit or n[2] < 0.5 then message("aim") return end
	local s = readSettings()
	local scale = SIZES[s.size]
	local vs = 0.1 * scale
	local R = CONE_W * vs * 0.5
	local g = VecAdd(eye.pos, VecScale(fwd, dist))
	-- keep the cone away from the player: at least its radius plus 4 m
	local flat = Vec(g[1] - eye.pos[1], 0, g[3] - eye.pos[3])
	local fl = VecLength(flat)
	if fl < R + 4 then
		local dir = fl > 0.1 and VecScale(flat, 1 / fl) or VecNormalize(Vec(fwd[1], 0, fwd[3]))
		local probe = VecAdd(Vec(eye.pos[1], eye.pos[2] + 30, eye.pos[3]), VecScale(dir, R + 4))
		QueryRequire("physical static")
		local h2, d2 = QueryRaycast(probe, Vec(0, -1, 0), 80)
		if not h2 then message("aim") return end
		g = VecAdd(probe, Vec(0, -d2, 0))
	end
	-- keep at most MAX_CONES cones: drop the oldest one, not all of them (review 16.10: the 5th volcano
	-- deleted all four kept cones)
	server.dropOldCones(MAX_CONES - 1)
	local group = {}
	server.coneGroups[#server.coneGroups + 1] = group
	local v = {
		phase = "grow", t = 0, s = s, scale = scale, vs = vs, R = R, ground = g, click = VecCopy(g), owner = p,
		rot = QuatEuler(0, rnd(0, 360), 0), layers = {}, offset = nil, bombAcc = 0,
		top = VecAdd(g, Vec(0, (CONE_H - CRATER_D) * vs - 0.3 * vs * 4, 0)),
		rumbleT = s.duration * 0.25, eruptT = s.duration * 0.75, tracked = {}, cursor = 1, scanT = 0,
		glowT = 0, glow = 0.2, group = group,
	}
	server.v = v
	local sv = shared.v
	sv.phase = "grow"
	sv.t = 0
	sv.T = GROW_TIME
	sv.x, sv.y, sv.z = g[1], g[2], g[3]
	sv.top = v.top[2]
	sv.R = R
	sv.k = 0
	sv.n = sv.n + 1
	sv.layers = 0
	server.clearFootprint(v)
end

-- players and loose bodies standing where the cone will be are pushed out and up
function server.clearFootprint(v)
	local g, R = v.ground, v.R
	for p in Players() do
		local pp = GetPlayerTransform(p).pos
		local d = Vec(pp[1] - g[1], 0, pp[3] - g[3])
		local l = VecLength(d)
		if l < R + 1 then
			local out = l > 0.1 and VecScale(d, 1 / l) or Vec(1, 0, 0)
			SetPlayerVelocity(VecAdd(VecScale(out, 9), Vec(0, 6, 0)), p)
		end
	end
	QueryRequire("physical dynamic")
	local list = QueryAabbBodies(VecSub(g, Vec(R, 1, R)), VecAdd(g, Vec(R, CONE_H * v.vs, R)))
	for i = 1, math.min(#list, 60) do
		local b = list[i]
		if GetBodyPlayer(b) == 0 then
			local bp = GetBodyTransform(b).pos
			local d = Vec(bp[1] - g[1], 0, bp[3] - g[3])
			local l = VecLength(d)
			local out = l > 0.1 and VecScale(d, 1 / l) or Vec(1, 0, 0)
			SetBodyVelocity(b, VecAdd(VecScale(out, 8), Vec(0, 7, 0)))
		end
	end
end

-- raise layer k: spawned below its place, then lifted into it over LAYER_TIME
-- Where does the game put a spawned vox relative to its spawn transform? Not documented, and two
-- assumptions were wrong in the game. So: a probe of the bottom cone layer is spawned and its world
-- bounds are read (GetShapeBounds, as the game's spawn menu does). Two lessons from the game:
-- bounds cover only the FILLED voxels (each layer model is full cone size but holds one height
-- band - correcting every layer by its own bounds bottom flattened the cone into a pancake), and
-- a just-spawned shape may not have valid bounds yet - so the probe is read over several ticks.
local LAYER_VOX = math.ceil(CONE_H / LAYERS)     -- voxel rows per layer

local function validBounds(mn, mx)
	return mx[1] - mn[1] > 0.05 and mx[2] - mn[2] > 0.05 and mx[3] - mn[3] > 0.05
end

local function shapeList(ents)
	local out = {}
	for i = 1, #ents do if GetEntityType(ents[i]) == "shape" then out[#out + 1] = ents[i] end end
	return out
end

-- start the probe (once per volcano)
function server.startProbe(v)
	v.probeAt = Transform(VecAdd(v.ground, Vec(0, 150, 0)), v.rot)
	v.probeEnts = Spawn("<body dynamic='false' tags='volcano'><vox file='" .. CONE_FILES[1] .. "' scale='" .. v.scale .. "'/></body>", v.probeAt, true)
	v.probeTries = 0
end

-- read the probe; true when the offset is known (measured, or the fallback after 20 ticks)
function server.readProbe(v)
	if v.offLocal then return true end
	if not v.probeEnts then server.startProbe(v) end
	v.probeTries = v.probeTries + 1
	for _, sh in ipairs(shapeList(v.probeEnts)) do
		local mn, mx = GetShapeBounds(sh)
		if validBounds(mn, mx) then
			local bottom = Vec((mn[1] + mx[1]) * 0.5, mn[2], (mn[3] + mx[3]) * 0.5)
			v.offLocal = TransformToLocalVec(v.probeAt, VecSub(bottom, v.probeAt.pos))
			v.measured = true
		end
	end
	if not v.offLocal and v.probeTries >= 20 then
		v.offLocal = Vec(0, 0, 0)                       -- fallback: spawn point = bottom centre
		v.measured = false
	end
	if v.offLocal then
		for i = 1, #v.probeEnts do if GetEntityType(v.probeEnts[i]) == "body" then Delete(v.probeEnts[i]) end end
	end
	return v.offLocal ~= nil
end

function server.spawnLayer(v, k)
	local want = VecAdd(v.ground, Vec(0, -0.3 * v.vs * 4, 0))         -- bottom centre of the cone, sunk a little
	v.wantBottom = want
	local xml = "<body dynamic='false' tags='volcano'><vox file='" .. CONE_FILES[k] .. "' scale='" .. v.scale .. "'/></body>"
	-- every layer model has the full cone size, so every layer is spawned with the same transform
	local t = Transform(VecSub(want, QuatRotateVec(v.rot, v.offLocal)), v.rot)
	local ents = Spawn(xml, t, true)
	local body = 0
	for i = 1, #ents do if GetEntityType(ents[i]) == "body" and body == 0 then body = ents[i] end end
	if body == 0 then return end
	local layer = { body = body, shapes = shapeList(ents), t = LAYER_TIME, drop = 0, k = k }
	v.layers[#v.layers + 1] = layer
	server.cones[#server.cones + 1] = body
	if v.group then v.group[#v.group + 1] = body end
	shared.v.layers = #v.layers
end

local function layerBounds(layer)
	local mn, mx = Vec(1e9, 1e9, 1e9), Vec(-1e9, -1e9, -1e9)
	local any = false
	for _, sh in ipairs(layer.shapes) do
		if IsHandleValid(sh) then
			local a, b = GetShapeBounds(sh)
			if validBounds(a, b) then
				any = true
				for k = 1, 3 do mn[k] = math.min(mn[k], a[k]) mx[k] = math.max(mx[k], b[k]) end
			end
		end
	end
	return mn, mx, any
end

-- smoke, lava, crater light and bombs come from where the cone really stands (its world bounds,
-- as soon as they are valid); until then from the intended place
function server.anchorFromCone(v)
	local mn, mx = Vec(1e9, 1e9, 1e9), Vec(-1e9, -1e9, -1e9)
	local n = 0
	local per = {}
	for i = 1, #v.layers do
		local a, b, ok = layerBounds(v.layers[i])
		if ok then
			n = n + 1
			for k = 1, 3 do mn[k] = math.min(mn[k], a[k]) mx[k] = math.max(mx[k], b[k]) end
			local wantY = v.wantBottom[2] + (v.layers[i].k - 1) * LAYER_VOX * v.vs
			per[#per + 1] = string.format("%d %.1f/%.1f", v.layers[i].k, wantY - v.click[2], a[2] - v.click[2])
		end
	end
	local sv = shared.v
	local bt = (#v.layers > 0) and GetBodyTransform(v.layers[1].body).pos or v.click
	if n == 0 then
		sv.dbg = string.format("volcano: click %.1f %.1f %.1f | cone body %.1f %.1f %.1f | cone bounds not valid yet%s",
			v.click[1], v.click[2], v.click[3], bt[1], bt[2], bt[3], v.offLocal and "" or " | probe waiting")
		return
	end
	local cx, cz = (mn[1] + mx[1]) * 0.5, (mn[3] + mx[3]) * 0.5
	v.centre = Vec(cx, v.click[2], cz)
	v.ground = Vec(cx, v.ground[2], cz)
	if n == #v.layers and #v.layers == LAYERS then
		v.top = Vec(cx, mx[2] - CRATER_D * v.vs, cz)          -- the top layer's top is the rim
	else
		v.top = Vec(cx, (v.wantBottom or v.ground)[2] + (CONE_H - CRATER_D) * v.vs, cz)
	end
	sv.x, sv.z = cx, cz
	sv.top = v.top[2]
	sv.dbg = string.format("volcano: click %.1f %.1f %.1f | cone body %.1f %.1f %.1f | cone bounds centre %.1f %.1f %.1f | off %.2f m | cone height %.1f m (want %.1f) | layer want/actual y: %s%s",
		v.click[1], v.click[2], v.click[3], bt[1], bt[2], bt[3], cx, (mn[2] + mx[2]) * 0.5, cz,
		math.sqrt((cx - v.click[1]) ^ 2 + (cz - v.click[3]) ^ 2), mx[2] - mn[2], CONE_H * v.vs, table.concat(per, ", "),
		v.measured and "" or " | probe: no valid bounds, fallback")
end

function server.update(dt)
	server.updateBombs(dt)
	local v = server.v
	if not v then return end
	v.t = v.t + dt
	local sv = shared.v
	sv.t = v.t
	if v.phase == "grow" then
		if server.readProbe(v) then
			v.growT = (v.growT or 0) + dt
			local want = math.min(LAYERS, math.floor(v.growT / LAYER_TIME) + 1)
			if #v.layers < want then server.spawnLayer(v, #v.layers + 1) end
		end
		server.anchorFromCone(v)
		sv.k = 0.1
		if (v.growT or 0) >= GROW_TIME + 0.2 then server.setPhase(v, "rumble", v.rumbleT) end
	elseif v.phase == "rumble" then
		if v.t < 1 then server.anchorFromCone(v) end
		sv.k = 0.2 + 0.4 * smooth(0, v.rumbleT, v.t)
		server.tremors(v, dt, sv.k * 0.6)
		server.setGlow(v, dt, 0.3 + 0.7 * sv.k)
		if v.t >= v.rumbleT then server.setPhase(v, "erupt", v.eruptT) end
	elseif v.phase == "erupt" then
		local s = v.s
		sv.k = 0.7 + 0.3 * math.sin(v.t * 1.3) ^ 2
		server.tremors(v, dt, sv.k)
		server.setGlow(v, dt, 1.4)
		v.bombAcc = v.bombAcc + dt * 6 * s.strength * (0.6 + 0.8 * sv.k)
		if v.bombAcc >= 1 then
			v.bombAcc = v.bombAcc - 1
			server.launch(v, math.random() < 0.25)
		end
		if v.t >= v.eruptT then server.blast(v) end
	elseif v.phase == "cool" then
		for i = 1, 2 do
			if (v.burst or 0) > 0 then
				v.burst = v.burst - 1
				server.launch(v, false)
			end
		end
		server.blastWork(v, dt)
		sv.k = 0.6 * (1 - smooth(0, COOL_TIME, v.t))
		server.setGlow(v, dt, 0.15 + 1.2 * (1 - smooth(0, COOL_TIME, v.t)))
		if v.t >= COOL_TIME and not v.blastR then
			server.v = nil
			sv.phase = "idle"
			sv.k = 0
		end
	end
end

function server.setPhase(v, phase, T)
	v.phase = phase
	v.t = 0
	local sv = shared.v
	sv.phase = phase
	sv.t = 0
	sv.T = T
end

-- glowing lava in the cone: emissive scale of the server-spawned layer shapes, updated 4x a second
function server.setGlow(v, dt, target)
	v.glowT = v.glowT - dt
	if v.glowT > 0 then return end
	v.glowT = 0.25
	v.glow = target
	for i = 1, #v.layers do
		local l = v.layers[i]
		for j = 1, #l.shapes do
			if IsHandleValid(l.shapes[j]) then SetShapeEmissiveScale(l.shapes[j], target) end
		end
	end
end

function server.tremors(v, dt, I)
	v.scanT = v.scanT - dt
	if v.scanT <= 0 then
		v.scanT = 1
		local g = v.ground
		local r = v.R * 3
		QueryRequire("physical dynamic")
		local found = QueryAabbBodies(VecSub(g, Vec(r, 5, r)), VecAdd(g, Vec(r, 20, r)))
		local list = {}
		for i = 1, #found do
			if GetBodyPlayer(found[i]) == 0 and not HasTag(found[i], "volcano_bomb") then list[#list + 1] = found[i] end
			if #list >= 150 then break end
		end
		v.tracked = list
		v.cursor = 1
	end
	local n = #v.tracked
	for k = 1, math.min(n, TREMOR_PER_UPDATE) do
		local b = v.tracked[v.cursor]
		v.cursor = (v.cursor % n) + 1
		if IsHandleValid(b) and IsBodyDynamic(b) then
			local mass = GetBodyMass(b)
			if mass > 0 then
				local massK = clamp(600 / mass, 0.05, 1)
				ApplyBodyImpulse(b, GetBodyTransform(b).pos, VecScale(Vec(rnd(-1, 1), rnd(0, 1.2), rnd(-1, 1)), mass * 0.9 * I * massK))
			end
		end
	end
end

-- a lava bomb: thrown in an arc from the crater; a flow rolls down the slope from the rim
function server.launch(v, flow)
	local alive = 0
	for i = 1, #server.bombs do if not server.bombs[i].dead then alive = alive + 1 end end
	if alive >= MAX_BOMBS then return end
	local s = v.s
	local a = rnd(0, 6.2832)
	local out = Vec(math.cos(a), 0, math.sin(a))
	local pos, vel
	local k = math.sqrt(s.strength) * (0.7 + 0.3 * v.scale / 4)
	if flow then
		pos = VecAdd(v.top, VecAdd(VecScale(out, 6 * v.vs), Vec(0, 0.6, 0)))   -- inside the crater rim
		vel = VecAdd(VecScale(out, rnd(3, 5)), Vec(0, 2, 0))
	else
		pos = VecAdd(v.top, Vec(0, 1.0, 0))
		vel = VecAdd(VecScale(out, rnd(4, 11) * k), Vec(0, rnd(14, 22) * k, 0))
	end
	local bscale = clamp(v.scale / 2, 1.5, 3)
	local ents = Spawn("<body dynamic='true'><vox file='MOD/vox/bomb.vox' scale='" .. bscale .. "'/></body>", Transform(pos, QuatEuler(rnd(0, 360), rnd(0, 360), 0)))
	for i = 1, #ents do
		if GetEntityType(ents[i]) == "body" then
			local b = ents[i]
			SetTag(b, "volcano_bomb")
			SetBodyVelocity(b, vel)
			SetBodyAngularVelocity(b, Vec(rnd(-4, 4), rnd(-4, 4), rnd(-4, 4)))
			server.bombs[#server.bombs + 1] = { body = b, shapes = GetBodyShapes(b), t = 0, prevVel = VecCopy(vel), flow = flow, landed = false, glow = 1, glowT = 0, burnT = 0 }
			if flow then v.lastFlow = pos else v.lastLaunch = pos end
			local sv = shared.v
			sv.launchN = sv.launchN + 1
			break
		end
	end
	server.syncBombs()
end

function server.syncBombs()
	local list = {}
	for i = 1, #server.bombs do
		local b = server.bombs[i]
		if not b.landed and not b.dead then list[#list + 1] = b.body end
	end
	shared.v.bombs = list
end

-- bombs in flight: a sudden stop is a landing: crater, fire; then they cool and go
function server.updateBombs(dt)
	local holes, fires, changed = 0, 0, false
	local v = server.v
	local s = v and v.s or readSettings()
	for i = #server.bombs, 1, -1 do
		local b = server.bombs[i]
		b.t = b.t + dt
		if not IsHandleValid(b.body) then
			table.remove(server.bombs, i)
			changed = true
		else
			if not b.landed then
				local vel = GetBodyVelocity(b.body)
				local hit = b.t > 0.3 and VecLength(VecSub(vel, b.prevVel)) > 6
				local settled = b.flow and b.t > 1.5 and VecLength(vel) < 1
				b.prevVel = vel
				-- a lava flow burns and breaks what it rolls through
				if b.flow and b.t > 0.5 and holes < HOLES_PER_UPDATE then
					b.burnT = b.burnT - dt
					if b.burnT <= 0 then
						b.burnT = 0.25
						local fp = GetBodyTransform(b.body).pos
						MakeHole(fp, 1.4, 0.7, 0, true)
						holes = holes + 1
						if s.fire and fires < FIRES_PER_UPDATE then SpawnFire(fp) fires = fires + 1 end
					end
				end
				if (hit or settled or b.t > 10) and holes < HOLES_PER_UPDATE then
					b.landed = true
					b.t = 0
					changed = true
					local pos = GetBodyTransform(b.body).pos
					local k = math.sqrt(s.strength)
					if not b.flow then
						-- a heavy glowing rock: a real crater, sometimes a small explosion
						MakeHole(pos, 2.6 * k, 2.0 * k, 1.0 * k, false)
						holes = holes + 1
						if math.random() < 0.33 then Explosion(pos, clamp(1.0 * k, 0.5, 2), v and v.owner or 0) end
						for p in Players() do
							local d = VecLength(VecSub(GetPlayerTransform(p).pos, pos))
							if d < 2.5 then ApplyPlayerDamage(p, 0.15 * k, "volcano", v and v.owner or 0) end
						end
					end
					if s.fire then
						-- fires around the impact, so they catch and spread
						for f = 1, 3 do
							if fires < FIRES_PER_UPDATE then
								SpawnFire(VecAdd(pos, Vec(rnd(-2, 2), rnd(0, 1), rnd(-2, 2))))
								fires = fires + 1
							end
						end
					end
					local sv = shared.v
					sv.impN = sv.impN + 1
					sv.ix, sv.iy, sv.iz = pos[1], pos[2], pos[3]
				end
			else
				-- cooling rock: the glow fades, after 20 s it is gone
				b.glowT = b.glowT - dt
				if b.glowT <= 0 then
					b.glowT = 0.5
					b.glow = math.max(0, 1 - b.t / 8)
					for j = 1, #b.shapes do if IsHandleValid(b.shapes[j]) then SetShapeEmissiveScale(b.shapes[j], b.glow) end end
				end
				if b.t > 20 then
					Delete(b.body)
					table.remove(server.bombs, i)
					changed = true
				end
			end
		end
	end
	if changed then server.syncBombs() end
end

-- the final blast: summit blown off, a ring of explosions, a burst of bombs
function server.blast(v)
	local s = v.s
	local k = s.strength
	local top = v.top
	local vs = v.vs
	Explosion(VecAdd(top, Vec(0, 1, 0)), clamp(2.5 + 1.5 * k, 0.5, 4), v.owner)
	for i = 1, 5 do
		local a = i / 5 * 6.2832
		Explosion(VecAdd(top, Vec(math.cos(a) * v.R * 0.3, -1, math.sin(a) * v.R * 0.3)), clamp(1.5 + k, 0.5, 4), v.owner)
	end
	local r = (CRATER_D + 4) * vs * clamp(0.7 + 0.3 * k, 0.8, 1.3)
	MakeHole(VecAdd(top, Vec(0, CRATER_D * vs * 0.5, 0)), r, r, r * 0.9, false)
	v.burst = math.floor(12 + 12 * k)    -- launched 2 per step during the cool-down
	-- the blast front: everything within BLAST_RADII cone radii is levelled over the next seconds
	v.blastR = BLAST_RADII * v.R * clamp(0.8 + 0.2 * k, 0.8, 1.2)
	v.front = 0
	v.queue = {}
	v.ringN = 0
	QueryRequire("physical dynamic")
	local list = QueryAabbBodies(VecSub(v.ground, Vec(v.blastR, 5, v.blastR)), VecAdd(v.ground, Vec(v.blastR, 30, v.blastR)))
	v.throw = {}
	for i = 1, math.min(#list, 200) do
		if GetBodyPlayer(list[i]) == 0 and not HasTag(list[i], "volcano") then v.throw[#v.throw + 1] = list[i] end
	end
	shared.v.blastN = shared.v.blastN + 1
	server.setPhase(v, "cool", COOL_TIME)
end

-- the blast worker: the front runs out, throws loose things, rings of explosions; probes in the
-- swept band find what stands there and punch holes (hard materials too near the cone)
function server.blastWork(v, dt)
	if not v.blastR then return end
	local s = v.s
	local g = v.ground
	if v.front < v.blastR then
		local r0 = v.front
		v.front = math.min(v.blastR, v.front + BLAST_SPEED * dt)
		local area = 3.1416 * (v.front * v.front - r0 * r0)
		v.queue[#v.queue + 1] = { r0 = r0, r1 = v.front, n = math.max(1, math.floor(area * BLAST_DENSITY + 0.5)) }
		-- loose bodies are thrown outwards as the front passes them
		local thrown = 0
		for i = #v.throw, 1, -1 do
			if thrown >= 30 then break end
			local b = v.throw[i]
			if not IsHandleValid(b) then
				table.remove(v.throw, i)
			else
				local bp = GetBodyTransform(b).pos
				local d = Vec(bp[1] - g[1], 0, bp[3] - g[3])
				local dl = VecLength(d)
				if dl <= v.front then
					table.remove(v.throw, i)
					thrown = thrown + 1
					if IsBodyDynamic(b) then
						local out = dl > 0.1 and VecScale(d, 1 / dl) or Vec(1, 0, 0)
						local sp = 30 * (1 - dl / v.blastR) + 6
						local m = GetBodyMass(b)
						ApplyBodyImpulse(b, bp, VecScale(VecNormalize(VecAdd(out, Vec(0, 0.5, 0))), m * sp * clamp(4000 / math.max(m, 1), 0.2, 1)))
					end
				end
			end
		end
		-- two rings of big explosions
		local rings = { 1.3 * v.R, 2.0 * v.R }
		local fired = 0
		while v.ringN < 16 and fired < 2 and v.front >= rings[math.floor(v.ringN / 8) + 1] do
			fired = fired + 1
			local a = (v.ringN % 8) / 8 * 6.2832 + math.floor(v.ringN / 8) * 0.39
			local rr = rings[math.floor(v.ringN / 8) + 1]
			Explosion(VecAdd(g, Vec(math.cos(a) * rr, 1.5, math.sin(a) * rr)), 4, v.owner)
			v.ringN = v.ringN + 1
		end
	end
	local budget, holes, probes, fires = BLAST_R2_BUDGET, 0, 0, 0
	while #v.queue > 0 and probes < BLAST_PROBES and holes < BLAST_HOLES and budget > 0 do
		local band = v.queue[1]
		band.n = band.n - 1
		if band.n <= 0 then table.remove(v.queue, 1) end
		probes = probes + 1
		local a = math.random() * 6.2832
		local rad = math.sqrt(rnd(band.r0 * band.r0, band.r1 * band.r1))
		if rad > v.R * 0.9 then
			local sample = VecAdd(g, Vec(math.cos(a) * rad, (math.random() < 0.6) and rnd(0.3, 4) or rnd(4, 14), math.sin(a) * rad))
			for i = 1, #v.layers do QueryRejectBody(v.layers[i].body) end
			QueryRequire("physical")
			local hit, point, n = QueryClosestPoint(sample, 3)
			if hit and not (n[2] > 0.7 and point[2] - g[2] < 1.0) then
				local k = clamp(rad / v.blastR, 0, 1)
				local r0 = (4.8 - 2.4 * k) * clamp(0.8 + 0.2 * s.strength, 0.8, 1.2)
				local r2 = (k < 0.5) and r0 * 0.5 or 0
				MakeHole(point, r0, r0 * 0.85, r2, true)
				budget = budget - r0 * r0
				holes = holes + 1
				if s.fire and holes % 3 == 0 and fires < FIRES_PER_UPDATE then SpawnFire(point) fires = fires + 1 end
			end
		end
	end
	if v.front >= v.blastR and #v.queue == 0 then v.blastR = nil end
end

-- delete the oldest cones until at most `keep` cones with a live layer are left
function server.dropOldCones(keep)
	local live = {}
	for _, g in ipairs(server.coneGroups) do
		local any = false
		for _, b in ipairs(g) do if IsHandleValid(b) then any = true end end
		if any then live[#live + 1] = g end
	end
	while #live > keep do
		for _, b in ipairs(table.remove(live, 1)) do
			if IsHandleValid(b) then Delete(b) end
		end
	end
	server.coneGroups = live
	local still = {}
	for _, b in ipairs(server.cones) do if IsHandleValid(b) then still[#still + 1] = b end end
	server.cones = still
end

-- R: remove the cones (only while nothing erupts)
function server.clear()
	if server.v then return end
	for i = 1, #server.cones do
		if IsHandleValid(server.cones[i]) then Delete(server.cones[i]) end
	end
	server.cones = {}
	server.coneGroups = {}
	message("cleared")
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.snd = {}
	for _, n in ipairs({ "launch", "impact", "blast", "place" }) do client.snd[n] = LoadSound("MOD/snd/" .. n .. ".ogg", 120) end
	client.loops = { grind = LoadLoop("MOD/snd/grind.ogg", 60), rumble = LoadLoop("MOD/snd/rumble.ogg", 120), roar = LoadLoop("MOD/snd/roar.ogg", 160) }
	client.anim = {}
	client.seen = nil
	client.flash = 0
	client.msgT = 0
	client.msg = ""
end

local MESSAGES = {
	busy = { "One volcano at a time", "Только один вулкан за раз" },
	aim = { "Aim at the ground", "Наведите на землю" },
	cleared = { "Cones removed", "Конусы убраны" },
}

function client.tick(dt)
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local sv = shared.v
	local seen = client.seen
	if not seen then
		seen = { n = sv.n, launchN = sv.launchN, impN = sv.impN, blastN = sv.blastN, mn = sv.mn }
		client.seen = seen
	end
	local base = Vec(sv.x, sv.y, sv.z)
	local top = Vec(sv.x, sv.top, sv.z)
	if sv.n ~= seen.n then seen.n = sv.n PlaySound(client.snd.place, base, 0.8) end
	if sv.launchN ~= seen.launchN then seen.launchN = sv.launchN PlaySound(client.snd.launch, top, 0.7) end
	if sv.impN ~= seen.impN then seen.impN = sv.impN PlaySound(client.snd.impact, Vec(sv.ix, sv.iy, sv.iz), 0.8) end
	if sv.blastN ~= seen.blastN then
		seen.blastN = sv.blastN
		PlaySound(client.snd.blast, top, 1.0)
		client.flash = 0.8
	end
	if sv.mn ~= seen.mn then
		seen.mn = sv.mn
		local m = MESSAGES[sv.msg]
		if m then client.msg, client.msgT = tr(m[1], m[2]), 2 end
	end
	client.msgT = math.max(0, client.msgT - dt)
	client.flash = math.max(0, client.flash - dt)

	if sv.phase == "grow" then
		PlayLoop(client.loops.grind, base, 0.9)
	elseif sv.phase == "rumble" or sv.phase == "erupt" or sv.phase == "cool" then
		PlayLoop(client.loops.rumble, base, 0.4 + 0.6 * sv.k)
		if sv.phase ~= "rumble" then PlayLoop(client.loops.roar, top, sv.k) end
	end
	if sv.phase ~= "idle" then
		local cam = GetPlayerCameraTransform()
		local d = VecLength(VecSub(cam.pos, base))
		local near = clamp(1 - (d - sv.R) / (sv.R * 8), 0, 1)
		local shake = (sv.phase == "grow" and 0.5 or sv.k) * near
		if shake > 0.02 then ShakeCamera(shake) end
	end

	if GetPlayerTool() == TOOL and GetPlayerCanUseTool() and InputPressed("r") and sv.phase == "idle" then
		ServerCall("server.clear")
	end
	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local a = client.anim[p]
			if not a then a = ToolAnimator() client.anim[p] = a end
			tickToolAnimator(a, dt, nil, p)
		end
	end
end

-- smoke column, lava fountain, bomb trails, ash (at most 44 particles per step)
function client.update(dt)
	local sv = shared.v
	if sv.phase == "idle" then return end
	local s = readSettings()
	local base = Vec(sv.x, sv.y, sv.z)
	local top = Vec(sv.x, sv.top, sv.z)
	if sv.phase == "grow" then
		ParticleReset()
		ParticleType("smoke")
		ParticleColor(0.45, 0.4, 0.35)
		ParticleRadius(0.6, 1.8)
		ParticleAlpha(0.5, 0)
		ParticleGravity(0.5)
		for i = 1, 6 do
			local a = rnd(0, 6.2832)
			SpawnParticle(VecAdd(base, Vec(math.cos(a) * sv.R, 0.3, math.sin(a) * sv.R)), Vec(math.cos(a) * 2, 1, math.sin(a) * 2), rnd(1.5, 3))
		end
		return
	end
	-- smoke column
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.2, 0.18, 0.17, 0.35, 0.33, 0.32)
	ParticleRadius(1 + sv.R * 0.05, 3 + sv.R * 0.15)
	ParticleAlpha(0.8, 0)
	ParticleGravity(2)
	ParticleDrag(0.1)
	for i = 1, math.floor(3 + 5 * sv.k) do
		SpawnParticle(VecAdd(top, Vec(rnd(-1, 1), 0.5, rnd(-1, 1))), Vec(rnd(-1, 1), rnd(4, 9) * (0.5 + sv.k), rnd(-1, 1)), rnd(6, 12))
	end
	if sv.phase == "erupt" then
		ParticleReset()
		ParticleType("plain")
		ParticleColor(1, 0.75, 0.3, 1, 0.25, 0.05)
		ParticleRadius(0.15, 0.05)
		ParticleEmissive(10, 0)
		ParticleGravity(-10)
		ParticleCollide(1)
		for i = 1, 10 do SpawnParticle(VecAdd(top, Vec(0, 0.5, 0)), Vec(rnd(-4, 4), rnd(8, 18), rnd(-4, 4)), rnd(1, 2.5)) end
	end
	-- glowing smoke trail behind each flying bomb
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(1, 0.5, 0.2, 0.25, 0.22, 0.2)
	ParticleRadius(0.3, 0.9)
	ParticleAlpha(0.7, 0)
	ParticleEmissive(3, 0)
	ParticleGravity(0.5)
	local list = sv.bombs
	for i = 1, math.min(#list, 20) do
		local b = list[i]
		if IsHandleValid(b) then SpawnParticle(GetBodyTransform(b).pos, Vec(0, 0.5, 0), 1.5) end
	end
	-- ash falling around the player
	if s.ash and (sv.phase == "erupt" or sv.phase == "cool") then
		local cam = GetPlayerCameraTransform()
		if VecLength(VecSub(cam.pos, base)) < sv.R * 10 then
			ParticleReset()
			ParticleType("plain")
			ParticleColor(0.3, 0.3, 0.3)
			ParticleRadius(0.04)
			ParticleGravity(-1.5)
			ParticleDrag(0.6)
			for i = 1, 6 do SpawnParticle(VecAdd(cam.pos, Vec(rnd(-15, 15), rnd(6, 12), rnd(-15, 15))), Vec(rnd(-0.5, 0.5), -1, rnd(-0.5, 0.5)), 6) end
		end
	end
end

function client.render(dt)
	local sv = shared.v
	if sv.phase == "idle" or sv.phase == "grow" then return end
	local flicker = 0.85 + 0.3 * math.random()
	PointLight(Vec(sv.x, sv.top + 2, sv.z), 1, 0.45, 0.15, (2 + 10 * sv.k) * flicker)
	local list = sv.bombs
	for i = 1, math.min(#list, 8) do
		if IsHandleValid(list[i]) then PointLight(GetBodyTransform(list[i]).pos, 1, 0.5, 0.2, 1.5) end
	end
end

local PHASES = {
	grow = { "Growing", "Растёт" },
	rumble = { "Rumbling", "Гудит" },
	erupt = { "ERUPTION", "ИЗВЕРЖЕНИЕ" },
	cool = { "Cooling down", "Остывает" },
}

function client.draw(dt)
	local svd = shared.v
	if readSettings().debug and svd.phase ~= "idle" and svd.dbg and svd.dbg ~= "" and not GetBool("game.ui.hidemods") then
		UiPush()
			UiTranslate(20, UiHeight() - 24)
			UiAlign("left middle")
			UiFont("regular.ttf", 16)
			UiTextShadow(0, 0, 0, 0.8, 1)
			UiColor(1, 1, 0.6, 0.95)
			UiText(svd.dbg)
		UiPop()
	end
	if client.flash > 0.01 then
		UiPush()
			UiColor(1, 0.7, 0.4, client.flash * 0.6)
			UiRect(UiWidth(), UiHeight())
		UiPop()
	end
	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or not GetPlayerCanUseTool() then return end
	local sv = shared.v
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 160)
		UiAlign("center middle")
		UiTextShadow(0, 0, 0, 0.6, 1.5)
		UiFont("regular.ttf", 22)
		UiColor(1, 1, 1, 0.9)
		if sv.phase == "idle" then
			UiText(tr("LMB: raise a volcano on the ground    R: remove the cones", "ЛКМ: поднять вулкан на земле    R: убрать конусы"))
		elseif sv.phase == "rumble" or sv.phase == "erupt" then
			UiText(tr("RMB: final blast now", "ПКМ: финальный взрыв сейчас"))
		end
		local ph = PHASES[sv.phase]
		if ph then
			UiTranslate(0, 30)
			UiFont("bold.ttf", 22)
			UiColor(1, 0.55, 0.25, 1)
			UiText(tr(ph[1], ph[2]))
			UiTranslate(0, 22)
			UiAlign("left middle")
			UiTranslate(-100, 0)
			UiColor(0, 0, 0, 0.5)
			UiRect(200, 6)
			UiColor(1, 0.5, 0.2, 1)
			UiRect(200 * clamp(sv.t / math.max(sv.T, 0.01), 0, 1), 6)
		end
		if client.msgT > 0 then
			UiAlign("center middle")
			UiTranslate(100, 28)
			UiColor(1, 0.6, 0.3, math.min(1, client.msgT))
			UiFont("regular.ttf", 20)
			UiText(client.msg)
		end
	UiPop()
end
