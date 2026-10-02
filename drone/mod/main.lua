#version 2
-- Camera Drone / Дрон с камерой
-- A deployable quadcopter flown from its own camera while the player's body
-- stays behind. WASD move, Space/Ctrl up/down, mouse looks, LMB drops a bomb
-- (the Singularity Grenade if that mod is enabled, otherwise a built-in bomb),
-- Q returns the view to the player, P toggles photo mode, R packs the drone up
-- when you stand next to it. Battery and signal range are limited; near the
-- range edge the picture gets static, past it the drone loses the link and
-- slowly descends. Hitting something too fast breaks it.
--
-- Client: reads the pilot's input (raw keys are client side), camera, HUD,
--         static, marker, sounds, rotor animation. Sends input with ServerCall.
-- Server: drone bodies, flight physics, battery, range, crash, bombs.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "drone"
local DRONE_XML = "<body dynamic='true'><vox file='MOD/vox/drone.vox' scale='0.5'/></body>"
local BOMB_XML = "<body dynamic='true'><vox file='MOD/vox/bomb.vox' scale='0.5'/></body>"
local DEBRIS_XML = "<body dynamic='true'><voxbox size='3 1 2'/></body>"
local REQ = "level.singularity_grenade."
local CLIMB = 4.0
local PACK_DIST = 4.0

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function rnd(a, b) return a + (b - a) * math.random() end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		speed = clamp(getF("speed", 12), 5, 25),
		range = clamp(getF("range", 150), 50, 500),
		battery = getB("battery", true),
		minutes = clamp(getF("minutes", 3), 1, 10),
		bombs = math.floor(clamp(getF("bombs", 3), 1, 10)),
		grenade = getB("grenade", true),
		bombSize = clamp(getF("bombsize", 1.0), 0.5, 2.0),
		crash = clamp(getF("crash", 9), 4, 20),
		sens = clamp(getF("sens", 1), 0.2, 3),
		fov = clamp(getF("fov", 90), 60, 110),
		freeze = getB("freeze", true),
	}
end

local function yawFrame(yaw)
	local r = math.rad(yaw)
	return Vec(-math.sin(r), 0, -math.cos(r)), Vec(math.cos(r), 0, -math.sin(r))
end

-- rotor shapes are 7 x 1 x 7 voxels (thin in Teardown's y)
local function isRotor(shape)
	local sx, sy, sz = GetShapeSize(shape)
	return sx == 7 and sy == 1 and sz == 7
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Camera Drone", "Дрон с камерой"), "MOD/prefab/tool.xml", 6)
	server.d = {}
	server.bombs = {}
	shared.d = {}
end

local function sd(p)
	local s = shared.d[p]
	if not s then
		s = { body = 0, piloting = false, battery = 1, weak = 0, lost = false, thrust = 0, bombs = 0, yaw = 0,
			crashN = 0, cx = 0, cy = 0, cz = 0, dropN = 0, dx = 0, dy = 0, dz = 0, deployN = 0, packN = 0, grenade = false }
		shared.d[p] = s
	end
	return s
end

function server.tick(dt)
	for p in PlayersAdded() do
		SetToolEnabled(TOOL, true, p)
		sd(p)
	end
	for p in PlayersRemoved() do
		local d = server.d[p]
		if d and IsHandleValid(d.body) then Delete(d.body) end
		server.d[p] = nil
		shared.d[p] = nil
	end
	for p in Players() do
		local d = server.d[p]
		if d and d.piloting and d.s.freeze then
			DisablePlayerInput(p)
		end
	end
end

function server.deploy(p)
	if server.d[p] then return end
	local s = readSettings()
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	local flat = VecNormalize(Vec(fwd[1], 0, fwd[3]))
	local pos = VecAdd(eye.pos, VecAdd(VecScale(flat, 1.2), Vec(0, 0.3, 0)))
	QueryRejectPlayer(p)
	QueryRequire("physical")
	local hit, dist = QueryRaycast(eye.pos, flat, 1.4)
	if hit then pos = VecAdd(eye.pos, VecAdd(VecScale(flat, math.max(0.3, dist - 0.5)), Vec(0, 0.3, 0))) end
	local yaw = math.deg(math.atan2(-flat[1], -flat[3]))
	local ents = Spawn(DRONE_XML, Transform(pos, QuatEuler(0, yaw, 0)))
	local body = 0
	for i = 1, #ents do if GetEntityType(ents[i]) == "body" then body = ents[i] break end end
	if body == 0 then return end
	local shapes = GetBodyShapes(body)
	for i = 1, #shapes do
		if isRotor(shapes[i]) then SetShapeCollisionFilter(shapes[i], 0, 0) end
	end
	SetTag(body, "camera_drone")
	server.d[p] = {
		body = body, piloting = true, input = { f = 0, s = 0, u = 0 }, yaw = yaw, battery = 1,
		bombs = s.bombs, prevVel = Vec(0, 0, 0), s = s, age = 0, lowWarned = false,
	}
	local st = sd(p)
	st.body = body
	st.piloting = true
	st.battery = 1
	st.bombs = s.bombs
	st.yaw = yaw
	st.grenade = s.grenade and GetBool(REQ .. "available")
	st.deployN = st.deployN + 1
end

function server.setPiloting(p, on)
	local d = server.d[p]
	if not d then
		if on then server.deploy(p) end
		return
	end
	d.piloting = on
	if not on then d.input = { f = 0, s = 0, u = 0 } end
	sd(p).piloting = on
end

function server.droneInput(p, f, s, u, yaw)
	local d = server.d[p]
	if not d or not d.piloting then return end
	d.input.f = clamp(f, -1, 1)
	d.input.s = clamp(s, -1, 1)
	d.input.u = clamp(u, -1, 1)
	d.yaw = yaw
end

function server.pack(p)
	local d = server.d[p]
	if not d then return end
	if IsHandleValid(d.body) then
		local dist = VecLength(VecSub(GetBodyTransform(d.body).pos, GetPlayerTransform(p).pos))
		if dist > PACK_DIST then return end
		Delete(d.body)
	end
	server.d[p] = nil
	local st = sd(p)
	st.body = 0
	st.piloting = false
	st.packN = st.packN + 1
end

function server.drop(p)
	local d = server.d[p]
	if not d or not d.piloting or d.bombs <= 0 or not IsHandleValid(d.body) then return end
	local bt = GetBodyTransform(d.body)
	local pos = VecAdd(bt.pos, Vec(0, -0.35, 0))
	local vel = GetBodyVelocity(d.body)
	d.bombs = d.bombs - 1
	local st = sd(p)
	st.bombs = d.bombs
	st.dropN = st.dropN + 1
	st.dx, st.dy, st.dz = pos[1], pos[2], pos[3]
	if d.s.grenade and GetBool(REQ .. "available") then
		-- hand the drop to the Singularity Grenade mod through the registry
		local n = GetInt(REQ .. "reqcount") + 1
		local k = REQ .. "req." .. n
		SetFloat(k .. ".x", pos[1])
		SetFloat(k .. ".y", pos[2])
		SetFloat(k .. ".z", pos[3])
		SetFloat(k .. ".vx", vel[1])
		SetFloat(k .. ".vy", vel[2])
		SetFloat(k .. ".vz", vel[3])
		SetInt(k .. ".owner", p)
		SetInt(REQ .. "reqcount", n)
	else
		local ents = Spawn(BOMB_XML, Transform(pos))
		for i = 1, #ents do
			if GetEntityType(ents[i]) == "body" then
				SetBodyVelocity(ents[i], vel)
				server.bombs[#server.bombs + 1] = { body = ents[i], t = 0, prevVel = VecCopy(vel), owner = p, size = d.s.bombSize }
				break
			end
		end
	end
end

function server.crash(p, d, pos)
	if IsHandleValid(d.body) then Delete(d.body) end
	for i = 1, 3 do
		local ents = Spawn(DEBRIS_XML, Transform(VecAdd(pos, GetRandomDirection(0.2)), QuatEuler(rnd(0, 360), rnd(0, 360), 0)))
		for j = 1, #ents do
			if GetEntityType(ents[j]) == "body" then
				SetBodyVelocity(ents[j], VecAdd(GetRandomDirection(rnd(2, 5)), Vec(0, 2, 0)))
			end
		end
	end
	server.d[p] = nil
	local st = sd(p)
	st.body = 0
	st.piloting = false
	st.crashN = st.crashN + 1
	st.cx, st.cy, st.cz = pos[1], pos[2], pos[3]
end

function server.update(dt)
	for p, d in pairs(server.d) do
		if not IsHandleValid(d.body) then
			server.d[p] = nil
			local st = sd(p)
			st.body = 0
			st.piloting = false
		else
			server.fly(p, d, dt)
		end
	end
	server.updateBombs(dt)
end

function server.fly(p, d, dt)
	local s = d.s
	local st = sd(p)
	d.age = d.age + dt
	local bt = GetBodyTransform(d.body)
	local vel = GetBodyVelocity(d.body)
	local mass = math.max(GetBodyMass(d.body), 0.5)

	-- crash: sudden change of velocity that our own control could not cause
	local dv = VecLength(VecSub(vel, d.prevVel))
	if d.age > 0.5 and dv > s.crash then
		server.crash(p, d, bt.pos)
		return
	end

	-- signal
	local dist = VecLength(VecSub(bt.pos, GetPlayerTransform(p).pos))
	local weak = clamp((dist - 0.75 * s.range) / (0.25 * s.range), 0, 1)
	local lost = dist > s.range
	st.weak = weak
	st.lost = lost

	-- battery
	local motors = true
	if s.battery then
		d.battery = math.max(0, d.battery - dt / (s.minutes * 60) * (0.7 + 0.6 * (st.thrust or 0)))
		if d.battery <= 0 then motors = false end
	end
	st.battery = d.battery

	local inp = d.input
	if lost or not d.piloting then inp = { f = 0, s = 0, u = 0 } end
	local fwd, right = yawFrame(d.yaw)
	local desired = VecAdd(VecScale(fwd, inp.f * s.speed), VecScale(right, inp.s * s.speed))
	local vy = inp.u * CLIMB
	if lost then vy = -0.6 end
	desired = Vec(desired[1], vy, desired[3])

	local acc = Vec(0, 0, 0)
	if motors then
		local k = math.min(1, 3 * dt)
		acc = VecAdd(VecScale(VecSub(desired, vel), k / dt), Vec(0, 10, 0))
		local a = VecLength(acc)
		if a > 40 then acc = VecScale(acc, 40 / a) end
		ApplyBodyImpulse(d.body, TransformToParentPoint(bt, GetBodyCenterOfMass(d.body)), VecScale(acc, mass * dt))
		-- keep it upright, facing the camera yaw, tilted into the motion
		local tiltX = -inp.f * 12
		local tiltZ = -inp.s * 12
		ConstrainOrientation(d.body, 0, bt.rot, QuatEuler(tiltX, d.yaw, tiltZ), 4, mass * 3)
	end
	st.thrust = motors and clamp(VecLength(acc) / 20, 0, 1) or 0
	st.yaw = d.yaw
	-- predicted velocity after our impulse, so the crash test ignores our own push
	d.prevVel = VecAdd(VecAdd(vel, VecScale(acc, dt)), Vec(0, -10 * dt, 0))
end

function server.updateBombs(dt)
	for i = #server.bombs, 1, -1 do
		local b = server.bombs[i]
		b.t = b.t + dt
		if not IsHandleValid(b.body) then
			table.remove(server.bombs, i)
		else
			local vel = GetBodyVelocity(b.body)
			local hit = b.t > 0.1 and VecLength(VecSub(vel, b.prevVel)) > 4
			b.prevVel = vel
			if hit or b.t > 6 then
				local pos = GetBodyTransform(b.body).pos
				Delete(b.body)
				Explosion(pos, b.size, b.owner)
				table.remove(server.bombs, i)
			end
		end
	end
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.snd = {}
	for _, n in ipairs({ "crash", "drop", "deploy", "pack", "battery", "signal" }) do
		client.snd[n] = LoadSound("MOD/snd/" .. n .. ".ogg")
	end
	client.hum = LoadLoop("MOD/snd/hum.ogg", 12)
	client.anim = {}
	client.seen = {}
	client.camYaw = 0
	client.camPitch = -10
	client.sent = { f = 0, s = 0, u = 0, yaw = 0, t = 0 }
	client.photo = false
	client.rotorAngle = 0
	client.rotors = {}
	client.blink = 0
	client.lowBeeped = false
	client.weakBeeped = false
	client.wasPiloting = false
end

local function mine()
	return shared.d[GetLocalPlayer()]
end

function client.tick(dt)
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local me = GetLocalPlayer()
	local s = readSettings()
	client.blink = client.blink + dt

	-- events from every drone -> sounds
	for p, st in pairs(shared.d) do
		local seen = client.seen[p]
		if not seen then
			seen = { crashN = st.crashN, dropN = st.dropN, deployN = st.deployN, packN = st.packN }
			client.seen[p] = seen
		end
		if st.crashN ~= seen.crashN then
			seen.crashN = st.crashN
			PlaySound(client.snd.crash, Vec(st.cx, st.cy, st.cz), 1.0)
			client.crashBurst = Vec(st.cx, st.cy, st.cz)
		end
		if st.dropN ~= seen.dropN then
			seen.dropN = st.dropN
			PlaySound(client.snd.drop, Vec(st.dx, st.dy, st.dz), 0.8)
		end
		if st.deployN ~= seen.deployN then
			seen.deployN = st.deployN
			if st.body ~= 0 and IsHandleValid(st.body) then PlaySound(client.snd.deploy, GetBodyTransform(st.body).pos, 0.8) end
		end
		if st.packN ~= seen.packN then
			seen.packN = st.packN
			PlaySound(client.snd.pack, GetPlayerTransform(p).pos, 0.8)
		end
		if st.body ~= 0 and IsHandleValid(st.body) then
			client.animateDrone(st, dt)
		end
	end

	local st = mine()
	local piloting = st and st.piloting and st.body ~= 0 and IsHandleValid(st.body)
	if piloting and not client.wasPiloting then
		client.camYaw = st.yaw
		client.camPitch = -10
		client.lowBeeped = false
	end
	client.wasPiloting = piloting

	if piloting then
		client.pilot(st, s, dt)
	else
		client.photo = false
		if GetPlayerTool() == TOOL and GetPlayerCanUseTool() then
			if InputPressed("usetool") then ServerCall("server.setPiloting", me, true) end
			if InputPressed("r") and st and st.body ~= 0 then ServerCall("server.pack", me) end
		end
	end

	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local a = client.anim[p]
			if not a then a = ToolAnimator() client.anim[p] = a end
			tickToolAnimator(a, dt, nil, p)
		end
	end
end

function client.pilot(st, s, dt)
	local me = GetLocalPlayer()
	local function axis(pos, neg) return (InputDown(pos) and 1 or 0) - (InputDown(neg) and 1 or 0) end
	local f = axis("up", "down")
	local side = axis("right", "left")
	local u = axis("jump", "crouch")
	client.camYaw = client.camYaw - math.deg(InputValue("camerax")) * s.sens
	client.camPitch = clamp(client.camPitch - math.deg(InputValue("cameray")) * s.sens, -85, 35)
	local sent = client.sent
	sent.t = sent.t + dt
	if f ~= sent.f or side ~= sent.s or u ~= sent.u or (math.abs(client.camYaw - sent.yaw) > 0.5 and sent.t > 0.033) then
		ServerCall("server.droneInput", me, f, side, u, client.camYaw)
		sent.f, sent.s, sent.u, sent.yaw, sent.t = f, side, u, client.camYaw, 0
	end
	if InputPressed("usetool") then ServerCall("server.drop", me) end
	if InputPressed("q") then ServerCall("server.setPiloting", me, false) end
	if InputPressed("p") then client.photo = not client.photo end

	-- camera under the nose, stabilised by a gimbal (yaw/pitch only)
	local bt = GetBodyTransform(st.body)
	local fwd = yawFrame(client.camYaw)
	local camPos = VecAdd(bt.pos, VecAdd(Vec(0, -0.15, 0), VecScale(fwd, 0.3)))
	SetCameraTransform(Transform(camPos, QuatEuler(client.camPitch, client.camYaw, 0)), s.fov)

	-- warnings
	if s.battery and st.battery < 0.2 and not client.lowBeeped then
		client.lowBeeped = true
		PlaySound(client.snd.battery, nil, 0.7)
	end
	if st.weak > 0.5 and not client.weakBeeped then
		client.weakBeeped = true
		PlaySound(client.snd.signal, nil, 0.7)
	elseif st.weak < 0.3 then
		client.weakBeeped = false
	end
end

function client.animateDrone(st, dt)
	local b = st.body
	local bt = GetBodyTransform(b)
	PlayLoop(client.hum, bt.pos, 0.3 + 0.5 * st.thrust, true, 0.8 + 0.6 * st.thrust)
	PointLight(VecAdd(bt.pos, Vec(0, -0.3, 0)), 1, 0.95, 0.85, 0.6)
	local r = client.rotors[b]
	if not r then
		r = { shapes = {} }
		local shapes = GetBodyShapes(b)
		for i = 1, #shapes do
			if isRotor(shapes[i]) then
				local sx, sy, sz, vs = GetShapeSize(shapes[i])
				r.shapes[#r.shapes + 1] = { shape = shapes[i], t0 = GetShapeLocalTransform(shapes[i]), center = Vec(sx * vs * 0.5, 0, sz * vs * 0.5) }
			else
				r.body = shapes[i]
			end
		end
		client.rotors[b] = r
	end
	client.rotorAngle = client.rotorAngle + dt * (900 + 1500 * st.thrust)
	for i = 1, #r.shapes do
		local e = r.shapes[i]
		local dir = (i % 2 == 0) and 1 or -1
		local pivot = Transform(e.center, QuatAxisAngle(Vec(0, 1, 0), client.rotorAngle * dir))
		SetShapeLocalTransform(e.shape, TransformToParentTransform(e.t0, TransformToParentTransform(pivot, Transform(VecScale(e.center, -1)))))
	end
	if r.body then
		SetShapeEmissiveScale(r.body, (math.floor(client.blink * 2) % 2 == 0) and 1.2 or 0.3)
	end
end

-- crash sparks, at a fixed rate
function client.update(dt)
	if client.crashBurst then
		local p = client.crashBurst
		client.crashBurst = nil
		ParticleReset()
		ParticleType("plain")
		ParticleColor(1, 0.7, 0.3, 1, 0.3, 0.1)
		ParticleRadius(0.03, 0.01)
		ParticleGravity(-10)
		ParticleEmissive(6, 0)
		ParticleCollide(1)
		for i = 1, 30 do SpawnParticle(p, VecAdd(GetRandomDirection(rnd(2, 6)), Vec(0, 2, 0)), rnd(0.4, 1.0)) end
		ParticleReset()
		ParticleType("smoke")
		ParticleColor(0.2, 0.2, 0.2)
		ParticleRadius(0.2, 0.6)
		ParticleAlpha(0.6, 0)
		for i = 1, 8 do SpawnParticle(p, GetRandomDirection(1), rnd(1, 2)) end
	end
end

function client.render(dt)
	local st = mine()
	if not st or not st.piloting or st.body == 0 or not IsHandleValid(st.body) then return end
	if client.photo then return end
	-- target marker: where a bomb released now would land
	local bt = GetBodyTransform(st.body)
	local vel = GetBodyVelocity(st.body)
	QueryRejectBody(st.body)
	QueryRequire("physical")
	local hit, h = QueryRaycast(bt.pos, Vec(0, -1, 0), 200)
	if not hit then return end
	local t = math.sqrt(2 * h / 10)
	local p = VecAdd(bt.pos, Vec(vel[1] * t, 0, vel[3] * t))
	QueryRejectBody(st.body)
	QueryRequire("physical")
	local hit2, h2 = QueryRaycast(p, Vec(0, -1, 0), 200)
	if hit2 then p = VecAdd(p, Vec(0, -h2 + 0.05, 0)) else p = VecAdd(bt.pos, Vec(0, -h + 0.05, 0)) end
	local r, g, b = 0.3, 1, 0.4
	if st.bombs <= 0 then r, g, b = 0.6, 0.6, 0.6 end
	local n = 24
	local rad = 0.6 + 0.04 * h
	for i = 0, n - 1 do
		local a0, a1 = i / n * 6.2832, (i + 1) / n * 6.2832
		DrawLine(VecAdd(p, Vec(math.cos(a0) * rad, 0, math.sin(a0) * rad)), VecAdd(p, Vec(math.cos(a1) * rad, 0, math.sin(a1) * rad)), r, g, b, 0.9)
	end
	DrawLine(VecAdd(p, Vec(-rad * 0.4, 0, 0)), VecAdd(p, Vec(rad * 0.4, 0, 0)), r, g, b, 0.9)
	DrawLine(VecAdd(p, Vec(0, 0, -rad * 0.4)), VecAdd(p, Vec(0, 0, rad * 0.4)), r, g, b, 0.9)
end

local function staticNoise(amount)
	UiPush()
		UiColor(0, 0, 0, 0.35 * amount)
		UiRect(UiWidth(), UiHeight())
		local n = math.floor(160 * amount)
		for i = 1, n do
			UiPush()
				UiTranslate(math.random() * UiWidth(), math.random() * UiHeight())
				local c = math.random()
				UiColor(c, c, c, 0.5 + 0.5 * amount)
				UiRect(math.random(2, 60), math.random(1, 4))
			UiPop()
		end
		for y = 0, UiHeight(), 6 do
			UiPush()
				UiTranslate(0, y)
				UiColor(0, 0, 0, 0.15 * amount)
				UiRect(UiWidth(), 2)
			UiPop()
		end
	UiPop()
end

function client.draw(dt)
	local st = mine()
	local piloting = st and st.piloting and st.body ~= 0 and IsHandleValid(st.body)
	if piloting then
		if not client.photo then
			local amount = st.weak
			if st.lost then amount = 1 end
			if amount > 0.02 then
				staticNoise(amount)
				UiSoundLoop("MOD/snd/static.ogg", 0.6 * amount, 1.0)
			end
			client.drawHud(st)
		end
		return
	end
	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or not GetPlayerCanUseTool() then return end
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 160)
		UiAlign("center middle")
		UiTextShadow(0, 0, 0, 0.6, 1.5)
		UiFont("regular.ttf", 22)
		UiColor(1, 1, 1, 0.9)
		if st and st.body ~= 0 then
			UiText(tr("LMB: take control of the drone    R (next to it): pack up", "ЛКМ: управлять дроном    R (рядом): сложить"))
		else
			UiText(tr("LMB: launch the drone", "ЛКМ: запустить дрон"))
		end
	UiPop()
end

function client.drawHud(st)
	local s = readSettings()
	local bt = GetBodyTransform(st.body)
	local vel = GetBodyVelocity(st.body)
	QueryRejectBody(st.body)
	QueryRequire("physical")
	local hit, alt = QueryRaycast(bt.pos, Vec(0, -1, 0), 300)
	if not hit then alt = 300 end
	UiPush()
		-- corner brackets
		UiColor(1, 1, 1, 0.6)
		local w, h = UiWidth(), UiHeight()
		for _, c in ipairs({ { 60, 60, 1, 1 }, { w - 60, 60, -1, 1 }, { 60, h - 60, 1, -1 }, { w - 60, h - 60, -1, -1 } }) do
			UiPush() UiTranslate(c[1], c[2]) UiAlign(c[3] > 0 and "left" or "right") UiRect(60, 3) UiPop()
			UiPush() UiTranslate(c[1], c[2]) UiAlign((c[4] > 0 and "top" or "bottom") .. (c[3] > 0 and " left" or " right")) UiRect(3, 60) UiPop()
		end
		-- crosshair
		UiPush() UiTranslate(w / 2, h / 2) UiAlign("center middle") UiRect(24, 2) UiRect(2, 24) UiPop()
		-- REC dot
		UiPush()
			UiTranslate(90, 100)
			UiAlign("left middle")
			if math.floor(client.blink * 2) % 2 == 0 then UiColor(1, 0.2, 0.2, 1) UiCircle(8) end
			UiTranslate(20, 0)
			UiFont("bold.ttf", 22)
			UiColor(1, 1, 1, 0.9)
			UiText("CAM")
		UiPop()
		-- telemetry
		UiPush()
			UiTranslate(w - 100, 100)
			UiAlign("right middle")
			UiFont("bold.ttf", 22)
			UiColor(1, 1, 1, 0.9)
			if s.battery then
				local b = st.battery
				if b < 0.2 then UiColor(1, 0.3, 0.25, 1) end
				UiText(string.format(tr("BAT %d%%", "БАТ %d%%"), math.floor(b * 100 + 0.5)))
				UiTranslate(0, 28)
				UiColor(1, 1, 1, 0.9)
			end
			local bars = math.floor((1 - st.weak) * 4 + 0.5)
			if st.lost then bars = 0 end
			UiText(tr("SIGNAL ", "СИГНАЛ ") .. string.rep("|", bars) .. string.rep(".", 4 - bars))
			UiTranslate(0, 28)
			UiText(string.format(tr("ALT %.1f m", "ВЫС %.1f м"), alt))
			UiTranslate(0, 28)
			UiText(string.format(tr("SPD %.1f m/s", "СКР %.1f м/с"), VecLength(vel)))
			UiTranslate(0, 28)
			local kind = st.grenade and tr("singularity", "сингулярность") or tr("bomb", "бомба")
			UiText(string.format(tr("BOMBS %d (%s)", "БОМБЫ %d (%s)"), st.bombs, kind))
		UiPop()
		if st.lost then
			UiPush()
				UiTranslate(w / 2, h / 2 - 80)
				UiAlign("center middle")
				UiFont("bold.ttf", 40)
				UiColor(1, 0.3, 0.25, 1)
				UiText(tr("SIGNAL LOST", "НЕТ СИГНАЛА"))
			UiPop()
		end
		UiPush()
			UiTranslate(w / 2, h - 70)
			UiAlign("center middle")
			UiFont("regular.ttf", 18)
			UiColor(1, 1, 1, 0.75)
			UiText(tr("WASD move  Space/Ctrl up/down  Mouse look  LMB drop  Q back to body  P photo mode",
				"WASD полёт  Пробел/Ctrl вверх/вниз  Мышь обзор  ЛКМ сброс  Q к телу  P фоторежим"))
		UiPop()
	UiPop()
end
