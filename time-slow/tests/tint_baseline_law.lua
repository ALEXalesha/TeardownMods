-- Tint baseline law (independent review 16.10.2026). Slow motion saved the CURRENT saturation as the
-- "original" when it started. Started during another mod's replay, it saved the replay's tinted value and
-- put it back when it ended, after the replay had already restored its own: the picture stayed
-- desaturated. Here the other mod is simulated by writing the post-processing value directly
-- (after this mod, every frame).
local function V(x, y, z) return { x, y, z } end
local function hold(key, n) for i = 1, n do T.hold(key); T.frames(1) end end
H.addPlayer(1, V(0, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(2)
-- another mod (a replay) tints the picture every frame
local other = 0.55
table.insert(T.frameHooks, function() if other then H.post.saturation = { other } end end)
T.frames(10)
T.press("h"); T.frames(1)
hold("h", 40)
T.check(T.cenv().client.active, "slow motion on while the other tint is on")
-- the other mod ends and restores its own baseline once
other = nil
H.post.saturation = { 1 }
hold("h", 20)
T.check(H.post.saturation[1] < 0.8, string.format("slow motion still tints the picture (%.3f)", H.post.saturation[1]))
T.release("h"); T.frames(90)
T.check(not T.cenv().client.active and T.cenv().client.k == 0, "slow motion fully ended")
T.check(math.abs(H.post.saturation[1] - 1) < 0.01, string.format("saturation back to 1 after both effects end (now %.3f)", H.post.saturation[1]))
T.check(math.abs(H.post.colorbalance[3] - 1) < 0.01, string.format("color balance back to 1 (blue %.3f)", H.post.colorbalance[3]))
table.remove(T.frameHooks)
