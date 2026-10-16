-- Cone limit law (independent review 16.10.2026). The Workshop text says "up to 4 dead cones are kept".
-- Placing the 5th volcano deleted ALL four kept cones (28 layer bodies) instead of only the oldest one.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function srv() return T.env().server end
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -20
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("volcano"); T.frames(1)
local function validCones()
	local n = 0
	for _, b in ipairs(srv().cones) do if H.W.IsHandleValid(b) then n = n + 1 end end
	return n
end
local bodiesPerVolcano = {}
for k = 1, 5 do
	H.P(1).yaw = (k - 1) * 72      -- aim in a different direction each time
	T.press("usetool"); T.frames(2)
	T.runUntil(function() return sh().v.phase == "rumble" end, 900)
	T.press("grab"); T.frames(2)
	T.runUntil(function() return sh().v.phase == "idle" end, 3000)
	local alive = 0
	for h, b in pairs(H.bodies) do if b.tags and b.tags.volcano then alive = alive + 1 end end
	print(string.format("after volcano %d: server.cones valid=%d, list=%d, volcano-tagged bodies in world=%d", k, validCones(), #srv().cones, alive))
	bodiesPerVolcano[k] = validCones()
end
T.check(bodiesPerVolcano[5] >= 4 * 7, "after the 5th volcano the previous dead cones are kept (valid layer bodies: " .. bodiesPerVolcano[5] .. ")")
T.check(bodiesPerVolcano[5] <= 4 * 7, "and not more than 4 cones stay (valid layer bodies: " .. bodiesPerVolcano[5] .. ")")
T.check(not T.hasText("Cones removed"), "placing a volcano does not say the cones were removed")
