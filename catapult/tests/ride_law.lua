-- Catapult ride law from Alexey's in-game check of 17.10 (2a46c03): "the RMB load button should load ME
-- into the catapult and send me; right now that does not happen". RMB (the game's "grab") loaded the
-- selected ammo once more, so nothing visible happened.
-- The law: RMB with the catapult tool near a ready catapult puts the player on the bucket floor (the
-- bucket's own load goes), the catapult fires at once, the player is carried with the bucket, leaves at
-- the planned speed from the release point, passes through the catapult while leaving (collision mask),
-- gets the mask back afterwards, lands near the arc preview's landing point and takes no fall damage.
-- Stand: the strict sleep model of flight_law (the bucket's own load is asleep).
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function cli() return T.cenv().client end
local A = H.API

H.spawnModel = { pivot = "field", physics = true, contentBounds = true, trimEmpty = true, boundsDelay = 1, shapesDelay = 1, dynamicDelay = 1, jointsAttach = false, com = true }
H.sleepModel = { restSleep = 1.0, velocityWakes = false, constraintWakes = false, activeWakes = false, vehicleAwake = true }
H.constraintModel = "step"
-- in-game 17.10 (80eed03): "I fly only half the way, then the speed runs out" - the player's own air
-- movement eats a velocity set once; the launched player is carried along the arc until he lands
H.playerAirDrag = 1.5
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("catapult")
T.frames(1)
T.press("usetool"); T.frames(90)
local c = srv().cats[1]
T.check(c ~= nil and c.state == "ready", "a catapult is placed and ready")
if not c then return end

-- band of two 8-bit numbers (Lua 5.1)
local function band(x, y)
	local r, bit = 0, 1
	for i = 1, 8 do
		if x % 2 == 1 and y % 2 == 1 then r = r + bit end
		x, y, bit = math.floor(x / 2), math.floor(y / 2), bit * 2
	end
	return r
end

for _, power in ipairs({ 0.1, 0.7 }) do
	local tag = string.format("power %.1f", power)
	H.P(1).pos = V(3, 0, -4)
	H.P(1).vel = V(0, 0, 0)
	H.P(1).health = 1
	c.power = power
	srv().sync()
	T.runUntil(function() local g = c.groups and c.groups[1] return g and g.placed end, 120)
	T.frames(120)                                   -- the bucket's load falls asleep
	local own = {}
	for _, a in ipairs(srv().ammo) do if a.cat == c.id and A.IsHandleValid(a.body) then own[#own + 1] = a.body end end
	local arc = cli().arc
	local land = arc and arc.land
	T.check(land ~= nil, tag .. ": the arc preview shows a landing point")
	if not land then break end
	local want = 14 + 42 * power

	T.press("grab"); T.frames(1)
	local floor = srv().bucketFloor(c)
	local pp = H.P(1).pos
	local d = math.sqrt((pp[1] - floor[1]) ^ 2 + (pp[3] - floor[3]) ^ 2)
	T.check(c.state == "swing", tag .. ": RMB fires the catapult (state " .. tostring(c.state) .. ")")
	T.check(d < 1.0 and pp[2] > floor[2] - 0.6 and pp[2] < floor[2] + 1.5,
		string.format("%s: RMB puts the player in the bucket (%.2f m from the floor centre, %.2f m above it)", tag, d, pp[2] - floor[2]))
	local left = 0
	for _, b in ipairs(own) do if A.IsHandleValid(b) then left = left + 1 end end
	T.check(left == 0, tag .. ": the bucket's own load is taken out for the rider (" .. left .. " left)")
	local mask = A.GetPlayerParam("CollisionMask", 1)
	T.check(band(mask, 2) == 0 and band(mask, 4) == 0, tag .. ": while thrown the player passes through the arm and frame (mask " .. tostring(mask) .. ")")

	-- carried with the bucket during the swing
	local far = 0
	while c.state == "swing" do
		T.frames(1)
		if c.state ~= "swing" then break end
		local bf = srv().bucketFloor(c)
		local q = H.P(1).pos
		far = math.max(far, math.sqrt((q[1] - bf[1]) ^ 2 + (q[2] - bf[2]) ^ 2 + (q[3] - bf[3]) ^ 2))
	end
	T.check(far < 2.5, string.format("%s: the player is carried with the bucket while it swings (at most %.2f m from it)", tag, far))
	-- the release: the planned speed, measured by the player's real movement in the next step
	local p0 = { H.P(1).pos[1], H.P(1).pos[2], H.P(1).pos[3] }
	T.frames(1)
	local p1 = H.P(1).pos
	local sp = math.sqrt((p1[1] - p0[1]) ^ 2 + (p1[2] - p0[2]) ^ 2 + (p1[3] - p0[3]) ^ 2) * 60
	T.check(math.abs(sp - want) / want < 0.05, string.format("%s: the player leaves at the planned %.1f m/s (%.1f)", tag, want, sp))
	local landed = nil
	for i = 1, 1200 do
		T.frames(1)
		if H.P(1).pos[2] <= 0.01 and i > 10 then landed = { H.P(1).pos[1], H.P(1).pos[3] } break end
	end
	if landed then
		local range = math.sqrt((land[1] - c.base[1]) ^ 2 + (land[3] - c.base[3]) ^ 2)
		local miss = math.sqrt((landed[1] - land[1]) ^ 2 + (landed[2] - land[3]) ^ 2)
		T.check(miss <= math.max(3, 0.05 * range), string.format("%s: the player lands %.1f m from the arc preview's landing point (range %.0f m)", tag, miss, range))
	else
		T.check(false, tag .. ": the player landed")
	end
	T.frames(120)
	T.check(A.GetPlayerParam("CollisionMask", 1) == 255, tag .. ": after the flight the player collides with everything again (" .. tostring(A.GetPlayerParam("CollisionMask", 1)) .. ")")
	T.check(H.P(1).health >= 0.999, tag .. ": no fall damage by default")
	T.runUntil(function() return c.state == "ready" end, 600)
	T.frames(5)
end

-- RMB far from any catapult does nothing
H.P(1).pos = V(200, 0, 200)
local f0 = T.sharedOf().cp.fireN
T.press("grab"); T.frames(2)
T.check(T.sharedOf().cp.fireN == f0 and H.P(1).pos[1] == 200, "RMB with no catapult within 40 m does nothing")
