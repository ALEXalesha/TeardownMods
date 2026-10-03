-- Scenario driver: creates script environments, steps frames, records checks.
T = {}
T.results = {}
T.scripts = {}      -- name -> {version, envs = {host=env} or {server=env, client=env}}
T.budgets = {}
T.budgetFailed = {}
T.accum = 0
T.clientSharedSnapshot = nil

local STD = {
	math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, type = type,
	tostring = tostring, tonumber = tonumber, select = select, unpack = unpack, pcall = pcall,
	xpcall = xpcall, error = error, assert = assert, next = next, rawget = rawget, rawset = rawset,
	rawequal = rawequal, setmetatable = setmetatable, getmetatable = getmetatable, print = function(...) end,
	os = { time = os.time, clock = os.clock, date = os.date }, coroutine = coroutine, _VERSION = _VERSION,
}

local function deepcopy(v, seen)
	if type(v) ~= "table" then return v end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local t = {}
	seen[v] = t
	for k, x in pairs(v) do t[deepcopy(k, seen)] = deepcopy(x, seen) end
	return t
end
T.deepcopy = deepcopy

local function deepequal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b or (a ~= a and b ~= b) end
	for k, v in pairs(a) do if not deepequal(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- shared must contain only syncable data (no functions, no handles to tables with metatables)
local function checkSyncable(v, path, depth)
	depth = depth or 0
	if depth > 8 then H.err("shared nesting too deep at " .. path) return end
	local t = type(v)
	if t == "function" or t == "userdata" or t == "thread" then H.err("shared contains non-syncable " .. t .. " at " .. path) return end
	if t == "table" then
		if getmetatable(v) then H.warn("shared table with metatable at " .. path) end
		for k, x in pairs(v) do
			if type(k) ~= "string" and type(k) ~= "number" then H.err("shared has non string/number key at " .. path) end
			checkSyncable(x, path .. "." .. tostring(k), depth + 1)
		end
	end
end

local function makeEnv(side)
	local env = { server = {}, client = {}, shared = {} }
	env._G = env
	setmetatable(env, { __index = function(t, k)
		local w = H.W[k]
		if w then return w end
		local s = STD[k]
		if s ~= nil then return s end
		if type(k) == "string" and k:match("^[A-Z]") then
			H.unknown[k] = (H.unknown[k] or 0) + 1
			H.err("access to undefined global '" .. k .. "' (not in script_defs and not defined by the mod)")
		end
		return nil
	end })
	env.__H_INCLUDE = function(code, name)
		local f, e = loadstring(code, "@" .. name)
		if not f then H.err("include compile error " .. name .. ": " .. tostring(e)) return end
		setfenv(f, env)
		local ok, e2 = xpcall(f, debug.traceback)
		if not ok then H.err("include runtime error " .. name .. ": " .. tostring(e2)) end
	end
	env.__side = side
	return env
end

local function callIn(env, ctx, path, ...)
	-- path like "server.tick" or "tick"
	local fn
	local a, b = path:match("^(%w+)%.(%w+)$")
	if a then
		local tbl = rawget(env, a)
		fn = tbl and rawget(tbl, b)
	else
		fn = rawget(env, path)
	end
	if type(fn) ~= "function" then return false end
	local prevCtx, prevCb, prevEnv = H.ctx, H.cbName, H.currentEnv
	H.ctx, H.cbName, H.currentEnv = ctx, path, env
	local args = { ... }
	local n = select("#", ...)
	local ok, e = xpcall(function() return fn(unpack(args, 1, n)) end, debug.traceback)
	if not ok then table.insert(H.errors, string.format("[frame %d %s] Lua error: %s", H.frame, path, tostring(e))) end
	H.ctx, H.cbName, H.currentEnv = prevCtx, prevCb, prevEnv
	return true
end
T.callIn = callIn

function T.load(rel, name)
	name = name or rel
	local src, version = H.preprocess(rel)
	local s = { version = version, rel = rel, envs = {} }
	local function compile(env)
		local f, e = loadstring(src, "@" .. rel)
		if not f then
			table.insert(H.errors, "compile error in " .. rel .. ": " .. tostring(e))
			return
		end
		setfenv(f, env)
		local prev = H.currentEnv
		H.currentEnv = env
		H.ctx = "load"
		local ok, e2 = xpcall(f, debug.traceback)
		H.ctx = "scenario"
		H.currentEnv = prev
		if not ok then table.insert(H.errors, "top-level error in " .. rel .. ": " .. tostring(e2)) end
	end
	if version >= 2 then
		if H.split then
			s.envs.server = makeEnv("server")
			s.envs.client = makeEnv("client")
		else
			local e = makeEnv("host")
			s.envs.server = e
			s.envs.client = e
		end
		compile(s.envs.server)
		if s.envs.client ~= s.envs.server then compile(s.envs.client) end
	else
		s.envs.legacy = makeEnv("legacy")
		compile(s.envs.legacy)
	end
	T.scripts[name] = s
	return s
end

function T.init(name)
	local s = T.scripts[name]
	if s.version >= 2 then
		callIn(s.envs.server, "server", "server.init")
		T.syncShared(s)
		callIn(s.envs.client, "client", "client.init")
	else
		callIn(s.envs.legacy, "legacy", "init")
	end
end

function T.syncShared(s)
	if s.version < 2 then return end
	checkSyncable(rawget(s.envs.server, "shared"), "shared")
	if s.envs.client ~= s.envs.server then
		local copy = deepcopy(rawget(s.envs.server, "shared"))
		rawset(s.envs.client, "shared", copy)
		s.clientSnapshot = deepcopy(copy)
	end
end

local function checkClientShared(s)
	if s.version >= 2 and s.envs.client ~= s.envs.server and s.clientSnapshot then
		if not deepequal(rawget(s.envs.client, "shared"), s.clientSnapshot) then
			H.err("client code modified the shared table (it is read-only on clients)")
			s.clientSnapshot = nil
		end
	end
end

local function processCalls(s)
	local sc = H.pendingServerCalls
	H.pendingServerCalls = {}
	for _, c in ipairs(sc) do
		local ok = callIn(s.envs.server, "server", c.fname, unpack(c.args, 1, c.n))
		if not ok then H.err("ServerCall target not found: " .. c.fname) end
	end
	local cc = H.pendingClientCalls
	H.pendingClientCalls = {}
	for _, c in ipairs(cc) do
		local ok = callIn(s.envs.client, "client", c.fname, unpack(c.args, 1, c.n))
		if not ok then H.err("ClientCall target not found: " .. c.fname) end
	end
end

T.frameHooks = {}
function T.step(dt)
	dt = dt or H.dt
	H.dt = dt
	H.frame = H.frame + 1
	H.time = H.time + dt
	H.frameCalls = {}
	H.frameParticles = 0
	H.uiTexts = {}
	H.camera = nil
	H.cameraShake = 0
	H.lights = {}
	H.sprites = {}
	H.timeScale = 1
	for name, s in pairs(T.scripts) do
		if not s.isOptions then
			if s.version >= 2 then
				callIn(s.envs.server, "server", "server.tick", dt)
				T.syncShared(s)
				callIn(s.envs.client, "client", "client.tick", dt)
				processCalls(s)
			else
				callIn(s.envs.legacy, "legacy", "tick", dt)
			end
		end
	end
	T.accum = T.accum + dt
	local steps = 0
	while T.accum >= 1/60 - 1e-9 and steps < 4 do
		T.accum = T.accum - 1/60
		steps = steps + 1
		H.inUpdate = true
		for name, s in pairs(T.scripts) do
			if not s.isOptions then
				if s.version >= 2 then
					callIn(s.envs.server, "server", "server.update", 1/60)
					callIn(s.envs.client, "client", "client.update", 1/60)
				else
					callIn(s.envs.legacy, "legacy", "update", 1/60)
				end
			end
		end
		H.inUpdate = false
		H.physicsStep(1/60)
		for name, s in pairs(T.scripts) do
			if s.version >= 2 and not s.isOptions then
				callIn(s.envs.server, "server", "server.postUpdate")
				callIn(s.envs.client, "client", "client.postUpdate")
			end
		end
	end
	if steps == 4 then T.accum = 0 end
	for name, s in pairs(T.scripts) do
		H.inDraw = true
		H.uiSliderIndex = 0
		H.uiStack = 0
		if s.version >= 2 and not s.isOptions then
			H.inDraw = false
			callIn(s.envs.client, "client", "client.render", dt)
			H.inDraw = true
			callIn(s.envs.client, "client", "client.draw", dt)
		else
			callIn(s.envs.legacy, "legacy", "draw", dt)
		end
		if H.uiStack ~= 0 then H.err("UiPush/UiPop unbalanced in draw (" .. H.uiStack .. ") of " .. name) end
		H.inDraw = false
		checkClientShared(s)
	end
	if H.frameParticles > H.maxFrameParticles then H.maxFrameParticles = H.frameParticles end
	-- per-frame budgets
	for fname, max in pairs(T.budgets) do
		local n = (fname == "SpawnParticle") and H.frameParticles or (H.frameCalls[fname] or 0)
		if n > max and not T.budgetFailed[fname] then
			T.budgetFailed[fname] = true
			T.fail(string.format("budget: %s called %d times in frame %d (max %d)", fname, n, H.frame, max))
		end
	end
	-- end of frame: one-shot input flags and added players are consumed
	for _, id in ipairs(H.playerOrder) do
		local p = H.players[id]
		p.pressed = {}
		p.released = {}
	end
	H.addedPlayers = {}
	H.removedPlayers = {}
	for _, f in ipairs(T.frameHooks) do f() end
end

function T.frames(n, dt) for i = 1, n do T.step(dt) end end
function T.runUntil(cond, maxFrames, dt)
	for i = 1, maxFrames do
		T.step(dt)
		if cond() then return i end
	end
	return nil
end

-- input helpers (apply to the next frame)
function T.press(name, pid) local p = H.P(pid); p.pressed[name] = true; p.input[name] = true end
function T.hold(name, pid) local p = H.P(pid); p.input[name] = true end
function T.release(name, pid) local p = H.P(pid); p.input[name] = nil; p.released[name] = true end
function T.select(tool, pid) H.P(pid).tool = tool end
function T.player(pid) return H.P(pid) end

function T.pass(msg) table.insert(T.results, "PASS " .. msg) end
function T.fail(msg) table.insert(T.results, "FAIL " .. msg) end
function T.check(cond, msg) if cond then T.pass(msg) else T.fail(msg) end return cond end
function T.budget(fname, max) T.budgets[fname] = max end
function T.env(name) local s = T.scripts[name or "main"]; return s.envs.server or s.envs.legacy end
function T.cenv(name) local s = T.scripts[name or "main"]; return s.envs.client or s.envs.legacy end
function T.sharedOf(name) return rawget(T.env(name), "shared") end
function T.texts() return H.uiTexts end
function T.hasText(pattern)
	for _, t in ipairs(H.uiTexts) do if t:find(pattern, 1, true) then return true end end
	return false
end
function T.soundsPlayed(pathPart)
	local n = 0
	for _, s in ipairs(H.playedSounds) do if s.path:find(pathPart, 1, true) then n = n + 1 end end
	return n
end
function T.loopFrames(pathPart)
	local n = 0
	for p, c in pairs(H.playedLoops) do if p:find(pathPart, 1, true) then n = n + c end end
	return n
end
function T.errorCount() return #H.errors end

-- options.lua: legacy script with draw() only
function T.loadOptions(rel)
	local s = T.load(rel or "options.lua", "options")
	s.isOptions = true
	return s
end
function T.drawOptions(frames)
	local s = T.scripts.options
	for i = 1, (frames or 1) do
		H.frame = H.frame + 1
		H.uiTexts = {}
		H.uiSliderIndex = 0
		H.uiStack = 0
		H.inDraw = true
		H.frameCalls = {}
		callIn(s.envs.legacy, "legacy", "draw", H.dt)
		H.inDraw = false
		if H.uiStack ~= 0 then H.err("UiPush/UiPop unbalanced in options draw") end
	end
end

function T.runScenario(code, name)
	local f, e = loadstring(code, "@" .. name)
	if not f then error("scenario compile error: " .. tostring(e)) end
	local ok, e2 = xpcall(f, debug.traceback)
	if not ok then T.fail("scenario crashed: " .. tostring(e2)) end
end
