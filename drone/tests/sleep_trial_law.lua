-- Drone law from Alexey's in-game check of 16.10 23:13 (code 50eb64c / e0f840d): "the drone broke
-- again and stopped reacting to the keys". In the game the drone flies on its kinematic fallback (the
-- engine did not follow its velocity, in-game 03.10, fallback_law). Until 50eb64c it stayed kinematic;
-- since 50eb64c it tries every 3 s whether velocity flight works again: SetBodyDynamic(true) plus a test
-- velocity, and if GetBodyVelocity then reads the test velocity, it goes back to velocity flight.
-- A body that was made static is out of the simulation (script_defs, IsBodyActive: "only dynamic bodies
-- can be active") and making it dynamic does not put it back: the test velocity is just stored, the
-- check reads it back and passes, and from then on the drone is in velocity mode on a body that is not
-- simulated - it does not move, does not sink (so the fallback never comes back), every key is ignored.
-- The stand models that (H.sleepModel, velocityWakes = false).
-- The law: in that world the drone keeps flying for 30 s - every 2 s burst of W / S moves it 8 m,
-- Space climbs, with nothing pressed it holds its place.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function me() return sh().d[1] end
local function copy(v) return { v[1], v[2], v[3] } end

H.addPlayer(1, V(0, 0, 0))
H.sleepModel = { velocityWakes = false }
H.ignoreBodyVelocity = true          -- the in-game failure that sends it to the kinematic fallback
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("drone")
T.frames(1)
T.press("usetool"); T.frames(3)
local body = me().body
T.check(body ~= 0 and me().piloting, "drone launched")
T.runUntil(function() return T.env().server.d[1] and T.env().server.d[1].mode == "kinematic" end, 120)
T.check(T.env().server.d[1].mode == "kinematic", "it sinks and goes over to kinematic flight, as in the game")
-- from now on the engine would follow a velocity again, but only on a simulated body
H.ignoreBodyVelocity = false

local function burst(key, n)
	T.press(key)
	for i = 1, n do T.hold(key); T.frames(1) end
	T.release(key); T.frames(1)
end
local bad = {}
for k = 1, 8 do
	-- W and S in turn, so it stays within the signal range
	local key = (k % 2 == 1) and "up" or "down"
	local p0 = copy(H.bodies[body].pos)
	burst(key, 120)
	local p1 = copy(H.bodies[body].pos)
	local fwd = (p0[3] - p1[3]) * ((key == "up") and 1 or -1)
	if fwd < 8 then bad[#bad + 1] = string.format("burst %d at %.0f s: %s moved %.1f m (mode %s)", k, H.time, key == "up" and "W" or "S", fwd, tostring(T.env().server.d[1].mode)) end
	T.frames(60)
	local p2 = copy(H.bodies[body].pos)
	T.frames(60)
	local drift = math.sqrt((H.bodies[body].pos[1] - p2[1]) ^ 2 + (H.bodies[body].pos[2] - p2[2]) ^ 2 + (H.bodies[body].pos[3] - p2[3]) ^ 2)
	if drift > 0.5 then bad[#bad + 1] = string.format("burst %d: drifted %.2f m with nothing pressed", k, drift) end
end
T.check(#bad == 0, "every 2 s of W (or S) over 30 s flies at least 8 m forward and it holds still between: " .. (#bad == 0 and "ok" or table.concat(bad, "; ")))
local y0 = H.bodies[body].pos[2]
burst("jump", 60)
T.frames(20)
T.check(H.bodies[body].pos[2] - y0 > 2, string.format("Space still climbs at the end (%.2f m)", H.bodies[body].pos[2] - y0))
T.check(me().body == body and me().piloting, "same drone, still piloted, no crash")
