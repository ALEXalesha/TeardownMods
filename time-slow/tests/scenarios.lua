-- Harness scenarios for Time Slow.
local function V(x, y, z) return { x, y, z } end
local function cli() return T.cenv().client end
local function callsOf(n) return H.calls[n] or 0 end
local function hold(key, n) for i = 1, n do T.hold(key); T.frames(1) end end

T.budget("SetTimeScale", 1)
T.budget("PlaySound", 2)

H.addPlayer(1, V(0, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(T.hasText("Hold H"), "hint shown at level start")
T.check(H.timeScale == 1 and callsOf("SetTimeScale") == 0, "no slow-down without input")

-- hold H: ramp to x0.25
T.press("h"); T.frames(1)
hold("h", 5)
T.check(H.timeScale < 1 and H.timeScale > 0.25, string.format("ramping in (scale %.2f)", H.timeScale))
T.check(T.soundsPlayed("enter.ogg") == 1, "enter whoosh")
hold("h", 40)
T.check(math.abs(H.timeScale - 0.25) < 0.01, string.format("default preset x0.25 reached (%.3f)", H.timeScale))
T.check(H.post.saturation[1] < 0.8 and H.post.colorbalance[3] > 1.1, "blue tint and desaturation applied")
T.check(callsOf("SetMusicLowPass") > 10, "music low-pass while slowed")
T.check(callsOf("UiSoundLoop") > 10, "heartbeat loop")
T.check(cli().energy < 1, "energy drains")

-- release: ramp out and restore
T.release("h"); T.frames(1)
T.frames(40)
T.check(H.timeScale == 1, "back to normal speed")
T.check(T.soundsPlayed("exit.ogg") == 1, "exit whoosh")
T.check(math.abs(H.post.saturation[1] - 1) < 1e-6 and math.abs(H.post.colorbalance[3] - 1) < 1e-6, "post-processing restored")

-- J cycles the preset to x0.1
T.press("j"); T.frames(1)
T.check(cli().preset == 3, "J switches to x0.1")
T.press("h"); T.frames(1); hold("h", 40)
T.check(math.abs(H.timeScale - 0.1) < 0.01, "x0.1 reached")
T.release("h"); T.frames(40)

-- energy runs out after ~8 s, lockout, recharge
local e0 = cli().energy
T.press("h"); T.frames(1)
local f = T.runUntil(function() return cli().lockout end, 900, nil)
T.check(f ~= nil, "energy runs out (" .. tostring(f) .. " frames)")
T.check(T.soundsPlayed("empty.ogg") == 1, "empty sound")
hold("h", 40)
T.check(H.timeScale == 1, "no slow motion while locked out")
T.check(T.hasText("Recharging"), "HUD says recharging")
T.release("h")
T.runUntil(function() return not cli().lockout end, 600)
T.check(not cli().lockout and cli().energy >= 0.3, "lockout ends after recharging to 30%")
T.runUntil(function() return cli().energy >= 1 end, 1200)
T.check(cli().energy >= 1, "energy refills")

-- toggle mode
H.reg["savegame.mod.toggle"] = true
T.press("h"); T.frames(1); T.release("h"); T.frames(40)
T.check(H.timeScale < 0.5, "toggle: stays slowed after releasing the key")
T.press("h"); T.frames(1); T.release("h"); T.frames(40)
T.check(H.timeScale == 1, "toggle: second press ends it")
H.reg["savegame.mod.toggle"] = false

-- energy off
H.reg["savegame.mod.energy"] = false
T.press("h"); T.frames(1); hold("h", 1000)
T.check(H.timeScale < 0.5 and not cli().lockout, "unlimited when the meter is off")
T.release("h"); T.frames(40)
H.reg["savegame.mod.energy"] = true

-- other key
H.reg["savegame.mod.key"] = "mmb"
T.press("h"); T.frames(1); hold("h", 20)
T.check(H.timeScale == 1, "H does nothing when the key is changed")
T.release("h")
T.press("mmb"); T.frames(1); hold("mmb", 20)
T.check(H.timeScale < 1, "middle mouse works when selected")
T.release("mmb"); T.frames(40)
H.reg["savegame.mod.key"] = "h"

-- walking compensation
H.reg["savegame.mod.walk"] = true
T.press("h"); T.frames(1); hold("h", 40)
T.check((H.P(1).walkSpeed or 7) > 20, string.format("walking speed boosted (%.1f)", H.P(1).walkSpeed or 7))
T.release("h"); T.frames(60)
T.check(H.P(1).walkSpeed == 7, "walking speed restored")
H.reg["savegame.mod.walk"] = false

-- variable frame rate: ramp uses real time from GetTime
T.press("h"); T.frames(1, 1 / 30); for i = 1, 12 do T.hold("h"); T.frames(1, 1 / 30) end
T.check(math.abs(H.timeScale - 0.1) < 0.02, "ramp completes at 30 fps")
T.release("h"); T.frames(30, 1 / 30)

-- Russian hint
H.reg["options.language"] = 7
cli().hintT = 5
T.frames(1)
T.check(T.hasText("Удерживайте H"), "hint in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Time Slow"), "options: title")
H.uiClicks["H"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.key"] == "y", "options: key H -> Y")
H.uiClicks["Hold"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.toggle"] == true, "options: toggle mode")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.key"] == "h" and H.reg["savegame.mod.toggle"] == false, "options: reset")
