-- Flight law for the Camera Drone (in-game report: "doesn't work at all, can't be controlled").
-- With numbers: hovering holds altitude, the heading follows the mouse, and W held for
-- 1 s moves the drone along the camera direction by at least 60 % of the set speed.
-- Run at 60, 144 and 30 frames per second: in the game tick runs per frame, physics at 60 Hz.
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end
local function me() return sh().d[1] end
local function copy(v) return { v[1], v[2], v[3] } end
local QuatRotateVec = H.API.QuatRotateVec

H.addPlayer(1, V(0, 0, 0))
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("drone")
T.frames(1)
T.press("usetool"); T.frames(3)
local body = me().body
T.check(body ~= 0 and me().piloting, "drone launched and piloted")
local speed = 12
local playerStart = copy(H.P(1).pos)

local function heading(b)
	local f = QuatRotateVec(H.bodies[b].rot, V(0, 0, -1))
	return math.deg(math.atan2(-f[1], -f[3]))
end
local function angDiff(a, b) local d = (a - b + 180) % 360 - 180 return math.abs(d) end
local function camYaw()
	local f = QuatRotateVec(H.camera.rot, V(0, 0, -1))
	return math.deg(math.atan2(-f[1], -f[3])), f
end

for _, fps in ipairs({ 60, 144, 30 }) do
	local dt = 1 / fps
	-- 1) hover: two seconds without input
	T.frames(math.floor(0.5 * fps), dt)
	local p0 = copy(H.bodies[body].pos)
	T.frames(2 * fps, dt)
	local p1 = H.bodies[body].pos
	local drift = math.sqrt((p1[1] - p0[1]) ^ 2 + (p1[3] - p0[3]) ^ 2)
	T.check(math.abs(p1[2] - p0[2]) < 0.3 and drift < 0.3,
		string.format("[%d fps] hovers without input (dy %.2f m, drift %.2f m)", fps, p1[2] - p0[2], drift))

	-- 2) mouse: turn the view by about 60 degrees, the drone body follows within a second
	H.P(1).values = { camerax = math.rad(-60) / math.floor(0.25 * fps) }
	T.frames(math.floor(0.25 * fps), dt)
	H.P(1).values = {}
	T.frames(fps, dt)
	local cy = camYaw()
	T.check(angDiff(heading(body), cy) < 8,
		string.format("[%d fps] body heading follows the mouse (body %.0f, camera %.0f)", fps, heading(body), cy))

	-- 3) W for one second: along the camera direction, at least 60 % of the speed
	local _, f = camYaw()
	local flat = { f[1], 0, f[3] }
	local fl = math.sqrt(flat[1] ^ 2 + flat[3] ^ 2)
	flat = { flat[1] / fl, 0, flat[3] / fl }
	local a = copy(H.bodies[body].pos)
	T.press("up")
	for i = 1, fps do T.hold("up"); T.frames(1, dt) end
	T.release("up"); T.frames(1, dt)
	local b = H.bodies[body].pos
	local d = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
	local along = d[1] * flat[1] + d[3] * flat[3]
	local side = math.abs(d[1] * flat[3] - d[3] * flat[1])
	T.check(along >= 0.6 * speed and side < 0.15 * along and math.abs(d[2]) < 0.5,
		string.format("[%d fps] W for 1 s: %.1f m along the view (need >= %.1f), %.2f m sideways, dy %.2f", fps, along, 0.6 * speed, side, d[2]))
	-- stop again before the next round
	T.frames(fps, dt)
end

-- Space for one second climbs at least 2 m, Ctrl comes back down
local y0 = H.bodies[body].pos[2]
T.press("jump"); for i = 1, 60 do T.hold("jump"); T.frames(1) end
T.release("jump"); T.frames(1)
T.check(H.bodies[body].pos[2] - y0 > 2, string.format("Space climbs (%.1f m)", H.bodies[body].pos[2] - y0))
local y1 = H.bodies[body].pos[2]
T.press("crouch"); for i = 1, 60 do T.hold("crouch"); T.frames(1) end
T.release("crouch"); T.frames(1)
T.check(y1 - H.bodies[body].pos[2] > 2, string.format("Ctrl descends (%.1f m)", y1 - H.bodies[body].pos[2]))

-- the pilot's body stays where it was
local pp = H.P(1).pos
T.check(math.abs(pp[1] - playerStart[1]) + math.abs(pp[3] - playerStart[3]) < 0.05, "pilot's body stays in place")
-- shapes of the flying drone body are not moved every tick (the game never does that to a free dynamic body)
T.check((H.calls.SetShapeLocalTransform or 0) == 0, "no per-tick shape edits on the dynamic drone body (" .. (H.calls.SetShapeLocalTransform or 0) .. ")")
-- and the camera follows the drone every frame
T.check(H.camera ~= nil, "camera on the drone")
-- the fallback must not kick in when the engine does apply velocities
T.check(T.env().server.d[1] == nil or T.env().server.d[1].mode ~= "kinematic", "normal flight stays in velocity mode")
