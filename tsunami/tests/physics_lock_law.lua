-- Physics lock (in-game 10.10: "the physics is all fine", only the look of the flood behind the
-- crest may change). The server half of main.lua - waterAt (height and flow behind the front), the
-- current (drag, buoyancy by density, damped lift), tearing - must stay byte for byte as in 775d30a,
-- the build Alexey approved. A deliberate physics change updates the numbers below together with
-- lift_law.lua and destruction_law.lua and a new in-game test.
-- 16.10.2026: re-locked after the review fix in server.tick (RMB during the warning stops instead of
-- starting the backwash); waterAt, the current and tearing are unchanged.
local LOCK_LEN, LOCK_HASH = 9684, 1768213176   -- 775d30a + early call-off

local src = H.readFile(H.modDir .. "/main.lua"):gsub("\r\n", "\n")
local a = src:find("function waterAt(", 1, true)
local b = src:find("\n-- CLIENT\n", 1, true)
T.check(a ~= nil and b ~= nil and b > a, "server section found (from waterAt to the CLIENT banner)")
local part = src:sub(a or 1, b or #src)
local h = 5381
for i = 1, #part do h = (h * 33 + part:byte(i)) % 4294967296 end
print(string.format("physics lock: %d bytes, hash %d", #part, h))
T.check(#part == LOCK_LEN and h == LOCK_HASH, string.format("server physics unchanged since 775d30a (%d bytes, hash %d; locked %d, %d)", #part, h, LOCK_LEN, LOCK_HASH))

-- the client part only draws: nothing the client does reaches bodies, players or the level
H.addPlayer(1, { 0, 0, 0 })
H.P(1).pitch = 0
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("tsunami")
T.frames(1)
T.press("usetool")
T.runUntil(function() return T.sharedOf().ts.phase == "idle" end, 6000)
local cs = H.sideCalls.client
local bad = {}
for _, n in ipairs({ "ApplyBodyImpulse", "SetBodyVelocity", "SetPlayerVelocity", "MakeHole", "SetProperty", "Spawn", "Delete" }) do
	if (cs[n] or 0) > 0 then bad[#bad + 1] = n end
end
T.check(#bad == 0, "the client never touches physics (" .. (#bad == 0 and "none" or table.concat(bad, ", ")) .. ")")
