-- Catapult law from Alexey's in-game report of 10.10: "it spawns only partly, complains about bad
-- ground and disappears almost at once", screenshot line
--   refused: arm, bucket not found among 1 bodies / 2 shapes after 30 ticks
-- Cause: the catapult was spawned from an XML text with two top-level <body> elements (the static
-- frame with frame + axle, then the dynamic arm with hub, hinge, beam, bucket, weight). An XML text
-- has one root; the game spawned only the first body - exactly 1 body / 2 shapes. The game's own
-- scripts wrap several bodies in <prefab><group>...</group></prefab> (data/script/mp/lib/tools.lua),
-- and the harness now spawns only the first root element of a text with several, like the game.
-- Also: an assembly failure showed the "no room here: aim at open ground" message, and the yellow
-- debug line was on by default.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "corner", physics = true, contentBounds = true, boundsDelay = 1, shapesDelay = 1, dynamicDelay = 1 }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("catapult")
T.frames(1)

-- 1. it assembles: two bodies from one Spawn, the arm carries the bucket, the hinge joins them
T.press("usetool"); T.frames(60)
local c = srv().cats[1]
T.check(c ~= nil, "the catapult is assembled (refusal: " .. tostring(T.sharedOf().cp.reason) .. ")")
local spawn = nil
for _, s in ipairs(H.spawned) do if s.xml:find("name='catapult'", 1, true) then spawn = s end end
T.check(spawn ~= nil and spawn.xml:find("<prefab", 1, true) == 1, "the catapult is spawned as one prefab document (one root element)")
if c then
	T.check(not A.IsBodyDynamic(c.frame) and A.IsBodyDynamic(c.arm) and c.frame ~= c.arm, "a static frame and a separate dynamic arm")
	T.check(A.HasTag(c.arm, "catapult_arm"), "the arm has its tag")
	T.check(c.bucket ~= 0 and A.GetShapeBody(c.bucket) == c.arm, "the bucket is part of the arm")
	local sx, sy, sz = A.GetShapeSize(c.bucket)
	local t = { sx, sy, sz } table.sort(t)
	T.check(t[1] == 5 and t[2] == 9 and t[3] == 9, "the bucket shape is the 9x9x5 bucket")
	T.check(srv().hubOffAxle(c) <= 0.05, "the arm hangs on the axle (scripted hinge)")
	T.check(T.hasText("Catapult placed"), "the player is told it is placed")
end
T.check(not T.hasText("refused") and not T.hasText("placing:"), "no yellow debug line on screen by default")

-- 2. crates: six bodies from one Spawn (the same multi-root text before)
if c then
	for _, b in ipairs(srv().contents(c)) do A.Delete(b) end
	T.frames(2)
	T.press("4"); T.frames(3)
	local crates = srv().contents(c)
	T.check(#crates == 6, "4 loads a pile of six crates (" .. #crates .. ")")
end

-- 3. no ground: the "aim at open ground" message (turned away from the first catapult, whose
-- frame would otherwise be the ground 14 m ahead)
H.P(1).yaw = 180
H.noGround = true
local printed0 = #H.printed
T.press("usetool"); T.frames(3)
H.noGround = nil
T.check(T.hasText("aim at open ground"), "no ground: the player is told to aim at open ground")
T.frames(150)

-- 4. a failed assembly (the game gives only the frame): its own message, not "bad ground"; the
-- reason goes to the log; what was spawned is removed, and the player is told so
H.P(1).yaw = 90
H.spawnModel.maxBodies = 1
local n0 = #srv().cats
T.press("usetool"); T.frames(90)
H.spawnModel.maxBodies = nil
T.check(#srv().cats == n0, "a half catapult is not registered")
T.check(T.hasText("did not assemble"), "a failed assembly says so")
T.check(not T.hasText("aim at open ground"), "a failed assembly is not reported as bad ground")
local logged = false
for i = printed0 + 1, #H.printed do if H.printed[i]:find("missing", 1, true) and H.printed[i]:find("catapult", 1, true) then logged = true end end
T.check(logged, "the refusal reason is written to the log")
local left = 0
for _, b in pairs(H.bodies) do if b.valid and b.tags and b.tags.catapult_part ~= nil and b.spawnFrame and b.spawnFrame > 0 then left = left + 1 end end
T.check(left == 2, string.format("nothing of the failed catapult is left (bodies with catapult_part: %d, the first catapult has 2)", left))

-- Russian
H.reg["options.language"] = 7
H.spawnModel.maxBodies = 1
T.frames(150)
T.press("usetool"); T.frames(90)
H.spawnModel.maxBodies = nil
T.check(T.hasText("не собралась"), "the failure message in Russian")
H.reg["options.language"] = 0

-- the debug line is still there for testing, behind the option
H.reg["savegame.mod.debugline"] = true
T.frames(2)
T.check(T.hasText("catapult:"), "the debug line shows when switched on in the options")
