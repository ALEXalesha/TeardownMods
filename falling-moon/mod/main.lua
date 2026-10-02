#version 2
-- Falling Moon / Падающая луна
-- Telescope tool. LMB marks the impact point: the moon starts to fall towards it
-- over 1-5 minutes, growing in the sky. Tremors, wind and lifting debris build
-- up, the sky turns red, a countdown runs. At the end: a blinding flash, a huge
-- crater, and a shockwave that rolls outwards over several frames, throwing
-- everything away, punching holes and starting fires; then dust and a slow
-- return of the sky. RMB during the approach sends the moon back.
--
-- Server: timeline, tremors and wind (budgeted impulses), sky tint
-- (SetEnvironmentProperty is server-side, like the game's own weather),
-- crater, shockwave in waves, fires, player push.
-- Client: the moon (a camera-facing sprite, kept within draw distance and scaled
-- to the right angular size), sounds, camera shake, flash, dust, countdown.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "fallingmoon"
local SHOCK_SPEED = 120
local AFTERMATH = 30
local RECEDE = 4
local SCAN_INTERVAL = 1.0
local TREMOR_PER_UPDATE = 30
local SHOCK_PER_UPDATE = 80
local HOLE_PROBES = 8
local MAX_SHOCK_BODIES = 600
local MOON_RADIUS = 1700     -- metres, a scaled-down moon so it reads well
local START_DIST = 60000     -- metres away when it starts falling
local SPRITE_DIST = 450      -- the sprite is drawn this far away at most

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function rnd(a, b) return a + (b - a) * math.random() end
local function smooth(a, b, x) local t = clamp((x - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getI(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetInt(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		duration = clamp(getF("duration", 120), 60, 300),
		radius = clamp(getF("radius", 150), 50, 300),
		damage = math.floor(clamp(getI("damage", 1), 0, 2)),
		fire = getB("fire", true),
		tint = clamp(getF("tint", 0.8), 0, 1),
		countdown = getB("countdown", true),
		tremors = getB("tremors", true),
	}
end

-- distance of the moon from the impact point at progress p (0..1)
function moonDistance(p)
	return START_DIST * (1 - p) ^ 2.2 + 30
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

local ENV_KEYS = { "skyboxtint", "fogColor", "sunColorTint" }
local ENV_RED = { skyboxtint = { 1.0, 0.35, 0.2 }, fogColor = { 0.5, 0.16, 0.08 }, sunColorTint = { 1.0, 0.35, 0.15 } }

function server.init()
	RegisterTool(TOOL, tr("Moon Caller", "Зов луны"), "MOD/prefab/tool.xml", 6)
	server.ev = nil
	shared.m = { phase = "idle", t = 0, T = 1, x = 0, y = 0, z = 0, dx = 0, dy = 1, dz = 0, r = 0, R = 150, n = 0, prog = 0 }
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
			if InputPressed("grab", p) and server.ev and server.ev.phase == "approach" then server.abort() end
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
	-- the moon comes in from above, slightly from behind the impact point as seen by the player
	local away = VecSub(target, eye.pos)
	away[2] = 0
	away = VecLength(away) > 0.1 and VecNormalize(away) or Vec(0, 0, -1)
	local dir = VecNormalize(VecAdd(Vec(0, 1, 0), VecScale(away, 0.7)))
	server.ev = { phase = "approach", t = 0, T = s.duration, center = target, dir = dir, s = s, orig = captureEnv(),
		tracked = {}, cursor = 1, scanT = 0, tintT = 0, owner = p }
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
	if ev.phase == "approach" then
		local p = clamp(ev.t / ev.T, 0, 1)
		m.prog = p
		local I = smooth(0.35, 1.0, p)
		server.tint(ev, dt, I * ev.s.tint)
		if ev.s.tremors and I > 0 then server.tremors(ev, dt, I) end
		if ev.t >= ev.T then server.impact(ev) end
	elseif ev.phase == "recede" then
		local p = ev.recedeFrom * clamp(1 - ev.t / RECEDE, 0, 1)
		m.prog = p
		server.tint(ev, dt, smooth(0.35, 1, p) * ev.s.tint)
		if ev.t >= RECEDE then server.finish() end
	elseif ev.phase == "impact" then
		server.shock(ev, dt)
	elseif ev.phase == "aftermath" then
		local k = 1 - smooth(AFTERMATH - 20, AFTERMATH, ev.t)
		server.tint(ev, dt, k * ev.s.tint)
		if ev.t >= AFTERMATH then server.finish() end
	end
end

function server.tint(ev, dt, k)
	ev.tintT = ev.tintT - dt
	if ev.tintT > 0 then return end
	ev.tintT = 0.5
	applyEnv(ev.orig, k)
end

function server.finish()
	local ev = server.ev
	applyEnv(ev.orig, 0)
	server.ev = nil
	shared.m.phase = "idle"
	shared.m.prog = 0
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
					-- light things start to lift and drift with the wind
					dv = VecAdd(dv, VecAdd(Vec(0, 7 * (I - 0.5) * dt * stride, 0), VecScale(wind, 5 * I * dt * stride)))
				end
				ApplyBodyImpulse(b, TransformToParentPoint(GetBodyTransform(b), GetBodyCenterOfMass(b)), VecScale(dv, mass))
			end
		end
	end
end

function server.impact(ev)
	local s = ev.s
	local c = ev.center
	ev.phase = "impact"
	ev.t = 0
	ev.r = 0
	local m = shared.m
	m.phase = "impact"
	m.t = 0
	m.r = 0
	m.prog = 1
	applyEnv(ev.orig, s.tint)
	-- crater and the lunar boulder
	MakeHole(c, 8, 6, 3.5, false)
	Explosion(c, 4, ev.owner)
	Spawn("<body dynamic='false'><vox file='MOD/vox/boulder.vox' scale='2'/></body>", Transform(VecAdd(c, Vec(0, -2.5, 0)), QuatEuler(rnd(-15, 15), rnd(0, 360), rnd(-15, 15))), true)
	-- every body in reach, nearest first; the shockwave works through the list over several frames
	local R = s.radius
	QueryRequire("physical dynamic")
	local list = QueryAabbBodies(VecSub(c, Vec(R, R * 0.4, R)), VecAdd(c, Vec(R, R * 0.6, R)))
	local items = {}
	for i = 1, #list do
		local b = list[i]
		if GetBodyPlayer(b) == 0 then
			local d = VecLength(VecSub(GetBodyTransform(b).pos, c))
			if d <= R then items[#items + 1] = { b = b, d = d } end
		end
	end
	table.sort(items, function(a, b) return a.d < b.d end)
	while #items > MAX_SHOCK_BODIES do table.remove(items) end
	ev.items = items
	ev.next = 1
	ev.hitPlayers = {}
end

function server.shock(ev, dt)
	local s = ev.s
	local c = ev.center
	local R = s.radius
	ev.r = math.min(R, ev.r + SHOCK_SPEED * dt)
	shared.m.r = ev.r
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
				local k = (1 - it.d / R) ^ 0.8
				local speed = 30 * k + 4
				local massK = clamp(3000 / mass, 0.1, 1)
				ApplyBodyImpulse(it.b, pos, VecScale(VecNormalize(VecAdd(out, Vec(0, 0.45, 0))), mass * speed * massK))
			end
		end
	end
	-- holes and fires along the front
	local k = 1 - ev.r / R
	for i = 1, HOLE_PROBES do
		local a = math.random() * 6.2832
		local p = VecAdd(c, Vec(math.cos(a) * ev.r, rnd(0.5, 8), math.sin(a) * ev.r))
		QueryRequire("physical")
		local hit, point = QueryClosestPoint(p, 2.5)
		if hit then
			MakeHole(point, 0.4 + 2.0 * k, 0.2 + 1.4 * k, 0.6 * k, true)
			if s.fire and ev.r < R * 0.4 and i <= 2 then SpawnFire(point) end
		end
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

function client.render(dt)
	local m = shared.m
	if m.phase ~= "approach" and m.phase ~= "recede" then return end
	local cam = GetCameraTransform()
	local center = Vec(m.x, m.y, m.z)
	local dist = moonDistance(m.prog)
	local true_pos = VecAdd(center, VecScale(Vec(m.dx, m.dy, m.dz), dist + MOON_RADIUS))
	local toMoon = VecSub(true_pos, cam.pos)
	local d = VecLength(toMoon)
	local dir = VecScale(toMoon, 1 / d)
	local spriteDist = math.min(d, SPRITE_DIST)
	local ang = math.atan(MOON_RADIUS / math.max(d, 1))
	local size = 2 * spriteDist * math.tan(ang)
	local pos = VecAdd(cam.pos, VecScale(dir, spriteDist))
	local t = Transform(pos, QuatLookAt(pos, cam.pos))
	DrawSprite(client.glow, t, size * 1.6, size * 1.6, 1.0, 0.5, 0.3, 0.35 + 0.4 * m.prog, false, true)
	DrawSprite(client.moon, t, size, size, 1.0, 0.95 - 0.35 * m.prog, 0.9 - 0.5 * m.prog, 1, false, false)
	if m.prog > 0.6 then
		PointLight(VecAdd(cam.pos, VecScale(dir, 40)), 1, 0.4, 0.2, 6 * (m.prog - 0.6))
	end
end

-- dust: rolling cloud on the shock front near the player, settling dust afterwards
function client.update(dt)
	local m = shared.m
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
		for i = 1, 6 do SpawnParticle(VecAdd(center, Vec(0, 4, 0)), GetRandomDirection(rnd(15, 40)), rnd(1, 3)) end
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
		-- red edges
		UiPush()
			UiColor(0.6, 0.1, 0.05, 0.25 * I * s.tint)
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
			elseif m.phase == "approach" then
				UiText(tr("RMB: send the moon back", "ПКМ: отправить луну обратно"))
			else
				UiText(tr("Wait for the dust to settle", "Ждите, пока осядет пыль"))
			end
		UiPop()
	end
end
