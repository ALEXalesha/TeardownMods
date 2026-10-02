#version 2
-- Trampoline Floor / Пол-батут
-- Pad placer tool. LMB places a 3 x 3 m trampoline pad on the ground, RMB
-- removes the nearest one, R toggles "global mode" in which the whole ground
-- bounces. Players, dynamic bodies and vehicles that land fast on a pad (or on
-- any static ground in global mode) are thrown back up with the restitution
-- from the options. Boing sound, squash dust, the pad membrane dips.
--
-- Teardown has no per-surface restitution, so the bounce is a velocity change.
-- Contact is found by position: when the bottom of a falling player or body is
-- within reach of the bouncy surface before the next physics step, its falling
-- speed (or the one remembered from the last 0.25 s) is given back upwards times
-- the restitution, default 1.05, so every bounce is a little higher, up to the
-- speed cap. Jump pressed on contact adds a boost.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "trampoline"
local PAD_XML = "<body dynamic='false'><vox file='MOD/vox/pad.vox'/></body>"
local PAD_HALF = 1.45          -- half side of the bouncy area (m)
local PAD_TOP = 0.2            -- membrane height above the pad origin
local MAX_PADS = 8
local SCAN_INTERVAL = 0.25
local HOT_PER_UPDATE = 60      -- falling bodies, round robin (all of them every step up to this many)
local COLD_PER_UPDATE = 30     -- the rest, round robin, to notice a new fall
local RAYS_PER_UPDATE = 24     -- ground height measurements per step (global mode)
local MIN_LAND = 1.5           -- m/s: a fall at least this fast is a landing
local MEMORY = 0.25            -- s: a fall speed is remembered this long after touching down
local CONTACT = 0.12           -- m: contact band above the surface
local COOLDOWN = 0.25          -- s between two bounces of the same thing
local JUMP_BUFFER = 0.3        -- s: jump pressed this shortly before contact still counts
local MIN_UP = 3.0             -- m/s: the weakest bounce

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		restitution = clamp(getF("restitution", 1.05), 0.3, 1.5),
		maxSpeed = clamp(getF("maxspeed", 30), 5, 60),
		jumpBoost = clamp(getF("jumpboost", 6), 0, 15),
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
	server.pst = {}
	server.hot = {}
	server.hotList = {}
	server.hotCursor = 1
	server.clock = 0
	server.rays = RAYS_PER_UPDATE
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

-- The bouncy surface under a point: a pad's membrane, or (global mode) the static ground.
-- Returns the surface height and the pad (nil for ground). Ground heights are cached per
-- tracked thing and only re-measured after it moved sideways, so a falling crowd costs
-- a raycast now and then, not every step.
local function surfaceUnder(bottom, st, global, rejectBody, rejectPlayer)
	for i = 1, #server.pads do
		local pad = server.pads[i]
		if IsHandleValid(pad.body) then
			local l = TransformToLocalPoint(Transform(pad.pos, pad.rot), bottom)
			if math.abs(l[1]) < PAD_HALF and math.abs(l[3]) < PAD_HALF and l[2] > PAD_TOP - 0.6 then
				return pad.pos[2] + PAD_TOP, pad
			end
		end
	end
	if not global then return nil end
	local stale = st.gy == nil or math.abs(bottom[1] - st.gx) + math.abs(bottom[3] - st.gz) > 0.75 or bottom[2] < st.gy - 0.6
	if stale and server.rays <= 0 and st.gy == nil then return nil end   -- out of raycasts this step: try the next one
	if stale and server.rays > 0 then
		server.rays = server.rays - 1
		if rejectBody then QueryRejectBody(rejectBody) end
		if rejectPlayer then QueryRejectPlayer(rejectPlayer) end
		QueryRequire("physical static")
		local from = VecAdd(bottom, Vec(0, 0.4, 0))
		local hit, dist = QueryRaycast(from, Vec(0, -1, 0), 80)
		st.gx, st.gz = bottom[1], bottom[3]
		st.gy = hit and (from[2] - dist) or -1e9
	end
	if st.gy < -1e8 then return nil end
	return st.gy, nil
end

local function newState() return { fall = 0, fallT = 99, cool = 0, jumpT = 99, last = server.clock } end

local function bounceSpeed(impact, s, boost)
	return clamp(impact * s.restitution + boost, MIN_UP, s.maxSpeed)
end

-- One contact test. Remembers the last falling speed for a moment (the engine may
-- already have stopped the fall by the time we look), and bounces when the bottom is
-- within reach of the surface before the next check, so the bounce happens in the air,
-- not after the engine has settled the landing. Returns the new vertical speed or nil.
local function contact(st, bottom, vy, dt, reachDt, s, global, boost, rejectBody, rejectPlayer)
	st.cool = st.cool - dt
	if vy < -MIN_LAND then
		st.fall = -vy
		st.fallT = 0
	else
		st.fallT = st.fallT + dt
	end
	if st.cool > 0 then return nil end
	local surf, pad = surfaceUnder(bottom, st, global, rejectBody, rejectPlayer)
	if not surf then return nil end
	local gap = bottom[2] - surf
	local reach = math.max(CONTACT, -vy * reachDt * 1.5)
	if gap > reach or gap < -0.6 or vy > 1 then return nil end
	local impact = (vy < -MIN_LAND) and -vy or ((st.fallT <= MEMORY) and st.fall or 0)
	if impact < MIN_LAND then return nil end
	local up = bounceSpeed(impact, s, boost)
	st.cool = COOLDOWN
	st.fall = 0
	st.fallT = 99
	if pad then pad.dip = math.min(0.12, impact * 0.01) end
	bounceEvent(Vec(bottom[1], surf, bottom[3]), clamp(impact / 15, 0.2, 1))
	return up
end

function server.update(dt)
	local s = readSettings()
	local global = shared.tp.global
	server.clock = server.clock + dt
	server.rays = RAYS_PER_UPDATE
	-- membrane spring-back animation (pads are static and server-authored, animated here)
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
			local st = server.pst[p]
			if not st then st = newState() server.pst[p] = st end
			-- jump pressed shortly before or during the contact adds a boost
			if InputDown("jump", p) or InputPressed("jump", p) then st.jumpT = 0 else st.jumpT = st.jumpT + dt end
			if GetPlayerVehicle(p) == 0 then
				local v = GetPlayerVelocity(p)
				local boost = (st.jumpT <= JUMP_BUFFER) and s.jumpBoost or 0
				local up = contact(st, GetPlayerTransform(p).pos, v[2], dt, dt, s, global, boost, nil, p)
				if up then
					SetPlayerVelocity(Vec(v[1], up, v[3]), p)
					st.jumpT = 99
				end
			end
		end
	end

	if s.bodies or s.vehicles then
		server.scanT = server.scanT - dt
		if server.scanT <= 0 then
			server.scanT = SCAN_INTERVAL
			server.tracked = server.scan(s, global)
			server.cursor = 1
		end
		-- falling (hot) bodies, round robin: every step while there are up to HOT_PER_UPDATE
		local list = server.hotList
		local per = math.min(#list, HOT_PER_UPDATE)
		local interval = math.max(1, math.ceil(#list / HOT_PER_UPDATE)) * dt
		for k = 1, per do
			if #list == 0 then break end
			if server.hotCursor > #list then server.hotCursor = 1 end
			local b = list[server.hotCursor]
			local st = server.hot[b]
			if st and server.checkBody(b, st, s, global, interval) then
				server.hotCursor = server.hotCursor + 1
			else
				server.hot[b] = nil
				list[server.hotCursor] = list[#list]
				list[#list] = nil
			end
		end
		-- the rest round robin, only to notice a new fall
		local n = #server.tracked
		for k = 1, math.min(n, COLD_PER_UPDATE) do
			local b = server.tracked[server.cursor]
			server.cursor = (server.cursor % n) + 1
			if not server.hot[b] and IsHandleValid(b) and IsBodyDynamic(b) and GetBodyVelocity(b)[2] < -MIN_LAND then
				server.hot[b] = newState()
				list[#list + 1] = b
			end
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
		add(QueryAabbBodies(VecSub(c, Vec(2.5, 0.5, 2.5)), VecAdd(c, Vec(2.5, 30, 2.5))))
	end
	if global then
		for p in Players() do
			local c = GetPlayerTransform(p).pos
			local R = s.radius
			QueryRequire("physical dynamic")
			add(QueryAabbBodies(VecSub(c, Vec(R, 5, R)), VecAdd(c, Vec(R, R, R))))
		end
	end
	-- hot bodies that left the area are dropped
	local list = {}
	for i = 1, #server.hotList do
		local b = server.hotList[i]
		if seen[b] then list[#list + 1] = b else server.hot[b] = nil end
	end
	server.hotList = list
	server.hotCursor = 1
	return out
end

-- returns false when the body should leave the hot list
function server.checkBody(b, st, s, global, interval)
	if not IsHandleValid(b) or not IsBodyDynamic(b) then return false end
	local since = server.clock - st.last
	st.last = server.clock
	local v = GetBodyVelocity(b)
	local bmin, bmax = GetBodyBounds(b)
	local bottom = Vec((bmin[1] + bmax[1]) * 0.5, bmin[2], (bmin[3] + bmax[3]) * 0.5)
	local up = contact(st, bottom, v[2], since, interval, s, global, 0, b, nil)
	if up then SetBodyVelocity(b, Vec(v[1], up, v[3])) end
	-- cooled down and no longer falling: back to the round robin
	return not (st.fallT > MEMORY and v[2] > -MIN_LAND and st.cool <= 0)
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
