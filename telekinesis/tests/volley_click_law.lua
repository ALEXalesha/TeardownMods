-- Telekinesis volley law. Independent review 16.10.2026: a second LMB click while a volley was
-- still being released started a charge with nothing held; on release it "threw" an empty list,
-- which replaced the running volley, so the rest of the held objects were never thrown. Now a
-- click with nothing held does not charge, and a throw with nothing held does nothing.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function me() return sh().tk[1] end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -15
H.reg["savegame.mod.maxbodies"] = 20
math.randomseed(4)
for i = 1, 20 do H.addBody { pos = V(-1.5 + math.random() * 3, 0.25, -6.5 + math.random() * 2), mass = 20 } end
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("telekinesis")
T.frames(1)
T.press("usetool"); T.frames(1); T.release("usetool"); T.frames(60)
local held = {}
for i, b in ipairs(me().held) do held[i] = b end
T.check(#held == 20, "holding 20 objects")

-- throw, then click again while the volley is still being released
T.press("usetool"); for i = 1, 20 do T.hold("usetool"); T.frames(1) end
T.release("usetool"); T.frames(1)
T.frames(3)
T.check(srv().p[1].volley ~= nil, "the volley is still running")
local throws = T.soundsPlayed("throw.ogg")
T.press("usetool"); T.frames(1)
T.check(not srv().p[1].charging, "a click with nothing held does not charge")
T.release("usetool"); T.frames(1)
T.frames(60)
T.check(srv().p[1].volley == nil, "the volley finished")
T.check(T.soundsPlayed("throw.ogg") == throws, "no second (empty) throw")
local thrown = 0
for _, b in ipairs(held) do if H.bodies[b].pos[3] < -12 then thrown = thrown + 1 end end
T.check(thrown >= 18, "the click does not cut the volley short: " .. thrown .. " of " .. #held .. " thrown")
-- a throw call with nothing held does nothing
local s = srv().p[1]
s.volley = { list = { { body = held[1], mass = 20 } }, i = 1, t = 1, speed = 10 }
srv().throw(1, s, T.env().readSettings())
T.check(s.volley and #s.volley.list == 1, "throw with nothing held keeps the running volley")
