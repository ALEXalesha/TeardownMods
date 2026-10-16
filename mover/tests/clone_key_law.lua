-- Clone key law (16.10.2026). Clone was G, and G is Gravity Change's key, which works with any tool in
-- the hands: with both mods on, G cloned the object and changed the gravity. Clone is P now, and the
-- controls panel shows P. Every key of every mod: _shared/tdlib/keymap.py.
local function V(x, y, z) return { x, y, z } end
local function callsOf(n) return H.calls[n] or 0 end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -16
local crate = H.addBody { pos = V(0, 0.25, -5), mass = 30 }
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("mover")
T.frames(2)
T.check(T.cenv().client.aimBody == crate, "crate aimed")
local texts = table.concat(T.texts(), "|")
T.check(texts:find("|P|clone", 1, true) ~= nil, "controls panel: P - clone")
T.check(texts:find("|G|", 1, true) == nil, "controls panel has no G")
local c0 = callsOf("CreateShape")
T.press("g"); T.frames(2)
T.check(callsOf("CreateShape") == c0, "G does not clone")
T.press("p"); T.frames(2)
T.check(callsOf("CreateShape") > c0, "P clones the aimed crate")
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Cloning (P)"), "options name the clone key P")
