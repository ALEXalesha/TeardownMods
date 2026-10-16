-- Early call-off law (independent review 16.10.2026). RMB during the warning, before any water came, put the
-- wave straight into its backwash: the level water jumped to full storm roughness and the "water runs back"
-- sound and hint played for 9 s.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
local sea = H.addEntity("water", { wave = 0.3, ripple = 0.4, motion = 0.2, foam = 0.1, depth = 5 })
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("tsunami"); T.frames(1)
T.press("usetool"); T.frames(60)
local before = H.entities[sea].props.wave
T.press("grab"); T.frames(40)
local after = H.entities[sea].props.wave
local l0 = T.loopFrames("recede.ogg")
T.frames(120)
print(string.format("sea wave prop: %.2f before RMB (1 s into warning), %.2f 0.7 s after RMB (orig 0.30, storm 1.0); recede.ogg loop frames in next 2 s: %d; hint '%s'",
	before, after, T.loopFrames("recede.ogg") - l0, T.hasText("The water runs back") and "The water runs back" or "-"))
T.check(after <= before + 0.05, "calling the wave off early does not make the level water stormier")
T.check(T.loopFrames("recede.ogg") - l0 == 0, "no 'water runs back' sound when no water ever came")
