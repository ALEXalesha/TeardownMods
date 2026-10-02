# Tornado (Teardown mod)

A storm caller tool. Russian: [README.ru.md](README.ru.md).

- **LMB** spawns a tornado at the aim point (up to 2 at a time), **RMB** dismisses the nearest one (it fades out over 3 s).
- The tornado forms in place for about 3 s, then travels: on a smooth random path (value noise steering, turns back at the map boundary) or towards your aim point (option).
- Funnel: the radius grows with height (0.6 m at the ground to the "size" at the top, height = 3.6 x size), the axis bends and sways. Particles: spiralling smoke wall dark at the base and lighter at the top, a dust ring around the base, dark debris specks orbiting and flung out, plus a dim light at the top. Wind roar loop (60 m nominal distance, so it gets louder as it approaches), thunder when it spawns, a fading gust when it dies, camera shake near it.
- Forces: bodies within 1.6 x size of the funnel axis are pulled in, spun and lifted; above 82% of the height they are thrown outwards. Heavier bodies get less (`1200 / (1200 + mass)`), the added speed is capped. The scale of the velocity change is in the range of the game's own tornado script.
- Vehicles and the player can be lifted (options); walls between the player and the funnel shield the player; very close to it the player drops what they are carrying.
- Damage within a budget: 2 `QueryClosestPoint` probes per physics step around the lower funnel; glass, wood, plaster, plastic and foliage get holes, concrete and weak metal only at strength 2 and above; up to 2 joints of lifted bodies are detached every 0.3 s. At most 600 holes per tornado.

Budget: one `QueryAabbBodies` every 0.25 s per tornado, up to 150 tracked bodies, 50 impulses per physics step (round robin);
32 particles per physics step shared by all tornadoes.

The game ships an internal tornado (`data/script/tornado.lua`) with C++ helpers `TornadoSpawnParticlesCPP` / `TornadoBodiesSuctionCPP`.
They are listed in `script_defs.lua` without documented parameters, so this mod does its own Lua physics and particles instead.

## Options

| Setting | Default | Key |
|---|---|---|
| Strength x0.3-x3 | x1 | `savegame.mod.strength` |
| Size (top radius) 4-20 m | 8 m | `savegame.mod.size` |
| Lifetime 10-180 s | 40 s | `savegame.mod.duration` |
| Travel speed 1-12 m/s | 4 | `savegame.mod.speed` |
| Movement: wanders / follows your aim | wanders | `savegame.mod.follow` |
| Lifts vehicles | yes | `savegame.mod.vehicles` |
| Lifts the player | yes | `savegame.mod.player` |
| Tears buildings | yes | `savegame.mod.damage` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\tornado" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Tornado -> enable; the tool "Storm Caller" is in the last tool group.
