-- Mover leave-during-resample law. Independent review 16.10.2026: a player who left during an
-- x2 / x0.5 resample job left the job running: it re-created shared.pl for the gone player and
-- finished the half-built copy. Now leaving deletes the job's new body and clears the job; the
-- original object stays as it was.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end

H.addPlayer(1, V(0, 0, 0))
H.addPlayer(2, V(3, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(2)
local box = H.addBody { pos = V(10, 0.25, 10), mass = 20 }
srv().scale(2, box, 2)
local job = srv().jobs[2]
T.check(job ~= nil, "player 2 started a scale job")
local nb = job.nb

for i, id in ipairs(H.playerOrder) do if id == 2 then table.remove(H.playerOrder, i) end end
H.players[2] = nil
H.removedPlayers = { 2 }
T.frames(1)
T.check(srv().jobs[2] == nil, "the job is cleared")
T.check(not H.API.IsHandleValid(nb), "the half-built copy is deleted")
T.frames(200)
T.check(sh().pl[2] == nil, "shared.pl of the gone player is not re-created")
T.check(H.API.IsHandleValid(box) and H.bodies[box].dynamic, "the original object stays as it was")
