#version 2
-- Vehicle Remote / Радиоуправление
-- Aim at any vehicle and press LMB to drive it like an RC car while you stay
-- where you are. W/S throttle and reverse, A/D steer, Space handbrake, V toggles
-- the chase camera, mouse orbits it, Q lets go. LMB on another vehicle hops to
-- it. Past the signal range the link is lost: the car brakes and is released.
--
-- Uses the real driving API: DriveVehicle(vehicle, drive, steering, handbrake),
-- called every tick from server code (vehicles are server-authored, so the
-- client only reads them and sends its input with ServerCall).

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "rcremote"
local LOST_RELEASE = 3.0

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		range = clamp(getF("range", 150), 30, 500),
		aimRange = clamp(getF("aimrange", 80), 10, 200),
		follow = getB("follow", true),
		camDist = clamp(getF("camdist", 7), 3, 20),
		freeze = getB("freeze", true),
		sens = clamp(getF("sens", 1), 0.2, 3),
	}
end

-- vehicle hit by a ray (works on any body of the vehicle, wheels included); `skip` is passed through
local function vehicleOnRay(p, origin, dir, range, skip)
	QueryRejectPlayer(p)
	if skip and skip ~= 0 then
		QueryRejectVehicle(skip)
		QueryRejectBody(GetVehicleBody(skip))
	end
	QueryRequire("physical")
	local hit, dist, _, shape = QueryRaycast(origin, dir, range)
	if hit and shape ~= 0 then
		return GetBodyVehicle(GetShapeBody(shape))
	end
	return 0
end

-- vehicle under the crosshair of the player's own eye
local function aimedVehicle(p, range)
	local eye = GetPlayerEyeTransform(p)
	return vehicleOnRay(p, eye.pos, TransformToParentVec(eye, Vec(0, 0, -1)), range)
end

-- vehicle in sight closest to the view direction, within 10 degrees (the chase camera looks down
-- at its own car, so a car further away sits above the middle of the picture)
local function nearView(p, origin, dir, range, skip)
	local best, bestA = 0, math.cos(math.rad(10))
	local list = FindVehicles("", true)
	for i = 1, #list do
		local v = list[i]
		if v ~= skip then
			local to = VecSub(GetVehicleTransform(v).pos, origin)
			local d = VecLength(to)
			if d > 0.5 and d < range and VecDot(to, dir) / d > bestA then
				if vehicleOnRay(p, origin, VecScale(to, 1 / d), d + 2, skip) == v then best, bestA = v, VecDot(to, dir) / d end
			end
		end
	end
	return best
end

-- hop target seen from the chase camera; if it finds nothing, the body's eye (the outline shows it)
local function hopTarget(p, camPos, camDir, s, current)
	local range = s.aimRange + s.camDist
	local v = vehicleOnRay(p, camPos, camDir, range, current)
	if v == 0 then v = nearView(p, camPos, camDir, range, current) end
	if v == 0 then v = aimedVehicle(p, s.aimRange) end
	return v
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Vehicle Remote", "Пульт радиоуправления"), "MOD/prefab/tool.xml", 6)
	server.c = {}          -- player -> control state
	shared.rc = {}
end

local function st(p)
	local s = shared.rc[p]
	if not s then
		s = { vehicle = 0, weak = 0, lost = false, n = 0, ev = "", msg = "", mn = 0 }
		shared.rc[p] = s
	end
	return s
end

local function event(p, kind)
	local s = st(p)
	s.n = s.n + 1
	s.ev = kind
end

local function message(p, code)
	local s = st(p)
	s.mn = s.mn + 1
	s.msg = code
end

local function takenBy(v)
	for q, c in pairs(server.c) do if c.vehicle == v then return q end end
	-- a player sitting in it?
	for q in Players() do if GetPlayerVehicle(q) == v then return q end end
	return nil
end

function server.tick(dt)
	for p in PlayersAdded() do
		SetToolEnabled(TOOL, true, p)
		st(p)
	end
	for p in PlayersRemoved() do
		server.c[p] = nil
		shared.rc[p] = nil
	end
	for p in Players() do
		-- on foot the click is read here; while driving, DisablePlayerInput (the freeze option)
		-- swallows server-side reads, so the client forwards the hop click instead
		if not server.c[p] and GetPlayerTool(p) == TOOL and GetPlayerCanUseTool(p) and GetPlayerVehicle(p) == 0 then
			if InputPressed("usetool", p) then server.grab(p) end
		end
		local c = server.c[p]
		-- putting the remote away lets the car go, like the drone: Q / V are tool keys of other mods
		-- (mover, catapult) and would act on the car too (16.10, _shared/tdlib/keymap.py)
		if c and GetPlayerTool(p) ~= TOOL then
			server.release(p)
			c = nil
		end
		if c then server.drive(p, c, dt) end
	end
end

function server.grab(p)
	local s = readSettings()
	server.connect(p, aimedVehicle(p, s.aimRange), s)
end

-- hop aimed from the client's chase camera: the server casts the ray itself
function server.hop(p, ox, oy, oz, dx, dy, dz)
	local c = server.c[p]
	if not c then return end
	local s = readSettings()
	local origin = Vec(ox, oy, oz)
	-- the chase camera is at most camDist (20 m max) from the car
	if VecLength(VecSub(origin, GetVehicleTransform(c.vehicle).pos)) > 25 then return end
	local dir = Vec(dx, dy, dz)
	if VecLength(dir) < 1e-3 then return end
	server.connect(p, hopTarget(p, origin, VecNormalize(dir), s, c.vehicle), s)
end

function server.connect(p, v, s)
	if v == 0 then
		if not server.c[p] then message(p, "novehicle") end
		return
	end
	local c = server.c[p]
	if c and c.vehicle == v then return end
	local owner = takenBy(v)
	if owner and owner ~= p then
		message(p, "taken")
		return
	end
	local hop = c ~= nil
	server.c[p] = { vehicle = v, drive = 0, steer = 0, brake = false, lostT = 0, s = s }
	local sp = st(p)
	sp.vehicle = v
	sp.lost = false
	sp.weak = 0
	event(p, hop and "hop" or "connect")
end

function server.release(p)
	if not server.c[p] then return end
	local v = server.c[p].vehicle
	server.c[p] = nil
	local sp = st(p)
	sp.vehicle = 0
	sp.lost = false
	sp.weak = 0
	event(p, "disconnect")
end

function server.input(p, drive, steer, brake)
	local c = server.c[p]
	if not c then return end
	c.drive = clamp(drive, -1, 1)
	c.steer = clamp(steer, -1, 1)
	c.brake = brake == true
end

function server.drive(p, c, dt)
	local v = c.vehicle
	local body = GetVehicleBody(v)
	if body == 0 or not IsHandleValid(body) then
		server.release(p)
		return
	end
	if GetPlayerHealth(p) <= 0 then
		-- a dead player lets go
		server.release(p)
		return
	end
	-- frozen also while the signal is lost
	if c.s.freeze then DisablePlayerInput(p) end
	local sp = st(p)
	local dist = VecLength(VecSub(GetVehicleTransform(v).pos, GetPlayerTransform(p).pos))
	local weak = clamp((dist - 0.75 * c.s.range) / (0.25 * c.s.range), 0, 1)
	sp.weak = weak
	if dist > c.s.range then
		if not sp.lost then
			sp.lost = true
			event(p, "lost")
		end
		c.lostT = c.lostT + dt
		DriveVehicle(v, 0, 0, true)
		if c.lostT > LOST_RELEASE then server.release(p) end
		return
	end
	sp.lost = false
	c.lostT = 0
	DriveVehicle(v, c.drive, c.steer, c.brake)
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

local MESSAGES = {
	novehicle = { "Aim at a vehicle", "Наведите на машину" },
	taken = { "Someone else drives that one", "Этой машиной уже кто-то управляет" },
}

function client.init()
	client.snd = {}
	for _, n in ipairs({ "connect", "disconnect", "hop", "lost" }) do client.snd[n] = LoadSound("MOD/snd/" .. n .. ".ogg") end
	client.anim = {}
	client.seenN = {}
	client.seenMsg = nil
	client.msgText = ""
	client.msgT = 0
	client.sent = { d = 0, s = 0, b = false }
	client.follow = nil
	client.yaw = 0
	client.pitch = -15
	client.aim = 0
	client.wasDriving = false
end

local function mine() return shared.rc[GetLocalPlayer()] end

function client.tick(dt)
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local me = GetLocalPlayer()
	local s = readSettings()
	if client.follow == nil then client.follow = s.follow end

	for p, sp in pairs(shared.rc) do
		if client.seenN[p] ~= nil and client.seenN[p] ~= sp.n and client.snd[sp.ev] and p == me then
			PlaySound(client.snd[sp.ev], nil, 0.8)
		end
		client.seenN[p] = sp.n
	end
	local sp = mine()
	if sp then
		if client.seenMsg ~= nil and sp.mn ~= client.seenMsg and MESSAGES[sp.msg] then
			client.msgText = tr(MESSAGES[sp.msg][1], MESSAGES[sp.msg][2])
			client.msgT = 2
		end
		client.seenMsg = sp.mn
	end
	client.msgT = math.max(0, client.msgT - dt)

	local holding = GetPlayerTool() == TOOL and GetPlayerCanUseTool()
	local driving = sp and sp.vehicle ~= 0
	client.camPos = nil
	if driving and not client.wasDriving then
		local vt = GetVehicleTransform(sp.vehicle)
		local fwd = TransformToParentVec(vt, Vec(0, 0, -1))
		client.yaw = math.deg(math.atan2(-fwd[1], -fwd[3]))
		client.pitch = -15
	end
	client.wasDriving = driving
	if driving and client.sentVehicle ~= sp.vehicle then
		-- a new car starts with no input on the server: send the held keys again
		client.sent = { d = 0, s = 0, b = false }
	end
	client.sentVehicle = driving and sp.vehicle or 0

	if driving then
		local function axis(a, b) return (InputDown(a) and 1 or 0) - (InputDown(b) and 1 or 0) end
		local d = axis("up", "down")
		local st = axis("right", "left")
		local b = InputDown("jump")
		if d ~= client.sent.d or st ~= client.sent.s or b ~= client.sent.b then
			ServerCall("server.input", me, d, st, b)
			client.sent = { d = d, s = st, b = b }
		end
		if InputPressed("q") then ServerCall("server.release", me) end
		if InputPressed("v") then client.follow = not client.follow end
		if client.follow then
			client.yaw = client.yaw - math.deg(InputValue("camerax")) * s.sens
			client.pitch = clamp(client.pitch - math.deg(InputValue("cameray")) * s.sens, -70, 10)
			local vt = GetVehicleTransform(sp.vehicle)
			local rot = QuatEuler(client.pitch, client.yaw, 0)
			local back = QuatRotateVec(rot, Vec(0, 0, s.camDist))
			local target = VecAdd(vt.pos, Vec(0, 1.2, 0))
			local pos = VecAdd(target, back)
			-- do not put the camera inside a wall
			QueryRequire("physical static")
			local hit, dist = QueryRaycast(target, VecNormalize(back), s.camDist)
			if hit then pos = VecAdd(target, VecScale(VecNormalize(back), math.max(0.8, dist - 0.3))) end
			SetCameraTransform(Transform(pos, rot), 75)
			client.camPos, client.camDir = pos, QuatRotateVec(rot, Vec(0, 0, -1))
		end
		if InputPressed("usetool") and GetPlayerTool() == TOOL then
			if client.camPos then
				local o, d = client.camPos, client.camDir
				ServerCall("server.hop", me, o[1], o[2], o[3], d[1], d[2], d[3])
			else
				ServerCall("server.grab", me)
			end
		end
	else
		client.sent = { d = 0, s = 0, b = false }
	end
	-- outline target: what LMB would take or hop to
	if not holding then
		client.aim = 0
	elseif client.camPos then
		client.aim = hopTarget(me, client.camPos, client.camDir, s, sp.vehicle)
	else
		client.aim = aimedVehicle(me, s.aimRange)
	end

	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local a = client.anim[p]
			if not a then a = ToolAnimator() client.anim[p] = a end
			tickToolAnimator(a, dt, nil, p)
		end
	end
end

function client.render(dt)
	local sp = mine()
	if sp and sp.vehicle ~= 0 then
		local b = GetVehicleBody(sp.vehicle)
		if b ~= 0 then DrawBodyOutline(b, 0.3, 1, 1, 0.8) end
	end
	if client.aim ~= 0 and (not sp or client.aim ~= sp.vehicle) then
		local b = GetVehicleBody(client.aim)
		if b ~= 0 then DrawBodyOutline(b, 1, 1, 1, 0.5) end
	end
end

local function staticNoise(amount)
	UiPush()
		local n = math.floor(120 * amount)
		for i = 1, n do
			UiPush()
				UiTranslate(math.random() * UiWidth(), math.random() * UiHeight())
				local c = math.random()
				UiColor(c, c, c, 0.4 + 0.5 * amount)
				UiRect(math.random(2, 50), math.random(1, 3))
			UiPop()
		end
	UiPop()
end

function client.draw(dt)
	local sp = mine()
	local driving = sp and sp.vehicle ~= 0
	if driving then
		local amount = sp.lost and 1 or sp.weak
		if amount > 0.02 then
			staticNoise(amount)
			UiSoundLoop("MOD/snd/static.ogg", 0.5 * amount, 1.0)
		end
	end
	if GetPlayerTool() ~= TOOL and not driving then return end
	if GetBool("game.ui.hidemods") then return end
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 170)
		UiAlign("center middle")
		UiTextShadow(0, 0, 0, 0.6, 1.5)
		if driving then
			local b = GetVehicleBody(sp.vehicle)
			local speed = b ~= 0 and VecLength(GetBodyVelocity(b)) * 3.6 or 0
			local health = GetVehicleHealth(sp.vehicle)
			local bars = sp.lost and 0 or math.floor((1 - sp.weak) * 4 + 0.5)
			UiFont("bold.ttf", 26)
			UiColor(0.5, 1, 1, 1)
			UiText(string.format(tr("%d km/h   damage %d%%   signal %s", "%d км/ч   повреждения %d%%   сигнал %s"),
				math.floor(speed + 0.5), math.floor((1 - health) * 100 + 0.5), string.rep("|", bars) .. string.rep(".", 4 - bars)))
			UiTranslate(0, 30)
			UiFont("regular.ttf", 20)
			UiColor(1, 1, 1, 0.85)
			UiText(tr("W/S drive   A/D steer   Space brake   V camera   Q let go   LMB on another car: hop",
				"W/S газ/назад   A/D руль   Пробел тормоз   V камера   Q отпустить   ЛКМ по другой машине: пересесть"))
			if sp.lost then
				UiTranslate(0, -90)
				UiFont("bold.ttf", 36)
				UiColor(1, 0.3, 0.25, 1)
				UiText(tr("SIGNAL LOST", "НЕТ СИГНАЛА"))
			end
		else
			UiFont("regular.ttf", 22)
			UiColor(1, 1, 1, 0.9)
			UiText(tr("LMB on a vehicle: take remote control", "ЛКМ по машине: взять на радиоуправление"))
		end
		if client.msgT > 0 then
			UiTranslate(0, 34)
			UiFont("bold.ttf", 20)
			UiColor(1, 0.6, 0.3, math.min(1, client.msgT))
			UiText(client.msgText)
		end
	UiPop()
end
