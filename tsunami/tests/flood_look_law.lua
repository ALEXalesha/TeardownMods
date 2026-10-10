-- Flood look law (in-game 10.10: "the water that comes behind the tsunami could be less 2D, more
-- volumetric and realistic, the physics is all fine"). Up to 775d30a the flood behind the crest was
-- one flat sheet per 10 m segment, 72 m long, at one height, and nothing at all further back: once
-- the front had passed, the player stood in invisible water.
-- The flood must now be drawn around the camera wherever the water is, as a body of water:
--   * several layers at different depths, the deep one darker than the surface;
--   * an uneven surface: tiles at different heights, slightly tilted, and the swell moves in time;
--   * foam and debris streaks lying along the current and drifting with it;
--   * a foam bead where the surge behind the crest meets the slope;
--   * side walls with foam on top where the flooded zone ends (only when the camera is near);
--   * level of detail: big far sheets, small near tiles; a hard cap on sprites per frame.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local A = H.API

local CAP, FLOOD_CAP = 280, 150
local HALF_WIDTH, CREST = 200, 12
T.budget("DrawSprite", CAP)
T.budget("QueryRaycast", 30 + 6 + 2)

local FLOODISH = { ["flood.png"] = "surface", ["flood_deep.png"] = "deep", ["streak.png"] = "streak", ["wall.png"] = "wall" }
local function kindOf(s)
	for k, v in pairs(FLOODISH) do if s.path:find(k, 1, true) then return v end end
	return nil
end
local function camPos() return A.GetPlayerCameraTransform(1).pos end
local function waveFrame(ts, p)
	local rx, rz = p[1] - ts.ox, p[3] - ts.oz
	return rx * ts.dx + rz * ts.dz, -rx * ts.dz + rz * ts.dx
end
local function hdist(p, q) return math.sqrt((p[1] - q[1]) ^ 2 + (p[3] - q[3]) ^ 2) end
local function normalOf(s) return A.QuatRotateVec(s.rot, V(0, 0, 1)) end
local function axisOf(s) return A.QuatRotateVec(s.rot, V(0, 1, 0)) end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("tsunami")
T.frames(1)

-- one wave; the player is moved to the lateral offset `side` from the wave's centre line
-- (the zone is centred on where he called it)
local function run(side)
	T.press("usetool"); T.frames(2)
	if side ~= 0 then
		local ts = sh().ts
		local p = H.P(1).pos
		p[1], p[3] = ts.ox + side * ts.dz, ts.oz - side * ts.dx
	end
	-- the player holds on to something: the current would carry him along with the front, and the
	-- law wants to look at the flood from inside it, far behind the crest
	local hold = { H.P(1).pos[1], H.P(1).pos[2], H.P(1).pos[3] }
	T.frameHooks[#T.frameHooks + 1] = function()
		local q = H.P(1)
		q.pos = { hold[1], hold[2], hold[3] }
		q.vel = V(0, 0, 0)
	end
	local st = { maxAll = 0, maxFlood = 0, badDepth = 0, deepFrames = 0, near = 0, nearTileArea = {}, farTileArea = {},
		layersOk = 0, darkerDeep = 0, uneven = 0, tilted = 0, moved = {}, streaks = 0, streakAligned = 0, streakDrift = {},
		bead = 0, beadFrames = 0, walls = 0, wallsVertical = 0, wallsCover = 0, ahead = 0, outside = 0,
		recedeLevels = {}, recedeNear = 0 }
	local prevSurface, prevStreaks = nil, nil
	T.frameHooks[#T.frameHooks + 1] = function()
		local ts = sh().ts
		local nAll, nFlood = #H.sprites, 0
		for _, s in ipairs(H.sprites) do
			if not s.depthTest then st.badDepth = st.badDepth + 1 end
			if s.fog then nFlood = nFlood + 1 end   -- the flood field is drawn fog-affected, the front is not
		end
		st.maxAll = math.max(st.maxAll, nAll)
		st.maxFlood = math.max(st.maxFlood, nFlood)
		if ts.phase == "idle" or ts.phase == "warning" then prevSurface, prevStreaks = nil, nil return end
		local cam = camPos()
		local ca, cl = waveFrame(ts, cam)
		local level = ts.oy + ts.flood
		if ts.phase == "recede" then
			local surf, n = 0, 0
			for _, s in ipairs(H.sprites) do
				if kindOf(s) == "surface" and hdist(s.pos, cam) < 25 then surf = surf + s.pos[2] n = n + 1 end
			end
			if n > 0 then st.recedeNear = st.recedeNear + 1 st.recedeLevels[#st.recedeLevels + 1] = surf / n end
			return
		end
		-- no water in front of the wave or outside the zone
		for _, s in ipairs(H.sprites) do
			local k = kindOf(s)
			if k == "surface" or k == "deep" or k == "streak" then
				local a, l = waveFrame(ts, s.pos)
				if a > ts.s + 0.5 then st.ahead = st.ahead + 1 end
				if math.abs(l) > HALF_WIDTH + 0.5 then st.outside = st.outside + 1 end
			end
		end
		-- the foam bead at the foot of the back slope, while the front is near the camera
		if math.abs(ts.s - ca) < 60 then
			st.beadFrames = st.beadFrames + 1
			for _, s in ipairs(H.sprites) do
				if s.path:find("foam.png", 1, true) then
					local a = waveFrame(ts, s.pos)
					local x = ts.s - a
					if x > CREST * 1.2 - 4 and x < CREST * 1.2 + 4 and s.pos[2] < ts.oy + 0.5 * ts.h then st.bead = st.bead + 1 break end
				end
			end
		end
		-- deep in the flood: the camera at least 90 m behind the front
		if ts.s - ca < 90 then prevSurface, prevStreaks = nil, nil return end
		st.deepFrames = st.deepFrames + 1
		local surface, deep, streaks = {}, {}, {}
		for _, s in ipairs(H.sprites) do
			local k = kindOf(s)
			local d = hdist(s.pos, cam)
			if k == "surface" or k == "deep" then
				if d < 25 then
					st.near = st.near + 1
					if k == "surface" then surface[#surface + 1] = s else deep[#deep + 1] = s end
				end
				if d < 30 then st.nearTileArea[#st.nearTileArea + 1] = s.w * s.h end
				if d > 70 then st.farTileArea[#st.farTileArea + 1] = s.w * s.h end
			elseif k == "streak" and d < 40 then
				streaks[#streaks + 1] = s
			elseif k == "wall" then
				local _, l = waveFrame(ts, s.pos)
				if math.abs(math.abs(l) - HALF_WIDTH) < 2 then
					st.walls = st.walls + 1
					if math.abs(normalOf(s)[2]) < 0.2 then st.wallsVertical = st.wallsVertical + 1 end
					local top, bottom = s.pos[2] + s.h / 2, s.pos[2] - s.h / 2
					if top >= level - 0.3 and bottom <= 0.05 then st.wallsCover = st.wallsCover + 1 end
				end
			end
		end
		-- layers: a surface and a deeper, darker layer under it
		if #surface > 0 and #deep > 0 then
			local sy, sb, dy, db = 0, 0, 1e9, 0
			for _, s in ipairs(surface) do sy = sy + s.pos[2] sb = sb + (s.r + s.g + s.b) * s.a end
			sy, sb = sy / #surface, sb / #surface
			local deepest
			for _, s in ipairs(deep) do if s.pos[2] < dy then dy = s.pos[2] deepest = s end end
			if sy - dy >= 0.3 then st.layersOk = st.layersOk + 1 end
			if (deepest.r + deepest.g + deepest.b) < (surface[1].r + surface[1].g + surface[1].b) * 0.7 then st.darkerDeep = st.darkerDeep + 1 end
			-- uneven: heights differ between tiles and some tiles are tilted
			local mean, var = sy, 0
			for _, s in ipairs(surface) do var = var + (s.pos[2] - mean) ^ 2 end
			if math.sqrt(var / #surface) > 0.03 then st.uneven = st.uneven + 1 end
			for _, s in ipairs(surface) do
				local ny = normalOf(s)[2]
				local ang = math.deg(math.acos(math.min(1, math.abs(ny))))
				if ang >= 1 and ang <= 15 then st.tilted = st.tilted + 1 break end
			end
		end
		-- the swell moves: the surface 1/2 s later is not the same
		if (H.frame % 30) == 0 then
			if prevSurface then
				local diff, n = 0, 0
				for _, s in ipairs(surface) do
					local best, bd = nil, 1e9
					for _, p in ipairs(prevSurface) do
						local d = hdist(s.pos, p.pos)
						if d < bd then bd, best = d, p end
					end
					if best and bd < 3 then diff = diff + math.abs(s.pos[2] - best.pos[2]) n = n + 1 end
				end
				if n > 0 then st.moved[#st.moved + 1] = diff / n end
			end
			prevSurface = surface
		end
		-- streaks lie along the current and drift with it
		st.streaks = math.max(st.streaks, #streaks)
		local dir = V(ts.dx, 0, ts.dz)
		for _, s in ipairs(streaks) do
			local ax = axisOf(s)
			if math.abs(ax[1] * dir[1] + ax[3] * dir[3]) >= 0.9 and s.h >= 2.5 * s.w then st.streakAligned = st.streakAligned + 1 end
		end
		if prevStreaks then
			for _, s in ipairs(streaks) do
				local best, bd = nil, 1e9
				for _, p in ipairs(prevStreaks) do
					local d = hdist(s.pos, p.pos)
					if d < bd then bd, best = d, p end
				end
				if best and bd < 0.5 then
					st.streakDrift[#st.streakDrift + 1] = (s.pos[1] - best.pos[1]) * dir[1] + (s.pos[3] - best.pos[3]) * dir[3]
				end
			end
		end
		prevStreaks = streaks
	end
	T.runUntil(function() return sh().ts.phase == "idle" end, 6000)
	T.frameHooks[#T.frameHooks] = nil
	T.frameHooks[#T.frameHooks] = nil
	return st
end

local function mean(t) local s = 0 for _, v in ipairs(t) do s = s + v end return #t > 0 and s / #t or 0 end

-- in the middle of the zone
local m = run(0)
T.check(m.deepFrames > 60, string.format("the camera spends time deep in the flood (%d frames)", m.deepFrames))
T.check(m.near > 0, string.format("water is drawn around the camera behind the front (%d near sprites)", m.near))
T.check(m.layersOk >= m.deepFrames * 0.9, string.format("a surface and a deeper layer >= 0.3 m below it (%d of %d frames)", m.layersOk, m.deepFrames))
T.check(m.darkerDeep >= m.deepFrames * 0.9, string.format("the deep layer is darker than the surface (%d of %d frames)", m.darkerDeep, m.deepFrames))
T.check(m.uneven >= m.deepFrames * 0.9, string.format("the surface is uneven (%d of %d frames)", m.uneven, m.deepFrames))
T.check(m.tilted >= m.deepFrames * 0.9, string.format("surface tiles follow the swell, tilted 1-15 deg (%d of %d frames)", m.tilted, m.deepFrames))
T.check(#m.moved > 2 and mean(m.moved) > 0.02, string.format("the swell moves in time (%.3f m mean change per 1/2 s)", mean(m.moved)))
T.check(m.streaks >= 6 and m.streakAligned > 0, string.format("foam and debris streaks along the current (%d near, %d aligned)", m.streaks, m.streakAligned))
T.check(#m.streakDrift > 10 and mean(m.streakDrift) > 0.01, string.format("streaks drift downstream (%.3f m per frame)", mean(m.streakDrift)))
T.check(m.beadFrames > 0 and m.bead >= m.beadFrames * 0.8, string.format("a foam bead at the foot of the back slope (%d of %d frames)", m.bead, m.beadFrames))
T.check(m.walls == 0, "no side walls when the zone's edge is 200 m away")
T.check(#m.farTileArea > 0 and #m.nearTileArea > 0 and mean(m.farTileArea) > 4 * mean(m.nearTileArea), string.format("level of detail: far sheets bigger than near tiles (%.0f vs %.0f m2)", mean(m.farTileArea), mean(m.nearTileArea)))
T.check(m.ahead == 0 and m.outside == 0, string.format("no flood in front of the wave or outside the zone (%d ahead, %d outside)", m.ahead, m.outside))
T.check(m.recedeNear > 30 and m.recedeLevels[#m.recedeLevels] < m.recedeLevels[1] - 0.5, string.format("the flood drains while the water runs back (%.2f -> %.2f m)", m.recedeLevels[1] or 0, m.recedeLevels[#m.recedeLevels] or 0))
T.check(m.maxAll <= CAP and m.maxFlood <= FLOOD_CAP and m.badDepth == 0, string.format("sprite budget: %d per frame (cap %d), flood %d (cap %d), all depth-tested", m.maxAll, CAP, m.maxFlood, FLOOD_CAP))

-- near the side edge of the zone
local e = run(HALF_WIDTH - 15)
T.check(e.walls > 0 and e.wallsVertical == e.walls, string.format("side walls stand at the zone's edge (%d, %d vertical)", e.walls, e.wallsVertical))
T.check(e.wallsCover > 0, "the side wall reaches from the ground up to the water surface")
T.check(e.maxAll <= CAP and e.maxFlood <= FLOOD_CAP, string.format("sprite budget near the edge: %d (cap %d), flood %d", e.maxAll, CAP, e.maxFlood))
