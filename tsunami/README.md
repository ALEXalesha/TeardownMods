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

Teardown's water volumes cannot be raised by a script: a water entity's surface height is not a settable property (`SetProperty` accepts wave, ripple, motion, foam, depth, colour and type; the depth is how deep the volume goes, not where its surface is), and there is no water to spawn. So the wave and the flood are drawn - depth-tested sprites (a forward-leaning water face, two inner slices that follow the height profile behind it, a back slope from the crest down to the surge, a curling foam lip and crest spray, flat flood sheets) and foam particles - and their force is a scripted current. The water has one flat level, measured from the ground where you stood when you called it, like the sea rising: valleys flood deeper, hills and roofs above it stay dry. Real level water only gets rougher.

Budgets per physics step: 60 bodies moved (round robin, within 90 m of a player), 30 destruction probes, 24 holes with a sum of hole radius² up to 900; per frame on the client at most 133 sprites (7 per 10 m segment), 6 ground raycasts, 30 particles.

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

`tests/scenarios.lua` (32 checks, one VM and split server/client) with numbers: the front moves at the set speed (18.0 m/s), a crate is carried 76 m, a 1.2 t car 99 m, the player 39 m, a crate on a 25 m roof stays put, wood and brick walls are torn, hard masonry not at all, the level's water turns rough and is restored exactly, the wall is drawn with depth-tested sprites only. `tests/destruction_law.lua` (a block town in the wave's path): wooden buildings 100 % torn down, brick 99-100 %, hard masonry 0 %, a car thrown at 20.6 m/s, work per step within budget.
