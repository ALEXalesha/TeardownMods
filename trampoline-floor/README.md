# Trampoline Floor (Teardown mod)

Bounce pads and a bouncy-ground mode. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB | place a 3 x 3 m trampoline pad on flat ground (up to 8) |
| RMB | remove the nearest pad |
| R | global mode on / off: the whole ground bounces |

- The pad is an own voxel model (blue frame with springs and a yellow stripe, black membrane, corner lights), spawned as a static body on the ground facing you.
- Teardown has no per-surface restitution, so the bounce is a velocity change done by the server. Contact is found by position: when the bottom of a falling player or body is within reach of the pad membrane (or, in global mode, the static ground below it) before the next physics step, its falling speed - or the one remembered from the last 0.25 s, in case the engine already stopped it - times the restitution is given back upwards with `SetPlayerVelocity` / `SetBodyVelocity`. The default restitution is 1.05, so every bounce is a little higher than the drop, up to the speed cap (30 m/s). Holding or pressing jump on contact adds +6 m/s, so you can climb very high bounce by bounce. Falling bodies are checked every physics step (round robin above 60 at once), ground heights are cached per body; law with numbers in `tests/bounce_law.lua`: a 5 m drop comes back to at least 5 m for the player, a crate and a car, on a pad and in global mode, and 60 crates landing together all bounce.
- Players, loose objects and vehicles can bounce (each switchable). Bodies are found with `QueryAabbBodies` over the pads and, in global mode, within 30 m of the players, every 0.25 s; 40 bodies are checked per physics step.
- Effects: boing (two sizes, pitch by impact), a ring of dust, the pad membrane dips and springs back (animated by the server, the pad is server-authored), a soft light over the pads while the tool is in hand.

## Options

| Setting | Default | Key |
|---|---|---|
| Bounciness 0.3-1.5 | 1.05 | `savegame.mod.restitution` |
| Max bounce speed 5-60 m/s | 30 | `savegame.mod.maxspeed` |
| Jump boost on contact 0-15 m/s | 6 | `savegame.mod.jumpboost` |
| Players bounce | yes | `savegame.mod.players` |
| Objects bounce | yes | `savegame.mod.bodies` |
| Vehicles bounce | yes | `savegame.mod.vehicles` |
| Global mode radius 10-80 m | 30 | `savegame.mod.radius` |
| Whole ground bounces at start | no | `savegame.mod.global` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\trampoline-floor" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Trampoline Floor -> enable; the tool "Bounce Pads" is in the last tool group.
