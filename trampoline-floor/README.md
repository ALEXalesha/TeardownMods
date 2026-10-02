# Trampoline Floor (Teardown mod)

Bounce pads and a bouncy-ground mode. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB | place a 3 x 3 m trampoline pad on flat ground (up to 8) |
| RMB | remove the nearest pad |
| R | global mode on / off: the whole ground bounces |

- The pad is an own voxel model (blue frame with springs and a yellow stripe, black membrane, corner lights), spawned as a static body on the ground facing you.
- Teardown has no per-surface restitution, so the bounce is a velocity change done by the server: it watches the vertical speed of players and bodies; when something that was falling faster than 3 m/s suddenly stops over a pad (or, in global mode, just above static ground), its downward speed times the restitution (0.85 by default, max 25 m/s) is given back upwards with `SetPlayerVelocity` / `SetBodyVelocity`.
- Players, loose objects and vehicles can bounce (each switchable). Bodies are found with `QueryAabbBodies` over the pads and, in global mode, within 30 m of the players, every 0.25 s; 40 bodies are checked per physics step.
- Effects: boing (two sizes, pitch by impact), a ring of dust, the pad membrane dips and springs back (animated by the server, the pad is server-authored), a soft light over the pads while the tool is in hand.

## Options

| Setting | Default | Key |
|---|---|---|
| Bounciness 0.3-1.3 | 0.85 | `savegame.mod.restitution` |
| Max bounce speed 5-50 m/s | 25 | `savegame.mod.maxspeed` |
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
