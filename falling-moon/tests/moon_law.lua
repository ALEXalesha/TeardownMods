-- Falling Moon laws.
-- In-game reports: (1) "a flat sticker over the trees, ring craters, the sun shines through";
-- (2) "the impact barely destroyed anything"; (3) after ebded38: "when the moon appears the sky
-- flickers" and "not everything is destroyed".
-- 1) Nothing flickers: with the default settings the sky/environment is never written during the
--    whole event, and the voxel moon is not moved every tick (it is spawned once, at the impact).
-- 2) The moon looks solid: every moon sprite is depth-tested, opaque, not additive; it is drawn
--    until the impact; after it the voxel moon sits in its crater on the aim point, unbreakable.
-- 3) Destruction with numbers, in a city of 2 m blocks over the whole default radius (200 m):
--    >= 95 % removed within half the radius, >= 88 % within the radius, >= 70 % of hard pillars,
--    <= 10 % beyond 1.1 x radius; per-step work within budget; a shockwave ring is drawn.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end

H.spawnModel = { pivot = "bottomcenter" }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
H.addStaticBox(V(-30, 0, -70), V(30, 10, -69), "masonry")   -- the aimed wall
local C = V(0, 0, -69)
local R = 200

local function building(cx, cz, w, hgt, mat)
	local x0, z0 = cx - w / 2, cz - w / 2
	H.addCubes(V(x0, 0, z0), V(x0 + w, hgt, z0 + 2), 2, mat)
	H.addCubes(V(x0, 0, z0 + w - 2), V(x0 + w, hgt, z0 + w), 2, mat)
	H.addCubes(V(x0, 0, z0 + 2), V(x0 + 2, hgt, z0 + w - 2), 2, mat)
	H.addCubes(V(x0 + w - 2, 0, z0 + 2), V(x0 + w, hgt, z0 + w - 2), 2, mat)
	H.addCubes(V(x0 + 2, hgt - 2, z0 + 2), V(x0 + w - 2, hgt, z0 + w - 2), 2, mat)
end
math.randomseed(3)
for i = 1, 36 do
	local a = i * 2.39996
	local d = 12 + (i - 1) / 35 * (R - 14)
	building(C[1] + math.cos(a) * d, C[3] + math.sin(a) * d, 8, 10 + (i % 3) * 4, (i % 2 == 0) and "wood" or "masonry")
end
for i = 1, 4 do
	local a = i * 1.5708 + 0.4
	H.addCubes(V(C[1] + math.cos(a) * 28 - 2, 0, C[3] + math.sin(a) * 28 - 2), V(C[1] + math.cos(a) * 28 + 2, 12, C[3] + math.sin(a) * 28 + 2), 2, "hardmasonry")
end
for i = 1, 6 do
	local a = i * 1.047
	building(C[1] + math.cos(a) * (R * 1.25), C[3] + math.sin(a) * (R * 1.25), 8, 10, "masonry")
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
local env0 = #H.envLog
T.press("usetool"); T.frames(2)
local m = sh().m
T.check(m.phase == "approach", "approach started")
local c = V(m.x, m.y, m.z)
srv().ev.T = 60
sh().m.T = 60

local spriteFrames, badSprites, approachFrames = 0, 0, 0
local bodyDuringApproach, closer, lastD = 0, true, nil
while sh().m.phase == "approach" and approachFrames < 4200 do
	T.frames(1)
	approachFrames = approachFrames + 1
	local n = 0
	for _, s in ipairs(H.sprites) do
		if s.path:find("moon.png", 1, true) then
			n = n + 1
			if not s.depthTest or s.additive or s.a < 0.999 then badSprites = badSprites + 1 end
		end
	end
	if n > 0 then spriteFrames = spriteFrames + 1 end
	if sh().m.phase == "approach" and srv().ev and srv().ev.moonBody ~= 0 then bodyDuringApproach = bodyDuringApproach + 1 end
	local mm = sh().m
	local restY = c[2] - 0.25 * mm.mr      -- where the moon's centre ends up, in the crater
	local d = math.sqrt((mm.cx - c[1]) ^ 2 + (mm.cy - restY) ^ 2 + (mm.cz - c[3]) ^ 2)
	if lastD and d > lastD + 1e-3 then closer = false end
	lastD = d
end
T.check(#H.envLog == env0, "no sky or environment writes during the approach (" .. (#H.envLog - env0) .. ")")
T.check(bodyDuringApproach == 0, "no voxel body is moved through the sky (spawned only at the impact)")
T.check(spriteFrames >= approachFrames - 3, string.format("the moon is drawn the whole approach (%d of %d frames)", spriteFrames, approachFrames))
T.check(badSprites == 0, "every moon sprite is depth-tested, opaque and not additive (" .. badSprites .. " bad)")
T.check(closer, "the moon only gets closer")

T.check(sh().m.phase == "impact", "impact reached")
local maxR2, maxHoles, ringFrames = 0, 0, 0
local peak = {}
local moonAt = nil
for i = 1, 2400 do
	T.frames(1)
	local r2, n = 0, 0
	for _, h in ipairs(H.holes) do if h.frame == H.frame then r2 = r2 + h.r0 ^ 2 n = n + 1 end end
	maxR2 = math.max(maxR2, r2)
	maxHoles = math.max(maxHoles, n)
	for _, s in ipairs(H.sprites) do if s.path:find("shock.png", 1, true) and s.depthTest then ringFrames = ringFrames + 1 break end end
	local b = srv().ev and srv().ev.moonBody
	if b and b ~= 0 and H.bodies[b] then
		if i == 5 then moonAt = { H.bodies[b].pos[1], H.bodies[b].pos[2], H.bodies[b].pos[3] } end
	end
	if i <= 150 then
		for k, bb in ipairs(bodies) do
			local bd = H.bodies[bb]
			local dx, dz = bd.pos[1] - c[1], bd.pos[3] - c[3]
			local dl = math.sqrt(dx * dx + dz * dz)
			if dl > 0.1 then peak[k] = math.max(peak[k] or 0, (bd.vel[1] * dx + bd.vel[3] * dz) / dl) end
		end
	end
	if sh().m.phase == "aftermath" and srv().ev and #srv().ev.queue == 0 and srv().ev.craterNext > #srv().ev.crater and i > 400 then break end
end
local b = srv().ev and srv().ev.moonBody
T.check(b and b ~= 0, "the voxel moon appears at the impact")
if b and b ~= 0 then
	local shp = H.bodies[b].shapes[1]
	local sx, sy, sz, vs = H.API.GetShapeSize(shp)
	local mc = H.API.TransformToParentPoint(H.API.GetShapeWorldTransform(shp), V(sx * vs * 0.5, sy * vs * 0.5, sz * vs * 0.5))
	T.check(math.abs(mc[1] - c[1]) < 0.5 and math.abs(mc[3] - c[3]) < 0.5 and mc[2] < c[2], string.format("the voxel moon sits in its crater on the aim point (centre %.2f m off)", math.sqrt((mc[1] - c[1]) ^ 2 + (mc[3] - c[3]) ^ 2)))
	local now = H.bodies[b].pos
	T.check(moonAt and math.abs(now[1] - moonAt[1]) + math.abs(now[2] - moonAt[2]) + math.abs(now[3] - moonAt[3]) < 1e-6, "after settling the voxel moon is never moved")
	local tagged = true
	for _, s in ipairs(H.bodies[b].shapes) do if H.shapes[s].tags.unbreakable == nil then tagged = false end end
	T.check(tagged, "the voxel moon is unbreakable")
end
T.check(ringFrames > 30, "a shockwave ring is drawn (" .. ringFrames .. " frames)")
local t1, r1 = H.cubeStats(c, 0, R * 0.5)
local t2, r2 = H.cubeStats(c, 0, R)
local th, rh = H.cubeStats(c, 0, R * 0.25, 2)
local t3, r3 = H.cubeStats(c, R * 1.1, R * 1.5)
T.check(t1 > 0 and r1 / t1 >= 0.95, string.format("within half the radius %.0f %% removed (need >= 95)", 100 * r1 / math.max(t1, 1)))
T.check(t2 > 0 and r2 / t2 >= 0.88, string.format("within the radius %.0f %% removed (need >= 88)", 100 * r2 / math.max(t2, 1)))
T.check(th > 0 and rh / th >= 0.7, string.format("hard pillars near the centre %.0f %% removed (need >= 70)", 100 * rh / math.max(th, 1)))
T.check(t3 > 0 and r3 / t3 <= 0.1, string.format("beyond 1.1 x radius only %.0f %% removed (need <= 10)", 100 * r3 / math.max(t3, 1)))
T.check(maxR2 <= 1150 and maxHoles <= 60, string.format("per-step hole work within budget (max sum r^2 %.0f <= 1150, max %d holes <= 60)", maxR2, maxHoles))
local sum = 0
for k = 1, #bodies do sum = sum + (peak[k] or 0) end
T.check(sum / #bodies >= 25, string.format("bodies thrown hard: peak %.1f m/s outwards on average", sum / #bodies))
T.check(#H.envLog == env0, "no environment writes at all with the default settings")
