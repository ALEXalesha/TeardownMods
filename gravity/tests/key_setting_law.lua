-- Key setting law (16.10.2026). With Time Slow on, J did two things (Gravity's key option and Time
-- Slow's speed key): J is no longer offered here. The key is the setting, and the hint on the screen
-- shows the key from the setting. Every key of every mod: _shared/tdlib/keymap.py.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function tap(k) T.press(k); T.frames(1); T.release(k); T.frames(1) end

H.addPlayer(1, V(0, 0, 0))
H.reg["savegame.mod.key"] = "k"
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(T.hasText("K: next gravity") and not T.hasText("G: next gravity"), "hint shows the chosen key K")
tap("g")
T.check(sh().g.preset == 1, "G does nothing when the key is K")
tap("k")
T.check(sh().g.preset == 2, "K switches to the Moon")
T.frames(120)

-- a setting saved by an older version (J) falls back to the default G, and the hint says so
H.reg["savegame.mod.key"] = "j"
T.cenv().client.showT = 3
T.frames(1)
T.check(T.hasText("G: next gravity"), "an old J setting falls back to G (hint shows G)")
tap("j")
T.check(sh().g.preset == 2, "J is not a gravity key any more (it is Time Slow's speed key)")
tap("g")
T.check(sh().g.preset == 3, "G works after the fallback")

-- Russian hint with the chosen key
H.reg["savegame.mod.key"] = "k"
H.reg["options.language"] = 7
T.cenv().client.showT = 3
T.frames(1)
T.check(T.hasText("K: следующая"), "Russian hint shows K")
H.reg["options.language"] = 0

-- the options screen offers G and K only
T.loadOptions("options.lua")
H.reg["savegame.mod.key"] = "g"
H.uiClicks["G"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.key"] == "k", "options: G -> K")
H.uiClicks["K"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.key"] == "g", "options: K -> G (no J between them)")
