-- Energy text law (16.10.2026). The README said a throw costs 10-15% of the energy; the code takes
-- 5% for a quick throw and up to 15% for a full charge. This law pins every energy number the texts
-- give (README, Workshop): 15 s for about 200 kg held, longer for a lighter load, a throw 5-15%,
-- refill from 0.8 s after the hands are empty, full in 9 s (0.6 x 15 s).
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function E() return srv().p[1].energy end
local function held() return #srv().p[1].held end
local crates = {}
local function home(n)
	-- the dropped crates fell somewhere: put the first n back in front of the player
	for i = 1, #crates do
		local b = H.bodies[crates[i]]
		b.pos = i <= n and V(-1.4 + (i % 4) * 0.9, 0.25, -6 + math.floor(i / 5) * 0.9) or V(40 + i, 0.25, 40)
		b.vel = V(0, 0, 0); b.angvel = V(0, 0, 0)
	end
	T.frames(2)
end
local function lift() T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(1) end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -15
for i = 1, 8 do crates[i] = H.addBody { pos = V(-1.4 + (i % 4) * 0.9, 0.25, -6 + math.floor(i / 5) * 0.9), mass = 25 } end
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("telekinesis")
T.frames(1)

-- 8 x 25 kg = 200 kg: lasts the set 15 s
lift()
T.check(held() == 8, "8 crates of 25 kg held (200 kg)")
T.frames(60 * 14)
T.check(held() == 8, string.format("still held after 14 s (energy %.2f)", E()))
T.runUntil(function() return held() == 0 end, 120)
T.check(held() == 0 and E() == 0, "dropped when the energy ran out, about 15 s with 200 kg")

-- refill: nothing for 0.8 s, then full after 0.6 x 15 = 9 s
T.frames(40)
T.check(E() == 0, "no refill in the first 0.8 s")
T.frames(60 * 9 + 20)
T.check(E() == 1, string.format("full again 9 s later (%.2f)", E()))

-- a lighter load lasts longer: 4 x 25 kg = 100 kg still held after 18 s (0.5 + 100/400 = 0.75 per 15 s -> 20 s)
home(4)
lift()
T.check(held() == 4, "4 crates (100 kg) held")
T.frames(60 * 18)
T.check(held() == 4, string.format("100 kg still held after 18 s (energy %.2f)", E()))
T.frames(60 * 2 + 30)
T.check(held() == 0, "100 kg runs out at about 20 s")
T.frames(60 * 11)

-- a quick throw costs 5%, a fully charged one 15%
home(4)
lift()
local e0 = E()
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(1)
local quick = e0 - E()
print(string.format("quick throw cost %.3f", quick))
T.check(quick > 0.045 and quick < 0.065, "a quick throw costs about 5%")
T.frames(60 * 12)
home(4)
lift()
e0 = E()
T.press("usetool"); for i = 1, 80 do T.hold("usetool"); T.frames(1) end; T.release("usetool"); T.frames(1)
local full = e0 - E()
print(string.format("full throw cost %.3f (holding included)", full))
-- 80 frames of holding 100 kg drain 80/60/15*0.75 = 0.067; the throw itself 0.15
T.check(math.abs(full - 0.067 - 0.15) < 0.02, "a fully charged throw costs 15% (plus the holding time)")
