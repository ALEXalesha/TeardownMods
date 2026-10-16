-- Singularity Grenade drop-queue law. Independent review 16.10.2026: a drop request from another
-- mod (the Camera Drone) that came while 4 grenades were alive was read, cleared and thrown away.
-- Now it stays queued in the registry until there is room, then spawns.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function alive() return srv().aliveCount() end
local function total() local n = 0 for _ in pairs(srv().grenades) do n = n + 1 end return n end

H.addPlayer(1, V(0, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(2)
local s = srv().settings
for i = 1, 4 do srv().spawnGrenade(V(i * 30, 1, 0), V(0, 0, 0), 1, s) end
T.frames(1)
T.check(alive() == 4, "4 grenades alive (the limit)")

-- the drone writes a drop request
local function request(x, y, z)
	local n = (H.reg["level.singularity_grenade.reqcount"] or 0) + 1
	local k = "level.singularity_grenade.req." .. n
	H.reg[k .. ".x"] = x; H.reg[k .. ".y"] = y; H.reg[k .. ".z"] = z
	H.reg[k .. ".vx"] = 0; H.reg[k .. ".vy"] = 0; H.reg[k .. ".vz"] = 0
	H.reg[k .. ".owner"] = 1
	H.reg["level.singularity_grenade.reqcount"] = n
	return k
end
local k1 = request(0, 5, -5)
local k2 = request(2, 5, -5)
T.frames(5)
T.check(total() == 4, "no fifth grenade while 4 are alive")
T.check(H.reg[k1 .. ".x"] ~= nil and H.reg[k2 .. ".x"] ~= nil, "both requests stay queued")

-- one grenade goes away: the first request spawns, the second keeps waiting
for id, g in pairs(srv().grenades) do if g.id == 1 then srv().remove(g) end end
T.frames(2)
T.check(alive() == 4, "a queued request fills the free slot (alive " .. alive() .. ")")
T.check(H.reg[k1 .. ".x"] == nil and H.reg[k2 .. ".x"] ~= nil, "first request used, second still queued")
local found = false
for _, g in pairs(srv().grenades) do
	if g.phase ~= "done" and math.abs(g.center[1]) < 0.01 and math.abs(g.center[3] + 5) < 0.01 then found = true end
end
T.check(found, "the grenade spawns where the drone dropped it")
for id, g in pairs(srv().grenades) do if g.id == 2 then srv().remove(g) end end
T.frames(2)
T.check(H.reg[k2 .. ".x"] == nil and alive() == 4, "the second request spawns when the next slot frees")
