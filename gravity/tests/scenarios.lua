-- Harness scenarios for Gravity Change.
local function V(x, y, z) return { x, y, z } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function callsOf(n) return H.calls[n] or 0 end
local function tapG() T.press("g"); T.frames(1); T.release("g"); T.frames(1) end

T.budget("SetBodyActive", 40)
T.budget("QueryAabbBodies", 2)
T.budget("SetGravity", 1)

H.addPlayer(1, V(0, 0, 0))
local sleepers = {}
for i = 1, 60 do
	sleepers[i] = H.addBody { pos = V((i % 10) - 5, 0.25, -5 - math.floor(i / 10)), mass = 10 }
	H.bodies[sleepers[i]].active = false
end
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(T.hasText("next gravity"), "hint at start")
T.check(math.abs(H.gravity[2] + 10) < 1e-6, "starts with Earth gravity")

-- Moon with a smooth transition
tapG()
T.check(sh().g.preset == 2, "G switches to Moon")
T.frames(30)
T.check(H.gravity[2] < -1.7 and H.gravity[2] > -9.9, string.format("transition in progress (%.2f)", H.gravity[2]))
T.frames(80)
T.check(math.abs(H.gravity[2] + 1.62) < 0.01, "Moon gravity reached (-1.62)")
T.check(T.soundsPlayed("lighter.ogg") == 1, "lighter sound")
T.check(T.hasText("Moon") and T.hasText("0.16 g"), "indicator shows Moon 0.16 g")
T.check((H.sideCalls.client.SetGravity or 0) == 0 and (H.sideCalls.server.SetGravity or 0) > 0, "SetGravity only from server code")

-- sleeping bodies get woken in a budget
local awake = 0
for i = 1, 60 do if H.bodies[sleepers[i]].active then awake = awake + 1 end end
T.check(awake == 60, "resting bodies woken so they react (" .. awake .. " of 60)")

-- Mars, zero-G (floating, thrusters, upright orientation)
tapG(); T.frames(120)
T.check(math.abs(H.gravity[2] + 3.71) < 0.01, "Mars gravity")
tapG(); T.frames(120)
T.check(len(H.gravity) < 0.01, "zero-G")
T.check(callsOf("SetPlayerOrientation") > 0, "player kept upright in zero-G")
local y0 = H.P(1).pos[2]
T.press("jump"); for i = 1, 60 do T.hold("jump"); T.frames(1) end; T.release("jump")
T.check(H.P(1).pos[2] > y0 + 0.5, "Space thrusts the player up in zero-G")
T.check(callsOf("UiSoundLoop") > 0, "zero-G hum")
T.check(H.particles > 0, "floating dust in low gravity")

-- reverse: things fall up
for i = 1, 10 do H.bodies[sleepers[i]].active = false end
tapG(); T.frames(120)
T.check(H.gravity[2] > 3.9, "reverse gravity points up")
T.frames(60)
T.check(H.bodies[sleepers[1]].pos[2] > 1, "objects fall up")

-- sideways: towards the player's right when chosen (yaw 0 -> +x)
tapG(); T.frames(120)
T.check(H.gravity[1] > 5.9 and math.abs(H.gravity[2]) < 0.01, string.format("sideways gravity to the right (%.1f, %.1f, %.1f)", H.gravity[1], H.gravity[2], H.gravity[3]))
T.check(T.soundsPlayed("heavier.ogg") >= 1, "heavier sound")

-- hold G: back to Earth
T.press("g"); for i = 1, 60 do T.hold("g"); T.frames(1) end; T.release("g"); T.frames(120)
T.check(sh().g.preset == 1 and math.abs(H.gravity[2] + 10) < 0.01, "holding G returns to Earth")

-- auto return
H.reg["savegame.mod.autoreturn"] = 10.0
tapG(); T.frames(120)
T.check(sh().g.preset == 2, "Moon again")
T.frames(600)
T.check(sh().g.preset == 1, "automatic return to Earth after 10 s")
T.frames(120)
H.reg["savegame.mod.autoreturn"] = 0.0

-- instant transition option
H.reg["savegame.mod.trans"] = 0.0
tapG(); T.frames(1)
T.check(math.abs(H.gravity[2] + 1.62) < 0.01, "transition 0 s switches at once")
H.reg["savegame.mod.trans"] = 1.5

-- Russian indicator
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("Луна"), "indicator in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Gravity Change"), "options: title")
H.uiClicks["Never"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.autoreturn"] == 10, "options: auto return 10 s")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.autoreturn"] == 0 and H.reg["savegame.mod.key"] == "g", "options: reset")
