#version 2
-- Cutter / Резак
-- Angle-grinder tool. Hold LMB on a surface, sweep, release: the saw cuts a
-- straight kerf from the press point to the release point. The cut is a row of
-- small MakeHole calls that march into the material until they come out the
-- other side (or reach the max depth), spread over frames with a hole budget.
--
-- MakeHole radii: soft (glass, wood, plastic, plaster, foliage), medium
-- (concrete, brick, weak metal), hard (hard metal, hard masonry). Medium is one
-- class in the engine, so concrete/brick vs metal is told apart per point with
-- GetShapeMaterialAtPosition: masonry costs more budget (cuts slower).

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "cutter"
local MAX_JOBS = 4
local SOFT = { glass = true, wood = true, plastic = true, plaster = true, foliage = true }
local MASONRY = { masonry = true }
local METAL = { metal = true }
local HARD = { hardmetal = true, hardmasonry = true, heavymetal = true }

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		radius = clamp(getF("kerf", 0.2), 0.1, 0.4) * 0.5,
		depth = clamp(getF("depth", 1.0), 0.2, 3),
		maxLen = clamp(getF("maxlen", 4), 0.5, 10),
		reach = clamp(getF("reach", 6), 2, 15),
		budget = math.floor(clamp(getF("budget", 12), 4, 40)),
		metal = getB("metal", true),
		masonry = getB("masonry", true),
		masonryCost = clamp(getF("masonrycost", 3), 1, 6),
		hard = getB("hard", false),
		sparks = getB("sparks", true),
	}
end

-- material class code shared with the client for effects: 1 soft, 2 metal, 3 masonry, 4 hard, 0 none
local function classOf(mat)
	if SOFT[mat] then return 1 elseif METAL[mat] then return 2 elseif MASONRY[mat] then return 3 elseif HARD[mat] then return 4 end
	return 0
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Cutter", "Резак"), "MOD/prefab/tool.xml", 6)
	server.players = {}
	server.jobs = {}
	server.nextJob = 1
	shared.pl = {}
	shared.jobs = {}
end

local function aim(p, reach)
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	QueryRejectPlayer(p)
	QueryRequire("physical")
	local hit, dist, normal, shape = QueryRaycast(eye.pos, fwd, reach)
	return hit, VecAdd(eye.pos, VecScale(fwd, dist)), normal, shape, eye.pos, fwd
end

function server.tick(dt)
	for p in PlayersAdded() do
		SetToolEnabled(TOOL, true, p)
		server.players[p] = { holding = false }
		shared.pl[p] = { holding = false, sx = 0, sy = 0, sz = 0, ex = 0, ey = 0, ez = 0, len = 0, msg = 0 }
	end
	for p in PlayersRemoved() do
		server.players[p] = nil
		shared.pl[p] = nil
	end
	for p in Players() do server.tickPlayer(p) end
end

function server.tickPlayer(p)
	local st = server.players[p]
	if not st then
		st = { holding = false }
		server.players[p] = st
		shared.pl[p] = { holding = false, sx = 0, sy = 0, sz = 0, ex = 0, ey = 0, ez = 0, len = 0, msg = 0 }
	end
	local sp = shared.pl[p]
	if GetPlayerTool(p) ~= TOOL or not GetPlayerCanUseTool(p) or GetPlayerVehicle(p) ~= 0 then
		st.holding = false
		sp.holding = false
		return
	end
	local s = readSettings()
	local hit, point, normal, shape, eyePos, fwd = aim(p, s.reach)
	if InputPressed("usetool", p) then
		if hit then
			st.holding = true
			st.a = point
			st.n = normal
			st.b = point
		else
			sp.msg = sp.msg + 1
		end
	end
	if st.holding then
		-- end point: aim hit, or where the view ray crosses the start surface plane
		local b
		if hit then
			b = point
		else
			local denom = VecDot(fwd, st.n)
			if math.abs(denom) > 0.05 then
				local t = VecDot(VecSub(st.a, eyePos), st.n) / denom
				if t > 0 then b = VecAdd(eyePos, VecScale(fwd, t)) end
			end
			b = b or st.b
		end
		local d = VecSub(b, st.a)
		local l = VecLength(d)
		if l > s.maxLen then b = VecAdd(st.a, VecScale(d, s.maxLen / l)) l = s.maxLen end
		st.b = b
		sp.holding = true
		sp.sx, sp.sy, sp.sz = st.a[1], st.a[2], st.a[3]
		sp.ex, sp.ey, sp.ez = b[1], b[2], b[3]
		sp.len = l
		if InputReleased("usetool", p) or not InputDown("usetool", p) then
			st.holding = false
			sp.holding = false
			server.queue(p, st.a, b, st.n, s)
		end
	end
end

function server.queue(p, a, b, n, s)
	local count = 0
	for _, j in pairs(server.jobs) do if j.owner == p then count = count + 1 end end
	if count >= MAX_JOBS then return end
	local len = VecLength(VecSub(b, a))
	local spacing = s.radius * 1.1
	local id = server.nextJob
	server.nextJob = id + 1
	server.jobs[id] = {
		id = id, owner = p, a = VecCopy(a), b = VecCopy(b), n = VecNormalize(n), len = len,
		points = math.max(1, math.floor(len / spacing) + 1), pi = 0, k = 0, misses = 0, surface = nil, s = s,
		holes = 0,
	}
	shared.jobs[id] = { owner = p, cx = a[1], cy = a[2], cz = a[3], mat = 0, prog = 0, cutting = false }
end

-- find the surface under line point i (the line may cross bumps and gaps)
local function surfaceAt(job, i)
	local u = (job.points > 1) and (i / (job.points - 1)) or 0
	local p = VecAdd(job.a, VecScale(VecSub(job.b, job.a), u))
	local from = VecAdd(p, VecScale(job.n, 0.4))
	QueryRequire("physical")
	local hit, dist, normal, shape = QueryRaycast(from, VecScale(job.n, -1), 0.4 + job.s.depth)
	if not hit then return nil end
	return VecAdd(from, VecScale(job.n, -dist)), shape
end

function server.update(dt)
	for id, job in pairs(server.jobs) do
		server.runJob(job, dt)
	end
end

function server.runJob(job, dt)
	local s = job.s
	local budget = s.budget
	local sj = shared.jobs[job.id]
	local step = s.radius * 1.2
	local maxSteps = math.floor(s.depth / step) + 1
	sj.cutting = false
	while budget > 0 do
		if job.pi >= job.points then
			server.jobs[job.id] = nil
			shared.jobs[job.id] = nil
			return
		end
		if not job.surface then
			local pt, shape = surfaceAt(job, job.pi)
			budget = budget - 0.25
			if not pt then
				job.pi = job.pi + 1
			else
				local mat = GetShapeMaterialAtPosition(shape, VecSub(pt, VecScale(job.n, 0.03)))
				local cls = classOf(mat)
				local r = s.radius
				local r0, r1, r2, cost = r, 0, 0, 1
				if cls == 2 then
					if s.metal then r1 = r else r0 = 0 end
					cost = 1.5
				elseif cls == 3 then
					if s.masonry then r1 = r else r0 = 0 end
					cost = s.masonryCost
				elseif cls == 4 then
					if s.hard then r1, r2 = r, r * 0.9 else r0 = 0 end
					cost = 4
				elseif cls == 0 then
					r0 = 0
				end
				job.surface = { pos = pt, r0 = r0, r1 = r1, r2 = r2, cost = cost, cls = cls }
				job.k = 0
				job.misses = 0
			end
		else
			local sf = job.surface
			if sf.r0 <= 0 or job.k >= maxSteps then
				job.surface = nil
				job.pi = job.pi + 1
			else
				local q = VecSub(sf.pos, VecScale(job.n, job.k * step))
				local removed = MakeHole(q, sf.r0, sf.r1, sf.r2, true)
				job.holes = job.holes + 1
				budget = budget - sf.cost
				sj.cx, sj.cy, sj.cz = q[1], q[2], q[3]
				sj.mat = sf.cls
				sj.cutting = true
				if removed == 0 then job.misses = job.misses + 1 else job.misses = 0 end
				job.k = job.k + 1
				-- two empty steps in a row: we are through the material
				if job.misses >= 2 and job.k >= 2 then
					job.surface = nil
					job.pi = job.pi + 1
				end
			end
		end
	end
	sj.prog = job.pi / job.points
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.snd = {
		spinup = LoadSound("MOD/snd/spinup.ogg"),
		spindown = LoadSound("MOD/snd/spindown.ogg"),
		click = LoadSound("MOD/snd/click.ogg"),
	}
	client.idle = LoadLoop("MOD/snd/idle.ogg")
	client.grind = LoadLoop("MOD/snd/grind.ogg", 15)
	client.anim = {}
	client.disc = {}
	client.angle = 0
	client.spin = 0
	client.wasSpinning = false
	client.msgSeen = nil
	client.msgT = 0
end

local function anyJobOf(p)
	for _, j in pairs(shared.jobs) do if j.owner == p then return true end end
	return false
end

function client.tick(dt)
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil client.disc[p] = nil end
	local me = GetLocalPlayer()
	local sp = shared.pl[me]
	if sp then
		if client.msgSeen ~= nil and sp.msg ~= client.msgSeen then client.msgT = 2 end
		client.msgSeen = sp.msg
	end
	client.msgT = math.max(0, client.msgT - dt)

	-- motor state of the local saw
	local selected = GetPlayerTool() == TOOL and GetPlayerCanUseTool()
	local spinning = selected and (InputDown("usetool") or anyJobOf(me))
	if spinning and not client.wasSpinning then PlaySound(client.snd.spinup, nil, 0.7) end
	if not spinning and client.wasSpinning then PlaySound(client.snd.spindown, nil, 0.6) end
	client.wasSpinning = spinning
	client.spin = spinning and math.min(1, client.spin + dt * 2) or math.max(0, client.spin - dt * 0.8)

	for p in Players() do
		if GetPlayerTool(p) == TOOL then client.animateTool(p, dt) end
	end
	if client.spin > 0.05 and selected then
		PlayLoop(client.idle, GetPlayerEyeTransform().pos, 0.5 * client.spin, true, 0.6 + 0.4 * client.spin)
	end
	-- grinding at every active cut
	for _, j in pairs(shared.jobs) do
		if j.cutting then
			local pitch = ({ 1.15, 1.0, 0.85, 0.75 })[j.mat] or 1
			PlayLoop(client.grind, Vec(j.cx, j.cy, j.cz), 0.9, true, pitch)
			PointLight(Vec(j.cx, j.cy, j.cz), 1.0, 0.6, 0.2, (j.mat == 2 or j.mat == 4) and 1.5 or 0.4)
		end
	end
end

function client.animateTool(p, dt)
	local a = client.anim[p]
	if not a then a = ToolAnimator() client.anim[p] = a end
	local press = InputDown("usetool", p) and 1 or 0
	a.forceActionPose = press > 0
	local shake = 0
	if IsPlayerLocal(p) and client.spin > 0 then shake = 0.003 * client.spin end
	a.offsetTransform = Transform(Vec((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, -0.03 * press))
	tickToolAnimator(a, dt, nil, p)
	local b = GetToolBody(p)
	if b == 0 then return end
	local d = client.disc[p]
	if not d or d.body ~= b then
		d = { body = b }
		local shapes = GetBodyShapes(b)
		for i = 1, #shapes do
			local sx, sy, sz, vs = GetShapeSize(shapes[i])
			if sx == 1 and sy == 11 and sz == 11 then
				d.shape = shapes[i]
				d.t0 = GetShapeLocalTransform(shapes[i])
				d.center = Vec(sx * vs * 0.5, sy * vs * 0.5, sz * vs * 0.5)
			end
		end
		client.disc[p] = d
	end
	if d.shape then
		local speed = IsPlayerLocal(p) and client.spin or press
		client.angle = client.angle + dt * 2400 * speed
		local pivot = Transform(d.center, QuatAxisAngle(Vec(1, 0, 0), client.angle))
		SetShapeLocalTransform(d.shape, TransformToParentTransform(d.t0, TransformToParentTransform(pivot, Transform(VecScale(d.center, -1)))))
	end
end

-- sparks / dust at a fixed rate
function client.update(dt)
	if not getB("sparks", true) then return end
	for _, j in pairs(shared.jobs) do
		if j.cutting then client.emit(Vec(j.cx, j.cy, j.cz), j.mat) end
	end
end

function client.emit(p, mat)
	if mat == 2 or mat == 4 or mat == 3 then
		ParticleReset()
		ParticleType("plain")
		ParticleColor(1.0, 0.75, 0.3, 1.0, 0.3, 0.05)
		ParticleRadius(0.02, 0.005)
		ParticleAlpha(1, 0.6)
		ParticleGravity(-10)
		ParticleDrag(0.1)
		ParticleEmissive(8, 0)
		ParticleStretch(3)
		ParticleCollide(1)
		local n = (mat == 3) and 3 or 8
		for i = 1, n do
			SpawnParticle(p, VecAdd(GetRandomDirection(3 + 5 * math.random()), Vec(0, 2, 0)), 0.4 + 0.6 * math.random())
		end
	end
	if mat == 1 or mat == 3 then
		ParticleReset()
		ParticleType("smoke")
		if mat == 1 then ParticleColor(0.75, 0.62, 0.45) else ParticleColor(0.6, 0.6, 0.58) end
		ParticleRadius(0.05, 0.3)
		ParticleAlpha(0.5, 0)
		ParticleGravity(-1)
		ParticleDrag(0.5)
		ParticleCollide(0)
		for i = 1, 3 do
			SpawnParticle(p, GetRandomDirection(1.5), 1.2)
		end
	end
end

function client.render(dt)
	-- cut preview line and a red laser dot
	for p, sp in pairs(shared.pl) do
		if sp.holding then
			local a = Vec(sp.sx, sp.sy, sp.sz)
			local b = Vec(sp.ex, sp.ey, sp.ez)
			local n = 16
			for i = 0, n - 1, 2 do
				DrawLine(VecLerp(a, b, i / n), VecLerp(a, b, (i + 1) / n), 1, 0.3, 0.1, 1)
			end
			DrawLine(VecAdd(a, Vec(0.05, 0, 0)), VecAdd(a, Vec(-0.05, 0, 0)), 1, 1, 1, 1)
			DrawLine(VecAdd(a, Vec(0, 0.05, 0)), VecAdd(a, Vec(0, -0.05, 0)), 1, 1, 1, 1)
		end
	end
	if GetPlayerTool() == TOOL and GetPlayerCanUseTool() then
		local cam = GetPlayerCameraTransform()
		local fwd = TransformToParentVec(cam, Vec(0, 0, -1))
		QueryRequire("physical")
		QueryRejectPlayer(GetLocalPlayer())
		local hit, dist = QueryRaycast(cam.pos, fwd, clamp(getF("reach", 6), 2, 15))
		if hit then
			local hp = VecAdd(cam.pos, VecScale(fwd, dist - 0.02))
			PointLight(hp, 1, 0.1, 0.05, 0.25)
			DrawLine(VecAdd(hp, Vec(0.03, 0, 0)), VecAdd(hp, Vec(-0.03, 0, 0)), 1, 0.1, 0.1, 1)
			DrawLine(VecAdd(hp, Vec(0, 0.03, 0)), VecAdd(hp, Vec(0, -0.03, 0)), 1, 0.1, 0.1, 1)
		end
	end
end

function client.draw(dt)
	if GetPlayerTool() ~= TOOL then return end
	if GetBool("game.ui.hidemods") or GetBool("game.player.usescreen") or not GetPlayerCanUseTool() then return end
	local sp = shared.pl[GetLocalPlayer()]
	UiPush()
		UiTranslate(UiCenter(), UiHeight() - 160)
		UiAlign("center middle")
		UiTextShadow(0, 0, 0, 0.6, 1.5)
		UiFont("regular.ttf", 22)
		UiColor(1, 1, 1, 0.9)
		if sp and sp.holding then
			UiText(string.format(tr("Cut length %.2f m - release to cut", "Длина реза %.2f м - отпустите, чтобы резать"), sp.len))
		else
			UiText(tr("Hold LMB on a surface, sweep, release to cut", "Зажмите ЛКМ на поверхности, проведите, отпустите - рез"))
		end
		local queued = 0
		local prog = 0
		for _, j in pairs(shared.jobs) do
			if j.owner == GetLocalPlayer() then queued = queued + 1 prog = j.prog end
		end
		if queued > 0 then
			UiTranslate(0, 28)
			UiColor(0, 0, 0, 0.5)
			UiRect(240, 10)
			UiAlign("left middle")
			UiTranslate(-118, 0)
			UiColor(1, 0.55, 0.15, 1)
			UiRect(236 * prog, 6)
			UiAlign("center middle")
			UiTranslate(118, 20)
			UiFont("regular.ttf", 16)
			UiColor(1, 1, 1, 0.8)
			UiText(string.format(tr("Cutting... (%d queued)", "Режу... (в очереди %d)"), queued))
		end
		if client.msgT > 0 then
			UiTranslate(0, 30)
			UiFont("bold.ttf", 20)
			UiColor(1, 0.5, 0.3, math.min(1, client.msgT))
			UiText(tr("Aim at a surface within reach", "Наведите на поверхность ближе"))
		end
	UiPop()
end
