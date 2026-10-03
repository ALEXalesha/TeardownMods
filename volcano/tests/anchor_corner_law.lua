-- Volcano anchor law with the other plausible vox convention (pivot at the model's corner) and a
-- one-tick delay before a spawned shape reports its transform: the cone must still stand on the
-- clicked point, which only the closed-loop correction can guarantee.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "corner" }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -4
local eye = A.GetPlayerEyeTransform(1)
local fwd = A.TransformToParentVec(eye, V(0, 0, -1))
local tHit = -eye.pos[2] / fwd[2]
local click = V(eye.pos[1] + fwd[1] * tHit, 0, eye.pos[3] + fwd[3] * tHit)

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("volcano")
T.frames(1)
T.press("usetool"); T.frames(2)
T.runUntil(function() return sh().v.phase == "rumble" end, 900)
for i, layer in ipairs(srv().v.layers) do
	local shp = layer.shapes[1]
	local sx, sy, sz, vs = A.GetShapeSize(shp)
	local fc = A.TransformToParentPoint(A.GetShapeWorldTransform(shp), V(sx * vs * 0.5, 0, sz * vs * 0.5))
	local dc = math.sqrt((fc[1] - click[1]) ^ 2 + (fc[3] - click[3]) ^ 2)
	T.check(dc < 0.5, string.format("layer %d stands on the clicked point (%.2f m off)", i, dc))
end
