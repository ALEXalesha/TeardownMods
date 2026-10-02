#version 2
-- Time Slow / Замедление времени
-- Hold (or toggle) a key to slow the world down with SetTimeScale. Presets
-- x0.5 / x0.25 / x0.1, smooth ramps, blue tint and desaturation through the
-- post-processing properties, enter/exit whooshes, heartbeat, optional energy
-- meter, optional walking-speed compensation for the player.
--
-- SetTimeScale is server-only in #version 2 (script_defs example and the game's
-- own scripts call it from server code), must be called every frame and accepts 0..2; since Teardown 1.5
-- it slows everything through rendering interpolation without changing physics
-- behaviour. It slows the player too: the API has no per-entity time, so
-- "player at normal speed" can only be approximated (walking speed boost).

local PRESETS = { 0.5, 0.25, 0.1 }
local KEYS = { h = "H", y = "Y", t = "T", mmb = "MMB" }

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function getF(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return d end
local function getI(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetInt(key) end return d end
local function getB(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return d end
local function getS(k, d) local key = "savegame.mod." .. k if HasKey(key) then return GetString(key) end return d end
local function tr(en, ru) if GetInt("options.language") == 7 then return ru end return en end
local function lerp(a, b, t) return a + (b - a) * t end

function readSettings()
	local key = getS("key", "h")
	if not KEYS[key] then key = "h" end
	return {
		key = key,
		toggle = getB("toggle", false),
		preset = math.floor(clamp(getI("preset", 2), 1, 3)),
		ramp = clamp(getF("ramp", 0.35), 0.05, 1.5),
		energy = getB("energy", true),
		capacity = clamp(getF("capacity", 8), 2, 60),
		recharge = clamp(getF("recharge", 12), 2, 60),
		tint = clamp(getF("tint", 0.8), 0, 1),
		walk = getB("walk", false),
		hint = getB("hint", true),
	}
end

---------------------------------------------------------------------------
-- SERVER: only the optional walking-speed compensation lives here
---------------------------------------------------------------------------

function server.init()
	server.baseWalk = {}
	server.scale = {}      -- player -> requested time scale
end

-- the client computes the ramp (in real time) and sends the scale it wants
function server.setScale(p, scale)
	if scale >= 0.999 then
		server.scale[p] = nil
	else
		server.scale[p] = clamp(scale, 0.05, 1)
	end
end

-- SetTimeScale only works from server code in #version 2 and lasts one frame,
-- so it is applied here every tick. With several players the slowest request wins.
function server.tick(dt)
	local s = 1
	for p, v in pairs(server.scale) do
		if IsPlayerValid(p) then s = math.min(s, v) else server.scale[p] = nil end
	end
	if s < 0.999 then SetTimeScale(s) end
end

function server.walk(p, factor)
	if not IsPlayerValid(p) then return end
	if factor > 1.001 then
		if not server.baseWalk[p] then server.baseWalk[p] = GetPlayerWalkingSpeed(p) end
		SetPlayerWalkingSpeed(server.baseWalk[p] * factor, p)
	elseif server.baseWalk[p] then
		SetPlayerWalkingSpeed(server.baseWalk[p], p)
		server.baseWalk[p] = nil
	end
end

---------------------------------------------------------------------------
-- CLIENT
---------------------------------------------------------------------------

function client.init()
	client.s = readSettings()
	client.preset = client.s.preset
	client.active = false
	client.k = 0
	client.energy = 1
	client.lockout = false
	client.sinceUse = 10
	client.lastTime = GetTime()
	client.orig = nil
	client.sentWalk = 1
	client.presetFlash = 0
	client.hintT = 8
	client.snd = {
		enter = LoadSound("MOD/snd/enter.ogg"),
		exit = LoadSound("MOD/snd/exit.ogg"),
		empty = LoadSound("MOD/snd/empty.ogg"),
		click = LoadSound("MOD/snd/click.ogg"),
	}
end

local function captureOriginal()
	local sat = GetPostProcessingProperty("saturation")
	local r, g, b = GetPostProcessingProperty("colorbalance")
	client.orig = { sat = sat or 1, r = r or 1, g = g or 1, b = b or 1 }
end

local function applyTint(k, strength)
	local o = client.orig
	if not o then return end
	local t = k * strength
	SetPostProcessingProperty("saturation", lerp(o.sat, o.sat * 0.45, t))
	SetPostProcessingProperty("colorbalance", lerp(o.r, o.r * 0.82, t), lerp(o.g, o.g * 0.97, t), lerp(o.b, o.b * 1.25, t))
end

local function restoreTint()
	local o = client.orig
	if not o then return end
	SetPostProcessingProperty("saturation", o.sat)
	SetPostProcessingProperty("colorbalance", o.r, o.g, o.b)
	client.orig = nil
end

local function keyDown(key) return InputDown(key) end
local function keyPressed(key) return InputPressed(key) end
local function keyReleased(key) return InputReleased(key) end

function client.setActive(on)
	if on == client.active then return end
	client.active = on
	if on then
		PlaySound(client.snd.enter, nil, 0.8)
	else
		PlaySound(client.snd.exit, nil, 0.7)
	end
end

function client.tick(dt)
	local now = GetTime()
	local real = clamp(now - client.lastTime, 0, 0.1)
	client.lastTime = now
	local s = readSettings()
	client.s = s

	client.hintT = math.max(0, client.hintT - real)
	client.presetFlash = math.max(0, client.presetFlash - real)

	-- input
	local usable = not GetBool("game.paused") and GetPlayerHealth() > 0
	if usable then
		if InputPressed("j") then
			client.preset = (client.preset % #PRESETS) + 1
			client.presetFlash = 2
			PlaySound(client.snd.click, nil, 0.6)
		end
		if s.toggle then
			if keyPressed(s.key) then client.setActive(not client.active) end
		else
			if keyPressed(s.key) or (keyDown(s.key) and not client.active and not client.lockout) then client.setActive(true) end
			if keyReleased(s.key) or (client.active and not keyDown(s.key)) then client.setActive(false) end
		end
	else
		client.setActive(false)
	end
	if client.active and client.lockout then client.setActive(false) end

	-- energy
	if s.energy then
		if client.active then
			client.energy = client.energy - real / s.capacity
			client.sinceUse = 0
			if client.energy <= 0 then
				client.energy = 0
				client.lockout = true
				client.setActive(false)
				PlaySound(client.snd.empty, nil, 0.8)
			end
		else
			client.sinceUse = client.sinceUse + real
			if client.sinceUse > 1.0 then
				client.energy = math.min(1, client.energy + real / s.recharge)
			end
			if client.lockout and client.energy >= 0.3 then client.lockout = false end
		end
	else
		client.energy = 1
		client.lockout = false
	end

	-- ramp in real time
	local want = client.active and 1 or 0
	local step = real / s.ramp
	if client.k < want then client.k = math.min(want, client.k + step) else client.k = math.max(want, client.k - step) end
	local k = client.k * client.k * (3 - 2 * client.k)
	local target = PRESETS[client.preset]
	local scale = 1 - k * (1 - target)
	client.scale = scale

	-- the time scale itself is set on the server (SetTimeScale is server-only in #version 2)
	if math.abs(scale - (client.sentScale or 1)) > 0.004 or (scale >= 0.999 and (client.sentScale or 1) < 0.999) then
		ServerCall("server.setScale", GetLocalPlayer(), scale)
		client.sentScale = scale
	end
	if client.k > 0.0005 then
		if not client.orig then captureOriginal() end
		applyTint(k, s.tint)
		SetMusicLowPass(0.85 * k)
	elseif client.orig then
		restoreTint()
	end

	-- walking compensation (server side, sent only when it changes noticeably)
	local walk = 1
	if s.walk and k > 0.01 then walk = clamp(1 / scale, 1, 4) end
	if math.abs(walk - client.sentWalk) > 0.05 or (walk == 1 and client.sentWalk ~= 1) then
		ServerCall("server.walk", GetLocalPlayer(), walk)
		client.sentWalk = walk
	end
end

function client.destroy()
	restoreTint()
end

function client.draw(dt)
	local k = client.k
	local s = client.s
	if k > 0.01 and s.tint > 0 then
		UiPush()
			local w, h = UiGetImageSize("MOD/ui/vignette.png")
			UiScale(UiWidth() / w, UiHeight() / h)
			UiColor(0.25, 0.5, 1.0, 0.45 * k * s.tint)
			UiImage("MOD/ui/vignette.png")
		UiPop()
		UiSoundLoop("MOD/snd/heartbeat.ogg", 0.7 * k, 1.0)
	end
	if GetBool("game.ui.hidemods") then return end

	local show = k > 0.01 or (s.energy and client.energy < 0.999) or client.presetFlash > 0
	if show then
		UiPush()
			UiTranslate(UiWidth() - 250, 60)
			UiAlign("left middle")
			UiColor(1, 1, 1, 0.9)
			UiImage("MOD/ui/icon.png")
			UiTranslate(70, 18)
			UiFont("bold.ttf", 30)
			UiColor(0.6, 0.85, 1, 1)
			UiText(string.format("x%.2g", PRESETS[client.preset]))
			if s.energy then
				UiTranslate(0, 28)
				UiColor(0, 0, 0, 0.5)
				UiRect(150, 10)
				local e = client.energy
				if client.lockout then UiColor(1, 0.3, 0.25, 1) else UiColor(0.4 + 0.6 * (1 - e), 0.8, 1, 1) end
				UiRect(150 * e, 10)
			end
		UiPop()
	end
	if s.hint and client.hintT > 0 then
		UiPush()
			UiTranslate(UiCenter(), 120)
			UiAlign("center middle")
			UiFont("regular.ttf", 22)
			UiTextShadow(0, 0, 0, 0.6, 1.5)
			UiColor(1, 1, 1, math.min(1, client.hintT))
			local key = KEYS[s.key]
			if s.toggle then
				UiText(tr("Press " .. key .. ": slow motion, J: change speed", "Нажмите " .. key .. ": замедление, J: сменить скорость"))
			else
				UiText(tr("Hold " .. key .. ": slow motion, J: change speed", "Удерживайте " .. key .. ": замедление, J: сменить скорость"))
			end
		UiPop()
	end
	if client.lockout and k <= 0.01 and (InputDown(s.key)) then
		UiPush()
			UiTranslate(UiCenter(), UiHeight() - 160)
			UiAlign("center middle")
			UiFont("bold.ttf", 22)
			UiColor(1, 0.4, 0.3, 1)
			UiText(tr("Recharging...", "Перезарядка..."))
		UiPop()
	end
end
