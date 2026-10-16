-- Key setting law (16.10.2026). J (speed) was fixed in the code and was also one of Gravity Change's
-- key choices; T (a slow-motion key choice) is Mover's freeze. Now the speed key is a setting (J or I),
-- T is not offered, and the hint shows both keys from the settings. Every key of every mod:
-- _shared/tdlib/keymap.py.
local function V(x, y, z) return { x, y, z } end
local function cli() return T.cenv().client end
local function hold(key, n) for i = 1, n do T.hold(key); T.frames(1) end end
local function tap(k) T.press(k); T.frames(1); T.release(k); T.frames(1) end

H.addPlayer(1, V(0, 0, 0))
H.reg["savegame.mod.key"] = "y"
H.reg["savegame.mod.speedkey"] = "i"
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(T.hasText("Hold Y: slow motion, I: change speed"), "hint shows both chosen keys (Y, I)")
local p0 = cli().preset
tap("j")
T.check(cli().preset == p0, "J does nothing when the speed key is I")
tap("i")
T.check(cli().preset ~= p0, "I changes the speed")
T.press("y"); T.frames(1); hold("y", 40)
T.check(H.timeScale < 0.99, "Y slows the world")
T.release("y"); T.frames(60)

-- toggle mode and Russian hint use the same keys
H.reg["savegame.mod.toggle"] = true
H.reg["options.language"] = 7
cli().hintT = 3
T.frames(1)
T.check(T.hasText("Нажмите Y: замедление, I: сменить скорость"), "Russian toggle hint shows Y and I")
H.reg["options.language"] = 0
H.reg["savegame.mod.toggle"] = false

-- an old T setting falls back to H (T is Mover's freeze key)
H.reg["savegame.mod.key"] = "t"
H.reg["savegame.mod.speedkey"] = "j"
cli().hintT = 3
T.frames(1)
T.check(T.hasText("Hold H: slow motion, J: change speed"), "old T setting falls back to H")
T.press("t"); T.frames(1); hold("t", 20)
T.check(H.timeScale == 1, "T does not slow the world any more")
T.release("t"); T.frames(2)

-- the options screen: speed key J <-> I, slow key H -> Y -> middle mouse -> H (no T)
T.loadOptions("options.lua")
H.reg["savegame.mod.key"] = "y"
H.uiClicks["Y"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.key"] == "mmb", "options: Y -> middle mouse (no T between)")
H.uiClicks["J"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.speedkey"] == "i", "options: speed key J -> I")
T.check(T.hasText("Speed key"), "options: speed key row")
