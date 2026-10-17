#version 2
-- Catapult / Катапульта
-- A giant wooden trebuchet you place in front of you. Its frame is real, destructible voxels;
-- its arm turns about the axle, driven by the script. Whatever lies in the bucket is thrown: a
-- boulder, an explosive barrel, a car, a pile of crates, the player.
--
--   LMB             place a catapult in front of you (up to 4)
--   Q, or E on it   fire           (F is the game's flashlight)
--   mouse wheel     power
--   Z / X           turn left / right          V / B   lower / raise the angle   (C is the game's camera key)
--   1 2 3 4         load a boulder / barrel / car / crates      RMB  ride: get into the bucket and be launched
--   R               remove all catapults and their ammo
--
-- Assembly by measurement (in-game 16.10, after three rounds of guessing the game's vox pivot):
-- where the game puts a spawned vox relative to its pos depends on the model's size, so no single
-- "pivot fraction" fits every part (the 30-voxel beam came out 1.5 m low and 1.1 m back with the
-- fraction of a 4-voxel probe). So the whole machine is first spawned still, 60 m up, out of sight;
-- the real centre of every part is measured (GetShapeBounds) and the difference to its designed
-- centre is added to that part's pos; then once more to check; then the real machine is spawned on
-- the ground and checked again (re-spawned if any part is more than 5 cm off). The corrections are
-- kept for the next catapults.
-- The arm turns by script, not on a spawned hinge joint: in-game the joint from the spawn text held
-- no shape at all ("joint shapes 0, hinge hub-nothing") and what a joint attaches to cannot be set or
-- moved by script. Every tick the arm body is set to its pose for the arm angle (the hub on the axle's
-- axis) with the matching angular velocity; the arm's shapes do not collide with the frame's
-- (collision filter), so the hub around the axle cannot jam. The load is held in the bucket while
-- the arm swings and released with exactly the planned speed (14-56 m/s by power) at the set angle.
-- Ammo is also placed by measurement: after it appears, its real bounds are read and it is moved so
-- that it lies on the bucket floor (the car on the rim).
-- Impacts punch holes scaled by speed and material (brick from 25 m/s, hard materials from
-- 45 m/s), boulders punch through, barrels explode.
--
-- Server: catapult bodies, arm, loading, release, impacts, limits. Client: input, arc preview, HUD,
-- sounds, particles.

#include "script/include/player.lua"
#include "script/toolanimation.lua"

local TOOL = "catapult"
local MAX_CATAPULTS = 4
local MAX_AMMO = 24              -- ammo bodies spawned by the mod, alive at once
local MAX_CARS = 3
local MAX_FLYING = 24
local HOLES_PER_UPDATE = 8
local V_MIN, V_MAX = 14, 56      -- launch speed at power 0 / 1 (m/s)
local SWING = 290                -- deg/s, arm speed while firing (about 5 rad/s)
local RESET = 70                 -- deg/s, arm speed back to rest
local REST = 55                  -- arm angle below the horizontal at rest (degrees)
local AXY = 9.6                  -- axle height (m)
local L1, L2 = 10, 3.4           -- pivot to bucket / to counterweight (m)
local SCALE = 3
local VS = 0.1 * SCALE           -- voxel size (m)
local TOL = 0.05                 -- a part more than 5 cm from its designed place counts as misplaced
local MAX_SPAWNS = 6             -- measuring and real spawns per placement
local AMMO = { "boulder", "barrel", "car", "crates" }
local AMMO_K = { boulder = 1.0, barrel = 0.7, car = 0.85, crates = 0.5, other = 0.7 }
-- collision layers: the arm's shapes do not collide with the frame's (the hub sits around the axle);
-- a load that has just been released does not collide with either while it leaves the bucket
local LAYER_FRAME, LAYER_ARM, LAYER_LOAD = 4, 2, 8
local GHOST_TIME = 1.0           -- seconds a released load passes through its catapult

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function rnd(a, b) return a + (b - a) * math.random() end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getI(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetInt(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end
local function fmt3(v) return string.format("%.4f %.4f %.4f", v[1], v[2], v[3]) end

function readSettings()
	return {
		ammo = math.floor(clamp(getI("ammo", 1), 1, 4)),
		reload = getB("reload", true),
		damage = clamp(getF("damage", 1), 0.25, 2),
		falldamage = getB("falldamage", false),
		arc = getB("arc", true),
		debug = getB("debugline", false),   -- hidden diagnostics, off by default since 10.10 (new key: old saves may hold debug=true)
	}
end

-- Several bodies in one Spawn must be ONE XML document. The game spawns only the first top-level
-- element of a text: in-game 10.10 the catapult (static frame body + dynamic arm body side by side)
-- came out as the frame alone. The game's own scripts wrap their spawn texts like this
-- (data/script/mp/lib/tools.lua).
local function prefabXml(name, inner)
	return "<prefab version='1.2.0'><group name='" .. name .. "' pos='0.0 0.0 0.0' rot='0.0 0.0 0.0'>" .. inner .. "</group></prefab>"
end

function launchSpeed(power) return V_MIN + (V_MAX - V_MIN) * clamp(power, 0, 1) end

-- the parts, which body they belong to, and how they are recognised: by their own tag (catapult_p_<name>),
-- else by their size in voxels (sorted). In-game 16.10 23:13 the frame was not recognised by the size of
-- its .vox (26x32x38): the game counts only the filled voxels, and the frame's outer columns are empty
-- (filled 22 wide) - "refused: missing frame among 2 bodies / 7 shapes". Both sizes are listed.
local PARTS = { "frame", "axle", "hub", "beam_long", "beam_short", "bucket", "weight" }
local ARM_PARTS = { hub = true, beam_long = true, beam_short = true, bucket = true, weight = true }
local PART_DIMS = { ["26x32x38"] = "frame", ["22x32x38"] = "frame", ["4x4x26"] = "axle", ["6x6x6"] = "hub", ["2x2x30"] = "beam_long",
	["2x2x8"] = "beam_short", ["5x9x9"] = "bucket", ["8x8x8"] = "weight" }
local function partTag(n) return "catapult_p_" .. n end

-- the designed layout (catapult space, metres): the centre of every part and its tilt about x. The
-- frame stands on the ground, the axle lies on its bearings at 9.6 m, the arm hangs in its rest pose
-- with the bucket behind (+z) and below the axle. All models are symmetric about their centre.
local function layout()
	local a = math.rad(REST)
	local u = Vec(0, -math.sin(a), math.cos(a))            -- along the arm towards the bucket (back, down)
	local P = Vec(0, AXY, 0)
	-- the beam is two pieces starting at the hub's faces (0.9 m from the axis; the axle's corners reach
	-- 0.85 m): in-game 11.10 one 14.4 m beam ran through the axle
	local r0 = 6 * VS * 0.5
	local longLen, shortLen = 30 * VS, 8 * VS
	return {
		frame = { c = Vec(0, 32 * VS * 0.5, 0), tilt = 0 },
		axle = { c = P, tilt = 0 },
		hub = { c = P, tilt = 0 },
		beam_long = { c = VecAdd(P, VecScale(u, r0 + longLen / 2)), tilt = REST },
		beam_short = { c = VecSub(P, VecScale(u, r0 + shortLen / 2)), tilt = REST },
		bucket = { c = VecAdd(VecAdd(P, VecScale(u, L1)), Vec(0, 0.3, 0)), tilt = 0 },
		weight = { c = VecSub(P, VecScale(u, L2)), tilt = REST },
	}, P
end

-- the spawn text: every part at its designed centre plus its measured correction. `still`: both bodies
-- static (the measuring copy 60 m up must not fall while it is measured)
local function prefab(fix, still)
	local lay, P = layout()
	local tag = still and "catapult_part catapult_measure" or "catapult_part"
	-- the arm body's origin is the axle centre (its parts are placed relative to it)
	local function vox(n)
		local p = VecAdd(lay[n].c, fix[n] or Vec(0, 0, 0))
		if ARM_PARTS[n] then p = VecSub(p, P) end
		return "<vox file='MOD/vox/" .. n .. ".vox' scale='" .. SCALE .. "' pos='" .. fmt3(p) .. "' rot='" .. lay[n].tilt .. " 0 0' tags='" .. tag .. " " .. partTag(n) .. "'/>"
	end
	local frameTags = still and "catapult_part catapult_measure" or "catapult catapult_part interact=Fire"
	local armTags = still and "catapult_part catapult_measure" or "catapult_arm catapult_part interact=Fire"
	return prefabXml("catapult", "<body dynamic='false' tags='" .. frameTags .. "'>" .. vox("frame") .. vox("axle") .. "</body>" ..
		"<body dynamic='" .. (still and "false" or "true") .. "' pos='" .. fmt3(P) .. "' tags='" .. armTags .. "'>" ..
		vox("hub") .. vox("beam_long") .. vox("beam_short") .. vox("bucket") .. vox("weight") .. "</body>")
end

local function validBounds(mn, mx)
	return mx[1] - mn[1] > 0.05 and mx[2] - mn[2] > 0.05 and mx[3] - mn[3] > 0.05
end
-- measured geometry, from world bounds like the game's own spawn menu
local function boundsCentre(shape)
	local mn, mx = GetShapeBounds(shape)
	return VecLerp(mn, mx, 0.5), mn, mx
end
local function shapeDims(sh)
	local x, y, z = GetShapeSize(sh)
	local t = { x, y, z }
	table.sort(t)
	return t[1] .. "x" .. t[2] .. "x" .. t[3]
end

-- the parts among the handles Spawn returned
local function findParts(ents)
	local parts, bodies, shapes = {}, {}, {}
	for i = 1, #(ents or {}) do
		local e = ents[i]
		local ty = GetEntityType(e)
		if ty == "body" then bodies[#bodies + 1] = e
		elseif ty == "shape" then
			shapes[#shapes + 1] = e
			local n = nil
			for _, pn in ipairs(PARTS) do if HasTag(e, partTag(pn)) then n = pn end end
			n = n or PART_DIMS[shapeDims(e)]
			if n and not parts[n] then parts[n] = e end
		end
	end
	-- the frame is also the frame body's one other shape besides the axle
	if not parts.frame and parts.axle then
		local fb = GetShapeBody(parts.axle)
		for _, sh in ipairs(shapes) do
			local used = false
			for _, pn in ipairs(PARTS) do if parts[pn] == sh then used = true end end
			if not used and GetShapeBody(sh) == fb then parts.frame = sh break end
		end
	end
	return parts, bodies
end
local function partsProblem(parts)
	local missing, notReady = {}, {}
	for _, n in ipairs(PARTS) do
		local sh = parts[n]
		if not sh or not IsHandleValid(sh) then missing[#missing + 1] = n
		else
			local mn, mx = GetShapeBounds(sh)
			if not validBounds(mn, mx) then notReady[#notReady + 1] = n end
		end
	end
	if #missing > 0 then return "missing " .. table.concat(missing, ", ") end
	if #notReady > 0 then return "no bounds yet for " .. table.concat(notReady, ", ") end
	-- frame and axle on one body, the arm parts on another
	local fb, ab = GetShapeBody(parts.frame), GetShapeBody(parts.hub)
	if GetShapeBody(parts.axle) ~= fb then return "axle not on the frame body" end
	if fb == ab then return "arm on the frame body" end
	for n in pairs(ARM_PARTS) do if GetShapeBody(parts[n]) ~= ab then return n .. " not on the arm body" end end
	return nil
end
local function deleteSpawned(ents)
	for i = 1, #(ents or {}) do if GetEntityType(ents[i]) == "body" and IsHandleValid(ents[i]) then Delete(ents[i]) end end
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
	server.fix = nil              -- measured per-part corrections (catapult space), kept for the next catapults
	server.loadN = 0              -- every load (one Spawn: a boulder, a car with its wheels, 6 crates) has its own number
	server.ghosts = {}            -- released loads passing through their catapult: { shapes = { {sh, layer, mask} }, t }
	shared.cp = { reason = "", list = {}, fireN = 0, fx = 0, fy = 0, fz = 0, relN = 0, impN = 0, ix = 0, iy = 0, iz = 0, isp = 0, msg = "", mn = 0, flying = {} }
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

-- the catapult's own space: the frame body (static; spawned at the catapult transform)
function server.catT(c) return GetBodyTransform(c.frame) end
function server.pivot(c) return (boundsCentre(c.axle)) end
function server.bucketCentre(c) return (boundsCentre(c.bucket)) end
-- the inside floor of the bucket (the bucket is upright whenever this is used: at rest)
function server.bucketFloor(c)
	local ctr, mn = boundsCentre(c.bucket)
	return Vec(ctr[1], mn[2] + VS, ctr[3])
end
function server.bucketRim(c)
	local _, _, mx = boundsCentre(c.bucket)
	return mx[2]
end
function server.back(c) return QuatRotateVec(GetBodyTransform(c.frame).rot, Vec(0, 0, 1)) end
-- the arm angle: the bucket's direction from the axle, degrees above the horizontal (behind the axle)
function server.psi(c)
	local d = VecSub(server.bucketCentre(c), server.pivot(c))
	return math.deg(math.atan2(d[2], VecDot(d, server.back(c))))
end

-- the arm's pose for the angle c.theta (degrees turned up from rest), about the axle's axis
function server.armPose(c, theta)
	local fT = server.catT(c)
	local rest = TransformToParentTransform(fT, c.armRestLocal)
	local P = TransformToParentPoint(fT, c.pivotLocal)
	local axis = QuatRotateVec(fT.rot, Vec(1, 0, 0))
	local q = QuatAxisAngle(axis, -theta)
	return Transform(VecAdd(P, QuatRotateVec(q, VecSub(rest.pos, P))), QuatRotateQuat(q, rest.rot)), P, axis
end
-- the scripted hinge: put the arm where its angle says, moving at `w` deg/s (so the load in the bucket
-- feels the real motion)
function server.holdArm(c, w)
	local t, P, axis = server.armPose(c, c.theta)
	SetBodyTransform(c.arm, t)
	local wv = VecScale(axis, -math.rad(w))
	SetBodyAngularVelocity(c.arm, wv)
	local com = TransformToParentPoint(t, GetBodyCenterOfMass(c.arm))
	SetBodyVelocity(c.arm, VecCross(wv, VecSub(com, P)))
end

function server.sync()
	local list = {}
	for i = 1, #server.cats do
		local c = server.cats[i]
		list[i] = { id = c.id, frame = c.frame, arm = c.arm, axle = c.axle, bucket = c.bucket, power = c.power, angle = c.angle,
			ammo = c.ammo, state = c.state, armLen = c.armLen or L1, psiRest = c.psiRest or -REST, broken = c.broken, dbg = c.dbg or "" }
		local rp = (not c.broken) and server.releasePoint(c) or nil
		if rp then list[i].rx, list[i].ry, list[i].rz = rp[1], rp[2], rp[3] end
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
				if c then server.ride(c, p) end
			end
		end
	end
	-- launched players: no fall damage unless the option says so
	for p, pr in pairs(server.protect) do
		pr.t = pr.t + dt
		if pr.ghost and pr.t >= GHOST_TIME then pr.ghost = nil server.ghostPlayer(p, false) end
		if not readSettings().falldamage then SetPlayerHealth(1, p) end
		local v = GetPlayerVelocity(p)
		if pr.t > 0.5 and math.abs(v[2]) < 0.5 then pr.landed = (pr.landed or 0) + dt end
		if (pr.landed or 0) > 1.5 or pr.t > 30 then server.protect[p] = nil end
	end
end

-- LMB: find the ground, then (over the next ticks) measure and assemble. Every refusal tells the
-- player why in plain words (no ground / did not assemble / too many), and the technical reason goes
-- to the game's log (print) and to the debug line, which is off by default.
local function refuse(reason, kind)
	shared.cp.reason = reason
	print("catapult: " .. reason)
	message(kind or "aim")
end

function server.place(p)
	if server.pending then return end
	if #server.cats >= MAX_CATAPULTS then refuse("4 catapults already stand", "full") return end
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
	local g
	if hit then
		g = VecAdd(probe, Vec(0, -dist, 0))
	else
		-- fallback: 14 m ahead at the height of the ground under the player
		QueryRejectPlayer(p)
		QueryRequire("physical")
		local h2, d2 = QueryRaycast(VecAdd(pp, Vec(0, 1, 0)), Vec(0, -1, 0), 5)
		if not h2 then refuse("refused: no ground 14 m ahead (ray from 20 m up, 60 m long) and none under you") return end
		g = Vec(probe[1], pp[2] + 1 - d2, probe[3])
	end
	local yaw = math.deg(math.atan2(-flat[1], -flat[3]))
	local fix = {}
	for n, v in pairs(server.fix or {}) do fix[n] = VecCopy(v) end
	server.pending = { stage = server.fix and "assemble" or "measure", g = g, yaw = yaw, tries = 0, spawns = 0, measures = 0, fix = fix }
	shared.cp.reason = "placing: " .. server.pending.stage
end

-- the pending placement, one step per tick:
--   measure  - a still copy 60 m up: where did each part really come out? correct its pos, repeat
--              until every part is within 5 cm (at least twice: once to measure, once to check)
--   assemble - the real catapult on the ground, checked the same way (re-spawned if a part is off)
function server.stepPending()
	local pd = server.pending
	if not pd then return end
	pd.tries = pd.tries + 1
	local catT = Transform(pd.g, QuatEuler(0, pd.yaw, 0))
	if not pd.ents then
		if pd.spawns >= MAX_SPAWNS then
			-- the measurements do not settle: build with what we have and let the debug line show it
			pd.stage = "assemble"
		end
		pd.at = (pd.stage == "measure") and Transform(VecAdd(pd.g, Vec(0, 60, 0)), catT.rot) or catT
		pd.ents = Spawn(prefab(pd.fix, pd.stage == "measure"), pd.at, true)
		pd.spawns = pd.spawns + 1
		pd.tries = 0
		shared.cp.reason = "placing: " .. pd.stage .. " (spawn " .. pd.spawns .. ")"
		return
	end
	local parts = findParts(pd.ents)
	local problem = partsProblem(parts)
	if problem then
		if pd.tries < 30 then shared.cp.reason = "placing: " .. pd.stage .. ", waiting: " .. problem .. " (tick " .. pd.tries .. ")" return end
		-- never leave half a catapult behind that nothing can remove
		local _, bodies = findParts(pd.ents)
		local nShapes = 0
		for i = 1, #pd.ents do if GetEntityType(pd.ents[i]) == "shape" then nShapes = nShapes + 1 end end
		deleteSpawned(pd.ents)
		server.pending = nil
		refuse("refused: " .. problem .. " among " .. #bodies .. " bodies / " .. nShapes .. " shapes after 30 ticks", "assembly")
		return
	end
	local lay = layout()
	local err, worst = {}, 0
	local frameBody, armBody = GetShapeBody(parts.frame), GetShapeBody(parts.hub)
	local restT = nil
	if pd.stage == "measure" then
		-- a still copy: every part measured in the space it was spawned in
		for _, n in ipairs(PARTS) do err[n] = VecSub(lay[n].c, TransformToLocalPoint(pd.at, (boundsCentre(parts[n])))) end
	else
		-- the real one: frame parts in catapult space; the arm (dynamic - it may have dropped a few mm since
		-- the spawn) as it will be held: its hub on the axle's centre, turned like the catapult
		local axleW = boundsCentre(parts.axle)
		local B1 = GetBodyTransform(armBody)
		local hubLocal = TransformToLocalPoint(B1, (boundsCentre(parts.hub)))
		restT = Transform(VecSub(axleW, QuatRotateVec(catT.rot, hubLocal)), catT.rot)
		for _, n in ipairs(PARTS) do
			local w = boundsCentre(parts[n])
			if ARM_PARTS[n] then w = TransformToParentPoint(restT, TransformToLocalPoint(B1, w)) end
			err[n] = VecSub(lay[n].c, TransformToLocalPoint(catT, w))
		end
		-- the hub is put on the axle by construction; its own error is the axle's
		err.hub = VecCopy(err.axle)
	end
	for _, n in ipairs(PARTS) do worst = math.max(worst, VecLength(err[n])) end
	pd.lastWorst = worst
	if worst > TOL and pd.spawns < MAX_SPAWNS then
		-- correct and spawn again (the game's offset of a part is fixed for its size and tilt, so one
		-- correction is enough; the next spawn checks it)
		for _, n in ipairs(PARTS) do pd.fix[n] = VecAdd(pd.fix[n] or Vec(0, 0, 0), err[n]) end
		deleteSpawned(pd.ents)
		pd.ents = nil
		shared.cp.reason = string.format("placing: %s, worst part %.2f m off, correcting", pd.stage, worst)
		return
	end
	if pd.stage == "measure" then
		deleteSpawned(pd.ents)
		pd.ents = nil
		server.fix = pd.fix
		pd.stage = "assemble"
		return
	end
	-- the real catapult is in place
	local c = { id = server.nextId, frame = frameBody, arm = armBody, axle = parts.axle, hub = parts.hub, bucket = parts.bucket,
		beamLong = parts.beam_long, beamShort = parts.beam_short, weight = parts.weight, frameShape = parts.frame,
		yaw = pd.yaw, base = pd.g, power = 0.75, angle = 45, ammo = readSettings().ammo, state = "settle", t = 0,
		held = {}, heldPlayers = {}, theta = 0, spawns = pd.spawns, design = lay, groups = {} }
	server.nextId = server.nextId + 1
	c.armRestLocal = TransformToLocalTransform(catT, restT)
	c.pivotLocal = TransformToLocalPoint(catT, (boundsCentre(parts.axle)))
	for _, sh in ipairs(GetBodyShapes(c.frame)) do SetShapeCollisionFilter(sh, LAYER_FRAME, 255 - LAYER_ARM) end
	for _, sh in ipairs(GetBodyShapes(c.arm)) do SetShapeCollisionFilter(sh, LAYER_ARM, 255 - LAYER_FRAME) end
	server.holdArm(c, 0)
	server.cats[#server.cats + 1] = c
	server.pending = nil
	server.fix = pd.fix
	shared.cp.reason = ""
	server.sync()
	message("placed")
end

-- a just-spawned body's transform is trusted only once all its shapes have real bounds
function server.bodyReady(b)
	local shapes = GetBodyShapes(b)
	if not shapes or #shapes == 0 then return false end
	for i = 1, #shapes do
		local mn, mx = GetShapeBounds(shapes[i])
		if not validBounds(mn, mx) then return false end
	end
	return true
end
-- world bounds of a group of bodies (all their shapes)
local function groupBounds(bodies)
	local mn, mx = Vec(1e9, 1e9, 1e9), Vec(-1e9, -1e9, -1e9)
	for _, b in ipairs(bodies) do
		if IsHandleValid(b) then
			for _, sh in ipairs(GetBodyShapes(b)) do
				local smn, smx = GetShapeBounds(sh)
				if validBounds(smn, smx) then
					for k = 1, 3 do mn[k] = math.min(mn[k], smn[k]) mx[k] = math.max(mx[k], smx[k]) end
				end
			end
		end
	end
	return mn, mx
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

-- keep the number of mod-spawned ammo bodies bounded, deleting whole loads (all bodies of one Spawn),
-- oldest first. In-game 17.10 "the car vanishes in mid-air": the car is 5 bodies (body + 4 wheels), and
-- the cars were counted by BODIES, so the automatic reload a second after the shot found "5 cars" and
-- deleted bodies of the car still flying.
local function deleteLoad(id)
	local keep = {}
	for _, a in ipairs(server.ammo) do
		if a.load == id then
			if IsHandleValid(a.body) then Delete(a.body) end
		else
			keep[#keep + 1] = a
		end
	end
	server.ammo = keep
end
local function trimAmmo(extra, kind)
	local alive = {}
	for i = 1, #server.ammo do if IsHandleValid(server.ammo[i].body) then alive[#alive + 1] = server.ammo[i] end end
	server.ammo = alive
	while #server.ammo + extra > MAX_AMMO and #server.ammo > 0 do deleteLoad(server.ammo[1].load) end
	if kind == "car" then
		while true do
			local seen, n, oldest = {}, 0, nil
			for _, a in ipairs(server.ammo) do
				if a.kind == "car" and not seen[a.load] then
					seen[a.load] = true
					n = n + 1
					oldest = oldest or a.load
				end
			end
			if n < MAX_CARS then break end
			deleteLoad(oldest)
		end
	end
end

-- one load body each (the body's origin is where it is spawned)
local AMMO_XML = {
	boulder = "<body dynamic='true' tags='catapult_ammo'><vox file='MOD/vox/boulder.vox' scale='3' tags='catapult_ammo'/></body>",
	barrel = "<body dynamic='true' tags='catapult_barrel catapult_ammo'><vox file='MOD/vox/barrel.vox' scale='3' tags='catapult_ammo'/></body>",
	crate = "<body dynamic='true' tags='catapult_ammo'><vox file='MOD/vox/crate.vox' scale='3' tags='catapult_ammo'/></body>",
	hulk = "<body dynamic='true' tags='catapult_ammo'><vox file='MOD/vox/hulk.vox' scale='3' tags='catapult_ammo'/></body>",
}

-- A thrown load must be in the simulation. In-game 17.10 (2a46c03) the boulder, the barrel and the crates,
-- asleep after lying still in the bucket, were moved to the release point (SetBodyTransform works on a
-- sleeping body) and hung there in the air: neither SetBodyActive(true), nor SetBodyVelocity, nor a
-- constraint brought them back into the simulation; only the car (a vehicle) flew. A body that has just
-- been spawned is awake, and SetBodyVelocity right after Spawn is how the game itself throws things
-- (data/script/snowball.lua, level/hub/script/skeet.lua). So a mod load is spawned anew at its place and
-- the old body deleted; its records follow the new handle. Returns the body and its shapes.
function server.respawnAwake(b, t)
	local a = nil
	for _, r in ipairs(server.ammo) do if r.body == b then a = r end end
	if a and a.xml then
		local ents = Spawn(a.xml, t)
		local nb, shapes = nil, {}
		for i = 1, #(ents or {}) do
			local ty = GetEntityType(ents[i])
			if ty == "body" and not nb then nb = ents[i] elseif ty == "shape" then shapes[#shapes + 1] = ents[i] end
		end
		if nb then
			if IsHandleValid(b) then Delete(b) end
			a.body = nb
			server.respawns = (server.respawns or 0) + 1
			-- old handle -> new one (the laws follow a thrown load by it); bounded
			server.replacedN = (server.replacedN or 0) + 1
			if server.replacedN > 300 then server.replaced, server.replacedN = {}, 1 end
			server.replaced = server.replaced or {}
			server.replaced[b] = nb
			return nb, shapes
		end
		deleteSpawned(ents)
	end
	-- not one of the mod's own loads (the game's car, anything else in the bucket): move it, wake it
	SetBodyTransform(b, t)
	SetBodyActive(b, true)
	return b, GetBodyShapes(b)
end

-- where each load group's bottom centre goes, relative to the bucket floor centre (catapult axes)
local CRATE_SLOTS = { { -0.5, 0, -0.5 }, { 0.5, 0, -0.5 }, { -0.5, 0, 0.5 }, { 0.5, 0, 0.5 }, { 0, 0.93, -0.5 }, { 0, 0.93, 0.5 } }

function server.load(c, kind)
	if c.broken or c.state ~= "ready" then return end
	-- an ammo key replaces this catapult's own load (in-game the auto-loaded boulder blocked the keys:
	-- "the bucket is not empty"); anything else lying in the bucket is left alone
	local inside = server.contents(c)
	local mine = {}
	for _, a in ipairs(server.ammo) do if a.cat == c.id then mine[a.body] = true end end
	for _, g in ipairs(c.groups or {}) do for _, b in ipairs(g.bodies) do mine[b] = true end end
	for _, b in ipairs(inside) do if not mine[b] then message("loaded") return end end
	for b in pairs(mine) do
		if IsHandleValid(b) and VecLength(VecSub(GetBodyTransform(b).pos, server.bucketFloor(c))) < 4 then Delete(b) end
	end
	local name = AMMO[kind] or "boulder"
	local floor = server.bucketFloor(c)
	local rot = GetBodyTransform(c.frame).rot
	-- spawned near the bucket (its exact place is measured once it exists, see server.placeLoad)
	local ents
	local groups = {}
	-- the text of each body (in spawn order), kept so that the body can be spawned anew, awake, when it is
	-- thrown (see server.respawnAwake); none for the game's car prefab
	local xmls = {}
	if name == "boulder" then
		trimAmmo(1, name)
		xmls[1] = AMMO_XML.boulder
		ents = Spawn(xmls[1], Transform(VecAdd(floor, Vec(0, 1.0, 0)), rot))
		groups[1] = { slot = Vec(0, 0, 0) }
	elseif name == "barrel" then
		trimAmmo(1, name)
		xmls[1] = AMMO_XML.barrel
		ents = Spawn(xmls[1], Transform(VecAdd(floor, Vec(0, 1.0, 0)), rot))
		groups[1] = { slot = Vec(0, 0, 0) }
	elseif name == "crates" then
		trimAmmo(6, name)
		local xml = ""
		for i = 1, #CRATE_SLOTS do
			local s = CRATE_SLOTS[i]
			xml = xml .. "<body dynamic='true' tags='catapult_ammo' pos='" .. fmt3(Vec(s[1], s[2] + 0.5, s[3])) .. "'><vox file='MOD/vox/crate.vox' scale='3' tags='catapult_ammo'/></body>"
			groups[i] = { slot = Vec(s[1], s[2], s[3]) }
			xmls[i] = AMMO_XML.crate
		end
		ents = Spawn(prefabXml("catapult_crates", xml), Transform(floor, rot))
	elseif name == "car" then
		trimAmmo(5, name)
		-- the game's own small car if its prefab can be spawned, else the mod's car body; it is wider than
		-- the bucket, so it lies on the rim
		local t = Transform(VecAdd(floor, Vec(0, 2.0, 0)), QuatRotateQuat(rot, QuatEuler(0, 90, 0)))
		ents = Spawn("BUILT-IN/prefab/vehicle/land/generic_small_blue.xml", t)
		local any = false
		for i = 1, #(ents or {}) do if GetEntityType(ents[i]) == "body" then any = true SetTag(ents[i], "catapult_ammo") end end
		if not any then
			xmls[1] = AMMO_XML.hulk
			ents = Spawn(xmls[1], t)
		end
		groups[1] = { slot = Vec(0, 0, 0), rim = true, all = true }
	end
	local bodies = {}
	server.loadN = server.loadN + 1
	for i = 1, #(ents or {}) do
		if GetEntityType(ents[i]) == "body" then
			bodies[#bodies + 1] = ents[i]
			server.ammo[#server.ammo + 1] = { body = ents[i], kind = name, cat = c.id, load = server.loadN, xml = xmls[#bodies] }
		end
	end
	-- one body per group (crates: in spawn order), or all bodies in one group (the car and its wheels)
	for i, g in ipairs(groups) do
		g.bodies = g.all and bodies or { bodies[i] }
		g.placed = false
		g.tries = 0
	end
	c.groups = groups
	c.loaded = name
	c.loadMoved = nil
	-- for the debug line (11.10: "the ammo sometimes does not spawn at all")
	c.loadDbg = string.format("%s: Spawn gave %d entities, %d bodies", name, #(ents or {}), #bodies)
	print("catapult: load " .. c.loadDbg)
end

-- once a load group exists (real bounds), move it so that it lies on the bucket floor (the car on the
-- rim), at its slot, at rest; then hold it there. In-game 16.10 "the ammo spawns crooked": it was put
-- where a guessed pivot said, not where it really was.
function server.placeLoad(c)
	local floor = server.bucketFloor(c)
	local rot = GetBodyTransform(c.frame).rot
	local armT = GetBodyTransform(c.arm)
	for _, g in ipairs(c.groups or {}) do
		if not g.placed and #g.bodies > 0 then
			g.tries = g.tries + 1
			local ready = true
			for _, b in ipairs(g.bodies) do if not (IsHandleValid(b) and server.bodyReady(b)) then ready = false end end
			if ready then
				local mn, mx = groupBounds(g.bodies)
				local bottom = Vec((mn[1] + mx[1]) / 2, mn[2], (mn[3] + mx[3]) / 2)
				local base = g.rim and Vec(floor[1], server.bucketRim(c), floor[3]) or floor
				local target = VecAdd(TransformToParentPoint(Transform(base, rot), g.slot), Vec(0, 0.02, 0))
				local d = VecSub(target, bottom)
				for _, b in ipairs(g.bodies) do
					local t = GetBodyTransform(b)
					SetBodyTransform(b, Transform(VecAdd(t.pos, d), t.rot))
					SetBodyVelocity(b, Vec(0, 0, 0))
					SetBodyAngularVelocity(b, Vec(0, 0, 0))
				end
				g.placed = true
				g.offs = {}
				for i, b in ipairs(g.bodies) do g.offs[i] = TransformToLocalPoint(armT, VecAdd(GetBodyTransform(b).pos, Vec(0, 0, 0))) end
				c.loadMoved = math.max(c.loadMoved or 0, VecLength(d))
			elseif g.tries > 60 then
				g.placed = true            -- give up placing; it rests where it is (shown as not in the bucket)
				g.offs = {}
			end
		end
	end
end

-- how many load groups lie in the bucket: centre over the bucket, bottom between the floor and the rim
function server.loadInBucket(c)
	local n, m = 0, 0
	local floor = server.bucketFloor(c)
	local rim = server.bucketRim(c)
	local lowest = nil
	for _, g in ipairs(c.groups or {}) do
		m = m + 1
		local alive = #g.bodies > 0
		for _, b in ipairs(g.bodies) do if not IsHandleValid(b) then alive = false end end
		if alive then
			local mn, mx = groupBounds(g.bodies)
			local cx, cz = (mn[1] + mx[1]) / 2, (mn[3] + mx[3]) / 2
			if math.sqrt((cx - floor[1]) ^ 2 + (cz - floor[3]) ^ 2) < 1.3 and mn[2] > floor[2] - 0.3 and mn[2] < rim + 0.6 then
				n = n + 1
				lowest = math.min(lowest or 99, mn[2] - floor[2])
			end
		end
	end
	return n, m, lowest
end

-- `riders`: players put into the bucket by RMB this update ({ p, pos }; their transform may not read back
-- until the next update)
function server.fire(c, riders)
	if c.broken or c.state ~= "ready" then return end
	local bodies, players = server.contents(c)
	-- also every body of the loaded groups (a car's wheels may stick out of the bucket's box)
	local seen = {}
	for _, b in ipairs(bodies) do seen[b] = true end
	for _, g in ipairs(c.groups or {}) do
		for _, b in ipairs(g.bodies) do if IsHandleValid(b) and not seen[b] and VecLength(VecSub(GetBodyTransform(b).pos, server.bucketFloor(c))) < 4 then bodies[#bodies + 1] = b seen[b] = true end end
	end
	local armT = GetBodyTransform(c.arm)
	c.held = {}
	for i = 1, #bodies do
		local b = bodies[i]
		if IsHandleValid(b) then
			local kind = "other"
			for j = 1, #server.ammo do if server.ammo[j].body == b then kind = server.ammo[j].kind end end
			c.held[#c.held + 1] = { body = b, off = TransformToLocalPoint(armT, GetBodyTransform(b).pos), kind = kind }
			-- a load lying still is out of the simulation, and neither a constraint nor SetBodyVelocity wakes it:
			-- in-game 17.10 the arm swung through the boulder, the barrel and the crates
			SetBodyActive(b, true)
		end
	end
	c.heldPlayers = {}
	local isRider = {}
	for _, r in ipairs(riders or {}) do
		isRider[r.p] = true
		c.heldPlayers[#c.heldPlayers + 1] = { p = r.p, off = TransformToLocalPoint(armT, r.pos) }
	end
	for i = 1, #players do
		local p = players[i]
		if not isRider[p] then c.heldPlayers[#c.heldPlayers + 1] = { p = p, off = TransformToLocalPoint(armT, GetPlayerTransform(p).pos) } end
	end
	-- a thrown player passes through the catapult's arm and frame until shortly after the release (the
	-- player stands in the bucket, which would stop him at the release point)
	for _, hp in ipairs(c.heldPlayers) do server.ghostPlayer(hp.p, true) end
	c.state = "swing"
	c.t = 0
	c.shotFrom = c.psiRest + c.theta
	c.shotTo = c.shotFrom
	shared.cp.fireN = shared.cp.fireN + 1
	local fp = GetBodyTransform(c.frame).pos
	shared.cp.fx, shared.cp.fy, shared.cp.fz = fp[1], fp[2], fp[3]
	server.sync()
end

-- the arm angle (degrees turned up from rest) at which the load is released: the bucket then moves at the
-- set launch angle
function server.releaseTheta(c)
	return clamp((90 - c.angle) - (c.psiRest or -REST), 0, 170)
end
-- where the load starts its flight: the loaded body's place on the arm at the release angle (the arc
-- preview starts here)
function server.releasePoint(c)
	if not (c.arm and IsHandleValid(c.arm) and c.pivotLocal) then return nil end
	local pose = server.armPose(c, server.releaseTheta(c))
	local g = c.groups and c.groups[1]
	if g and g.placed and g.offs and g.offs[1] then return TransformToParentPoint(pose, g.offs[1]) end
	if not (c.bucket and IsHandleValid(c.bucket)) then return nil end
	local now = server.armPose(c, c.theta or 0)
	return TransformToParentPoint(pose, TransformToLocalPoint(now, server.bucketCentre(c)))
end

-- the release: the arm stops at exactly the release angle, every held body is put at its place in the
-- bucket at that angle and given exactly the planned velocity, and it passes through its catapult while
-- it leaves. In-game 17.10 "the shots do not fly along the trajectory": in the release update the swing
-- had already put the load on a position constraint towards the moving arm and given the arm its full
-- swing speed; the game solves constraints in the physics step after the script, so the load left with
-- the bucket's speed (about 50 m/s at any power) instead of the planned one.
-- a released load does not collide with any catapult's arm or frame for GHOST_TIME (kept in `ghost`)
function server.ghostShapes(ghost, shapes)
	for _, sh in ipairs(shapes or {}) do
		if IsHandleValid(sh) then
			local layer, mask = GetShapeCollisionFilter(sh)
			ghost.shapes[#ghost.shapes + 1] = { sh = sh, layer = layer, mask = mask }
			SetShapeCollisionFilter(sh, LAYER_LOAD, 255 - LAYER_ARM - LAYER_FRAME)
		end
	end
end
-- the same for a player (CollisionMask: the player's mask against the shapes' layers, script_defs)
function server.ghostPlayer(p, on)
	server.playerMask = server.playerMask or {}
	if on then
		if server.playerMask[p] == nil then
			local m = GetPlayerParam("CollisionMask", p)
			server.playerMask[p] = (type(m) == "number" and m > 0) and m or 255
		end
		SetPlayerParam("CollisionMask", 255 - LAYER_ARM - LAYER_FRAME, p)
	elseif server.playerMask[p] ~= nil then
		SetPlayerParam("CollisionMask", server.playerMask[p], p)
		server.playerMask[p] = nil
	end
end

-- RMB with the catapult tool: the player rides. In-game 17.10: "RMB load should load me into the catapult
-- and send me" - it loaded the selected ammo again. The bucket's own load goes (the rider is not thrown
-- together with a boulder), the player is put on the bucket floor and the catapult fires at once.
function server.ride(c, p)
	if c.broken or c.state ~= "ready" then return end
	local floor = server.bucketFloor(c)
	local keep = {}
	for _, a in ipairs(server.ammo) do
		if a.cat == c.id and IsHandleValid(a.body) and VecLength(VecSub(GetBodyTransform(a.body).pos, floor)) < 4 then Delete(a.body) else keep[#keep + 1] = a end
	end
	server.ammo = keep
	c.groups = {}
	c.loaded = nil
	local pos = VecAdd(floor, Vec(0, 0.05, 0))
	SetPlayerTransform(Transform(pos, GetPlayerTransform(p).rot), p)
	SetPlayerVelocity(Vec(0, 0, 0), p)
	c.rides = (c.rides or 0) + 1
	server.fire(c, { { p = p, pos = pos } })
end

function server.releaseLoad(c, theta)
	local fwd = VecScale(server.back(c), -1)
	local th = math.rad(c.angle)
	local speed = launchSpeed(c.power)
	local v = VecAdd(VecScale(fwd, speed * math.cos(th)), Vec(0, speed * math.sin(th), 0))
	local pose = server.armPose(c, theta or c.theta)
	local spin = Vec(rnd(-1.5, 1.5), rnd(-1.5, 1.5), rnd(-1.5, 1.5))
	local ghost = { shapes = {}, t = 0 }
	for i = 1, #c.held do
		local h = c.held[i]
		if IsHandleValid(h.body) then
			local at = Transform(TransformToParentPoint(pose, h.off), GetBodyTransform(h.body).rot)
			-- a fresh, awake copy of a mod load (see server.respawnAwake)
			local b, shapes = server.respawnAwake(h.body, at)
			h.body = b
			SetBodyVelocity(b, v)
			-- one spin for the whole load; none for the car (its wheels spinning apart from its body would
			-- tear them off)
			SetBodyAngularVelocity(b, (h.kind == "car") and Vec(0, 0, 0) or spin)
			server.ghostShapes(ghost, shapes)
			if #server.flying < MAX_FLYING then
				server.flying[#server.flying + 1] = { body = b, kind = h.kind, t = 0, prev = VecCopy(v), n = 0, from = VecCopy(server.bucketFloor(c)), cat = c.id,
					p0 = VecCopy(at.pos), v0 = VecCopy(v), tries = 0 }
			end
		end
	end
	if #ghost.shapes > 0 then server.ghosts[#server.ghosts + 1] = ghost end
	for i = 1, #c.heldPlayers do
		local hp = c.heldPlayers[i]
		-- at its place in the bucket at the release angle (where the arc preview starts), then the velocity:
		-- SetPlayerTransform resets the player's velocity (script_defs)
		local pt = GetPlayerTransform(hp.p)
		SetPlayerTransform(Transform(TransformToParentPoint(pose, hp.off), pt.rot), hp.p)
		SetPlayerVelocity(v, hp.p)
		server.protect[hp.p] = { t = 0, ghost = true }
	end
	c.lastLaunch = { pos = server.bucketFloor(c), vel = v, speed = speed, psi = c.psiRest + (theta or c.theta), held = #c.held + #c.heldPlayers }
	c.lastShot = string.format("last shot: angle %+.0f -> %+.0f, released %d at %.0f m/s", c.shotFrom or 0, c.psiRest + (theta or c.theta), #c.held + #c.heldPlayers, speed)
	c.held = {}
	c.heldPlayers = {}
	c.loaded = nil
	c.groups = {}
	c.state = "reset"
	c.t = 0
	shared.cp.relN = shared.cp.relN + 1
end

function server.update(dt)
	local s = readSettings()
	server.stepPending()
	for i = #server.cats, 1, -1 do
		local c = server.cats[i]
		if not IsHandleValid(c.frame) or not IsHandleValid(c.arm) or not IsHandleValid(c.axle) or not IsHandleValid(c.hub) then
			if not c.broken then
				c.broken = true
				c.state = "broken"
				-- a player held in the bucket when it broke collides with everything again
				for _, hp in ipairs(c.heldPlayers or {}) do server.ghostPlayer(hp.p, false) end
				c.heldPlayers = {}
				server.sync()
			end
		elseif c.state == "settle" then
			c.t = c.t + dt
			server.holdArm(c, 0)
			local amn, amx = GetShapeBounds(c.axle)
			local bmn, bmx = GetShapeBounds(c.bucket)
			if c.t > 0.05 and validBounds(amn, amx) and validBounds(bmn, bmx) then
				c.psiRest = server.psi(c)
				c.armLen = VecLength(VecSub(server.bucketCentre(c), server.pivot(c)))
				c.state = "ready"
				c.t = 0
				server.load(c, c.ammo)
				server.debugInfo(c)
				server.sync()
			end
		elseif c.state == "ready" then
			c.theta = 0
			server.holdArm(c, 0)
			server.placeLoad(c)
			local armT = GetBodyTransform(c.arm)
			for _, g in ipairs(c.groups or {}) do
				if g.placed then
					for k, b in ipairs(g.bodies) do
						if IsHandleValid(b) and g.offs[k] then
							ConstrainPosition(b, 0, GetBodyTransform(b).pos, TransformToParentPoint(armT, g.offs[k]), 4)
						end
					end
				end
			end
			c.dbgT = (c.dbgT or 0) - dt
			if c.dbgT <= 0 then c.dbgT = 0.5 server.debugInfo(c) server.sync() end
		elseif c.state == "swing" then
			c.t = c.t + dt
			local relTheta = server.releaseTheta(c)
			if c.theta + SWING * dt >= relTheta or c.theta + SWING * dt >= 170 then
				-- the release update: the load leaves from its place at exactly the release angle and nothing
				-- pulls it towards the arm any more (see server.releaseLoad); the arm stops where the last
				-- physics step really took it (measured: a step past the angle it was set to), so it does
				-- not jerk back
				c.theta = clamp(server.psi(c) - c.psiRest, c.theta, 170)
				c.shotTo = c.psiRest + relTheta
				server.holdArm(c, 0)
				server.releaseLoad(c, relTheta)
				server.debugInfo(c)
				server.sync()
			else
				c.theta = c.theta + SWING * dt
				server.holdArm(c, SWING)
				c.shotTo = c.psiRest + c.theta
				local armT, P, axis = server.armPose(c, c.theta)
				local wv = VecScale(axis, -math.rad(SWING))
				-- the load is carried with the bucket by moving it (a constraint does not move a load asleep
				-- in the bucket - in-game 17.10 - and SetBodyTransform does), at the bucket's velocity
				for j = 1, #c.held do
					local h = c.held[j]
					if IsHandleValid(h.body) then
						local at = TransformToParentPoint(armT, h.off)
						SetBodyTransform(h.body, Transform(at, GetBodyTransform(h.body).rot))
						SetBodyVelocity(h.body, VecCross(wv, VecSub(at, P)))
					end
				end
				for j = 1, #c.heldPlayers do
					local hp = c.heldPlayers[j]
					SetPlayerTransform(Transform(TransformToParentPoint(armT, hp.off), GetPlayerTransform(hp.p).rot), hp.p)
					SetPlayerVelocity(Vec(0, 0, 0), hp.p)
				end
				c.dbgT = (c.dbgT or 0) - dt
				if c.dbgT <= 0 then c.dbgT = 0.1 server.debugInfo(c) server.sync() end
			end
		elseif c.state == "reset" then
			c.t = c.t + dt
			local w = 0
			if c.t > 0.5 and c.theta > 0 then
				c.theta = math.max(0, c.theta - RESET * dt)
				w = -RESET
			end
			server.holdArm(c, w)
			c.dbgT = (c.dbgT or 0) - dt
			if c.dbgT <= 0 then c.dbgT = 0.25 server.debugInfo(c) server.sync() end
			if c.t > 1.0 and c.theta <= 0 then
				c.state = "ready"
				c.t = 0
				if s.reload then server.load(c, c.ammo) end
				server.sync()
			end
		end
	end
	-- released loads collide with their catapult again once they are away from it
	for i = #server.ghosts, 1, -1 do
		local g = server.ghosts[i]
		g.t = g.t + dt
		if g.t >= GHOST_TIME then
			for _, e in ipairs(g.shapes) do if IsHandleValid(e.sh) then SetShapeCollisionFilter(e.sh, e.layer, e.mask) end end
			table.remove(server.ghosts, i)
		end
	end
	server.updateFlying(dt, s)
end

-- a released load that does not really move (measured by its position, not GetBodyVelocity, which returns
-- the set velocity of a sleeping body) is put where its arc says it should be by now, awake, with the
-- arc's velocity; up to 3 times. The debug line counts these ("stuck").
function server.flightCheck(f)
	if not f.p0 or f.moving or f.t < 0.1 then return end
	local moved = VecLength(VecSub(GetBodyTransform(f.body).pos, f.p0))
	if moved >= 0.3 * VecLength(f.v0) * f.t then f.moving = true return end
	if f.tries >= 3 then f.moving = true return end
	-- something in the way of the arc right there is a real hit, not a sleeping body
	local cur = GetBodyTransform(f.body).pos
	local g0 = GetGravity()
	local want = VecAdd(VecAdd(f.p0, VecScale(f.v0, f.t)), VecScale(g0, 0.5 * f.t * f.t))
	local d = VecSub(want, cur)
	local l = VecLength(d)
	if l > 0.01 then
		QueryRejectBody(f.body)
		QueryRequire("physical")
		for _, c in ipairs(server.cats) do QueryRejectBody(c.frame) QueryRejectBody(c.arm) end
		if QueryRaycast(cur, VecScale(d, 1 / l), l) then f.moving = true return end
	end
	f.tries = f.tries + 1
	server.stuck = (server.stuck or 0) + 1
	local g = GetGravity()
	local p = VecAdd(VecAdd(f.p0, VecScale(f.v0, f.t)), VecScale(g, 0.5 * f.t * f.t))
	local v = VecAdd(f.v0, VecScale(g, f.t))
	local b, shapes = server.respawnAwake(f.body, Transform(p, GetBodyTransform(f.body).rot))
	f.body = b
	SetBodyVelocity(b, v)
	local ghost = { shapes = {}, t = 0 }
	server.ghostShapes(ghost, shapes)
	if #ghost.shapes > 0 then server.ghosts[#server.ghosts + 1] = ghost end
	f.p0, f.v0, f.t, f.prev = p, v, 0, VecCopy(v)
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
			server.flightCheck(f)
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

-- how far each part is from where it should be now (frame parts: designed place; arm parts: designed
-- place turned by the current arm angle), metres
function server.partsOff(c)
	local fT = server.catT(c)
	local P = TransformToParentPoint(fT, c.pivotLocal)
	local axis = QuatRotateVec(fT.rot, Vec(1, 0, 0))
	local q = QuatAxisAngle(axis, -c.theta)
	local shapes = { frame = c.frameShape, axle = c.axle, hub = c.hub, beam_long = c.beamLong, beam_short = c.beamShort, bucket = c.bucket, weight = c.weight }
	local out, worst = {}, 0
	for _, n in ipairs(PARTS) do
		local sh = shapes[n]
		local d = 99
		if sh and sh ~= 0 and IsHandleValid(sh) then
			local want = TransformToParentPoint(fT, c.design[n].c)
			if ARM_PARTS[n] then want = VecAdd(P, QuatRotateVec(q, VecSub(want, P))) end
			d = VecLength(VecSub((boundsCentre(sh)), want))
		end
		out[n] = d
		worst = math.max(worst, d)
	end
	return out, worst
end
-- the hub's distance from the axle's axis (the scripted hinge holds it at 0)
function server.hubOffAxle(c)
	local ac = server.pivot(c)
	local axis = QuatRotateVec(GetBodyTransform(c.frame).rot, Vec(1, 0, 0))
	local d = VecSub((boundsCentre(c.hub)), ac)
	return VecLength(VecSub(d, VecScale(axis, VecDot(d, axis))))
end

-- three lines of measured numbers for in-game diagnosis (16.10: one long line was cut off by the
-- screen edge)
function server.debugInfo(c)
	local off = server.partsOff(c)
	local parts = ""
	for _, n in ipairs(PARTS) do parts = parts .. string.format(" %s %.2f", n, off[n]) end
	local hub = server.hubOffAxle(c)
	local hinge = string.format("hinge script hub%s %.2f m (no joint)", hub <= TOL and "-axle" or " OFF the axle", hub)
	local n, m, lowest = server.loadInBucket(c)
	local placed = 0
	for _, g in ipairs(c.groups or {}) do if g.placed then placed = placed + 1 end end
	local l1 = string.format("catapult: %s | parts off m:%s | spawns %d", c.state, parts, c.spawns or 0)
	local l2 = string.format("%s | arm angle %+.0f (rest %+.0f) | %s | respawned awake %d, stuck %d, rides %d | fire: Q or E",
		hinge, server.psi(c), c.psiRest or -REST, c.lastShot or "no shot yet", server.respawns or 0, server.stuck or 0, c.rides or 0)
	local l3 = string.format("load %d/%d in bucket | %s | placed %d/%d%s%s", n, m, c.loadDbg or "no load yet", placed, #(c.groups or {}),
		c.loadMoved and string.format(", moved into place by %.2f m", c.loadMoved) or "",
		lowest and string.format(", lowest %.2f m above the floor", lowest) or "")
	c.dbg = l1 .. "\n" .. l2 .. "\n" .. l3
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

-- turn the whole machine (frame, arm and whatever is in the bucket) about its base; the arm's pose is
-- kept relative to the frame, so it follows the frame
function server.turn(c, deg)
	local oldT = Transform(c.base, QuatEuler(0, c.yaw, 0))
	c.yaw = c.yaw + deg
	local newT = Transform(c.base, QuatEuler(0, c.yaw, 0))
	local bodies = server.contents(c)
	local all = { c.frame }
	for i = 1, #bodies do all[#all + 1] = bodies[i] end
	for i = 1, #all do
		local rel = TransformToLocalTransform(oldT, GetBodyTransform(all[i]))
		SetBodyTransform(all[i], TransformToParentTransform(newT, rel))
	end
	server.holdArm(c, 0)
end

-- R: everything this mod ever spawned goes, found by tag (also pieces broken off, catapults that
-- were never registered, and parts tagged by the first version: catapult / catapult_arm)
function server.clear()
	for _, tag in ipairs({ "catapult_part", "catapult_ammo", "catapult", "catapult_arm", "catapult_barrel", "catapult_measure" }) do
		local list = FindBodies(tag, true)
		for i = 1, #list do if IsHandleValid(list[i]) then Delete(list[i]) end end
		local shapes = FindShapes(tag, true)
		for i = 1, #shapes do if IsHandleValid(shapes[i]) then Delete(shapes[i]) end end
	end
	for i = 1, #server.cats do
		local c = server.cats[i]
		if IsHandleValid(c.arm) then Delete(c.arm) end
		if IsHandleValid(c.frame) then Delete(c.frame) end
	end
	for i = 1, #server.ammo do if IsHandleValid(server.ammo[i].body) then Delete(server.ammo[i].body) end end
	if server.pending then deleteSpawned(server.pending.ents) server.pending = nil end
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
	-- in-game 10.10 a failed assembly said "aim at open ground": the ground was fine
	assembly = { "The catapult did not assemble (the game did not create all its parts) - removed, try again",
		"Катапульта не собралась (игра создала не все её части) - убрана, попробуйте ещё раз" },
}
local MESSAGE_TIME = { assembly = 6 }
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
		if m then client.msg, client.msgT = tr(m[1], m[2]), MESSAGE_TIME[cp.msg] or 2 end
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
		-- Q fires: F is the game's flashlight and C its camera view (data/input_settings.xml), so the
		-- fire key moved off F and turning off C (in-game 16.10: "F turns the flashlight on")
		if InputPressed("q") then ServerCall("server.cmd", me, c.id, "fire", 0) end
		if InputPressed("v") then ServerCall("server.cmd", me, c.id, "angle", c.angle - 5) end
		if InputPressed("b") then ServerCall("server.cmd", me, c.id, "angle", c.angle + 5) end
		for k = 1, 4 do if InputPressed(tostring(k)) then ServerCall("server.cmd", me, c.id, "ammo", k) end end
		local turn = (InputDown("z") and 1 or 0) - (InputDown("x") and 1 or 0)
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
	local amn, amx = GetShapeBounds(c.axle)
	local P = VecLerp(amn, amx, 0.5)
	local back = QuatRotateVec(GetBodyTransform(c.frame).rot, Vec(0, 0, 1))
	local psi = math.rad(90 - c.angle)
	local R = VecAdd(P, VecAdd(VecScale(back, c.armLen * math.cos(psi)), Vec(0, c.armLen * math.sin(psi), 0)))
	-- the server's release point: the loaded body's own place on the arm at the release angle
	if c.rx then R = Vec(c.rx, c.ry, c.rz) end
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
	local sel = client.sel
	if readSettings().debug then
		local text = (sel and sel.dbg and sel.dbg ~= "") and sel.dbg or "catapult: none selected"
		local lines = {}
		for l in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
		local reason = shared.cp.reason or ""
		if reason ~= "" then lines[#lines + 1] = reason end
		UiPush()
			UiTranslate(20, UiHeight() - 24 - 22 * (#lines - 1))
			UiAlign("left middle")
			UiFont("regular.ttf", 16)
			UiTextShadow(0, 0, 0, 0.8, 1)
			UiColor(1, 1, 0.6, 0.95)
			for i = 1, #lines do
				UiText(lines[i])
				UiTranslate(0, 22)
			end
		UiPop()
	end
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
			UiText(tr("Q or E: fire   Wheel: power   Z/X: turn   V/B: angle   1-4: ammo   RMB: ride   R: remove all",
				"Q или E: выстрел   Колесо: сила   Z/X: поворот   V/B: угол   1-4: снаряд   ПКМ: полететь самому   R: убрать все"))
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
