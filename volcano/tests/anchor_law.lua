-- Volcano laws (in-game report: "the cone appears to the right of where I clicked while the
-- smoke is in the right place; it barely destroys anything").
-- Spawned shapes follow the game: a vox shape's pivot is the centre of its bottom face, and a
-- freshly spawned shape reports an identity transform until the next tick.
-- 1) One anchor: the cone's real footprint centre, the smoke/lava source and the bombs' origin are
--    within 0.5 m of the clicked point.
-- 2) Destruction in a town of 2 m blocks around it: >= 70 % removed within the blast radius,
--    <= 15 % beyond 1.4 x blast radius, craters from bombs during the eruption.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "bottomcenter", latency = 1 }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -4
H.P(1).yaw = 0

-- where the aim ray hits the ground (eye height from the harness player)
local eye = A.GetPlayerEyeTransform(1)
local fwd = A.TransformToParentVec(eye, V(0, 0, -1))
local tHit = -eye.pos[2] / fwd[2]
local click = V(eye.pos[1] + fwd[1] * tHit, 0, eye.pos[3] + fwd[3] * tHit)

-- a town around the click point
local R = 73 * 0.4 * 0.5           -- medium cone radius
local BLAST = 2.5 * R
local function building(cx, cz, w, hgt, mat)
	local x0, z0 = cx - w / 2, cz - w / 2
	H.addCubes(V(x0, 0, z0), V(x0 + w, hgt, z0 + 2), 2, mat)
	H.addCubes(V(x0, 0, z0 + w - 2), V(x0 + w, hgt, z0 + w), 2, mat)
	H.addCubes(V(x0, 0, z0 + 2), V(x0 + 2, hgt, z0 + w - 2), 2, mat)
	H.addCubes(V(x0 + w - 2, 0, z0 + 2), V(x0 + w, hgt, z0 + w - 2), 2, mat)
end
for i = 1, 14 do
	local a = i * 2.39996
	local d = R + 6 + (i - 1) / 13 * (BLAST - R - 10)
	building(click[1] + math.cos(a) * d, click[3] + math.sin(a) * d, 6, 8, (i % 2 == 0) and "wood" or "masonry")
end
for i = 1, 6 do
	local a = i * 1.047
	building(click[1] + math.cos(a) * (BLAST * 1.6), click[3] + math.sin(a) * (BLAST * 1.6), 6, 8, "masonry")
end

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("volcano")
T.frames(1)
T.press("usetool"); T.frames(2)
local v = sh().v
T.check(v.phase == "grow", "LMB starts a volcano")
local d0 = math.sqrt((v.x - click[1]) ^ 2 + (v.z - click[3]) ^ 2)
T.check(d0 < 0.5, string.format("the volcano's anchor is the clicked point (%.2f m off)", d0))

T.runUntil(function() return sh().v.phase == "rumble" end, 900)
-- the real footprint centre of the cone (bottom layer shape, bottom face centre)
local layer = srv().v.layers[1]
local shp = layer.shapes[1]
local sx, sy, sz, vs = A.GetShapeSize(shp)
local fc = A.TransformToParentPoint(A.GetShapeWorldTransform(shp), V(sx * vs * 0.5, 0, sz * vs * 0.5))
local dc = math.sqrt((fc[1] - click[1]) ^ 2 + (fc[3] - click[3]) ^ 2)
T.check(dc < 0.5, string.format("the cone stands on the clicked point (footprint centre %.2f m off)", dc))
local top = sh().v
local ds = math.sqrt((top.x - click[1]) ^ 2 + (top.z - click[3]) ^ 2)
T.check(ds < 0.5, string.format("smoke and lava come from the same point (%.2f m off)", ds))

-- the first bomb starts above the crater (launch position recorded by the server)
T.runUntil(function() return srv().v and srv().v.lastLaunch ~= nil end, 2400)
local lp = srv().v and srv().v.lastLaunch
local db = lp and math.sqrt((lp[1] - click[1]) ^ 2 + (lp[3] - click[3]) ^ 2) or 99
T.check(db < 0.5, string.format("lava bombs leave from the crater (%.2f m off)", db))
T.runUntil(function() return srv().v and srv().v.lastFlow ~= nil end, 2400)
local fp = srv().v and srv().v.lastFlow
local dfl = fp and math.sqrt((fp[1] - click[1]) ^ 2 + (fp[3] - click[3]) ^ 2) or 99
T.check(dfl < 7 * 0.4, string.format("lava flows start inside the crater rim (%.2f m from the centre, rim 2.8 m)", dfl))

-- the whole eruption and the final blast
local holes0 = #H.holes
T.runUntil(function() return sh().v.phase == "cool" end, 6000)
local eruptHoles = #H.holes - holes0
T.check(eruptHoles >= 40, "bombs punch many craters during the eruption (" .. eruptHoles .. ")")
local big, sum = 0, 0
for i = holes0 + 1, #H.holes do if H.holes[i].r0 >= 2.0 then big = big + 1 end end
T.check(big >= 25, "bomb craters are big: " .. big .. " with radius >= 2 m")
T.runUntil(function() return sh().v.phase == "idle" end, 2400)
local t1, r1 = H.cubeStats(click, 0, BLAST)
local t2, r2 = H.cubeStats(click, BLAST * 1.4, BLAST * 2)
T.check(t1 > 0 and r1 / t1 >= 0.7, string.format("within the blast radius %.0f %% of the town is gone (need >= 70)", 100 * r1 / math.max(t1, 1)))
T.check(t2 > 0 and r2 / t2 <= 0.15, string.format("beyond 1.4 x blast radius %.0f %% (need <= 15)", 100 * r2 / math.max(t2, 1)))
T.check(H.fires >= 20, "fires (" .. H.fires .. ")")
