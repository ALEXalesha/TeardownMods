#version 2
-- Mover / Перемещатель
-- Gizmo gun: grab any dynamic body (props, debris, vehicles), carry it, push and
-- pull it along the view, rotate it on three axes with optional snapping,
-- freeze/unfreeze it in place, clone it, resample it x2 / x0.5 and undo moves.
--
-- Input is read on the client (keys are not replicated for remote players) and
-- sent to the server with ServerCall; the server owns the held state, moves the
-- bodies with ConstrainPosition/ConstrainOrientation (or SetBodyTransform for
-- frozen bodies) and publishes per-player state in shared.pl[p].

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "mover"
local MAX_FROZEN = 64
local MAX_UNDO = 12
local CLONE_MAX_SHAPES = 16
local CLONE_MAX_VOXELS = 150000
local SCALE_MAX_SHAPES = 8
local SCALE_MAX_CELLS = 60000      -- source cells read per scale job
local SCALE_MAX_DIM = 128
local SCALE_READS_PER_UPDATE = 2500
local PLACEHOLDER = "<body dynamic='false'><voxbox size='1 1 1'/></body>"

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		maxDist = clamp(getF("maxdist", 40), 5, 100),
		speed = clamp(getF("speed", 20), 5, 40),
		posSnap = clamp(getF("possnap", 0), 0, 1),
		rotSnap = clamp(getF("rotsnap", 0), 0, 90),
		rotSpeed = clamp(getF("rotspeed", 90), 30, 360),
		clone = getB("clone", true),
		scale = getB("scale", true),
		help = getB("help", true),
	}
end

local function yawQuat(p)
	local fwd = TransformToParentVec(GetPlayerEyeTransform(p), Vec(0, 0, -1))
	local yaw = math.deg(math.atan2(-fwd[1], -fwd[3]))
	return yaw
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Mover", "Перемещатель"), "MOD/prefab/tool.xml", 6)
	server.held = {}
	server.undo = {}
	server.jobs = {}
	shared.pl = {}
	shared.frozen = {}
	shared.frozenCount = 0
end

local function pl(p)
	local s = shared.pl[p]
	if not s then
		s = { held = 0, lx = 0, ly = 0, lz = 0, dist = 0, n = 0, ev = "", ex = 0, ey = 0, ez = 0, msg = "", mn = 0, job = -1 }
		shared.pl[p] = s
	end
	return s
end

local function event(p, kind, pos)
	local s = pl(p)
	s.n = s.n + 1
	s.ev = kind
	if pos then s.ex, s.ey, s.ez = pos[1], pos[2], pos[3] end
end

local function message(p, code)
	local s = pl(p)
	s.mn = s.mn + 1
	s.msg = code
end

local function pushUndo(p, entry)
	local u = server.undo[p]
	if not u then u = {} server.undo[p] = u end
	u[#u + 1] = entry
	if #u > MAX_UNDO then table.remove(u, 1) end
end

-- vehicles are moved by their main body; the wheels follow through their joints
local function rootBody(body)
	local v = GetBodyVehicle(body)
	if v ~= 0 then
		local vb = GetVehicleBody(v)
		if vb ~= 0 then return vb end
	end
	return body
end

-- drop destroyed bodies from the frozen list and recount it
local function pruneFrozen()
	local n = 0
	for b in pairs(shared.frozen) do
		if IsHandleValid(b) then n = n + 1 else shared.frozen[b] = nil end
	end
	shared.frozenCount = n
end

local function movable(body)
	if body == 0 or not IsHandleValid(body) then return false end
	if body == GetWorldBody() then return false end
	if GetBodyPlayer(body) ~= 0 then return false end
	return IsBodyDynamic(body) or shared.frozen[body] == true
end

function server.tick(dt)
	for p in PlayersAdded() do
		SetToolEnabled(TOOL, true, p)
		pl(p)
	end
	for p in PlayersRemoved() do
		-- a resample job of a player who left: drop its half-built copy
		local job = server.jobs[p]
		if job and IsHandleValid(job.nb) then Delete(job.nb) end
		server.jobs[p] = nil
		server.held[p] = nil
		server.undo[p] = nil
		shared.pl[p] = nil
	end
	server.pruneT = (server.pruneT or 0) + 1
	if server.pruneT >= 5 then
		server.pruneT = 0
		pruneFrozen()
	end
	for p in Players() do
		if server.held[p] and (GetPlayerTool(p) ~= TOOL or not GetPlayerCanUseTool(p)) then
			server.release(p)
		end
	end
end

function server.grab(p, body, hx, hy, hz, dist)
	if server.held[p] then return end
	body = rootBody(body)
	if not movable(body) then
		message(p, "nothing")
		return
	end
	for q, h in pairs(server.held) do
		if h.body == body then
			message(p, "taken")
			return
		end
	end
	local s = readSettings()
	local bt = GetBodyTransform(body)
	local hit = Vec(hx, hy, hz)
	local yaw = yawQuat(p)
	server.held[p] = {
		body = body,
		localPoint = TransformToLocalPoint(bt, hit),
		dist = clamp(dist, 1.0, s.maxDist),
		rotOffset = QuatRotateQuat(QuatEuler(0, -yaw, 0), bt.rot),
		spin = { 0, 0, 0 },
		s = s,
	}
	pushUndo(p, { kind = "move", body = body, t = TransformCopy(bt), dyn = IsBodyDynamic(body) })
	local st = pl(p)
	st.held = body
	local lp = server.held[p].localPoint
	st.lx, st.ly, st.lz = lp[1], lp[2], lp[3]
	st.dist = server.held[p].dist
	event(p, "grab", hit)
end

function server.release(p)
	local h = server.held[p]
	if not h then return end
	server.held[p] = nil
	local st = pl(p)
	st.held = 0
	if IsHandleValid(h.body) then
		if IsBodyDynamic(h.body) then
			local v = GetBodyVelocity(h.body)
			local sp = VecLength(v)
			if sp > 10 then SetBodyVelocity(h.body, VecScale(v, 10 / sp)) end
		end
		event(p, "release", GetBodyTransform(h.body).pos)
	end
end

function server.wheel(p, value)
	local h = server.held[p]
	if not h then return end
	h.dist = clamp(h.dist + value * math.max(0.5, h.dist * 0.08), 1.0, h.s.maxDist)
	pl(p).dist = h.dist
end

local AXES = { Vec(0, 1, 0), Vec(1, 0, 0), Vec(0, 0, 1) }

function server.rotate(p, axis, degrees)
	local h = server.held[p]
	if not h or not AXES[axis] then return end
	h.rotOffset = QuatRotateQuat(QuatAxisAngle(AXES[axis], degrees), h.rotOffset)
	event(p, "tick")
end

function server.spin(p, axis, dir)
	local h = server.held[p]
	if not h or not AXES[axis] then return end
	h.spin[axis] = clamp(dir, -1, 1)
end

function server.freeze(p, body)
	body = rootBody(body)
	if not movable(body) then
		message(p, "nothing")
		return
	end
	local bt = GetBodyTransform(body)
	if shared.frozen[body] then
		shared.frozen[body] = nil
		shared.frozenCount = shared.frozenCount - 1
		SetBodyDynamic(body, true)
		SetBodyActive(body, true)
		event(p, "unfreeze", bt.pos)
	else
		if shared.frozenCount >= MAX_FROZEN then pruneFrozen() end
		if shared.frozenCount >= MAX_FROZEN then
			message(p, "toomanyfrozen")
			return
		end
		pushUndo(p, { kind = "move", body = body, t = TransformCopy(bt), dyn = true })
		SetBodyVelocity(body, Vec(0, 0, 0))
		SetBodyAngularVelocity(body, Vec(0, 0, 0))
		SetBodyDynamic(body, false)
		shared.frozen[body] = true
		shared.frozenCount = shared.frozenCount + 1
		event(p, "freeze", bt.pos)
	end
end

function server.undoLast(p)
	local u = server.undo[p]
	if not u or #u == 0 then
		message(p, "undoempty")
		return
	end
	local e = table.remove(u)
	if server.held[p] and server.held[p].body == e.body then server.release(p) end
	if e.kind == "clone" then
		if IsHandleValid(e.body) then Delete(e.body) end
		event(p, "undo", e.pos)
		return
	end
	if not IsHandleValid(e.body) then
		message(p, "undogone")
		return
	end
	if shared.frozen[e.body] and e.dyn then
		shared.frozen[e.body] = nil
		shared.frozenCount = shared.frozenCount - 1
	end
	SetBodyTransform(e.body, e.t)
	if e.dyn then
		SetBodyDynamic(e.body, true)
		SetBodyVelocity(e.body, Vec(0, 0, 0))
		SetBodyAngularVelocity(e.body, Vec(0, 0, 0))
		SetBodyActive(e.body, true)
	end
	event(p, "undo", e.t.pos)
end

-- copy every shape of a body onto a new body next to it
function server.clone(p, body)
	local s = readSettings()
	if not s.clone then message(p, "clonedisabled") return end
	body = rootBody(body)
	if not movable(body) then message(p, "nothing") return end
	if GetBodyVehicle(body) ~= 0 then message(p, "novehicle") return end
	local shapes = GetBodyShapes(body)
	if #shapes == 0 or #shapes > CLONE_MAX_SHAPES then message(p, "toobig") return end
	local total = 0
	for i = 1, #shapes do total = total + GetShapeVoxelCount(shapes[i]) end
	if total > CLONE_MAX_VOXELS then message(p, "toobig") return end
	local bt = GetBodyTransform(body)
	local bmin, bmax = GetBodyBounds(body)
	local right = TransformToParentVec(GetPlayerEyeTransform(p), Vec(1, 0, 0))
	right = VecNormalize(Vec(right[1], 0, right[3]))
	local width = math.max(bmax[1] - bmin[1], bmax[3] - bmin[3])
	local t = Transform(VecAdd(bt.pos, VecScale(right, width + 0.3)), bt.rot)
	local ents = Spawn(PLACEHOLDER, t, true)
	local nb, placeholder = 0, 0
	for i = 1, #ents do
		local ty = GetEntityType(ents[i])
		if ty == "body" and nb == 0 then nb = ents[i] elseif ty == "shape" and placeholder == 0 then placeholder = ents[i] end
	end
	if nb == 0 then message(p, "failed") return end
	for i = 1, #shapes do
		local ns = CreateShape(nb, GetShapeLocalTransform(shapes[i]), shapes[i])
		CopyShapeContent(shapes[i], ns)
	end
	if placeholder ~= 0 then Delete(placeholder) end
	SetBodyDynamic(nb, true)
	SetBodyActive(nb, true)
	pushUndo(p, { kind = "clone", body = nb, pos = t.pos })
	event(p, "clone", t.pos)
end

-- voxel resampling x2 / x0.5, spread over several physics steps
function server.scale(p, body, factor)
	local s = readSettings()
	if not s.scale then message(p, "scaledisabled") return end
	if server.jobs[p] then message(p, "scalebusy") return end
	body = rootBody(body)
	if not movable(body) then message(p, "nothing") return end
	if GetBodyVehicle(body) ~= 0 then message(p, "novehicle") return end
	if factor ~= 2 and factor ~= 0.5 then return end
	local shapes = GetBodyShapes(body)
	if #shapes == 0 or #shapes > SCALE_MAX_SHAPES then message(p, "toobig") return end
	local cells = 0
	local list = {}
	for i = 1, #shapes do
		local sx, sy, sz = GetShapeSize(shapes[i])
		local nx = math.max(1, math.floor(sx * factor))
		local ny = math.max(1, math.floor(sy * factor))
		local nz = math.max(1, math.floor(sz * factor))
		if nx > SCALE_MAX_DIM or ny > SCALE_MAX_DIM or nz > SCALE_MAX_DIM then message(p, "toobig") return end
		cells = cells + sx * sy * sz
		list[#list + 1] = { src = shapes[i], sx = sx, sy = sy, sz = sz, nx = nx, ny = ny, nz = nz }
	end
	if cells > SCALE_MAX_CELLS then message(p, "toobig") return end
	if server.held[p] and server.held[p].body == body then server.release(p) end
	local bt = GetBodyTransform(body)
	local ents = Spawn(PLACEHOLDER, bt, true)
	local nb, placeholder = 0, 0
	for i = 1, #ents do
		local ty = GetEntityType(ents[i])
		if ty == "body" and nb == 0 then nb = ents[i] elseif ty == "shape" and placeholder == 0 then placeholder = ents[i] end
	end
	if nb == 0 then message(p, "failed") return end
	for i = 1, #list do
		local e = list[i]
		local lt = GetShapeLocalTransform(e.src)
		e.dst = CreateShape(nb, Transform(VecScale(lt.pos, factor), lt.rot), e.src)
		ResizeShape(e.dst, 0, 0, 0, e.nx - 1, e.ny - 1, e.nz - 1)
		SetShapeCollisionFilter(e.dst, 0, 0)
	end
	if placeholder ~= 0 then Delete(placeholder) end
	server.jobs[p] = {
		old = body, nb = nb, list = list, factor = factor, si = 1, x = 0, y = 0, z = 0,
		done = 0, total = 0, wasDynamic = IsBodyDynamic(body), oldMin = nil,
	}
	local job = server.jobs[p]
	for i = 1, #list do
		local e = list[i]
		job.total = job.total + e.nx * e.ny * e.nz
	end
	job.oldMin, job.oldMax = GetBodyBounds(body)
	pl(p).job = 0
	event(p, "scale", bt.pos)
end

-- reads one destination row (x = 0..nx-1) and draws runs of equal material
local function scaleRow(job, e, y, z)
	local f = job.factor
	local reads = 0
	local runStart, runEntry = -1, 0
	local function flush(xEnd)
		if runStart >= 0 and runEntry ~= 0 then
			SetBrush("cube", 1, runEntry)
			DrawShapeBox(e.dst, runStart, y, z, xEnd, y, z)
		end
	end
	for x = 0, e.nx do
		local entry = 0
		if x < e.nx then
			if f == 2 then
				local _, _, _, _, _, en = GetShapeMaterialAtIndex(e.src, math.floor(x / 2), math.floor(y / 2), math.floor(z / 2))
				entry = en
				reads = reads + 1
			else
				for k = 0, 7 do
					local dx, dy, dz = k % 2, math.floor(k / 2) % 2, math.floor(k / 4)
					local _, _, _, _, _, en = GetShapeMaterialAtIndex(e.src, x * 2 + dx, y * 2 + dy, z * 2 + dz)
					reads = reads + 1
					if en ~= 0 then entry = en break end
				end
			end
		end
		if entry ~= runEntry or x == e.nx then
			flush(x - 1)
			runStart, runEntry = x, entry
		end
	end
	return reads
end

function server.updateJob(p, job)
	local budget = SCALE_READS_PER_UPDATE
	while budget > 0 do
		local e = job.list[job.si]
		if not e then
			server.finishJob(p, job)
			return
		end
		budget = budget - scaleRow(job, e, job.y, job.z)
		job.done = job.done + e.nx
		job.y = job.y + 1
		if job.y >= e.ny then
			job.y = 0
			job.z = job.z + 1
			if job.z >= e.nz then
				job.z = 0
				job.si = job.si + 1
			end
		end
	end
	pl(p).job = clamp(job.done / math.max(1, job.total), 0, 0.99)
end

function server.finishJob(p, job)
	server.jobs[p] = nil
	pl(p).job = -1
	if not IsHandleValid(job.nb) then return end
	for i = 1, #job.list do
		SetShapeCollisionFilter(job.list[i].dst, 1, 255)
	end
	-- keep the bottom centre where the old body stood
	local nmin, nmax = GetBodyBounds(job.nb)
	local oldBottom = Vec((job.oldMin[1] + job.oldMax[1]) * 0.5, job.oldMin[2], (job.oldMin[3] + job.oldMax[3]) * 0.5)
	local newBottom = Vec((nmin[1] + nmax[1]) * 0.5, nmin[2], (nmin[3] + nmax[3]) * 0.5)
	local t = GetBodyTransform(job.nb)
	t.pos = VecAdd(t.pos, VecAdd(VecSub(oldBottom, newBottom), Vec(0, 0.02, 0)))
	SetBodyTransform(job.nb, t)
	if IsHandleValid(job.old) then
		if shared.frozen[job.old] then
			shared.frozen[job.old] = nil
			shared.frozenCount = shared.frozenCount - 1
		end
		Delete(job.old)
	end
	if job.wasDynamic then
		SetBodyDynamic(job.nb, true)
		SetBodyActive(job.nb, true)
	else
		shared.frozen[job.nb] = true
		shared.frozenCount = shared.frozenCount + 1
	end
	event(p, "scaled", t.pos)
end

function server.update(dt)
	for p, h in pairs(server.held) do
		if not IsHandleValid(h.body) then
			server.release(p)
		else
			server.moveHeld(p, h, dt)
		end
	end
	for p, job in pairs(server.jobs) do
		server.updateJob(p, job)
	end
end

function server.moveHeld(p, h, dt)
	local s = h.s
	for axis = 1, 3 do
		if h.spin[axis] ~= 0 then
			h.rotOffset = QuatRotateQuat(QuatAxisAngle(AXES[axis], h.spin[axis] * s.rotSpeed * dt), h.rotOffset)
		end
	end
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	local yaw = yawQuat(p)
	if s.rotSnap > 0 then yaw = math.floor(yaw / s.rotSnap + 0.5) * s.rotSnap end
	local rot = QuatRotateQuat(QuatEuler(0, yaw, 0), h.rotOffset)
	local target = VecAdd(eye.pos, VecScale(fwd, h.dist))
	-- body origin that puts the grab point on the target
	local origin = VecSub(target, QuatRotateVec(rot, h.localPoint))
	if s.posSnap > 0 then
		local g = s.posSnap
		origin = Vec(math.floor(origin[1] / g + 0.5) * g, math.floor(origin[2] / g + 0.5) * g, math.floor(origin[3] / g + 0.5) * g)
	end
	if shared.frozen[h.body] then
		SetBodyTransform(h.body, Transform(origin, rot))
	else
		local bt = GetBodyTransform(h.body)
		local mass = math.max(GetBodyMass(h.body), 1)
		local grabWorld = TransformToParentPoint(bt, h.localPoint)
		local targetPoint = VecAdd(origin, QuatRotateVec(rot, h.localPoint))
		ConstrainPosition(h.body, 0, grabWorld, targetPoint, s.speed, mass * 40)
		ConstrainOrientation(h.body, 0, bt.rot, rot, 6, mass * 20)
	end
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

local MESSAGES = {
	nothing = { "Nothing movable here", "Здесь нечего двигать" },
	taken = { "Another player holds it", "Это держит другой игрок" },
	toomanyfrozen = { "Too many frozen objects (64)", "Слишком много замороженных (64)" },
	undoempty = { "Nothing to undo", "Нечего отменять" },
	undogone = { "That object no longer exists", "Этого предмета уже нет" },
	novehicle = { "Not for vehicles", "Не для машин" },
	toobig = { "Too big for this", "Слишком большой" },
	failed = { "Could not create it", "Не получилось создать" },
	clonedisabled = { "Cloning is off in options", "Клонирование выключено в настройках" },
	scaledisabled = { "Scaling is off in options", "Масштаб выключен в настройках" },
	scalebusy = { "Scaling in progress", "Масштаб ещё идёт" },
}

local KEYS_ROT = { { "q", 1, -1 }, { "r", 1, 1 }, { "z", 2, -1 }, { "x", 2, 1 }, { "v", 3, -1 }, { "b", 3, 1 } }
local KEY_CLONE = "p"

function client.init()
	client.snd = {}
	for _, n in ipairs({ "grab", "release", "freeze", "unfreeze", "clone", "tick", "undo", "error", "scale" }) do
		client.snd[n] = LoadSound("MOD/snd/" .. n .. ".ogg")
	end
	client.hold = LoadLoop("MOD/snd/hold.ogg")
	client.anim = {}
	client.seenN = {}
	client.seenMsg = {}
	client.msgText = ""
	client.msgT = 0
	client.aimBody = 0
	client.holding = false
	client.spinning = {}
	client.t = 0
end

local function localHeld()
	local s = shared.pl[GetLocalPlayer()]
	if s then return s.held, s end
	return 0, nil
end

function client.aim()
	local cam = GetPlayerCameraTransform()
	local fwd = TransformToParentVec(cam, Vec(0, 0, -1))
	local maxDist = clamp(getF("maxdist", 40), 5, 100)
	QueryRequire("physical")
	QueryRejectPlayer(GetLocalPlayer())
	local hit, dist, _, shape = QueryRaycast(cam.pos, fwd, maxDist)
	if hit and shape ~= 0 then
		local b = GetShapeBody(shape)
		local v = GetBodyVehicle(b)
		if v ~= 0 then b = GetVehicleBody(v) end
		if b ~= 0 and b ~= GetWorldBody() and (IsBodyDynamic(b) or shared.frozen[b]) and GetBodyPlayer(b) == 0 then
			return b, VecAdd(cam.pos, VecScale(fwd, dist)), dist
		end
	end
	return 0, nil, 0
end

function client.tick(dt)
	client.t = client.t + dt
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local me = GetLocalPlayer()

	-- events from the server -> sounds
	for p, s in pairs(shared.pl) do
		if client.seenN[p] ~= s.n then
			if client.seenN[p] ~= nil and client.snd[s.ev] then
				PlaySound(client.snd[s.ev], Vec(s.ex, s.ey, s.ez), 0.8)
			elseif client.seenN[p] ~= nil and s.ev == "scaled" then
				PlaySound(client.snd.clone, Vec(s.ex, s.ey, s.ez), 0.8)
			end
			client.seenN[p] = s.n
		end
		if p == me and client.seenMsg[p] ~= s.mn then
			if client.seenMsg[p] ~= nil and MESSAGES[s.msg] then
				client.msgText = tr(MESSAGES[s.msg][1], MESSAGES[s.msg][2])
				client.msgT = 2.5
				PlaySound(client.snd.error, nil, 0.6)
			end
			client.seenMsg[p] = s.mn
		end
	end
	client.msgT = math.max(0, client.msgT - dt)

	local held = localHeld()
	local active = GetPlayerTool() == TOOL and GetPlayerCanUseTool() and GetPlayerVehicle() == 0
	client.aimBody = 0
	if active then
		local b, hitPos, dist = client.aim()
		client.aimBody = b
		if InputPressed("usetool") and held == 0 then
			if b ~= 0 then
				ServerCall("server.grab", me, b, hitPos[1], hitPos[2], hitPos[3], dist)
			else
				client.msgText = tr(MESSAGES.nothing[1], MESSAGES.nothing[2])
				client.msgT = 1.5
			end
		end
		if InputReleased("usetool") and held ~= 0 then
			ServerCall("server.release", me)
		end
		if held ~= 0 then
			SetBool("game.input.locktool", true)
			local w = InputValue("mousewheel")
			if w ~= 0 then ServerCall("server.wheel", me, w) end
			local snap = clamp(getF("rotsnap", 0), 0, 90)
			for i = 1, #KEYS_ROT do
				local k = KEYS_ROT[i]
				if snap > 0 then
					if InputPressed(k[1]) then ServerCall("server.rotate", me, k[2], k[3] * snap) end
				else
					if InputPressed(k[1]) then
						ServerCall("server.spin", me, k[2], k[3])
						client.spinning[k[1]] = true
					elseif client.spinning[k[1]] and not InputDown(k[1]) then
						ServerCall("server.spin", me, k[2], 0)
						client.spinning[k[1]] = nil
					end
				end
			end
		end
		local target = held ~= 0 and held or b
		if InputPressed("t") then
			if target ~= 0 then ServerCall("server.freeze", me, target) end
		end
		-- clone on P, not G: G is Gravity Change's key, which works with any tool (16.10,
		-- _shared/tdlib/keymap.py); P is the only letter no always-active mod key uses
		if InputPressed(KEY_CLONE) and target ~= 0 then ServerCall("server.clone", me, target) end
		if InputPressed("n") and target ~= 0 then ServerCall("server.scale", me, target, 0.5) end
		if InputPressed("m") and target ~= 0 then ServerCall("server.scale", me, target, 2) end
		if InputPressed("u") then ServerCall("server.undoLast", me) end
	end
	-- stop any spin when keys are no longer held or the tool was put away
	for k in pairs(client.spinning) do
		if not active or held == 0 then
			for i = 1, #KEYS_ROT do
				if KEYS_ROT[i][1] == k then ServerCall("server.spin", me, KEYS_ROT[i][2], 0) end
			end
			client.spinning[k] = nil
		end
	end

	-- tool animation for every player holding the gizmo gun
	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local a = client.anim[p]
			if not a then a = ToolAnimator() client.anim[p] = a end
			local s = shared.pl[p]
			local h = s and s.held ~= 0
			a.forceActionPose = h
			a.offsetTransform = Transform(Vec(0, 0, h and 0.03 or 0))
			tickToolAnimator(a, dt, nil, p)
			local tb = GetToolBody(p)
			if tb ~= 0 then
				local shapes = GetBodyShapes(tb)
				local glow = h and (1.2 + 0.4 * math.sin(client.t * 12)) or 0.6
				for i = 1, #shapes do SetShapeEmissiveScale(shapes[i], glow) end
			end
		end
	end
end

function client.render(dt)
	local me = GetLocalPlayer()
	-- outlines: frozen (blue), aimed (white), held (cyan) and beams
	local n = 0
	for b in pairs(shared.frozen) do
		if IsHandleValid(b) then
			DrawBodyOutline(b, 0.3, 0.6, 1.0, 0.6)
			n = n + 1
			if n >= 32 then break end
		end
	end
	if client.aimBody ~= 0 and localHeld() == 0 then
		DrawBodyOutline(client.aimBody, 1, 1, 1, 0.5)
	end
	for p, s in pairs(shared.pl) do
		if s.held ~= 0 and IsHandleValid(s.held) then
			local bt = GetBodyTransform(s.held)
			local gp = TransformToParentPoint(bt, Vec(s.lx, s.ly, s.lz))
			DrawBodyOutline(s.held, 0.3, 1.0, 1.0, 1.0)
			local mt = GetToolLocationWorldTransform("muzzle", p)
			local from = mt and mt.pos or GetPlayerEyeTransform(p).pos
			local last = from
			for i = 1, 12 do
				local t = i / 12
				local pt = VecLerp(from, gp, t)
				if i < 12 then pt = VecAdd(pt, VecScale(GetRandomDirection(1), 0.04 * math.sin(t * 3.14))) end
				DrawLine(last, pt, 0.4, 1.0, 1.0, 0.8)
				last = pt
			end
			PointLight(from, 0.3, 1.0, 1.0, 0.8)
			PlayLoop(client.hold, gp, 0.5, true, 1.0)
		end
	end
end

local function keyRow(k, text)
	UiPush()
		UiAlign("center middle")
		UiColor(1, 1, 1, 0.15)
		UiRoundedRect(70, 26, 5)
		UiColor(1, 1, 1, 1)
		UiFont("bold.ttf", 18)
		UiText(k)
	UiPop()
	UiPush()
		UiTranslate(46, 0)
		UiAlign("left middle")
		UiFont("regular.ttf", 18)
		UiColor(1, 1, 1, 0.85)
		UiText(text)
	UiPop()
end

function client.draw(dt)
	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or GetBool("game.player.usescreen") or not GetPlayerCanUseTool() then return end
	local held, s = localHeld()
	if getB("help", true) then
		local rows = {
			{ tr("LMB", "ЛКМ"), held ~= 0 and tr("release", "отпустить") or tr("hold to grab", "держать: схватить") },
			{ tr("Wheel", "Колесо"), tr("push / pull", "дальше / ближе") },
			{ "Q / R", tr("rotate (yaw)", "поворот (рыскание)") },
			{ "Z / X", tr("tilt (pitch)", "наклон (тангаж)") },
			{ "V / B", tr("roll", "крен") },
			{ "T", tr("freeze / unfreeze", "заморозить / разморозить") },
			{ string.upper(KEY_CLONE), tr("clone", "клонировать") },
			{ "N / M", tr("scale x0.5 / x2", "масштаб x0,5 / x2") },
			{ "U", tr("undo last move", "отменить ход") },
		}
		UiPush()
			UiTranslate(UiWidth() - 360, UiHeight() / 2 - 140)
			UiColor(0, 0, 0, 0.45)
			UiAlign("left top")
			UiRoundedRect(330, 30 + #rows * 30, 8)
			UiTranslate(50, 30)
			for i = 1, #rows do
				keyRow(rows[i][1], rows[i][2])
				UiTranslate(0, 30)
			end
		UiPop()
	end
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 150)
		UiAlign("center middle")
		UiTextShadow(0, 0, 0, 0.6, 1.5)
		if held ~= 0 and s then
			UiFont("regular.ttf", 20)
			UiColor(0.5, 1, 1, 0.9)
			local frozen = shared.frozen[held] and tr("  (frozen)", "  (заморожен)") or ""
			UiText(string.format(tr("Holding at %.1f m", "Держу на %.1f м"), s.dist) .. frozen)
		end
		if s and s.job and s.job >= 0 then
			UiTranslate(0, 28)
			UiColor(0, 0, 0, 0.5)
			UiRect(260, 12)
			UiAlign("left middle")
			UiTranslate(-128, 0)
			UiColor(1, 0.7, 0.2, 1)
			UiRect(256 * s.job, 8)
			UiAlign("center middle")
			UiTranslate(128, 20)
			UiFont("regular.ttf", 16)
			UiColor(1, 1, 1, 0.8)
			UiText(tr("Resampling voxels...", "Пересчёт вокселей..."))
		end
		if client.msgT > 0 then
			UiTranslate(0, 30)
			UiFont("bold.ttf", 22)
			UiColor(1, 0.6, 0.3, math.min(1, client.msgT))
			UiText(client.msgText)
		end
	UiPop()
end
