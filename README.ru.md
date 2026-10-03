# Моды для Teardown

Набор модов для Teardown 2.x (скриптовый API `#version 2`: `server` / `client` / `shared`).
У каждого мода своя папка: собранный мод в `mod/`, генераторы в `tools/`, офлайн-тесты в `tests/`
и свой README на английском и русском. English: [README.md](README.md).

<!-- mods -->
| Папка | Мод | Что это |
|---|---|---|
| [catapult](catapult) | Катапульта | A giant catapult. |
| [cutter](cutter) | Резак | An angle grinder. Hold the mouse button on a surface, sweep to the end point and release: the saw cuts a straight kerf from one point to the other, through walls, floors and vehicles. Controls: Hold LMB, sweep, release - cut a straight line from the press point to the release point. Settings in the Mod Manager (Options). |
| [drone](drone) | Дрон с камерой | take control again; R (on foot, within 4 m) - pack it up (refills bombs and battery); WASD - fly; Space / Ctrl - up / down; Mouse - look and turn; LMB (flying) - drop a bomb; Q - back to your body (the drone keeps hovering); P - photo mode. Settings in the Mod Manager (Options). |
| [earthquake](earthquake) | Землетрясение | stop it; RMB - next preset. Settings in the Mod Manager (Options). |
| [falling-moon](falling-moon) | Падающая луна | A telescope that calls the moon down on the aim point. Over 1-5 minutes it grows in the sky, the ground trembles, dust and wind rise and a countdown runs; then it slams into the ground, sits in a huge crater as a real voxel moon, and its shockwave takes almost everything around with it. Controls: LMB - call the moon down on the aim point; RMB - send it back. Settings in the Mod Manager (Options). |
| [gravity](gravity) | Смена гравитации | Ctrl in zero-G - float up / down. Settings in the Mod Manager (Options). |
| [mover](mover) | Перемещатель | pull; Q / R - rotate; Z / X - tilt; V / B - roll; T - freeze / unfreeze; G - clone; N / M - resample x0.5 / x2 (experimental); U - undo. Settings in the Mod Manager (Options). |
| [portal-gun](portal-gun) | Портальная пушка | Place a blue and an orange portal on flat surfaces and walk, fall or throw things through them. Momentum and direction are kept, so floor-to-wall flings work. Controls: LMB - blue portal; RMB - orange portal; R - close both. Settings in the Mod Manager (Options). |
| [remote](remote) | Радиоуправление | S - throttle / reverse; A / D - steer; Space - handbrake; V - chase camera on / off; Q - let go. Settings in the Mod Manager (Options). |
| [singularity-grenade](singularity-grenade) | Гравитационная граната | A throwable gravity grenade. It bounces, rises and opens into a short-lived singularity that pulls in debris, objects and players, squeezes them into a spinning orbit and then collapses in a blast. Controls: Hold LMB, release - throw (hold up to 1 s to throw farther); RMB - short toss at your feet. Settings in the Mod Manager (Options). |
| [telekinesis](telekinesis) | Телекинез | A telekinesis gauntlet. Lift the loose objects around your aim point into a spinning ring in front of you, charge, and throw them as a volley - or put them down gently. Controls: LMB (hands empty) - lift the objects around the aim point; Hold LMB (holding), release - charge and throw them as a volley; RMB - put them down gently. Settings in the Mod Manager (Options). |
| [time-slow](time-slow) | Замедление времени | x0.25 / x0.1. Settings in the Mod Manager (Options). |
| [tornado](tornado) | Торнадо | A storm caller. Spawn a tornado at the aim point: it forms in place, then wanders the map or follows your aim, sucking in, spinning, lifting and throwing objects, vehicles and you, and tearing weak buildings. Controls: LMB - spawn a tornado at the aim point; RMB - dismiss the nearest one. Settings in the Mod Manager (Options). |
| [trampoline-floor](trampoline-floor) | Пол-батут | off; Space on contact - bounce higher. Settings in the Mod Manager (Options). |
| [tsunami](tsunami) | Цунами | A conch horn that calls a tsunami from where you look. A siren warns while the wave rises on the horizon, then a wall of water rolls in, throws cars, carries away objects and you, tears buildings apart, floods the ground and finally runs back. Controls: LMB - call a tsunami from where you look; RMB - call it off. Settings in the Mod Manager (Options). |
| [volcano](volcano) | Вулкан | A magma core tool. Raise a volcano on the ground in a few seconds and watch it erupt in phases: rumble and smoke, lava bombs that punch craters and start fires, lava flows, ash, and a final blast that blows the summit off. Controls: LMB on the ground - raise a volcano; RMB during the eruption - final blast now; R - remove the cones. Settings in the Mod Manager (Options). |
<!-- /mods -->


## Мастерская Steam

Каждый мод готов к Мастерской (квадратное превью для Steam, превью 16:9 для игры, теги, описания EN/RU в `<мод>/workshop/`, проверка перед загрузкой). Пошаговая инструкция и порядок загрузки: [WORKSHOP.md](WORKSHOP.md#русский).

## Общие инструменты

В [`_shared`](_shared) лежат генераторы и офлайн-харнесс для всех модов: запись и чтение `.vox`
MagicaVoxel, синтез звуков с экспортом в OGG (ffmpeg), изометрический рендер вокселей для превью
и иконок, генератор экрана настроек, статическая проверка и поддельный движок Teardown, который
гоняет настоящие скрипты модов в Lua 5.1 (lupa) против API, собранного из `data/script_defs.lua` игры.

```powershell
cd _shared
python -m venv .venv
.venv\Scripts\python -m pip install lupa numpy pillow
cd ..\<мод>
..\_shared\.venv\Scripts\python tools\build_all.py
```

`build_all.py` заново собирает модели, звуки, картинки и экран настроек, затем запускает статическую
проверку и сценарии харнесса (каждый дважды: одна Lua-машина и раздельные сервер и клиент).
Игру эти инструменты не запускают.

## Как попробовать мод

Связать папку `mod/` мода с папкой локальных модов (команду запускать внутри папки мода):

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\<мод>" -Target "$PWD\mod"
```

В игре: Mod Manager -> Local files -> включить мод.
