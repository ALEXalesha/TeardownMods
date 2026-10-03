#version 2
-- Falling Moon / Падающая луна
-- Telescope tool. LMB marks the impact point: the moon starts to fall towards it
-- over 1-5 minutes, growing in the sky. Tremors, wind and lifting debris build
-- up, the sky turns red, a countdown runs. For the last stretch the moon is a
-- real voxel body that comes down on the point and stays in its crater. At the
-- impact: a blinding flash, a crater ring around the moon, and a shockwave that
-- rolls outwards and takes most structures in the radius down - holes punched
-- into whatever stands near the front (hard materials too near the centre),
-- explosions, fires, bodies thrown hard - spread over frames within a budget.
-- RMB sends the moon back while it is still far away.
--
-- The moon is a camera-facing sprite the whole way in: opaque, sphere-shaded, depth-tested
-- (trees and buildings in front of it hide it), with the size the real geometry gives and an
-- orange heat glow on its edge. At the impact the voxel moon (a hollow shell tagged
-- unbreakable and nocull) is spawned once, static, in its crater.
--
-- No flicker: the sky is never rewritten while the moon flies (that was the cause of the
-- flicker: three sky properties rewritten every 0.5 s). The optional red sky is written once
-- when the moon is called and restored once at the end. The rest of the drama is made of
-- things that cannot flicker: growing camera shake, dust lifted around you, rising wind, the
-- heat glow, a red screen wash, and a shockwave ring at the impact.
--
-- Server: timeline, tremors and wind (budgeted impulses), crater, shockwave, destruction
-- queue, fires, player push, the voxel moon at the impact.
-- Client: the moon sprite, sounds, camera shake, flash, dust, ring, countdown.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "fallingmoon"
local SHOCK_SPEED = 60          -- m/s
local AFTERMATH = 30
local RECEDE = 4
local SCAN_INTERVAL = 1.0
local TREMOR_PER_UPDATE = 30
local SHOCK_PER_UPDATE = 80
local MAX_SHOCK_BODIES = 600
local START_RADII = 41          -- the moon starts this many radii away (about 1.4 degrees)
local EMBED = 0.25              -- the moon's centre ends this many radii below the impact point
local MOON_VOXELS = 80          -- shell radius in voxels (moon.vox)
local SPRITE_DIST = 300         -- the far sprite is drawn this far away at most (well inside the far plane)
-- destruction budget per physics step. Buildings are shells, so the voxels a hole removes
-- grow with its area (radius squared), not its volume.
local HOLE_R2_BUDGET = 1100
local HOLES_PER_UPDATE = 60
local PROBES_PER_UPDATE = 140
local FIRES_PER_UPDATE = 6
local LEVELS = {                -- per destruction setting: hole size, probe density per m^2, throw
	{ size = 0.8, density = 0.05, throw = 0.8 },
	{ size = 1.1, density = 0.09, throw = 1.0 },
	{ size = 1.4, density = 0.14, throw = 1.3 },
}

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function rnd(a, b) return a + (b - a) * math.random() end
local function smooth(a, b, x) local t = clamp((x - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getI(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetInt(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	local size = getI("moonsize", 45)
	if size ~= 30 and size ~= 60 then size = 45 end
	return {
		duration = clamp(getF("duration", 120), 60, 300),
		radius = clamp(getF("radius", 200), 50, 300),
		damage = math.floor(clamp(getI("damage", 1), 0, 2)),
		fire = getB("fire", true),
		redsky = getB("redsky", false),
		countdown = getB("countdown", true),
		tremors = getB("tremors", true),
		moonSize = size,
		destruction = math.floor(clamp(getI("destruction", 3), 1, 3)),
	}
end

-- distance (along the approach direction) of the moon centre from its final place at
-- progress u (0..1): it accelerates in, like something falling
function moonDistance(u, r)
	return START_RADII * r * (1 - clamp(u, 0, 1) ^ 3)
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

local ENV_KEYS = { "skyboxtint", "fogColor", "sunColorTint" }
local ENV_RED = { skyboxtint = { 1.0, 0.35, 0.2 }, fogColor = { 0.5, 0.16, 0.08 }, sunColorTint = { 1.0, 0.35, 0.15 } }

function server.init()
	RegisterTool(TOOL, tr("Moon Caller", "Зов луны"), "MOD/prefab/tool.xml", 6)
	server.ev = nil
	shared.m = { phase = "idle", t = 0, T = 1, x = 0, y = 0, z = 0, dx = 0, dy = 1, dz = 0, r = 0, R = 150, n = 0, prog = 0,
		cx = 0, cy = 0, cz = 0, mr = 45, body = 0 }
end

local function captureEnv()
	local orig = {}
	for _, k in ipairs(ENV_KEYS) do
		local a, b, c = GetEnvironmentProperty(k)
		orig[k] = { a or 1, b or 1, c or 1 }
	end
	return orig
end

local function applyEnv(orig, k)
	for _, key in ipairs(ENV_KEYS) do
		local o, r = orig[key], ENV_RED[key]
		SetEnvironmentProperty(key, lerp(o[1], r[1], k), lerp(o[2], r[2], k), lerp(o[3], r[3], k))
	end
end

function server.tick(dt)
	for p in PlayersAdded() do SetToolEnabled(TOOL, true, p) end
	for p in Players() do
		if GetPlayerTool(p) == TOOL and GetPlayerCanUseTool(p) and GetPlayerVehicle(p) == 0 then
			if InputPressed("usetool", p) and not server.ev then server.start(p) end
			if InputPressed("grab", p) and server.ev and server.ev.phase == "approach" and server.ev.moonBody == 0 then server.abort() end
		end
	end
end

function server.start(p)
	local s = readSettings()
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	QueryRejectPlayer(p)
	QueryRequire("physical static")
	local hit, dist = QueryRaycast(eye.pos, fwd, 400)
	local target
	if hit and dist > 25 then
		target = VecAdd(eye.pos, VecScale(fwd, dist))
	else
		-- too close or nothing hit: 80 m ahead, on the ground
		local flat = VecNormalize(Vec(fwd[1], 0, fwd[3]))
		local probe = VecAdd(eye.pos, VecAdd(VecScale(flat, 80), Vec(0, 60, 0)))
		QueryRequire("physical static")
		local h2, d2 = QueryRaycast(probe, Vec(0, -1, 0), 200)
		target = h2 and VecAdd(probe, Vec(0, -d2, 0)) or VecAdd(eye.pos, VecScale(flat, 80))
	end
	-- the moon comes in from above, from beyond the impact point as seen by the player
	local away = VecSub(target, eye.pos)
	away[2] = 0
	away = VecLength(away) > 0.1 and VecNormalize(away) or Vec(0, 0, -1)
	local dir = VecNormalize(VecAdd(Vec(0, 1, 0), VecScale(away, 0.7)))
	local r = s.moonSize
	server.ev = { phase = "approach", t = 0, T = s.duration, center = target, dir = dir, s = s,
		tracked = {}, cursor = 1, scanT = 0, owner = p, mr = r, rest = VecAdd(target, Vec(0, -EMBED * r, 0)),
		moonBody = 0, spin = rnd(0, 360), level = LEVELS[s.destruction] }
	-- optional red sky: written ONCE now and restored ONCE at the end. Rewriting sky properties
	-- while the moon flies made the sky flicker, so nothing touches the environment in between.
	if s.redsky then
		server.ev.orig = captureEnv()
		applyEnv(server.ev.orig, 1)
	end
	local m = shared.m
	m.phase = "approach"
	m.t = 0
	m.T = s.duration
	m.x, m.y, m.z = target[1], target[2], target[3]
	m.dx, m.dy, m.dz = dir[1], dir[2], dir[3]
	m.R = s.radius
	m.r = 0
	m.n = m.n + 1
	m.prog = 0
	m.mr = r
	m.body = 0
	server.placeMoon(server.ev, 0)
end

-- moon centre for progress u; shared for the client's far sprite
function server.placeMoon(ev, u)
	local L = moonDistance(u, ev.mr)
	local c = VecAdd(ev.rest, VecScale(ev.dir, L))
	ev.moonPos = c
	ev.moonL = L
	local m = shared.m
	m.cx, m.cy, m.cz = c[1], c[2], c[3]
	return c, L
end

-- the voxel moon: spawned once at the impact, static, never moved through the sky (moving a
-- 230k-voxel body every tick was the second flicker suspect). First guess: the vox pivot is the
-- centre of the bottom face; from the next tick on the real centre is measured and corrected.
function server.spawnMoon(ev)
	local scale = ev.mr / (MOON_VOXELS * 0.1)
	local half = (2 * MOON_VOXELS + 1) * 0.1 * scale * 0.5
	local rot = QuatEuler(12, ev.spin, 0)
	local xml = "<body dynamic='false'><vox file='MOD/vox/moon.vox' scale='" .. string.format("%.4f", scale) .. "' tags='unbreakable nocull'/></body>"
	local ents = Spawn(xml, Transform(VecSub(ev.moonPos, QuatRotateVec(rot, Vec(0, half, 0))), rot), true)
	for i = 1, #ents do
		if GetEntityType(ents[i]) == "body" then ev.moonBody = ents[i] break end
	end
	ev.moonFixes = 0
	shared.m.body = ev.moonBody
end

function server.anchorMoon(ev)
	if ev.moonBody == 0 or not IsHandleValid(ev.moonBody) or (ev.moonFixes or 0) >= 3 then return end
	local shapes = GetBodyShapes(ev.moonBody)
	if #shapes == 0 then return end
	local sx, sy, sz, vs = GetShapeSize(shapes[1])
	local centre = TransformToParentPoint(GetShapeWorldTransform(shapes[1]), Vec(sx * vs * 0.5, sy * vs * 0.5, sz * vs * 0.5))
	local err = VecSub(ev.moonPos, centre)
	if VecLength(err) > 0.05 then
		local bt = GetBodyTransform(ev.moonBody)
		SetBodyTransform(ev.moonBody, Transform(VecAdd(bt.pos, err), bt.rot))
		ev.moonFixes = ev.moonFixes + 1
	else
		ev.moonFixes = 3
	end
end

function server.abort()
	local ev = server.ev
	ev.phase = "recede"
	ev.recedeFrom = ev.t / ev.T
	ev.t = 0
	shared.m.phase = "recede"
end

function server.update(dt)
	local ev = server.ev
	if not ev then return end
	ev.t = ev.t + dt
	local m = shared.m
	m.t = ev.t
	m.T = ev.T
	if ev.phase == "approach" then
		local u = clamp(ev.t / ev.T, 0, 1)
		m.prog = u
		server.placeMoon(ev, u)
		local I = smooth(0.35, 1.0, u)
		if ev.s.tremors and I > 0 then server.tremors(ev, dt, I) end
		if ev.t >= ev.T then server.impact(ev) end
	elseif ev.phase == "recede" then
		local u = ev.recedeFrom * clamp(1 - ev.t / RECEDE, 0, 1)
		m.prog = u
		server.placeMoon(ev, u)
		if ev.t >= RECEDE then server.finish() end
	elseif ev.phase == "impact" then
		server.anchorMoon(ev)
		server.shock(ev, dt)
		server.work(ev, dt)
	elseif ev.phase == "aftermath" then
		server.anchorMoon(ev)
		server.work(ev, dt)
		if ev.t >= AFTERMATH and #ev.queue == 0 and ev.craterNext > #ev.crater then server.finish() end
	end
end

function server.finish()
	local ev = server.ev
	if ev.orig then applyEnv(ev.orig, 0) end      -- the one restore
	server.ev = nil
	shared.m.phase = "idle"
	shared.m.prog = 0
	shared.m.body = 0
end

-- shaking, a wind away from the moon and light debris lifting in the last part
function server.tremors(ev, dt, I)
	ev.scanT = ev.scanT - dt
	if ev.scanT <= 0 then
		ev.scanT = SCAN_INTERVAL
		local list = {}
		for p in Players() do
			local c = GetPlayerTransform(p).pos
			QueryRequire("physical dynamic")
			local found = QueryAabbBodies(VecSub(c, Vec(60, 20, 60)), VecAdd(c, Vec(60, 40, 60)))
			for i = 1, #found do
				if GetBodyPlayer(found[i]) == 0 then list[#list + 1] = found[i] end
				if #list >= 200 then break end
			end
		end
		ev.tracked = list
		ev.cursor = 1
	end
	local n = #ev.tracked
	if n == 0 then return end
	local per = math.min(n, TREMOR_PER_UPDATE)
	local stride = n / per
	local wind = VecNormalize(Vec(-ev.dir[1], 0, -ev.dir[3]))
	for k = 1, per do
		local b = ev.tracked[ev.cursor]
		ev.cursor = (ev.cursor % n) + 1
		if IsHandleValid(b) and IsBodyDynamic(b) then
			local mass = GetBodyMass(b)
			if mass > 0 then
				local massK = clamp(800 / mass, 0.05, 1)
				local jolt = Vec(rnd(-1, 1), rnd(0, 1.5), rnd(-1, 1))
				local dv = VecScale(jolt, 1.6 * I * massK)
				if mass < 80 and I > 0.5 then
					dv = VecAdd(dv, VecAdd(Vec(0, 7 * (I - 0.5) * dt * stride, 0), VecScale(wind, 5 * I * dt * stride)))
				end
				ApplyBodyImpulse(b, TransformToParentPoint(GetBodyTransform(b), GetBodyCenterOfMass(b)), VecScale(dv, mass))
			end
		end
	end
end

-- crater ring around the moon: tiles from the moon's rim outwards, deepest at the rim
local function craterTiles(c, r, lv)
	local tiles = {}
	local tr0 = 4.5 * lv.size
	local step = tr0 * 1.4
	local inner, outer = 0.85 * r, 1.6 * r
	local depth0 = 0.45 * r
	for x = -outer, outer, step do
		for z = -outer, outer, step do
			local rho = math.sqrt(x * x + z * z)
			if rho >= inner and rho <= outer then
				local depth = depth0 * (1 - (rho - inner) / (outer - inner))
				for y = -depth, 1.0, step do
					tiles[#tiles + 1] = { pos = VecAdd(c, Vec(x, y, z)), d = rho }
				end
			end
		end
	end
	table.sort(tiles, function(a, b) return a.d < b.d end)
	return tiles, tr0
end

function server.impact(ev)
	local s = ev.s
	local c = ev.center
	local lv = ev.level
	ev.phase = "impact"
	ev.t = 0
	ev.r = 0
	ev.rDone = 0
	local m = shared.m
	m.phase = "impact"
	m.t = 0
	m.r = 0
	m.prog = 1
	server.placeMoon(ev, 1)
	server.spawnMoon(ev)
	Explosion(c, 4, ev.owner)
	for i = 1, 6 do
		local a = i / 6 * 6.2832
		Explosion(VecAdd(c, Vec(math.cos(a) * 1.3 * ev.mr, 1, math.sin(a) * 1.3 * ev.mr)), 4, ev.owner)
	end
	ev.crater, ev.craterR = craterTiles(c, ev.mr, lv)
	ev.craterNext = 1
	ev.queue = {}          -- pending probe bands { r0, r1, n }
	-- every body in reach, nearest first; the shockwave works through the list over several frames
	local R = s.radius
	QueryRequire("physical dynamic")
	local list = QueryAabbBodies(VecSub(c, Vec(R, R * 0.4, R)), VecAdd(c, Vec(R, R * 0.6, R)))
	local items = {}
	for i = 1, #list do
		local b = list[i]
		if GetBodyPlayer(b) == 0 and b ~= ev.moonBody then
			local d = VecLength(VecSub(GetBodyTransform(b).pos, c))
			if d <= R then items[#items + 1] = { b = b, d = d } end
		end
	end
	table.sort(items, function(a, b) return a.d < b.d end)
	while #items > MAX_SHOCK_BODIES do table.remove(items) end
	ev.items = items
	ev.next = 1
	ev.hitPlayers = {}
	ev.explodeT = 0
end

-- the front: pushes bodies and players, queues the band it swept for the destruction worker
function server.shock(ev, dt)
	local s = ev.s
	local c = ev.center
	local R = s.radius
	local lv = ev.level
	local r0 = ev.r
	ev.r = math.min(R, ev.r + SHOCK_SPEED * dt)
	shared.m.r = ev.r
	if ev.r > r0 then
		local area = 3.1416 * (ev.r * ev.r - r0 * r0)
		ev.queue[#ev.queue + 1] = { r0 = r0, r1 = ev.r, n = math.max(1, math.floor(area * lv.density + 0.5)) }
	end
	-- bodies the front has reached
	local done = 0
	while ev.next <= #ev.items and ev.items[ev.next].d <= ev.r and done < SHOCK_PER_UPDATE do
		local it = ev.items[ev.next]
		ev.next = ev.next + 1
		done = done + 1
		if IsHandleValid(it.b) and IsBodyDynamic(it.b) then
			local mass = GetBodyMass(it.b)
			if mass > 0 then
				local pos = TransformToParentPoint(GetBodyTransform(it.b), GetBodyCenterOfMass(it.b))
				local out = VecSub(pos, c)
				out[2] = 0
				out = VecLength(out) > 0.01 and VecNormalize(out) or GetRandomDirection(1)
				local k = (1 - it.d / R) ^ 0.7
				local speed = (45 * k + 8) * lv.throw
				local massK = clamp(5000 / mass, 0.2, 1)
				ApplyBodyImpulse(it.b, pos, VecScale(VecNormalize(VecAdd(out, Vec(0, 0.45, 0))), mass * speed * massK))
			end
		end
	end
	-- explosions riding the inner part of the front
	ev.explodeT = ev.explodeT - dt
	if ev.explodeT <= 0 and ev.r < R * 0.6 then
		ev.explodeT = 0.05
		local a = math.random() * 6.2832
		local p = VecAdd(c, Vec(math.cos(a) * ev.r, rnd(1, 6), math.sin(a) * ev.r))
		Explosion(p, clamp(lv.size * lerp(4, 2, ev.r / (R * 0.6)), 0.5, 4), ev.owner)
	end
	-- players: pushed once when the front passes them
	for p in Players() do
		if not ev.hitPlayers[p] then
			local pp = GetPlayerTransform(p).pos
			local d = VecLength(VecSub(pp, c))
			if d <= ev.r then
				ev.hitPlayers[p] = true
				if d < R then
					local out = VecSub(pp, c)
					out[2] = 0
					out = VecLength(out) > 0.01 and VecNormalize(out) or Vec(1, 0, 0)
					local f = 1 - d / R
					SetPlayerVelocity(VecAdd(GetPlayerVelocity(p), VecAdd(VecScale(out, 18 * f + 3), Vec(0, 6 * f + 1, 0))), p)
					local dmg = ({ 0, 0.5, 1.2 })[s.damage + 1] * f
					if dmg > 0 then ApplyPlayerDamage(p, dmg, "falling moon", ev.owner) end
				end
			end
		end
	end
	if ev.r >= R and ev.next > #ev.items then
		ev.phase = "aftermath"
		ev.t = 0
		shared.m.phase = "aftermath"
		shared.m.t = 0
	end
end

-- The destruction worker: crater tiles first, then probes in the swept bands. A probe
-- looks for the nearest solid thing within 3.5 m of a random point in the band (heights
-- weighted towards the ground floors, so buildings lose their supports and collapse) and
-- punches a hole there, sized by distance from the centre; hard materials only near the
-- centre. Open ground is skipped. Everything stays within the per-step budget; the rest
-- waits for the next step, so the collapse keeps going behind the front.
function server.work(ev, dt)
	local s = ev.s
	local c = ev.center
	local R = s.radius
	local lv = ev.level
	local budget, holes, probes, fires = HOLE_R2_BUDGET, 0, 0, 0
	-- crater ring (at most half the budget per step)
	local tr0 = ev.craterR
	while ev.craterNext <= #ev.crater and budget > HOLE_R2_BUDGET * 0.5 and holes < HOLES_PER_UPDATE do
		local tile = ev.crater[ev.craterNext]
		ev.craterNext = ev.craterNext + 1
		MakeHole(tile.pos, tr0, tr0 * 0.9, tr0 * 0.8, true)
		budget = budget - tr0 * tr0
		holes = holes + 1
	end
	while #ev.queue > 0 and probes < PROBES_PER_UPDATE and holes < HOLES_PER_UPDATE and budget > 0 do
		local band = ev.queue[1]
		band.n = band.n - 1
		if band.n <= 0 then table.remove(ev.queue, 1) end
		probes = probes + 1
		local a = math.random() * 6.2832
		local rad = math.sqrt(rnd(band.r0 * band.r0, band.r1 * band.r1))
		local u = math.random()
		local h = (u < 0.45) and rnd(0.3, 4) or ((u < 0.8) and rnd(4, 12) or rnd(12, 28))
		local sample = VecAdd(c, Vec(math.cos(a) * rad, h, math.sin(a) * rad))
		if ev.moonBody ~= 0 then QueryRejectBody(ev.moonBody) end
		QueryRequire("physical")
		local hit, point, n = QueryClosestPoint(sample, 3.5)
		if hit and not (n[2] > 0.7 and point[2] - c[2] < 1.0) then
			local k = clamp(rad / R, 0, 1)
			local r0 = lv.size * (6.5 - 3.0 * k)
			local r2 = r0 * 0.85 * clamp(1 - k / 0.45, 0, 1)   -- hard materials near the centre (r2 <= r1)
			MakeHole(point, r0, r0 * 0.85, r2, true)
			budget = budget - r0 * r0
			holes = holes + 1
			if s.fire and k < 0.7 and holes % 4 == 0 and fires < FIRES_PER_UPDATE then
				SpawnFire(point)
				fires = fires + 1
			end
		end
	end
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.snd = {
		roar = LoadSound("MOD/snd/roar.ogg", 200),
		impact = LoadSound("MOD/snd/impact.ogg", 400),
		beep = LoadSound("MOD/snd/beep.ogg"),
		chime = LoadSound("MOD/snd/chime.ogg"),
	}
	client.moon = LoadSprite("MOD/ui/moon.png")
	client.glow = LoadSprite("MOD/ui/glow.png")
	client.shock = LoadSprite("MOD/ui/shock.png")
	client.anim = {}
	client.lastN = 0
	client.phase = "idle"
	client.roared = false
	client.lastBeep = -1
	client.flash = 0
	client.shake = 0
	client.passed = false
end

function client.tick(dt)
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local m = shared.m
	if m.n ~= client.lastN then
		client.lastN = m.n
		client.roared = false
		client.passed = false
		PlaySound(client.snd.chime, nil, 0.7)
	end
	if m.phase ~= client.phase then
		if m.phase == "impact" then
			PlaySound(client.snd.impact, Vec(m.x, m.y, m.z), 1.0)
			client.flash = 1
		end
		client.phase = m.phase
	end
	local eye = GetPlayerCameraTransform()
	local center = Vec(m.x, m.y, m.z)
	local shake = 0
	if m.phase == "approach" then
		local left = m.T - m.t
		local I = smooth(0.35, 1.0, m.prog)
		shake = I * 0.6
		if left < 6.2 and not client.roared then
			client.roared = true
			PlaySound(client.snd.roar, center, 1.0)
		end
		local sec = math.floor(left)
		if left < 10 and sec ~= client.lastBeep then
			client.lastBeep = sec
			PlaySound(client.snd.beep, nil, 0.6)
		end
	elseif m.phase == "impact" then
		local d = VecLength(VecSub(eye.pos, center))
		local front = math.abs(d - m.r)
		shake = clamp(1 - front / 25, 0, 1) * 1.5 + 0.3
		if d < m.r and not client.passed then
			client.passed = true
			client.flash = math.max(client.flash, 0.4)
		end
	elseif m.phase == "aftermath" then
		shake = clamp(0.3 - m.t * 0.03, 0, 0.3)
	end
	if shake > 0.02 then ShakeCamera(shake) end
	client.flash = math.max(0, client.flash - dt * 0.6)

	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local a = client.anim[p]
			if not a then a = ToolAnimator() client.anim[p] = a end
			tickToolAnimator(a, dt, nil, p)
		end
	end
end

-- the far moon: an opaque, depth-tested sprite with the angular size of the real sphere;
-- once the voxel moon exists it draws itself and no sprite is drawn
function client.render(dt)
	local m = shared.m
	client.renderRing(m)
	if m.phase ~= "approach" and m.phase ~= "recede" then return end
	local cam = GetCameraTransform()
	local moonPos = Vec(m.cx, m.cy, m.cz)
	local toMoon = VecSub(moonPos, cam.pos)
	local d = math.max(VecLength(toMoon), m.mr * 1.05)
	local dir = VecScale(toMoon, 1 / VecLength(toMoon))
	local spriteDist = math.min(d, SPRITE_DIST)
	local size = 2 * spriteDist * math.tan(math.asin(clamp(m.mr / d, 0, 0.999)))
	local pos = VecAdd(cam.pos, VecScale(dir, spriteDist))
	local t = Transform(pos, QuatLookAt(pos, cam.pos))
	local red = m.prog
	-- orange heat glow around the edge, stronger as it comes in (drawn behind the opaque moon)
	DrawSprite(client.glow, t, size * 1.25, size * 1.25, 1.0, 0.42, 0.12, 0.3 + 0.6 * red, true, true)
	DrawSprite(client.moon, t, size, size, 1.0, 0.97 - 0.3 * red, 0.94 - 0.45 * red, 1, true, false)
	if m.prog > 0.6 then
		PointLight(VecAdd(cam.pos, VecScale(dir, 40)), 1, 0.4, 0.2, 6 * (m.prog - 0.6))
	end
end

-- shockwave ring on the ground at the impact
function client.renderRing(m)
	if m.phase ~= "impact" or m.r <= 1 then return end
	local c = Vec(m.x, m.y + 0.6, m.z)
	local flat = QuatEuler(-90, 0, 0)
	DrawSprite(client.shock, Transform(c, flat), 2 * m.r, 2 * m.r, 1, 0.85, 0.65, 0.85 * (1 - m.r / math.max(m.R, 1)), true, true)
end

-- dust: lifted from the ground around you while the moon comes; rolling cloud on the shock
-- front; settling dust afterwards
function client.update(dt)
	local m = shared.m
	if m.phase == "approach" then
		local I = smooth(0.35, 1.0, m.prog)
		if I > 0.05 then
			local cam = GetPlayerCameraTransform()
			ParticleReset()
			ParticleType("smoke")
			ParticleColor(0.55, 0.45, 0.38)
			ParticleRadius(0.3, 1.2 + 2 * I)
			ParticleAlpha(0.45 * I, 0)
			ParticleGravity(1 + 3 * I)
			ParticleDrag(0.3)
			local wind = Vec(-m.dx * 6 * I, 0, -m.dz * 6 * I)
			for i = 1, math.floor(2 + 10 * I) do
				local p = VecAdd(cam.pos, Vec(rnd(-25, 25), -1.4, rnd(-25, 25)))
				SpawnParticle(p, VecAdd(wind, Vec(rnd(-1, 1), rnd(1, 3) * I, rnd(-1, 1))), rnd(2, 4))
			end
		end
		return
	end
	if m.phase ~= "impact" and m.phase ~= "aftermath" then return end
	local cam = GetPlayerCameraTransform()
	local center = Vec(m.x, m.y, m.z)
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.5, 0.42, 0.35, 0.65, 0.6, 0.55)
	ParticleRadius(1.5, 4)
	ParticleAlpha(0.6, 0)
	ParticleGravity(0.3)
	ParticleDrag(0.4)
	ParticleCollide(0)
	if m.phase == "impact" then
		local toCam = VecSub(cam.pos, center)
		local baseA = math.atan2(toCam[3], toCam[1])
		for i = 1, 14 do
			local a = baseA + rnd(-0.6, 0.6)
			local p = VecAdd(center, Vec(math.cos(a) * m.r, rnd(0, 6), math.sin(a) * m.r))
			SpawnParticle(p, Vec(math.cos(a) * 20, rnd(2, 8), math.sin(a) * 20), rnd(2, 4))
		end
		ParticleReset()
		ParticleType("plain")
		ParticleColor(1, 0.6, 0.2, 0.3, 0.1, 0.05)
		ParticleRadius(0.2, 0.05)
		ParticleEmissive(8, 0)
		ParticleGravity(-10)
		ParticleCollide(1)
		for i = 1, 6 do SpawnParticle(VecAdd(center, Vec(0, m.mr * 0.8, 0)), GetRandomDirection(rnd(15, 40)), rnd(1, 3)) end
	elseif m.t < 20 then
		for i = 1, 4 do
			local p = VecAdd(cam.pos, Vec(rnd(-30, 30), rnd(0, 10), rnd(-30, 30)))
			SpawnParticle(p, Vec(rnd(-1, 1), 0.2, rnd(-1, 1)), rnd(4, 7))
		end
	end
end

function client.draw(dt)
	local m = shared.m
	local s = readSettings()
	if m.phase == "approach" then
		local I = smooth(0.35, 1.0, m.prog)
		UiSoundLoop("MOD/snd/rumble.ogg", 0.2 + 0.8 * I, 0.8 + 0.3 * I)
		if I > 0.3 then UiSoundLoop("MOD/snd/wind.ogg", I * 0.8, 1.0) end
		UiPush()
			UiColor(0.6, 0.12, 0.05, 0.22 * I)
			UiRect(UiWidth(), UiHeight())
		UiPop()
	elseif m.phase == "aftermath" and m.t < 15 then
		UiSoundLoop("MOD/snd/rumble.ogg", 0.6 * (1 - m.t / 15), 0.7)
	end
	if client.flash > 0.01 then
		UiPush()
			UiColor(1, 0.97, 0.9, math.min(1, client.flash * 1.4))
			UiRect(UiWidth(), UiHeight())
		UiPop()
	end
	if GetBool("game.ui.hidemods") then return end
	if m.phase == "approach" and s.countdown then
		local left = math.max(0, m.T - m.t)
		UiPush()
			UiTranslate(UiCenter(), 70)
			UiAlign("center middle")
			UiTextShadow(0, 0, 0, 0.7, 2)
			UiFont("bold.ttf", 22)
			UiColor(1, 0.5, 0.4, 1)
			UiText(tr("IMPACT IN", "ДО УДАРА"))
			UiTranslate(0, 40)
			UiFont("bold.ttf", 46)
			if left < 10 and math.floor(left * 2) % 2 == 0 then UiColor(1, 0.2, 0.15, 1) else UiColor(1, 1, 1, 1) end
			UiText(string.format("%02d:%02d", math.floor(left / 60), math.floor(left % 60)))
		UiPop()
	end
	if GetPlayerTool() == TOOL and GetPlayerCanUseTool() then
		UiPush()
			UiTranslate(UiCenter(), UiHeight() - 160)
			UiAlign("center middle")
			UiTextShadow(0, 0, 0, 0.6, 1.5)
			UiFont("regular.ttf", 22)
			UiColor(1, 1, 1, 0.9)
			if m.phase == "idle" then
				UiText(tr("LMB: call the moon down on the aim point", "ЛКМ: обрушить луну в точку прицела"))
			elseif m.phase == "approach" and m.body == 0 then
				UiText(tr("RMB: send the moon back", "ПКМ: отправить луну обратно"))
			elseif m.phase == "approach" then
				UiText(tr("Too late to stop it!", "Остановить уже нельзя!"))
			else
				UiText(tr("Wait for the dust to settle", "Ждите, пока осядет пыль"))
			end
		UiPop()
	end
end
