#version 2
-- Tornado / Торнадо
-- Storm caller tool: LMB on the ground spawns a tornado there, RMB dismisses
-- the nearest one. The tornado wanders on a smooth random path (or follows
-- your aim point, option), pulls loose bodies and debris in and up, spins them
-- and throws them out at the top, tears weak parts (wood, glass, plaster,
-- plastic, foliage; concrete only when very strong) and loosens joints within a
-- per-step budget, and can lift vehicles and the player (options).
--
-- Server: tornado state, motion, forces, damage, player push.
-- Client: funnel particles (layers, darker base, dust ring, debris specks),
--         roar loop, camera shake, HUD.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "tornado"
local MAX_TORNADOES = 2
local SCAN_INTERVAL = 0.25
local MAX_TRACKED = 150
local BODIES_PER_UPDATE = 50
local PROBES_PER_UPDATE = 2
local JOINT_INTERVAL = 0.3
local MAX_HOLES = 600
local FADE = 3.0
local WEAK = { glass = true, wood = true, plaster = true, plastic = true, foliage = true }

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function rnd(a, b) return a + (b - a) * math.random() end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		strength = clamp(getF("strength", 1), 0.3, 3),
		size = clamp(getF("size", 8), 4, 20),
		duration = clamp(getF("duration", 40), 10, 180),
		speed = clamp(getF("speed", 4), 1, 12),
		follow = getB("follow", false),
		vehicles = getB("vehicles", true),
		player = getB("player", true),
		damage = getB("damage", true),
	}
end

-- smooth noise for the wandering path and the funnel bend
local function hash(n) local x = math.sin(n * 127.1 + 311.7) * 43758.5453 return (x - math.floor(x)) * 2 - 1 end
local function vnoise(t, seed)
	local i = math.floor(t)
	local f = t - i
	local u = f * f * (3 - 2 * f)
	return hash(i + seed * 13.0) * (1 - u) + hash(i + 1 + seed * 13.0) * u
end

-- funnel geometry shared by server and client
function funnelHeight(size) return size * 3.6 end
function funnelRadius(size, rel) return 0.6 + (size - 0.6) * rel ^ 1.6 end
function funnelOffset(age, rel, size)
	local bend = math.sin(rel * math.pi) * size * 0.35
	local a = age * 0.8 + rel * 6
	return Vec(math.sin(a) * bend, 0, math.sin(a * 0.7) * bend)
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Storm Caller", "Вызов бури"), "MOD/prefab/tool.xml", 6)
	server.t = {}
	server.nextId = 1
	shared.t = {}
end

function server.count()
	local n = 0
	for _ in pairs(server.t) do n = n + 1 end
	return n
end

function server.tick(dt)
	for p in PlayersAdded() do SetToolEnabled(TOOL, true, p) end
	for p in Players() do
		if GetPlayerTool(p) == TOOL and GetPlayerCanUseTool(p) and GetPlayerVehicle(p) == 0 then
			local eye = GetPlayerEyeTransform(p)
			local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
			QueryRejectPlayer(p)
			QueryRequire("physical")
			local hit, dist = QueryRaycast(eye.pos, fwd, 250)
			local aim = hit and VecAdd(eye.pos, VecScale(fwd, dist)) or nil
			if aim then
				for id, tn in pairs(server.t) do
					if tn.owner == p then tn.aim = aim end
				end
			end
			if InputPressed("usetool", p) and aim and server.count() < MAX_TORNADOES then
				server.spawn(p, aim)
			end
			if InputPressed("grab", p) and GetPlayerGrabBody(p) == 0 and GetPlayerPickBody(p) == 0 then
				server.dismissNearest(p)
			end
		end
	end
end

function server.spawn(p, pos)
	local s = readSettings()
	local id = server.nextId
	server.nextId = id + 1
	server.t[id] = {
		id = id, owner = p, pos = VecCopy(pos), start = VecCopy(pos), age = 0, life = s.duration, s = s,
		amount = 0, seed = math.random(1, 999), heading = math.random() * 6.2832, groundT = 0,
		tracked = {}, cursor = 1, scanT = 0, jointT = 0, holes = 0, aim = VecCopy(pos), dying = false,
	}
	shared.t[id] = { x = pos[1], y = pos[2], z = pos[3], amount = 0, age = 0, life = s.duration, size = s.size, owner = p, n = 1 }
end

function server.dismissNearest(p)
	local pp = GetPlayerTransform(p).pos
	local best, bestD = nil, 1e9
	for id, tn in pairs(server.t) do
		local d = VecLength(VecSub(tn.pos, pp))
		if d < bestD and not tn.dying then best, bestD = tn, d end
	end
	if best then
		best.dying = true
		best.life = math.min(best.life, best.age + FADE)
	end
end

function server.update(dt)
	for id, tn in pairs(server.t) do
		server.updateTornado(tn, dt)
	end
end

function server.updateTornado(tn, dt)
	local s = tn.s
	tn.age = tn.age + dt
	if tn.age >= tn.life then
		server.t[tn.id] = nil
		shared.t[tn.id] = nil
		return
	end
	local fin = clamp(tn.age / FADE, 0, 1)
	local fout = clamp((tn.life - tn.age) / FADE, 0, 1)
	tn.amount = math.min(fin, fout) ^ 2

	-- motion
	local dir
	if s.follow then
		local d = VecSub(tn.aim, tn.pos)
		d[2] = 0
		local l = VecLength(d)
		if l > 1.5 then dir = VecScale(d, 1 / l) else dir = Vec(0, 0, 0) end
	else
		tn.heading = tn.heading + vnoise(tn.age * 0.15, tn.seed) * dt * 0.9
		dir = Vec(math.cos(tn.heading), 0, math.sin(tn.heading))
		if not IsPointInBoundaries(VecAdd(tn.pos, VecScale(dir, 10))) then
			-- turn back towards where it started
			local back = VecSub(tn.start, tn.pos)
			back[2] = 0
			if VecLength(back) > 0.1 then
				tn.heading = math.atan2(back[3], back[1])
				dir = VecNormalize(back)
			end
		end
	end
	-- it forms in place and only starts travelling once it has spun up
	tn.pos = VecAdd(tn.pos, VecScale(dir, s.speed * dt * tn.amount))
	-- stick to the ground
	tn.groundT = tn.groundT - dt
	if tn.groundT <= 0 then
		tn.groundT = 0.4
		QueryRequire("physical static")
		local hit, dist = QueryRaycast(VecAdd(tn.pos, Vec(0, 20, 0)), Vec(0, -1, 0), 60)
		if hit then tn.groundY = tn.pos[2] + 20 - dist end
	end
	if tn.groundY then tn.pos[2] = tn.pos[2] + (tn.groundY - tn.pos[2]) * math.min(1, dt * 3) end

	server.pull(tn, dt)
	server.pushPlayers(tn, dt)
	if s.damage then
		server.tear(tn, dt)
		server.joints(tn, dt)
	end

	local st = shared.t[tn.id]
	st.x, st.y, st.z = tn.pos[1], tn.pos[2], tn.pos[3]
	st.amount = tn.amount
	st.age = tn.age
	st.life = tn.life
end

function server.scan(tn)
	local s = tn.s
	local R = s.size * 1.6
	local H = funnelHeight(s.size)
	QueryRequire("physical dynamic")
	local list = QueryAabbBodies(Vec(tn.pos[1] - R, tn.pos[2] - 2, tn.pos[3] - R), Vec(tn.pos[1] + R, tn.pos[2] + H, tn.pos[3] + R))
	local out = {}
	for i = 1, #list do
		local b = list[i]
		if GetBodyPlayer(b) == 0 and (s.vehicles or GetBodyVehicle(b) == 0) then
			out[#out + 1] = b
			if #out >= MAX_TRACKED then break end
		end
	end
	return out
end

-- velocity change for a body at pos with given mass (game-style funnel model)
function server.velChange(tn, pos, mass, vel)
	local s = tn.s
	local H = funnelHeight(s.size)
	local rel = clamp((pos[2] - tn.pos[2]) / H, 0, 1)
	local axis = VecAdd(Vec(tn.pos[1], pos[2], tn.pos[3]), funnelOffset(tn.age, rel, s.size))
	local to = VecSub(axis, pos)
	to[2] = 0
	local dist = VecLength(to)
	local suck = s.size * 1.6
	if dist >= suck then return nil end
	local inward = dist > 0.01 and VecScale(to, 1 / dist) or Vec(1, 0, 0)
	-- dv is applied as 30 * dt per physics step (about 0.5 m/s per step at k = 1),
	-- in the range of the game's own tornado script
	local k = (1 - dist / suck) ^ 1.5 * tn.amount * s.strength * 1200 / (1200 + mass)
	local tang = Vec(inward[3], 0, -inward[1])
	local r = funnelRadius(s.size, rel)
	local dv
	if rel > 0.82 then
		-- top of the funnel: throw outwards
		dv = VecAdd(VecScale(inward, -k * 2.5), Vec(0, k * 0.5, 0))
	elseif dist < r then
		-- inside the wall: spin and lift
		dv = VecAdd(VecAdd(VecScale(tang, k * 2.2), VecScale(inward, k * 0.4)), Vec(0, k * 3.2, 0))
	else
		dv = VecAdd(VecAdd(VecScale(inward, k * 2.0), VecScale(tang, k * 0.8)), Vec(0, k * 1.6, 0))
	end
	-- limit the speed the tornado can add
	local maxV = 14 * math.sqrt(s.strength)
	for i = 1, 3 do
		if dv[i] > 0 and vel[i] > maxV then dv[i] = 0 end
		if dv[i] < 0 and vel[i] < -maxV then dv[i] = 0 end
	end
	return dv, k
end

function server.pull(tn, dt)
	tn.scanT = tn.scanT - dt
	if tn.scanT <= 0 then
		tn.scanT = SCAN_INTERVAL
		tn.tracked = server.scan(tn)
		tn.cursor = 1
	end
	local n = #tn.tracked
	if n == 0 then return end
	local per = math.min(n, BODIES_PER_UPDATE)
	local stride = n / per
	for i = 1, per do
		local idx = tn.cursor
		tn.cursor = (tn.cursor % n) + 1
		local b = tn.tracked[idx]
		if IsHandleValid(b) and IsBodyDynamic(b) then
			local mass = GetBodyMass(b)
			if mass > 0 then
				local bt = GetBodyTransform(b)
				local com = TransformToParentPoint(bt, GetBodyCenterOfMass(b))
				local dv, k = server.velChange(tn, com, mass, GetBodyVelocity(b))
				if dv then
					-- the per-body change is applied every `stride` steps, scale it so the average is right
					ApplyBodyImpulse(b, VecAdd(com, Vec(0, 0.15, 0)), VecScale(dv, mass * 30 * dt * stride))
				end
			end
		end
	end
end

function server.pushPlayers(tn, dt)
	local s = tn.s
	if not s.player then return end
	for p in Players() do
		if GetPlayerVehicle(p) == 0 then
			local pos = VecAdd(GetPlayerTransform(p).pos, Vec(0, 1, 0))
			local dv, k = server.velChange(tn, pos, 600, GetPlayerVelocity(p))
			if dv then
				local d = VecSub(Vec(tn.pos[1], pos[2], tn.pos[3]), pos)
				d[2] = 0
				-- walls shield the player
				QueryRequire("physical static")
				local blocked = QueryRaycast(pos, VecNormalize(d), VecLength(d))
				if not blocked then
					if VecLength(d) < 3 then ReleasePlayerGrab(p) end
					SetPlayerVelocity(VecAdd(GetPlayerVelocity(p), VecScale(dv, 30 * dt)), p)
				end
			end
		end
	end
end

function server.tear(tn, dt)
	if tn.holes >= MAX_HOLES or tn.amount < 0.3 then return end
	local s = tn.s
	for i = 1, PROBES_PER_UPDATE do
		local h = rnd(0.3, 10)
		local rel = h / funnelHeight(s.size)
		local a = math.random() * 6.2832
		local r = funnelRadius(s.size, rel) * rnd(0.5, 1.4)
		local p = VecAdd(VecAdd(tn.pos, funnelOffset(tn.age, rel, s.size)), Vec(math.cos(a) * r, h, math.sin(a) * r))
		QueryRequire("physical")
		local hit, point, normal, shape = QueryClosestPoint(p, 1.5)
		if hit and shape ~= 0 then
			local inside = VecSub(point, VecScale(normal, 0.05))
			local mat = GetShapeMaterialAtPosition(shape, inside)
			local strong = s.strength >= 2
			if WEAK[mat] or (strong and (mat == "masonry" or mat == "metal")) then
				local r0 = 0.35 + 0.25 * s.strength * tn.amount
				local r1 = strong and r0 * 0.5 or 0
				MakeHole(inside, r0, r1, 0, false)
				tn.holes = tn.holes + 1
			end
		end
	end
end

function server.joints(tn, dt)
	tn.jointT = tn.jointT - dt
	if tn.jointT > 0 then return end
	tn.jointT = JOINT_INTERVAL
	local n = #tn.tracked
	if n == 0 then return end
	local chance = 0.25 * tn.amount * tn.s.strength
	local done = 0
	for k = 1, math.min(n, 6) do
		local b = tn.tracked[math.random(1, n)]
		if IsHandleValid(b) then
			local shapes = GetBodyShapes(b)
			for i = 1, #shapes do
				local js = GetShapeJoints(shapes[i])
				for j = 1, #js do
					if done < 2 and not IsJointBroken(js[j]) and math.random() < chance then
						DetachJointFromShape(js[j], shapes[i])
						done = done + 1
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

local PARTICLES_PER_UPDATE = 32

function client.init()
	client.roar = LoadLoop("MOD/snd/roar.ogg", 60)
	client.snd = { spawn = LoadSound("MOD/snd/spawn.ogg", 80), dissipate = LoadSound("MOD/snd/dissipate.ogg", 60), click = LoadSound("MOD/snd/click.ogg") }
	client.anim = {}
	client.seen = {}
	client.angle = 0
	client.dish = {}
end

function client.tick(dt)
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local eye = GetPlayerCameraTransform()
	local shake = 0
	for id, st in pairs(shared.t) do
		local pos = Vec(st.x, st.y, st.z)
		if not client.seen[id] then
			client.seen[id] = { dying = false, pos = pos }
			PlaySound(client.snd.spawn, pos, 1.0)
		end
		client.seen[id].pos = pos
		if st.life - st.age < 3 and not client.seen[id].dying then
			client.seen[id].dying = true
			PlaySound(client.snd.dissipate, pos, 1.0)
		end
		PlayLoop(client.roar, VecAdd(pos, Vec(0, 3, 0)), clamp(st.amount * 1.5, 0, 1), true, 0.9 + 0.2 * st.amount)
		local d = VecLength(VecSub(eye.pos, pos))
		shake = math.max(shake, clamp(1 - d / (st.size * 5), 0, 1) * st.amount)
		PointLight(VecAdd(pos, Vec(0, funnelHeight(st.size) * 0.9, 0)), 0.5, 0.55, 0.6, 2 * st.amount)
	end
	for id in pairs(client.seen) do if not shared.t[id] then client.seen[id] = nil end end
	if shake > 0.02 then ShakeCamera(shake * 0.8) end

	client.angle = client.angle + dt * 180
	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local a = client.anim[p]
			if not a then a = ToolAnimator() client.anim[p] = a end
			tickToolAnimator(a, dt, nil, p)
			local b = GetToolBody(p)
			if b ~= 0 then
				local dsh = client.dish[p]
				if not dsh or dsh.body ~= b then
					dsh = { body = b }
					local shapes = GetBodyShapes(b)
					for i = 1, #shapes do
						local sx, sy, sz, vs = GetShapeSize(shapes[i])
						if sx == 7 and sy == 7 and sz == 1 then
							dsh.shape = shapes[i]
							dsh.t0 = GetShapeLocalTransform(shapes[i])
							dsh.center = Vec(sx * vs * 0.5, sy * vs * 0.5, 0)
						end
					end
					client.dish[p] = dsh
				end
				if dsh.shape then
					local pivot = Transform(dsh.center, QuatAxisAngle(Vec(0, 1, 0), client.angle))
					SetShapeLocalTransform(dsh.shape, TransformToParentTransform(dsh.t0, TransformToParentTransform(pivot, Transform(VecScale(dsh.center, -1)))))
				end
			end
		end
	end
end

-- funnel particles at a fixed rate, budget shared by all tornadoes
function client.update(dt)
	local n = 0
	for _ in pairs(shared.t) do n = n + 1 end
	if n == 0 then return end
	local per = math.floor(PARTICLES_PER_UPDATE / n)
	for id, st in pairs(shared.t) do client.emit(st, per) end
end

function client.emit(st, budget)
	local pos = Vec(st.x, st.y, st.z)
	local size = st.size
	local H = funnelHeight(size)
	local amt = st.amount
	local nWall = math.floor(budget * 0.55 * amt + 0.5)
	local nDust = math.floor(budget * 0.25 * amt + 0.5)
	local nBits = math.floor(budget * 0.2 * amt + 0.5)

	-- funnel wall: spiralling smoke, dark at the base, lighter at the top
	ParticleReset()
	ParticleType("smoke")
	ParticleDrag(0.15)
	ParticleGravity(0)
	ParticleCollide(0)
	for i = 1, nWall do
		local rel = math.random() ^ 1.5
		local h = rel * H
		local r = funnelRadius(size, rel) * (0.85 + 0.3 * math.random())
		local a = math.random() * 6.2832
		local off = funnelOffset(st.age, rel, size)
		local p = VecAdd(VecAdd(pos, off), Vec(math.cos(a) * r, h, math.sin(a) * r))
		local tang = Vec(-math.sin(a), 0, math.cos(a))
		local v = VecAdd(VecScale(tang, 6 + r * 1.2), Vec(0, 4 + 4 * rel, 0))
		local c = 0.22 + 0.4 * rel
		ParticleColor(c, c, c * 1.05, c + 0.1, c + 0.1, c + 0.12)
		ParticleRadius(0.8 + 2.5 * rel, 1.5 + 3 * rel)
		ParticleAlpha(0.55 * amt, 0, "linear", 0.1, 0.6)
		SpawnParticle(p, v, rnd(1.2, 2.4))
	end

	-- dust ring at the base
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.45, 0.38, 0.3, 0.55, 0.5, 0.45)
	ParticleDrag(0.3)
	ParticleGravity(0.5)
	ParticleCollide(0)
	for i = 1, nDust do
		local a = math.random() * 6.2832
		local r = size * rnd(0.6, 1.8)
		local p = VecAdd(pos, Vec(math.cos(a) * r, 0.3, math.sin(a) * r))
		local tang = Vec(-math.sin(a), 0, math.cos(a))
		local v = VecAdd(VecScale(tang, 8), VecAdd(Vec(math.cos(a), 0, math.sin(a)), Vec(0, 1.5, 0)))
		ParticleRadius(1.2, 2.8)
		ParticleAlpha(0.45 * amt, 0)
		SpawnParticle(p, v, rnd(1.5, 3))
	end

	-- debris specks orbiting and being flung
	ParticleReset()
	ParticleType("plain")
	ParticleColor(0.18, 0.15, 0.12)
	ParticleRadius(0.06, 0.04)
	ParticleAlpha(1, 1)
	ParticleGravity(-4)
	ParticleDrag(0.1)
	ParticleCollide(1)
	for i = 1, nBits do
		local rel = math.random() * 0.7
		local r = funnelRadius(size, rel) * rnd(0.9, 1.3)
		local a = math.random() * 6.2832
		local p = VecAdd(pos, Vec(math.cos(a) * r, rel * H, math.sin(a) * r))
		local tang = Vec(-math.sin(a), 0, math.cos(a))
		SpawnParticle(p, VecAdd(VecScale(tang, 10), Vec(math.cos(a) * 3, rnd(2, 8), math.sin(a) * 3)), rnd(1, 2.5))
	end
end

function client.draw(dt)
	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or not GetPlayerCanUseTool() then return end
	local n = 0
	local left = 0
	for _, st in pairs(shared.t) do n = n + 1 left = math.max(left, st.life - st.age) end
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 160)
		UiAlign("center middle")
		UiTextShadow(0, 0, 0, 0.6, 1.5)
		UiFont("regular.ttf", 22)
		UiColor(1, 1, 1, 0.9)
		UiText(tr("LMB: tornado at the aim point    RMB: dismiss the nearest", "ЛКМ: торнадо в точке прицела    ПКМ: развеять ближайший"))
		UiTranslate(0, 28)
		UiFont("regular.ttf", 18)
		UiColor(0.8, 0.85, 0.9, 0.85)
		local mode = getB("follow", false) and tr("follows your aim", "идёт за прицелом") or tr("wanders", "бродит сам")
		if n > 0 then
			UiText(string.format(tr("Active: %d (max %d), %.0f s left, %s", "Активно: %d (макс %d), осталось %.0f с, %s"), n, MAX_TORNADOES, left, mode))
		else
			UiText(string.format(tr("Movement: %s", "Движение: %s"), mode))
		end
	UiPop()
end
