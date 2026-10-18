-- Put-away law (18.10, Alexey: "removing all of them should be on some other key"). Near your own catapult the
-- wheel and 1-9 belong to the catapult, and the way to get the other tools back was R - which removed every
-- catapult. Now:
--   * R puts the catapult away: the tool held before it comes back (the sledgehammer if there was none or it
--     is not enabled), and every catapult, its load and its settings stay;
--   * R with another tool in hand does nothing to the catapults;
--   * Delete removes all catapults; Delete with another tool in hand does nothing;
--   * the hints say so: "R: other tools (the catapults stay)", "Delete: remove all catapults".
local function V(x, y, z) return { x, y, z } end
local function srv() return T.env().server end
local A = H.API

H.spawnModel = { pivot = "center", physics = true }
H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = 0
H.reg["game.tool.shotgun.enabled"] = true
T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.select("shotgun"); T.frames(2)
T.select("catapult"); T.frames(1)
T.press("usetool"); T.frames(60)
T.check(#srv().cats == 1, "a catapult is placed")
local c = srv().cats[1]
T.check(T.hasText("R: other tools (the catapults stay)") and T.hasText("Delete: remove all catapults"), "the hint names R and Delete")
local frame, arm = c.frame, c.arm
T.press("r"); T.frames(3)
T.check(H.P(1).tool == "shotgun", "R: back to the tool held before the catapult (" .. tostring(H.P(1).tool) .. ")")
T.check(#srv().cats == 1 and A.IsHandleValid(frame) and A.IsHandleValid(arm), "the catapult stays")
T.press("r"); T.frames(2)
T.press("delete"); T.frames(2)
T.check(#srv().cats == 1 and A.IsHandleValid(frame), "R and Delete with another tool in hand do nothing to it")
-- a tool that is not enabled any more: the sledgehammer
H.reg["game.tool.shotgun.enabled"] = false
T.select("catapult"); T.frames(2)
T.press("r"); T.frames(3)
T.check(H.P(1).tool == "sledge", "R with no usable previous tool: the sledgehammer (" .. tostring(H.P(1).tool) .. ")")
T.select("catapult"); T.frames(2)
T.press("delete"); T.frames(3)
T.check(#srv().cats == 0 and not A.IsHandleValid(frame) and not A.IsHandleValid(arm), "Delete removes all catapults")
T.check(H.P(1).tool == "catapult", "and keeps the catapult in hand")
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("Delete: убрать все"), "the hint in Russian")
