#version 2
-- Singularity Grenade / Гравитационная граната
-- Throwable tool: the grenade opens into a short-lived singularity that pulls
-- loose bodies, debris and players in, shreds weak materials and finally
-- collapses with an outward blast.
--
-- Server: input, throwing, grenade state machine, forces, holes, damage.
-- Client: tool animation, sounds, lights, particles, camera shake, HUD.
-- Only the `shared` table crosses the boundary (shared.g[id] = grenade state).

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "singularity"
local GRENADE_XML = "<body dynamic='true'><vox file='MOD/vox/grenade.vox' scale='0.2'/></body>"
local GRENADE_TAG = "singularity_grenade"
local REQ = "level.singularity_grenade."

-- throwing
local CHARGE_TIME = 1.0       -- seconds of holding LMB for a full-power throw
local MIN_SPEED = 7.0
local MAX_SPEED = 25.0
local COOLDOWN = 0.55
local MAX_ALIVE = 4           -- grenades in the world at the same time (performance)

-- grenade state machine
local REST_SPEED = 0.7
local REST_TIME = 0.2
local REST_FUSE = 1.5         -- timer mode: open 1.5 s after the grenade stops
local IMPACT_FUSE = 0.12      -- impact mode: open almost immediately after the first hit
local IMPACT_DV = 3.0         -- velocity change (m/s) in one physics step that counts as a hit
local MAX_FLIGHT = 12.0
local HOVER = 1.0             -- the opened grenade rises this high above its rest point
local OPEN_RAMP = 0.6
local IMPLODE_TIME = 0.32     -- matches the implosion part of collapse.ogg
local DONE_TIME = 1.5

-- forces and budgets
local BASE_ACCEL = 24.0       -- m/s^2 at the core for strength 1.0
local MASS_LIMIT = 450.0      -- kg; heavier bodies get proportionally less pull
local MAX_BODY_SPEED = 28.0
local ORBIT_SPEED = 7.0
local SCAN_INTERVAL = 0.2     -- seconds between QueryAabbBodies calls per singularity
local MAX_TRACKED = 120       -- bodies kept per singularity
local BODIES_PER_UPDATE = 40  -- bodies that receive an impulse per physics step
local TEAR_INTERVAL = 0.12
local MAX_HOLES = 48
local BLAST_PER_UPDATE = 50
local MAX_BLAST = 160
local BLAST_SPEED = 16.0
local PLAYER_ACCEL = 16.0
local PLAYER_MAX_SPEED = 18.0
local DAMAGE_RATE = { 0.0, 0.08, 0.25 }   -- per second in the core: off / low / high

-- materials that the singularity tears (multiplier for the hole size)
local WEAK = { glass = 1.4, wood = 1.0, plastic = 1.1, plaster = 0.9, foliage = 1.2 }

---------------------------------------------------------------------------
-- shared helpers (pure functions, used on both sides)
---------------------------------------------------------------------------

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function smoothstep(a, b, x) local t = clamp((x - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function rnd(a, b) return a + (b - a) * math.random() end

local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getI(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetInt(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end

function readSettings()
	local s = {}
	s.radius = clamp(getF("radius", 8), 3, 20)
	s.strength = clamp(getF("strength", 1), 0.2, 3)
	s.duration = clamp(getF("duration", 4), 1, 15)
	s.ammo = math.floor(clamp(getI("ammo", 5), 1, 99))
	s.impact = getB("impact", false)
	s.pullPlayer = getB("pullplayer", true)
	s.damage = math.floor(clamp(getI("damage", 1), 0, 2))
	s.tear = getB("tear", true)
	s.blast = getB("blast", false)
	return s
end

local function isRussian() return GetInt("options.language") == 7 end
local function tr(en, ru) if isRussian() then return ru end return en end

local function coreRadius(R) return clamp(0.12 * R + 0.4, 0.6, 2.2) end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	server.settings = readSettings()
	RegisterTool(TOOL, tr("Singularity Grenade", "Гравитационная граната"), "MOD/prefab/tool.xml", 6)
	SetToolAmmoPickupAmount(TOOL, 3)
	server.players = {}
	server.grenades = {}
	server.nextId = 1
	shared.g = {}
	shared.maxAlive = MAX_ALIVE
	server.reqDone = GetInt(REQ .. "reqcount")
	SetBool(REQ .. "available", true)
end

function server.aliveCount()
	local n = 0
	for _, g in pairs(server.grenades) do
		if g.phase ~= "done" then n = n + 1 end
	end
	return n
end

function server.tick(dt)
	for p in PlayersAdded() do
		server.players[p] = { charge = 0, charging = false, cooldown = 0 }
		SetToolEnabled(TOOL, true, p)
		SetToolAmmo(TOOL, server.settings.ammo, p)
	end
	for p in PlayersRemoved() do
		server.players[p] = nil
	end
	for p in Players() do
		server.tickPlayer(p, dt)
	end
	server.processRequests()
end

function server.tickPlayer(p, dt)
	local st = server.players[p]
	if not st then
		st = { charge = 0, charging = false, cooldown = 0 }
		server.players[p] = st
	end
	st.cooldown = math.max(0, st.cooldown - dt)
	if GetPlayerTool(p) ~= TOOL or not GetPlayerCanUseTool(p) or GetPlayerVehicle(p) ~= 0 then
		st.charging = false
		st.charge = 0
		return
	end
	local ammo = GetToolAmmo(TOOL, p)
	local canThrow = ammo > 0 and st.cooldown <= 0 and server.aliveCount() < MAX_ALIVE
	if InputPressed("usetool", p) and canThrow then
		st.charging = true
		st.charge = 0
	end
	if st.charging then
		if InputDown("usetool", p) then
			st.charge = math.min(1, st.charge + dt / CHARGE_TIME)
		end
		if InputReleased("usetool", p) or not InputDown("usetool", p) then
			server.throw(p, st.charge, false)
			st.charging = false
			st.charge = 0
			st.cooldown = COOLDOWN
		end
	elseif InputPressed("grab", p) and canThrow and GetPlayerGrabBody(p) == 0 and GetPlayerPickBody(p) == 0 then
		server.throw(p, 0, true)
		st.cooldown = COOLDOWN
	end
end

function server.throw(p, charge, underhand)
	-- the limit again: a grenade may have appeared while charging
	if server.aliveCount() >= MAX_ALIVE then return end
	local s = readSettings()
	server.settings = s
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	local right = TransformToParentVec(eye, Vec(1, 0, 0))
	local up = TransformToParentVec(eye, Vec(0, 1, 0))
	local pos, vel
	if underhand then
		local pt = GetPlayerTransform(p)
		local flat = TransformToParentVec(pt, Vec(0, 0, -1))
		pos = VecAdd(pt.pos, VecAdd(Vec(0, 0.9, 0), VecScale(flat, 0.45)))
		vel = VecAdd(VecScale(flat, 2.5), Vec(0, 1.2, 0))
	else
		local speed = MIN_SPEED + (MAX_SPEED - MIN_SPEED) * charge
		pos = VecAdd(eye.pos, VecAdd(VecScale(fwd, 0.55), VecAdd(VecScale(right, 0.22), VecScale(up, -0.15))))
		vel = VecAdd(VecScale(fwd, speed), Vec(0, 1.5 + 1.5 * charge, 0))
	end
	-- keep the spawn point out of walls the player is standing against
	local d = VecSub(pos, eye.pos)
	local len = VecLength(d)
	local dir = VecNormalize(d)
	QueryRejectPlayer(p)
	QueryRequire("physical")
	local hit, dist = QueryRaycast(eye.pos, dir, len + 0.15)
	if hit then
		pos = VecAdd(eye.pos, VecScale(dir, math.max(0.05, dist - 0.2)))
	end
	vel = VecAdd(vel, VecScale(GetPlayerVelocity(p), 0.8))

	if not server.spawnGrenade(pos, vel, p, s) then
		return
	end

	local ammo = GetToolAmmo(TOOL, p)
	if ammo < 9999 and not GetBool("level.unlimitedammo") then
		SetToolAmmo(TOOL, math.max(0, ammo - 1), p)
	end
end

-- spawn one grenade body and register it in the state machine
function server.spawnGrenade(pos, vel, owner, s)
	local ents = Spawn(GRENADE_XML, Transform(pos, QuatEuler(rnd(0, 360), rnd(0, 360), 0)))
	local body = 0
	for i = 1, #ents do
		if GetEntityType(ents[i]) == "body" then
			body = ents[i]
			break
		end
	end
	if body == 0 then
		return false
	end
	SetBodyVelocity(body, vel)
	SetBodyAngularVelocity(body, Vec(rnd(-8, 8), rnd(-8, 8), rnd(-8, 8)))
	SetTag(body, GRENADE_TAG)

	local id = server.nextId
	server.nextId = id + 1
	server.grenades[id] = {
		id = id, body = body, owner = owner, phase = "fly", t = 0, rest = 0, fuse = 0,
		prevVel = VecCopy(vel), boosted = 0, s = s, center = VecCopy(pos),
		tracked = {}, cursor = 1, scanT = 0, tearT = 0, holes = 0,
		blastList = nil, blastCursor = 1,
	}
	shared.g[id] = {
		body = body, phase = "fly", x = pos[1], y = pos[2], z = pos[3], cx = pos[1], cy = pos[2], cz = pos[3],
		r = s.radius, dur = s.duration, t = 0, fuse = 0, bounces = 0, hit = 0, owner = owner,
	}
	return true
end

-- Other mods (for example the camera drone) can drop a Singularity Grenade by
-- writing a request into the registry:
--   level.singularity_grenade.req.<n>.x/y/z/vx/vy/vz (float), .owner (int)
--   then SetInt("level.singularity_grenade.reqcount", n)
-- This mod sets level.singularity_grenade.available = true so they can check.
function server.processRequests()
	local count = GetInt(REQ .. "reqcount")
	while server.reqDone < count do
		local k = REQ .. "req." .. (server.reqDone + 1)
		-- at the limit: keep the request queued until a grenade is gone
		if HasKey(k) and server.aliveCount() >= MAX_ALIVE then break end
		server.reqDone = server.reqDone + 1
		if HasKey(k) then
			local pos = Vec(GetFloat(k .. ".x"), GetFloat(k .. ".y"), GetFloat(k .. ".z"))
			local vel = Vec(GetFloat(k .. ".vx"), GetFloat(k .. ".vy"), GetFloat(k .. ".vz"))
			local owner = GetInt(k .. ".owner")
			ClearKey(k)
			server.spawnGrenade(pos, vel, owner, readSettings())
		end
	end
end

function server.update(dt)
	for id, g in pairs(server.grenades) do
		server.updateGrenade(g, dt)
	end
end

-- Emissive glow of the grenade body. The body is spawned by the server, so in
-- #version 2 only server code may change it (clients may only read it).
function server.glow(g, scale)
	if g.glow and math.abs(g.glow - scale) < 0.05 then return end
	g.glow = scale
	local shapes = GetBodyShapes(g.body)
	for i = 1, #shapes do SetShapeEmissiveScale(shapes[i], scale) end
end

function server.remove(g)
	server.grenades[g.id] = nil
	shared.g[g.id] = nil
end

function server.updateGrenade(g, dt)
	g.t = g.t + dt
	local sg = shared.g[g.id]
	if g.phase == "fly" or g.phase == "armed" then
		if not IsHandleValid(g.body) then
			server.remove(g)
			return
		end
		local pos = GetBodyTransform(g.body).pos
		if pos[2] < -50 then
			Delete(g.body)
			server.remove(g)
			return
		end
		local vel = GetBodyVelocity(g.body)
		local dv = VecLength(VecSub(vel, g.prevVel))
		if dv > IMPACT_DV and g.t > 0.05 then
			sg.bounces = sg.bounces + 1
			sg.hit = clamp(dv / 15, 0.1, 1)
			-- a little extra bounce: the grenade is springy, not a brick
			if g.prevVel[2] < -3 and vel[2] > -0.5 and g.boosted < 3 then
				vel = Vec(vel[1], math.max(vel[2], -g.prevVel[2] * 0.35), vel[3])
				SetBodyVelocity(g.body, vel)
				g.boosted = g.boosted + 1
			end
			if g.s.impact and g.phase == "fly" then
				g.phase = "armed"
				g.fuse = IMPACT_FUSE
			end
		end
		g.prevVel = vel
		if g.phase == "fly" then
			if VecLength(vel) < REST_SPEED then g.rest = g.rest + dt else g.rest = 0 end
			if g.rest > REST_TIME then
				g.phase = "armed"
				g.fuse = g.s.impact and IMPACT_FUSE or REST_FUSE
			elseif g.t > MAX_FLIGHT then
				g.phase = "armed"
				g.fuse = 0.3
			end
		else
			g.fuse = g.fuse - dt
			if g.fuse <= 0 then
				server.open(g, pos)
			end
		end
		sg.x, sg.y, sg.z = pos[1], pos[2], pos[3]
		sg.phase = g.phase
		sg.fuse = g.fuse
		-- blink faster as the fuse runs down (the client plays the matching beeps)
		local blink = 0.4
		if g.phase == "armed" then
			local interval = clamp(g.fuse / 3, 0.08, 0.5)
			blink = ((g.t % interval) < 0.06) and 1.6 or 0.4
		end
		server.glow(g, blink)
	elseif g.phase == "open" or g.phase == "collapse" then
		server.updateOpen(g, sg, dt)
	elseif g.phase == "done" then
		server.updateBlast(g, dt)
		sg.t = g.t
		if g.t > DONE_TIME and (g.blastList == nil or g.blastCursor > #g.blastList) then
			server.remove(g)
		end
	end
end

function server.open(g, pos)
	g.phase = "open"
	g.t = 0
	QueryRejectBody(g.body)
	QueryRequire("physical")
	local hit, dist = QueryRaycast(pos, Vec(0, 1, 0), HOVER + 0.4)
	local h = HOVER
	if hit then h = math.max(0.15, dist - 0.4) end
	g.center = VecAdd(pos, Vec(0, h, 0))
	SetBodyGravityScale(g.body, 0)
	local sg = shared.g[g.id]
	sg.cx, sg.cy, sg.cz = g.center[1], g.center[2], g.center[3]
	sg.phase = "open"
	sg.t = 0
	g.scanT = 0
	g.tearT = 0.2
end

function server.updateOpen(g, sg, dt)
	local D = g.s.duration
	local t = g.t
	local ramp = smoothstep(0, OPEN_RAMP, t)
	local collapsing = t > D - IMPLODE_TIME
	local mult = ramp
	if collapsing then mult = 2.2 end

	if IsHandleValid(g.body) then
		local bp = GetBodyTransform(g.body).pos
		SetBodyVelocity(g.body, VecScale(VecSub(g.center, bp), 6))
		SetBodyAngularVelocity(g.body, Vec(2, 6 + 16 * ramp, 3))
		server.glow(g, 1 + 2 * ramp)
	end

	server.pullBodies(g, dt, mult, collapsing)
	server.pullPlayers(g, dt, mult)
	if g.s.tear then
		server.tear(g, dt, collapsing)
	end

	if collapsing then g.phase = "collapse" end
	sg.phase = g.phase
	sg.t = t
	if t >= D then
		server.collapse(g)
	end
end

function server.scan(g)
	local R = g.s.radius
	local c = g.center
	QueryRequire("physical dynamic")
	if IsHandleValid(g.body) then QueryRejectBody(g.body) end
	local list = QueryAabbBodies(VecSub(c, Vec(R, R, R)), VecAdd(c, Vec(R, R, R)))
	local tracked = {}
	for i = 1, #list do
		local b = list[i]
		if b ~= g.body and GetBodyPlayer(b) == 0 and not HasTag(b, GRENADE_TAG) then
			tracked[#tracked + 1] = b
			if #tracked >= MAX_TRACKED then break end
		end
	end
	return tracked
end

function server.pullBodies(g, dt, mult, collapsing)
	g.scanT = g.scanT - dt
	if g.scanT <= 0 then
		g.scanT = SCAN_INTERVAL
		g.tracked = server.scan(g)
		g.cursor = 1
	end
	local n = #g.tracked
	if n == 0 then return end
	local per = math.min(n, BODIES_PER_UPDATE)
	local stride = n / per
	local strength = BASE_ACCEL * g.s.strength * mult
	for k = 1, per do
		local idx = g.cursor
		g.cursor = (g.cursor % n) + 1
		local b = g.tracked[idx]
		if IsHandleValid(b) and IsBodyDynamic(b) then
			server.pullBody(g, b, dt * stride, strength, collapsing)
		end
	end
end

function server.pullBody(g, b, h, strength, collapsing)
	local mass = GetBodyMass(b)
	if mass <= 0 then return end
	local massK = clamp(MASS_LIMIT * g.s.strength / mass, 0, 1)
	if massK < 0.02 then return end
	local bt = GetBodyTransform(b)
	local com = TransformToParentPoint(bt, GetBodyCenterOfMass(b))
	local d = VecSub(g.center, com)
	local dist = VecLength(d)
	local R = g.s.radius
	if dist > R or dist < 0.01 then return end
	local dir = VecScale(d, 1 / dist)
	local vel = GetBodyVelocity(b)
	local core = coreRadius(R)
	local acc
	local point = com
	if dist > core then
		local x = dist / R
		local fall = (1 - x) ^ 1.2 + 0.15 * (1 - x)
		acc = VecAdd(VecScale(dir, strength * fall), Vec(0, 4 * fall, 0))
	else
		-- inside the core: steer onto a tightening orbit and tumble
		local tang = VecCross(Vec(0, 1, 0), dir)
		if VecLength(tang) < 0.1 then tang = VecCross(Vec(1, 0, 0), dir) end
		tang = VecNormalize(tang)
		local orbitR = core * 0.45
		if collapsing then orbitR = 0.15 end
		local desired = VecAdd(VecScale(tang, ORBIT_SPEED), VecScale(dir, (dist - orbitR) * 4))
		local k = math.min(1, 5 * h)
		acc = VecAdd(VecScale(VecSub(desired, vel), k / h), Vec(0, 10, 0))
		point = VecAdd(com, Vec(0, 0.2, 0))
	end
	local imp = VecScale(acc, mass * massK * h)
	ApplyBodyImpulse(b, point, imp)
	local nv = VecAdd(vel, VecScale(imp, 1 / mass))
	local sp = VecLength(nv)
	if sp > MAX_BODY_SPEED then
		SetBodyVelocity(b, VecScale(nv, MAX_BODY_SPEED / sp))
	end
end

function server.pullPlayers(g, dt, mult)
	local R = g.s.radius
	local core = coreRadius(R)
	for p in Players() do
		local pos = VecAdd(GetPlayerTransform(p).pos, Vec(0, 0.9, 0))
		local d = VecSub(g.center, pos)
		local dist = VecLength(d)
		if dist < R and dist > 0.01 then
			if g.s.pullPlayer then
				local fall = (1 - dist / R) ^ 1.5
				local a = PLAYER_ACCEL * math.sqrt(g.s.strength) * fall * mult
				local v = VecAdd(GetPlayerVelocity(p), VecScale(d, a * dt / dist))
				if dist < core then
					v = VecScale(v, 1 - math.min(0.5, 3 * dt))
				end
				local sp = VecLength(v)
				if sp > PLAYER_MAX_SPEED then v = VecScale(v, PLAYER_MAX_SPEED / sp) end
				SetPlayerVelocity(v, p)
			end
			local rate = DAMAGE_RATE[g.s.damage + 1] or 0
			if rate > 0 and dist < core + 0.5 then
				ApplyPlayerDamage(p, rate * dt * math.min(mult, 1.5), "singularity", g.owner)
			end
		end
	end
end

function server.tear(g, dt, collapsing)
	if g.holes >= MAX_HOLES then return end
	g.tearT = g.tearT - dt
	if g.tearT > 0 then return end
	g.tearT = collapsing and 0.05 or TEAR_INTERVAL
	local maxd = g.s.radius * 0.6
	local rays = collapsing and 4 or 2
	for i = 1, rays do
		local dir = GetRandomDirection(1)
		if IsHandleValid(g.body) then QueryRejectBody(g.body) end
		QueryRequire("physical")
		local hit, dist, normal, shape = QueryRaycast(g.center, dir, maxd)
		if hit and shape ~= 0 then
			local p = VecAdd(g.center, VecScale(dir, dist + 0.05))
			local mat = GetShapeMaterialAtPosition(shape, p)
			local k = WEAK[mat]
			if k then
				local r = 0.2 + 0.35 * (1 - dist / maxd) * k
				MakeHole(p, r, 0, 0, false)
				g.holes = g.holes + 1
				if g.holes >= MAX_HOLES then return end
			end
		end
	end
end

function server.collapse(g)
	local c = g.center
	local R = g.s.radius * 1.15
	QueryRequire("physical dynamic")
	if IsHandleValid(g.body) then QueryRejectBody(g.body) end
	local list = QueryAabbBodies(VecSub(c, Vec(R, R, R)), VecAdd(c, Vec(R, R, R)))
	local blast = {}
	for i = 1, #list do
		if GetBodyPlayer(list[i]) == 0 and not HasTag(list[i], GRENADE_TAG) then
			blast[#blast + 1] = list[i]
			if #blast >= MAX_BLAST then break end
		end
	end
	g.blastList = blast
	g.blastCursor = 1
	g.blastR = R

	for p in Players() do
		local pos = VecAdd(GetPlayerTransform(p).pos, Vec(0, 0.9, 0))
		local d = VecSub(pos, c)
		local dist = VecLength(d)
		if dist < R then
			local k = 1 - dist / R
			if g.s.pullPlayer then
				local out = VecNormalize(VecAdd(d, Vec(0, 0.5, 0)))
				SetPlayerVelocity(VecAdd(GetPlayerVelocity(p), VecScale(out, 10 * k * math.sqrt(g.s.strength))), p)
			end
			local rate = DAMAGE_RATE[g.s.damage + 1] or 0
			if rate > 0 then
				ApplyPlayerDamage(p, rate * 1.5 * k, "singularity", g.owner)
			end
		end
	end

	Paint(c, math.min(g.s.radius * 0.35, 4.5), "explosion", 0.85)
	MakeHole(c, 0.7, 0, 0, false)
	if g.s.blast then
		Explosion(c, clamp(g.s.radius / 5, 0.5, 2.5), g.owner)
	end
	if IsHandleValid(g.body) then Delete(g.body) end

	g.phase = "done"
	g.t = 0
	local sg = shared.g[g.id]
	sg.phase = "done"
	sg.t = 0
end

function server.updateBlast(g, dt)
	local list = g.blastList
	if not list or g.blastCursor > #list then return end
	local c = g.center
	local R = g.blastR
	local last = math.min(#list, g.blastCursor + BLAST_PER_UPDATE - 1)
	local power = BLAST_SPEED * math.sqrt(g.s.strength)
	for i = g.blastCursor, last do
		local b = list[i]
		if IsHandleValid(b) and IsBodyDynamic(b) then
			local mass = GetBodyMass(b)
			if mass > 0 then
				local massK = clamp(MASS_LIMIT * g.s.strength / mass, 0, 1)
				local com = TransformToParentPoint(GetBodyTransform(b), GetBodyCenterOfMass(b))
				local d = VecSub(com, c)
				local dist = VecLength(d)
				if dist < R and massK > 0.02 then
					local dir
					if dist < 0.05 then dir = GetRandomDirection(1) else dir = VecScale(d, 1 / dist) end
					dir = VecNormalize(VecAdd(dir, Vec(0, 0.35, 0)))
					local speed = power * (1 - dist / R) ^ 0.7 + 3
					ApplyBodyImpulse(b, com, VecScale(dir, mass * massK * speed))
				end
			end
		end
	end
	g.blastCursor = last + 1
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

local PARTICLES_PER_UPDATE = 40

function client.init()
	client.snd = {
		throw = LoadSound("MOD/snd/throw.ogg"),
		bounce = LoadSound("MOD/snd/bounce.ogg"),
		beep = LoadSound("MOD/snd/beep.ogg"),
		open = LoadSound("MOD/snd/open.ogg", 15),
		collapse = LoadSound("MOD/snd/collapse.ogg", 25),
	}
	client.hum = LoadLoop("MOD/snd/hum.ogg", 15)
	client.anim = {}
	client.toolShapes = {}
	client.seen = {}
	client.charge = 0
	client.charging = false
	client.thrownT = 10
	client.vignette = 0
	client.flash = 0
	client.ringAngle = 0
	client.time = 0
end

function client.initPlayer(p)
	local a = ToolAnimator()
	a.armPitchScale = 0.3
	a.toolPitchScale = 0.2
	a.maxActionPoseTime = 0.3
	client.anim[p] = a
end

local function grenadePos(sg)
	if sg.body ~= 0 and IsHandleValid(sg.body) then
		return GetBodyTransform(sg.body).pos
	end
	return Vec(sg.x, sg.y, sg.z)
end

function client.tick(dt)
	client.time = client.time + dt
	for p in PlayersAdded() do client.initPlayer(p) end
	for p in PlayersRemoved() do
		client.anim[p] = nil
		client.toolShapes[p] = nil
	end

	client.tickLocalCharge(dt)
	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			client.animateTool(p, dt)
		end
	end
	client.tickGrenades(dt)
	client.flash = math.max(0, client.flash - dt * 2.5)
end

function client.tickLocalCharge(dt)
	client.thrownT = client.thrownT + dt
	local usable = GetPlayerTool() == TOOL and GetPlayerCanUseTool() and GetPlayerVehicle() == 0 and GetToolAmmo(TOOL) > 0
	if usable and InputPressed("usetool") then
		client.charging = true
		client.charge = 0
	end
	if client.charging then
		if usable and InputDown("usetool") then
			client.charge = math.min(1, client.charge + dt / CHARGE_TIME)
		else
			client.charging = false
			client.charge = 0
			client.thrownT = 0
		end
	end
	if usable and InputPressed("grab") and GetPlayerGrabBody() == 0 and GetPlayerPickBody() == 0 then
		client.thrownT = 0
	end
end

function client.animateTool(p, dt)
	local a = client.anim[p]
	if not a then
		client.initPlayer(p)
		a = client.anim[p]
	end
	local c = 0
	local snap = 0
	if IsPlayerLocal(p) then
		c = client.charge
		snap = math.max(0, 1 - client.thrownT / 0.18)
	end
	a.forceActionPose = c > 0
	a.offsetTransform = Transform(Vec(0.04 * c, 0.07 * c, 0.22 * c - 0.25 * snap), QuatEuler(25 * c, 0, 0))
	tickToolAnimator(a, dt, nil, p)

	-- spin the brass rings, pulse the core
	local b = GetToolBody(p)
	if b == 0 then return end
	local ts = client.toolShapes[p]
	if not ts or ts.body ~= b then
		ts = { body = b, rings = {}, cores = {} }
		local shapes = GetBodyShapes(b)
		for i = 1, #shapes do
			local sx, sy, sz, vs = GetShapeSize(shapes[i])
			local t0 = GetShapeLocalTransform(shapes[i])
			local center = Vec(sx * vs * 0.5, sy * vs * 0.5, sz * vs * 0.5)
			if sx < sy and sx < sz then
				ts.rings[#ts.rings + 1] = { shape = shapes[i], t0 = t0, center = center, axis = Vec(1, 0, 0), speed = 1.0 }
			elseif sy < sx and sy < sz then
				ts.rings[#ts.rings + 1] = { shape = shapes[i], t0 = t0, center = center, axis = Vec(0, 1, 0), speed = -1.4 }
			else
				ts.cores[#ts.cores + 1] = shapes[i]
			end
		end
		client.toolShapes[p] = ts
	end
	client.ringAngle = client.ringAngle + dt * (70 + 650 * c)
	for i = 1, #ts.rings do
		local r = ts.rings[i]
		local rot = QuatAxisAngle(r.axis, client.ringAngle * r.speed)
		local pivot = Transform(r.center, rot)
		local back = Transform(VecScale(r.center, -1))
		SetShapeLocalTransform(r.shape, TransformToParentTransform(r.t0, TransformToParentTransform(pivot, back)))
	end
	local glow = 0.55 + 0.25 * math.sin(client.time * 4) + 0.8 * c
	for i = 1, #ts.cores do
		SetShapeEmissiveScale(ts.cores[i], glow)
	end
end

function client.tickGrenades(dt)
	local eye = GetPlayerCameraTransform()
	local shake = 0
	local vig = 0
	for id, sg in pairs(shared.g) do
		local seen = client.seen[id]
		local pos = grenadePos(sg)
		local center = Vec(sg.cx, sg.cy, sg.cz)
		if not seen then
			seen = { phase = "", bounces = 0, beepT = 0, flashT = 10, groundY = nil, center = center }
			client.seen[id] = seen
			if sg.phase == "fly" then
				PlaySound(client.snd.throw, pos, 0.8)
			end
		end
		seen.center = center
		seen.r = sg.r
		if sg.bounces > seen.bounces then
			seen.bounces = sg.bounces
			PlaySound(client.snd.bounce, pos, 0.3 + 0.7 * sg.hit, true, 0.9 + 0.2 * math.random())
		end
		if sg.phase ~= seen.phase then
			if sg.phase == "open" then
				PlaySound(client.snd.open, center, 1.0)
			elseif sg.phase == "collapse" then
				PlaySound(client.snd.collapse, center, 1.0)
			elseif sg.phase == "done" then
				if seen.phase ~= "collapse" then PlaySound(client.snd.collapse, center, 1.0) end
				client.onBlast(seen, center, sg.r, eye)
			end
			seen.phase = sg.phase
		end

		if sg.phase == "fly" or sg.phase == "armed" then
			local blink = 0.4
			if sg.phase == "armed" then
				seen.beepT = seen.beepT - dt
				local interval = clamp(sg.fuse / 3, 0.08, 0.5)
				if seen.beepT <= 0 then
					seen.beepT = interval
					PlaySound(client.snd.beep, pos, 0.5)
					seen.blink = 1
				end
				blink = (seen.blink or 0)
				seen.blink = math.max(0, (seen.blink or 0) - dt * 8)
			end
			PointLight(pos, 0.6, 0.3, 1.0, 0.4 + 1.6 * blink)
			-- the grenade body is server-authored: its glow is set on the server (server.glow)
		elseif sg.phase == "open" or sg.phase == "collapse" then
			local ramp = smoothstep(0, OPEN_RAMP, sg.t)
			local prog = clamp(sg.t / sg.dur, 0, 1)
			local collapsing = sg.phase == "collapse"
			local pitch = 0.8 + 0.4 * prog
			if collapsing then pitch = 1.6 end
			PlayLoop(client.hum, center, 0.35 + 0.65 * ramp, true, pitch)
			local flicker = 0.85 + 0.3 * math.random()
			if collapsing then
				PointLight(center, 1.0, 0.8, 1.0, 10 * flicker)
			else
				PointLight(center, 0.55, 0.25, 1.0, (2 + 5 * ramp) * flicker)
			end
			local de = VecLength(VecSub(eye.pos, center))
			local k = clamp(1 - de / (sg.r * 2.2), 0, 1)
			local s = k * (0.12 + 0.45 * prog) * ramp
			if collapsing then s = k * 0.9 end
			shake = math.max(shake, s)
			if de < sg.r then vig = math.max(vig, (1 - de / sg.r) * ramp) end
		elseif sg.phase == "done" then
			seen.flashT = sg.t
			local f = clamp(1 - sg.t / 0.45, 0, 1)
			if f > 0 then
				PointLight(center, 1.0, 0.85, 1.0, 40 * f * f)
			end
		end
	end
	-- grenades that vanished (removed on the server)
	for id, seen in pairs(client.seen) do
		if not shared.g[id] then
			if seen.phase == "open" or seen.phase == "collapse" then
				PlaySound(client.snd.collapse, seen.center, 1.0)
				client.onBlast(seen, seen.center, seen.r or 8, eye)
			end
			client.seen[id] = nil
		end
	end
	if shake > 0.01 then ShakeCamera(shake) end
	client.vignette = client.vignette + (vig - client.vignette) * math.min(1, dt * 6)
end

function client.onBlast(seen, center, R, eye)
	local de = VecLength(VecSub(eye.pos, center))
	local k = clamp(1 - de / (R * 3), 0, 1)
	client.flash = math.max(client.flash, 0.85 * k)
	if k > 0 then ShakeCamera(k) end
	seen.burst = true
end

-- particles at a fixed rate (update runs at 60 Hz)
function client.update(dt)
	local active = 0
	for id, sg in pairs(shared.g) do
		if sg.phase == "open" or sg.phase == "collapse" then active = active + 1 end
	end
	local budget = PARTICLES_PER_UPDATE
	local per = 0
	if active > 0 then per = math.floor(budget / active) end
	for id, sg in pairs(shared.g) do
		local seen = client.seen[id]
		if seen then
			if (sg.phase == "open" or sg.phase == "collapse") and per > 0 then
				client.emitSwirl(seen, sg, per)
			end
			if seen.burst then
				seen.burst = false
				client.emitBurst(Vec(sg.cx, sg.cy, sg.cz), sg.r)
			end
		end
	end
end

function client.emitSwirl(seen, sg, n)
	local c = Vec(sg.cx, sg.cy, sg.cz)
	local R = sg.r
	local core = coreRadius(R)
	local ramp = smoothstep(0, OPEN_RAMP, sg.t)
	if seen.groundY == nil then
		QueryRequire("physical static")
		local hit, dist = QueryRaycast(c, Vec(0, -1, 0), 6)
		seen.groundY = hit and (c[2] - dist) or false
	end
	local nSwirl = math.floor(n * 0.55 * ramp + 0.5)
	local nDisk = math.floor(n * 0.3 + 0.5)
	local nCore = 2
	local nDust = (seen.groundY and 2) or 0

	-- infalling streaks
	ParticleReset()
	ParticleType("plain")
	ParticleColor(0.75, 0.45, 1.0, 0.35, 0.1, 0.9)
	ParticleRadius(0.05, 0.01)
	ParticleAlpha(0.9, 0.0)
	ParticleGravity(0)
	ParticleDrag(0)
	ParticleEmissive(5, 1)
	ParticleStretch(4)
	ParticleCollide(0)
	for i = 1, nSwirl do
		local r = R * (0.35 + 0.65 * math.random())
		local a = math.random() * 6.2832
		local y = (math.random() - 0.5) * r * 0.6
		local p = VecAdd(c, Vec(math.cos(a) * r, y, math.sin(a) * r))
		local life = 0.45 + 0.4 * math.random()
		local inward = VecScale(VecSub(c, p), 0.85 / life)
		local tang = Vec(-math.sin(a) * r * 0.9 / life, 0, math.cos(a) * r * 0.9 / life)
		SpawnParticle(p, VecAdd(inward, tang), life)
	end

	-- accretion disk: short-lived particles moving tangentially at the core radius
	ParticleReset()
	ParticleType("plain")
	ParticleColor(1.0, 0.85, 1.0, 0.6, 0.3, 1.0)
	ParticleRadius(0.07, 0.03)
	ParticleAlpha(1.0, 0.0)
	ParticleGravity(0)
	ParticleDrag(0)
	ParticleEmissive(8, 2)
	ParticleCollide(0)
	local spin = client.time * 3
	for i = 1, nDisk do
		local a = spin + math.random() * 6.2832
		local rr = core * (0.6 + 0.25 * math.random())
		if sg.phase == "collapse" then rr = rr * 0.4 end
		local p = VecAdd(c, Vec(math.cos(a) * rr, (math.random() - 0.5) * 0.1, math.sin(a) * rr))
		local v = Vec(-math.sin(a) * 7, 0, math.cos(a) * 7)
		SpawnParticle(p, v, 0.12)
	end

	-- dark core
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.02, 0.0, 0.05)
	ParticleRadius(0.35 * ramp + 0.05, 0.1)
	ParticleAlpha(0.85, 0.0)
	ParticleGravity(0)
	ParticleDrag(1)
	ParticleCollide(0)
	for i = 1, nCore do
		SpawnParticle(VecAdd(c, GetRandomDirection(0.05)), GetRandomDirection(0.2), 0.25)
	end

	-- dust dragged along the ground
	if nDust > 0 then
		ParticleReset()
		ParticleType("smoke")
		ParticleColor(0.45, 0.42, 0.4)
		ParticleRadius(0.25, 0.5)
		ParticleAlpha(0.35, 0.0)
		ParticleGravity(0.5)
		ParticleDrag(0.2)
		ParticleCollide(0)
		for i = 1, nDust do
			local a = math.random() * 6.2832
			local r = R * (0.5 + 0.4 * math.random())
			local p = Vec(c[1] + math.cos(a) * r, seen.groundY + 0.15, c[3] + math.sin(a) * r)
			local v = VecAdd(VecScale(VecSub(c, p), 0.6), Vec(-math.sin(a) * 2, 0.5, math.cos(a) * 2))
			SpawnParticle(p, v, 1.2)
		end
	end
end

function client.emitBurst(c, R)
	ParticleReset()
	ParticleType("plain")
	ParticleColor(1.0, 0.9, 1.0, 0.5, 0.2, 1.0)
	ParticleRadius(0.08, 0.02)
	ParticleAlpha(1.0, 0.0)
	ParticleGravity(-2)
	ParticleDrag(0.3)
	ParticleEmissive(10, 0)
	ParticleStretch(6)
	ParticleCollide(0)
	for i = 1, 60 do
		SpawnParticle(c, GetRandomDirection(rnd(8, 22)), rnd(0.3, 0.8))
	end
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.35, 0.25, 0.45, 0.6, 0.6, 0.6)
	ParticleRadius(0.4, 1.4)
	ParticleAlpha(0.5, 0.0)
	ParticleGravity(0.5)
	ParticleDrag(0.6)
	ParticleCollide(1)
	for i = 1, 20 do
		SpawnParticle(c, GetRandomDirection(rnd(3, 7)), rnd(1.5, 3))
	end
end

-- hide the hand model when out of grenades or right after a throw
function client.render(dt)
	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local b = GetToolBody(p)
			if b ~= 0 then
				local hide = GetToolAmmo(TOOL, p) <= 0
				if IsPlayerLocal(p) and client.thrownT < 0.25 then hide = true end
				local shapes = GetBodyShapes(b)
				for i = 1, #shapes do
					if hide then SetTag(shapes[i], "invisible") else RemoveTag(shapes[i], "invisible") end
				end
			end
		end
	end
end

function client.draw(dt)
	-- full-screen effects first (shown even when mod UI is hidden)
	if client.vignette > 0.01 then
		UiPush()
			local w, h = UiGetImageSize("MOD/ui/vignette.png")
			UiScale(UiWidth() / w, UiHeight() / h)
			UiColor(0.55, 0.2, 1.0, math.min(0.75, client.vignette * 0.8))
			UiImage("MOD/ui/vignette.png")
		UiPop()
	end
	if client.flash > 0.01 then
		UiPush()
			UiColor(1.0, 0.92, 1.0, client.flash)
			UiRect(UiWidth(), UiHeight())
		UiPop()
	end

	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or GetBool("game.player.usescreen") or not GetPlayerCanUseTool() then return end

	local ammo = GetToolAmmo(TOOL)
	local alive = 0
	for _, sg in pairs(shared.g) do if sg.phase ~= "done" then alive = alive + 1 end end
	local impact = getB("impact", false)

	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 170)
		UiAlign("center middle")
		UiFont("regular.ttf", 22)
		UiTextShadow(0, 0, 0, 0.6, 1.5)

		if client.charging then
			UiPush()
				UiTranslate(0, -60)
				UiColor(0, 0, 0, 0.5)
				UiRect(260, 14)
				UiAlign("left middle")
				UiTranslate(-128, 0)
				UiColor(0.75, 0.45, 1.0, 0.95)
				UiRect(256 * client.charge, 10)
			UiPop()
		end

		UiColor(1, 1, 1, 0.9)
		UiText(tr("Hold LMB: throw (longer = farther)    RMB: drop at your feet",
			"Удерживайте ЛКМ: бросок (дольше = дальше)    ПКМ: под ноги"))
		UiTranslate(0, 26)
		UiFont("regular.ttf", 18)
		UiColor(0.8, 0.7, 1.0, 0.85)
		if impact then
			UiText(tr("Opens on impact", "Раскрывается от удара"))
		else
			UiText(tr("Opens 1.5 s after it stops", "Раскрывается через 1,5 с после остановки"))
		end
		if ammo <= 0 then
			UiTranslate(0, 30)
			UiFont("bold.ttf", 24)
			UiColor(1, 0.35, 0.3, 1)
			UiText(tr("Out of grenades", "Гранаты закончились"))
		elseif alive >= MAX_ALIVE then
			UiTranslate(0, 30)
			UiFont("bold.ttf", 22)
			UiColor(1, 0.8, 0.3, 1)
			UiText(tr("Too many singularities, wait a moment", "Слишком много сингулярностей, подождите"))
		end
	UiPop()
end
