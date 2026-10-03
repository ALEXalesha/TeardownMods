-- The voxel moon must sit on the aim point whatever vox origin convention the game uses: here the
-- pivot is the model's corner and a spawned shape reports its transform one tick late, so only
-- the closed-loop correction can put the moon's centre into its crater.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
H.spawnModel = { pivot = "corner", latency = 1 }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
H.addStaticBox(V(-30, 0, -70), V(30, 10, -69), "masonry")
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("fallingmoon")
T.frames(1)
T.press("usetool"); T.frames(2)
local m = sh().m
local c = V(m.x, m.y, m.z)
srv().ev.T = 60
sh().m.T = 60
T.runUntil(function() return sh().m.phase == "impact" end, 4000)
T.frames(30)
local b = srv().ev.moonBody
local shp = H.bodies[b].shapes[1]
local sx, sy, sz, vs = H.API.GetShapeSize(shp)
local mc = H.API.TransformToParentPoint(H.API.GetShapeWorldTransform(shp), V(sx * vs * 0.5, sy * vs * 0.5, sz * vs * 0.5))
local off = math.sqrt((mc[1] - c[1]) ^ 2 + (mc[3] - c[3]) ^ 2)
T.check(off < 0.5 and mc[2] < c[2], string.format("the voxel moon sits on the aim point with a corner pivot too (%.2f m off)", off))
