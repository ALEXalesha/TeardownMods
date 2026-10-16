-- Tremors option law (independent review 16.10.2026). The option "Tremors and wind" Off stopped only the
-- physical tremors; the wind sound, the camera shake and the lifted dust of the approach went on.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -10
for i = 1, 10 do H.addBody { pos = V(-5 + i, 0.25, -6), mass = 20 } end
H.reg["savegame.mod.tremors"] = false
H.reg["savegame.mod.duration"] = 60
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("fallingmoon"); T.frames(1)
local orig = H.W.UiSoundLoop
local wind = 0
H.W.UiSoundLoop = function(path, ...) if tostring(path):find("wind") then wind = wind + 1 end return orig(path, ...) end
local shakes = 0
T.frameHooks[#T.frameHooks + 1] = function() if H.cameraShake > 0.02 and sh().m.phase == "approach" then shakes = shakes + 1 end end
T.press("usetool"); T.frames(2)
T.check(sh().m.phase == "approach", "moon called")
local imp0, part0 = H.calls.ApplyBodyImpulse or 0, H.particles
T.runUntil(function() return sh().m.prog > 0.97 end, 4000)
local imp = (H.calls.ApplyBodyImpulse or 0) - imp0
print(string.format("tremors=off: ApplyBodyImpulse=%d, wind.ogg UiSoundLoop frames=%d, camera-shake frames=%d, particles=%d", imp, wind, shakes, H.particles - part0))
T.check(imp == 0, "no body tremors with the option off")
T.check(wind == 0, "no wind sound with 'Tremors and wind' off")
T.check(shakes == 0, "no tremor camera shake with 'Tremors and wind' off")
