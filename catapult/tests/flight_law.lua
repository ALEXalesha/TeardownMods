-- Catapult flight law from Alexey's in-game check of 17.10 (2e1f916): "it works, but the shots do not
-- fly along the trajectory; only the car flies, and then it vanishes in mid-air; the others do not fly,
-- the catapult goes right through them". Debug line: "last shot: angle -54 -> +48, released 5 at 16 m/s |
-- load 1/1 in bucket | car: Spawn gave 48 entities, 5 bodies".
-- Causes, each reproduced on the stand (this law red on 2e1f916):
--  1. the boulder, the barrel and the crates lie still in the bucket and the game takes them out of the
--     simulation (IsBodyActive: "bodies that don't move are taken out of the simulation"); a constraint
--     to the world and SetBodyVelocity do not wake them (the drone's sleep, 17.10), and the arm, moved by
--     SetBodyTransform, swings through them. The car on the rim never rests, so it flew.
--     Stand: H.sleepModel { restSleep, velocityWakes = false, constraintWakes = false }.
--  2. the car vanished: the car is 5 bodies (the game makes every <wheel> a body). trimAmmo counted cars
--     by BODIES, so the automatic reload a second after the shot "saw" 5 cars > 2 and deleted bodies of
--     the car still in the air - its main body among them.
--  3. off the trajectory: the release set the planned speed, but in the same update the swing had
--     already put the load on a position constraint towards the arm (up to 80 m/s) and given the arm its
--     full swing speed. The game solves constraints in the physics step AFTER the script, so the load
--     left with the bucket's speed (about 50 m/s at any power), not the planned 14-56 m/s.
--     Stand: H.constraintModel = "step".
-- 17.10 (2a46c03) in-game: "the car flies fine now, the other loads just stay hanging in the air": the
-- boulder, barrel and crates, asleep in the bucket, were moved to the release point and nothing woke them
-- (not SetBodyActive either). Stand: activeWakes = false, vehicleAwake = true (the car flew). The mod now
-- throws a fresh, awake copy of its load; the law follows the load by its number.
-- The law, for each of the 4 loads (1-4) at two powers: every body of the load is released, leaves at
-- the planned speed (2 %), does not collide with the catapult's arm and frame while it leaves, no body of
-- it is deleted in flight (also with the automatic reload in between), and it lands where the arc
-- preview showed (within 3 % of the range or 2 m).
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
local function cli() return T.cenv().client end
local A = H.API

H.spawnModel = { pivot = "field", physics = true, contentBounds = true, trimEmpty = true, boundsDelay = 1, shapesDelay = 1, dynamicDelay = 1, jointsAttach = false, com = true }
H.sleepModel = { restSleep = 1.0, velocityWakes = false, constraintWakes = false, activeWakes = false, vehicleAwake = true }
H.constraintModel = "step"
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

-- stand self-check: a body lying still falls asleep, and then a world constraint does not move it
do
	local b = H.addBody { pos = V(300, 0.25, 300), mass = 10 }
	T.frames(90)
	local asleep = not A.IsBodyActive(b)
	T.check(asleep, "stand: a body lying still for 1.5 s is out of the simulation")
	A.Delete(b)
end

-- Lua 5.1: bitwise AND of two 8-bit numbers
local function band(x, y)
	local r, bit = 0, 1
	for i = 1, 8 do
		if x % 2 == 1 and y % 2 == 1 then r = r + bit end
		x, y, bit = math.floor(x / 2), math.floor(y / 2), bit * 2
	end
	return r
end
-- SetShapeCollisionFilter: "the layer of one object must be in the mask of the other and vice versa"
local function collides(s1, s2)
	local a, b = H.shapes[s1], H.shapes[s2]
	return band(a.layer, b.mask) ~= 0 and band(b.layer, a.mask) ~= 0
end

local names = { "boulder", "barrel", "car", "crates" }
for _, power in ipairs({ 0.05, 0.6 }) do
	for k = 1, 4 do
		local tag = string.format("%s, power %.2f", names[k], power)
		T.press(tostring(k)); T.frames(3)
		T.runUntil(function() local g = c.groups and c.groups[1] return g and g.placed end, 120)
		c.power = power
		srv().sync()
		T.frames(150)                                  -- lies still long enough to fall asleep
		local bodies = {}
		for _, g in ipairs(c.groups or {}) do for _, b in ipairs(g.bodies) do bodies[#bodies + 1] = b end end
		local main = c.groups[1] and c.groups[1].bodies[1]
		local mainLoad = nil
		for _, a in ipairs(srv().ammo) do if a.body == main then mainLoad = a.load end end
		local asleep = 0
		for _, b in ipairs(bodies) do if not A.IsBodyActive(b) then asleep = asleep + 1 end end
		local arc = cli().arc
		local land = arc and arc.land
		T.check(#bodies > 0 and land ~= nil, tag .. ": loaded (" .. #bodies .. " bodies, " .. asleep .. " asleep) and the arc preview shows a landing point")
		if #bodies == 0 or not land then break end
		local want = 14 + 42 * power
		T.press("q"); T.frames(1)
		local released = nil
		local far, d0 = 0, nil
		for i = 1, 120 do
			T.frames(1)
			if c.state ~= "swing" then released = true break end
			-- carried with the bucket (a load asleep in the bucket is not moved by a constraint)
			local bf = srv().bucketFloor(c)
			local bp = H.bodies[main].pos
			local d = math.sqrt((bp[1] - bf[1]) ^ 2 + (bp[2] - bf[2]) ^ 2 + (bp[3] - bf[3]) ^ 2)
			d0 = d0 or d
			far = math.max(far, math.abs(d - d0))
		end
		T.check(released, tag .. ": the shot is released")
		T.check(far < 1.0, string.format("%s: the load is carried with the bucket while it swings (its distance to the floor changes by %.2f m)", tag, far))
		-- the load is followed by its load number: the mod may replace a body by a fresh copy when it throws it
		local loadId = mainLoad
		if loadId then
			local now = {}
			for _, a in ipairs(srv().ammo) do if a.load == loadId then now[#now + 1] = a.body end end
			local before = bodies
			if #now == #bodies then bodies = now end
			main = bodies[1]
			-- a replaced body does not stay behind, hanging where it was
			local left = 0
			for _, b in ipairs(before) do
				local still = false
				for _, nb in ipairs(bodies) do if nb == b then still = true end end
				if not still and A.IsHandleValid(b) then left = left + 1 end
			end
			T.check(left == 0, tag .. ": no old copy of the load is left behind (" .. left .. ")")
		end
		-- right after the release step: the real speed, measured by how far each body moves in the next
		-- step (GetBodyVelocity of a sleeping body returns the stored velocity although it does not move)
		local p0 = {}
		for i, b in ipairs(bodies) do local bd = H.bodies[b] p0[i] = { bd.pos[1], bd.pos[2], bd.pos[3] } end
		T.frames(1)
		local slow = {}
		for i, b in ipairs(bodies) do
			local bd = H.bodies[b]
			local sp = A.VecLength(A.VecSub(bd.pos, p0[i])) * 60
			if math.abs(sp - want) / want > 0.03 then slow[#slow + 1] = string.format("%.1f", sp) end
		end
		T.check(#slow == 0, string.format("%s: every body (%d) leaves at the planned %.1f m/s%s", tag, #bodies, want,
			#slow > 0 and (" - got " .. table.concat(slow, ", ")) or ""))
		-- leaving the bucket: no collision with the arm or the frame
		local hits = {}
		for f = 1, 18 do
			for _, b in ipairs(bodies) do
				if H.bodies[b].valid then
					for _, s1 in ipairs(H.bodies[b].shapes) do
						for _, part in ipairs({ c.bucket, c.hub, c.beamLong, c.frameShape }) do
							if collides(s1, part) then hits[#hits + 1] = f break end
						end
					end
				end
			end
			if #hits > 0 then break end
			T.frames(1)
		end
		T.check(#hits == 0, tag .. ": while it leaves, the load does not collide with the bucket, arm or frame" .. (#hits > 0 and (" (frame " .. hits[1] .. ")") or ""))
		-- the flight: nothing of the load is deleted, the main body lands where the preview said
		local lost, landed = nil, nil
		for i = 1, 900 do
			T.frames(1)
			for _, b in ipairs(bodies) do if not (H.bodies[b] and H.bodies[b].valid) then lost = lost or i end end
			local bd = H.bodies[main]
			if bd.valid and bd.pos[2] <= 0.2 and i > 10 then landed = { bd.pos[1], bd.pos[3] } break end
		end
		T.check(not lost, tag .. ": no body of the load is deleted in flight" .. (lost and string.format(" (gone %.1f s after the release, state %s)", lost / 60, c.state) or ""))
		if landed then
			local range = math.sqrt((land[1] - c.base[1]) ^ 2 + (land[3] - c.base[3]) ^ 2)
			local miss = math.sqrt((landed[1] - land[1]) ^ 2 + (landed[2] - land[3]) ^ 2)
			T.check(miss <= math.max(2, 0.03 * range), string.format("%s: lands %.1f m from the arc preview's landing point (range %.0f m)", tag, miss, range))
		else
			T.check(false, tag .. ": the load landed")
		end
		-- once away, the load collides with catapults again (a later shot can hit one)
		local ghost = 0
		for _, b in ipairs(bodies) do
			if H.bodies[b] and H.bodies[b].valid then
				for _, s1 in ipairs(H.bodies[b].shapes) do if not collides(s1, c.bucket) then ghost = ghost + 1 end end
			end
		end
		T.check(ghost == 0, tag .. ": after the flight the load collides with the catapult again" .. (ghost > 0 and (" (" .. ghost .. " shapes still pass through)") or ""))
		T.runUntil(function() return c.state == "ready" end, 600)
		T.frames(5)
	end
end

-- the safety net: a thrown load that does not really move (the game left it out of the simulation once
-- more) is put on its arc, awake, and still lands where the preview showed. Stand: the fresh copy is put
-- to sleep right after the release.
do
	T.press("1"); T.frames(3)
	T.runUntil(function() local g = c.groups and c.groups[1] return g and g.placed end, 120)
	c.power = 0.4
	srv().sync()
	T.frames(60)
	local land = cli().arc and cli().arc.land
	local main = c.groups[1] and c.groups[1].bodies[1]
	T.press("q"); T.frames(1)
	T.runUntil(function() return c.state ~= "swing" end, 120)
	local rep = srv().replaced or {}
	while rep[main] do main = rep[main] end
	local bd = H.bodies[main]
	bd.active, bd.slept, bd.vel = false, true, { 0, 0, 0 }
	H.sleepModel.impulseWakes = false
	local p0 = { bd.pos[1], bd.pos[2], bd.pos[3] }
	local landed = nil
	for i = 1, 900 do
		T.frames(1)
		rep = srv().replaced or {}
		while rep[main] do main = rep[main] end
		local b = H.bodies[main]
		if b and b.valid and b.pos[2] <= 0.2 and i > 10 then landed = { b.pos[1], b.pos[3] } break end
	end
	if landed and land then
		local range = math.sqrt((land[1] - c.base[1]) ^ 2 + (land[3] - c.base[3]) ^ 2)
		local miss = math.sqrt((landed[1] - land[1]) ^ 2 + (landed[2] - land[3]) ^ 2)
		T.check(miss <= math.max(2, 0.03 * range), string.format("a thrown load left asleep is put back on its arc and lands %.1f m from the preview (range %.0f m)", miss, range))
	else
		T.check(false, "a thrown load left asleep is put back on its arc and lands (it stays at " .. string.format("%.1f %.1f %.1f", p0[1], p0[2], p0[3]) .. ")")
	end
	T.check(T.env().server.stuck ~= nil and T.env().server.stuck >= 1, "the debug line counts it as stuck (" .. tostring(T.env().server.stuck) .. ")")
	H.sleepModel.impulseWakes = nil
end
