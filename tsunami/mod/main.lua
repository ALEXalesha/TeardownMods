#version 2
-- Tsunami / Цунами
-- Conch horn tool. LMB: a tsunami comes from where you look. A siren warns first
-- while the wave rises on the horizon (and real water in the level, if there is
-- any, turns rough); then a wall of water rolls in at the set speed, carries away
-- loose objects, vehicles and players, tears weak structures (wood, glass, plaster;
-- concrete only a little) along its front, floods the ground behind it, and finally
-- the water runs back (backwash) and drains away. RMB calls the wave off.
--
-- What is real and what is an effect: Teardown's water volumes cannot be raised by
-- scripts (a water entity's surface height is not a settable property), so the wave
-- and the flood are drawn (depth-tested water sprites and foam particles) and their
-- force is applied by the server as a water current: objects below the water surface
-- are dragged towards the flow speed and buoyed up; players likewise. The water has one
-- flat level, measured from the ground where you stood when you called the wave (like
-- the sea rising): valleys flood deeper, hills and roofs above it stay dry. Level
-- water that exists gets real wave, motion and foam through SetProperty, restored
-- at the end.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "tsunami"
local START_DIST = 260       -- the wave starts this far away, along your view
local END_DIST = 200         -- and runs out this far behind you
local HALF_WIDTH = 200
local CREST = 12             -- m: the steep front of the wave
local SURGE = 60             -- m: fast water behind the crest
local WARN_TIME = 7
local RECEDE_TIME = 9
local ACT_RADIUS = 90        -- bodies are moved within this distance of a player
local BODIES_PER_UPDATE = 60
local PROBES_PER_UPDATE = 30
local HOLES_PER_UPDATE = 24
local HOLE_R2_BUDGET = 900      -- per step: sum of hole radius^2 (holes in shells cost ~ area)
local SEG = 10               -- client: wall segment width
local DRAW_HALF = 90         -- client: segments drawn within this lateral distance
local LEAN = 14              -- client: the face leans forward this many degrees
local LEAN_COS, LEAN_TAN = math.cos(math.rad(LEAN)), math.tan(math.rad(LEAN))
local SLICES = { 0.35, 0.7 } -- client: inner slices of the crest, as parts of CREST behind the face
-- client: the flood behind the crest (in-game 10.10: "less 2D, more volumetric"); everything is
-- bounded per frame and centred on the camera, nothing grows with the size of the flooded zone
local SPRITE_CAP = 280            -- all water sprites per frame
local FLOOD_CAP = 150             -- of them: the flood field, its streaks and side walls
local FULL_DETAIL = 40            -- front segments this close to the camera sideways get every sprite
local NEAR_TILE, NEAR_N = 10, 6   -- near field: 6 x 6 tiles of 10 m, a surface and a deep layer
local MID_TILE, MID_N = 20, 3     -- a middle layer, coarser and drifting slower (parallax depth)
local FAR_HALF, FAR_CHUNK = 150, 100 -- far sheets out to 150 m around the camera, pieces up to 100 m
local STREAKS = 16                -- foam and debris streaks drifting with the current
local STREAK_A, STREAK_L = 40, 30 -- their window around the camera, half sizes along / across
local WALL_PIECE, WALL_N = 12, 6  -- side walls: up to 6 pieces of 12 m along the zone's edge
local WALL_NEAR = 70              -- drawn when the camera is this close to the edge
local RAYS_PER_FRAME = 6          -- ground probes per frame for the wall and the side walls

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function rnd(a, b) return a + (b - a) * math.random() end
local function lerp(a, b, t) return a + (b - a) * t end
local function smooth(a, b, x) local t = clamp((x - a) / (b - a), 0, 1) return t * t * (3 - 2 * t) end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end

function readSettings()
	return {
		height = clamp(getF("height", 14), 3, 25),
		speed = clamp(getF("speed", 18), 8, 35),
		flood = clamp(getF("flood", 1.5), 0, 4),
		power = clamp(getF("power", 1.5), 0, 3),
		siren = getB("siren", true),
	}
end

-- water height above the ground and flow speed (along the wave's direction) at a point
-- x metres behind the front. Shared by server (force) and client (looks).
function waterAt(w, x)
	if w.phase == "recede" then
		local k = 1 - clamp(w.t / RECEDE_TIME, 0, 1)
		if x < 0 then return 0, 0 end
		return w.flood * k, -0.35 * w.speed * k
	end
	if x < 0 then return 0, 0 end
	if x < CREST then return w.h * math.sqrt(1 - x / CREST * 0.65), w.speed * 1.15 * (w.phase == "wave" and 1 or 0) end
	if x < CREST + SURGE then
		local f = (x - CREST) / SURGE
		return lerp(0.35 * w.h, w.flood, f), w.speed * lerp(0.8, 0.25, f) * (w.phase == "wave" and 1 or 0)
	end
	return w.flood, 0.15 * w.speed * (w.phase == "wave" and 1 or 0)
end

-- along / lateral coordinates of a point in the wave's frame
local function frame(w, p)
	local rx, rz = p[1] - w.ox, p[3] - w.oz
	return rx * w.dx + rz * w.dz, -rx * w.dz + rz * w.dx
end

---------------------------------------------------------------------------
-- SERVER
---------------------------------------------------------------------------

function server.init()
	RegisterTool(TOOL, tr("Tsunami", "Цунами"), "MOD/prefab/tool.xml", 6)
	server.w = nil
	shared.ts = { phase = "idle", t = 0, ox = 0, oy = 0, oz = 0, dx = 0, dz = 1, s = 0, h = 0, H = 9, flood = 1.5, speed = 14, n = 0 }
end

function server.tick(dt)
	for p in PlayersAdded() do SetToolEnabled(TOOL, true, p) end
	for p in Players() do
		if GetPlayerTool(p) == TOOL and GetPlayerCanUseTool(p) and GetPlayerVehicle(p) == 0 then
			if InputPressed("usetool", p) and not server.w then server.start(p) end
			if InputPressed("grab", p) and server.w and server.w.phase ~= "recede" then
				-- before any water came there is nothing to run back: just stop (review 16.10)
				if server.w.phase == "warning" then server.finish(server.w) else server.recede(server.w) end
			end
		end
	end
end

local WATER_KEYS = { "wave", "ripple", "motion", "foam" }

function server.start(p)
	local s = readSettings()
	local eye = GetPlayerEyeTransform(p)
	local fwd = TransformToParentVec(eye, Vec(0, 0, -1))
	local flat = Vec(fwd[1], 0, fwd[3])
	if VecLength(flat) < 0.1 then flat = Vec(0, 0, -1) end
	flat = VecNormalize(flat)
	local pp = GetPlayerTransform(p).pos
	QueryRejectPlayer(p)
	QueryRequire("physical static")
	local gh, gd = QueryRaycast(VecAdd(pp, Vec(0, 0.5, 0)), Vec(0, -1, 0), 20)
	if gh then pp = Vec(pp[1], pp[2] + 0.5 - gd, pp[3]) end
	-- the wave travels towards the player: from where he looks
	local w = { phase = "warning", t = 0, ox = pp[1], oy = pp[2], oz = pp[3], dx = -flat[1], dz = -flat[3],
		s = -START_DIST, h = 0, H = s.height, flood = s.flood, speed = s.speed, power = s.power, owner = p,
		tracked = {}, state = {}, cursor = 1, scanT = 0, clock = 0, waterT = 0, water = {} }
	-- real water in the level: remember its looks to make it rough and restore it later
	local ws = FindEntities("", true, "water")
	for i = 1, #ws do
		local orig = {}
		for _, k in ipairs(WATER_KEYS) do
			local v = GetProperty(ws[i], k)
			if type(v) == "number" then orig[k] = v end
		end
		w.water[#w.water + 1] = { h = ws[i], orig = orig }
	end
	server.w = w
	server.sync(w)
	shared.ts.n = shared.ts.n + 1
end

function server.sync(w)
	local t = shared.ts
	t.phase, t.t, t.s, t.h, t.H, t.flood, t.speed = w.phase, w.t, w.s, w.h, w.H, w.flood, w.speed
	t.ox, t.oy, t.oz, t.dx, t.dz = w.ox, w.oy, w.oz, w.dx, w.dz
end

function server.recede(w)
	w.phase = "recede"
	w.t = 0
	server.sync(w)
end

-- roughness of the level's own water: 0 = as it was, 1 = storm
function server.roughWater(w, dt, k)
	w.waterT = w.waterT - dt
	if w.waterT > 0 and k > 0 then return end
	w.waterT = 0.5
	for i = 1, #w.water do
		local e = w.water[i]
		if IsHandleValid(e.h) then
			for key, o in pairs(e.orig) do
				local storm = (key == "foam") and 1 or math.max(o * 3, 1)
				SetProperty(e.h, key, lerp(o, storm, k))
			end
		end
	end
end

function server.finish(w)
	w.waterT = 0
	server.roughWater(w, 0, 0)
	server.w = nil
	shared.ts.phase = "idle"
end

function server.update(dt)
	local w = server.w
	if not w then return end
	w.t = w.t + dt
	w.clock = w.clock + dt
	if w.phase == "warning" then
		w.h = w.H * smooth(0, WARN_TIME, w.t)
		server.roughWater(w, dt, smooth(0, WARN_TIME, w.t))
		if w.t >= WARN_TIME then
			w.phase = "wave"
			w.t = 0
		end
	elseif w.phase == "wave" then
		w.h = w.H
		w.s = w.s + w.speed * dt
		server.roughWater(w, dt, 1)
		server.tear(w)
		if w.s > END_DIST + CREST + SURGE then
			w.phase = "recede"
			w.t = 0
		end
	elseif w.phase == "recede" then
		server.roughWater(w, dt, 1 - smooth(0, RECEDE_TIME, w.t))
		if w.t >= RECEDE_TIME then
			server.sync(w)
			server.finish(w)
			return
		end
	end
	server.sync(w)
	server.current(w, dt)
end

-- the water current: drag towards the flow, buoyancy, a lift in the crest
function server.current(w, dt)
	local dir = Vec(w.dx, 0, w.dz)
	-- players
	for p in Players() do
		if GetPlayerVehicle(p) == 0 then
			local pos = GetPlayerTransform(p).pos
			local a, l = frame(w, pos)
			if math.abs(l) <= HALF_WIDTH then
				local hgt, u = waterAt(w, w.s - a)
				local depth = w.oy + hgt - pos[2]
				if depth > 0 and hgt > 0 then
					local sub = clamp(depth / 1.8, 0, 1)
					local v = GetPlayerVelocity(p)
					local kf = 1 - math.exp(-(1.0 + 2.5 * sub) * dt)
					local nv = Vec(v[1] + (u * dir[1] - v[1]) * kf, v[2] + 10 * dt * sub * 0.8, v[3] + (u * dir[3] - v[3]) * kf)
					if w.phase == "wave" and w.s - a < CREST then nv[2] = math.max(nv[2], 2.5 * sub) end
					SetPlayerVelocity(nv, p)
				end
			end
		end
	end
	-- bodies near the players
	w.scanT = w.scanT - dt
	if w.scanT <= 0 then
		w.scanT = 0.25
		local list, seen = {}, {}
		for p in Players() do
			local c = GetPlayerTransform(p).pos
			QueryRequire("physical dynamic")
			local found = QueryAabbBodies(VecSub(c, Vec(ACT_RADIUS, 10, ACT_RADIUS)), VecAdd(c, Vec(ACT_RADIUS, 25, ACT_RADIUS)))
			for i = 1, #found do
				local b = found[i]
				if not seen[b] and GetBodyPlayer(b) == 0 then
					seen[b] = true
					list[#list + 1] = b
				end
			end
		end
		w.tracked = list
		w.cursor = 1
	end
	local n = #w.tracked
	local per = math.min(n, BODIES_PER_UPDATE)
	for k = 1, per do
		local b = w.tracked[w.cursor]
		w.cursor = (w.cursor % n) + 1
		if IsHandleValid(b) and IsBodyDynamic(b) then
			local st = w.state[b]
			if not st then st = { last = w.clock } w.state[b] = st end
			-- bodies are visited in turns: the drag towards the flow may catch up the whole gap (it
			-- only approaches the flow speed), the vertical push may not (a long wait was one huge kick)
			local since = math.max(dt, w.clock - st.last)
			local sinceV = math.min(since, 0.1)
			st.last = w.clock
			local bt = GetBodyTransform(b)
			local com = TransformToParentPoint(bt, GetBodyCenterOfMass(b))
			local a, l = frame(w, com)
			if math.abs(l) <= HALF_WIDTH then
				local hgt, u = waterAt(w, w.s - a)
				if hgt > 0 then
					local bmin, bmax = GetBodyBounds(b)
					local depth = w.oy + hgt - bmin[2]
					if depth > 0 then
						local mass = GetBodyMass(b)
						local sub = clamp(depth / math.max(0.5, bmax[2] - bmin[2]), 0, 1)
						local v = GetBodyVelocity(b)
						local kf = 1 - math.exp(-(2.5 + 4.0 * sub) * since)
						local massK = clamp(20000 / math.max(mass, 1), 0.6, 1)
						local dvx = (u * dir[1] - v[1]) * kf * massK
						local dvz = (u * dir[3] - v[3]) * kf * massK
						-- buoyancy by density, at most 3/4 of the weight: debris is dragged along and
						-- rolled, never thrown up (in-game 04.10: it was 0.95 g for everything plus a
						-- crest kick, so even concrete flew 20 m high); upward motion is damped
						local vol = math.max((bmax[1] - bmin[1]) * (bmax[2] - bmin[2]) * (bmax[3] - bmin[3]), 0.001)
						local float = clamp(1000 * vol / math.max(mass, 1), 0, 1)
						-- vehicles are hollow: they float and ride the flood (just above their weight), debris sinks
						local lift = GetBodyVehicle(b) ~= 0 and 1.1 or 0.75
						local dvy = 10 * sinceV * sub * lift * float
						if v[2] > 0 then dvy = dvy - v[2] * (1 - math.exp(-4 * sinceV)) end
						ApplyBodyImpulse(b, com, VecScale(Vec(dvx, dvy, dvz), mass))
					end
				end
			end
		end
	end
end

-- weak structures at the front give way: probes just behind the front face near the
-- players find what stands there and punch holes, big in soft materials (wood, glass,
-- plaster), small in medium ones (concrete, brick), none in hard ones
function server.tear(w)
	if w.power <= 0 then return end
	local holes = 0
	local hk = clamp(w.h / 8, 0.6, 2)
	local r0 = (1.6 + 1.2 * w.power) * hk                     -- wood, glass, plaster
	local r1 = math.min(r0, (0.6 + 0.7 * w.power) * hk)       -- brick, concrete: real breaches now
	local budget = HOLE_R2_BUDGET
	local players = {}
	for p in Players() do players[#players + 1] = p end
	if #players == 0 then return end
	for i = 1, PROBES_PER_UPDATE do
		if holes >= HOLES_PER_UPDATE or budget <= 0 then break end
		local p = players[(i % #players) + 1]
		local _, lp = frame(w, GetPlayerTransform(p).pos)
		local l = clamp(lp + rnd(-ACT_RADIUS, ACT_RADIUS), -HALF_WIDTH, HALF_WIDTH)
		local a = w.s - rnd(0, 6)
		local base = Vec(w.ox + a * w.dx - l * w.dz, w.oy + 40, w.oz + a * w.dz + l * w.dx)
		QueryRequire("physical static")
		local hit, dist = QueryRaycast(base, Vec(0, -1, 0), 120)
		if hit and base[2] - dist < w.oy + w.h - 0.5 then
			local gy = math.max(base[2] - dist, w.oy)
			local sample = Vec(base[1], rnd(gy + 0.3, math.max(gy + 0.6, w.oy + w.h)), base[3])
			QueryRequire("physical")
			local ok, point, nrm = QueryClosestPoint(sample, 2.5)
			if ok and not (nrm[2] > 0.7 and point[2] < gy + 0.5) then
				MakeHole(point, r0, r1, 0, true)
				holes = holes + 1
				budget = budget - r0 * r0
			end
		end
	end
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.wave = LoadSprite("MOD/ui/wave.png")
	client.foam = LoadSprite("MOD/ui/foam.png")
	client.flood = LoadSprite("MOD/ui/flood.png")
	client.deep = LoadSprite("MOD/ui/flood_deep.png")
	client.streak = LoadSprite("MOD/ui/streak.png")
	client.wall = LoadSprite("MOD/ui/wall.png")
	client.snd = { crash = LoadSound("MOD/snd/crash.ogg", 150), horn = LoadSound("MOD/snd/horn.ogg") }
	client.roar = LoadLoop("MOD/snd/roar.ogg", 200)
	client.recede = LoadLoop("MOD/snd/recede.ogg", 60)
	client.anim = {}
	client.lastN = 0
	client.ground = {}
	client.sideGround = {}
	client.flow, client.clock = 0, 0
	client.ns, client.nf = 0, 0
	client.passed = false
	client.lastX = nil
end

local function camFrame(w)
	local cam = GetPlayerCameraTransform()
	local a, l = frame(w, cam.pos)
	return cam, a, l
end

function client.tick(dt)
	for p in PlayersAdded() do client.anim[p] = ToolAnimator() end
	for p in PlayersRemoved() do client.anim[p] = nil end
	local w = shared.ts
	if w.n ~= client.lastN then
		client.lastN = w.n
		client.ground = {}
		client.sideGround = {}
		client.flow, client.clock = 0, 0
		client.passed = false
		client.lastX = nil
		PlaySound(client.snd.horn, nil, 0.8)
	end
	if w.phase ~= "idle" then
		local cam, a, l = camFrame(w)
		local x = w.s - a
		if w.phase == "wave" then
			-- the roar comes from the nearest point of the front
			local ll = clamp(l, -HALF_WIDTH, HALF_WIDTH)
			local p = Vec(w.ox + w.s * w.dx - ll * w.dz, cam.pos[2], w.oz + w.s * w.dz + ll * w.dx)
			PlayLoop(client.roar, p, clamp(w.h / 8, 0.4, 1.5))
			if client.lastX and client.lastX < 0 and x >= 0 and math.abs(l) <= HALF_WIDTH then
				PlaySound(client.snd.crash, cam.pos, 1.0)
				client.passed = true
			end
			local near = clamp(1 - math.abs(x) / 40, 0, 1)
			if near > 0.02 then ShakeCamera(near * clamp(w.h / 8, 0.4, 1.5)) end
		elseif w.phase == "recede" then
			PlayLoop(client.recede, cam.pos, 0.8 * (1 - clamp(w.t / RECEDE_TIME, 0, 1)))
		end
		client.lastX = x
	end
	for p in Players() do
		if GetPlayerTool(p) == TOOL then
			local an = client.anim[p]
			if not an then an = ToolAnimator() client.anim[p] = an end
			tickToolAnimator(an, dt, nil, p)
		end
	end
end

-- every water sprite goes through here: a hard cap per frame, a separate cap for the flood
local function put(img, t, width, height, r, g, b, a, flood)
	if client.ns >= SPRITE_CAP then return end
	if flood then
		if client.nf >= FLOOD_CAP then return end
		client.nf = client.nf + 1
	end
	client.ns = client.ns + 1
	DrawSprite(img, t, width, height, r, g, b, a, true, false, flood == true)
end

-- world point from the wave's frame: a along the travel, l sideways
local function wpos(w, a, l, y) return Vec(w.ox + a * w.dx - l * w.dz, y, w.oz + a * w.dz + l * w.dx) end

-- the flood's swell: height and slope (along, across) of gentle waves running downstream
local function swell(a, l, t, amp)
	local p1 = 0.23 * a - 1.7 * t
	local p2 = 0.17 * l + 0.11 * a + 1.1 * t
	local y = amp * (0.6 * math.sin(p1) + 0.4 * math.sin(p2))
	local ga = amp * (0.6 * 0.23 * math.cos(p1) + 0.4 * 0.11 * math.cos(p2))
	local gl = amp * 0.4 * 0.17 * math.cos(p2)
	return y, ga, gl
end

-- a flat sprite tilted to a slope (ga along the travel, gl sideways); its height runs along the travel
local function tilted(flat, ga, gl)
	return QuatRotateQuat(flat, QuatEuler(math.deg(math.atan(ga)), -math.deg(math.atan(gl)), 0))
end

-- fixed pseudo-random numbers per streak (no math.random: the server shares it in a local game)
local function hash(i, k) local x = math.sin(i * 12.9898 + k * 78.233) * 43758.5453 return x - math.floor(x) end

-- ground height under wall segment k at the front's current position (cached, a few per frame)
local function segGround(w, k, rays)
	local c = client.ground[k]
	if c and math.abs(c.s - w.s) < 6 then return c.y, rays end
	if rays <= 0 then return c and c.y, rays end      -- no measurement yet: drawn from the next frame on
	local l = k * SEG
	local p = Vec(w.ox + w.s * w.dx - l * w.dz, w.oy + 40, w.oz + w.s * w.dz + l * w.dx)
	QueryRequire("physical static")
	local hit, dist = QueryRaycast(p, Vec(0, -1, 0), 120)
	local y = hit and (p[2] - dist) or (c and c.y or w.oy)
	client.ground[k] = { s = w.s, y = y }
	return y, rays - 1
end

-- ground height under side wall piece k on the edge `side` (the wave's frame is fixed: cached for good)
local function sideGround(w, side, k, rays)
	local key = side * 100000 + k
	local y = client.sideGround[key]
	if y or rays <= 0 then return y, rays end
	local p = wpos(w, (k + 0.5) * WALL_PIECE, side * HALF_WIDTH, w.oy + 40)
	QueryRequire("physical static")
	local hit, dist = QueryRaycast(p, Vec(0, -1, 0), 120)
	y = hit and (p[2] - dist) or (w.oy - 2)
	client.sideGround[key] = y
	return y, rays - 1
end

-- clip [a0, a1] x [l0, l1] to the flooded zone; nil when nothing is left
local function clipZone(a0, a1, l0, l1, aMin, aMax)
	a0, a1 = math.max(a0, aMin), math.min(a1, aMax)
	l0, l1 = math.max(l0, -HALF_WIDTH), math.min(l1, HALF_WIDTH)
	if a1 - a0 < 0.5 or l1 - l0 < 0.5 then return nil end
	return a0, a1, l0, l1
end

-- colours: murky and dark in the depth, light and foamy on top
local DEEP_C = { 0.11, 0.19, 0.18 }
local MID_C = { 0.24, 0.35, 0.33 }
local TOP_C = { 0.64, 0.77, 0.77 }
local SURGE_C = { 0.76, 0.86, 0.87 }

-- the wall of the wave: per 10 m segment a forward-leaning face, two inner slices, a back slope,
-- a foam lip and crest foam, the fast surge behind it in tilted pieces with a foam bead at the foot of
-- the slope; segments far to the side get only the face, slope, lip and one surge piece
local function drawFront(w, cam, cl, dir, lat, yaw, flat, rays)
	local k0 = math.floor((cl - DRAW_HALF) / SEG + 0.5)
	local k1 = math.floor((cl + DRAW_HALF) / SEG + 0.5)
	for k = k0, k1 do
		local l = k * SEG
		if math.abs(l) <= HALF_WIDTH then
			local gy
			gy, rays = segGround(w, k, rays)
			if gy then
				local full = math.abs(l - cl) <= FULL_DETAIL
				-- the wall stands on the ground and reaches the flat crest height; none where the ground is higher
				local topY = w.oy + w.h
				local bottomY = math.min(gy, topY)
				local hh = topY - bottomY
				local base = Vec(w.ox + w.s * w.dx + l * lat[1], bottomY, w.oz + w.s * w.dz + l * lat[3])
				if hh > 0.3 then
					local fh = hh / LEAN_COS
					local fc = VecAdd(base, VecAdd(Vec(0, hh * 0.5, 0), VecScale(dir, hh * 0.5 * LEAN_TAN)))
					put(client.wave, Transform(fc, QuatRotateQuat(yaw, QuatEuler(-LEAN, 0, 0))), SEG * 1.08, fh, 1, 1, 1, 0.95)
					if full then
						for _, f in ipairs(SLICES) do
							local x = CREST * f
							local sy = w.oy + math.min(waterAt(w, x), w.h)
							local sb = math.min(gy, sy)
							if sy - sb > 0.3 then
								local c = VecAdd(base, VecScale(dir, -x))
								c[2] = (sy + sb) * 0.5
								put(client.wave, Transform(c, yaw), SEG * 1.08, sy - sb, 0.82, 0.9, 1, 0.75)
							end
						end
					end
					local backL = CREST * 1.2
					local by = math.max(w.oy + math.min(waterAt(w, backL), w.h), bottomY)
					local dy = topY - by
					if dy > 0.2 then
						local mid = VecAdd(Vec(base[1], (topY + by) * 0.5, base[3]), VecScale(dir, -backL * 0.5))
						local tilt = math.deg(math.atan2(backL, dy))
						put(client.flood, Transform(mid, QuatRotateQuat(yaw, QuatEuler(-tilt, 0, 0))), SEG * 1.05, math.sqrt(backL * backL + dy * dy), 1, 1, 1, 0.85)
					end
					local top = Vec(base[1], topY, base[3])
					local lip = VecAdd(top, VecScale(dir, hh * LEAN_TAN))
					put(client.foam, Transform(lip, QuatRotateQuat(yaw, QuatEuler(-70, 0, 0))), SEG * 1.3, w.h * 0.5 + 1, 1, 1, 1, 0.9)
					if full then put(client.foam, Transform(top, QuatLookAt(top, cam.pos)), SEG * 1.4, w.h * 0.3 + 1, 1, 1, 1, 0.9) end
				end
				if w.phase == "wave" then
					-- the surge: fast foamy water from the foot of the back slope down to the flood level,
					-- in tilted pieces that follow the height profile (it was one flat sheet)
					local x0, x1 = CREST * 1.2 - 0.5, CREST + SURGE + 1
					local n = full and 2 or 1
					for i = 0, n - 1 do
						local xa, xb = x0 + (x1 - x0) * i / n, x0 + (x1 - x0) * (i + 1) / n
						local ha, hb = math.min(waterAt(w, xa), w.h), math.min(waterAt(w, xb), w.h)
						local xc = (xa + xb) * 0.5
						local sy, sga, sgl = swell(w.s - xc, l, client.clock, 0.25)
						local p = wpos(w, w.s - xc, l, w.oy + (ha + hb) * 0.5 + sy)
						local ga = (ha - hb) / (xb - xa) + sga
						put(client.flood, Transform(p, tilted(flat, ga, sgl)), SEG * 1.12, math.sqrt((xb - xa) ^ 2 + (ha - hb) ^ 2) * 1.05, SURGE_C[1], SURGE_C[2], SURGE_C[3], 0.85)
					end
					if full and hh > 0.3 then
						-- a bead of foam where the falling water hits the surge
						local xb = CREST * 1.2 + 0.5
						local p = wpos(w, w.s - xb, l, w.oy + math.min(waterAt(w, xb), w.h) + 0.35)
						put(client.foam, Transform(p, QuatRotateQuat(yaw, QuatEuler(-35, 0, 0))), SEG * 1.25, 1.8, 1, 1, 1, 0.9)
					end
				end
			end
		end
	end
	return rays
end

-- the flood behind the surge (and while it drains): a body of water around the camera.
-- Near: 6 x 6 tiles of 10 m, each a deep dark layer and a light surface tilted by the swell, both
-- drifting with the current; a middle layer of 20 m tiles drifting at half speed in between (parallax);
-- far: big sheets out to 150 m; foam and debris streaks along the current; side walls with a foam
-- bead where the zone ends, when the camera is near that edge
local function drawFlood(w, cam, ca, cl, dir, lat, flat, rays, dt)
	local level, u
	if w.phase == "recede" then
		local k = 1 - clamp(w.t / RECEDE_TIME, 0, 1)
		level, u = w.flood * k, -0.35 * w.speed * k
	elseif w.phase == "wave" then
		level, u = w.flood, 0.15 * w.speed
	else
		return rays
	end
	client.flow = client.flow + u * dt
	if level <= 0.02 then return rays end
	local aMin = -START_DIST
	local aMax = (w.phase == "wave") and (w.s - (CREST + SURGE)) or w.s
	if aMax - aMin < 0.5 then return rays end
	local L = w.oy + level
	local t = client.clock
	local amp = clamp(0.15 + 0.12 * level, 0.12, 0.6)
	local dDeep = clamp(0.5 * level, 0.35, 0.9)

	-- near field
	local ph = client.flow % NEAR_TILE
	local i0 = math.floor((ca - ph) / NEAR_TILE) - NEAR_N / 2 + 1
	local j0 = math.floor(cl / NEAR_TILE) - NEAR_N / 2 + 1
	local nA0, nL0 = i0 * NEAR_TILE + ph, j0 * NEAR_TILE
	local nA1, nL1 = nA0 + NEAR_N * NEAR_TILE, nL0 + NEAR_N * NEAR_TILE
	for i = 0, NEAR_N - 1 do
		for j = 0, NEAR_N - 1 do
			local a0, a1, l0, l1 = clipZone(nA0 + i * NEAR_TILE, nA0 + (i + 1) * NEAR_TILE, nL0 + j * NEAR_TILE, nL0 + (j + 1) * NEAR_TILE, aMin, aMax)
			if a0 then
				local ac, lc, la, ll = (a0 + a1) * 0.5, (l0 + l1) * 0.5, a1 - a0, l1 - l0
				put(client.deep, Transform(wpos(w, ac, lc, L - dDeep), flat), ll * 1.4, la * 1.4, DEEP_C[1], DEEP_C[2], DEEP_C[3], 0.85, true)
				local sy, ga, gl = swell(ac, lc, t, amp)
				put(client.flood, Transform(wpos(w, ac, lc, L + sy), tilted(flat, ga, gl)), ll * 1.3, la * 1.3, TOP_C[1], TOP_C[2], TOP_C[3], 0.8, true)
			end
		end
	end
	-- middle layer: coarser, half a tile off and slower, so the depth shows when you move
	local ph2 = (client.flow * 0.5) % MID_TILE
	local mi0 = math.floor((ca - ph2) / MID_TILE) - 1
	local mj0 = math.floor(cl / MID_TILE) - 1
	for i = 0, MID_N - 1 do
		for j = 0, MID_N - 1 do
			local a = (mi0 + i) * MID_TILE + ph2 + MID_TILE * 0.5
			local l = (mj0 + j) * MID_TILE + MID_TILE * 0.5
			local a0, a1, l0, l1 = clipZone(a, a + MID_TILE, l, l + MID_TILE, aMin, aMax)
			if a0 then
				put(client.deep, Transform(wpos(w, (a0 + a1) * 0.5, (l0 + l1) * 0.5, L - dDeep * 0.5), flat), (l1 - l0) * 1.3, (a1 - a0) * 1.3, MID_C[1], MID_C[2], MID_C[3], 0.45, true)
			end
		end
	end
	-- foam and debris streaks: fixed in the water, drifting with it, wrapped into a window around the camera
	local wa0, wl0 = ca - STREAK_A, cl - STREAK_L
	local aTop = (w.phase == "wave") and (w.s - CREST * 1.2 - 2) or aMax
	for i = 1, STREAKS do
		local h1, h2, h3 = hash(i, 1), hash(i, 2), hash(i, 3)
		local a = wa0 + ((h1 * 2 * STREAK_A + client.flow * (0.8 + 0.4 * h3) - wa0) % (2 * STREAK_A))
		local l = wl0 + ((h2 * 2 * STREAK_L - wl0) % (2 * STREAK_L))
		if a > aMin and a < aTop and math.abs(l) < HALF_WIDTH - 1 then
			local hgt = level
			if w.phase == "wave" then hgt = math.min(waterAt(w, w.s - a), w.h) end
			local sy, ga, gl = swell(a, l, t, amp)
			local fade = clamp(math.min(a - wa0, wa0 + 2 * STREAK_A - a) / 6, 0, 1)
			local p = wpos(w, a, l, w.oy + hgt + sy + 0.06)
			if h3 < 0.3 then
				put(client.streak, Transform(p, tilted(flat, ga, gl)), 0.7, 3 + 2 * h1, 0.33, 0.25, 0.17, 0.85 * fade, true)
			else
				put(client.streak, Transform(p, tilted(flat, ga, gl)), 0.8 + 0.8 * h2, 5 + 6 * h3, 0.95, 0.97, 0.97, 0.75 * fade, true)
			end
		end
	end
	-- side walls where the flooded zone ends, so the flood has a side, not just a top
	local side = cl >= 0 and 1 or -1
	if HALF_WIDTH - math.abs(cl) <= WALL_NEAR then
		local lw = side * HALF_WIDTH
		local k0 = math.floor(ca / WALL_PIECE) - WALL_N / 2
		for k = k0, k0 + WALL_N - 1 do
			local lo, hi = math.max(k * WALL_PIECE, aMin), math.min((k + 1) * WALL_PIECE, aMax)
			if hi - lo > 0.5 then
				local gy
				gy, rays = sideGround(w, side, k, rays)
				if gy and gy < L - 0.1 then
					local bottom = gy - 0.3
					local mid = (lo + hi) * 0.5
					local p = wpos(w, mid, lw, (L + bottom) * 0.5)
					local rot = QuatLookAt(p, VecAdd(p, VecScale(lat, side)))
					put(client.wall, Transform(p, rot), hi - lo + 0.3, L - bottom, 0.9, 0.95, 0.95, 0.9, true)
					put(client.foam, Transform(wpos(w, mid, lw + side * 0.2, L + 0.15), QuatRotateQuat(rot, QuatEuler(-50, 0, 0))), hi - lo + 0.6, 1.3, 1, 1, 1, 0.85, true)
				end
			end
		end
	end
	-- far sheets: the ring between the near field and 150 m, in pieces of at most 100 m
	local fA0, fA1, fL0, fL1 = ca - FAR_HALF, ca + FAR_HALF, cl - FAR_HALF, cl + FAR_HALF
	local strips = {
		{ fA0, nA0, fL0, fL1 }, { nA1, fA1, fL0, fL1 },
		{ nA0, nA1, fL0, nL0 }, { nA0, nA1, nL1, fL1 },
	}
	for _, sp in ipairs(strips) do
		local a0, a1, l0, l1 = clipZone(sp[1], sp[2], sp[3], sp[4], aMin, aMax)
		if a0 then
			local na, nl = math.ceil((a1 - a0) / FAR_CHUNK), math.ceil((l1 - l0) / FAR_CHUNK)
			local da, dl = (a1 - a0) / na, (l1 - l0) / nl
			for i = 0, na - 1 do
				for j = 0, nl - 1 do
					local ac, lc = a0 + (i + 0.5) * da, l0 + (j + 0.5) * dl
					put(client.deep, Transform(wpos(w, ac, lc, L - dDeep), flat), dl * 1.35, da * 1.35, DEEP_C[1], DEEP_C[2], DEEP_C[3], 0.85, true)
					local sy = swell(ac, lc, t, amp)
					put(client.flood, Transform(wpos(w, ac, lc, L + sy * 0.5), flat), dl * 1.3, da * 1.3, TOP_C[1], TOP_C[2], TOP_C[3], 0.7, true)
				end
			end
		end
	end
	return rays
end

-- the wall of the wave and the flood behind it: depth-tested sprites, at most SPRITE_CAP per frame
-- (FLOOD_CAP of them for the flood), RAYS_PER_FRAME ground probes
function client.render(dt)
	local w = shared.ts
	client.ns, client.nf = 0, 0
	if w.phase == "idle" then return end
	client.clock = client.clock + dt
	local cam, ca, cl = camFrame(w)
	local dir = Vec(w.dx, 0, w.dz)
	local lat = Vec(-w.dz, 0, w.dx)
	local yaw = QuatLookAt(Vec(0, 0, 0), dir)
	local flat = QuatRotateQuat(yaw, QuatEuler(-90, 0, 0))
	local rays = RAYS_PER_FRAME
	if w.phase ~= "recede" and w.h >= 0.2 then rays = drawFront(w, cam, cl, dir, lat, yaw, flat, rays) end
	drawFlood(w, cam, ca, cl, dir, lat, flat, rays, dt)
end

-- foam and spray on the crest near the camera (at most 30 particles per step)
function client.update(dt)
	local w = shared.ts
	if w.phase ~= "wave" and w.phase ~= "warning" then return end
	if w.h < 0.5 then return end
	local cam, ca, cl = camFrame(w)
	if math.abs(w.s - ca) > 150 then return end
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.92, 0.96, 1.0)
	ParticleRadius(0.6, 2.2)
	ParticleAlpha(0.7, 0)
	ParticleGravity(-3)
	ParticleDrag(0.3)
	for i = 1, 18 do
		local l = clamp(cl + rnd(-60, 60), -HALF_WIDTH, HALF_WIDTH)
		local p = Vec(w.ox + w.s * w.dx - l * w.dz, w.oy + w.h * rnd(0.85, 1.05), w.oz + w.s * w.dz + l * w.dx)
		SpawnParticle(p, Vec(w.dx * w.speed * 0.8 + rnd(-2, 2), rnd(1, 5), w.dz * w.speed * 0.8 + rnd(-2, 2)), rnd(1, 2.5))
	end
	ParticleReset()
	ParticleType("plain")
	ParticleColor(1, 1, 1)
	ParticleRadius(0.08, 0.03)
	ParticleGravity(-10)
	ParticleCollide(0)
	for i = 1, 12 do
		local l = clamp(cl + rnd(-40, 40), -HALF_WIDTH, HALF_WIDTH)
		local p = Vec(w.ox + w.s * w.dx - l * w.dz, w.oy + w.h, w.oz + w.s * w.dz + l * w.dx)
		SpawnParticle(p, Vec(w.dx * w.speed + rnd(-3, 3), rnd(3, 9), w.dz * w.speed + rnd(-3, 3)), rnd(0.8, 1.6))
	end
end

function client.draw(dt)
	local w = shared.ts
	local s = readSettings()
	local cam, ca, cl = nil, 0, 0
	if w.phase ~= "idle" then cam, ca, cl = camFrame(w) end
	local ahead = w.phase ~= "idle" and w.phase ~= "recede" and (w.s - ca) < 0 and math.abs(cl) <= HALF_WIDTH
	if ahead and s.siren then UiSoundLoop("MOD/snd/siren.ogg", 0.7, 1.0) end
	if GetBool("game.ui.hidemods") then return end
	if ahead then
		UiPush()
			UiTranslate(UiCenter(), 70)
			UiAlign("center middle")
			UiTextShadow(0, 0, 0, 0.7, 2)
			UiFont("bold.ttf", 30)
			if math.floor(GetTime() * 2) % 2 == 0 then UiColor(1, 0.25, 0.2, 1) else UiColor(1, 1, 1, 1) end
			UiText(tr("TSUNAMI WARNING", "УГРОЗА ЦУНАМИ"))
			UiTranslate(0, 34)
			UiFont("regular.ttf", 22)
			UiColor(1, 1, 1, 0.9)
			UiText(string.format(tr("Wave: %.0f m, %.0f m high", "Волна: %.0f м, высота %.0f м"), math.max(0, ca - w.s), w.h))
		UiPop()
	end
	if GetPlayerTool() == TOOL and GetPlayerCanUseTool() then
		UiPush()
			UiTranslate(UiCenter(), UiHeight() - 160)
			UiAlign("center middle")
			UiTextShadow(0, 0, 0, 0.6, 1.5)
			UiFont("regular.ttf", 22)
			UiColor(1, 1, 1, 0.9)
			if w.phase == "idle" then
				UiText(tr("LMB: call a tsunami from where you look", "ЛКМ: вызвать цунами оттуда, куда смотрите"))
			elseif w.phase ~= "recede" then
				UiText(tr("RMB: call the wave off", "ПКМ: отменить волну"))
			else
				UiText(tr("The water runs back", "Вода уходит"))
			end
		UiPop()
	end
end
