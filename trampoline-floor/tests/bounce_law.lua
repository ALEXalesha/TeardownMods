-- Bounce law for Trampoline Floor (in-game report: "barely works, very weak").
-- Dropped from 5 m above the bouncy surface, the player, a crate and a car come back
-- up to at least 5 m; the next bounce is at least as high; jump on contact goes higher;
-- the same in global mode; and a crowd of bodies landing together all bounce.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -30
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("trampoline")
T.frames(1)
T.press("usetool"); T.frames(2)
local pad = sh().tp.pads[1]
T.check(pad ~= nil, "pad placed")
local top = pad.y + 0.2   -- membrane height

-- highest point reached after the first bounce (fn returns the bottom height)
local function peakAfterBounce(bottom, vel, frames)
	local bounced, peak = false, -1e9
	for i = 1, frames do
		T.frames(1)
		if not bounced and vel() > 1 then bounced = true end
		if bounced then
			peak = math.max(peak, bottom())
			if vel() < -0.5 then break end
		end
	end
	return bounced and peak or nil
end

local function dropPlayer(x, z, h, holdJump)
	H.P(1).pos = V(x, top + h, z)
	H.P(1).vel = V(0, 0, 0)
	if holdJump then
		local p = H.P(1)
		T.frameHooks[#T.frameHooks + 1] = function() p.input.jump = true end
	end
	local peak = peakAfterBounce(function() return H.P(1).pos[2] - top end, function() return H.P(1).vel[2] end, 400)
	if holdJump then T.frameHooks[#T.frameHooks] = nil; H.P(1).input.jump = nil end
	return peak
end

-- 1) player from 5 m on the pad
local p1 = dropPlayer(pad.x, pad.z, 5)
T.check(p1 and p1 >= 5.0, string.format("player dropped from 5 m bounces back to %.2f m (need >= 5)", p1 or -1))
-- 2) the next bounce is at least as high (restitution >= 1, capped)
local p2 = peakAfterBounce(function() return H.P(1).pos[2] - top end, function() return H.P(1).vel[2] end, 400)
T.check(p2 and p1 and p2 >= p1 - 0.05, string.format("second bounce at least as high (%.2f after %.2f)", p2 or -1, p1 or -1))
-- 3) jump held on contact adds height
local pj = dropPlayer(pad.x, pad.z, 5, true)
T.check(pj and pj >= 5 + 2, string.format("jump on contact goes higher (%.2f m)", pj or -1))

-- 4) a crate and a car on the pad
local crate = H.addBody { pos = V(pad.x + 0.4, top + 5 + 0.25, pad.z), mass = 20 }
local cb = H.bodies[crate]
local pc = peakAfterBounce(function() return cb.pos[2] - cb.half[2] - top end, function() return cb.vel[2] end, 400)
T.check(pc and pc >= 5.0, string.format("crate dropped from 5 m bounces back to %.2f m", pc or -1))
cb.valid = false
local car = H.addBody { pos = V(pad.x, top + 5 + 0.8, pad.z), mass = 1200, half = V(1, 0.8, 2) }
H.addVehicle(car, {})
local vb = H.bodies[car]
local pv = peakAfterBounce(function() return vb.pos[2] - vb.half[2] - top end, function() return vb.vel[2] end, 400)
T.check(pv and pv >= 5.0, string.format("car dropped from 5 m bounces back to %.2f m", pv or -1))
vb.valid = false

-- 5) global mode on plain ground
T.press("r"); T.frames(2)
T.check(sh().tp.global, "global mode on")
local gx, gz = pad.x + 12, pad.z
H.P(1).pos = V(gx, 5, gz)
H.P(1).vel = V(0, 0, 0)
local pg = peakAfterBounce(function() return H.P(1).pos[2] end, function() return H.P(1).vel[2] end, 400)
T.check(pg and pg >= 5.0, string.format("global mode: player from 5 m back to %.2f m", pg or -1))
local gb = H.addBody { pos = V(gx + 2, 5.25, gz), mass = 30 }
local gbb = H.bodies[gb]
local pgb = peakAfterBounce(function() return gbb.pos[2] - gbb.half[2] end, function() return gbb.vel[2] end, 400)
T.check(pgb and pgb >= 5.0, string.format("global mode: crate from 5 m back to %.2f m", pgb or -1))
gbb.valid = false
H.P(1).pos = V(0, 0, 0)
H.P(1).vel = V(0, 0, 0)
T.frames(5)

-- 6) a crowd: 60 crates dropped together in global mode all bounce
local crowd = {}
for i = 1, 60 do
	local a = i / 60 * 6.2832
	crowd[i] = H.addBody { pos = V(math.cos(a) * (6 + i % 5), 5.25, math.sin(a) * (6 + i % 5)), mass = 10 + i }
end
T.frames(30)   -- one scan interval so all are tracked
local peaks, done = {}, 0
for f = 1, 300 do
	T.frames(1)
	for i = 1, #crowd do
		local b = H.bodies[crowd[i]]
		if b.vel[2] > 1 then peaks[i] = math.max(peaks[i] or 0, b.pos[2] - b.half[2]) end
	end
end
local good = 0
for i = 1, #crowd do if (peaks[i] or 0) >= 4.5 then good = good + 1 end end
T.check(good >= 54, string.format("crowd of 60 landing together: %d bounce back above 4.5 m (need >= 54)", good))
