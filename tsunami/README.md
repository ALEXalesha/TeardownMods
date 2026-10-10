# Tsunami (Teardown mod)

Call a tsunami. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB | call a tsunami from where you look (it comes towards you) |
| RMB while it comes | call it off (the water runs back) |

## What happens

1. **Warning** (7 s): a siren, a flashing "TSUNAMI WARNING" with the distance and height of the wave; the wave rises 260 m away; water that exists in the level turns rough (`SetProperty` on the level's water entities: wave, motion and foam go up; the original values are read first and written back exactly at the end).
2. **The wave**: a wall of water 400 m wide (14 m high by default) rolls in at the set speed (default 18 m/s), with a foam crest, spray and a roar coming from the nearest point of the front. Behind the steep 12 m front, 60 m of fast water, then the flood level. Everything below the water surface - loose objects, vehicles, the player - is dragged hard towards the flow speed (1.15 x the wave speed in the crest). Vehicles float and ride the flood; debris is not lifted out of the water: buoyancy depends on density and holds up at most 3/4 of the weight, upward motion is damped, so pieces roll and slide along instead of flying into the sky. Along the front, near the players, buildings give way over the whole wave height: holes up to about 6 m in soft materials (wood, glass, plaster) and up to about 3 m in brick and concrete, none in hard materials; the debris that breaks off is carried along.
3. **Backwash** (9 s): the flow turns and pulls things back a little while the flood drains away.

## What is real and what is an effect

Teardown's water volumes cannot be raised by a script: a water entity's surface height is not a settable property (`SetProperty` accepts wave, ripple, motion, foam, depth, colour and type; the depth is how deep the volume goes, not where its surface is), and there is no water to spawn. So the wave and the flood are drawn - depth-tested sprites (a forward-leaning water face, two inner slices that follow the height profile behind it, a back slope from the crest down to the surge, a curling foam lip and crest spray) and foam particles - and their force is a scripted current.

The flood behind the crest is a body of water around the camera, wherever the water is (up to 775d30a it was one flat sheet per segment, 72 m long, and further back nothing): the fast surge in tilted pieces that follow the height profile, with a foam bead where the falling crest hits it; behind it, near the camera, 6 x 6 tiles of 10 m, each a dark murky layer up to 0.9 m down and a light surface on top that rides a gentle swell (tiles at different heights, tilted to its slope, the swell running downstream); a middle layer of 20 m tiles drifting at half speed between them (the layers shift against each other as you move, so the depth shows); big sheets out to 150 m; 16 foam and debris streaks lying along the current and drifting with it; and where the flooded zone ends sideways, a wall of water with foam on top, so the flood has a side, not just a top (drawn when you are within 70 m of that edge). The flood sprites are fog-affected, so the flood fades into the distance like the level. While the water runs back, the same flood sinks and flows back.

Other ways checked (`data/script_defs.lua` of the installed game): water entities only take wave, ripple, motion, foam, depth, colour and type through `SetProperty`, `Spawn` documents no water, and `QueryRaycastWater` / `IsPointInWater` only read. A real rising water level is not available to mods, so the flood stays drawn. The water has one flat level, measured from the ground where you stood when you called it, like the sea rising: valleys flood deeper, hills and roofs above it stay dry. Real level water only gets rougher.

Budgets per physics step: 60 bodies moved (round robin, within 90 m of a player), 30 destruction probes, 24 holes with a sum of hole radius² up to 900; per frame on the client at most 280 sprites (a hard cap in the drawing code; the front gets 9 per 10 m segment within 40 m of you sideways and 4 further out, the flood at most 150, by level of detail: near tiles, a coarse middle layer, far sheets), 6 ground raycasts, 30 particles. Nothing drawn per frame grows with the size of the flooded zone: everything is centred on the camera, and the ground under the side walls is measured once and kept.

## Options

| Setting | Default | Key |
|---|---|---|
| Wave height 3-25 m | 14 m | `savegame.mod.height` |
| Wave speed 8-35 m/s | 18 m/s | `savegame.mod.speed` |
| Flood level behind it 0-4 m | 1.5 m | `savegame.mod.flood` |
| Damage to buildings x0-x3 | x1.5 | `savegame.mod.power` |
| Warning siren | on | `savegame.mod.siren` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\tsunami" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

`tests/scenarios.lua` (32 checks, one VM and split server/client) with numbers: the front moves at the set speed (18.0 m/s), a crate is carried 76 m, a 1.2 t car 99 m, the player 39 m, a crate on a 25 m roof stays put, wood and brick walls are torn, hard masonry not at all, the level's water turns rough and is restored exactly, the wall and the flood are drawn with depth-tested sprites only, at most 280 per frame. `tests/flood_look_law.lua` (the player holds on far behind the front, then near the zone's edge): water is drawn around the camera behind the front, a surface and a darker layer at least 0.3 m below it, an uneven surface (heights differ, tiles tilted 1-15 deg, the swell changes 0.08 m per 1/2 s), 15 streaks along the current drifting 0.044 m per frame, the foam bead in every frame near the front, far sheets about 10 x the area of near tiles, no water ahead of the front or outside the zone, vertical side walls from the ground up to the surface near the edge and none in the middle, the flood drains in the backwash; at most 250 sprites per frame, 129 of them for the flood. `tests/physics_lock_law.lua`: the server half of main.lua (water height and flow, the current, tearing) is byte for byte the one of 775d30a, and the client never touches physics. `tests/lift_law.lua`: debris is never thrown above the water. `tests/destruction_law.lua` (a block town in the wave's path): wooden buildings 100 % torn down, brick 99-100 %, hard masonry 0 %, a car thrown at 20.6 m/s, work per step within budget.
