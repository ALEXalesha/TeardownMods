-- Self-test of the harness authority model.
H.addPlayer(1, { 0, 0, 0 })
T.load("main.lua", "main")
T.init("main")
T.select("selftest")
T.frames(3)
T.check(H.authorityErrors == 0, "client reading server entities and writing its own tool body is allowed")
T.check(T.cenv().client.reached == true, "client tick runs to the end")
H.reg["selftest.touch"] = true
T.frames(2)
T.check(H.authorityErrors == 2, "client SetShapeEmissiveScale on a server-spawned shape is an authority error (" .. H.authorityErrors .. ")")
T.check(T.cenv().client.reached == false, "the error aborts the rest of the client tick")
-- every name in the mutating list exists in script_defs.lua
local missing = {}
for name in pairs(H.MUTATING) do if not H.SPEC[name] then missing[#missing + 1] = name end end
table.sort(missing)
T.check(#missing == 0, "all mutating API names exist in script_defs (missing: " .. table.concat(missing, ", ") .. ")")
local n = 0
for _ in pairs(H.MUTATING) do n = n + 1 end
T.check(n >= 40, "mutating list covers " .. n .. " functions")
-- the expected errors are part of this self-test, clear them so the run reports OK
H.errors = {}
-- server-only functions
T.check(H.SERVER_ONLY.SetTimeScale == true, "SetTimeScale is listed as server-only")
local before = H.serverOnlyErrors
H.ctx = "client"
H.W.SetTimeScale(0.5)
H.ctx = "scenario"
T.check(H.serverOnlyErrors == before + 1 and H.timeScale == 1, "client SetTimeScale is reported and has no effect")
H.ctx = "server"
H.W.SetTimeScale(0.5)
H.ctx = "scenario"
T.check(H.timeScale == 0.5, "server SetTimeScale works")
H.errors = {}
