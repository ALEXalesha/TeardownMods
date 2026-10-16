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
-- Client: camera, HUD, static, marker, sounds, rotor blur discs. Sends the
--         view yaw and its key state with ServerCall.
-- Server: drone bodies, flight, battery, range, crash, bombs. Movement keys are
--         also read here with the player id, the way the game's own turret
--         does (data/level/carib/script/turret.lua), so either path works.
--
-- Flight sets the body velocity directly every physics step (with this step's
-- gravity cancelled) and steers the orientation through the angular velocity:
-- exact at any mass and frame rate. The pilot's body is held in place by
-- position, not by DisablePlayerInput, which swallows that player's input for
-- server-side readers. Rotor shapes are never moved on the flying body; the
-- spinning blur is drawn by the client.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "drone"
local DRONE_XML = "<body dynamic='true'><vox file='MOD/vox/drone.vox' scale='0.5'/></body>"
local BOMB_XML = "<body dynamic='true'><vox file='MOD/vox/bomb.vox' scale='0.5'/></body>"
local DEBRIS_XML = "<body dynamic='true'><voxbox size='3 1 2'/></body>"
local REQ = "level.singularity_grenade."
local CLIMB = 4.0
local PACK_DIST = 4.0
local RESPONSE = 5.0      -- 1/s, how fast the velocity follows the sticks
local MAX_ACC = 30        -- m/s^2
local TURN_GAIN = 8       -- 1/s, orientation error -> angular velocity
local MAX_TURN = 6        -- rad/s

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
		debug = getB("debugline", false),   -- new key: old saves may hold debug = true
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

-- world space angular velocity that turns rotation `cur` into `target`
local function turnTowards(cur, target, gain, maxw)
	local q = QuatRotateQuat(target, Quat(-cur[1], -cur[2], -cur[3], cur[4]))
	local x, y, z, w = q[1], q[2], q[3], q[4]
	if w < 0 then x, y, z, w = -x, -y, -z, -w end
	local sn = math.sqrt(x * x + y * y + z * z)
	if sn < 1e-6 then return Vec(0, 0, 0) end
	local m = math.min(2 * math.atan2(sn, w) * gain, maxw)
	return Vec(x / sn * m, y / sn * m, z / sn * m)
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
		-- another tool or death ends piloting (and the pin)
		if d and d.piloting and (GetPlayerTool(p) ~= TOOL or GetPlayerHealth(p) <= 0) then server.setPiloting(p, false) end
		if d and d.piloting and d.s.freeze and d.pin then
			-- hold the pilot's body where it stood; DisablePlayerInput would also swallow the keys
			SetPlayerTransform(d.pin, p)
			SetPlayerVelocity(Vec(0, 0, 0), p)
		end
	end
end

function server.deploy(p)
	if server.d[p] then return end
	local s = readSettings()
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	local flat = VecNormalize(Vec(fwd[1], 0, fwd[3]))
	local pos = VecAdd(eye.pos, VecAdd(VecScale(flat, 2.5), Vec(0, 0.5, 0)))
	QueryRejectPlayer(p)
	QueryRequire("physical")
	local hit, dist = QueryRaycast(eye.pos, flat, 2.7)
	if hit then pos = VecAdd(eye.pos, VecAdd(VecScale(flat, math.max(0.3, dist - 0.5)), Vec(0, 0.3, 0))) end
	local yaw = math.deg(math.atan2(-flat[1], -flat[3]))
	local ents = Spawn(DRONE_XML, Transform(pos, QuatEuler(0, yaw, 0)))
	local body = 0
	for i = 1, #ents do if GetEntityType(ents[i]) == "body" then body = ents[i] break end end
	if body == 0 then return end
	local shapes = GetBodyShapes(body)
	local hull = 0
	for i = 1, #shapes do
		if isRotor(shapes[i]) then
			SetShapeCollisionFilter(shapes[i], 0, 0)
		elseif hull == 0 then
			hull = shapes[i]
		end
	end
	SetTag(body, "camera_drone")
	server.d[p] = {
		body = body, piloting = true, input = { f = 0, s = 0, u = 0 }, yaw = yaw, battery = 1,
		bombs = s.bombs, expect = nil, s = s, age = 0, lowWarned = false,
		hull = hull, ledOn = nil, pin = GetPlayerTransform(p),
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
	if on then d.pin = GetPlayerTransform(p) else d.input = { f = 0, s = 0, u = 0 } d.pin = nil end
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
	if GetPlayerTool(p) ~= TOOL then return end
	local bt = GetBodyTransform(d.body)
	local pos = VecAdd(bt.pos, Vec(0, -0.35, 0))
	local vel = (d.mode == "kinematic") and VecCopy(d.kvel) or GetBodyVelocity(d.body)
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

-- movement keys: what the client sent, or read here with the player id
local function sticks(p, d)
	local function axis(a, b) return (InputDown(a, p) and 1 or 0) - (InputDown(b, p) and 1 or 0) end
	local function pick(client, server) if client ~= 0 then return client end return server end
	return pick(d.input.f, axis("up", "down")), pick(d.input.s, axis("right", "left")), pick(d.input.u, axis("jump", "crouch"))
end

function server.fly(p, d, dt)
	local s = d.s
	local st = sd(p)
	d.age = d.age + dt
	local bt = GetBodyTransform(d.body)
	local vel = GetBodyVelocity(d.body)
	local g = GetGravity()
	-- how the body really moved since the last step. GetBodyVelocity is not enough: on a body that is
	-- not simulated it reads back what we set, while the body stands still (in-game 16.10 23:13)
	local moved = (d.prevPos and dt > 0) and VecScale(VecSub(bt.pos, d.prevPos), 1 / dt) or vel
	d.prevPos = VecCopy(bt.pos)

	-- crash: the velocity is not what our controller left it at (something hit us)
	if d.mode == "kinematic" then
		if server.flyKinematic(p, d, dt, st, s) ~= "velocity" then return end
	end
	if d.expect and d.age > 1.5 and VecLength(VecSub(vel, d.expect)) > s.crash then
		st.lastCrash = string.format("dv %.1f", VecLength(VecSub(vel, d.expect)))
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

	local f, side, u = 0, 0, 0
	if d.piloting and not lost then f, side, u = sticks(p, d) end
	server.debugInput(p, d, st)
	local fwd, right = yawFrame(d.yaw)
	local desired = VecAdd(VecScale(fwd, f * s.speed), VecScale(right, side * s.speed))
	desired = Vec(desired[1], lost and -0.6 or u * CLIMB, desired[3])

	-- fallback that cannot fail: if the body does not follow our velocity (input held but no
	-- progress, or sinking with no input) for half a second, fly it kinematically instead
	if u ~= 0 or lost or not d.refY then d.refY = bt.pos[2] end
	-- not when lost (planned descent) or going down (the ground stops it)
	if motors and d.age > 0.3 and not lost and desired[2] >= 0 then
		local want = VecLength(desired)
		local stuck
		if want > 1 then
			local dir = VecScale(desired, 1 / want)
			stuck = VecDot(moved, dir) < 0.3 * want
			if stuck then
				-- something in the way (a wall) is not "stuck"
				QueryRejectBody(d.body)
				QueryRequire("physical")
				if QueryRaycast(bt.pos, dir, 1.5) then stuck = false end
			end
		else
			stuck = bt.pos[2] < d.refY - 0.4        -- losing height with nothing pressed
		end
		if stuck and not d.stuckT then d.stuckFrom = VecCopy(bt.pos) end
		d.stuckT = stuck and (d.stuckT or 0) + dt or nil
		if d.stuckT and d.stuckT >= ((want > 1) and 0.5 or 0.25) then
			-- back to where it got stuck (its hover height), then fly kinematically
			server.goKinematic(d, st, Transform(Vec(bt.pos[1], math.max(bt.pos[2], d.refY), bt.pos[3]), bt.rot))
			server.flyKinematic(p, d, dt, st, s)
			return
		end
	else
		d.stuckT = nil
	end

	if motors then
		-- velocity follows the sticks with a first-order response, limited acceleration,
		-- and this step's gravity cancelled so the drone holds its altitude exactly
		local change = VecScale(VecSub(desired, vel), 1 - math.exp(-RESPONSE * dt))
		local cl = VecLength(change)
		if cl > MAX_ACC * dt then change = VecScale(change, MAX_ACC * dt / cl) end
		local nv = VecSub(VecAdd(vel, change), VecScale(g, dt))
		SetBodyVelocity(d.body, nv)
		d.expect = VecAdd(nv, VecScale(g, dt))
		-- upright, facing the view, tilted into the motion
		local target = QuatEuler(-f * 12, d.yaw, -side * 12)
		SetBodyAngularVelocity(d.body, turnTowards(bt.rot, target, TURN_GAIN, MAX_TURN))
		st.thrust = clamp(0.35 + cl / (MAX_ACC * dt) * 0.65, 0, 1)
	else
		-- motors off: free fall, so a hard landing still breaks it
		d.expect = VecAdd(vel, VecScale(g, dt))
		st.thrust = 0
	end
	st.yaw = d.yaw
	st.speed = VecLength(vel)
	server.animate(d, st, dt)
end

-- what the server sees of the pilot's keys, for the debug line
function server.debugInput(p, d, st)
	local function k(name, label) return InputDown(name, p) and label or nil end
	local keys = {}
	for _, kv in ipairs({ { "up", "W" }, { "down", "S" }, { "left", "A" }, { "right", "D" }, { "jump", "Space" }, { "crouch", "Ctrl" } }) do
		local l = k(kv[1], kv[2])
		if l then keys[#keys + 1] = l end
	end
	st.srvKeys = table.concat(keys, " ")
	local c = {}
	if d.input.f > 0 then c[#c + 1] = "W" elseif d.input.f < 0 then c[#c + 1] = "S" end
	if d.input.s > 0 then c[#c + 1] = "D" elseif d.input.s < 0 then c[#c + 1] = "A" end
	if d.input.u > 0 then c[#c + 1] = "Space" elseif d.input.u < 0 then c[#c + 1] = "Ctrl" end
	st.callKeys = table.concat(c, " ")
	st.mode = d.mode or "velocity"
end

function server.goKinematic(d, st, bt)
	d.mode = "kinematic"
	st.mode = "kinematic"
	d.kpos = VecCopy(bt.pos)
	d.kvel = Vec(0, 0, 0)
	d.kinN = (d.kinN or 0) + 1
	d.kinT = 0
	d.trial = nil
	d.prevPos = nil
	SetBodyDynamic(d.body, false)
end

-- a test step succeeded: the engine follows our velocity again
function server.goVelocity(d, st, bt)
	d.mode = nil
	st.mode = "velocity"
	d.expect = nil
	d.stuckT = nil
	d.refY = bt.pos[2]
	d.prevPos = VecCopy(bt.pos)
end

-- kinematic flight: the body is static and moved every physics step; it stops at walls
function server.flyKinematic(p, d, dt, st, s)
	if d.trial then
		-- last step was a velocity test: did the body really MOVE with the velocity we set? (in-game 16.10
		-- 23:13 "the drone stopped reacting to the keys": a body made static and then dynamic again is not
		-- simulated, GetBodyVelocity read the test velocity back, the test passed and the drone stood still
		-- in velocity mode for good)
		local moved = VecScale(VecSub(GetBodyTransform(d.body).pos, d.trialFrom), 1 / math.max(d.trialDt, 1e-4))
		local ok = VecLength(VecSub(moved, d.trial)) < 0.3 and VecLength(VecSub(GetBodyVelocity(d.body), d.trial)) < 0.3
		d.trial = nil
		if ok then
			server.goVelocity(d, st, GetBodyTransform(d.body))
			return "velocity"
		end
		SetBodyDynamic(d.body, false)
	end
	local f, side, u = 0, 0, 0
	local dist = VecLength(VecSub(d.kpos, GetPlayerTransform(p).pos))
	local lost = dist > s.range
	st.weak = clamp((dist - 0.75 * s.range) / (0.25 * s.range), 0, 1)
	st.lost = lost
	if s.battery then
		d.battery = math.max(0, d.battery - dt / (s.minutes * 60))
		st.battery = d.battery
	end
	local motors = not s.battery or d.battery > 0
	if d.piloting and not lost and motors then f, side, u = sticks(p, d) end
	server.debugInput(p, d, st)
	local fwd, right = yawFrame(d.yaw)
	local desired = VecAdd(VecScale(fwd, f * s.speed), VecScale(right, side * s.speed))
	desired = Vec(desired[1], (lost or not motors) and -2 or u * CLIMB, desired[3])
	local k = (VecLength(desired) < 0.1) and 15 or RESPONSE       -- brake crisply when the sticks are released
	d.kvel = VecAdd(d.kvel, VecScale(VecSub(desired, d.kvel), 1 - math.exp(-k * dt)))
	local step = VecScale(d.kvel, dt)
	local sl = VecLength(step)
	if sl > 1e-4 then
		QueryRejectBody(d.body)
		QueryRequire("physical")
		local hit, hd = QueryRaycast(d.kpos, VecScale(step, 1 / sl), sl + 0.6)
		if hit then
			step = VecScale(step, math.max(0, hd - 0.6) / sl)
			d.kvel = Vec(0, 0, 0)
		end
	end
	d.kpos = VecAdd(d.kpos, step)
	SetBodyTransform(d.body, Transform(d.kpos, QuatEuler(-f * 12, d.yaw, -side * 12)))
	-- now and then try one physics step with a test velocity (less often after each relapse)
	d.kinT = (d.kinT or 0) + dt
	if motors and not lost and d.kinT >= math.min(60, 3 * 2 ^ ((d.kinN or 1) - 1)) then
		d.kinT = 0
		d.trial = VecAdd(d.kvel, Vec(0, 0.5, 0))
		d.trialFrom = VecCopy(d.kpos)
		d.trialDt = dt
		SetBodyDynamic(d.body, true)
		SetBodyActive(d.body, true)         -- back into the simulation (a static body was taken out of it)
		SetBodyVelocity(d.body, VecSub(d.trial, VecScale(GetGravity(), dt)))
	end
	st.thrust = motors and clamp(0.35 + VecLength(d.kvel) / s.speed * 0.65, 0, 1) or 0
	st.speed = VecLength(d.kvel)
	st.yaw = d.yaw
	server.animate(d, st, dt)
end

-- LED blink. The drone body is spawned by the server, so in #version 2 only server
-- code may change its shapes; the rotor blur is drawn by the client.
function server.animate(d, st, dt)
	local on = math.floor(d.age * 2) % 2 == 0
	if d.hull ~= 0 and on ~= d.ledOn and IsHandleValid(d.hull) then
		d.ledOn = on
		SetShapeEmissiveScale(d.hull, on and 1.2 or 0.3)
	end
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
	client.blur = LoadSprite("MOD/ui/rotor.png")
	client.anim = {}
	client.seen = {}
	client.camYaw = 0
	client.camPitch = -10
	client.sent = { f = 0, s = 0, u = 0, yaw = 0, t = 0 }
	client.photo = false
	client.blink = 0
	client.lowBeeped = false
	client.weakBeeped = false
	client.wasPiloting = false
end

local function mine()
	return shared.d[GetLocalPlayer()]
end

-- this client flies the drone: holding the drone tool and alive
local function pilotingNow(st)
	return st and st.piloting and st.body ~= 0 and IsHandleValid(st.body) and GetPlayerTool() == TOOL and GetPlayerHealth() > 0
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
	local piloting = pilotingNow(st)
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
	local keys = {}
	for _, kv in ipairs({ { "up", "W" }, { "down", "S" }, { "left", "A" }, { "right", "D" }, { "jump", "Space" }, { "crouch", "Ctrl" } }) do
		if InputDown(kv[1]) then keys[#keys + 1] = kv[2] end
	end
	client.cliKeys = table.concat(keys, " ")
	client.camYaw = client.camYaw - math.deg(InputValue("camerax")) * s.sens
	client.camPitch = clamp(client.camPitch - math.deg(InputValue("cameray")) * s.sens, -85, 35)
	local sent = client.sent
	sent.t = sent.t + dt
	if f ~= sent.f or side ~= sent.s or u ~= sent.u or math.abs(client.camYaw - sent.yaw) > 0.2 or sent.t > 0.25 then
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
	-- sound and light; the spinning rotor blur is drawn in client.render
	local bt = GetBodyTransform(st.body)
	PlayLoop(client.hum, bt.pos, 0.3 + 0.5 * st.thrust, true, 0.8 + 0.6 * st.thrust)
	PointLight(VecAdd(bt.pos, Vec(0, -0.3, 0)), 1, 0.95, 0.85, 0.6)
end

-- translucent spinning discs over the rotor shapes (reading shapes is allowed on the client)
function client.drawRotors(st)
	local shapes = GetBodyShapes(st.body)
	local spin = client.blink * (20 + 25 * st.thrust)
	for i = 1, #shapes do
		local sh = shapes[i]
		if isRotor(sh) then
			local sx, sy, sz, vs = GetShapeSize(sh)
			local wt = GetShapeWorldTransform(sh)
			local c = TransformToParentPoint(wt, Vec(sx * vs * 0.5, sy * vs * 0.5, sz * vs * 0.5))
			local dir = (i % 2 == 0) and 1 or -1
			local rot = QuatRotateQuat(wt.rot, QuatRotateQuat(QuatEuler(0, spin * dir * 57.3, 0), QuatEuler(90, 0, 0)))
			local size = sx * vs * 1.15
			DrawSprite(client.blur, Transform(c, rot), size, size, 0.85, 0.85, 0.85, 0.55, true, false)
		end
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
	for p, other in pairs(shared.d) do
		if other.body ~= 0 and IsHandleValid(other.body) then client.drawRotors(other) end
	end
	local st = mine()
	if not pilotingNow(st) then return end
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
	local piloting = pilotingNow(st)
	if piloting then
		if not client.photo then
			local amount = st.weak
			if st.lost then amount = 1 end
			if amount > 0.02 then
				staticNoise(amount)
				UiSoundLoop("MOD/snd/static.ogg", 0.6 * amount, 1.0)
			end
			client.drawHud(st)
			client.drawDebug(st, true)
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

-- one small line for in-game diagnosis (setting "Debug line", off by default, hidden in photo mode)
function client.drawDebug(st, piloting)
	if not readSettings().debug or not st then return end
	local line = string.format("drone: mode %s | client %s | server %s | sent %s | speed %.1f m/s | camera %s | crashes %d%s",
		st.mode or "velocity", (client.cliKeys and client.cliKeys ~= "") and client.cliKeys or "-",
		(st.srvKeys and st.srvKeys ~= "") and st.srvKeys or "-", (st.callKeys and st.callKeys ~= "") and st.callKeys or "-",
		st.speed or 0, piloting and "drone" or "player", st.crashN or 0, st.lastCrash and (" (" .. st.lastCrash .. ")") or "")
	UiPush()
		UiTranslate(20, UiHeight() - 24)
		UiAlign("left middle")
		UiFont("regular.ttf", 16)
		UiTextShadow(0, 0, 0, 0.8, 1)
		UiColor(1, 1, 0.6, 0.95)
		UiText(line)
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
