-- Walk every tick law (independent review 16.10.2026). The walking-speed compensation called
-- SetPlayerWalkingSpeed only when the factor changed, but the game's own scripts
-- (data/script/mp/lib/countdown.lua) and the script_defs example call it every tick: it lasts one
-- frame, so the boost was gone right after it was set. It must be applied on every server tick
-- while slow motion is on, and stop (with the speed restored) when it ends.
local function V(x, y, z) return { x, y, z } end
local function cli() return T.cenv().client end
local function callsOf(n) return H.calls[n] or 0 end
local function hold(key, n) for i = 1, n do T.hold(key); T.frames(1) end end
H.addPlayer(1, V(0, 0, 0))
H.reg["savegame.mod.walk"] = true
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.press("h"); T.frames(1)
hold("h", 60)
T.check(cli().active and (H.P(1).walkSpeed or 7) > 20, string.format("walking speed boosted (%.1f)", H.P(1).walkSpeed or 7))
local c0 = callsOf("SetPlayerWalkingSpeed")
hold("h", 30)
local n = callsOf("SetPlayerWalkingSpeed") - c0
T.check(n >= 30, "SetPlayerWalkingSpeed called on every tick while slowed (" .. n .. " calls in 30 frames)")
T.release("h"); T.frames(90)
T.check(not cli().active and H.P(1).walkSpeed == 7, "walking speed restored after slow motion")
local c1 = callsOf("SetPlayerWalkingSpeed")
T.frames(30)
T.check(callsOf("SetPlayerWalkingSpeed") == c1, "no more calls once slow motion is over")
H.reg["savegame.mod.walk"] = false
