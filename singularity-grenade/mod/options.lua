-- Options screen for Singularity Grenade (opened from the Mod Manager).
-- All values are stored in savegame.mod.* and read by main.lua at level start
-- and again on every throw.

local PANEL_W = 760
local PANEL_H = 700
local ROW_H = 46
local SLIDER_W = 260

local function ru() return GetInt("options.language") == 7 end
local function tr(en, r) if ru() then return r end return en end

local DEFAULTS = {
	radius = 8, strength = 1, duration = 4, ammo = 5,
	impact = false, pullplayer = true, damage = 1, tear = true, blast = false,
}

local function getF(k) local key = "savegame.mod." .. k if HasKey(key) then return GetFloat(key) end return DEFAULTS[k] end
local function getI(k) local key = "savegame.mod." .. k if HasKey(key) then return GetInt(key) end return DEFAULTS[k] end
local function getB(k) local key = "savegame.mod." .. k if HasKey(key) then return GetBool(key) end return DEFAULTS[k] end

local function resetDefaults()
	SetFloat("savegame.mod.radius", DEFAULTS.radius)
	SetFloat("savegame.mod.strength", DEFAULTS.strength)
	SetFloat("savegame.mod.duration", DEFAULTS.duration)
	SetInt("savegame.mod.ammo", DEFAULTS.ammo)
	SetBool("savegame.mod.impact", DEFAULTS.impact)
	SetBool("savegame.mod.pullplayer", DEFAULTS.pullplayer)
	SetInt("savegame.mod.damage", DEFAULTS.damage)
	SetBool("savegame.mod.tear", DEFAULTS.tear)
	SetBool("savegame.mod.blast", DEFAULTS.blast)
end

-- label on the left, slider in the middle, value on the right
local function sliderRow(label, key, min, max, fmt, isInt)
	local value = isInt and getI(key) or getF(key)
	UiPush()
		UiAlign("left middle")
		UiFont("regular.ttf", 24)
		UiColor(1, 1, 1, 0.9)
		UiText(label)
		UiTranslate(300, 0)
		UiColor(1, 1, 1, 0.25)
		UiRect(SLIDER_W, 4)
		UiColor(0.75, 0.45, 1.0, 1)
		local t = (value - min) / (max - min)
		UiRect(SLIDER_W * t, 4)
		UiColor(1, 1, 1, 1)
		UiTranslate(-10, 0)
		local pos, done = UiSlider("MOD/ui/dot.png", "x", SLIDER_W * t, 0, SLIDER_W)
		local nv = min + (pos / SLIDER_W) * (max - min)
		if isInt then
			nv = math.floor(nv + 0.5)
			if nv ~= value then SetInt("savegame.mod." .. key, nv) end
		else
			nv = math.floor(nv * 10 + 0.5) / 10
			if math.abs(nv - value) > 0.001 then SetFloat("savegame.mod." .. key, nv) end
		end
		UiTranslate(SLIDER_W + 40, 0)
		UiFont("bold.ttf", 24)
		UiText(string.format(fmt, isInt and getI(key) or getF(key)))
	UiPop()
end

-- label on the left, a button that cycles through the choices
local function choiceRow(label, key, choices, isInt)
	local current = isInt and getI(key) or getB(key)
	local idx = 1
	for i = 1, #choices do if choices[i][1] == current then idx = i end end
	UiPush()
		UiAlign("left middle")
		UiFont("regular.ttf", 24)
		UiColor(1, 1, 1, 0.9)
		UiText(label)
		UiTranslate(300, 0)
		UiFont("bold.ttf", 24)
		UiColor(1, 1, 1, 1)
		UiButtonImageBox("ui/common/box-outline-6.png", 6, 6, 1, 1, 1, 0.6)
		UiButtonHoverColor(0.85, 0.65, 1.0, 1)
		if UiTextButton(choices[idx][2], 300, 36) then
			local nextChoice = choices[(idx % #choices) + 1][1]
			if isInt then SetInt("savegame.mod." .. key, nextChoice) else SetBool("savegame.mod." .. key, nextChoice) end
		end
	UiPop()
end

function draw()
	UiPush()
		UiColor(0, 0, 0, 0.55)
		UiRect(UiWidth(), UiHeight())
	UiPop()

	UiPush()
		UiTranslate(UiCenter(), UiMiddle())
		UiAlign("center middle")
		UiColor(0.07, 0.05, 0.1, 0.92)
		UiRoundedRect(PANEL_W, PANEL_H, 14)
		UiColor(0.75, 0.45, 1.0, 0.8)
		UiRoundedRectOutline(PANEL_W, PANEL_H, 14, 2)

		UiTranslate(0, -PANEL_H / 2 + 50)
		UiFont("bold.ttf", 40)
		UiColor(1, 1, 1, 1)
		UiText(tr("Singularity Grenade", "Гравитационная граната"))
		UiTranslate(0, 34)
		UiFont("regular.ttf", 20)
		UiColor(0.8, 0.7, 1.0, 0.8)
		UiText(tr("Settings apply to the next throw", "Настройки действуют со следующего броска"))

		UiTranslate(-PANEL_W / 2 + 40, 56)
		sliderRow(tr("Radius", "Радиус"), "radius", 3, 20, tr("%.1f m", "%.1f м"), false)
		UiTranslate(0, ROW_H)
		sliderRow(tr("Strength", "Сила"), "strength", 0.2, 3, "x%.1f", false)
		UiTranslate(0, ROW_H)
		sliderRow(tr("Duration", "Длительность"), "duration", 1, 15, tr("%.1f s", "%.1f с"), false)
		UiTranslate(0, ROW_H)
		sliderRow(tr("Grenades", "Боезапас"), "ammo", 1, 50, "%d", true)
		UiTranslate(0, ROW_H)
		choiceRow(tr("Opens", "Раскрытие"), "impact",
			{ { false, tr("1.5 s after stopping", "Через 1,5 с после остановки") }, { true, tr("On impact", "От удара") } }, false)
		UiTranslate(0, ROW_H)
		choiceRow(tr("Pulls the player", "Тянет игрока"), "pullplayer",
			{ { true, tr("Yes", "Да") }, { false, tr("No", "Нет") } }, false)
		UiTranslate(0, ROW_H)
		choiceRow(tr("Damage to players", "Урон игроку"), "damage",
			{ { 0, tr("Off", "Нет") }, { 1, tr("Low", "Слабый") }, { 2, tr("High", "Сильный") } }, true)
		UiTranslate(0, ROW_H)
		choiceRow(tr("Tears weak materials", "Рвёт слабые материалы"), "tear",
			{ { true, tr("Yes", "Да") }, { false, tr("No", "Нет") } }, false)
		UiTranslate(0, ROW_H)
		choiceRow(tr("Real explosion at the end", "Настоящий взрыв в конце"), "blast",
			{ { false, tr("No", "Нет") }, { true, tr("Yes", "Да") } }, false)

		UiTranslate(PANEL_W / 2 - 40, ROW_H + 30)
		UiAlign("center middle")
		UiFont("regular.ttf", 22)
		UiButtonImageBox("ui/common/box-outline-6.png", 6, 6, 1, 1, 1, 0.8)
		UiPush()
			UiTranslate(-130, 0)
			if UiTextButton(tr("Reset to defaults", "Сбросить"), 230, 44) then
				resetDefaults()
			end
		UiPop()
		UiPush()
			UiTranslate(130, 0)
			if UiTextButton(tr("Close", "Закрыть"), 230, 44) then
				Menu()
			end
		UiPop()
	UiPop()
end
