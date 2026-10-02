#version 2
-- Telekinesis / Телекинез
-- Gauntlet tool. LMB lifts the loose objects around the aim point; they hover
-- in a swirling ring in front of you. Hold LMB to charge and release to throw
-- them as a volley along your view. RMB puts them down gently. Holding costs
-- energy (more for heavier loads), throwing costs a chunk; energy refills when
-- your hands are empty. Held objects glow.
--
-- Server: picking, hovering (ConstrainPosition in update), throwing, energy.
-- Client: outlines, wisps and sparkles, hum loop, HUD. Bodies are server-authored,
-- so the client only reads them.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "telekinesis"
local CHARGE_TIME = 1.2
local VOLLEY_GAP = 0.04
local RING_DIST = 3.2

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		radius = clamp(getF("radius", 3), 1, 8),
		maxBodies = math.floor(clamp(getF("maxbodies", 8), 1, 20)),
		massLimit = clamp(getF("masslimit", 200), 10, 1000),
		power = clamp(getF("power", 1), 0.3, 3),
		reach = clamp(getF("reach", 40), 5, 100),
		energy = getB("energy", true),
		capacity = clamp(getF("capacity", 15), 5, 60),
	}
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Telekinesis", "Телекинез"), "MOD/prefab/tool.xml", 6)
	server.p = {}
	shared.tk = {}
end

local function state(p)
	local s = server.p[p]
	if not s then
		s = { held = {}, charge = 0, charging = false, needRelease = false, energy = 1, idleT = 0, volley = nil, spin = 0 }
		server.p[p] = s
	end
	return s
end

local function sync(p, s)
	local sh = shared.tk[p]
	if not sh then
		sh = { held = {}, charge = 0, energy = 1, n = 0, ev = "", ex = 0, ey = 0, ez = 0, mass = 0 }
		shared.tk[p] = sh
	end
	local list, mass = {}, 0
	for i = 1, #s.held do
		list[i] = s.held[i].body
		mass = mass + s.held[i].mass
	end
	sh.held = list
	sh.mass = mass
	sh.charge = s.charge
	sh.energy = s.energy
	return sh
end

local function event(p, kind, pos)
	local sh = shared.tk[p]
	if not sh then return end
	sh.n = sh.n + 1
	sh.ev = kind
	if pos then sh.ex, sh.ey, sh.ez = pos[1], pos[2], pos[3] end
end

function server.tick(dt)
	for p in PlayersAdded() do
		SetToolEnabled(TOOL, true, p)
		sync(p, state(p))
	end
	for p in PlayersRemoved() do
		server.p[p] = nil
		shared.tk[p] = nil
	end
	for p in Players() do
		local s = state(p)
		local cfg = readSettings()
		local active = GetPlayerTool(p) == TOOL and GetPlayerCanUseTool(p) and GetPlayerVehicle(p) == 0
		if not active and #s.held > 0 then server.drop(p, s) end
		if active then
			if #s.held == 0 and not s.volley then
				if InputPressed("usetool", p) then server.pick(p, s, cfg) end
			else
				if not InputDown("usetool", p) then s.needRelease = false end
				if InputPressed("usetool", p) and not s.needRelease then s.charging = true end
				if s.charging then
					s.charge = math.min(1, s.charge + dt / CHARGE_TIME)
					if InputReleased("usetool", p) or not InputDown("usetool", p) then
						server.throw(p, s, cfg)
					end
				end
				if InputPressed("grab", p) and #s.held > 0 then server.drop(p, s) end
			end
		end
		-- energy
		if cfg.energy then
			if #s.held > 0 then
				local mass = 0
				for i = 1, #s.held do mass = mass + s.held[i].mass end
				s.energy = s.energy - dt / cfg.capacity * (0.5 + mass / 400)
				s.idleT = 0
				if s.energy <= 0 then
					s.energy = 0
					server.drop(p, s)
					event(p, "empty")
				end
			else
				s.idleT = s.idleT + dt
				if s.idleT > 0.8 then s.energy = math.min(1, s.energy + dt / (cfg.capacity * 0.6)) end
			end
		else
			s.energy = 1
		end
		server.tickVolley(p, s, dt)
		sync(p, s)
	end
end

function server.pick(p, s, cfg)
	if cfg.energy and s.energy < 0.1 then
		event(p, "empty")
		return
	end
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	QueryRejectPlayer(p)
	QueryRequire("physical")
	local hit, dist = QueryRaycast(eye.pos, fwd, cfg.reach)
	local c = VecAdd(eye.pos, VecScale(fwd, hit and dist or cfg.reach * 0.5))
	local R = cfg.radius
	QueryRequire("physical dynamic")
	local list = QueryAabbBodies(VecSub(c, Vec(R, R, R)), VecAdd(c, Vec(R, R, R)))
	local cand = {}
	for i = 1, #list do
		local b = list[i]
		if GetBodyPlayer(b) == 0 and GetBodyVehicle(b) == 0 then
			local mass = GetBodyMass(b)
			local pos = TransformToParentPoint(GetBodyTransform(b), GetBodyCenterOfMass(b))
			local d = VecLength(VecSub(pos, c))
			if mass > 0 and mass <= cfg.massLimit and d <= R then
				cand[#cand + 1] = { body = b, mass = mass, d = d }
			end
		end
	end
	table.sort(cand, function(a, b) return a.d < b.d end)
	for i = 1, math.min(#cand, cfg.maxBodies) do
		s.held[#s.held + 1] = { body = cand[i].body, mass = cand[i].mass, slot = i }
	end
	if #s.held > 0 then
		s.needRelease = true
		s.charge = 0
		s.charging = false
		event(p, "grab", c)
	else
		event(p, "miss", c)
	end
end

function server.drop(p, s)
	for i = 1, #s.held do
		local b = s.held[i].body
		if IsHandleValid(b) then
			local v = GetBodyVelocity(b)
			if VecLength(v) > 3 then SetBodyVelocity(b, VecScale(VecNormalize(v), 3)) end
		end
	end
	if #s.held > 0 then event(p, "drop", GetPlayerEyeTransform(p).pos) end
	s.held = {}
	s.charge = 0
	s.charging = false
end

function server.throw(p, s, cfg)
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	local speed = (14 + 40 * s.charge) * cfg.power
	-- release them one after another for a volley
	s.volley = { list = s.held, i = 1, t = 0, speed = speed }
	s.held = {}
	if cfg.energy then s.energy = math.max(0, s.energy - 0.1 * (0.5 + s.charge)) end
	event(p, "throw", eye.pos)
	s.charge = 0
	s.charging = false
end

function server.tickVolley(p, s, dt)
	local v = s.volley
	if not v then return end
	v.t = v.t - dt
	while v.t <= 0 and v.i <= #v.list do
		local e = v.list[v.i]
		if IsHandleValid(e.body) then
			local eye = GetPlayerEyeTransform(p)
			local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
			local spread = VecScale(GetRandomDirection(1), 0.04)
			local massK = clamp(60 / math.max(e.mass, 1), 0.35, 1)
			SetBodyVelocity(e.body, VecScale(VecNormalize(VecAdd(fwd, spread)), v.speed * (0.6 + 0.4 * massK)))
			SetBodyAngularVelocity(e.body, GetRandomDirection(6))
		end
		v.i = v.i + 1
		v.t = v.t + VOLLEY_GAP
	end
	if v.i > #v.list then s.volley = nil end
end

-- hover: every held body is pulled to its slot on a slowly spinning ring
function server.update(dt)
	for p, s in pairs(server.p) do
		if #s.held > 0 and IsPlayerValid(p) then
			s.spin = s.spin + dt * (1.2 + 3 * s.charge)
			local eye = GetPlayerEyeTransform(p)
			local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
			local right = TransformToParentVec(eye, Vec(1, 0, 0))
			local up = TransformToParentVec(eye, Vec(0, 1, 0))
			local center = VecAdd(eye.pos, VecScale(fwd, RING_DIST - 0.8 * s.charge))
			local n = #s.held
			local radius = 0.6 + 0.25 * n * (1 - 0.6 * s.charge)
			local keep = {}
			for i = 1, n do
				local e = s.held[i]
				if IsHandleValid(e.body) and IsBodyDynamic(e.body) then
					local a = s.spin + (i - 1) / n * 6.2832
					local target = VecAdd(center, VecAdd(VecScale(right, math.cos(a) * radius), VecScale(up, math.sin(a) * radius * 0.6)))
					local bt = GetBodyTransform(e.body)
					local com = TransformToParentPoint(bt, GetBodyCenterOfMass(e.body))
					ConstrainPosition(e.body, 0, com, target, 14, e.mass * 60)
					keep[#keep + 1] = e
				end
			end
			s.held = keep
		end
	end
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.snd = {}
	for _, n in ipairs({ "grab", "throw", "drop", "empty" }) do client.snd[n] = LoadSound("MOD/snd/" .. n .. ".ogg") end
	client.hold = LoadLoop("MOD/snd/hold.ogg")
	client.anim = {}
	client.seen = {}
	client.t = 0
end

function client.tick(dt)
	client.t = client.t + dt
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	for p, sh in pairs(shared.tk) do
		if client.seen[p] ~= nil and client.seen[p] ~= sh.n and client.snd[sh.ev] then
			PlaySound(client.snd[sh.ev], Vec(sh.ex, sh.ey, sh.ez), 0.9)
		end
		client.seen[p] = sh.n
		if #sh.held > 0 then
			PlayLoop(client.hold, GetPlayerEyeTransform(p).pos, 0.4 + 0.4 * sh.charge, true, 0.9 + 0.6 * sh.charge)
		end
	end
	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local a = client.anim[p]
			if not a then a = ToolAnimator() client.anim[p] = a end
			local sh = shared.tk[p]
			local holding = sh and #sh.held > 0
			a.forceActionPose = holding
			local c = sh and sh.charge or 0
			a.offsetTransform = Transform(Vec(0, 0.03 * c, 0.12 * c))
			tickToolAnimator(a, dt, nil, p)
			local tb = GetToolBody(p)
			if tb ~= 0 then
				local shapes = GetBodyShapes(tb)
				local glow = (holding and 1.3 or 0.6) + 0.3 * math.sin(client.t * 6) + 1.5 * c
				for i = 1, #shapes do SetShapeEmissiveScale(shapes[i], glow) end
			end
		end
	end
end

function client.render(dt)
	for p, sh in pairs(shared.tk) do
		for i = 1, #sh.held do
			local b = sh.held[i]
			if IsHandleValid(b) then
				DrawBodyOutline(b, 0.7, 0.4, 1.0, 0.9)
				DrawBodyHighlight(b, 0.25 + 0.25 * sh.charge)
			end
		end
	end
end

-- wisps from the hand to the held objects and sparkles around them
function client.update(dt)
	for p, sh in pairs(shared.tk) do
		local n = #sh.held
		if n > 0 then
			local from = VecAdd(GetPlayerEyeTransform(p).pos, Vec(0, -0.3, 0))
			ParticleReset()
			ParticleType("plain")
			ParticleColor(0.75, 0.45, 1.0, 0.4, 0.15, 0.9)
			ParticleRadius(0.04, 0.0)
			ParticleAlpha(0.9, 0)
			ParticleGravity(0)
			ParticleDrag(0.3)
			ParticleEmissive(6, 0)
			ParticleCollide(0)
			for k = 1, math.min(n, 6) do
				local b = sh.held[math.random(1, n)]
				if IsHandleValid(b) then
					local pos = GetBodyTransform(b).pos
					SpawnParticle(VecAdd(pos, GetRandomDirection(0.4)), GetRandomDirection(0.5), 0.5)
					local t = math.random()
					SpawnParticle(VecLerp(from, pos, t), VecScale(VecSub(pos, from), 0.6), 0.25)
				end
			end
		end
	end
end

function client.draw(dt)
	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or not GetPlayerCanUseTool() then return end
	local sh = shared.tk[GetLocalPlayer()]
	if not sh then return end
	local energyOn = getB("energy", true)
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 170)
		UiAlign("center middle")
		UiTextShadow(0, 0, 0, 0.6, 1.5)
		if energyOn then
			UiPush()
				UiTranslate(0, -40)
				UiColor(0, 0, 0, 0.5)
				UiRect(260, 12)
				UiAlign("left middle")
				UiTranslate(-128, 0)
				UiColor(0.7, 0.4, 1.0, 1)
				UiRect(256 * sh.energy, 8)
			UiPop()
		end
		if sh.charge > 0 then
			UiPush()
				UiTranslate(0, -60)
				UiColor(0, 0, 0, 0.5)
				UiRect(200, 8)
				UiAlign("left middle")
				UiTranslate(-98, 0)
				UiColor(1, 0.85, 0.4, 1)
				UiRect(196 * sh.charge, 4)
			UiPop()
		end
		UiFont("regular.ttf", 22)
		UiColor(1, 1, 1, 0.9)
		if #sh.held > 0 then
			UiText(string.format(tr("Holding %d (%.0f kg)   Hold LMB: charge, release: throw   RMB: put down",
				"Держу %d (%.0f кг)   Держите ЛКМ: заряд, отпустите: бросок   ПКМ: опустить"), #sh.held, sh.mass))
		else
			UiText(tr("LMB: lift the objects around the aim point", "ЛКМ: поднять предметы вокруг точки прицела"))
		end
	UiPop()
end
