# Vehicle Remote (Teardown mod)

Drive any vehicle remotely, like an RC car, while you stay where you are. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB on a vehicle | take remote control (any body of it counts, wheels too); on another vehicle while driving: hop to it |
| W / S | throttle / reverse |
| A / D | steer |
| Space | handbrake |
| V | chase camera on / off (mouse orbits it) |
| Q | let go |

- Real driving API: `DriveVehicle(vehicle, drive, steering, handbrake)`, called every tick from server code (the game's own `truxterminator.lua` does the same). Vehicles are server-authored, so the client only reads them and sends its input with `ServerCall` when it changes; no force tricks.
- The player's body is held with `DisablePlayerInput` while driving (option), so WASD only drives the car.
- Chase camera: behind and above the car, mouse orbits, pulled in front of walls; V switches back to your own eyes.
- Signal range 150 m: from 75% of it the picture gets static with a static sound; past it the link is lost, the car brakes with the handbrake, and after 3 s it is released.
- The controlled car has a cyan outline, the aimed one a white outline. HUD: speed, damage (from `GetVehicleHealth`), signal bars, controls.
- A car that another player drives (or sits in) cannot be taken. If the vehicle disappears, control ends.

## Options

| Setting | Default | Key |
|---|---|---|
| Signal range 30-500 m | 150 m | `savegame.mod.range` |
| Pick-up distance 10-200 m | 80 m | `savegame.mod.aimrange` |
| Chase camera on at start | yes | `savegame.mod.follow` |
| Camera distance 3-20 m | 7 m | `savegame.mod.camdist` |
| Freeze player while driving | yes | `savegame.mod.freeze` |
| Mouse sensitivity | x1 | `savegame.mod.sens` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\remote" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Vehicle Remote -> enable; the tool "Vehicle Remote" is in the last tool group.
