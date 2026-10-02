# Camera Drone (Teardown mod)

A deployable quadcopter flown from its own camera. Russian: [README.ru.md](README.ru.md).

| Input | On foot (tool in hand) | Flying |
|---|---|---|
| LMB | launch the drone / take control of it again | drop a bomb on the target marker |
| WASD | | fly (relative to the camera heading) |
| Space / Ctrl | | up / down |
| Mouse | | look (yaw turns the drone, pitch tilts the camera gimbal) |
| Q | | back to the player's body (the drone keeps hovering) |
| P | | photo mode: hides the HUD and the static |
| R | pack the drone up (within 4 m), bombs and battery refill | |

- Own voxel model with four rotor shapes spinning (animated by the server, because the drone body is server-authored and clients may only read it; rotor collision is switched off), blinking LEDs, a light under the body, a hum loop whose volume and pitch follow the thrust.
- Flight: velocity tracking with `ApplyBodyImpulse` plus gravity compensation, upright and tilted into motion with `ConstrainOrientation`. With no input it holds position.
- Battery (3 min by default, more drain at high thrust): when empty the motors stop and the drone falls.
- Signal range (150 m by default): from 75% of the range the picture gets static (noise and scan lines, static sound); past the range the link is lost, input is ignored and the drone slowly descends.
- Crash: a velocity change above 9 m/s in one physics step (the mod subtracts its own push) breaks the drone into debris; control returns to the player.
- Bombs: 3 per flight. If the Singularity Grenade mod is enabled, the drop is handed to it through the registry
  (`level.singularity_grenade.req.<n>.*`, see that mod's README): the real singularity grenade falls, with the drone's velocity. Otherwise the drone drops its own bomb that explodes on impact (`Explosion`, size 1.0 by default).
- Target marker: a ring on the ground where a bomb released now would land (ballistic estimate with the current velocity).

## What the API allows (honest notes)

- The player's body is held with `DisablePlayerInput` from `server.tick`, the same way the game's spawn menu does; the camera is set with `SetCameraTransform` every frame. If `DisablePlayerInput` turned out to block the drone keys too, switch "Freeze player while flying" off in options.
- Photo mode: there is no screenshot function in `script_defs.lua` (`Command` is deprecated and only exposes the game's screen recorder), so photo mode hides the HUD and you take the picture with Steam's screenshot key (F12).
- Cross-mod drop works only because both mods are ours and agree on the registry keys; Teardown has no general way to call another mod's code.

## Options

| Setting | Default | Key |
|---|---|---|
| Max speed 5-25 m/s | 12 | `savegame.mod.speed` |
| Signal range 50-500 m | 150 | `savegame.mod.range` |
| Battery limited / unlimited | limited | `savegame.mod.battery` |
| Battery lasts 1-10 min | 3 | `savegame.mod.minutes` |
| Bombs per flight 1-10 | 3 | `savegame.mod.bombs` |
| Drop Singularity Grenade if that mod is on | yes | `savegame.mod.grenade` |
| Own bomb size 0.5-2 | 1.0 | `savegame.mod.bombsize` |
| Breaks at impact of 4-20 m/s | 9 | `savegame.mod.crash` |
| Mouse sensitivity | x1 | `savegame.mod.sens` |
| Camera FOV 60-110° | 90 | `savegame.mod.fov` |
| Freeze player while flying | yes | `savegame.mod.freeze` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\drone" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Camera Drone -> enable; the tool "Camera Drone" is in the last tool group.
