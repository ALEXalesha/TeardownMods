-- Mover frozen-list law. Independent review 16.10.2026: a frozen body that was destroyed (blown
-- up, deleted by another mod) stayed in shared.frozen and frozenCount never went down, so after
-- 64 such bodies nothing could be frozen any more ("Too many frozen objects"). Now invalid handles
-- are pruned every few ticks (and before the limit check) and the count is recounted.
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local function sh() return T.sharedOf() end
local function me() return sh().pl[1] end
local function keys(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -16
local crate = H.addBody { pos = V(0, 0.25, -5), mass = 30 }
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("mover")
T.frames(2)
T.press("t"); T.frames(2)
T.check(sh().frozenCount == 1 and sh().frozen[crate], "T froze the crate")
H.API.Delete(crate)
T.frames(10)
T.check(sh().frozenCount == 0 and keys(sh().frozen) == 0, "a destroyed frozen body frees its slot (frozenCount " .. sh().frozenCount .. ")")

-- 64 frozen bodies destroyed in the same tick, then a fresh one can still be frozen right away
for i = 1, 64 do
	local b = H.addBody { pos = V(20 + i, 0.25, 0), mass = 10 }
	srv().freeze(1, b)
	H.API.Delete(b)
end
local fresh = H.addBody { pos = V(0, 0.25, -5), mass = 30 }
local mn = me().mn
srv().freeze(1, fresh)
T.check(sh().frozen[fresh] and me().mn == mn, "a fresh body freezes although 64 destroyed ones were on the list")
T.frames(10)
T.check(sh().frozenCount == 1 and keys(sh().frozen) == 1, "count and list agree (frozenCount " .. sh().frozenCount .. ")")
-- valid frozen bodies are kept
local kept = H.addBody { pos = V(3, 0.25, -5), mass = 30 }
srv().freeze(1, kept)
T.frames(30)
T.check(sh().frozen[kept] and sh().frozen[fresh] and sh().frozenCount == 2, "valid frozen bodies stay frozen")
