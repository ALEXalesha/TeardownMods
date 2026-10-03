#version 2
-- Catapult / Катапульта
-- A giant wooden trebuchet you place in front of you. Its frame is real, destructible voxels;
-- its arm hangs on a real hinge joint and is swung by the joint's motor. Whatever lies in the
-- bucket is thrown: a boulder, an explosive barrel, a car, a pile of crates, the player.
--
--   LMB             place a catapult in front of you (up to 4)
--   F, or E on it   fire
--   mouse wheel     power
--   Z / C           turn left / right          X / V   lower / raise the angle
--   1 2 3 4         load a boulder / barrel / car / crates      RMB  load the selected ammo
--   R               remove all catapults and their ammo
--
-- How a throw works: the motor swings the arm; when the bucket's motion points along the set
-- angle (arm 90 - angle degrees above the horizontal, behind the axle) everything in the bucket
-- is released with exactly the planned speed (14-56 m/s by power), so range and the arc preview
-- agree; if the motor does not reach the angle in time, the release happens anyway. While the
-- arm swings the load is held to the bucket (ConstrainPosition; players by position), so it
-- cannot fall out early or stick afterwards; the arm brakes right after the release.
-- Impacts punch holes scaled by speed and material (brick from 25 m/s, hard materials from
-- 45 m/s), boulders punch through, barrels explode.
--
-- Server: catapult bodies, motor, loading, release, impacts, limits. Client: input, arc
-- preview, HUD, sounds, particles.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "catapult"
local MAX_CATAPULTS = 4
local MAX_AMMO = 24              -- ammo bodies spawned by the mod, alive at once
local MAX_CARS = 3
local MAX_FLYING = 24
local HOLES_PER_UPDATE = 8
local V_MIN, V_MAX = 14, 56      -- launch speed at power 0 / 1 (m/s)
local SWING = 5                  -- rad/s, arm motor speed while firing
local REST = 55                  -- arm angle below the horizontal at rest (degrees)
local AXY = 9.6                  -- axle height (m)
local L1, L2 = 10, 3.4           -- pivot to bucket / to counterweight (m)
local SCALE = 3
local AMMO = { "boulder", "barrel", "car", "crates" }
local AMMO_K = { boulder = 1.0, barrel = 0.7, car = 0.85, crates = 0.5, other = 0.7 }

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function rnd(a, b) return a + (b - a) * math.random() end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getI(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetInt(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end
local function fmt3(v) return string.format("%.3f %.3f %.3f", v[1], v[2], v[3]) end

function readSettings()
	return {
		ammo = math.floor(clamp(getI("ammo", 1), 1, 4)),
		reload = getB("reload", true),
		damage = clamp(getF("damage", 1), 0.25, 2),
		falldamage = getB("falldamage", false),
		arc = getB("arc", true),
	}
end

function launchSpeed(power) return V_MIN + (V_MAX - V_MIN) * clamp(power, 0, 1) end

-- the prefab: a static frame with the axle, and the arm (hub with the hinge, beam, bucket,
-- counterweight) in its rest pose. Positions assume the game's vox pivot (centre of the bottom
-- face); the geometry used for aiming is measured from the real shapes afterwards.
local function prefab()
	local a = math.rad(REST)
	local u = Vec(0, -math.sin(a), math.cos(a))            -- along the arm towards the bucket (back, down)
	local P = Vec(0, AXY, 0)
	local beamC = VecAdd(P, VecScale(u, (L1 - L2) / 2))
	local beamPos = VecSub(beamC, Vec(0, 0.3 * math.cos(a), 0.3 * math.sin(a)))
	local T = VecAdd(P, VecScale(u, L1))
	local W = VecSub(P, VecScale(u, L2))
	local weightPos = VecSub(W, Vec(0, 1.2 * math.cos(a), 1.2 * math.sin(a)))
	return "<body dynamic='false' tags='catapult interact=Fire'>" ..
		"<vox file='MOD/vox/frame.vox' scale='" .. SCALE .. "' pos='0 0 0'/>" ..
		"<vox file='MOD/vox/axle.vox' scale='" .. SCALE .. "' pos='0 " .. (AXY - 0.6) .. " 0'/>" ..
		"</body>" ..
		"<body dynamic='true' tags='catapult_arm interact=Fire'>" ..
		"<vox file='MOD/vox/hub.vox' scale='" .. SCALE .. "' pos='0 " .. (AXY - 0.6) .. " 0'>" ..
		"<joint pos='0 0.6 0' rot='0 90 0' type='hinge' size='0.5' rotstrength='0' rotspring='0'/></vox>" ..
		"<vox file='MOD/vox/beam.vox' scale='" .. SCALE .. "' pos='" .. fmt3(beamPos) .. "' rot='" .. REST .. " 0 0'/>" ..
		"<vox file='MOD/vox/bucket.vox' scale='" .. SCALE .. "' pos='" .. fmt3(VecAdd(T, Vec(0, -0.45, 0))) .. "'/>" ..
		"<vox file='MOD/vox/weight.vox' scale='" .. SCALE .. "' pos='" .. fmt3(weightPos) .. "' rot='" .. REST .. " 0 0'/>" ..
		"</body>"
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Catapult", "Катапульта"), "MOD/prefab/tool.xml", 6)
	server.cats = {}
	server.ammo = {}              -- { body, kind, cat } spawned by the mod
	server.flying = {}
	server.protect = {}           -- launched players: [p] = { t, landed }
	server.impacts = {}
	server.nextId = 1
	shared.cp = { list = {}, fireN = 0, fx = 0, fy = 0, fz = 0, relN = 0, impN = 0, ix = 0, iy = 0, iz = 0, isp = 0, msg = "", mn = 0, flying = {} }
end

local function message(kind)
	shared.cp.msg = kind
	shared.cp.mn = shared.cp.mn + 1
end

local function catById(id)
	for i = 1, #server.cats do if server.cats[i].id == id then return server.cats[i], i end end
	return nil
end

local function nearestCat(pos, maxd)
	local best, bd = nil, maxd or 40
	for i = 1, #server.cats do
		local c = server.cats[i]
		if IsHandleValid(c.frame) then
			local d = VecLength(VecSub(GetBodyTransform(c.frame).pos, pos))
			if d < bd then best, bd = c, d end
		end
	end
	return best
end

-- measured geometry
local function shapeCentre(shape, yFrac)
	local sx, sy, sz, vs = GetShapeSize(shape)
	return TransformToParentPoint(GetShapeWorldTransform(shape), Vec(sx * vs * 0.5, sy * vs * (yFrac or 0.5), sz * vs * 0.5))
end
function server.pivot(c) return shapeCentre(c.axle, 0.5) end
function server.bucketFloor(c)
	local sx, sy, sz, vs = GetShapeSize(c.bucket)
	return TransformToParentPoint(GetShapeWorldTransform(c.bucket), Vec(sx * vs * 0.5, vs, sz * vs * 0.5))
end
function server.back(c) return QuatRotateVec(GetBodyTransform(c.frame).rot, Vec(0, 0, 1)) end
function server.psi(c)
	local d = VecSub(server.bucketFloor(c), server.pivot(c))
	return math.deg(math.atan2(d[2], VecDot(d, server.back(c))))
end

function server.sync()
	local list = {}
	for i = 1, #server.cats do
		local c = server.cats[i]
		list[i] = { id = c.id, frame = c.frame, arm = c.arm, axle = c.axle, bucket = c.bucket, power = c.power, angle = c.angle,
			ammo = c.ammo, state = c.state, armLen = c.armLen or L1, psiRest = c.psiRest or -REST, broken = c.broken }
	end
	shared.cp.list = list
	local fl = {}
	for i = 1, math.min(#server.flying, 12) do fl[i] = server.flying[i].body end
	shared.cp.flying = fl
end

function server.tick(dt)
	for p in PlayersAdded() do SetToolEnabled(TOOL, true, p) end
	for p in Players() do
		-- E on a catapult fires it, with any tool in hand
		if InputPressed("interact", p) then
			local ib = GetPlayerInteractBody(p)
			if ib ~= 0 then
				for i = 1, #server.cats do
					local c = server.cats[i]
					if ib == c.frame or ib == c.arm then server.fire(c) end
				end
			end
		end
		if GetPlayerTool(p) == TOOL and GetPlayerCanUseTool(p) and GetPlayerVehicle(p) == 0 then
			if InputPressed("usetool", p) then server.place(p) end
			if InputPressed("grab", p) and GetPlayerGrabBody(p) == 0 then
				local c = nearestCat(GetPlayerTransform(p).pos)
				if c then server.load(c, c.ammo) end
			end
		end
	end
	-- launched players: no fall damage unless the option says so
	for p, pr in pairs(server.protect) do
		pr.t = pr.t + dt
		if not readSettings().falldamage then SetPlayerHealth(1, p) end
		local v = GetPlayerVelocity(p)
		if pr.t > 0.5 and math.abs(v[2]) < 0.5 then pr.landed = (pr.landed or 0) + dt end
		if (pr.landed or 0) > 1.5 or pr.t > 30 then server.protect[p] = nil end
	end
end

function server.place(p)
	if #server.cats >= MAX_CATAPULTS then message("full") return end
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	local flat = Vec(fwd[1], 0, fwd[3])
	if VecLength(flat) < 0.1 then flat = Vec(0, 0, -1) end
	flat = VecNormalize(flat)
	local pp = GetPlayerTransform(p).pos
	local probe = VecAdd(pp, VecAdd(VecScale(flat, 14), Vec(0, 20, 0)))
	QueryRejectPlayer(p)
	QueryRequire("physical static")
	local hit, dist = QueryRaycast(probe, Vec(0, -1, 0), 60)
	if not hit then message("aim") return end
	local g = VecAdd(probe, Vec(0, -dist, 0))
	local yaw = math.deg(math.atan2(-flat[1], -flat[3]))
	local ents = Spawn(prefab(), Transform(g, QuatEuler(0, yaw, 0)), true)
	local c = { id = server.nextId, frame = 0, arm = 0, joint = 0, axle = 0, bucket = 0, yaw = yaw, base = g,
		power = 0.75, angle = 45, ammo = readSettings().ammo, state = "settle", t = 0, held = {}, heldPlayers = {}, sign = 1 }
	server.nextId = server.nextId + 1
	for i = 1, #ents do
		local e = ents[i]
		local ty = GetEntityType(e)
		if ty == "body" then
			if HasTag(e, "catapult_arm") then c.arm = e elseif c.frame == 0 then c.frame = e end
		elseif ty == "joint" and c.joint == 0 then
			c.joint = e
		end
	end
	if c.frame == 0 or c.arm == 0 then message("aim") return end
	for _, sh in ipairs(GetBodyShapes(c.frame)) do
		local sx, sy, sz = GetShapeSize(sh)
		if sx == 26 and sy == 4 and sz == 4 then c.axle = sh end
	end
	for _, sh in ipairs(GetBodyShapes(c.arm)) do
		local sx, sy, sz = GetShapeSize(sh)
		if sx == 9 and sy == 5 and sz == 9 then c.bucket = sh end
	end
	server.cats[#server.cats + 1] = c
	server.sync()
	message("placed")
end

-- bodies (and players) lying in the bucket
function server.contents(c)
	local b = server.bucketFloor(c)
	QueryRequire("physical dynamic")
	local list = QueryAabbBodies(VecAdd(b, Vec(-1.5, -0.3, -1.5)), VecAdd(b, Vec(1.5, 2.6, 1.5)))
	local out = {}
	for i = 1, #list do
		local body = list[i]
		local ours = false
		for j = 1, #server.cats do if body == server.cats[j].frame or body == server.cats[j].arm then ours = true end end
		if not ours and GetBodyPlayer(body) == 0 and IsBodyDynamic(body) then out[#out + 1] = body end
	end
	local players = {}
	for p in Players() do
		local pp = GetPlayerTransform(p).pos
		local d = VecSub(pp, b)
		if math.abs(d[1]) < 1.6 and math.abs(d[3]) < 1.6 and d[2] > -0.5 and d[2] < 2.5 then players[#players + 1] = p end
	end
	return out, players
end

local function trimAmmo(extra)
	-- keep the number of mod-spawned ammo bodies bounded: drop the oldest that are not in a swing
	local alive = {}
	for i = 1, #server.ammo do if IsHandleValid(server.ammo[i].body) then alive[#alive + 1] = server.ammo[i] end end
	server.ammo = alive
	while #server.ammo + extra > MAX_AMMO and #server.ammo > 0 do
		local a = table.remove(server.ammo, 1)
		Delete(a.body)
	end
	local cars = 0
	for i = #server.ammo, 1, -1 do
		if server.ammo[i].kind == "car" then
			cars = cars + 1
			if cars > MAX_CARS - 1 and extra > 0 then Delete(server.ammo[i].body) table.remove(server.ammo, i) end
		end
	end
end

function server.load(c, kind)
	if c.broken or c.state ~= "ready" then return end
	local inside = server.contents(c)
	if #inside > 0 then message("loaded") return end
	local name = AMMO[kind] or "boulder"
	local floor = server.bucketFloor(c)
	local rot = GetBodyTransform(c.frame).rot
	local ents
	if name == "boulder" then
		trimAmmo(1)
		ents = Spawn("<body dynamic='true'><vox file='MOD/vox/boulder.vox' scale='3'/></body>", Transform(VecAdd(floor, Vec(0, 0.05, 0)), rot))
	elseif name == "barrel" then
		trimAmmo(1)
		ents = Spawn("<body dynamic='true' tags='catapult_barrel'><vox file='MOD/vox/barrel.vox' scale='3'/></body>", Transform(VecAdd(floor, Vec(0, 0.05, 0)), rot))
	elseif name == "crates" then
		trimAmmo(6)
		local xml = ""
		local slots = { { -0.5, 0, -0.5 }, { 0.5, 0, -0.5 }, { -0.5, 0, 0.5 }, { 0.5, 0, 0.5 }, { 0, 0.95, -0.5 }, { 0, 0.95, 0.5 } }
		for i = 1, #slots do
			xml = xml .. "<body dynamic='true' pos='" .. slots[i][1] .. " " .. (0.05 + slots[i][2]) .. " " .. slots[i][3] .. "'><vox file='MOD/vox/crate.vox' scale='3'/></body>"
		end
		ents = Spawn(xml, Transform(floor, rot))
	elseif name == "car" then
		trimAmmo(1)
		-- the game's own small car if its prefab can be spawned, else the mod's car body
		local t = Transform(VecAdd(floor, Vec(0, 0.4, 0)), QuatRotateQuat(rot, QuatEuler(0, 90, 0)))
		ents = Spawn("BUILT-IN/prefab/vehicle/land/generic_small_blue.xml", t)
		local any = false
		for i = 1, #(ents or {}) do if GetEntityType(ents[i]) == "body" then any = true end end
		if not any then
			ents = Spawn("<body dynamic='true'><vox file='MOD/vox/hulk.vox' scale='3'/></body>", t)
		end
	end
	-- the loaded ammo is held gently where it lies in the bucket while the catapult stands
	-- (aiming and turning cannot shake it out); anything else in the bucket rests freely
	local armT = GetBodyTransform(c.arm)
	c.loadedBodies = {}
	for i = 1, #(ents or {}) do
		if GetEntityType(ents[i]) == "body" then
			local b = ents[i]
			server.ammo[#server.ammo + 1] = { body = b, kind = name, cat = c.id }
			local com = TransformToParentPoint(GetBodyTransform(b), GetBodyCenterOfMass(b))
			c.loadedBodies[#c.loadedBodies + 1] = { body = b, off = TransformToLocalPoint(armT, com) }
		end
	end
	c.loaded = name
end

function server.fire(c)
	if c.broken or c.state ~= "ready" then return end
	local bodies, players = server.contents(c)
	local armT = GetBodyTransform(c.arm)
	c.held = {}
	for i = 1, #bodies do
		local b = bodies[i]
		local com = TransformToParentPoint(GetBodyTransform(b), GetBodyCenterOfMass(b))
		local kind = "other"
		for j = 1, #server.ammo do if server.ammo[j].body == b then kind = server.ammo[j].kind end end
		c.held[#c.held + 1] = { body = b, off = TransformToLocalPoint(armT, com), kind = kind }
	end
	c.heldPlayers = {}
	for i = 1, #players do
		local p = players[i]
		c.heldPlayers[#c.heldPlayers + 1] = { p = p, off = TransformToLocalPoint(armT, GetPlayerTransform(p).pos) }
	end
	c.state = "swing"
	c.t = 0
	c.signChecked = false
	c.psiStart = server.psi(c)
	c.psiPrev = c.psiStart
	c.release = 90 - c.angle
	c.timeout = math.rad(c.release - c.psiStart) / SWING + 0.35
	SetJointMotor(c.joint, c.sign * SWING)
	shared.cp.fireN = shared.cp.fireN + 1
	local fp = GetBodyTransform(c.frame).pos
	shared.cp.fx, shared.cp.fy, shared.cp.fz = fp[1], fp[2], fp[3]
	server.sync()
end

function server.releaseLoad(c)
	local fwd = VecScale(server.back(c), -1)
	local th = math.rad(c.angle)
	local speed = launchSpeed(c.power)
	local v = VecAdd(VecScale(fwd, speed * math.cos(th)), Vec(0, speed * math.sin(th), 0))
	for i = 1, #c.held do
		local h = c.held[i]
		if IsHandleValid(h.body) then
			SetBodyVelocity(h.body, VecAdd(v, Vec(rnd(-0.3, 0.3), rnd(-0.3, 0.3), rnd(-0.3, 0.3))))
			SetBodyAngularVelocity(h.body, Vec(rnd(-2, 2), rnd(-2, 2), rnd(-2, 2)))
			if #server.flying < MAX_FLYING then
				server.flying[#server.flying + 1] = { body = h.body, kind = h.kind, t = 0, prev = VecCopy(v), n = 0, from = VecCopy(server.bucketFloor(c)), cat = c.id }
			end
		end
	end
	for i = 1, #c.heldPlayers do
		local hp = c.heldPlayers[i]
		SetPlayerVelocity(v, hp.p)
		server.protect[hp.p] = { t = 0 }
	end
	c.lastLaunch = { pos = server.bucketFloor(c), vel = v, speed = speed, psi = server.psi(c), held = #c.held + #c.heldPlayers }
	c.held = {}
	c.heldPlayers = {}
	c.loaded = nil
	c.loadedBodies = {}
	SetJointMotor(c.joint, 0)                  -- brake right away so the bucket does not catch the load
	c.state = "reset"
	c.t = 0
	shared.cp.relN = shared.cp.relN + 1
end

function server.update(dt)
	local s = readSettings()
	for i = #server.cats, 1, -1 do
		local c = server.cats[i]
		if not IsHandleValid(c.frame) or not IsHandleValid(c.arm) or (c.joint ~= 0 and IsJointBroken(c.joint)) then
			if not c.broken then c.broken = true c.state = "broken" server.sync() end
		elseif c.state == "settle" then
			c.t = c.t + dt
			if c.t > 0.05 then
				c.psiRest = server.psi(c)
				c.armLen = VecLength(VecSub(server.bucketFloor(c), server.pivot(c)))
				c.state = "ready"
				c.t = 0
				server.load(c, c.ammo)
				server.sync()
			end
		elseif c.state == "ready" then
			SetJointMotorTarget(c.joint, 0, 1.5)
			local armT = GetBodyTransform(c.arm)
			for j = 1, #(c.loadedBodies or {}) do
				local h = c.loadedBodies[j]
				if IsHandleValid(h.body) then
					local com = TransformToParentPoint(GetBodyTransform(h.body), GetBodyCenterOfMass(h.body))
					ConstrainPosition(h.body, c.arm, com, TransformToParentPoint(armT, h.off), 4)
				end
			end
		elseif c.state == "swing" then
			c.t = c.t + dt
			local psi = server.psi(c)
			-- the hinge's sign convention is unknown: if the arm goes the wrong way, reverse once
			if not c.signChecked and c.t > 0.06 then
				c.signChecked = true
				if psi < c.psiStart - 0.5 then
					c.sign = -c.sign
					SetJointMotor(c.joint, c.sign * SWING)
				end
			end
			local armT = GetBodyTransform(c.arm)
			for j = 1, #c.held do
				local h = c.held[j]
				if IsHandleValid(h.body) then
					local com = TransformToParentPoint(GetBodyTransform(h.body), GetBodyCenterOfMass(h.body))
					ConstrainPosition(h.body, c.arm, com, TransformToParentPoint(armT, h.off), 80)
				end
			end
			for j = 1, #c.heldPlayers do
				local hp = c.heldPlayers[j]
				SetPlayerTransform(Transform(TransformToParentPoint(armT, hp.off), GetPlayerTransform(hp.p).rot), hp.p)
				SetPlayerVelocity(Vec(0, 0, 0), hp.p)
			end
			if psi >= c.release or c.t >= c.timeout then server.releaseLoad(c) server.sync() end
			c.psiPrev = psi
		elseif c.state == "reset" then
			c.t = c.t + dt
			if c.t > 0.5 then SetJointMotorTarget(c.joint, 0, 1.2) end
			if c.t > 1.0 and (math.abs(GetJointMovement(c.joint)) < 3 or c.t > 4) then
				c.state = "ready"
				c.t = 0
				if s.reload then server.load(c, c.ammo) end
				server.sync()
			end
		end
	end
	server.updateFlying(dt, s)
end

-- impacts: a sudden loss of speed is a hit; holes by speed and material
function server.updateFlying(dt, s)
	local holes = 0
	for i = #server.flying, 1, -1 do
		local f = server.flying[i]
		f.t = f.t + dt
		if not IsHandleValid(f.body) then
			table.remove(server.flying, i)
		else
			local v = GetBodyVelocity(f.body)
			local sp = VecLength(f.prev)
			local dv = VecLength(VecSub(v, f.prev))
			if f.t > 0.12 and sp > 12 and dv > 0.45 * sp and holes < HOLES_PER_UPDATE then
				local pos = TransformToParentPoint(GetBodyTransform(f.body), GetBodyCenterOfMass(f.body))
				local dir = VecScale(f.prev, 1 / sp)
				local k = AMMO_K[f.kind] or AMMO_K.other
				local e = sp * s.damage
				local r0 = clamp(0.065 * e * k, 0.6, 5)
				local r1 = (e >= 25) and r0 * 0.75 or r0 * 0.3
				local r2 = (e >= 45) and r0 * 0.35 or 0
				MakeHole(VecAdd(pos, VecScale(dir, 0.4)), r0, r1, r2)
				holes = holes + 1
				if f.kind == "boulder" and f.n == 0 then
					-- a boulder punches on through
					for d = 1, 2 do
						if holes < HOLES_PER_UPDATE then
							MakeHole(VecAdd(pos, VecScale(dir, 1.5 * d)), r0 * (1 - 0.2 * d), r1 * (1 - 0.2 * d), r2 * (1 - 0.2 * d))
							holes = holes + 1
						end
					end
				end
				if f.kind == "barrel" and f.n == 0 and VecLength(VecSub(pos, f.from)) > 12 then
					Explosion(pos, 2.5)
				end
				f.n = f.n + 1
				server.impacts[#server.impacts + 1] = { speed = sp, pos = pos, kind = f.kind }
				local cp = shared.cp
				cp.impN = cp.impN + 1
				cp.ix, cp.iy, cp.iz, cp.isp = pos[1], pos[2], pos[3], sp
			end
			f.prev = v
			if f.n >= 3 or (VecLength(v) < 4 and f.t > 1) or f.t > 20 then table.remove(server.flying, i) end
		end
	end
	server.sync()
end

-- client commands
function server.cmd(p, id, what, value)
	local c = catById(id)
	if what == "clear" then return server.clear() end
	if not c then return end
	if what == "fire" then server.fire(c)
	elseif what == "power" then c.power = clamp(value, 0, 1)
	elseif what == "angle" then c.angle = clamp(value, 20, 70)
	elseif what == "ammo" then c.ammo = math.floor(clamp(value, 1, 4)) server.load(c, c.ammo)
	elseif what == "turn" and c.state == "ready" then server.turn(c, value)
	end
	server.sync()
end

-- turn the whole machine (frame, arm and whatever is in the bucket) about its base
function server.turn(c, deg)
	local oldT = Transform(c.base, QuatEuler(0, c.yaw, 0))
	c.yaw = c.yaw + deg
	local newT = Transform(c.base, QuatEuler(0, c.yaw, 0))
	local bodies = server.contents(c)
	local all = { c.frame, c.arm }
	for i = 1, #bodies do all[#all + 1] = bodies[i] end
	for i = 1, #all do
		local rel = TransformToLocalTransform(oldT, GetBodyTransform(all[i]))
		SetBodyTransform(all[i], TransformToParentTransform(newT, rel))
	end
end

function server.clear()
	for i = 1, #server.cats do
		local c = server.cats[i]
		if IsHandleValid(c.arm) then Delete(c.arm) end
		if IsHandleValid(c.frame) then Delete(c.frame) end
	end
	for i = 1, #server.ammo do if IsHandleValid(server.ammo[i].body) then Delete(server.ammo[i].body) end end
	server.cats = {}
	server.ammo = {}
	server.flying = {}
	server.sync()
	message("cleared")
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.snd = {}
	for _, n in ipairs({ "creak", "swing", "twang", "impact" }) do client.snd[n] = LoadSound("MOD/snd/" .. n .. ".ogg", 150) end
	client.whistle = LoadLoop("MOD/snd/whistle.ogg", 40)
	client.anim = {}
	client.seen = nil
	client.sel = nil
	client.turnAcc = 0
	client.turnT = 0
	client.arc = nil
	client.arcT = 0
	client.arcRange = nil
	client.msg, client.msgT = "", 0
	client.burst = nil
end

local MESSAGES = {
	full = { "At most 4 catapults", "Не больше 4 катапульт" },
	aim = { "No room here: aim at open ground", "Здесь не поставить: наведите на открытую землю" },
	cleared = { "Catapults removed", "Катапульты убраны" },
	loaded = { "The bucket is not empty", "Ковш уже занят" },
	placed = { "Catapult placed", "Катапульта поставлена" },
}
local AMMO_NAMES = { { "Boulder", "Валун" }, { "Explosive barrel", "Бочка со взрывчаткой" }, { "Car", "Машина" }, { "Crates", "Ящики" } }

local function selectCat()
	local pp = GetPlayerTransform().pos
	local best, bd = nil, 40
	for i, c in ipairs(shared.cp.list) do
		if c.frame ~= 0 and IsHandleValid(c.frame) then
			local d = VecLength(VecSub(GetBodyTransform(c.frame).pos, pp))
			if d < bd then best, bd = c, d end
		end
	end
	return best
end

function client.tick(dt)
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local cp = shared.cp
	local seen = client.seen
	if not seen then seen = { fireN = cp.fireN, relN = cp.relN, impN = cp.impN, mn = cp.mn } client.seen = seen end
	if cp.fireN ~= seen.fireN then seen.fireN = cp.fireN PlaySound(client.snd.swing, Vec(cp.fx, cp.fy + 8, cp.fz), 1.0) end
	if cp.relN ~= seen.relN then seen.relN = cp.relN PlaySound(client.snd.twang, Vec(cp.fx, cp.fy + 10, cp.fz), 0.9) end
	if cp.impN ~= seen.impN then
		seen.impN = cp.impN
		local ip = Vec(cp.ix, cp.iy, cp.iz)
		PlaySound(client.snd.impact, ip, clamp(cp.isp / 40, 0.4, 1.2))
		client.burst = { pos = ip, power = clamp(cp.isp / 50, 0.2, 1) }
		local d = VecLength(VecSub(GetPlayerCameraTransform().pos, ip))
		if d < 60 then ShakeCamera(clamp(cp.isp / 60, 0.2, 1) * (1 - d / 60)) end
	end
	if cp.mn ~= seen.mn then
		seen.mn = cp.mn
		local m = MESSAGES[cp.msg]
		if m then client.msg, client.msgT = tr(m[1], m[2]), 2 end
	end
	client.msgT = math.max(0, client.msgT - dt)
	for i = 1, math.min(#cp.flying, 3) do
		local b = cp.flying[i]
		if IsHandleValid(b) then PlayLoop(client.whistle, GetBodyTransform(b).pos, 0.6) end
	end

	local me = GetLocalPlayer()
	local holding = GetPlayerTool() == TOOL and GetPlayerCanUseTool()
	client.sel = holding and selectCat() or nil
	local c = client.sel
	if holding then
		if InputPressed("r") then ServerCall("server.cmd", me, 0, "clear", 0) end
	end
	if c then
		SetBool("game.input.locktool", true)           -- the wheel sets the power
		local wheel = InputValue("mousewheel")
		if wheel ~= 0 then ServerCall("server.cmd", me, c.id, "power", clamp(c.power + 0.05 * wheel, 0, 1)) end
		if InputPressed("f") then ServerCall("server.cmd", me, c.id, "fire", 0) end
		if InputPressed("x") then ServerCall("server.cmd", me, c.id, "angle", c.angle - 5) end
		if InputPressed("v") then ServerCall("server.cmd", me, c.id, "angle", c.angle + 5) end
		for k = 1, 4 do if InputPressed(tostring(k)) then ServerCall("server.cmd", me, c.id, "ammo", k) end end
		local turn = (InputDown("z") and 1 or 0) - (InputDown("c") and 1 or 0)
		client.turnAcc = client.turnAcc + turn * 30 * dt
		client.turnT = client.turnT + dt
		if client.turnT > 0.1 and math.abs(client.turnAcc) > 0.01 then
			ServerCall("server.cmd", me, c.id, "turn", client.turnAcc)
			if client.turnAcc ~= 0 then PlaySound(client.snd.creak, GetBodyTransform(c.frame).pos, 0.4) end
			client.turnAcc = 0
			client.turnT = 0
		end
	end
	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local an = client.anim[p]
			if not an then an = ToolAnimator() client.anim[p] = an end
			tickToolAnimator(an, dt, nil, p)
		end
	end
end

-- predicted flight: from the bucket at the release angle, with the planned launch velocity,
-- until it meets the world. Returns points, landing point, horizontal range from the release.
function client.predict(c)
	if c.axle == 0 or c.bucket == 0 or not IsHandleValid(c.axle) or not IsHandleValid(c.bucket) then return nil end
	local sx, sy, sz, vs = GetShapeSize(c.axle)
	local P = TransformToParentPoint(GetShapeWorldTransform(c.axle), Vec(sx * vs * 0.5, sy * vs * 0.5, sz * vs * 0.5))
	local back = QuatRotateVec(GetBodyTransform(c.frame).rot, Vec(0, 0, 1))
	local psi = math.rad(90 - c.angle)
	local R = VecAdd(P, VecAdd(VecScale(back, c.armLen * math.cos(psi)), Vec(0, c.armLen * math.sin(psi), 0)))
	local th = math.rad(c.angle)
	local speed = launchSpeed(c.power)
	local v = VecAdd(VecScale(back, -speed * math.cos(th)), Vec(0, speed * math.sin(th), 0))
	local g = GetGravity()
	local pts = { R }
	local p = R
	local land = nil
	local step = 0.06
	for i = 1, 300 do
		local np = VecAdd(VecAdd(p, VecScale(v, step)), VecScale(g, 0.5 * step * step))
		local nv = VecAdd(v, VecScale(g, step))
		if i % 2 == 0 or np[2] < R[2] - 2 then
			local seg = VecSub(np, p)
			local l = VecLength(seg)
			QueryRequire("physical")
			QueryRejectBody(c.frame)
			QueryRejectBody(c.arm)
			local hit, d = QueryRaycast(p, VecScale(seg, 1 / l), l)
			if hit then land = VecAdd(p, VecScale(seg, d / l)) pts[#pts + 1] = land break end
		end
		pts[#pts + 1] = np
		p, v = np, nv
		if p[2] < -50 then break end
	end
	land = land or p
	local range = math.sqrt((land[1] - R[1]) ^ 2 + (land[3] - R[3]) ^ 2)
	return pts, land, range
end

function client.render(dt)
	local c = client.sel
	if c and IsHandleValid(c.frame) then DrawBodyOutline(c.frame, 1, 0.75, 0.3, 0.5) end
	if not c or c.broken or not readSettings().arc then client.arcRange = nil return end
	client.arcT = client.arcT - dt
	if client.arcT <= 0 or not client.arc or client.arc.power ~= c.power or client.arc.angle ~= c.angle then
		client.arcT = 0.15
		local pts, land, range = client.predict(c)
		client.arc = pts and { pts = pts, land = land, range = range, power = c.power, angle = c.angle } or nil
		client.arcRange = range
	end
	local a = client.arc
	if not a then return end
	for i = 1, #a.pts - 1, 2 do                      -- dashed line
		DrawLine(a.pts[i], a.pts[i + 1], 1, 0.85, 0.4, 0.9)
	end
	local rad = 2.5
	for i = 0, 15 do
		local a0, a1 = i / 16 * 6.2832, (i + 1) / 16 * 6.2832
		DrawLine(VecAdd(a.land, Vec(math.cos(a0) * rad, 0.2, math.sin(a0) * rad)), VecAdd(a.land, Vec(math.cos(a1) * rad, 0.2, math.sin(a1) * rad)), 1, 0.5, 0.2, 1)
	end
end

function client.update(dt)
	local cp = shared.cp
	-- dust trails behind flying loads
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.6, 0.55, 0.5)
	ParticleRadius(0.3, 0.8)
	ParticleAlpha(0.5, 0)
	ParticleGravity(0.2)
	for i = 1, math.min(#cp.flying, 12) do
		local b = cp.flying[i]
		if IsHandleValid(b) then SpawnParticle(GetBodyTransform(b).pos, Vec(0, 0.3, 0), 1.2) end
	end
	local burst = client.burst
	if burst then
		client.burst = nil
		ParticleReset()
		ParticleType("smoke")
		ParticleColor(0.55, 0.5, 0.45)
		ParticleRadius(0.8, 3)
		ParticleAlpha(0.7, 0)
		ParticleGravity(0.5)
		ParticleDrag(0.4)
		for i = 1, math.floor(8 + 16 * burst.power) do
			SpawnParticle(burst.pos, VecAdd(GetRandomDirection(rnd(2, 10) * burst.power), Vec(0, 2, 0)), rnd(1.5, 3))
		end
	end
end

function client.draw(dt)
	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or not GetPlayerCanUseTool() then return end
	local c = client.sel
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 170)
		UiAlign("center middle")
		UiTextShadow(0, 0, 0, 0.6, 1.5)
		UiFont("regular.ttf", 21)
		UiColor(1, 1, 1, 0.92)
		if c then
			local ammo = AMMO_NAMES[c.ammo] or AMMO_NAMES[1]
			local state = c.broken and tr("BROKEN", "СЛОМАНА") or ((c.state == "ready") and tr("ready", "готова") or tr("reloading", "перезарядка"))
			UiFont("bold.ttf", 22)
			UiText(string.format(tr("Catapult - power %d%% - angle %d° - %s - %s", "Катапульта - сила %d%% - угол %d° - %s - %s"),
				math.floor(c.power * 100 + 0.5), c.angle, tr(ammo[1], ammo[2]), state))
			if client.arcRange then
				UiTranslate(0, 26)
				UiColor(1, 0.8, 0.4, 1)
				UiText(string.format(tr("Range about %d m", "Дальность около %d м"), math.floor(client.arcRange + 0.5)))
			end
			UiTranslate(0, 26)
			UiFont("regular.ttf", 18)
			UiColor(1, 1, 1, 0.8)
			UiText(tr("F or E: fire   Wheel: power   Z/C: turn   X/V: angle   1-4: ammo   RMB: load   R: remove all",
				"F или E: выстрел   Колесо: сила   Z/C: поворот   X/V: угол   1-4: снаряд   ПКМ: зарядить   R: убрать все"))
		else
			UiText(tr("LMB: place a catapult in front of you   R: remove all", "ЛКМ: поставить катапульту перед собой   R: убрать все"))
		end
		if client.msgT > 0 then
			UiTranslate(0, 28)
			UiColor(1, 0.6, 0.3, math.min(1, client.msgT))
			UiText(client.msg)
		end
	UiPop()
end
