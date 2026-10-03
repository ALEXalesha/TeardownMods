# Volcano (Teardown mod)

Raise a volcano and watch it erupt. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB on the ground | raise a volcano there (kept at least its radius + 4 m away from you) |
| RMB during the rumble or eruption | final blast right now |
| R (nothing erupting) | remove all cones |

## Phases

1. **Growth** (about 5 s): seven rock layers of the cone (own voxel models, palette range "rock") appear one after another, each spawned directly at its final place. Where the game puts a spawned vox relative to its spawn point is not documented; two earlier versions assumed it and corrected with shape-size maths and `SetBodyTransform`, and in the game the cone still stood about 20 m beside the smoke. Now a probe of the cone model is spawned once and its world bounds are read in the same tick (`GetShapeBounds`, the way the game's own spawn menu places things), every layer is spawned from that offset and checked by its bounds (spawned again once if it is off), and nothing is moved afterwards. Smoke, lava, the crater light and the bombs come from the cone's measured bounds, so they cannot drift apart from the cone. Players and loose objects standing on the spot are pushed out first. Grinding sound, dust ring, shaking.
2. **Rumble** (a quarter of the eruption time): smoke column, tremors (impulses to loose objects around, 20 per physics step), the lava streams and crater start to glow (`SetShapeEmissiveScale` on the server-spawned layer shapes).
3. **Eruption** (three quarters of the time): heavy lava bombs (about 6 per second times the strength) are thrown from the crater in arcs; on landing each punches a real crater (`MakeHole` 2.6 / 2.0 / 1.0 m, so brick and even hard materials break), every third one also explodes, and three fires are lit around it so they spread. A quarter of them are lava flows that roll down the slopes from inside the crater rim, breaking and burning what they roll through. Glowing smoke trails, a spark fountain, crater light, ash falling around you, roar and rumble.
4. **Final blast**: size-4 explosion at the crater and a ring of five more, a big hole that takes the summit off, a burst of 12-36 bombs, and a blast front that runs out to 2.5 cone radii: loose things are thrown, two rings of size-4 explosions go off, and destruction probes level what stands there (holes 4.8 m near the cone down to 2.4 m at the edge, hard materials in the inner half, fires).
5. **Cooling** (15 s): the glow fades; landed bombs fade out and vanish after 20 s. The dead cone stays until you press R.

Budgets per physics step: at most 1 bomb spawned (2 during the burst), 6 bomb craters, 6 fires, 20 tremor impulses, 2 explosions, 44 particles; the blast front 40 holes / 100 probes / sum of hole radius² 900, 30 thrown bodies; at most 40 bombs alive; up to 4 volcanoes' cones kept (older ones are removed when a fifth is raised).

## Options

| Setting | Default | Key |
|---|---|---|
| Size small 22 m / medium 29 m / large 44 m (base width) | medium | `savegame.mod.size` |
| Eruption strength x0.5-x2 | x1 | `savegame.mod.strength` |
| Eruption length 20-120 s | 45 s | `savegame.mod.duration` |
| Fires | on | `savegame.mod.fire` |
| Ash fall | on | `savegame.mod.ash` |
| Debug line (for testing) | on | `savegame.mod.debug` |

The debug line (bottom left while a volcano is active) shows `volcano: click x y z | cone body x y z | cone bounds centre x y z (width x height) | smoke x z | off d m`: where you clicked, the cone body's position, the centre of the cone's world bounds, where smoke and lava come from, and how far the cone stands from the click.

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\volcano" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

`tests/scenarios.lua` (43 checks, one VM and split server/client): layers, server-only building and glow, tremors, bombs, craters, fires, bomb cap, blast, cooling, RMB, R, one volcano at a time, options, Russian. `tests/anchor_law.lua` models the game's spawn (pivot at the bottom-face centre, transform reported one tick late) and checks with numbers: the cone's footprint centre, the smoke and the bombs are within 0.5 m of the clicked point (measured 0.00 m), flows start inside the crater rim, 128-170 craters with 25+ of radius 2 m or more, 73-80 % of a block town within the blast radius gone, none beyond 1.4 x. `tests/anchor_corner_law.lua` repeats the anchor check with a corner pivot. `tests/anchor_mv_law.lua` and `tests/anchor_mv_corner_law.lua` model the in-game failure (vox centred or at a corner, the shape keeping the model's own axes, static bodies that cannot be moved): the old code put the cone 20.65 m from the click with the smoke on the click, exactly like the report; now the cone's bounds centre, the smoke and the bombs are within 0.5 m of the click (0.00 m) and the debug line is on screen. Not checked offline: how the rising layers look on real terrain.
