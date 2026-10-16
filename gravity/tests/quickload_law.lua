-- Quick load law (independent review 16.10.2026: "gravity after a quick load" was a guess). The mod
-- called SetGravity only during a transition. script_defs.lua: "When the scene restarts, it resets to
-- the default value (0, -10, 0)". If the game resets the scene gravity while this script keeps its
-- state (a quick load restores script state), the indicator said Moon and everything fell like on
-- Earth, for ever. Now the server puts its gravity back whenever the scene gravity differs from it.
-- On Earth the mod does not touch the scene gravity (a level may set its own).
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function tap(k) T.press(k); T.frames(1); T.release(k); T.frames(1) end

T.budget("SetGravity", 1)
H.addPlayer(1, V(0, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(2)
tap("g"); T.frames(120)
T.check(sh().g.preset == 2 and math.abs(H.gravity[2] + 1.62) < 0.01, "Moon gravity set")

-- the game resets the scene gravity (scene restart / quick load), the script state stays
H.gravity = V(0, -10, 0)
T.frames(2)
print(string.format("after the reset: preset %d, scene gravity %.2f", sh().g.preset, H.gravity[2]))
T.check(math.abs(H.gravity[2] + 1.62) < 0.01, "Moon gravity is put back after the scene gravity was reset")
local n = H.calls.SetGravity or 0
T.frames(30)
T.check((H.calls.SetGravity or 0) == n, "no SetGravity every frame once it matches")

-- zero-G is put back too
tap("g"); T.frames(120); tap("g"); T.frames(120)
T.check(sh().g.preset == 4, "zero-G chosen")
H.gravity = V(0, -10, 0)
T.frames(2)
T.check(math.abs(H.gravity[2]) < 0.01, "zero-G is put back after a reset")

-- back on Earth the mod leaves a level's own gravity alone
T.press("g"); for i = 1, 60 do T.hold("g"); T.frames(1) end; T.release("g"); T.frames(120)
T.check(sh().g.preset == 1, "back to Earth")
H.gravity = V(0, -5, 0)
T.frames(30)
T.check(math.abs(H.gravity[2] + 5) < 0.01, "on Earth the mod does not override another gravity")
