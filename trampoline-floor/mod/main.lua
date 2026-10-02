#version 2
-- Trampoline Floor / Пол-батут
-- Pad placer tool. LMB places a 3 x 3 m trampoline pad on the ground, RMB
-- removes the nearest one, R toggles "global mode" in which the whole ground
-- bounces. Players, dynamic bodies and vehicles that land fast on a pad (or on
-- any static ground in global mode) are thrown back up with the restitution
-- from the options. Boing sound, squash dust, the pad membrane dips.
--
-- Teardown has no per-surface restitution, so the bounce is a velocity change:
-- the server watches the vertical speed; when something that was falling
-- fast suddenly stops near a pad / the ground, its downward speed is given
-- back upwards (players: SetPlayerVelocity, bodies: SetBodyVelocity).

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "trampoline"
local PAD_XML = "<body dynamic='false'><vox file='MOD/vox/pad.vox'/></body>"
local PAD_HALF = 1.45          -- half side of the bouncy area (m)
local PAD_TOP = 0.2            -- membrane height above the pad origin
local MAX_PADS = 8
local SCAN_INTERVAL = 0.25
local BODIES_PER_UPDATE = 40
local LAND_SPEED = 3.0         -- falling faster than this counts as a landing

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		restitution = clamp(getF("restitution", 0.85), 0.3, 1.3),
		maxSpeed = clamp(getF("maxspeed", 25), 5, 50),
		players = getB("players", true),
		bodies = getB("bodies", true),
		vehicles = getB("vehicles", true),
		radius = clamp(getF("radius", 30), 10, 80),
		globalStart = getB("global", false),
	}
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Bounce Pads", "Батуты"), "MOD/prefab/tool.xml", 6)
	server.pads = {}
	server.prevPlayer = {}
	server.prevBody = {}
	server.tracked = {}
	server.cursor = 1
	server.scanT = 0
	shared.tp = { global = readSettings().globalStart, pads = {}, n = 0, bx = 0, by = 0, bz = 0, power = 0, ev = "", en = 0 }
end

local function syncPads()
	local list = {}
	for i = 1, #server.pads do
		local p = server.pads[i]
		list[i] = { x = p.pos[1], y = p.pos[2], z = p.pos[3], body = p.body }
	end
	shared.tp.pads = list
end

local function bounceEvent(pos, power)
	local t = shared.tp
	t.n = t.n + 1
	t.bx, t.by, t.bz = pos[1], pos[2], pos[3]
	t.power = power
end

local function toolEvent(kind)
	local t = shared.tp
	t.en = t.en + 1
	t.ev = kind
end

function server.tick(dt)
	for p in PlayersAdded() do SetToolEnabled(TOOL, true, p) end
	for p in Players() do
		if GetPlayerTool(p) == TOOL and GetPlayerCanUseTool(p) and GetPlayerVehicle(p) == 0 then
			if InputPressed("usetool", p) then server.place(p) end
			if InputPressed("grab", p) and GetPlayerGrabBody(p) == 0 and GetPlayerPickBody(p) == 0 then server.remove(p) end
		end
	end
end

function server.toggleGlobal(p)
	shared.tp.global = not shared.tp.global
	toolEvent("toggle")
end

function server.place(p)
	if #server.pads >= MAX_PADS then
		toolEvent("full")
		return
	end
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	QueryRejectPlayer(p)
	QueryRequire("physical static")
	local hit, dist, n = QueryRaycast(eye.pos, fwd, 40)
	if not hit or n[2] < 0.7 then
		toolEvent("fail")
		return
	end
	local pos = VecAdd(eye.pos, VecScale(fwd, dist))
	local flat = VecNormalize(Vec(fwd[1], 0, fwd[3]))
	local yaw = math.deg(math.atan2(-flat[1], -flat[3]))
	local origin = VecAdd(pos, Vec(0, 0.15, 0))
	local ents = Spawn(PAD_XML, Transform(origin, QuatEuler(0, yaw, 0)), true)
	local body, membrane = 0, 0
	for i = 1, #ents do
		local ty = GetEntityType(ents[i])
		if ty == "body" and body == 0 then body = ents[i] end
		if ty == "shape" then
			local sx, sy, sz = GetShapeSize(ents[i])
			if sy == 1 then membrane = ents[i] end
		end
	end
	if body == 0 then return end
	SetTag(body, "trampoline")
	server.pads[#server.pads + 1] = {
		body = body, pos = origin, rot = QuatEuler(0, yaw, 0), membrane = membrane,
		m0 = membrane ~= 0 and GetShapeLocalTransform(membrane) or nil, dip = 0,
	}
	syncPads()
	toolEvent("place")
end

function server.remove(p)
	local pp = GetPlayerTransform(p).pos
	local best, bi = 1e9, nil
	for i = 1, #server.pads do
		local d = VecLength(VecSub(server.pads[i].pos, pp))
		if d < best then best, bi = d, i end
	end
	if not bi or best > 30 then return end
	local pad = table.remove(server.pads, bi)
	if IsHandleValid(pad.body) then Delete(pad.body) end
	syncPads()
	toolEvent("remove")
end

-- is a world point above a pad's membrane? returns the pad
local function padUnder(pos, slack)
	for i = 1, #server.pads do
		local pad = server.pads[i]
		if IsHandleValid(pad.body) then
			local l = TransformToLocalPoint(Transform(pad.pos, pad.rot), pos)
			if math.abs(l[1]) < PAD_HALF and math.abs(l[3]) < PAD_HALF and l[2] > PAD_TOP - 0.45 and l[2] < PAD_TOP + slack then
				return pad
			end
		end
	end
	return nil
end

-- in global mode: static ground just under the point?
local function groundUnder(pos, slack, rejectBody)
	if rejectBody then QueryRejectBody(rejectBody) end
	QueryRequire("physical static")
	local hit = QueryRaycast(pos, Vec(0, -1, 0), slack)
	return hit
end

local function bounceSpeed(prevVy, s)
	return clamp(-prevVy * s.restitution, LAND_SPEED * 0.8, s.maxSpeed)
end

function server.update(dt)
	local s = readSettings()
	local global = shared.tp.global
	-- membrane spring-back animation (pads are server-authored, animated here)
	for i = 1, #server.pads do
		local pad = server.pads[i]
		if pad.dip > 0.001 and pad.membrane ~= 0 and pad.m0 and IsHandleValid(pad.membrane) then
			pad.dip = pad.dip * 0.85
			local t = TransformCopy(pad.m0)
			t.pos = VecAdd(t.pos, Vec(0, -pad.dip, 0))
			SetShapeLocalTransform(pad.membrane, t)
		end
	end
	if #server.pads == 0 and not global then return end

	if s.players then
		for p in Players() do
			local v = GetPlayerVelocity(p)
			local prev = server.prevPlayer[p] or 0
			local pos = GetPlayerTransform(p).pos
			if prev < -LAND_SPEED and v[2] > prev * 0.35 and GetPlayerVehicle(p) == 0 then
				local pad = padUnder(pos, 0.6)
				if pad or (global and groundUnder(VecAdd(pos, Vec(0, 0.3, 0)), 0.6)) then
					local up = bounceSpeed(prev, s)
					SetPlayerVelocity(Vec(v[1], up, v[3]), p)
					v = Vec(v[1], up, v[3])
					if pad then pad.dip = math.min(0.12, -prev * 0.01) end
					bounceEvent(pos, clamp(-prev / 15, 0.2, 1))
				end
			end
			server.prevPlayer[p] = v[2]
		end
	end

	if s.bodies or s.vehicles then
		server.scanT = server.scanT - dt
		if server.scanT <= 0 then
			server.scanT = SCAN_INTERVAL
			server.tracked = server.scan(s, global)
			server.cursor = 1
		end
		local n = #server.tracked
		for k = 1, math.min(n, BODIES_PER_UPDATE) do
			local b = server.tracked[server.cursor]
			server.cursor = (server.cursor % n) + 1
			if IsHandleValid(b) and IsBodyDynamic(b) then server.checkBody(b, s, global) end
		end
	end
end

function server.scan(s, global)
	local seen, out = {}, {}
	local function add(list)
		for i = 1, #list do
			local b = list[i]
			if not seen[b] and GetBodyPlayer(b) == 0 and not HasTag(b, "trampoline") then
				local isVehicle = GetBodyVehicle(b) ~= 0
				if (isVehicle and s.vehicles) or (not isVehicle and s.bodies) then
					seen[b] = true
					out[#out + 1] = b
				end
			end
		end
	end
	for i = 1, #server.pads do
		local c = server.pads[i].pos
		QueryRequire("physical dynamic")
		add(QueryAabbBodies(VecSub(c, Vec(2, 0.5, 2)), VecAdd(c, Vec(2, 8, 2))))
	end
	if global then
		for p in Players() do
			local c = GetPlayerTransform(p).pos
			local R = s.radius
			QueryRequire("physical dynamic")
			add(QueryAabbBodies(VecSub(c, Vec(R, 5, R)), VecAdd(c, Vec(R, R, R))))
		end
	end
	-- forget bodies that are no longer tracked
	local keep = {}
	for i = 1, #out do keep[out[i]] = server.prevBody[out[i]] end
	server.prevBody = keep
	return out
end

-- each body is checked every few physics steps (round robin), so the landing test
-- compares with the vertical speed seen at its previous check
function server.checkBody(b, s, global)
	local v = GetBodyVelocity(b)
	local prev = server.prevBody[b] or 0
	server.prevBody[b] = v[2]
	if prev < -LAND_SPEED and v[2] > prev * 0.35 then
		local bmin, bmax = GetBodyBounds(b)
		local bottom = Vec((bmin[1] + bmax[1]) * 0.5, bmin[2], (bmin[3] + bmax[3]) * 0.5)
		local pad = padUnder(bottom, 0.5)
		if pad or (global and groundUnder(VecAdd(bottom, Vec(0, 0.2, 0)), 0.5, b)) then
			local up = bounceSpeed(prev, s)
			SetBodyVelocity(b, Vec(v[1], up, v[3]))
			server.prevBody[b] = up
			if pad then pad.dip = math.min(0.12, -prev * 0.01) end
			bounceEvent(bottom, clamp(-prev / 15, 0.2, 1))
		end
	end
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.snd = {}
	for _, n in ipairs({ "boing", "boing_small", "place", "remove", "toggle" }) do client.snd[n] = LoadSound("MOD/snd/" .. n .. ".ogg") end
	client.anim = {}
	client.lastN = 0
	client.lastE = 0
	client.burst = nil
	client.msgT = 0
	client.msg = ""
end

function client.tick(dt)
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local t = shared.tp
	if t.n ~= client.lastN then
		client.lastN = t.n
		local pos = Vec(t.bx, t.by, t.bz)
		PlaySound(t.power > 0.5 and client.snd.boing or client.snd.boing_small, pos, 0.5 + 0.5 * t.power, true, 1.15 - 0.3 * t.power)
		client.burst = { pos = pos, power = t.power }
	end
	if t.en ~= client.lastE then
		client.lastE = t.en
		if client.snd[t.ev] then PlaySound(client.snd[t.ev], nil, 0.8) end
		if t.ev == "fail" then client.msg, client.msgT = tr("Aim at flat ground", "Наведите на ровную землю"), 2 end
		if t.ev == "full" then client.msg, client.msgT = tr("Maximum 8 pads", "Не больше 8 батутов"), 2 end
	end
	client.msgT = math.max(0, client.msgT - dt)
	if GetPlayerTool() == TOOL and GetPlayerCanUseTool() and InputPressed("r") then
		ServerCall("server.toggleGlobal", GetLocalPlayer())
	end
	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local a = client.anim[p]
			if not a then a = ToolAnimator() client.anim[p] = a end
			tickToolAnimator(a, dt, nil, p)
		end
	end
end

function client.update(dt)
	local b = client.burst
	if not b then return end
	client.burst = nil
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.6, 0.58, 0.55)
	ParticleRadius(0.15, 0.4)
	ParticleAlpha(0.5, 0)
	ParticleGravity(0)
	ParticleDrag(0.5)
	ParticleCollide(0)
	local n = math.floor(6 + 10 * b.power)
	for i = 1, n do
		local a = i / n * 6.2832
		local dir = Vec(math.cos(a), 0.15, math.sin(a))
		SpawnParticle(VecAdd(b.pos, VecScale(dir, 0.3)), VecScale(dir, 2 + 4 * b.power), 0.8)
	end
end

function client.render(dt)
	-- soft glow lines along the pad edges so pads read as bouncy
	if GetPlayerTool() ~= TOOL then return end
	for _, pad in ipairs(shared.tp.pads) do
		local c = Vec(pad.x, pad.y + PAD_TOP + 0.05, pad.z)
		PointLight(c, 0.4, 0.8, 1.0, 0.5)
	end
end

function client.draw(dt)
	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or not GetPlayerCanUseTool() then return end
	local t = shared.tp
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 160)
		UiAlign("center middle")
		UiTextShadow(0, 0, 0, 0.6, 1.5)
		UiFont("regular.ttf", 22)
		UiColor(1, 1, 1, 0.9)
		UiText(tr("LMB: place a pad    RMB: remove the nearest    R: whole ground bounces", "ЛКМ: поставить батут    ПКМ: убрать ближайший    R: прыгает вся земля"))
		UiTranslate(0, 28)
		UiFont("bold.ttf", 20)
		if t.global then UiColor(0.4, 1, 0.5, 1) else UiColor(0.8, 0.8, 0.8, 0.9) end
		UiText(string.format(tr("Pads: %d / %d    Global mode: %s", "Батутов: %d / %d    Вся земля: %s"), #t.pads, MAX_PADS,
			t.global and tr("ON", "ВКЛ") or tr("off", "выкл")))
		if client.msgT > 0 then
			UiTranslate(0, 28)
			UiColor(1, 0.6, 0.3, math.min(1, client.msgT))
			UiText(client.msg)
		end
	UiPop()
end
