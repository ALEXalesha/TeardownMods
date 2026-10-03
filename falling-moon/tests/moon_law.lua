-- Falling Moon laws (in-game report: "looks like a flat 2D sticker drawn over the trees,
-- the craters look like overlapping rings, the sun flare shines through it; the impact
-- barely destroyed anything").
-- 1) The moon is a real object: while far away it is a depth-tested opaque sprite, for
--    the last seconds a voxel moon body (unbreakable, not distance-culled) that really
--    falls onto the aim point and stays there.
-- 2) Destruction with numbers, in a city of 2 m blocks (hollow masonry and wood
--    buildings, hard pillars near the centre, buildings beyond the radius):
--    >= 90 % removed within half the radius, >= 75 % within the radius, >= 70 % of the
--    hard pillars, <= 10 % beyond 1.1 x radius, per-tick work within budget.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
H.addStaticBox(V(-30, 0, -70), V(30, 10, -69), "masonry")   -- the aimed wall
local C = V(0, 0, -69)
local R = 150

-- hollow building: walls and roof of 2 m blocks
local function building(cx, cz, w, hgt, mat)
	local x0, z0 = cx - w / 2, cz - w / 2
	H.addCubes(V(x0, 0, z0), V(x0 + w, hgt, z0 + 2), 2, mat)
	H.addCubes(V(x0, 0, z0 + w - 2), V(x0 + w, hgt, z0 + w), 2, mat)
	H.addCubes(V(x0, 0, z0 + 2), V(x0 + 2, hgt, z0 + w - 2), 2, mat)
	H.addCubes(V(x0 + w - 2, 0, z0 + 2), V(x0 + w, hgt, z0 + w - 2), 2, mat)
	H.addCubes(V(x0 + 2, hgt - 2, z0 + 2), V(x0 + w - 2, hgt, z0 + w - 2), 2, mat)
end
math.randomseed(3)
for i = 1, 32 do
	local a = i * 2.39996
	local d = 12 + (i - 1) / 31 * 132
	building(C[1] + math.cos(a) * d, C[3] + math.sin(a) * d, 8, 10 + (i % 3) * 4, (i % 2 == 0) and "wood" or "masonry")
end
for i = 1, 4 do
	local a = i * 1.5708 + 0.4
	H.addCubes(V(C[1] + math.cos(a) * 28 - 2, 0, C[3] + math.sin(a) * 28 - 2), V(C[1] + math.cos(a) * 28 + 2, 12, C[3] + math.sin(a) * 28 + 2), 2, "hardmasonry")
end
for i = 1, 6 do
	local a = i * 1.047
	building(C[1] + math.cos(a) * 185, C[3] + math.sin(a) * 185, 8, 10, "masonry")
end
local bodies = {}
for i = 1, 60 do
	local a = math.random() * 6.28
	local r = 10 + math.random() * 60
	bodies[i] = H.addBody { pos = V(C[1] + math.cos(a) * r, 0.25, C[3] + math.sin(a) * r), mass = 20 + math.random() * 400 }
end

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("fallingmoon")
T.frames(1)
T.press("usetool"); T.frames(2)
local m = sh().m
T.check(m.phase == "approach", "approach started")
local c = V(m.x, m.y, m.z)

-- the shortest countdown the options allow
srv().ev.T = 60
sh().m.T = 60

-- centre of the voxel moon sphere (body transform applied to the shape centre)
local function moonCentre(b)
	local shp = H.bodies[b].shapes[1]
	local sx, sy, sz, vs = H.API.GetShapeSize(shp)
	return H.API.TransformToParentPoint(H.API.GetShapeWorldTransform(shp), V(sx * vs * 0.5, sy * vs * 0.5, sz * vs * 0.5))
end

-- 1) far: only depth-tested, non-additive moon sprites
local spriteFrames, badSprites = 0, 0
local bodySeen, bodyFrames, approachDist, closer = nil, 0, nil, true
local spriteWhileBody = 0
local f = 0
while sh().m.phase == "approach" and f < 4200 do
	T.frames(1)
	f = f + 1
	local moonSprites = 0
	for _, s in ipairs(H.sprites) do
		if s.path:find("moon.png", 1, true) then
			moonSprites = moonSprites + 1
			if not s.depthTest or s.additive or s.a < 0.999 then badSprites = badSprites + 1 end
		end
	end
	if moonSprites > 0 then spriteFrames = spriteFrames + 1 end
	local b = srv().ev and srv().ev.moonBody
	if b and b ~= 0 and H.bodies[b] then
		bodySeen = b
		bodyFrames = bodyFrames + 1
		if moonSprites > 0 then spriteWhileBody = spriteWhileBody + 1 end
		local mc = moonCentre(b)
		local restY = c[2] - 0.25 * sh().m.mr   -- where the centre ends up, in the crater
		local d = math.sqrt((mc[1] - c[1]) ^ 2 + (mc[2] - restY) ^ 2 + (mc[3] - c[3]) ^ 2)
		if approachDist and d > approachDist + 1e-3 then closer = false end
		approachDist = d
	end
end
T.check(spriteFrames > 100, "the far moon is drawn (" .. spriteFrames .. " frames)")
T.check(badSprites == 0, "every moon sprite is depth-tested, opaque and not additive (" .. badSprites .. " bad)")
T.check(bodySeen ~= nil and bodyFrames >= 240, "a voxel moon body falls for the last 4+ seconds (" .. bodyFrames .. " frames)")
T.check(spriteWhileBody <= 2, "no sprite is drawn over the voxel moon (" .. spriteWhileBody .. " frames; the client learns about the body one sync later)")
T.check(closer, "the voxel moon only gets closer to its resting place")
if bodySeen then
	local shapes = H.bodies[bodySeen].shapes
	local tagged = #shapes > 0
	for _, s in ipairs(shapes) do if H.shapes[s].tags.unbreakable == nil or H.shapes[s].tags.nocull == nil then tagged = false end end
	T.check(tagged, "the voxel moon is unbreakable and never distance-culled")
end

-- 2) impact and destruction
T.check(sh().m.phase == "impact", "impact reached")
local maxR2, maxHoles = 0, 0
local peak = {}
for i = 1, 1200 do
	T.frames(1)
	local r2, n = 0, 0
	for _, h in ipairs(H.holes) do if h.frame == H.frame then r2 = r2 + h.r0 ^ 2 n = n + 1 end end
	maxR2 = math.max(maxR2, r2)
	maxHoles = math.max(maxHoles, n)
	if i <= 150 then
		for k, b in ipairs(bodies) do
			local bb = H.bodies[b]
			local dx, dz = bb.pos[1] - c[1], bb.pos[3] - c[3]
			local dl = math.sqrt(dx * dx + dz * dz)
			if dl > 0.1 then peak[k] = math.max(peak[k] or 0, (bb.vel[1] * dx + bb.vel[3] * dz) / dl) end
		end
	end
	if sh().m.phase == "aftermath" and srv().ev and (srv().ev.queue == nil or #srv().ev.queue == 0) and i > 400 then break end
end
if bodySeen then
	local mc = moonCentre(bodySeen)
	T.check(math.abs(mc[1] - c[1]) < 2 and math.abs(mc[3] - c[3]) < 2 and mc[2] < c[2], string.format("the voxel moon came down on the aim point and sits in it (centre %.1f m off, %.1f m below)", math.sqrt((mc[1] - c[1]) ^ 2 + (mc[3] - c[3]) ^ 2), c[2] - mc[2]))
end
local t1, r1 = H.cubeStats(c, 0, R * 0.5)
local t2, r2 = H.cubeStats(c, 0, R)
local th, rh = H.cubeStats(c, 0, R * 0.25, 2)
local t3, r3 = H.cubeStats(c, R * 1.1, R * 1.5)
T.check(t1 > 0 and r1 / t1 >= 0.9, string.format("within half the radius %.0f %% removed (need >= 90)", 100 * r1 / math.max(t1, 1)))
T.check(t2 > 0 and r2 / t2 >= 0.75, string.format("within the radius %.0f %% removed (need >= 75)", 100 * r2 / math.max(t2, 1)))
T.check(th > 0 and rh / th >= 0.7, string.format("hard pillars near the centre %.0f %% removed (need >= 70)", 100 * rh / math.max(th, 1)))
T.check(t3 > 0 and r3 / t3 <= 0.1, string.format("beyond 1.1 x radius only %.0f %% removed (need <= 10)", 100 * r3 / math.max(t3, 1)))
T.check(maxR2 <= 760 and maxHoles <= 45, string.format("per-tick hole work within budget (max sum r^2 %.0f <= 760, max %d holes <= 45)", maxR2, maxHoles))
local sum, cnt = 0, 0
for k, b in ipairs(bodies) do
	local p0 = H.bodies[b]
	sum = sum + (peak[k] or 0)
	cnt = cnt + 1
end
T.check(cnt > 0 and sum / cnt >= 25, string.format("bodies thrown hard: peak %.1f m/s outwards on average (need >= 25)", sum / math.max(cnt, 1)))
T.check(H.fires > 10, "fires (" .. H.fires .. ")")
