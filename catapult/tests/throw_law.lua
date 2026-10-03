-- Catapult laws (spawned shapes follow the game: pivot at the bottom-face centre, transform one
-- tick late; the hinge is driven by its motor):
--  * range grows with power; full power throws the boulder >= 150 m;
--  * the arc preview predicts the landing within 5 %;
--  * the load leaves the bucket at the release, with the planned speed, and nothing holds it after;
--  * the player in the bucket is thrown >= 100 m and takes no fall damage by default.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
local function cli() return T.cenv().client end

H.spawnModel = { pivot = "bottomcenter", latency = 1 }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("catapult")
T.frames(1)
T.press("usetool"); T.frames(10)
local c = srv().cats[1]
T.check(c ~= nil and c.state == "ready", "a catapult is placed and ready")
T.check(c.joint ~= 0 and H.joints[c.joint].type == "hinge", "its arm hangs on a hinge joint")
T.check(c.loaded == "boulder", "a boulder is loaded")
local fp = H.bodies[c.frame].pos
T.check(math.abs(fp[3] + 14) < 0.5, string.format("placed 14 m in front of the player (z %.1f)", fp[3]))

-- one throw at a given power: returns horizontal range from the release point, release info,
-- and the range the arc preview showed just before
local function throw(power)
	c.power = power
	srv().sync()
	T.frames(12)                               -- the client sees the new power and recomputes the arc
	local predicted = cli().arcRange
	local inside = srv().contents(c)
	local boulder = inside[1]
	T.press("f"); T.frames(1)
	local rel = nil
	for i = 1, 120 do
		T.frames(1)
		if c.state ~= "swing" then rel = c.lastLaunch break end
	end
	if not rel or not boulder then return nil end
	local b = H.bodies[boulder]
	local relPos = { b.pos[1], b.pos[2], b.pos[3] }
	local relVel = { b.vel[1], b.vel[2], b.vel[3] }
	-- 10 frames later: away from the bucket and nothing holds it
	T.frames(10)
	local bucket = srv().bucketFloor(c)
	local away = math.sqrt((b.pos[1] - bucket[1]) ^ 2 + (b.pos[2] - bucket[2]) ^ 2 + (b.pos[3] - bucket[3]) ^ 2)
	local landed = nil
	for i = 1, 1200 do
		T.frames(1)
		if b.pos[2] <= b.half[2] + 0.05 then landed = { b.pos[1], b.pos[3] } break end
	end
	local range = landed and math.sqrt((landed[1] - relPos[1]) ^ 2 + (landed[2] - relPos[3]) ^ 2) or 0
	T.runUntil(function() return c.state == "ready" end, 600)
	T.frames(3)
	return { range = range, predicted = predicted, rel = rel, relVel = relVel, away = away, held = #c.held }
end

local last = 0
local results = {}
for _, p in ipairs({ 0.2, 0.4, 0.6, 0.8, 1.0 }) do
	local r = throw(p)
	results[#results + 1] = r
	T.check(r ~= nil, string.format("power %.1f: the boulder is thrown", p))
	if r then
		T.check(r.range > last, string.format("power %.1f: range %.0f m grows with power (previous %.0f m)", p, r.range, last))
		last = r.range
		local sp = math.sqrt(r.relVel[1] ^ 2 + r.relVel[2] ^ 2 + r.relVel[3] ^ 2)
		local want = 14 + 42 * p
		T.check(math.abs(sp - want) / want < 0.02, string.format("power %.1f: leaves at the planned %.1f m/s (%.1f)", p, want, sp))
		T.check(r.away > 3 and r.held == 0, string.format("power %.1f: clear of the bucket after 10 frames (%.1f m), nothing held", p, r.away))
		T.check(r.predicted and math.abs(r.predicted - r.range) / r.range < 0.05, string.format("power %.1f: arc preview %.0f m vs real %.0f m (within 5 %%)", p, r.predicted or -1, r.range))
	end
end
T.check(results[5] and results[5].range >= 150, string.format("full power throws the boulder %.0f m (need >= 150)", results[5] and results[5].range or 0))

-- the player in the bucket
c.ammo = 1
local inside = srv().contents(c)
for _, b in ipairs(inside) do H.API.Delete(b) end
T.frames(2)
local floor = srv().bucketFloor(c)
H.P(1).pos = { floor[1], floor[2] + 0.1, floor[3] }
H.P(1).vel = V(0, 0, 0)
c.power = 1
srv().sync()
T.frames(2)
local start = { H.P(1).pos[1], H.P(1).pos[3] }
srv().fire(c)
local flown = 0
for i = 1, 1500 do
	T.frames(1)
	if c.state ~= "swing" and H.P(1).pos[2] <= 0.01 and i > 30 then break end
end
flown = math.sqrt((H.P(1).pos[1] - start[1]) ^ 2 + (H.P(1).pos[3] - start[2]) ^ 2)
T.check(flown >= 100, string.format("the player in the bucket is thrown %.0f m (need >= 100)", flown))
T.check(H.P(1).health >= 0.999, "no fall damage by default")
