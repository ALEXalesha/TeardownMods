-- Tsunami lift law (in-game report 04.10.2026: "why does the tsunami toss everything up instead of
-- just destroying it", screenshot of debris flying high above the water).
-- Debris of every size and material in the wave's path: the water drags it along the flow but
-- never throws it into the air. No body rises more than 1.5 m above the local water surface and
-- none goes up faster than 4 m/s; heavy concrete pieces stay near the ground (they do not float).
local function V(x, y, z) return { x, y, z } end
local function sh() return T.sharedOf() end

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
local debris = {}
local kinds = {
	{ mass = 3, half = V(0.15, 0.15, 0.15), mat = "wood" },        -- splinters
	{ mass = 25, half = V(0.4, 0.2, 0.4), mat = "wood" },          -- planks and crates
	{ mass = 120, half = V(0.3, 0.3, 0.3), mat = "masonry" },      -- brick chunks
	{ mass = 900, half = V(0.5, 0.4, 0.5), mat = "concrete" },     -- concrete blocks
}
for i = 0, 39 do
	local k = kinds[(i % #kinds) + 1]
	local b = H.addBody { pos = V(-20 + (i % 10) * 4, k.half[2], -20 - math.floor(i / 10) * 12), mass = k.mass, half = k.half, material = k.mat }
	debris[#debris + 1] = { h = b, kind = k }
end

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("tsunami")
T.frames(1)
T.press("usetool"); T.frames(2)

local worstAbove, worstUp, worstConcrete = -1e9, -1e9, -1e9
T.frameHooks[#T.frameHooks + 1] = function()
	local w = T.env().server.w
	if not w or w.phase == "warning" then return end
	for _, d in ipairs(debris) do
		local b = H.bodies[d.h]
		if b and b.valid then
			local a = (b.pos[1] - w.ox) * w.dx + (b.pos[3] - w.oz) * w.dz
			local hgt = T.env().waterAt(w, w.s - a)
			if hgt > 0 then
				local surface = w.oy + hgt
				local bottom = b.pos[2] - b.half[2]
				worstAbove = math.max(worstAbove, bottom - surface)
				worstUp = math.max(worstUp, b.vel[2])
				if d.kind.mass >= 900 then worstConcrete = math.max(worstConcrete, bottom) end
			end
		end
	end
end
T.runUntil(function() return sh().ts.phase == "idle" end, 6000)

T.check(worstAbove <= 1.5, string.format("debris never thrown above the water (worst %.1f m above the surface, need <= 1.5)", worstAbove))
T.check(worstUp <= 4, string.format("no debris shoots up (worst upward speed %.1f m/s, need <= 4)", worstUp))
T.check(worstConcrete <= 2, string.format("concrete blocks do not float up (highest bottom %.1f m, need <= 2)", worstConcrete))
