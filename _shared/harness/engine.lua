-- Fake Teardown engine for offline testing of mod scripts (Lua 5.1).
-- Loaded into one lupa Lua51 runtime. The mod script itself runs in its own
-- environment table(s) created by H.loadMod; the API functions below are
-- visible to those environments through __index.
--
-- Every API function goes through a checker that:
--   * fails on calls to functions not listed in script_defs.lua
--   * validates required argument presence and basic types (number, string,
--     boolean, TVec, TQuat, TTransform)
--   * counts calls per frame (max per frame kept for budget checks)
--   * enforces that Ui* functions are only used inside draw callbacks

H = {}
H.errors = {}          -- list of strings
H.warnings = {}
H.calls = {}           -- name -> total calls
H.frameCalls = {}      -- name -> calls in current frame
H.maxFrameCalls = {}   -- name -> max calls in any frame
H.sideCalls = { server = {}, client = {}, legacy = {}, scenario = {} }
H.unknown = {}         -- names looked up but not provided
H.frame = 0
H.time = 0
H.dt = 1/60
H.ctx = "scenario"     -- current callback context: server/client/legacy/scenario
H.cbName = ""          -- current callback name (e.g. "client.draw")
H.log = {}             -- free-form event log (strings)
H.uiTexts = {}         -- texts drawn this frame
H.uiClicks = {}        -- label -> true to simulate a button click this frame
H.uiSliderSet = {}     -- index -> value to simulate slider drag
H.uiSliderIndex = 0
H.uiButtonsSeen = {}
H.modDir = ""
H.dataDir = ""
H.fileExists = nil     -- set from python: function(path) -> bool
H.API = {}             -- name -> function
H.SPEC = {}            -- set from python: name -> {params={{n,t,opt}}, returns={t...}, varargs=bool}

local function err(msg)
	local tb = debug.traceback("", 3)
	table.insert(H.errors, string.format("[frame %d %s] %s%s", H.frame, H.cbName, msg, tb))
end
H.err = err
function H.warn(msg) table.insert(H.warnings, string.format("[frame %d %s] %s", H.frame, H.cbName, msg)) end
function H.note(msg) table.insert(H.log, string.format("[%d] %s", H.frame, msg)) end

---------------------------------------------------------------------------
-- math helpers (real implementations; scripts depend on correct math)
---------------------------------------------------------------------------
local sqrt, sin, cos, acos, atan2, rad, deg = math.sqrt, math.sin, math.cos, math.acos, math.atan2, math.rad, math.deg

local function V(x, y, z) return { x or 0, y or 0, z or 0 } end
local function Q(x, y, z, w) return { x or 0, y or 0, z or 0, w or 1 } end

local A = H.API
A.Vec = function(x, y, z) return V(x, y, z) end
A.VecCopy = function(v) return V(v[1], v[2], v[3]) end
A.VecStr = function(v) return string.format("%.2f, %.2f, %.2f", v[1], v[2], v[3]) end
A.VecLength = function(v) return sqrt(v[1]*v[1] + v[2]*v[2] + v[3]*v[3]) end
A.VecNormalize = function(v)
	local l = sqrt(v[1]*v[1] + v[2]*v[2] + v[3]*v[3])
	if l < 1e-9 then return V(0, 0, 0) end
	return V(v[1]/l, v[2]/l, v[3]/l)
end
A.VecScale = function(v, s) return V(v[1]*s, v[2]*s, v[3]*s) end
A.VecAdd = function(a, b) return V(a[1]+b[1], a[2]+b[2], a[3]+b[3]) end
A.VecSub = function(a, b) return V(a[1]-b[1], a[2]-b[2], a[3]-b[3]) end
A.VecDot = function(a, b) return a[1]*b[1] + a[2]*b[2] + a[3]*b[3] end
A.VecCross = function(a, b) return V(a[2]*b[3]-a[3]*b[2], a[3]*b[1]-a[1]*b[3], a[1]*b[2]-a[2]*b[1]) end
A.VecLerp = function(a, b, t) return V(a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t, a[3]+(b[3]-a[3])*t) end

local function qmul(a, b)
	return Q(
		a[4]*b[1] + a[1]*b[4] + a[2]*b[3] - a[3]*b[2],
		a[4]*b[2] - a[1]*b[3] + a[2]*b[4] + a[3]*b[1],
		a[4]*b[3] + a[1]*b[2] - a[2]*b[1] + a[3]*b[4],
		a[4]*b[4] - a[1]*b[1] - a[2]*b[2] - a[3]*b[3])
end
local function qconj(q) return Q(-q[1], -q[2], -q[3], q[4]) end
local function qrot(q, v)
	local p = qmul(qmul(q, Q(v[1], v[2], v[3], 0)), qconj(q))
	return V(p[1], p[2], p[3])
end
local function qnorm(q)
	local l = sqrt(q[1]*q[1]+q[2]*q[2]+q[3]*q[3]+q[4]*q[4])
	if l < 1e-12 then return Q() end
	return Q(q[1]/l, q[2]/l, q[3]/l, q[4]/l)
end
A.Quat = function(x, y, z, w) return Q(x, y, z, w) end
A.QuatCopy = function(q) return Q(q[1], q[2], q[3], q[4]) end
A.QuatAxisAngle = function(axis, angle)
	local n = A.VecNormalize(axis)
	local h = rad(angle) * 0.5
	local s = sin(h)
	return Q(n[1]*s, n[2]*s, n[3]*s, cos(h))
end
A.QuatEuler = function(x, y, z)
	-- yaw (y) * pitch (x) * roll (z)
	local qx = A.QuatAxisAngle(V(1,0,0), x or 0)
	local qy = A.QuatAxisAngle(V(0,1,0), y or 0)
	local qz = A.QuatAxisAngle(V(0,0,1), z or 0)
	return qmul(qmul(qy, qx), qz)
end
A.GetQuatEuler = function(q)
	local x, y, z, w = q[1], q[2], q[3], q[4]
	local sinp = 2*(w*x - y*z)
	if sinp > 1 then sinp = 1 elseif sinp < -1 then sinp = -1 end
	local pitch = math.asin(sinp)
	local yaw = atan2(2*(w*y + x*z), 1 - 2*(x*x + y*y))
	local roll = atan2(2*(w*z + x*y), 1 - 2*(x*x + z*z))
	return deg(pitch), deg(yaw), deg(roll)
end
A.QuatDeltaNormals = function(n0, n1)
	local d = A.VecDot(n0, n1)
	if d > 0.99999 then return Q() end
	if d < -0.99999 then
		local axis = A.VecCross(V(1,0,0), n0)
		if A.VecLength(axis) < 0.01 then axis = A.VecCross(V(0,1,0), n0) end
		return A.QuatAxisAngle(axis, 180)
	end
	local c = A.VecCross(n0, n1)
	return qnorm(Q(c[1], c[2], c[3], 1 + d))
end
A.QuatDeltaVectors = function(a, b) return A.QuatDeltaNormals(A.VecNormalize(a), A.VecNormalize(b)) end
A.QuatAlignXZ = function(xAxis, zAxis)
	local x = A.VecNormalize(xAxis)
	local z = A.VecNormalize(zAxis)
	local y = A.VecNormalize(A.VecCross(z, x))
	x = A.VecCross(y, z)
	-- rotation matrix columns x,y,z -> quaternion
	local m00, m11, m22 = x[1], y[2], z[3]
	local tr = m00 + m11 + m22
	local q
	if tr > 0 then
		local s = sqrt(tr + 1) * 2
		q = Q((y[3]-z[2])/s, (z[1]-x[3])/s, (x[2]-y[1])/s, 0.25*s)
	elseif m00 > m11 and m00 > m22 then
		local s = sqrt(1 + m00 - m11 - m22) * 2
		q = Q(0.25*s, (y[1]+x[2])/s, (z[1]+x[3])/s, (y[3]-z[2])/s)
	elseif m11 > m22 then
		local s = sqrt(1 + m11 - m00 - m22) * 2
		q = Q((y[1]+x[2])/s, 0.25*s, (z[2]+y[3])/s, (z[1]-x[3])/s)
	else
		local s = sqrt(1 + m22 - m00 - m11) * 2
		q = Q((z[1]+x[3])/s, (z[2]+y[3])/s, 0.25*s, (x[2]-y[1])/s)
	end
	return qnorm(q)
end
A.QuatLookAt = function(eye, target)
	local f = A.VecNormalize(A.VecSub(target, eye))
	if A.VecLength(f) < 0.5 then return Q() end
	local z = A.VecScale(f, -1)
	local up = V(0,1,0)
	if math.abs(A.VecDot(up, z)) > 0.999 then up = V(0,0,1) end
	local x = A.VecNormalize(A.VecCross(up, z))
	return A.QuatAlignXZ(x, z)
end
A.QuatSlerp = function(a, b, t)
	local d = a[1]*b[1]+a[2]*b[2]+a[3]*b[3]+a[4]*b[4]
	local bb = b
	if d < 0 then d = -d; bb = Q(-b[1], -b[2], -b[3], -b[4]) end
	if d > 0.9995 then
		return qnorm(Q(a[1]+(bb[1]-a[1])*t, a[2]+(bb[2]-a[2])*t, a[3]+(bb[3]-a[3])*t, a[4]+(bb[4]-a[4])*t))
	end
	local th = acos(d)
	local s0 = sin((1-t)*th)/sin(th)
	local s1 = sin(t*th)/sin(th)
	return Q(a[1]*s0+bb[1]*s1, a[2]*s0+bb[2]*s1, a[3]*s0+bb[3]*s1, a[4]*s0+bb[4]*s1)
end
A.QuatStr = function(q) return string.format("%.2f, %.2f, %.2f, %.2f", q[1], q[2], q[3], q[4]) end
A.QuatRotateQuat = function(a, b) return qmul(a, b) end
A.QuatRotateVec = function(q, v) return qrot(q, v) end
A.Transform = function(pos, rot) return { pos = pos and V(pos[1], pos[2], pos[3]) or V(), rot = rot and Q(rot[1], rot[2], rot[3], rot[4]) or Q() } end
A.TransformCopy = function(t) return A.Transform(t.pos, t.rot) end
A.TransformStr = function(t) return A.VecStr(t.pos) .. " " .. A.QuatStr(t.rot) end
A.TransformToParentTransform = function(p, c) return { pos = A.VecAdd(p.pos, qrot(p.rot, c.pos)), rot = qmul(p.rot, c.rot) } end
A.TransformToLocalTransform = function(p, c)
	local inv = qconj(p.rot)
	return { pos = qrot(inv, A.VecSub(c.pos, p.pos)), rot = qmul(inv, c.rot) }
end
A.TransformToParentVec = function(t, v) return qrot(t.rot, v) end
A.TransformToLocalVec = function(t, v) return qrot(qconj(t.rot), v) end
A.TransformToParentPoint = function(t, p) return A.VecAdd(t.pos, qrot(t.rot, p)) end
A.TransformToLocalPoint = function(t, p) return qrot(qconj(t.rot), A.VecSub(p, t.pos)) end

A.SetRandomSeed = function(s) math.randomseed(s) end
A.GetRandomBool = function() return math.random() < 0.5 end
A.GetRandomInt = function(a, b) return math.random(a, b) end
A.GetRandomFloat = function(a, b) return a + (b - a) * math.random() end
A.GetRandomDirection = function(len)
	local v
	repeat v = V(math.random()*2-1, math.random()*2-1, math.random()*2-1) until A.VecLength(v) > 0.01 and A.VecLength(v) <= 1
	return A.VecScale(A.VecNormalize(v), len or 1)
end

---------------------------------------------------------------------------
-- registry
---------------------------------------------------------------------------
H.reg = {}
A.SetInt = function(k, v) H.reg[k] = math.floor(v) end
A.GetInt = function(k) local v = H.reg[k]; if type(v) == "number" then return math.floor(v) elseif v == true then return 1 elseif type(v) == "string" then return math.floor(tonumber(v) or 0) end return 0 end
A.SetFloat = function(k, v) H.reg[k] = v end
A.GetFloat = function(k) local v = H.reg[k]; if type(v) == "number" then return v elseif v == true then return 1 elseif type(v) == "string" then return tonumber(v) or 0 end return 0 end
A.SetBool = function(k, v) H.reg[k] = v and true or false end
A.GetBool = function(k) local v = H.reg[k]; if type(v) == "boolean" then return v elseif type(v) == "number" then return v ~= 0 elseif type(v) == "string" then return v ~= "" and v ~= "0" and v ~= "false" end return false end
A.SetString = function(k, v) H.reg[k] = tostring(v) end
A.GetString = function(k) local v = H.reg[k]; if v == nil then return "" elseif type(v) == "boolean" then return v and "1" or "0" end return tostring(v) end
A.SetColor = function(k, r, g, b, a) H.reg[k] = { r, g, b, a or 1 } end
A.GetColor = function(k) local v = H.reg[k]; if type(v) == "table" then return v[1], v[2], v[3], v[4] end return 0, 0, 0, 0 end
A.HasKey = function(k)
	if H.reg[k] ~= nil then return true end
	local pre = k .. "."
	for kk in pairs(H.reg) do if kk:sub(1, #pre) == pre then return true end end
	return false
end
A.ClearKey = function(k)
	local pre = k .. "."
	for kk in pairs(H.reg) do if kk == k or kk:sub(1, #pre) == pre then H.reg[kk] = nil end end
end
A.ListKeys = function(parent)
	local pre = parent .. "."
	local seen, out = {}, {}
	for kk in pairs(H.reg) do
		if kk:sub(1, #pre) == pre then
			local rest = kk:sub(#pre + 1)
			local child = rest:match("^([^.]+)")
			if child and not seen[child] then seen[child] = true; out[#out+1] = child end
		end
	end
	table.sort(out)
	return out
end
A.GetTranslatedStringByKey = function(key, default) return default or key end
A.HasTranslationByKey = function() return false end

---------------------------------------------------------------------------
-- world: bodies, shapes, static boxes, players
---------------------------------------------------------------------------
H.nextHandle = 100
H.bodies = {}   -- handle -> body
H.shapes = {}   -- handle -> shape
H.boxes = {}    -- static world boxes {min,max,shape}
H.lights = {}
H.holes = {}    -- list of {pos,r0,r1,r2,frame}
H.spawned = {}
H.sounds = {}   -- handle -> path
H.loops = {}
H.playedSounds = {} -- list {path, pos, frame}
H.playedLoops = {}  -- path -> frames played count
H.particles = 0
H.frameParticles = 0
H.maxFrameParticles = 0
H.gravity = V(0, -10, 0)
H.timeScale = 1
H.camera = nil  -- override set by SetCameraTransform for this frame
H.cameraShake = 0
H.explosions = {}
H.fires = 0
H.paints = 0
H.toolsRegistered = {}

-- Authority model (Teardown #version 2): every entity is authored by the side that
-- created it. Level entities and everything spawned from server code are
-- server-authored; client scripts may read them but any mutating call raises
-- "invalid attempt to access server authored entity from client script".
-- Tool bodies are local to the client that renders them.
H.owner = {}
local function newHandle()
	H.nextHandle = H.nextHandle + 1
	H.owner[H.nextHandle] = (H.ctx == "client") and "client" or "server"
	return H.nextHandle
end

function H.addBody(o)
	local h = newHandle()
	local b = {
		handle = h, pos = V(o.pos[1], o.pos[2], o.pos[3]), rot = o.rot or Q(),
		vel = o.vel or V(), angvel = V(), mass = o.mass or 10, dynamic = (o.dynamic ~= false),
		half = o.half or V(0.25, 0.25, 0.25), shapes = {}, tags = {}, valid = true, gravityScale = 1,
		active = true, player = o.player or 0, material = o.material or "wood", isTool = o.isTool,
		desc = "", restitution = o.restitution or 0.35,
	}
	H.bodies[h] = b
	local nshapes = o.shapes or 1
	for i = 1, nshapes do
		local sh = newHandle()
		H.shapes[sh] = { handle = sh, body = h, local_ = A.Transform(), material = b.material, tags = {}, emissive = 1, valid = true, layer = 1, mask = 255 }
		b.shapes[#b.shapes + 1] = sh
	end
	return h
end

function H.addStaticBox(min, max, material)
	local bh = H.worldBody
	local sh = newHandle()
	H.shapes[sh] = { handle = sh, body = bh, local_ = A.Transform(), material = material or "masonry", tags = {}, emissive = 1, valid = true, layer = 1, mask = 255, box = true }
	H.boxes[#H.boxes + 1] = { min = min, max = max, shape = sh, material = material or "masonry" }
	return sh
end

-- Destructible blocks: a grid of small static cubes (buildings) kept apart from H.boxes so
-- physics and raycasts stay fast. MakeHole removes a cube when its centre lies within the
-- radius for its material class, exactly as the game's three MakeHole radii work:
-- r0 soft (glass, foliage, dirt, wood, plaster, plastic), r1 medium (masonry/concrete/brick,
-- weak metal), r2 hard (hard metal, hard masonry, heavy metal, rock).
-- Explosions do not remove cubes here (unknown radius in the game), so laws only count holes.
H.cubes = {}
H.cubeGrid = {}
H.CUBE_BUCKET = 4
local CUBE_CLASS = { glass = 0, foliage = 0, dirt = 0, wood = 0, plaster = 0, plastic = 0,
	masonry = 1, concrete = 1, brick = 1, metal = 1,
	hardmetal = 2, hardmasonry = 2, heavymetal = 2, rock = 2 }
local function cubeKey(ix, iy, iz) return ix .. ":" .. iy .. ":" .. iz end
local function cubeBucket(p) local b = H.CUBE_BUCKET return math.floor(p[1] / b), math.floor(p[2] / b), math.floor(p[3] / b) end
function H.addCubes(min, max, cell, material)
	local n = 0
	local x = min[1]
	while x < max[1] - 1e-6 do
		local y = min[2]
		while y < max[2] - 1e-6 do
			local z = min[3]
			while z < max[3] - 1e-6 do
				local c = { x + cell * 0.5, y + cell * 0.5, z + cell * 0.5 }
				local sh = newHandle()
				H.shapes[sh] = { handle = sh, body = H.worldBody, local_ = A.Transform(), material = material, tags = {}, emissive = 1, valid = true, layer = 1, mask = 255, cube = true }
				local cube = { c = c, half = cell * 0.5, material = material, class = CUBE_CLASS[material] or 1, alive = true, shape = sh }
				H.cubes[#H.cubes + 1] = cube
				local k = cubeKey(cubeBucket(c))
				local list = H.cubeGrid[k]
				if not list then list = {} H.cubeGrid[k] = list end
				list[#list + 1] = cube
				n = n + 1
				z = z + cell
			end
			y = y + cell
		end
		x = x + cell
	end
	return n
end
-- calls fn(cube) for alive cubes whose bucket overlaps the sphere
local function eachCubeNear(p, r, fn)
	local b = H.CUBE_BUCKET
	local x0, y0, z0 = math.floor((p[1] - r) / b), math.floor((p[2] - r) / b), math.floor((p[3] - r) / b)
	local x1, y1, z1 = math.floor((p[1] + r) / b), math.floor((p[2] + r) / b), math.floor((p[3] + r) / b)
	for ix = x0, x1 do for iy = y0, y1 do for iz = z0, z1 do
		local list = H.cubeGrid[cubeKey(ix, iy, iz)]
		if list then for i = 1, #list do if list[i].alive then fn(list[i]) end end end
	end end end
end
H.eachCubeNear = eachCubeNear
-- statistics: cubes whose horizontal distance from c is within [r0, r1); optional class filter
function H.cubeStats(c, r0, r1, class)
	local total, removed = 0, 0
	for _, cube in ipairs(H.cubes) do
		local dx, dz = cube.c[1] - c[1], cube.c[3] - c[3]
		local d = math.sqrt(dx * dx + dz * dz)
		if d >= r0 and d < r1 and (class == nil or cube.class == class) then
			total = total + 1
			if not cube.alive then removed = removed + 1 end
		end
	end
	return total, removed
end

H.worldBody = newHandle()
H.bodies[H.worldBody] = { handle = H.worldBody, pos = V(), rot = Q(), vel = V(), angvel = V(), mass = 0, dynamic = false, half = V(1000, 0.01, 1000), shapes = {}, tags = {}, valid = true, gravityScale = 0, active = false, player = 0, material = "dirt", desc = "" }
H.groundShape = newHandle()
H.shapes[H.groundShape] = { handle = H.groundShape, body = H.worldBody, local_ = A.Transform(), material = "dirt", tags = {}, emissive = 1, valid = true, layer = 1, mask = 255 }

-- players
H.players = {}
H.playerOrder = {}
H.addedPlayers = {}
H.removedPlayers = {}
function H.addPlayer(id, pos)
	local p = {
		id = id, pos = pos or V(0, 0, 0), vel = V(), yaw = 0, pitch = 0, health = 1, tool = "sledge",
		ammo = {}, enabled = {}, input = {}, pressed = {}, released = {}, vehicle = 0, canUseTool = true,
		grabBody = 0, pickBody = 0, toolBody = 0, damage = 0, toolTransform = nil, local_ = (id == 1),
	}
	H.players[id] = p
	H.playerOrder[#H.playerOrder + 1] = id
	H.addedPlayers[#H.addedPlayers + 1] = id
	return p
end
local function P(id)
	if id == nil or id == 0 then id = H.playerOrder[1] end
	local p = H.players[id]
	if not p then err("invalid player id " .. tostring(id)) end
	return p
end
H.P = P

---------------------------------------------------------------------------
-- query state
---------------------------------------------------------------------------
local q = {}
local function qreset() q = { require = {}, rejectBodies = {}, rejectShapes = {}, rejectPlayers = {}, include = {} } end
qreset()
A.QueryRequire = function(layers) for w in layers:gmatch("%S+") do q.require[w] = true end end
A.QueryInclude = function(layers) for w in layers:gmatch("%S+") do q.include[w] = true end end
A.QueryCollisionMask = function(mask) q.mask = mask end
A.QueryRejectAnimator = function(h) end
A.QueryRejectVehicle = function(h) end
A.QueryRejectBody = function(h) q.rejectBodies[h] = true end
A.QueryRejectBodies = function(list) for _, h in ipairs(list) do q.rejectBodies[h] = true end end
A.QueryRejectShape = function(h) q.rejectShapes[h] = true end
A.QueryRejectShapes = function(list) for _, h in ipairs(list) do q.rejectShapes[h] = true end end
A.QueryRejectPlayer = function(id) q.rejectPlayers[id] = true end

local function bodyPasses(b)
	if not b.valid then return false end
	if q.rejectBodies[b.handle] then return false end
	if q.require.dynamic and not b.dynamic then return false end
	if q.require.static and b.dynamic then return false end
	if b.isTool and not q.require.tool then return false end
	if b.player ~= 0 and q.rejectPlayers[b.player] then return false end
	if q.require.small and b.mass > 50 then return false end
	if q.require.large and b.mass <= 50 then return false end
	return true
end

local function aabbOverlap(amin, amax, bmin, bmax)
	return amin[1] <= bmax[1] and amax[1] >= bmin[1] and amin[2] <= bmax[2] and amax[2] >= bmin[2] and amin[3] <= bmax[3] and amax[3] >= bmin[3]
end
local function bodyAabb(b)
	return A.VecSub(b.pos, b.half), A.VecAdd(b.pos, b.half)
end

A.QueryAabbBodies = function(min, max)
	local out = {}
	for h, b in pairs(H.bodies) do
		if h ~= H.worldBody and bodyPasses(b) then
			local bmin, bmax = bodyAabb(b)
			if aabbOverlap(min, max, bmin, bmax) then out[#out + 1] = h end
		end
	end
	table.sort(out)
	qreset()
	return out
end
A.QueryAabbShapes = function(min, max)
	local out = {}
	for h, b in pairs(H.bodies) do
		if h ~= H.worldBody and bodyPasses(b) then
			local bmin, bmax = bodyAabb(b)
			if aabbOverlap(min, max, bmin, bmax) then for _, s in ipairs(b.shapes) do if not q.rejectShapes[s] then out[#out + 1] = s end end end
		end
	end
	if not q.require.dynamic then
		for _, bx in ipairs(H.boxes) do
			if H.shapes[bx.shape].valid and aabbOverlap(min, max, bx.min, bx.max) and not q.rejectShapes[bx.shape] then out[#out + 1] = bx.shape end
		end
	end
	table.sort(out)
	qreset()
	return out
end

-- ray vs aabb
local function rayBox(o, d, bmin, bmax)
	local tmin, tmax = -1e30, 1e30
	local nrm = V()
	for i = 1, 3 do
		if math.abs(d[i]) < 1e-9 then
			if o[i] < bmin[i] or o[i] > bmax[i] then return nil end
		else
			local t1 = (bmin[i] - o[i]) / d[i]
			local t2 = (bmax[i] - o[i]) / d[i]
			local n = V(); n[i] = -1
			if t1 > t2 then t1, t2 = t2, t1; n[i] = 1 end
			if t1 > tmin then tmin = t1; nrm = n end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return nil end
		end
	end
	if tmax < 0 then return nil end
	if tmin < 0 then return 0, V(-d[1], -d[2], -d[3]) end
	return tmin, nrm
end

local function raycast(origin, dir, maxDist)
	local bestT, bestN, bestS = nil, nil, 0
	-- ground plane y=0
	if dir[2] < -1e-6 and origin[2] >= 0 then
		local t = -origin[2] / dir[2]
		if t <= maxDist then bestT, bestN, bestS = t, V(0, 1, 0), H.groundShape end
	end
	for _, bx in ipairs(H.boxes) do
		if H.shapes[bx.shape].valid and not q.rejectShapes[bx.shape] and not q.require.dynamic then
			local t, n = rayBox(origin, dir, bx.min, bx.max)
			if t and t <= maxDist and (not bestT or t < bestT) then bestT, bestN, bestS = t, n, bx.shape end
		end
	end
	for h, b in pairs(H.bodies) do
		if h ~= H.worldBody and bodyPasses(b) and b.player == 0 then
			local bmin, bmax = bodyAabb(b)
			local t, n = rayBox(origin, dir, bmin, bmax)
			if t and t <= maxDist and (not bestT or t < bestT) then bestT, bestN, bestS = t, n, b.shapes[1] or 0 end
		end
	end
	return bestT, bestN, bestS
end
H.raycast = raycast

A.QueryRaycast = function(origin, dir, maxDist, radius, rejectTransparent)
	local t, n, s = raycast(origin, dir, maxDist)
	qreset()
	if t then return true, t, n, s end
	return false, maxDist, V(), 0
end
A.QueryRaycastRope = function(origin, dir, maxDist) qreset(); return false, maxDist, 0, 0 end
A.QueryRaycastWater = function(origin, dir, maxDist) qreset(); return false, maxDist, V() end
A.QueryShot = function(origin, dir, maxDist, radius, playerId)
	local t, n, s = raycast(origin, dir, maxDist)
	qreset()
	if t then return true, t, s, 0, 1, n end
	return false, maxDist, 0, 0, 0, V()
end
A.QueryClosestPoint = function(origin, maxDist)
	local best, bp, bn, bs = maxDist, nil, nil, 0
	if origin[2] >= 0 and origin[2] <= best then best, bp, bn, bs = origin[2], V(origin[1], 0, origin[3]), V(0, 1, 0), H.groundShape end
	for _, bx in ipairs(H.boxes) do
		if H.shapes[bx.shape].valid and not q.rejectShapes[bx.shape] and not q.require.dynamic then
			local cp = V(math.max(bx.min[1], math.min(origin[1], bx.max[1])), math.max(bx.min[2], math.min(origin[2], bx.max[2])), math.max(bx.min[3], math.min(origin[3], bx.max[3])))
			local d = A.VecLength(A.VecSub(origin, cp))
			if d <= best then best, bp, bs = d, cp, bx.shape; bn = d > 1e-6 and A.VecNormalize(A.VecSub(origin, cp)) or V(0, 1, 0) end
		end
	end
	for h, b in pairs(H.bodies) do
		if h ~= H.worldBody and bodyPasses(b) and b.player == 0 then
			local bmin, bmax = bodyAabb(b)
			local cp = V(math.max(bmin[1], math.min(origin[1], bmax[1])), math.max(bmin[2], math.min(origin[2], bmax[2])), math.max(bmin[3], math.min(origin[3], bmax[3])))
			local d = A.VecLength(A.VecSub(origin, cp))
			if d <= best then best, bp, bs = d, cp, b.shapes[1] or 0; bn = d > 1e-6 and A.VecNormalize(A.VecSub(origin, cp)) or V(0, 1, 0) end
		end
	end
	if #H.cubes > 0 and not q.require.dynamic then
		eachCubeNear(origin, best, function(cube)
			local h = cube.half
			local c = cube.c
			local cp = V(math.max(c[1] - h, math.min(origin[1], c[1] + h)), math.max(c[2] - h, math.min(origin[2], c[2] + h)), math.max(c[3] - h, math.min(origin[3], c[3] + h)))
			local d = A.VecLength(A.VecSub(origin, cp))
			if d <= best then
				best, bp, bs = d, cp, cube.shape
				if d > 1e-6 then
					-- face normal of the nearest face (cubes are axis aligned)
					local o = A.VecSub(origin, c)
					local ax = { math.abs(o[1]), math.abs(o[2]), math.abs(o[3]) }
					if ax[1] >= ax[2] and ax[1] >= ax[3] then bn = V(o[1] > 0 and 1 or -1, 0, 0)
					elseif ax[2] >= ax[3] then bn = V(0, o[2] > 0 and 1 or -1, 0)
					else bn = V(0, 0, o[3] > 0 and 1 or -1) end
				else
					bn = V(0, 1, 0)
				end
			end
		end)
	end
	qreset()
	if bp then return true, bp, bn, bs end
	return false, V(), V(), 0
end
A.QueryPath = function() qreset() end
A.GetLastSound = function() return V(), 0 end
A.IsPointInWater = function(p) if H.waterLevel and p[2] < H.waterLevel then return true, H.waterLevel - p[2] end return false, 0 end
A.GetWindVelocity = function() return V() end

---------------------------------------------------------------------------
-- body / shape API
---------------------------------------------------------------------------
local function B(h, fname)
	local b = H.bodies[h]
	if not b then
		if h ~= 0 then H.warn((fname or "?") .. ": unknown body handle " .. tostring(h)) end
		return nil
	end
	if not b.valid then H.warn((fname or "?") .. ": deleted body " .. tostring(h)); return nil end
	return b
end
local function S(h, fname)
	local s = H.shapes[h]
	if not s then if h ~= 0 then H.warn((fname or "?") .. ": unknown shape handle " .. tostring(h)) end return nil end
	if not s.valid then H.warn((fname or "?") .. ": deleted shape " .. tostring(h)); return nil end
	return s
end
H.B = B

A.GetBodyTransform = function(h) local b = B(h, "GetBodyTransform"); if not b then return A.Transform() end return A.Transform(b.pos, b.rot) end
A.SetBodyTransform = function(h, t)
	local b = B(h, "SetBodyTransform")
	if not b then return end
	-- optional failure model: static bodies cannot be moved after they are spawned
	if H.spawnModel and H.spawnModel.staticFixed and not b.dynamic then return end
	b.pos = A.VecCopy(t.pos); b.rot = A.QuatCopy(t.rot)
end
A.GetBodyMass = function(h) local b = B(h, "GetBodyMass"); if not b or not b.dynamic then return 0 end return b.mass end
A.IsBodyDynamic = function(h) local b = B(h, "IsBodyDynamic"); return b ~= nil and b.dynamic end
A.SetBodyDynamic = function(h, d) local b = B(h, "SetBodyDynamic"); if b then b.dynamic = d end end
A.SetBodyVelocity = function(h, v)
	local b = B(h, "SetBodyVelocity")
	if b and not H.ignoreBodyVelocity then b.vel = A.VecCopy(v); b.active = true end
end
A.GetBodyVelocity = function(h) local b = B(h, "GetBodyVelocity"); if not b then return V() end return A.VecCopy(b.vel) end
A.GetBodyVelocityAtPos = function(h, p) local b = B(h, "GetBodyVelocityAtPos"); if not b then return V() end return A.VecAdd(b.vel, A.VecCross(b.angvel, A.VecSub(p, b.pos))) end
A.SetBodyAngularVelocity = function(h, v) local b = B(h, "SetBodyAngularVelocity"); if b then b.angvel = A.VecCopy(v) end end
A.GetBodyAngularVelocity = function(h) local b = B(h, "GetBodyAngularVelocity"); if not b then return V() end return A.VecCopy(b.angvel) end
A.SetBodyGravityScale = function(h, s) local b = B(h); if b then b.gravityScale = s end end
A.IsBodyActive = function(h) local b = B(h, "IsBodyActive"); return b ~= nil and b.active end
A.SetBodyActive = function(h, a) local b = B(h, "SetBodyActive"); if b then b.active = a end end
A.ApplyBodyImpulse = function(h, pos, imp)
	local b = B(h, "ApplyBodyImpulse")
	if not b then return end
	if not b.dynamic then H.warn("ApplyBodyImpulse on static body " .. h) return end
	b.vel = A.VecAdd(b.vel, A.VecScale(imp, 1 / math.max(b.mass, 0.001)))
	b.active = true
	local s = A.VecLength(b.vel)
	if s > 500 then err("body speed exploded: " .. s) end
end
A.GetBodyShapes = function(h) local b = B(h, "GetBodyShapes"); if not b then return {} end local o = {} for i, s in ipairs(b.shapes) do if H.shapes[s].valid then o[#o + 1] = s end end return o end
H.vehicleOf = {}     -- body -> vehicle handle (scenario sets it)
H.vehicles = {}      -- vehicle handle -> {body=main body, bodies={...}}
A.GetBodyVehicle = function(h) return H.vehicleOf[h] or 0 end
A.GetBodyAnimator = function(h) return 0 end
A.GetBodyPlayer = function(h) local b = B(h); return b and b.player or 0 end
A.GetBodyBounds = function(h) local b = B(h, "GetBodyBounds"); if not b then return V(), V() end return bodyAabb(b) end
A.GetBodyCenterOfMass = function(h) return V() end
A.IsBodyVisible = function() return true end
A.IsBodyBroken = function() return false end
A.IsBodyJointedToStatic = function(h) local b = B(h); return b ~= nil and b.jointedToStatic == true end
A.DrawBodyOutline = function() end
A.DrawBodyHighlight = function() end
A.GetBodyClosestPoint = function(h, o) local b = B(h); if not b then return false, V(), V(), 0 end local bmin, bmax = bodyAabb(b); local cp = V(math.max(bmin[1], math.min(o[1], bmax[1])), math.max(bmin[2], math.min(o[2], bmax[2])), math.max(bmin[3], math.min(o[3], bmax[3]))); return true, cp, V(0, 1, 0), b.shapes[1] or 0 end
A.GetWorldBody = function() return H.worldBody end
A.FindBodies = function(tag, global)
	local out = {}
	for h, b in pairs(H.bodies) do
		if b.valid ~= false and h ~= H.worldBody and (tag == nil or tag == "" or b.tags[tag] ~= nil) then out[#out + 1] = h end
	end
	table.sort(out)
	return out
end
A.FindBody = function(tag, global) return A.FindBodies(tag, global)[1] or 0 end
A.FindShapes = function(tag, global)
	local out = {}
	for h, sh in pairs(H.shapes) do
		if sh.valid and (tag == nil or tag == "" or sh.tags[tag] ~= nil) then out[#out + 1] = h end
	end
	table.sort(out)
	return out
end
A.FindShape = function(tag, global) return A.FindShapes(tag, global)[1] or 0 end
A.GetShapeLocalTransform = function(h) local s = S(h, "GetShapeLocalTransform"); if not s then return A.Transform() end return A.TransformCopy(s.local_) end
A.SetShapeLocalTransform = function(h, t) local s = S(h, "SetShapeLocalTransform"); if s then s.local_ = A.TransformCopy(t) end end
A.GetShapeWorldTransform = function(h) local s = S(h, "GetShapeWorldTransform"); if not s then return A.Transform() end local b = H.bodies[s.body]; return A.TransformToParentTransform(A.Transform(b.pos, b.rot), s.local_) end
A.GetShapeBody = function(h) local s = S(h, "GetShapeBody"); return s and s.body or 0 end
function H.shapeWorldAabb(s)
	local b = H.bodies[s.body]
	local vs = s.voxelSize or 0.1
	local sz = s.size
	local wt = A.TransformToParentTransform(A.Transform(b.pos, b.rot), s.local_)
	local mn, mx = V(1e9, 1e9, 1e9), V(-1e9, -1e9, -1e9)
	for i = 0, 7 do
		local c = V((i % 2) * sz[1] * vs, (math.floor(i / 2) % 2) * sz[2] * vs, math.floor(i / 4) * sz[3] * vs)
		local w = A.TransformToParentPoint(wt, c)
		for k = 1, 3 do mn[k] = math.min(mn[k], w[k]) mx[k] = math.max(mx[k], w[k]) end
	end
	return mn, mx
end
A.GetShapeBounds = function(h)
	local s = S(h, "GetShapeBounds"); if not s then return V(), V() end
	for _, bx in ipairs(H.boxes) do if bx.shape == h then return A.VecCopy(bx.min), A.VecCopy(bx.max) end end
	if s.size and H.bodies[s.body] then return H.shapeWorldAabb(s) end
	return bodyAabb(H.bodies[s.body])
end
A.SetShapeEmissiveScale = function(h, sc) local s = S(h, "SetShapeEmissiveScale"); if s then s.emissive = sc end end
A.GetShapeMaterialAtPosition = function(h, pos)
	local s = S(h, "GetShapeMaterialAtPosition"); if not s then return "", 0, 0, 0, 0, 0 end
	return s.material, 0.5, 0.5, 0.5, 1, 1
end
A.GetShapeMaterialAtIndex = function(h) local s = S(h); if not s then return "", 0, 0, 0, 0, 0 end return s.material, 0.5, 0.5, 0.5, 1, 1 end
A.GetShapeSize = function(h) return 10, 10, 10, 0.1 end
A.GetShapeVoxelCount = function(h) return 100 end
A.IsShapeVisible = function() return true end
A.IsShapeBroken = function(h) local s = H.shapes[h]; return s == nil or not s.valid or s.broken == true end
A.DrawShapeOutline = function() end
A.DrawShapeHighlight = function() end
A.SetShapeCollisionFilter = function(h, layer, mask) local s = S(h, "SetShapeCollisionFilter"); if s then s.layer = layer; s.mask = mask end end
A.GetShapeCollisionFilter = function(h) local s = S(h); if not s then return 1, 255 end return s.layer, s.mask end
A.GetShapeClosestPoint = function(h, o)
	local s = S(h, "GetShapeClosestPoint"); if not s then return false, V(), V() end
	local bmin, bmax = A.GetShapeBounds(h)
	local cp = V(math.max(bmin[1], math.min(o[1], bmax[1])), math.max(bmin[2], math.min(o[2], bmax[2])), math.max(bmin[3], math.min(o[3], bmax[3])))
	return true, cp, V(0, 1, 0)
end
A.IsShapeTouching = function() return false end
A.GetShapeJoints = function(h) local s = H.shapes[h]; return (s and s.joints) or {} end
A.GetShapeLights = function() return {} end
A.IsShapeDisconnected = function() return false end
A.IsStaticShapeDetached = function() return false end

-- tags / entities
local function ent(h) return H.bodies[h] or H.shapes[h] or (H.entities and H.entities[h]) end
A.SetTag = function(h, tag, val) local e = ent(h); if e then e.tags[tag] = val or "" end end
A.RemoveTag = function(h, tag) local e = ent(h); if e then e.tags[tag] = nil end end
A.HasTag = function(h, tag) local e = ent(h); return e ~= nil and e.tags[tag] ~= nil end
A.GetTagValue = function(h, tag) local e = ent(h); return (e and e.tags[tag]) or "" end
A.ListTags = function(h) local e = ent(h); local o = {}; if e then for k in pairs(e.tags) do o[#o + 1] = k end end return o end
A.GetDescription = function(h) local e = ent(h); return (e and e.desc) or "" end
A.SetDescription = function(h, d) local e = ent(h); if e then e.desc = d end end
A.Delete = function(h)
	local b = H.bodies[h]
	if b then
		if h == H.worldBody then err("attempt to delete world body") return end
		b.valid = false
		for _, s in ipairs(b.shapes) do H.shapes[s].valid = false end
		return
	end
	local s = H.shapes[h]
	if s then s.valid = false return end
end
A.IsHandleValid = function(h) local e = ent(h); return e ~= nil and e.valid ~= false end
A.GetEntityType = function(h) if H.bodies[h] then return "body" elseif H.shapes[h] then return "shape" elseif H.joints[h] then return "joint" elseif H.entities[h] then return H.entities[h].type end return "" end
-- generic level entities (water so far): H.addEntity("water", {wave = 0.5, ...}, tags)
H.entities = {}
function H.addEntity(etype, props, tags)
	local h = newHandle()
	H.entities[h] = { type = etype, props = props or {}, tags = tags or {} }
	return h
end
A.FindEntity = function(tag, global, etype)
	local l = A.FindEntities(tag, global, etype)
	return l[1] or 0
end
A.FindEntities = function(tag, global, etype)
	local out = {}
	for h, e in pairs(H.entities) do
		if (etype == nil or etype == "" or e.type == etype) and (tag == nil or tag == "" or e.tags[tag] ~= nil) then out[#out + 1] = h end
	end
	table.sort(out)
	return out
end
A.GetEntityChildren = function() return {} end
A.GetEntityParent = function() return 0 end
A.GetProperty = function(h, name)
	local e = H.entities[h]
	if e then return e.props[name] end
	return nil
end
A.SetProperty = function(h, name, value)
	local e = H.entities[h]
	if e then
		if e.type == "water" and name == "transform" then H.err("SetProperty: water transform is not settable") return end
		e.props[name] = value
	end
end
A.FindLocation = function() return 0 end
A.FindLocations = function() return {} end
A.FindJoint = function() return 0 end
A.FindJoints = function() return {} end
A.FindLight = function() return 0 end
A.FindLights = function() return {} end
A.FindTrigger = function() return 0 end
A.FindTriggers = function() return {} end
A.FindVehicle = function() return 0 end
A.FindVehicles = function() return {} end
A.FindScreen = function() return 0 end
A.FindScreens = function() return {} end
A.FindAnimator = function() return 0 end
A.FindAnimators = function() return {} end
A.IsPointInBoundaries = function() return true end
A.GetBoundaryBounds = function() return V(-200, -50, -200), V(200, 200, 200) end
A.GetGravity = function() return A.VecCopy(H.gravity) end
A.SetGravity = function(v) H.gravity = A.VecCopy(v) end

-- joints (simple model: joints attached to shapes)
H.joints = {}
function H.addJoint(shapeA, shapeB, jtype)
	local j = newHandle()
	H.joints[j] = { handle = j, shapes = { shapeA, shapeB }, type = jtype or "ball", broken = false, tags = {} }
	for _, s in ipairs({ shapeA, shapeB }) do
		if s ~= 0 and H.shapes[s] then H.shapes[s].joints = H.shapes[s].joints or {}; table.insert(H.shapes[s].joints, j) end
	end
	return j
end
A.IsJointBroken = function(j) local jj = H.joints[j]; return jj == nil or jj.broken end
A.GetJointType = function(j) local jj = H.joints[j]; return jj and jj.type or "" end
A.GetJointShapes = function(j) local jj = H.joints[j]; return jj and { jj.shapes[1], jj.shapes[2] } or {} end
A.GetJointOtherShape = function(j, s) local jj = H.joints[j]; if not jj then return 0 end if jj.shapes[1] == s then return jj.shapes[2] end return jj.shapes[1] end
A.DetachJointFromShape = function(j, s) local jj = H.joints[j]; if jj then jj.broken = true; H.note("joint detached " .. j) end end
A.GetJointedBodies = function(b) return {} end
A.SetJointMotor = function(j, vel, strength) local jj = H.joints[j]; if jj then jj.motorVel = vel; jj.target = nil end end
A.SetJointMotorTarget = function(j, target, maxVel, strength) local jj = H.joints[j]; if jj then jj.target = target; jj.maxVel = maxVel or 3; jj.motorVel = nil end end
A.GetJointLimits = function() return 0, 0 end
A.GetJointMovement = function(j) local jj = H.joints[j]; return jj and jj.angle or 0 end

---------------------------------------------------------------------------
-- spawning, holes, fx
---------------------------------------------------------------------------
local function resolvePath(path)
	if path:sub(1, 4) == "MOD/" then return H.modDir .. "/" .. path:sub(5), true end
	return H.dataDir .. "/" .. path, false
end
H.resolvePath = resolvePath

local function checkFile(path, what, alsoTde, searchDirs)
	local full, isMod = resolvePath(path)
	if H.fileExists(full) then return true end
	if alsoTde and H.fileExists(full .. ".tde") then return true end
	if searchDirs then
		for _, d in ipairs(searchDirs) do
			local f = H.dataDir .. "/" .. d .. "/" .. path
			if H.fileExists(f) or (alsoTde and H.fileExists(f .. ".tde")) then return true end
		end
	end
	err(what .. ": file not found: " .. path)
	return false
end
H.checkFile = checkFile

local function parseAttr(s, name)
	return s:match(name .. "%s*=%s*'([^']*)'") or s:match(name .. '%s*=%s*"([^"]*)"')
end

H.pendingShapes = {}
function H.revealShapes()
	local keep = {}
	for _, sh in ipairs(H.pendingShapes) do
		local s = H.shapes[sh]
		if s and s.revealFrame and H.frame >= s.revealFrame then
			s.local_ = s.realLocal
			s.realLocal, s.revealFrame = nil, nil
		elseif s then
			keep[#keep + 1] = sh
		end
	end
	H.pendingShapes = keep
end
function H.attrTransform(attrs)
	local pos, rot = A.Vec(0, 0, 0), A.Quat()
	local ps = parseAttr(attrs, "pos")
	if ps then local a, b, c = ps:match("(%S+)%s+(%S+)%s+(%S+)") if a then pos = A.Vec(tonumber(a), tonumber(b), tonumber(c)) end end
	local rs = parseAttr(attrs, "rot")
	if rs then local a, b, c = rs:match("(%S+)%s+(%S+)%s+(%S+)") if a then rot = A.QuatEuler(tonumber(a), tonumber(b), tonumber(c)) end end
	return A.Transform(pos, rot)
end
A.Spawn = function(xml, transform, allowStatic, jointExisting)
	local content = xml
	if not xml:find("<") then
		if not checkFile(xml, "Spawn") then return {} end
		content = H.readFile((resolvePath(xml)))
	end
	local out = {}
	local cur = nil
	local lastVox = nil
	-- every <body> creates a body; every <vox>/<voxbox> a shape
	for tag, attrs in content:gmatch("<(%w+)([^>]*)>") do
		if tag == "body" then
			local dyn = parseAttr(attrs, "dynamic")
			local bt = A.TransformToParentTransform(transform, H.attrTransform(attrs))
			cur = H.addBody { pos = bt.pos, rot = bt.rot, dynamic = (dyn == "true"), shapes = 0, mass = 2, half = V(0.1, 0.1, 0.1) }
			out[#out + 1] = cur
			local btags = parseAttr(attrs, "tags")
			if btags and not (H.spawnModel and H.spawnModel.noBodyTags) then
				for t in btags:gmatch("%S+") do
					local k, v = t:match("([^=]+)=?(.*)")
					H.bodies[cur].tags[k] = v
				end
			end
			H.bodies[cur].spawnedXml = content
		elseif tag == "vox" or tag == "voxbox" then
			local sizes = nil
			local scale = tonumber(parseAttr(attrs, "scale") or "1") or 1
			if tag == "vox" then
				local f = parseAttr(attrs, "file")
				if f and checkFile(f, "Spawn vox") and H.voxSizes then sizes = H.voxSizes(resolvePath(f)) end
			else
				local sz = parseAttr(attrs, "size")
				if sz then
					local a, b, c = sz:match("(%S+)%s+(%S+)%s+(%S+)")
					sizes = { { tonumber(a), tonumber(b), tonumber(c) } }
				end
			end
			if not cur then
				cur = H.addBody { pos = transform.pos, rot = transform.rot, dynamic = false, shapes = 0 }
				if not allowStatic then H.warn("Spawn: shape without dynamic body and allowStatic=false is dropped by the game") end
				out[#out + 1] = cur
			end
			-- one shape per model in the vox file, with its real size
			local n = sizes and #sizes or 1
			local made = {}
			for k = 1, math.max(1, n) do
				local sh = newHandle()
				local size = sizes and sizes[k] and { sizes[k][1], sizes[k][2], sizes[k][3] } or nil
				local vs = 0.1 * scale
				local attrT = H.attrTransform(attrs)
				local local_ = attrT
				local model = H.spawnModel
				if model and model.axes == "mv" and size then
					-- the shape keeps the model's own axes (height along its local z) and is stood up by
					-- its transform; GetShapeSize then reports the model's x, y, z
					size = { size[1], size[3], size[2] }
					local half = model.pivot == "center" and V(-size[1] * vs * 0.5, -size[2] * vs * 0.5, -size[3] * vs * 0.5)
						or (model.pivot == "bottomcenter" and V(-size[1] * vs * 0.5, -size[2] * vs * 0.5, 0) or V(0, 0, 0))
					local_ = A.TransformToParentTransform(attrT, A.TransformToParentTransform(A.Transform(V(0, 0, 0), A.QuatEuler(-90, 0, 0)), A.Transform(half)))
					attrT = local_
					model = nil
				end
				if model and model.pivot == "bottomcenter" and size then
					local_ = A.TransformToParentTransform(attrT, A.Transform(V(-size[1] * vs * 0.5, 0, -size[3] * vs * 0.5)))
				elseif model and model.pivot == "center" and size then
					-- what the in-game screenshot of the first catapult shows: the vox is centred on its pos
					local_ = A.TransformToParentTransform(attrT, A.Transform(V(-size[1] * vs * 0.5, -size[2] * vs * 0.5, -size[3] * vs * 0.5)))
				end
				H.shapes[sh] = { handle = sh, body = cur, local_ = local_, material = "metal", tags = {}, emissive = 1, valid = true, layer = 1, mask = 255, size = size, voxelSize = vs }
				if H.spawnModel and (H.spawnModel.latency or 0) > 0 then
					-- right after Spawn the engine reports an identity shape transform until the next tick
					H.shapes[sh].realLocal = local_
					H.shapes[sh].local_ = A.Transform()
					H.shapes[sh].revealFrame = H.frame + H.spawnModel.latency
					H.pendingShapes[#H.pendingShapes + 1] = sh
				end
				lastVox = { shape = sh, attrT = attrT, body = cur }
				table.insert(H.bodies[cur].shapes, sh)
				out[#out + 1] = sh
				made[#made + 1] = sh
			end
			local tags = parseAttr(attrs, "tags")
			if tags then
				for t in tags:gmatch("%S+") do
					local k, v = t:match("([^=]+)=?(.*)")
					for _, sh in ipairs(made) do H.shapes[sh].tags[k] = v end
				end
			end
		elseif tag == "light" then
			out[#out + 1] = newHandle()
		elseif tag == "joint" then
			local j = newHandle()
			H.joints[j] = { handle = j, shapes = { lastVox and lastVox.shape or 0, 0 }, type = parseAttr(attrs, "type") or "ball", broken = false, tags = {},
				body = lastVox and lastVox.body or 0, localT = lastVox and A.TransformToParentTransform(lastVox.attrT, H.attrTransform(attrs)) or A.Transform(),
				angle = 0, spawnedWith = out }
			out[#out + 1] = j
		end
	end
	if H.spawnModel and H.spawnModel.physics then
		for _, e in ipairs(out) do
			local jj = H.joints[e]
			if jj and jj.body ~= 0 then
				local b = H.bodies[jj.body]
				local wt = A.TransformToParentTransform(A.Transform(b.pos, b.rot), jj.localT)
				local inside = false
				for _, e2 in ipairs(out) do
					local s2 = H.shapes[e2]
					if s2 and s2.body ~= jj.body and s2.size then
						local mn, mx = H.shapeWorldAabb(s2)
						if wt.pos[1] > mn[1] + 0.05 and wt.pos[1] < mx[1] - 0.05 and wt.pos[2] > mn[2] + 0.05 and wt.pos[2] < mx[2] - 0.05 and wt.pos[3] > mn[3] + 0.05 and wt.pos[3] < mx[3] - 0.05 then inside = true end
					end
				end
				if not inside then jj.broken = true jj.unattached = true end
			end
		end
		for _, e in ipairs(out) do
			local b = H.bodies[e]
			if b and b.dynamic then
				local low = 1e9
				for _, sh in ipairs(b.shapes) do
					local s2 = H.shapes[sh]
					if s2.size then local mn = H.shapeWorldAabb(s2) low = math.min(low, mn[2]) end
				end
				if low < -0.1 then
					b.vel = V(math.random() * 30 - 15, 25, math.random() * 30 - 15)
					b.flung = true
				end
			end
		end
	end
	H.spawned[#H.spawned + 1] = { frame = H.frame, n = #out, xml = content:sub(1, 120) }
	return out
end
A.SpawnLayer = function(xml, layer, t, allowStatic, je) return A.Spawn(xml, t, allowStatic, je) end
A.SpawnTool = function() return {} end

A.MakeHole = function(pos, r0, r1, r2, silent)
	r1 = r1 or 0; r2 = r2 or 0
	if r1 > r0 + 1e-6 then H.warn("MakeHole: r1 bigger than r0") end
	if r2 > r1 + 1e-6 then H.warn("MakeHole: r2 bigger than r1") end
	table.insert(H.holes, { pos = A.VecCopy(pos), r0 = r0, r1 = r1, r2 = r2, frame = H.frame })
	-- count voxels removed from boxes of soft material within r0
	local count = 0
	if #H.cubes > 0 then
		local radii = { [0] = r0, [1] = r1, [2] = r2 }
		eachCubeNear(pos, r0, function(cube)
			local rr = radii[cube.class]
			if rr > 0 then
				local dx, dy, dz = cube.c[1] - pos[1], cube.c[2] - pos[2], cube.c[3] - pos[3]
				if dx * dx + dy * dy + dz * dz <= rr * rr then
					cube.alive = false
					H.shapes[cube.shape].valid = false
					count = count + 10
				end
			end
		end)
	end
	for _, bx in ipairs(H.boxes) do
		local cp = V(math.max(bx.min[1], math.min(pos[1], bx.max[1])), math.max(bx.min[2], math.min(pos[2], bx.max[2])), math.max(bx.min[3], math.min(pos[3], bx.max[3])))
		if A.VecLength(A.VecSub(cp, pos)) < r0 then count = count + 10 end
	end
	return count
end
A.Explosion = function(pos, size, inst)
	if size < 0.5 or size > 4.0 then H.warn("Explosion size out of range 0.5-4: " .. size) end
	table.insert(H.explosions, { pos = A.VecCopy(pos), size = size, frame = H.frame })
end
A.SpawnFire = function() H.fires = H.fires + 1 end
A.GetFireCount = function() return H.fires end
A.QueryClosestFire = function() return false, V() end
A.QueryAabbFireCount = function() return 0 end
A.RemoveAabbFires = function() return 0 end
A.Paint = function(o, r, t, p)
	if r < 0 or r > 5 then H.warn("Paint radius out of range: " .. r) end
	if t and t ~= "explosion" and t ~= "spraycan" then H.warn("Paint type invalid: " .. tostring(t)) end
	H.paints = H.paints + 1
end
A.PaintRGBA = function() H.paints = H.paints + 1 end
A.AddSnow = function() return true end
A.AddHeat = function() end
A.Shoot = function() end

-- particles
A.ParticleReset = function() end
A.ParticleType = function(t) if t ~= "plain" and t ~= "smoke" and t ~= "fire" and t ~= "darksmoke" then H.warn("ParticleType unknown: " .. tostring(t)) end end
A.SpawnParticle = function(pos, vel, life)
	H.particles = H.particles + 1
	H.frameParticles = H.frameParticles + 1
end

-- lights / camera / time
A.PointLight = function(pos, r, g, b, i) H.lights[#H.lights + 1] = pos end
A.ShakeCamera = function(s) H.cameraShake = math.max(H.cameraShake, s) end
A.GetCameraTransform = function()
	if H.camera then return A.TransformCopy(H.camera) end
	return A.GetPlayerCameraTransform(0)
end
A.SetCameraTransform = function(t, fov) H.camera = A.TransformCopy(t); H.cameraFov = fov end
A.SetCameraOffsetTransform = function(t) end
A.SetPlayerCameraOffsetTransform = function(t) end
A.SetCameraFov = function() end
A.SetCameraDof = function() end
A.AttachCameraTo = function() end
A.RequestFirstPerson = function() end
A.RequestThirdPerson = function() end
A.SetTimeScale = function(s)
	if s < 0 or s > 2 then H.warn("SetTimeScale out of range 0-2: " .. s) end
	H.timeScale = s
end
A.GetTime = function() return H.time end
A.GetTimeStep = function() return H.dt end
A.GetFps = function() return 1 / H.dt end
H.env = { skyboxtint = { 1, 1, 1 }, fogColor = { 0.8, 0.8, 0.8 }, sunColorTint = { 1, 1, 1 }, exposure = { 1, 5 }, skyboxbrightness = { 1 } }
H.envLog = {}
A.SetEnvironmentProperty = function(name, a, b, c, d)
	H.env[name] = { a, b, c, d }
	H.envLog[#H.envLog + 1] = { frame = H.frame, ctx = H.ctx, key = name, v = { a, b, c, d } }
end
A.GetEnvironmentProperty = function(name)
	local v = H.env[name]
	if not v then return 0, 0, 0, 0 end
	return v[1], v[2], v[3], v[4]
end
H.post = { saturation = { 1 }, colorbalance = { 1, 1, 1 }, brightness = { 1 }, gamma = { 1 }, bloom = { 1 } }
A.SetPostProcessingProperty = function(name, a, b, c)
	if not H.post[name] then H.warn("SetPostProcessingProperty: unknown property " .. tostring(name)) end
	H.post[name] = { a, b, c }
end
A.GetPostProcessingProperty = function(name)
	local v = H.post[name]
	if not v then H.warn("GetPostProcessingProperty: unknown property " .. tostring(name)) return 0, 0, 0 end
	return v[1], v[2], v[3]
end
A.SetPostProcessingDefault = function() H.post = { saturation = { 1 }, colorbalance = { 1, 1, 1 }, brightness = { 1 }, gamma = { 1 }, bloom = { 1 } } end
A.SetEnvironmentDefault = function() end
H.spritePaths = {}
H.sprites = {}   -- this frame: { path, w, h, a, depthTest, additive }
A.LoadSprite = function(path) checkFile(path, "LoadSprite"); local h = newHandle(); H.spritePaths[h] = path; return h end
A.DrawSprite = function(h, t, w, hh, r, g, b, a, depthTest, additive, fog)
	H.sprites[#H.sprites + 1] = { path = H.spritePaths[h] or "?", pos = t and t.pos, w = w, h = hh, a = a or 1, depthTest = depthTest == true, additive = additive == true }
end
A.DrawLine = function() end
A.DebugLine = function() end
A.DebugCross = function() end
A.DebugTransform = function() end
A.DebugWatch = function() end
A.DebugPrint = function(m) H.note("DebugPrint: " .. tostring(m)) end
A.SetValue = function(var, value, transition, time)
	-- engine animates a global of the calling script; we set it immediately
	if H.currentEnv then H.currentEnv[var] = value end
end
A.SetValueInTable = function(tbl, member, value) end

-- sound
A.LoadSound = function(path, nd)
	checkFile(path, "LoadSound", true, { "snd" })
	local h = newHandle(); H.sounds[h] = path; return h
end
A.LoadLoop = function(path, nd)
	checkFile(path, "LoadLoop", true, { "snd" })
	local h = newHandle(); H.loops[h] = path; return h
end
A.UnloadSound = function() end
A.UnloadLoop = function() end
A.PlaySound = function(h, pos, vol, reg, pitch)
	if not H.sounds[h] then err("PlaySound with invalid handle " .. tostring(h)) return 0 end
	table.insert(H.playedSounds, { path = H.sounds[h], frame = H.frame, vol = vol or 1, pitch = pitch or 1 })
	return newHandle()
end
A.PlaySoundForUser = function(h) return A.PlaySound(h) end
A.PlayLoop = function(h, pos, vol, reg, pitch)
	if not H.loops[h] then err("PlayLoop with invalid handle " .. tostring(h)) return end
	H.playedLoops[H.loops[h]] = (H.playedLoops[H.loops[h]] or 0) + 1
end
A.StopSound = function() end
A.IsSoundPlaying = function() return false end
A.GetSoundProgress = function() return 0 end
A.SetSoundProgress = function() end
A.GetSoundLoopProgress = function() return 0 end
A.SetSoundLoopProgress = function() end
A.PlayMusic = function() end
A.StopMusic = function() end
A.IsMusicPlaying = function() return false end
A.LoadHaptic = function(p) checkFile(p, "LoadHaptic"); return "haptic" .. newHandle() end
A.CreateHaptic = function() return "haptic" .. newHandle() end
A.PlayHaptic = function() end
A.PlayHapticDirectional = function() end
A.HapticIsPlaying = function() return false end
A.SetToolHaptic = function() end
A.StopHaptic = function() end

---------------------------------------------------------------------------
-- players and tools
---------------------------------------------------------------------------
A.GetAllPlayers = function() local o = {}; for _, id in ipairs(H.playerOrder) do o[#o + 1] = id end return o end
A.GetMaxPlayers = function() return 4 end
A.GetPlayerCount = function() return #H.playerOrder end
A.GetAddedPlayers = function() local o = {}; for _, id in ipairs(H.addedPlayers) do o[#o + 1] = id end return o end
A.GetRemovedPlayers = function() local o = {}; for _, id in ipairs(H.removedPlayers) do o[#o + 1] = id end return o end
A.GetPlayerName = function(id) return "Player" .. tostring(id) end
A.GetLocalPlayer = function() return H.playerOrder[1] end
A.IsPlayerLocal = function(id) local p = H.players[id]; return p ~= nil and p.local_ end
A.IsPlayerHost = function(id) return id == H.playerOrder[1] end
A.IsPlayerValid = function(id) return H.players[id] ~= nil end
A.IsMultiplayer = function() return #H.playerOrder > 1 end
A.GetPlayerPos = function(id) return A.VecCopy(P(id).pos) end
local function yawRot(p) return A.QuatEuler(0, p.yaw, 0) end
local function eyeT(p) return A.Transform(A.VecAdd(p.pos, V(0, 1.7, 0)), A.QuatEuler(p.pitch, p.yaw, 0)) end
H.eyeT = eyeT
A.GetPlayerTransform = function(id) local p = P(id); return A.Transform(p.pos, yawRot(p)) end
A.GetPlayerTransformWithPitch = function(id) local p = P(id); return A.Transform(p.pos, A.QuatEuler(p.pitch, p.yaw, 0)) end
A.SetPlayerTransform = function(t, id) local p = P(id); p.pos = A.VecCopy(t.pos); local _, y = A.GetQuatEuler(t.rot); p.yaw = y end
A.SetPlayerTransformWithPitch = function(t, id) local p = P(id); p.pos = A.VecCopy(t.pos); local x, y = A.GetQuatEuler(t.rot); p.yaw = y; p.pitch = x end
A.GetPlayerEyeTransform = function(id) return eyeT(P(id)) end
A.GetPlayerCameraTransform = function(id) return eyeT(P(id)) end
A.GetPlayerPitch = function(id) return P(id).pitch end
A.GetPlayerYaw = function(id) return P(id).yaw end
A.SetPlayerPitch = function(pitch, id) P(id).pitch = pitch end
A.GetPlayerCrouch = function(id) return 0 end
A.GetPlayerUp = function(id) return V(0, 1, 0) end
A.GetPlayerVelocity = function(id) return A.VecCopy(P(id).vel) end
A.SetPlayerVelocity = function(v, id)
	if H.ctx == "client" and H.split then H.note("SetPlayerVelocity called on client") end
	P(id).vel = A.VecCopy(v)
	if A.VecLength(v) > 200 then err("player velocity exploded") end
end
A.SetPlayerGroundVelocity = function(v, id) end
A.GetPlayerAimInfo = function(pos, maxdist, id)
	local p = P(id)
	local e = eyeT(p)
	local dir = A.TransformToParentVec(e, V(0, 0, -1))
	maxdist = maxdist or 100
	local t, n, s = raycast(e.pos, dir, maxdist)
	qreset()
	local hit = t ~= nil
	t = t or maxdist
	local endp = A.VecAdd(e.pos, A.VecScale(dir, t))
	local start = pos
	local d = A.VecNormalize(A.VecSub(endp, start))
	local mat = hit and (H.shapes[s] and H.shapes[s].material or "") or ""
	return hit, start, endp, d, n or V(), t, s or 0, mat
end
A.GetPlayerHealth = function(id) return P(id).health end
A.SetPlayerHealth = function(h, id) P(id).health = h end
A.ApplyPlayerDamage = function(target, dmg, cause, inst)
	local p = P(target)
	if dmg < 0 then H.warn("negative damage") end
	p.damage = p.damage + dmg
	p.health = math.max(0, p.health - dmg)
end
A.GetPlayerCanUseTool = function(id) return P(id).canUseTool end
A.SetPlayerTool = function(tool, id) P(id).tool = tool end
A.GetPlayerTool = function(id) return P(id).tool end
A.GetPlayerVehicle = function(id) return P(id).vehicle end
A.IsPlayerGrounded = function(id) return P(id).pos[2] <= 0.01 end
A.IsPlayerJumping = function() return false end
A.GetPlayerGroundContact = function() return 0 end
A.GetPlayerGrabShape = function() return 0 end
A.GetPlayerGrabBody = function(id) return P(id).grabBody end
A.ReleasePlayerGrab = function(id) P(id).grabBody = 0 end
A.GetPlayerGrabPoint = function() return V() end
A.GetPlayerPickShape = function() return 0 end
A.GetPlayerPickBody = function(id) return P(id).pickBody end
A.GetPlayerInteractShape = function() return 0 end
A.GetPlayerInteractBody = function(id) return P(id).interactBody or 0 end
A.GetPlayerScreen = function() return 0 end
A.SetPlayerScreen = function() end
A.GetPlayerAnimator = function() return 0 end
A.GetPlayerBodies = function() return {} end
A.GetPlayerParam = function(name, id)
	local p = P(id)
	p.params = p.params or {}
	local v = p.params[name]
	if v == nil then if name == "flymode" or name == "godmode" then return false end return 0 end
	return v
end
A.SetPlayerParam = function(name, value, id) local p = P(id); p.params = p.params or {}; p.params[name] = value end
A.GetPlayerWalkingSpeed = function(id) return P(id).walkSpeed or 7 end
A.SetPlayerWalkingSpeed = function(sp, id) P(id).walkSpeed = sp end
A.DisablePlayerInput = function(id) local p = P(id); H.inputDisabledUntil[p.id] = H.frame + 1 end
A.DisablePlayer = function() end
A.IsPlayerDisabled = function() return false end
A.DisablePlayerDamage = function() end
A.SetPlayerHidden = function() end
A.RespawnPlayer = function() end
A.GetPlayerColor = function() return 1, 1, 1 end
A.GetFlashlight = function() return 0 end
A.GetPlayerRig = function() return 0 end
A.GetPlayerOrientation = function() return Q() end

A.RegisterTool = function(id, name, file, group)
	if H.toolsRegistered[id] then H.warn("RegisterTool called twice for " .. id) end
	checkFile(file, "RegisterTool")
	H.toolsRegistered[id] = { name = name, file = file, group = group or 6 }
	H.reg["game.tool." .. id .. ".name"] = name
	if group and (group < 1 or group > 6) then H.warn("tool group out of range") end
	-- parse prefab locations
	if file:match("%.xml$") then
		local full = resolvePath(file)
		if H.fileExists(full) then
			local c = H.readFile(full)
			local locs = {}
			for attrs in c:gmatch("<location([^>]*)>") do
				local n = parseAttr(attrs, "name")
				local pos = parseAttr(attrs, "pos") or "0 0 0"
				local x, y, z = pos:match("(%S+)%s+(%S+)%s+(%S+)")
				if n then locs[n] = A.Transform(V(tonumber(x), tonumber(y), tonumber(z))) end
			end
			for vf in c:gmatch("<vox[^>]-file%s*=%s*[\"']([^\"']+)[\"']") do
				if checkFile(vf, "tool prefab vox") and H.voxSizes then
					H.toolsRegistered[id].voxSizes = H.voxSizes(resolvePath(vf))
					local sc = c:match("<vox[^>]-scale%s*=%s*[\"']([^\"']+)[\"']")
					H.toolsRegistered[id].voxScale = tonumber(sc or "1") or 1
				end
			end
			H.toolsRegistered[id].locations = locs
		end
	end
end
A.SetToolAmmoPickupAmount = function(id, a) end
A.GetToolAmmoPickupAmount = function() return 0 end
A.SetToolEnabled = function(id, en, pid)
	if pid == nil then for _, p in pairs(H.players) do p.enabled[id] = en end else P(pid).enabled[id] = en end
	H.reg["game.tool." .. id .. ".enabled"] = en
end
A.IsToolEnabled = function(id, pid) return P(pid).enabled[id] == true end
A.SetToolAmmo = function(id, a, pid)
	if a < 0 then err("SetToolAmmo negative") end
	if pid == nil then for _, p in pairs(H.players) do p.ammo[id] = a end else P(pid).ammo[id] = a end
	H.reg["game.tool." .. id .. ".ammo"] = a
end
A.GetToolAmmo = function(id, pid) return P(pid).ammo[id] or 0 end
local function toolBody(pid)
	local p = P(pid)
	if not H.toolsRegistered[p.tool] then return 0 end
	if p.toolBody == 0 or p.toolBodyTool ~= p.tool then
		local reg = H.toolsRegistered[p.tool]
		local sizes = reg and reg.voxSizes
		p.toolBody = H.addBody { pos = A.VecAdd(p.pos, V(0.3, 1.3, -0.5)), dynamic = false, shapes = sizes and #sizes or 3, isTool = true, material = "metal" }
		if sizes then
			for k, sh in ipairs(H.bodies[p.toolBody].shapes) do
				H.shapes[sh].size = { sizes[k][1], sizes[k][2], sizes[k][3] }
				H.shapes[sh].voxelSize = 0.1 * (reg.voxScale or 1)
			end
		end
		p.toolBodyTool = p.tool
		H.owner[p.toolBody] = "client"
		for _, sh in ipairs(H.bodies[p.toolBody].shapes) do H.owner[sh] = "client" end
	end
	return p.toolBody
end
A.GetToolBody = function(pid) return toolBody(pid) end
A.SetToolTransform = function(t, sway, pid) P(pid).toolTransform = A.TransformCopy(t) end
A.SetToolTransformOverride = function(t, pid) P(pid).toolTransform = A.TransformCopy(t) end
A.SetToolHandPoseLocalTransform = function(r, l, pid) end
A.GetToolHandPoseLocalTransform = function() return A.Transform(), A.Transform() end
A.GetToolHandPoseWorldTransform = function() return A.Transform(), A.Transform() end
A.GetToolLocationLocalTransform = function(name, pid)
	local p = P(pid)
	local t = H.toolsRegistered[p.tool]
	if t and t.locations and t.locations[name] then return A.TransformCopy(t.locations[name]) end
	return nil
end
A.GetToolLocationWorldTransform = function(name, pid)
	local l = A.GetToolLocationLocalTransform(name, pid)
	if not l then return nil end
	return A.TransformToParentTransform(eyeT(P(pid)), l)
end
A.SetToolOffset = function() end
A.SetToolAllowedZoom = function() end

-- input
local function inp(id) return P(id) end
-- DisablePlayerInput(p) swallows that player's input for server-side readers for the rest of
-- the frame and the next one: the game's spawn menu (data/script/spawn.lua) reads
-- InputPressed("usetool", p) and then calls it precisely so the held tool's script does not
-- see the click. Client-side reads stay live (the vehicle remote mod reads keys on the client
-- while freezing the player, and works in the game).
H.inputDisabledUntil = {}
local function swallowed(id)
	if H.ctx ~= "server" then return false end
	local p = P(id)
	local u = H.inputDisabledUntil[p.id]
	return u ~= nil and H.frame <= u
end
A.InputDown = function(name, id) if swallowed(id) then return false end return inp(id).input[name] == true end
A.InputPressed = function(name, id) if swallowed(id) then return false end return inp(id).pressed[name] == true end
A.InputReleased = function(name, id) if swallowed(id) then return false end return inp(id).released[name] == true end
A.InputValue = function(name, id) if swallowed(id) then return 0 end local p = inp(id); p.values = p.values or {}; return p.values[name] or 0 end
A.InputLastPressedKey = function() return "" end
A.InputClear = function() end
A.LastInputDevice = function() return 1 end
A.HasVersion = function(v) return true end
A.GetVersion = function() return "2.0.0" end
A.IsRunningOnPC = function() return true end
A.IsRunningOnSteam = function() return true end
A.Command = function() end
A.Menu = function() H.note("Menu() called") end
A.HasFile = function(p) local full = resolvePath(p); return H.fileExists(full) end
A.GetEventCount = function() return 0 end
A.PostEvent = function() end
A.GetEvent = function() return nil end
A.GetUserNickname = function() return "tester" end
A.RegisterListenerTo = function() end
A.UnregisterListener = function() end
A.TriggerEvent = function() end
A.IsRunningOnClient = function() return H.ctx == "client" end

-- server/client calls
H.pendingServerCalls = {}
H.pendingClientCalls = {}
A.ServerCall = function(fname, ...)
	if H.ctx == "server" then H.warn("ServerCall from server: " .. fname) end
	table.insert(H.pendingServerCalls, { fname = fname, args = { ... }, n = select("#", ...) })
end
A.ClientCall = function(pid, fname, ...)
	if H.ctx == "client" then H.warn("ClientCall from client: " .. fname) end
	table.insert(H.pendingClientCalls, { pid = pid, fname = fname, args = { ... }, n = select("#", ...) })
end

---------------------------------------------------------------------------
-- UI (only allowed in draw)
---------------------------------------------------------------------------
H.uiStack = 0
H.uiCanvas = { w = 1920, h = 1080 }
A.UiPush = function() H.uiStack = H.uiStack + 1 end
A.UiPop = function() H.uiStack = H.uiStack - 1; if H.uiStack < 0 then err("UiPop without UiPush") end end
A.UiWidth = function() return H.uiCanvas.w end
A.UiHeight = function() return H.uiCanvas.h end
A.UiCenter = function() return H.uiCanvas.w / 2 end
A.UiMiddle = function() return H.uiCanvas.h / 2 end
A.UiText = function(text, move, maxChars)
	text = tostring(text)
	table.insert(H.uiTexts, text)
	return #text * 10, 22, 0, 0, ""
end
A.UiGetTextSize = function(text) return #tostring(text) * 10, 22, 0, 0 end
A.UiMeasureText = function(space, ...) return 100, 22 end
A.UiFont = function(path, size)
	if size < 10 or size > 100 then H.warn("UiFont size out of range: " .. size) end
	checkFile(path, "UiFont", false, { "ui/font" })
end
local function uiImageCheck(path) if path and path:sub(1, 4) == "MOD/" then checkFile(path, "UiImage") elseif path then checkFile(path, "UiImage") end end
A.UiImage = function(path) uiImageCheck(path); return 100, 100 end
A.UiImageBox = function(path) uiImageCheck(path) end
A.UiButtonImageBox = function(path) uiImageCheck(path) end
A.UiGetImageSize = function(path) uiImageCheck(path); return 256, 256 end
A.UiHasImage = function(path) return H.fileExists(resolvePath(path)) end
A.UiTextButton = function(text, w, h)
	text = tostring(text)
	table.insert(H.uiTexts, text)
	H.uiButtonsSeen[text] = true
	if H.uiClicks[text] then H.uiClicks[text] = nil; return true end
	return false
end
A.UiImageButton = function(path) uiImageCheck(path); return false end
A.UiBlankButton = function(w, h) return false, false end
A.UiSlider = function(path, axis, current, min, max)
	uiImageCheck(path)
	H.uiSliderIndex = H.uiSliderIndex + 1
	local v = H.uiSliderSet[H.uiSliderIndex]
	if v ~= nil then H.uiSliderSet[H.uiSliderIndex] = nil; return v, true end
	return current, false
end
A.UiIsMouseInRect = function() return false end
A.UiGetMousePos = function() return 0, 0 end
A.UiWorldToPixel = function(p)
	local cam = A.GetCameraTransform()
	local l = A.TransformToLocalPoint(cam, p)
	local d = -l[3]
	if d <= 0.01 then return 0, 0, d end
	return H.uiCanvas.w / 2 + l[1] / d * 960, H.uiCanvas.h / 2 - l[2] / d * 960, d
end
A.UiGetLanguage = function() return H.language or 0 end
A.UiTextInput = function(text) return text, false end

---------------------------------------------------------------------------
-- per-call checking wrapper
---------------------------------------------------------------------------
local function isVec(v) return type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number" end
local function isQuat(v) return isVec(v) and type(v[4]) == "number" end
local function isTransform(v) return type(v) == "table" and isVec(v.pos) and isQuat(v.rot) end
local checkers = {
	number = function(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end,
	string = function(v) return type(v) == "string" end,
	boolean = function(v) return type(v) == "boolean" end,
	TVec = isVec, TQuat = isQuat, TTransform = isTransform,
}

local function nanCheck(v)
	if type(v) == "number" then return v ~= v end
	if type(v) == "table" then
		for i = 1, 4 do if type(v[i]) == "number" and v[i] ~= v[i] then return true end end
		if v.pos then return nanCheck(v.pos) or nanCheck(v.rot) end
	end
	return false
end

local defaultFor = {
	number = 0, boolean = false, string = "",
}
local function defaultReturn(t)
	if t == "TVec" then return V() elseif t == "TQuat" then return Q() elseif t == "TTransform" then return A.Transform() elseif t == "any" then return {} end
	return defaultFor[t]
end

-- mutating API -> list of argument positions that hold entity handles
H.MUTATING = {
	SetBodyTransform = { 1 }, SetBodyDynamic = { 1 }, SetBodyVelocity = { 1 }, SetBodyAngularVelocity = { 1 },
	SetBodyGravityScale = { 1 }, SetBodyActive = { 1 }, ApplyBodyImpulse = { 1 },
	ConstrainVelocity = { 1, 2 }, ConstrainAngularVelocity = { 1, 2 }, ConstrainPosition = { 1, 2 }, ConstrainOrientation = { 1, 2 },
	SetShapeLocalTransform = { 1 }, SetShapeEmissiveScale = { 1 }, SetShapeDensity = { 1 }, SetShapeCollisionFilter = { 1 },
	SetShapeBody = { 1, 2 }, CreateShape = { 1 }, ClearShape = { 1 }, ResizeShape = { 1 }, CopyShapeContent = { 2 },
	CopyShapePalette = { 2 }, DrawShapeLine = { 1 }, DrawShapeBox = { 1 }, ExtrudeShape = { 1 }, TrimShape = { 1 },
	SplitShape = { 1 }, MergeShape = { 1 },
	SetTag = { 1 }, RemoveTag = { 1 }, SetDescription = { 1 }, Delete = { 1 }, SetProperty = { 1 },
	SetJointMotor = { 1 }, SetJointMotorTarget = { 1 }, DetachJointFromShape = { 1, 2 }, BreakRope = { 1 },
	SetLightEnabled = { 1 }, SetLightColor = { 1 }, SetLightIntensity = { 1 },
	SetScreenEnabled = { 1 }, SetTriggerTransform = { 1 }, DriveVehicle = { 1 }, SetVehicleHealth = { 1 }, SetVehicleParam = { 1 },
	SetAnimatorTransform = { 1 }, MakeRagdoll = { 1 }, UnRagdoll = { 1 },
}
H.authorityErrors = 0

-- Functions that only work from server code in #version 2. Calls from client code
-- are silently ignored by the game, so the harness reports them as errors.
-- Evidence: SetTimeScale - the script_defs example uses server.tick and the game's
-- own v2 script level/cullington/script/truxterminator.lua calls it from server code.
-- SetGravity - the script_defs example calls it from server.tick and it changes scene state.
-- SetEnvironmentProperty - the game's sandbox sets the weather from server.setWeather.
H.SERVER_ONLY = { SetTimeScale = true, SetGravity = true, SetEnvironmentProperty = true }
H.serverOnlyErrors = 0

H.allowedSides = {}
function H.wrapAll()
	local W = {}
	for name, spec in pairs(H.SPEC) do
		local impl = A[name]
		if not impl then
			-- generic stub with plausible returns
			impl = function(...)
				local r = {}
				for i, t in ipairs(spec.returns) do r[i] = defaultReturn(t) end
				return unpack(r, 1, #spec.returns)
			end
			H.genericStubs = H.genericStubs or {}
			H.genericStubs[name] = true
		end
		local params = spec.params
		local isUi = name:sub(1, 2) == "Ui"
		W[name] = function(...)
			local n = select("#", ...)
			local args = { ... }
			H.calls[name] = (H.calls[name] or 0) + 1
			local fc = (H.frameCalls[name] or 0) + 1
			H.frameCalls[name] = fc
			if fc > (H.maxFrameCalls[name] or 0) then H.maxFrameCalls[name] = fc end
			local side = H.sideCalls[H.ctx]
			if side then side[name] = (side[name] or 0) + 1 end
			if isUi and not H.inDraw and name ~= "UiGetLanguage" then
				err(name .. " called outside draw callback")
			end
			if H.SERVER_ONLY[name] and H.ctx == "client" then
				H.serverOnlyErrors = H.serverOnlyErrors + 1
				err(name .. " called from client code: server-only in #version 2, the game ignores it")
				return
			end
			local mut = H.MUTATING[name]
			if mut and H.ctx == "client" then
				for _, ai in ipairs(mut) do
					local hnd = args[ai]
					if type(hnd) == "number" and hnd ~= 0 and H.owner[hnd] == "server" then
						-- like the game: a script error that aborts the rest of the callback
						H.authorityErrors = H.authorityErrors + 1
						error("invalid attempt to access server authored entity from client script (" .. name .. " on " .. hnd .. ")", 2)
					end
				end
			end
			if not spec.varargs then
				for i, p in ipairs(params) do
					local v = args[i]
					if v == nil then
						if not p.opt then err(name .. ": missing required argument #" .. i .. " '" .. p.n .. "'") end
					else
						local c = checkers[p.t]
						if c and not c(v) then
							err(name .. ": argument #" .. i .. " '" .. p.n .. "' expected " .. p.t .. ", got " .. type(v) .. " (" .. tostring(v) .. ")")
						elseif nanCheck(v) then
							err(name .. ": argument #" .. i .. " '" .. p.n .. "' contains NaN")
						end
					end
				end
				if n > #params then H.warn(name .. ": too many arguments (" .. n .. " > " .. #params .. ")") end
			end
			return impl(...)
		end
	end
	-- functions implemented here but missing from script_defs are NOT exposed
	H.W = W
end

---------------------------------------------------------------------------
-- physics step
---------------------------------------------------------------------------
-- hinge joints spawned from XML: the joint's dynamic body is held on the hinge (no free fall) and
-- turned about the joint by its motor (SetJointMotor velocity, or SetJointMotorTarget angle)
function H.hingeStep(dt)
	for j, jj in pairs(H.joints) do
		local b = jj.body and H.bodies[jj.body]
		if jj.type == "hinge" and b and b.valid and b.dynamic and not jj.broken then
			b.hinged = true
			local w = 0
			if jj.target then
				local err = jj.target - jj.angle
				w = math.max(-(jj.maxVel or 3), math.min(jj.maxVel or 3, math.rad(err) * 8))
			elseif jj.motorVel then
				w = jj.motorVel
			end
			local wt = A.TransformToParentTransform(A.Transform(b.pos, b.rot), jj.localT)
			local axis = A.QuatRotateVec(wt.rot, A.Vec(0, 0, 1))
			local d = w * dt
			if d ~= 0 then
				local q = A.QuatAxisAngle(axis, math.deg(d))
				b.rot = A.QuatRotateQuat(q, b.rot)
				b.pos = A.VecAdd(wt.pos, A.QuatRotateVec(q, A.VecSub(b.pos, wt.pos)))
				jj.angle = jj.angle + math.deg(d)
			end
			b.angvel = A.VecScale(axis, w)
			b.vel = A.Vec(0, 0, 0)
		end
	end
end

-- optional: bodies stop at destructible blocks (H.cubeCollision = true)
local function cubeHit(b)
	if not H.cubeCollision or #H.cubes == 0 then return false end
	local hit = false
	H.eachCubeNear(b.pos, b.half[1] + 2, function(cube)
		if hit then return end
		local h = cube.half
		if math.abs(b.pos[1] - cube.c[1]) < h + b.half[1] and math.abs(b.pos[2] - cube.c[2]) < h + b.half[2] and math.abs(b.pos[3] - cube.c[3]) < h + b.half[3] then hit = true end
	end)
	return hit
end

function H.physicsStep(dt)
	H.hingeStep(dt)
	for h, b in pairs(H.bodies) do
		-- sleeping bodies (active == false) are not simulated until something wakes them
		if b.valid and b.dynamic and h ~= H.worldBody and not b.isTool and b.active ~= false and not b.hinged then
			b.vel = A.VecAdd(b.vel, A.VecScale(H.gravity, dt * b.gravityScale))
			local prevPos = b.pos
			b.pos = A.VecAdd(b.pos, A.VecScale(b.vel, dt))
			if cubeHit(b) then
				b.pos = prevPos
				b.vel = A.VecScale(b.vel, 0.1)
			end
			local r = b.half[2]
			if b.pos[2] < r then
				b.pos[2] = r
				if b.vel[2] < -1.5 then
					b.vel[2] = -b.vel[2] * b.restitution
					b.vel[1] = b.vel[1] * 0.8; b.vel[3] = b.vel[3] * 0.8
				else
					b.vel[2] = 0
					b.vel[1] = b.vel[1] * 0.9; b.vel[3] = b.vel[3] * 0.9
				end
			end
			-- static boxes: simple push-out on y
			for _, bx in ipairs(H.boxes) do
				if H.shapes[bx.shape].valid and b.pos[1] > bx.min[1] and b.pos[1] < bx.max[1] and b.pos[3] > bx.min[3] and b.pos[3] < bx.max[3] and b.pos[2] - r < bx.max[2] and b.pos[2] > bx.min[2] then
					local pen = bx.max[2] - (b.pos[2] - r)
					if pen < 0.5 then b.pos[2] = bx.max[2] + r; if b.vel[2] < 0 then b.vel[2] = -b.vel[2] * b.restitution end end
				end
			end
			-- integrate the angular velocity (world space) into the orientation
			local w = b.angvel
			if w[1] ~= 0 or w[2] ~= 0 or w[3] ~= 0 then
				local q = b.rot
				local h = 0.5 * dt
				local x = q[1] + h * (w[1] * q[4] + w[2] * q[3] - w[3] * q[2])
				local y = q[2] + h * (w[2] * q[4] + w[3] * q[1] - w[1] * q[3])
				local z = q[3] + h * (w[3] * q[4] + w[1] * q[2] - w[2] * q[1])
				local ww = q[4] - h * (w[1] * q[1] + w[2] * q[2] + w[3] * q[3])
				local n = math.sqrt(x * x + y * y + z * z + ww * ww)
				b.rot = { x / n, y / n, z / n, ww / n }
			end
			b.angvel = A.VecScale(b.angvel, 0.98)
			if b.pos[2] < -100 then b.valid = false end
		end
	end
	for _, id in ipairs(H.playerOrder) do
		local p = H.players[id]
		p.vel = A.VecAdd(p.vel, A.VecScale(H.gravity, dt))
		p.pos = A.VecAdd(p.pos, A.VecScale(p.vel, dt))
		if p.pos[2] < 0 then p.pos[2] = 0; p.vel[2] = 0; p.vel[1] = p.vel[1] * 0.8; p.vel[3] = p.vel[3] * 0.8 end
	end
end


---------------------------------------------------------------------------
-- shape editing and constraints (added for the mover / volcano mods)
---------------------------------------------------------------------------
local function shapeSize(s) if not s.size then s.size = { 10, 10, 10 } end return s.size end
A.GetShapeSize = function(h)
	local s = H.shapes[h]
	if not s then return 0, 0, 0, 0.1 end
	local sz = shapeSize(s)
	return sz[1], sz[2], sz[3], s.voxelSize or 0.1
end
A.GetShapeVoxelCount = function(h)
	local s = H.shapes[h]
	if not s then return 0 end
	if s.voxels then return s.voxels end
	local sz = shapeSize(s)
	return sz[1] * sz[2] * sz[3]
end
A.CreateShape = function(body, t, ref)
	local b = H.bodies[body]
	if not b then H.err("CreateShape on invalid body " .. tostring(body)) return 0 end
	if type(ref) == "string" then H.checkFile(ref, "CreateShape") elseif not H.shapes[ref] then H.err("CreateShape: invalid reference shape " .. tostring(ref)) end
	H.nextHandle = H.nextHandle + 1
	local sh = H.nextHandle
	H.owner[sh] = (H.ctx == "client") and "client" or "server"
	local voxel = (type(ref) == "number" and H.shapes[ref] and H.shapes[ref].voxelSize) or 0.1
	H.shapes[sh] = { handle = sh, body = body, local_ = A.TransformCopy(t), material = "metal", tags = {}, emissive = 1, valid = true, layer = 1, mask = 255, size = { 1, 1, 1 }, voxels = 0, voxelSize = voxel }
	table.insert(b.shapes, sh)
	return sh
end
A.ResizeShape = function(h, x0, y0, z0, x1, y1, z1)
	local s = H.shapes[h]
	if not s then H.err("ResizeShape invalid shape") return false, V() end
	local nx, ny, nz = x1 - x0 + 1, y1 - y0 + 1, z1 - z0 + 1
	if nx < 1 or ny < 1 or nz < 1 or nx > 256 or ny > 256 or nz > 256 then H.err("ResizeShape: bad size " .. nx .. "x" .. ny .. "x" .. nz) return false, V() end
	s.size = { nx, ny, nz }
	return true, V(x0, y0, z0)
end
A.CopyShapeContent = function(src, dst)
	local a, b = H.shapes[src], H.shapes[dst]
	if not a or not b then H.err("CopyShapeContent invalid shapes") return end
	local sz = shapeSize(a)
	b.size = { sz[1], sz[2], sz[3] }
	b.voxels = A.GetShapeVoxelCount(src)
end
A.CopyShapePalette = function() end
A.GetShapePalette = function() return { 1, 2, 3 } end
A.GetShapeMaterial = function() return "metal", 0.5, 0.5, 0.5, 1, 0, 0, 0, 0 end
H.brush = nil
A.SetBrush = function(typ, size, index, object)
	if typ ~= "sphere" and typ ~= "cube" and typ ~= "noise" then H.err("SetBrush: bad type " .. tostring(typ)) end
	if size < 1 or size > 16 then H.err("SetBrush: size out of range 1-16: " .. size) end
	H.brush = { typ = typ, size = size, index = index }
end
A.DrawShapeBox = function(h, x0, y0, z0, x1, y1, z1)
	local s = H.shapes[h]
	if not s then H.err("DrawShapeBox invalid shape") return end
	if not H.brush then H.err("DrawShapeBox before SetBrush") end
	local sz = shapeSize(s)
	for _, c in ipairs({ { x0, 1 }, { x1, 1 }, { y0, 2 }, { y1, 2 }, { z0, 3 }, { z1, 3 } }) do
		if c[1] < 0 or c[1] >= sz[c[2]] then H.err(string.format("DrawShapeBox outside shape bounds (%d not in 0..%d)", c[1], sz[c[2]] - 1)) return end
	end
	s.voxels = (s.voxels or 0) + (math.abs(x1 - x0) + 1) * (math.abs(y1 - y0) + 1) * (math.abs(z1 - z0) + 1)
end
A.DrawShapeLine = function() end
A.ExtrudeShape = function() end
A.TrimShape = function() return V() end
A.ClearShape = function(h) local s = H.shapes[h]; if s then s.voxels = 0 end end
A.SplitShape = function() return {} end
A.MergeShape = function(h) return h end
A.GetShapeMaterialAtIndex = function(h, x, y, z)
	local s = H.shapes[h]
	if not s then return "", 0, 0, 0, 0, 0 end
	local sz = shapeSize(s)
	if x < 0 or y < 0 or z < 0 or x >= sz[1] or y >= sz[2] or z >= sz[3] then return "", 0, 0, 0, 0, 0 end
	-- hollow box pattern so resampling code sees empty and filled voxels
	local edge = (x == 0 or y == 0 or z == 0 or x == sz[1] - 1 or y == sz[2] - 1 or z == sz[3] - 1)
	if edge then return s.material, 0.5, 0.5, 0.5, 1, 3 end
	return "", 0, 0, 0, 0, 0
end

-- constraints: drive the fake body towards the target in the next physics step
A.ConstrainPosition = function(bA, bB, pA, pB, maxVel, maxImp)
	if not H.inUpdate then H.warn("ConstrainPosition outside update") end
	local b = H.bodies[bA]
	if not b or not b.valid then return end
	if not b.dynamic then return end
	local d = A.VecSub(pB, pA)
	local v = A.VecScale(d, 60)
	local l = A.VecLength(v)
	if maxVel and l > maxVel then v = A.VecScale(v, maxVel / l) end
	b.vel = A.VecSub(v, A.VecScale(H.gravity, 1 / 60))
	b.active = true
end
A.ConstrainOrientation = function(bA, bB, qA, qB, maxAngVel, maxAngImp)
	if not H.inUpdate then H.warn("ConstrainOrientation outside update") end
	local b = H.bodies[bA]
	if not b or not b.valid or not b.dynamic then return end
	b.rot = A.QuatSlerp(b.rot, qB, 0.5)
end
A.ConstrainVelocity = function() if not H.inUpdate then H.warn("ConstrainVelocity outside update") end end
A.ConstrainAngularVelocity = function() if not H.inUpdate then H.warn("ConstrainAngularVelocity outside update") end end

function H.addVehicle(mainBody, extraBodies)
	local v = newHandle()
	H.vehicles[v] = { body = mainBody, bodies = { mainBody }, driven = nil, health = 1 }
	H.vehicleOf[mainBody] = v
	for _, b in ipairs(extraBodies or {}) do
		H.vehicleOf[b] = v
		table.insert(H.vehicles[v].bodies, b)
	end
	return v
end
A.GetVehicleBody = function(v) local vv = H.vehicles[v]; return vv and vv.body or 0 end
A.GetVehicleBodies = function(v) local vv = H.vehicles[v]; if not vv then return {} end local o = {} for i, b in ipairs(vv.bodies) do o[i] = b end return o end
A.GetVehicleTransform = function(v) local vv = H.vehicles[v]; if not vv then return A.Transform() end return A.GetBodyTransform(vv.body) end
A.GetVehicleHealth = function(v) local vv = H.vehicles[v]; return vv and vv.health or 0 end
A.DriveVehicle = function(v, drive, steering, handbrake)
	local vv = H.vehicles[v]
	if not vv then H.err("DriveVehicle: invalid vehicle " .. tostring(v)) return end
	vv.driven = { drive = drive, steering = steering, handbrake = handbrake, frame = H.frame }
	-- crude motion so scenarios can see the vehicle move
	local b = H.bodies[vv.body]
	if b and b.valid then
		local fwd = A.QuatRotateVec(b.rot, V(0, 0, -1))
		b.vel = A.VecAdd(A.VecScale(b.vel, 0.95), A.VecScale(fwd, drive * 0.5))
		b.rot = A.QuatRotateQuat(b.rot, A.QuatAxisAngle(V(0, 1, 0), -steering * 1.5))
	end
end
A.FindVehicles = function() local o = {} for v in pairs(H.vehicles) do o[#o + 1] = v end table.sort(o) return o end
A.FindVehicle = function() for v in pairs(H.vehicles) do return v end return 0 end

return H
