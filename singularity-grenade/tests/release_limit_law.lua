-- Singularity Grenade release-limit law. Independent review 16.10.2026: the 4-grenade limit was
-- checked only when the charge started; a grenade that appeared during the charge (a drone drop,
-- another player) let the release throw a fifth one. Now the limit is checked again on release.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function alive() return srv().aliveCount() end

H.addPlayer(1, V(0, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("singularity")
T.frames(1)
local s = srv().settings
for i = 1, 3 do srv().spawnGrenade(V(i * 30, 1, 0), V(0, 0, 0), 1, s) end
T.frames(1)
T.check(alive() == 3, "3 grenades alive")
local ammo = H.API.GetToolAmmo("singularity", 1)
T.press("usetool"); T.frames(1)
T.check(srv().players[1].charging, "charging started with room for one more")
srv().spawnGrenade(V(200, 1, 0), V(0, 0, 0), 1, s)
for i = 1, 10 do T.hold("usetool"); T.frames(1) end
T.release("usetool"); T.frames(2)
T.check(alive() <= 4, "the limit of 4 holds on release (alive " .. alive() .. ")")
T.check(H.API.GetToolAmmo("singularity", 1) == ammo, "no ammo spent on the refused throw")
