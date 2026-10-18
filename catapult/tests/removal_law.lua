-- Catapult removal law (in-game report: "it cannot be removed"). Delete (R until 18.10) must remove everything the mod
-- ever spawned: registered catapults, pieces broken off them, ammo, and parts of a catapult the
-- mod lost track of. Here body tags are ignored by the spawn (one way the first version lost its
-- catapult: it looked for the arm by tag only), plus an untracked broken piece and a part left
-- by the first version are planted.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "center", physics = true, noBodyTags = true }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("catapult")
T.frames(1)
local before = {}
for h in pairs(H.bodies) do before[h] = true end
T.press("usetool"); T.frames(60)
T.check(#srv().cats == 1, "the catapult is registered even when body tags are not readable")
local spawned = {}
for h, b in pairs(H.bodies) do if not before[h] and b.valid ~= false then spawned[#spawned + 1] = h end end
T.check(#spawned >= 3, "frame, arm and ammo spawned (" .. #spawned .. ")")
-- a piece broken off the frame (a new body carrying the shape tag) and a part of a lost catapult
local piece = H.addBody { pos = V(2, 1, -12), mass = 50 }
H.bodies[piece].tags.catapult_part = ""
local old = H.addBody { pos = V(-3, 4, -12), mass = 500, dynamic = false }
H.bodies[old].tags.catapult = ""
T.press("delete"); T.frames(3)
local left = {}
for _, h in ipairs(spawned) do if A.IsHandleValid(h) then left[#left + 1] = h end end
T.check(#left == 0, "Delete removes everything the placement spawned (" .. #left .. " left)")
T.check(not A.IsHandleValid(piece), "Delete removes a broken-off piece")
T.check(not A.IsHandleValid(old), "Delete removes parts left by the first version")
T.check(#A.FindShapes("catapult_part", true) == 0 and #A.FindBodies("catapult_ammo", true) == 0, "no tagged shape or ammo left")
