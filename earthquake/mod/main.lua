#version 2
-- Earthquake / Землетрясение
-- Seismic detonator tool. LMB starts a quake at the aim point (LMB again stops it),
-- RMB cycles the preset from weak to catastrophic.
--
-- Server: input, quake timeline, impulses to dynamic bodies, player jolts,
--         budgeted holes in weak materials, budgeted joint detaching, aftershocks.
-- Client: camera shake, rumble, cracks, dust and falling grit, seismograph HUD.
-- The ground motion is a pure function of (time, seed), so client and server
-- compute the same shaking from the small shared.quake table.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "quake"

local PRESETS = {
	-- pgv: peak ground velocity (m/s); holes: probes per physics step; r0/r1/r2: MakeHole radii
	-- joint: chance to detach a joint per check; jolt: player push scale
	{ en = "Weak", ru = "Слабое", pgv = 0.25, holes = 0, r0 = 0.0, r1 = 0.0, r2 = 0.0, joint = 0.0, jolt = 0.0 },
	{ en = "Moderate", ru = "Умеренное", pgv = 0.6, holes = 1, r0 = 0.2, r1 = 0.0, r2 = 0.0, joint = 0.08, jolt = 0.2 },
	{ en = "Strong", ru = "Сильное", pgv = 1.2, holes = 2, r0 = 0.3, r1 = 0.15, r2 = 0.0, joint = 0.2, jolt = 0.45 },
	{ en = "Severe", ru = "Разрушительное", pgv = 2.0, holes = 3, r0 = 0.4, r1 = 0.25, r2 = 0.05, joint = 0.4, jolt = 0.7 },
	{ en = "Catastrophic", ru = "Катастрофическое", pgv = 3.2, holes = 5, r0 = 0.55, r1 = 0.35, r2 = 0.12, joint = 0.7, jolt = 1.0 },
}

local RAMP_IN = 2.0
local RAMP_OUT = 3.0
local SCAN_INTERVAL = 0.25
local MAX_TRACKED = 220
local BODIES_PER_UPDATE = 55
local MASS_LIMIT = 2500
local JOINT_INTERVAL = 0.3
local JOINTS_PER_CHECK = 2
local MAX_HOLES_PER_QUAKE = 450
local HEIGHT = 25             -- bodies and structures up to this height above the epicentre are affected

local SOFT = { glass = true, wood = true, plaster = true, plastic = true, foliage = true }
local MEDIUM = { masonry = true, metal = true }
local HARD = { hardmasonry = true, hardmetal = true, heavymetal = true }

---------------------------------------------------------------------------
-- helpers (both sides)
---------------------------------------------------------------------------
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function rnd(a, b) return a + (b - a) * math.random() end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getI(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetInt(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		duration = clamp(getF("duration", 15), 5, 60),
		preset = math.floor(clamp(getI("preset", 3), 1, 5)),
		radius = clamp(getF("radius", 60), 20, 150),
		aftershocks = getB("aftershocks", true),
		damage = getB("damage", true),
		shake = clamp(getF("shake", 1), 0, 2),
		atPlayer = getB("atplayer", false),
	}
end

-- smooth pseudo random value in [-1, 1] (value noise), deterministic from seed
local function hash(n) local x = math.sin(n * 127.1 + 311.7) * 43758.5453 return (x - math.floor(x)) * 2 - 1 end
local function vnoise(t, seed)
	local i = math.floor(t)
	local f = t - i
	local u = f * f * (3 - 2 * f)
	return hash(i + seed * 17.0) * (1 - u) + hash(i + 1 + seed * 17.0) * u
end

-- envelope 0..1 of a quake of length D at time t
function quakeEnvelope(t, D)
	if t < 0 or t > D then return 0 end
	local a = clamp(t / RAMP_IN, 0, 1)
	local b = clamp((D - t) / RAMP_OUT, 0, 1)
	return math.min(a * a * (3 - 2 * a), b * b * (3 - 2 * b))
end

-- ground velocity (m/s) at time t for quake q = {t0-relative time, D, pgv, seed}
function groundVelocity(t, D, pgv, seed)
	local e = quakeEnvelope(t, D)
	if e <= 0 then return 0, 0, 0 end
	-- bursts make the shaking uneven, like real quakes
	local burst = 0.65 + 0.35 * vnoise(t * 0.7, seed + 3)
	local a = pgv * e * burst
	local x = math.sin(t * 8.2 + seed) * 0.7 + vnoise(t * 5.0, seed) * 0.5
	local z = math.sin(t * 6.9 + seed * 1.7) * 0.6 + vnoise(t * 4.3, seed + 1) * 0.5
	local y = math.sin(t * 13.1 + seed * 0.3) * 0.25 + vnoise(t * 9.0, seed + 2) * 0.25
	return x * a, y * a, z * a
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	server.settings = readSettings()
	RegisterTool(TOOL, tr("Seismic Detonator", "Сейсмический детонатор"), "MOD/prefab/tool.xml", 6)
	server.players = {}
	server.q = nil
	server.pending = {}      -- scheduled aftershocks {at, scale, D}
	server.time = 0
	shared.quake = { active = false, t = 0, D = 1, pgv = 0, seed = 0, preset = 3, x = 0, y = 0, z = 0, R = 60, n = 0, after = 0 }
	shared.presets = {}
end

function server.tick(dt)
	server.time = server.time + dt
	for p in PlayersAdded() do
		server.players[p] = { preset = server.settings.preset }
		shared.presets[p] = server.settings.preset
		SetToolEnabled(TOOL, true, p)
	end
	for p in PlayersRemoved() do
		server.players[p] = nil
		shared.presets[p] = nil
	end
	for p in Players() do
		local st = server.players[p]
		if not st then
			st = { preset = server.settings.preset }
			server.players[p] = st
		end
		if GetPlayerTool(p) == TOOL and GetPlayerCanUseTool(p) and GetPlayerVehicle(p) == 0 then
			if InputPressed("usetool", p) then
				if server.q then          -- also during an aftershock: "LMB again stops it" (review 16.10)
					server.stop()
				else
					server.start(p, st.preset, 1.0, nil, false)
				end
			end
			if InputPressed("grab", p) and GetPlayerGrabBody(p) == 0 and GetPlayerPickBody(p) == 0 then
				st.preset = (st.preset % #PRESETS) + 1
				shared.presets[p] = st.preset
			end
		end
	end
	-- aftershocks
	for i = #server.pending, 1, -1 do
		local a = server.pending[i]
		if server.time >= a.at and not server.q then
			table.remove(server.pending, i)
			server.start(a.owner, a.preset, a.scale, a.D, true, a.pos)
		end
	end
end

function server.start(p, preset, scale, D, aftershock, pos)
	local s = readSettings()
	server.settings = s
	if not pos then
		if s.atPlayer then
			pos = GetPlayerTransform(p).pos
		else
			local eye = GetPlayerEyeTransform(p)
			local hit, _, endPos = GetPlayerAimInfo(eye.pos, 120, p)
			pos = hit and endPos or GetPlayerTransform(p).pos
		end
	end
	local P = PRESETS[preset]
	server.q = {
		t = 0, D = D or s.duration, pgv = P.pgv * scale, preset = preset, seed = math.random(1, 1000),
		pos = VecCopy(pos), R = s.radius, owner = p, aftershock = aftershock, scale = scale,
		tracked = {}, cursor = 1, scanT = 0, jointT = 0, holes = 0, damage = s.damage,
	}
	if not aftershock then
		server.pending = {}
		if s.aftershocks and preset >= 2 then
			local count = (preset >= 4) and 3 or 2
			local at = server.time + server.q.D
			for i = 1, count do
				at = at + rnd(8, 22)
				server.pending[#server.pending + 1] = {
					at = at, owner = p, preset = preset, scale = rnd(0.3, 0.6), D = rnd(4, 9), pos = VecAdd(pos, Vec(rnd(-15, 15), 0, rnd(-15, 15))),
				}
			end
		end
	end
	local q = shared.quake
	q.active = true
	q.t = 0
	q.D = server.q.D
	q.pgv = server.q.pgv
	q.seed = server.q.seed
	q.preset = preset
	q.x, q.y, q.z = pos[1], pos[2], pos[3]
	q.R = server.q.R
	q.n = q.n + 1
	q.after = aftershock and 1 or 0
end

function server.stop()
	server.q = nil
	server.pending = {}
	shared.quake.active = false
end

function server.update(dt)
	local q = server.q
	if not q then return end
	local prevT = q.t
	q.t = q.t + dt
	shared.quake.t = q.t
	if q.t >= q.D then
		server.q = nil
		shared.quake.active = false
		return
	end
	server.shakeBodies(q, dt)
	server.jolt(q, prevT)
	if q.damage then
		server.crack(q, dt)
		server.joints(q, dt)
	end
end

function server.scan(q)
	local R = q.R
	local c = q.pos
	QueryRequire("physical dynamic")
	local list = QueryAabbBodies(Vec(c[1] - R, c[2] - 10, c[3] - R), Vec(c[1] + R, c[2] + HEIGHT, c[3] + R))
	local out = {}
	for i = 1, #list do
		if GetBodyPlayer(list[i]) == 0 then
			out[#out + 1] = list[i]
			if #out >= MAX_TRACKED then break end
		end
	end
	return out
end

function server.shakeBodies(q, dt)
	q.scanT = q.scanT - dt
	if q.scanT <= 0 then
		q.scanT = SCAN_INTERVAL
		q.tracked = server.scan(q)
		q.cursor = 1
	end
	local n = #q.tracked
	if n == 0 then return end
	local per = math.min(n, BODIES_PER_UPDATE)
	local stride = n / per
	-- velocity change of the ground over the time since this body was last handled
	local x1, y1, z1 = groundVelocity(q.t, q.D, q.pgv, q.seed)
	local x0, y0, z0 = groundVelocity(q.t - dt * stride, q.D, q.pgv, q.seed)
	local dv = Vec(x1 - x0, y1 - y0, z1 - z0)
	if VecLength(dv) < 1e-4 then return end
	for k = 1, per do
		local i = q.cursor
		q.cursor = (q.cursor % n) + 1
		local b = q.tracked[i]
		if IsHandleValid(b) and IsBodyDynamic(b) then
			local mass = GetBodyMass(b)
			if mass > 0 then
				local bt = GetBodyTransform(b)
				local d = VecSub(bt.pos, q.pos)
				local horiz = math.sqrt(d[1] * d[1] + d[3] * d[3])
				local fall = clamp(1 - horiz / q.R, 0, 1)
				if fall > 0 then
					local massK = clamp(MASS_LIMIT / mass, 0.15, 1)
					local com = TransformToParentPoint(bt, GetBodyCenterOfMass(b))
					-- push slightly off-centre so things also rock and tip over
					local off = Vec(rnd(-0.2, 0.2), rnd(0, 0.3), rnd(-0.2, 0.2))
					ApplyBodyImpulse(b, VecAdd(com, off), VecScale(dv, mass * massK * fall))
				end
			end
		end
	end
end

function server.jolt(q, prevT)
	local P = PRESETS[q.preset]
	if P.jolt <= 0 then return end
	local x1, y1, z1 = groundVelocity(q.t, q.D, q.pgv, q.seed)
	local x0, y0, z0 = groundVelocity(prevT, q.D, q.pgv, q.seed)
	for p in Players() do
		if IsPlayerGrounded(p) and GetPlayerVehicle(p) == 0 then
			local d = VecSub(GetPlayerTransform(p).pos, q.pos)
			local horiz = math.sqrt(d[1] * d[1] + d[3] * d[3])
			local fall = clamp(1 - horiz / q.R, 0, 1)
			if fall > 0 then
				local k = P.jolt * fall
				local v = GetPlayerVelocity(p)
				SetPlayerVelocity(VecAdd(v, Vec((x1 - x0) * k, math.max(0, y1 - y0) * k, (z1 - z0) * k)), p)
			end
		end
	end
end

-- random probes near structures; weak materials crack first
function server.crack(q, dt)
	local P = PRESETS[q.preset]
	if P.holes <= 0 or q.holes >= MAX_HOLES_PER_QUAKE then return end
	local e = quakeEnvelope(q.t, q.D) * (q.scale or 1)
	if e < 0.3 then return end
	local probes = math.max(1, math.floor(P.holes * e + 0.5))
	for i = 1, probes do
		local a = math.random() * 6.2832
		local r = q.R * 0.8 * math.sqrt(math.random())
		local p = Vec(q.pos[1] + math.cos(a) * r, q.pos[2] + rnd(0.3, 12), q.pos[3] + math.sin(a) * r)
		QueryRequire("physical")
		local hit, point, normal, shape = QueryClosestPoint(p, 1.5)
		if hit and shape ~= 0 then
			local inside = VecSub(point, VecScale(normal, 0.05))
			local mat = GetShapeMaterialAtPosition(shape, inside)
			local ok = SOFT[mat] or (P.r1 > 0 and MEDIUM[mat]) or (P.r2 > 0 and HARD[mat])
			if ok then
				MakeHole(inside, P.r0 * e, P.r1 * e, P.r2 * e, false)
				q.holes = q.holes + 1
				if q.holes >= MAX_HOLES_PER_QUAKE then return end
			end
		end
	end
end

-- loosen joints (hinges, ropes, ball joints): check a few shaken dynamic bodies
-- (doors, lamps, signs are dynamic bodies jointed to the world) plus the shapes
-- around one random point
local function tryDetach(shape, chance, budget)
	local joints = GetShapeJoints(shape)
	local n = 0
	for j = 1, #joints do
		if n >= budget then break end
		if not IsJointBroken(joints[j]) and math.random() < chance then
			DetachJointFromShape(joints[j], shape)
			n = n + 1
		end
	end
	return n
end

function server.joints(q, dt)
	local P = PRESETS[q.preset]
	if P.joint <= 0 then return end
	q.jointT = q.jointT - dt
	if q.jointT > 0 then return end
	q.jointT = JOINT_INTERVAL
	local chance = P.joint * quakeEnvelope(q.t, q.D) * (q.scale or 1)
	local left = JOINTS_PER_CHECK
	local n = #q.tracked
	for k = 1, math.min(n, 6) do
		local b = q.tracked[math.random(1, n)]
		if IsHandleValid(b) then
			local shapes = GetBodyShapes(b)
			for i = 1, #shapes do
				left = left - tryDetach(shapes[i], chance, left)
				if left <= 0 then return end
			end
		end
	end
	local a = math.random() * 6.2832
	local r = q.R * 0.5 * math.sqrt(math.random())
	local c = Vec(q.pos[1] + math.cos(a) * r, q.pos[2] + rnd(0.5, 8), q.pos[3] + math.sin(a) * r)
	QueryRequire("physical")
	local shapes = QueryAabbShapes(VecSub(c, Vec(3, 3, 3)), VecAdd(c, Vec(3, 3, 3)))
	for i = 1, math.min(#shapes, 12) do
		left = left - tryDetach(shapes[i], chance, left)
		if left <= 0 then return end
	end
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

local GRAPH_N = 120

function client.init()
	client.rumble = LoadLoop("MOD/snd/rumble.ogg", 40)
	client.crack = { LoadSound("MOD/snd/crack1.ogg", 20), LoadSound("MOD/snd/crack2.ogg", 20) }
	client.click = LoadSound("MOD/snd/click.ogg")
	client.boom = LoadSound("MOD/snd/boom.ogg", 60)
	client.anim = {}
	client.lastN = 0
	client.crackT = 0
	client.graph = {}
	for i = 1, GRAPH_N do client.graph[i] = 0 end
	client.graphT = 0
	client.intensity = 0
	client.lastPreset = nil
	client.blink = 0
end

local function localIntensity()
	local q = shared.quake
	if not q.active then return 0, 0 end
	local eye = GetPlayerCameraTransform()
	local dx, dz = eye.pos[1] - q.x, eye.pos[3] - q.z
	local fall = clamp(1 - math.sqrt(dx * dx + dz * dz) / q.R, 0, 1)
	local x, y, z = groundVelocity(q.t, q.D, q.pgv, q.seed)
	local mag = math.sqrt(x * x + y * y + z * z)
	return quakeEnvelope(q.t, q.D) * fall * (q.pgv / 3.2), mag * fall
end

function client.tick(dt)
	for p in PlayersAdded() do
		local a = ToolAnimator()
		a.armPitchScale = 0.4
		client.anim[p] = a
	end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local q = shared.quake

	-- sounds of a new quake / aftershock
	if q.n ~= client.lastN then
		client.lastN = q.n
		if q.active then
			if q.after == 0 then PlaySound(client.click) end
			PlaySound(client.boom, Vec(q.x, q.y, q.z), 0.6 + 0.4 * q.pgv / 3.2)
		end
	end

	local inten, mag = localIntensity()
	client.intensity = inten
	if q.active and inten > 0 then
		local eye = GetPlayerCameraTransform()
		PlayLoop(client.rumble, eye.pos, clamp(0.25 + inten * 1.2, 0, 1), true, 0.8 + 0.3 * inten)
		local sh = getF("shake", 1)
		if sh > 0 then
			ShakeCamera(clamp(inten * 1.4 * sh, 0, 1.5))
		end
		client.crackT = client.crackT - dt
		if client.crackT <= 0 and inten > 0.15 then
			client.crackT = rnd(0.4, 1.6) / (0.3 + inten)
			local p = VecAdd(eye.pos, Vec(rnd(-12, 12), rnd(-1, 6), rnd(-12, 12)))
			PlaySound(client.crack[math.random(1, 2)], p, clamp(0.3 + inten, 0, 1))
		end
	end

	-- seismograph samples at 30 Hz
	client.graphT = client.graphT + dt
	while client.graphT > 1 / 30 do
		client.graphT = client.graphT - 1 / 30
		table.remove(client.graph, 1)
		local x = 0
		if q.active then
			local gx, gy, gz = groundVelocity(q.t, q.D, q.pgv, q.seed)
			x = gx + gz * 0.5
		end
		client.graph[GRAPH_N] = x
	end

	-- hand tool
	client.blink = client.blink + dt
	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local a = client.anim[p]
			if not a then
				a = ToolAnimator()
				client.anim[p] = a
			end
			local press = 0
			if InputDown("usetool", p) then press = 1 end
			a.offsetTransform = Transform(Vec(0, -0.01 * press, 0.02 * press))
			tickToolAnimator(a, dt, nil, p)
			local b = GetToolBody(p)
			if b ~= 0 then
				local shapes = GetBodyShapes(b)
				local on = q.active and (math.floor(client.blink * 4) % 2 == 0)
				for i = 1, #shapes do
					SetShapeEmissiveScale(shapes[i], on and 1.6 or 0.5)
				end
			end
		end
	end
end

-- dust and falling grit at a fixed rate
function client.update(dt)
	local q = shared.quake
	if not q.active then return end
	local inten = client.intensity
	if inten <= 0.02 then return end
	local eye = GetPlayerCameraTransform()
	local nDust = math.floor(2 + 8 * inten)
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.55, 0.5, 0.42, 0.6, 0.58, 0.55)
	ParticleRadius(0.3, 1.2)
	ParticleAlpha(0.35 * inten + 0.05, 0)
	ParticleGravity(0.4)
	ParticleDrag(0.4)
	ParticleCollide(0)
	for i = 1, nDust do
		local a = math.random() * 6.2832
		local r = rnd(2, 25)
		local p = Vec(eye.pos[1] + math.cos(a) * r, eye.pos[2] + 20, eye.pos[3] + math.sin(a) * r)
		QueryRequire("physical static")
		local hit, dist = QueryRaycast(p, Vec(0, -1, 0), 40)
		if hit then
			local g = Vec(p[1], p[2] - dist + 0.1, p[3])
			SpawnParticle(g, Vec(rnd(-0.5, 0.5), rnd(0.3, 1.2), rnd(-0.5, 0.5)), rnd(1.5, 3))
		end
	end
	-- grit falling from ceilings around the player
	local nGrit = math.floor(6 * inten)
	if nGrit > 0 then
		ParticleReset()
		ParticleType("plain")
		ParticleColor(0.45, 0.42, 0.38)
		ParticleRadius(0.02, 0.015)
		ParticleAlpha(1, 1)
		ParticleGravity(-10)
		ParticleCollide(1)
		ParticleSticky(0.2)
		for i = 1, nGrit do
			local p = VecAdd(eye.pos, Vec(rnd(-6, 6), 0, rnd(-6, 6)))
			QueryRequire("physical static")
			local hit, dist = QueryRaycast(p, Vec(0, 1, 0), 8)
			if hit then
				SpawnParticle(VecAdd(p, Vec(0, dist - 0.05, 0)), Vec(0, -0.5, 0), 2)
			end
		end
	end
end

function client.draw(dt)
	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or GetBool("game.player.usescreen") or not GetPlayerCanUseTool() then return end
	local q = shared.quake
	local preset = shared.presets[GetLocalPlayer()] or 3
	local P = PRESETS[preset]
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 190)
		UiAlign("center middle")
		UiColor(0, 0, 0, 0.55)
		UiRoundedRect(560, 150, 10)
		-- seismograph
		UiPush()
			UiTranslate(-260, -30)
			UiAlign("left middle")
			local w = 520 / GRAPH_N
			for i = 1, GRAPH_N do
				local v = clamp(client.graph[i] / 3.2, -1, 1)
				local h = math.max(2, math.abs(v) * 50)
				UiPush()
					UiTranslate((i - 1) * w, 0)
					UiColor(0.4 + 0.6 * math.abs(v), 1 - 0.6 * math.abs(v), 0.3, 0.9)
					UiRect(math.max(1, w - 1), h)
				UiPop()
			end
		UiPop()
		UiTranslate(0, 22)
		UiFont("bold.ttf", 26)
		UiColor(1, 0.85, 0.3, 1)
		UiText(tr("Preset: ", "Сила: ") .. tr(P.en, P.ru) .. " (" .. preset .. "/5)")
		UiTranslate(0, 28)
		UiFont("regular.ttf", 20)
		UiColor(1, 1, 1, 0.85)
		if q.active then
			if q.after == 1 then
				UiText(tr("Aftershock", "Афтершок") .. string.format(" %.0f / %.0f s", q.t, q.D) .. tr("    LMB: stop", "    ЛКМ: остановить"))
			else
				UiText(tr("LMB: stop the quake", "ЛКМ: остановить") .. string.format("   %.0f / %.0f s", q.t, q.D))
			end
		else
			UiText(tr("LMB: start a quake at the aim point    RMB: change preset", "ЛКМ: землетрясение в точке прицела    ПКМ: сменить силу"))
		end
	UiPop()
end
