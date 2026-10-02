#version 2
-- Gravity Change / Смена гравитации
-- Press G to switch the scene gravity: Earth, Moon, Mars, zero-G, reverse,
-- sideways. Hold G to go back to Earth. Uses the real SetGravity (server-only,
-- smooth transition), wakes sleeping bodies in a budget so they react, keeps
-- the player upright and gives Space/Ctrl thrusters in zero-G.

#include "script/include/player.lua"

local KEYS = { g = "G", j = "J", k = "K" }
local EARTH = -10.0     -- Teardown's default gravity is (0, -10, 0)
local WAKE_PER_TICK = 40
local SCAN_INTERVAL = 1.0
local HOLD_RESET = 0.8

local PRESETS = {
	{ id = "earth", en = "Earth", ru = "Земля" },
	{ id = "moon", en = "Moon", ru = "Луна" },
	{ id = "mars", en = "Mars", ru = "Марс" },
	{ id = "zerog", en = "Zero-G", ru = "Невесомость" },
	{ id = "reverse", en = "Reverse", ru = "Обратная" },
	{ id = "sideways", en = "Sideways", ru = "Вбок" },
}

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function getS(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetString(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	local key = getS("key", "g")
	if not KEYS[key] then key = "g" end
	return {
		key = key,
		trans = clamp(getF("trans", 1.5), 0, 5),
		reverse = clamp(getF("reverse", 4), 1, 10),
		sideways = clamp(getF("sideways", 6), 2, 10),
		autoReturn = clamp(getF("autoreturn", 0), 0, 120),
		wakeRadius = clamp(getF("wakeradius", 60), 20, 120),
		thrusters = getB("thrusters", true),
		indicator = getB("indicator", true),
	}
end

-- gravity vector of a preset; "right" is the player's right when it was chosen
function presetVector(idx, s, right)
	local id = PRESETS[idx].id
	if id == "moon" then return Vec(0, -1.62, 0) end
	if id == "mars" then return Vec(0, -3.71, 0) end
	if id == "zerog" then return Vec(0, 0, 0) end
	if id == "reverse" then return Vec(0, s.reverse, 0) end
	if id == "sideways" then return VecScale(right, s.sideways) end
	return Vec(0, EARTH, 0)
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	server.from = Vec(0, EARTH, 0)
	server.target = Vec(0, EARTH, 0)
	server.cur = Vec(0, EARTH, 0)
	server.t = 1
	server.T = 0
	server.since = 0
	server.scanT = 0
	server.bodies = {}
	server.cursor = 1
	shared.g = { preset = 1, x = 0, y = EARTH, z = 0, trans = 1, n = 0, heavier = false }
end

function server.select(p, idx, rx, ry, rz)
	local s = readSettings()
	idx = math.floor(clamp(idx, 1, #PRESETS))
	local right = VecNormalize(Vec(rx or 1, 0, rz or 0))
	server.from = VecCopy(server.cur)
	server.target = presetVector(idx, s, right)
	server.t = 0
	server.T = s.trans
	server.since = 0
	server.scanT = 0
	local g = shared.g
	g.preset = idx
	g.n = g.n + 1
	g.heavier = VecLength(server.target) > VecLength(server.from)
	if PRESETS[idx].id == "zerog" then
		for q in Players() do SetPlayerOrientation(Quat(), q) end
	end
end

function server.tick(dt)
	local s = readSettings()
	-- smooth transition (SetGravity only in server code)
	if server.t < 1 then
		if server.T <= 0 then server.t = 1 else server.t = math.min(1, server.t + dt / server.T) end
		local k = server.t * server.t * (3 - 2 * server.t)
		server.cur = VecLerp(server.from, server.target, k)
		SetGravity(server.cur)
	end
	local g = shared.g
	g.x, g.y, g.z = server.cur[1], server.cur[2], server.cur[3]
	g.trans = server.t

	local earth = math.abs(server.cur[2] - EARTH) < 0.01 and math.abs(server.cur[1]) < 0.01 and math.abs(server.cur[3]) < 0.01
	if not earth then
		server.since = server.since + dt
		if s.autoReturn > 0 and server.since > s.autoReturn and g.preset ~= 1 then
			server.select(0, 1, 1, 0, 0)
		end
		server.wake(s, dt)
		if s.thrusters and VecLength(server.cur) < 0.5 then server.thrust(dt) end
	elseif server.t < 1 then
		server.wake(s, dt)
	end
end

-- resting bodies are asleep and would ignore the new gravity: wake them in a budget
function server.wake(s, dt)
	server.scanT = server.scanT - dt
	if server.scanT <= 0 then
		server.scanT = SCAN_INTERVAL
		local list = {}
		local seen = {}
		for p in Players() do
			local c = GetPlayerTransform(p).pos
			local R = s.wakeRadius
			QueryRequire("physical dynamic")
			local found = QueryAabbBodies(VecSub(c, Vec(R, R, R)), VecAdd(c, Vec(R, R, R)))
			for i = 1, #found do
				if not seen[found[i]] then
					seen[found[i]] = true
					list[#list + 1] = found[i]
				end
			end
		end
		server.bodies = list
		server.cursor = 1
	end
	local n = #server.bodies
	local woken = 0
	local checked = 0
	while woken < WAKE_PER_TICK and checked < n and server.cursor <= n do
		local b = server.bodies[server.cursor]
		server.cursor = server.cursor + 1
		checked = checked + 1
		if IsHandleValid(b) and IsBodyDynamic(b) and not IsBodyActive(b) then
			SetBodyActive(b, true)
			woken = woken + 1
		end
	end
end

-- zero-G: Space / Ctrl push the player up and down, a little drag keeps it controllable
function server.thrust(dt)
	for p in Players() do
		if GetPlayerVehicle(p) == 0 then
			local v = GetPlayerVelocity(p)
			local up = (InputDown("jump", p) and 1 or 0) - (InputDown("crouch", p) and 1 or 0)
			v = VecAdd(VecScale(v, 1 - math.min(0.5, 0.6 * dt)), Vec(0, up * 6 * dt, 0))
			SetPlayerVelocity(v, p)
		end
	end
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.snd = { lighter = LoadSound("MOD/snd/lighter.ogg"), heavier = LoadSound("MOD/snd/heavier.ogg"), click = LoadSound("MOD/snd/click.ogg") }
	client.lastN = 0
	client.showT = 6
	client.holdT = 0
	client.resetSent = false
	client.hint = true
end

function client.tick(dt)
	local s = readSettings()
	local g = shared.g
	if g.n ~= client.lastN then
		client.lastN = g.n
		PlaySound(g.heavier and client.snd.heavier or client.snd.lighter, nil, 0.8)
		client.showT = 4
	end
	client.showT = math.max(0, client.showT - dt)
	if GetBool("game.paused") then return end
	local me = GetLocalPlayer()
	if InputDown(s.key) then
		client.holdT = client.holdT + dt
		if client.holdT > HOLD_RESET and not client.resetSent then
			client.resetSent = true
			ServerCall("server.select", me, 1, 1, 0, 0)
		end
	end
	if InputReleased(s.key) then
		if not client.resetSent then
			local cam = GetPlayerCameraTransform()
			local right = TransformToParentVec(cam, Vec(1, 0, 0))
			ServerCall("server.select", me, (g.preset % #PRESETS) + 1, right[1], right[2], right[3])
			PlaySound(client.snd.click, nil, 0.5)
		end
		client.holdT = 0
		client.resetSent = false
	end
end

-- floating dust shows the gravity when it is low
function client.update(dt)
	local g = shared.g
	local mag = math.sqrt(g.x * g.x + g.y * g.y + g.z * g.z)
	if mag > 4 then return end
	local cam = GetPlayerCameraTransform()
	ParticleReset()
	ParticleType("plain")
	ParticleColor(0.8, 0.85, 0.9)
	ParticleRadius(0.015, 0.01)
	ParticleAlpha(0.8, 0)
	ParticleGravity(g.y * 0.3)
	ParticleDrag(0.6)
	ParticleCollide(1)
	for i = 1, 2 do
		local p = VecAdd(cam.pos, Vec((math.random() - 0.5) * 8, (math.random() - 0.5) * 4, (math.random() - 0.5) * 8))
		SpawnParticle(p, GetRandomDirection(0.2), 3)
	end
end

function client.draw(dt)
	local g = shared.g
	local s = readSettings()
	local mag = math.sqrt(g.x * g.x + g.y * g.y + g.z * g.z)
	if mag < 0.5 then UiSoundLoop("MOD/snd/zerog.ogg", 0.35, 1.0) end
	if not s.indicator or GetBool("game.ui.hidemods") then return end
	local notEarth = g.preset ~= 1 or g.trans < 1
	if not notEarth and client.showT <= 0 then return end
	local P = PRESETS[g.preset]
	UiPush()
		UiTranslate(UiWidth() - 270, 50)
		UiAlign("left top")
		UiColor(0, 0, 0, 0.5)
		UiRoundedRect(230, 96, 8)
		-- arrow pointing where "down" is, as seen from the camera
		UiPush()
			UiTranslate(46, 48)
			local cam = GetPlayerCameraTransform()
			local lg = TransformToLocalVec(cam, Vec(g.x, g.y, g.z))
			UiAlign("center middle")
			if mag > 0.05 then
				local ang = math.deg(math.atan2(lg[1], -lg[2]))
				UiRotate(-ang)
				UiColor(1, 0.8, 0.25, 1)
				UiRect(6, 40)
				UiTranslate(0, 22)
				UiRect(18, 6)
			else
				UiColor(0.5, 0.9, 1, 1)
				UiCircleOutline(16, 3)
			end
		UiPop()
		UiTranslate(90, 18)
		UiFont("bold.ttf", 26)
		UiColor(1, 1, 1, 1)
		UiText(tr(P.en, P.ru))
		UiTranslate(0, 32)
		UiFont("regular.ttf", 20)
		UiColor(0.8, 0.9, 1, 0.9)
		UiText(string.format("%.2f g", mag / 10))
		if g.trans < 1 then
			UiTranslate(0, 26)
			UiColor(0, 0, 0, 0.6)
			UiRect(120, 6)
			UiColor(1, 0.8, 0.25, 1)
			UiRect(120 * g.trans, 6)
		end
	UiPop()
	if client.showT > 0 and client.hint then
		UiPush()
			UiTranslate(UiWidth() - 270, 156)
			UiAlign("left top")
			UiFont("regular.ttf", 16)
			UiColor(1, 1, 1, math.min(1, client.showT))
			UiText(tr(KEYS[s.key] .. ": next gravity, hold: Earth", KEYS[s.key] .. ": следующая, удержать: Земля"))
			if mag < 0.5 and s.thrusters then
				UiTranslate(0, 20)
				UiText(tr("Space / Ctrl: up / down", "Пробел / Ctrl: вверх / вниз"))
			end
		UiPop()
	end
end
