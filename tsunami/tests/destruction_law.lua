-- Tsunami destruction law (in-game report: "OK but far too weak, it barely destroyed anything").
-- A town of 2 m blocks in the wave's path, near the player: with the default settings at least
-- 85 % of the wooden buildings and >= 30 % of the brick ones are torn down, hard
-- masonry stays; a car in the water is thrown at >= 18 m/s; work per step stays within budget.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
local function building(cx, cz, w, hgt, mat)
	local x0, z0 = cx - w / 2, cz - w / 2
	H.addCubes(V(x0, 0, z0), V(x0 + w, hgt, z0 + 2), 2, mat)
	H.addCubes(V(x0, 0, z0 + w - 2), V(x0 + w, hgt, z0 + w), 2, mat)
	H.addCubes(V(x0, 0, z0 + 2), V(x0 + 2, hgt, z0 + w - 2), 2, mat)
	H.addCubes(V(x0 + w - 2, 0, z0 + 2), V(x0 + w, hgt, z0 + w - 2), 2, mat)
end
local n = 0
for row = 0, 3 do
	for col = -3, 3 do
		n = n + 1
		local mat = (n % 2 == 0) and "wood" or "masonry"
		building(col * 16 + (row % 2) * 8, -30 - row * 22, 8, 8 + (n % 3) * 2, mat)
	end
end
H.addCubes(V(-4, 0, -150), V(4, 10, -146), 2, "hardmasonry")
local car = H.addBody { pos = V(10, 0.8, -15), mass = 1200, half = V(1, 0.8, 2) }
H.addVehicle(car, {})

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("tsunami")
T.frames(1)
T.press("usetool"); T.frames(2)
local maxHoles, carPeak, maxR2 = 0, 0, 0
T.frameHooks[#T.frameHooks + 1] = function()
	local c, r2 = 0, 0
	for i = #H.holes, 1, -1 do if H.holes[i].frame == H.frame then c = c + 1 r2 = r2 + H.holes[i].r0 ^ 2 else break end end
	maxHoles = math.max(maxHoles, c)
	maxR2 = math.max(maxR2, r2)
	local v = H.bodies[car].vel
	carPeak = math.max(carPeak, math.sqrt(v[1] * v[1] + v[3] * v[3]))
end
T.runUntil(function() return sh().ts.phase == "idle" end, 6000)
local stats = {}
for _, cube in ipairs(H.cubes) do
	local st = stats[cube.material] or { t = 0, r = 0 }
	stats[cube.material] = st
	st.t = st.t + 1
	if not cube.alive then st.r = st.r + 1 end
end
local w, m, h = stats.wood, stats.masonry, stats.hardmasonry
T.check(w.r / w.t >= 0.85, string.format("wooden buildings torn down: %.0f %% (need >= 85)", 100 * w.r / w.t))
T.check(m.r / m.t >= 0.30, string.format("brick buildings broken: %.0f %% (need >= 30)", 100 * m.r / m.t))
T.check(h.r == 0, "hard masonry untouched")
T.check(carPeak >= 18, string.format("the car is thrown at %.1f m/s (need >= 18)", carPeak))
T.check(maxHoles <= 24 and maxR2 <= 950, string.format("holes per step within budget (%d holes, sum r^2 %.0f <= 950)", maxHoles, maxR2))
