#version 2
-- Harness self-test mod: the client touches a server-spawned body (must fail)
-- and its own tool body (allowed).
#include "script/include/player.lua"

function server.init()
	RegisterTool("selftest", "Self test", "MOD/tool.vox")
	shared.body = 0
end

function server.tick(dt)
	for p in PlayersAdded() do SetToolEnabled("selftest", true, p) end
	if shared.body == 0 then
		local ents = Spawn("<body dynamic='true'><voxbox size='2 2 2'/></body>", Transform(Vec(0, 2, 0)))
		shared.body = ents[1]
		shared.shape = ents[2]
	end
end

function client.tick(dt)
	client.reached = false
	if GetBool("selftest.touch") and shared.body ~= 0 then
		local shapes = GetBodyShapes(shared.body)       -- reading is fine
		SetShapeEmissiveScale(shapes[1], 2)              -- mutating a server entity: error
	end
	client.reached = true
	local tb = GetToolBody()
	if tb ~= 0 then
		local s = GetBodyShapes(tb)
		for i = 1, #s do SetShapeEmissiveScale(s[i], 1) end   -- tool body is client-local: allowed
	end
end
