-- Drone debug line law. Independent review 16.10.2026: the debug line was drawn in photo mode
-- (which must show a clean picture) and was on by default. Now it is off by default under the new
-- key savegame.mod.debugline (a debug = true left in old saves does not bring it back), and when
-- switched on it is hidden in photo mode together with the HUD.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function me() return sh().d[1] end

H.addPlayer(1, V(0, 0, 0))
H.reg["savegame.mod.debug"] = true
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("drone")
T.frames(1)
T.press("usetool"); T.frames(3)
T.check(me().piloting and T.hasText("BAT"), "piloting, HUD shown")
T.check(not T.hasText("drone: mode"), "debug line off by default (an old debug = true does not count)")

H.reg["savegame.mod.debugline"] = true
T.frames(2)
T.check(T.hasText("drone: mode"), "the debugline option shows it")
T.press("p"); T.frames(2)
T.check(not T.hasText("BAT"), "photo mode hides the HUD")
T.check(not T.hasText("drone: mode"), "photo mode hides the debug line")
T.press("p"); T.frames(2)
T.check(T.hasText("drone: mode") and T.hasText("BAT"), "leaving photo mode shows both again")

-- the options page writes the new key, default off
T.loadOptions("options.lua")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.debugline"] == false, "options: reset sets debugline off")
