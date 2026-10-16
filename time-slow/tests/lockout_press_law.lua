-- Lockout press law (independent review 16.10.2026). A key press while the energy was locked out
-- switched slow motion on for one tick and straight off again: the enter whoosh and then the exit
-- whoosh played. During lockout a press (hold or toggle mode) must not activate at all.
local function V(x, y, z) return { x, y, z } end
local function cli() return T.cenv().client end
local function hold(key, n) for i = 1, n do T.hold(key); T.frames(1) end end
H.addPlayer(1, V(0, 0, 0))
H.reg["savegame.mod.capacity"] = 2.0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.press("h"); hold("h", 200)
T.release("h"); T.frames(1)
T.check(cli().lockout, "energy ran out: lockout")
local e0, x0 = T.soundsPlayed("enter.ogg"), T.soundsPlayed("exit.ogg")
T.press("h"); T.frames(1); T.release("h"); T.frames(1)
local e1, x1 = T.soundsPlayed("enter.ogg"), T.soundsPlayed("exit.ogg")
T.check(e1 == e0 and x1 == x0, "hold mode: no whoosh on a press during lockout (enter +" .. (e1 - e0) .. ", exit +" .. (x1 - x0) .. ")")
-- toggle mode
H.reg["savegame.mod.toggle"] = true
T.check(cli().lockout, "still locked out")
T.press("h"); T.frames(1); T.release("h"); T.frames(1)
local e2, x2 = T.soundsPlayed("enter.ogg"), T.soundsPlayed("exit.ogg")
T.check(e2 == e1 and x2 == x1 and not cli().active, "toggle mode: no whoosh on a press during lockout (enter +" .. (e2 - e1) .. ", exit +" .. (x2 - x1) .. ")")
-- after recharging the key works again
T.runUntil(function() return not cli().lockout end, 1200)
T.press("h"); T.frames(1); T.release("h"); T.frames(1)
T.check(cli().active and T.soundsPlayed("enter.ogg") == e2 + 1, "toggle mode: a press after the recharge starts slow motion")
T.press("h"); T.frames(1); T.release("h"); T.frames(1)
H.reg["savegame.mod.toggle"] = false
