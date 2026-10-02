#version 2
-- Portal Gun / Портальная пушка
-- LMB places the blue portal, RMB the orange one, on flat surfaces (walls,
-- floors, ceilings). Walking, falling or throwing things into one brings them
-- out of the other with the momentum rotated into the exit portal's frame.
-- R closes both portals.
--
-- What the API allows (see README): teleporting players (SetPlayerTransformWithPitch
-- + SetPlayerVelocity) and dynamic bodies (SetBodyTransform + SetBodyVelocity +
-- SetBodyAngularVelocity) works. There is no render-to-texture, mirror or camera
-- feed in script_defs.lua, so you cannot see through a portal: the surface is an
-- animated swirl sprite (DrawSprite) with a glowing rim.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "portalgun"
local COLORS = { { 0.25, 0.6, 1.0 }, { 1.0, 0.55, 0.12 } }
local SIZES = { { 0.45, 0.8 }, { 0.6, 1.05 }, { 0.8, 1.35 } }   -- half width, half height
local PLAYER_COOLDOWN = 1.0   -- seconds after a teleport before the same player can teleport again
local BODY_COOLDOWN = 1.0     -- the same for every body, tracked per body
local LEAVE_DIST = 1.0        -- and it must first move this far away from the exit portal
local CHECK_INTERVAL = 0.25

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getI(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetInt(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		range = clamp(getF("range", 100), 20, 200),
		size = math.floor(clamp(getI("size", 2), 1, 3)),
		bodies = getB("bodies", true),
		massLimit = clamp(getF("masslimit", 500), 50, 3000),
		dynamic = getB("dynamic", false),
		hum = clamp(getF("hum", 0.5), 0, 1),
	}
end

-- portal frame: x = right, y = up, z = normal (out of the surface)
local function frame(n, viewFwd)
	local up
	if math.abs(n[2]) > 0.7 then
		-- floor / ceiling: "up" of the portal points away from the player along the view
		up = VecSub(viewFwd, VecScale(n, VecDot(viewFwd, n)))
		if VecLength(up) < 0.01 then up = Vec(0, 0, -1) end
		up = VecNormalize(up)
	else
		up = VecNormalize(VecSub(Vec(0, 1, 0), VecScale(n, n[2])))
	end
	local right = VecCross(up, n)
	return right, up
end

function portalRot(p) return QuatAlignXZ(Vec(p.rx, p.ry, p.rz), Vec(p.nx, p.ny, p.nz)) end

local function toLocal(p, point)
	local d = VecSub(point, Vec(p.x, p.y, p.z))
	return VecDot(d, Vec(p.rx, p.ry, p.rz)), VecDot(d, Vec(p.ux, p.uy, p.uz)), VecDot(d, Vec(p.nx, p.ny, p.nz))
end

local function vecToLocal(p, v)
	return VecDot(v, Vec(p.rx, p.ry, p.rz)), VecDot(v, Vec(p.ux, p.uy, p.uz)), VecDot(v, Vec(p.nx, p.ny, p.nz))
end

-- entering A along -nA, leaving B along +nB: local (x, y, z) -> (-x, y, -z)
local function mapPoint(a, b, point, outOffset)
	local x, y, z = toLocal(a, point)
	local bx, by = -x, y
	local pos = VecAdd(Vec(b.x, b.y, b.z), VecAdd(VecScale(Vec(b.rx, b.ry, b.rz), bx), VecScale(Vec(b.ux, b.uy, b.uz), by)))
	return VecAdd(pos, VecScale(Vec(b.nx, b.ny, b.nz), outOffset))
end

local function mapVec(a, b, v)
	local x, y, z = vecToLocal(a, v)
	return VecAdd(VecAdd(VecScale(Vec(b.rx, b.ry, b.rz), -x), VecScale(Vec(b.ux, b.uy, b.uz), y)), VecScale(Vec(b.nx, b.ny, b.nz), -z))
end

local function mapRot(a, b, q)
	local flip = QuatAxisAngle(Vec(0, 1, 0), 180)
	local qa = portalRot(a)
	local qb = portalRot(b)
	local inv = Quat(-qa[1], -qa[2], -qa[3], qa[4])
	return QuatRotateQuat(QuatRotateQuat(qb, QuatRotateQuat(flip, inv)), q)
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Portal Gun", "Портальная пушка"), "MOD/prefab/tool.xml", 6)
	server.players = {}
	server.cool = {}       -- body/player key -> time left
	server.lock = {}       -- body/player key -> exit portal it must leave first
	shared.pairs = {}
end

local function pairOf(p)
	local pr = shared.pairs[p]
	if not pr then
		pr = { { active = false, n = 0 }, { active = false, n = 0 }, fireN = 0, fireColor = 1, failN = 0, passN = 0, px = 0, py = 0, pz = 0, closeN = 0 }
		shared.pairs[p] = pr
	end
	return pr
end

function server.tick(dt)
	for p in PlayersAdded() do
		SetToolEnabled(TOOL, true, p)
		pairOf(p)
		server.players[p] = { checkT = 0 }
	end
	for p in PlayersRemoved() do
		shared.pairs[p] = nil
		server.players[p] = nil
	end
	for k, t in pairs(server.cool) do
		server.cool[k] = t - dt
		if server.cool[k] <= 0 then server.cool[k] = nil end
	end
	for p in Players() do
		local pr = pairOf(p)
		local st = server.players[p] or { checkT = 0 }
		server.players[p] = st
		if GetPlayerTool(p) == TOOL and GetPlayerCanUseTool(p) and GetPlayerVehicle(p) == 0 then
			if InputPressed("usetool", p) then server.fire(p, 1) end
			if InputPressed("grab", p) and GetPlayerGrabBody(p) == 0 and GetPlayerPickBody(p) == 0 then server.fire(p, 2) end
		end
		for i = 1, 2 do
			if pr[i].active then pr[i].age = (pr[i].age or 0) + dt end
		end
		st.checkT = st.checkT - dt
		if st.checkT <= 0 then
			st.checkT = CHECK_INTERVAL
			server.checkSurfaces(p, pr)
		end
	end
	-- players walk / fall through any pair
	for p in Players() do
		server.teleportPlayer(p)
	end
end

function server.reset(p)
	local pr = pairOf(p)
	for i = 1, 2 do
		if pr[i].active then
			pr[i].active = false
			pr[i].n = pr[i].n + 1
			pr.closeN = pr.closeN + 1
		end
	end
end

-- a portal needs a flat, solid area of its size
local function flatEnough(point, n, right, up, hw, hh, rejectBody)
	local offsets = { { hw * 0.9, 0 }, { -hw * 0.9, 0 }, { 0, hh * 0.9 }, { 0, -hh * 0.9 } }
	for i = 1, #offsets do
		local o = offsets[i]
		local p = VecAdd(VecAdd(point, VecScale(right, o[1])), VecScale(up, o[2]))
		local from = VecAdd(p, VecScale(n, 0.25))
		QueryRequire("physical")
		local hit, dist, nn = QueryRaycast(from, VecScale(n, -1), 0.45)
		if not hit or math.abs(dist - 0.25) > 0.12 or VecDot(nn, n) < 0.9 then return false end
		-- and nothing blocking right in front of the portal
		QueryRequire("physical")
		local blocked = QueryRaycast(VecAdd(p, VecScale(n, 0.05)), n, 0.4)
		if blocked then return false end
	end
	return true
end

function server.fire(p, color)
	local s = readSettings()
	local pr = pairOf(p)
	pr.fireN = pr.fireN + 1
	pr.fireColor = color
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	QueryRejectPlayer(p)
	QueryRequire("physical")
	local hit, dist, n, shape = QueryRaycast(eye.pos, fwd, s.range)
	local function fail(pos)
		pr.failN = pr.failN + 1
		pr.px, pr.py, pr.pz = pos[1], pos[2], pos[3]
	end
	if not hit or shape == 0 then
		fail(VecAdd(eye.pos, VecScale(fwd, math.min(dist, 30))))
		return
	end
	local point = VecAdd(eye.pos, VecScale(fwd, dist))
	local body = GetShapeBody(shape)
	if IsBodyDynamic(body) and not s.dynamic then fail(point) return end
	local right, up = frame(n, fwd)
	local hw, hh = SIZES[s.size][1], SIZES[s.size][2]
	if not flatEnough(point, n, right, up, hw, hh) then fail(point) return end
	-- not on top of the other portal
	local other = pr[3 - color]
	if other.active and VecLength(VecSub(point, Vec(other.x, other.y, other.z))) < hh * 2 then fail(point) return end
	local c = VecAdd(point, VecScale(n, 0.02))
	local bt = GetBodyTransform(body)
	local po = pr[color]
	po.active = true
	po.x, po.y, po.z = c[1], c[2], c[3]
	po.nx, po.ny, po.nz = n[1], n[2], n[3]
	po.rx, po.ry, po.rz = right[1], right[2], right[3]
	po.ux, po.uy, po.uz = up[1], up[2], up[3]
	po.hw, po.hh = hw, hh
	po.age = 0
	po.n = po.n + 1
	po.shape = shape
	po.body = body
	po.onDynamic = IsBodyDynamic(body)
	-- remember where it sits on the body so it can follow a moving body
	local lp = TransformToLocalPoint(bt, c)
	local ln = TransformToLocalVec(bt, n)
	local lr = TransformToLocalVec(bt, right)
	po.local_ = { lp[1], lp[2], lp[3], ln[1], ln[2], ln[3], lr[1], lr[2], lr[3] }
end

-- close portals whose surface broke away or whose body moved/vanished
function server.checkSurfaces(p, pr)
	for i = 1, 2 do
		local po = pr[i]
		if po.active then
			-- IsShapeBroken is true after any small damage, so solidity is tested with rays instead
			local ok = IsHandleValid(po.shape)
			if ok and po.onDynamic and IsHandleValid(po.body) then
				-- follow the body
				local bt = GetBodyTransform(po.body)
				local l = po.local_
				local c = TransformToParentPoint(bt, Vec(l[1], l[2], l[3]))
				local n = TransformToParentVec(bt, Vec(l[4], l[5], l[6]))
				local r = TransformToParentVec(bt, Vec(l[7], l[8], l[9]))
				local u = VecCross(n, r)
				po.x, po.y, po.z = c[1], c[2], c[3]
				po.nx, po.ny, po.nz = n[1], n[2], n[3]
				po.rx, po.ry, po.rz = r[1], r[2], r[3]
				po.ux, po.uy, po.uz = u[1], u[2], u[3]
			end
			if ok then
				-- the centre and two edges must still be solid
				local n = Vec(po.nx, po.ny, po.nz)
				local c = Vec(po.x, po.y, po.z)
				for k, o in ipairs({ { 0, 0 }, { po.hw * 0.8, 0 }, { -po.hw * 0.8, 0 } }) do
					local q = VecAdd(c, VecScale(Vec(po.rx, po.ry, po.rz), o[1]))
					QueryRequire("physical")
					local hit = QueryRaycast(VecAdd(q, VecScale(n, 0.2)), VecScale(n, -1), 0.4)
					if not hit then ok = false break end
				end
			end
			if not ok then
				po.active = false
				po.n = po.n + 1
				pr.closeN = pr.closeN + 1
			end
		end
	end
end

-- the player's capsule point closest to the portal plane
local function playerProbe(po, p)
	local t = GetPlayerTransform(p)
	local best, bz = nil, 1e9
	for _, h in ipairs({ 0.1, 0.9, 1.7 }) do
		local q = VecAdd(t.pos, Vec(0, h, 0))
		local x, y, z = toLocal(po, q)
		-- closest to the plane; on a wall all three are equally close, then take the one nearest the portal centre
		if z < bz - 0.05 or (math.abs(z - bz) <= 0.05 and math.abs(y) < math.abs(best.y)) then
			best, bz = { q = q, x = x, y = y, z = z, h = h }, z
		end
	end
	return best
end

-- an entity that came out of a portal must step away from it before that portal can take it again
local function locked(key, a)
	local lk = server.lock[key]
	return lk ~= nil and lk == a
end

local function releaseLock(key, point)
	local lk = server.lock[key]
	if lk then
		local x, y, z = toLocal(lk, point)
		if not lk.active or z > LEAVE_DIST or math.abs(x) > lk.hw + 0.5 or math.abs(y) > lk.hh + 0.8 then
			server.lock[key] = nil
		end
	end
end

function server.teleportPlayer(p)
	local key = "p" .. p
	releaseLock(key, VecAdd(GetPlayerTransform(p).pos, Vec(0, 0.9, 0)))
	if server.cool[key] then return end
	for owner, pr in pairs(shared.pairs) do
		if pr[1].active and pr[2].active then
			for i = 1, 2 do
				local a, b = pr[i], pr[3 - i]
				if not locked(key, a) then
					local pb = playerProbe(a, p)
					local v = GetPlayerVelocity(p)
					local vn = VecDot(v, Vec(a.nx, a.ny, a.nz))
					local yMargin = (math.abs(a.ny) > 0.7) and 0 or 0.3
					if pb.z < 0.5 and pb.z > -0.6 and math.abs(pb.x) < a.hw and math.abs(pb.y) < a.hh + yMargin and vn <= 0.2 then
						server.doTeleportPlayer(p, a, b, pb, v, owner, pr)
						return
					end
				end
			end
		end
	end
end

function server.doTeleportPlayer(p, a, b, pb, v, owner, pr)
	local out = mapPoint(a, b, pb.q, 0.55)
	-- put the player's feet where the probe point maps to
	local feet = VecSub(out, Vec(0, pb.h, 0))
	if b.ny > 0.7 then feet = VecAdd(Vec(b.x, b.y, b.z), Vec(0, 0.15, 0)) end
	local newVel = mapVec(a, b, v)
	-- leave with at least a little speed out of the exit portal
	local outN = Vec(b.nx, b.ny, b.nz)
	local along = VecDot(newVel, outN)
	if along < 2 then newVel = VecAdd(newVel, VecScale(outN, 2 - along)) end
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	local nf = mapVec(a, b, fwd)
	local yaw = math.deg(math.atan2(-nf[1], -nf[3]))
	local pitch = math.deg(math.asin(clamp(nf[2], -1, 1)))
	SetPlayerTransformWithPitch(Transform(feet, QuatEuler(pitch, yaw, 0)), p)
	SetPlayerVelocity(newVel, p)
	server.cool["p" .. p] = PLAYER_COOLDOWN
	server.lock["p" .. p] = b
	pr.passN = pr.passN + 1
	pr.px, pr.py, pr.pz = b.x, b.y, b.z
end

function server.update(dt)
	local s = readSettings()
	if not s.bodies then return end
	-- every physics step: a thrown object bounces off the wall behind a portal within a few steps
	for owner, pr in pairs(shared.pairs) do
		if pr[1].active and pr[2].active then
			for i = 1, 2 do server.teleportBodies(pr, pr[i], pr[3 - i], s, dt) end
		end
	end
end

function server.teleportBodies(pr, a, b, s, dt)
	local c = Vec(a.x, a.y, a.z)
	local r = math.max(a.hw, a.hh) + 1.5
	QueryRequire("physical dynamic")
	if a.body and a.body ~= 0 then QueryRejectBody(a.body) end
	local list = QueryAabbBodies(VecSub(c, Vec(r, r, r)), VecAdd(c, Vec(r, r, r)))
	for i = 1, math.min(#list, 24) do
		local body = list[i]
		local key = "b" .. body
		if server.lock[key] then releaseLock(key, GetBodyTransform(body).pos) end
		if not server.cool[key] and not locked(key, a) and GetBodyPlayer(body) == 0 and GetBodyVehicle(body) == 0 then
			local mass = GetBodyMass(body)
			if mass > 0 and mass <= s.massLimit then
				local bt = GetBodyTransform(body)
				local com = TransformToParentPoint(bt, GetBodyCenterOfMass(body))
				local bmin, bmax = GetBodyBounds(body)
				local he = VecScale(VecSub(bmax, bmin), 0.5)
				local hn = math.abs(he[1] * a.nx) + math.abs(he[2] * a.ny) + math.abs(he[3] * a.nz)
				local hr = math.abs(he[1] * a.rx) + math.abs(he[2] * a.ry) + math.abs(he[3] * a.rz)
				local hu = math.abs(he[1] * a.ux) + math.abs(he[2] * a.uy) + math.abs(he[3] * a.uz)
				local x, y, z = toLocal(a, com)
				local v = GetBodyVelocity(body)
				local vn = VecDot(v, Vec(a.nx, a.ny, a.nz))
				local fits = hr < a.hw and hu < a.hh
				-- look one step ahead so fast objects are caught before they hit the wall
				local zNext = z + math.min(vn, 0) * dt * 2
				if fits and zNext < hn + 0.15 and z > -0.5 and math.abs(x) < a.hw - hr * 0.5 and math.abs(y) < a.hh - hu * 0.5 and vn <= 0.1 then
					local hnB = math.abs(he[1] * b.nx) + math.abs(he[2] * b.ny) + math.abs(he[3] * b.nz)
					local newCom = mapPoint(a, b, com, hnB + 0.15)
					local newRot = mapRot(a, b, bt.rot)
					-- keep the body origin consistent with the centre of mass
					local comLocal = GetBodyCenterOfMass(body)
					local newPos = VecSub(newCom, QuatRotateVec(newRot, comLocal))
					local newVel = mapVec(a, b, v)
					local outN = Vec(b.nx, b.ny, b.nz)
					local along = VecDot(newVel, outN)
					if along < 1 then newVel = VecAdd(newVel, VecScale(outN, 1 - along)) end
					SetBodyTransform(body, Transform(newPos, newRot))
					SetBodyVelocity(body, newVel)
					SetBodyAngularVelocity(body, mapVec(a, b, GetBodyAngularVelocity(body)))
					server.cool[key] = BODY_COOLDOWN
					server.lock[key] = b
					pr.passN = pr.passN + 1
					pr.px, pr.py, pr.pz = b.x, b.y, b.z
				end
			end
		end
	end
end

-- R from the client
function server.resetCmd(p) server.reset(p) end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.snd = {}
	for _, n in ipairs({ "fire_blue", "fire_orange", "open", "close", "pass", "fail" }) do
		client.snd[n] = LoadSound("MOD/snd/" .. n .. ".ogg")
	end
	client.hum = LoadLoop("MOD/snd/hum.ogg", 6)
	client.swirl = LoadSprite("MOD/ui/swirl.png")
	client.rim = LoadSprite("MOD/ui/rim.png")
	client.anim = {}
	client.seen = {}
	client.t = 0
end

local function portalTransform(po, spin)
	local rot = portalRot(po)
	if spin then rot = QuatRotateQuat(rot, QuatAxisAngle(Vec(0, 0, 1), spin)) end
	return Transform(Vec(po.x + po.nx * 0.01, po.y + po.ny * 0.01, po.z + po.nz * 0.01), rot)
end

function client.tick(dt)
	client.t = client.t + dt
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local me = GetLocalPlayer()
	local hum = getF("hum", 0.5)

	for owner, pr in pairs(shared.pairs) do
		local seen = client.seen[owner]
		if not seen then
			seen = { fireN = pr.fireN, failN = pr.failN, passN = pr.passN, closeN = pr.closeN, n = { pr[1].n, pr[2].n } }
			client.seen[owner] = seen
		end
		if pr.fireN ~= seen.fireN then
			seen.fireN = pr.fireN
			PlaySound(pr.fireColor == 1 and client.snd.fire_blue or client.snd.fire_orange, GetPlayerTransform(owner).pos, 0.8)
		end
		if pr.failN ~= seen.failN then
			seen.failN = pr.failN
			PlaySound(client.snd.fail, Vec(pr.px, pr.py, pr.pz), 0.8)
			client.fizzle = Vec(pr.px, pr.py, pr.pz)
		end
		if pr.passN ~= seen.passN then
			seen.passN = pr.passN
			PlaySound(client.snd.pass, Vec(pr.px, pr.py, pr.pz), 1.0)
		end
		if pr.closeN ~= seen.closeN then
			seen.closeN = pr.closeN
			PlaySound(client.snd.close, GetPlayerTransform(owner).pos, 0.8)
		end
		for i = 1, 2 do
			local po = pr[i]
			if po.n ~= seen.n[i] then
				seen.n[i] = po.n
				if po.active then PlaySound(client.snd.open, Vec(po.x, po.y, po.z), 0.9) end
			end
			if po.active then
				local c = COLORS[i]
				local open = clamp((po.age or 1) / 0.25, 0, 1)
				local w, h = po.hw * 2 * open, po.hh * 2 * open
				local spin = client.t * (i == 1 and 120 or -120)
				DrawSprite(client.swirl, portalTransform(po, spin), w, h, c[1], c[2], c[3], 0.9, true, true)
				DrawSprite(client.swirl, portalTransform(po, -spin * 0.6), w * 0.8, h * 0.8, c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 0.7, true, true)
				local pulse = 1 + 0.06 * math.sin(client.t * 6 + i)
				DrawSprite(client.rim, portalTransform(po, 0), w * 1.15 * pulse, h * 1.1 * pulse, c[1], c[2], c[3], 1.0, true, true)
				PointLight(Vec(po.x + po.nx * 0.4, po.y + po.ny * 0.4, po.z + po.nz * 0.4), c[1], c[2], c[3], 1.2)
				if hum > 0 then PlayLoop(client.hum, Vec(po.x, po.y, po.z), hum, true, i == 1 and 1.0 or 0.85) end
			end
		end
	end

	if GetPlayerTool() == TOOL and GetPlayerCanUseTool() and InputPressed("r") then
		ServerCall("server.resetCmd", me)
	end

	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local a = client.anim[p]
			if not a then a = ToolAnimator() client.anim[p] = a end
			tickToolAnimator(a, dt, nil, p)
			local tb = GetToolBody(p)
			local pr = shared.pairs[p]
			if tb ~= 0 and pr then
				local shapes = GetBodyShapes(tb)
				local glow = 0.6 + 0.4 * math.sin(client.t * 5)
				for i = 1, #shapes do SetShapeEmissiveScale(shapes[i], glow) end
			end
		end
	end
end

-- rim particles and fizzles at a fixed rate
function client.update(dt)
	for owner, pr in pairs(shared.pairs) do
		for i = 1, 2 do
			local po = pr[i]
			if po.active then
				local c = COLORS[i]
				ParticleReset()
				ParticleType("plain")
				ParticleColor(c[1], c[2], c[3], c[1] * 0.5, c[2] * 0.5, c[3] * 0.5)
				ParticleRadius(0.04, 0.0)
				ParticleAlpha(1, 0)
				ParticleGravity(0)
				ParticleDrag(0.5)
				ParticleEmissive(6, 0)
				ParticleCollide(0)
				for k = 1, 3 do
					local a = math.random() * 6.2832
					local ex = math.cos(a) * po.hw
					local ey = math.sin(a) * po.hh
					local p = Vec(po.x + po.rx * ex + po.ux * ey + po.nx * 0.05, po.y + po.ry * ex + po.uy * ey + po.ny * 0.05, po.z + po.rz * ex + po.uz * ey + po.nz * 0.05)
					local v = Vec(po.nx * 0.6 + po.rx * ex, po.ny * 0.6 + po.ry * ex + po.uy * ey * 0.5, po.nz * 0.6 + po.rz * ex)
					SpawnParticle(p, v, 0.5)
				end
			end
		end
	end
	if client.fizzle then
		local p = client.fizzle
		client.fizzle = nil
		ParticleReset()
		ParticleType("plain")
		ParticleColor(0.8, 0.9, 1.0)
		ParticleRadius(0.03, 0)
		ParticleEmissive(5, 0)
		ParticleGravity(-5)
		for k = 1, 16 do SpawnParticle(p, GetRandomDirection(3), 0.4) end
	end
end

function client.draw(dt)
	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or not GetPlayerCanUseTool() then return end
	local pr = shared.pairs[GetLocalPlayer()]
	UiPush()
		-- crosshair halves: filled when that portal exists
		UiTranslate(UiCenter(), UiMiddle())
		for i = 1, 2 do
			local c = COLORS[i]
			local on = pr and pr[i].active
			UiPush()
				UiTranslate(i == 1 and -14 or 14, 0)
				UiAlign("center middle")
				UiColor(c[1], c[2], c[3], on and 1 or 0.35)
				UiRect(6, on and 22 or 14)
			UiPop()
		end
	UiPop()
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 160)
		UiAlign("center middle")
		UiTextShadow(0, 0, 0, 0.6, 1.5)
		UiFont("regular.ttf", 22)
		UiColor(1, 1, 1, 0.9)
		UiText(tr("LMB: blue portal    RMB: orange portal    R: close both", "ЛКМ: синий портал    ПКМ: оранжевый    R: закрыть оба"))
	UiPop()
end
