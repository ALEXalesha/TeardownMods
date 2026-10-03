# Volcano (Teardown mod)

Raise a volcano and watch it erupt. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB on the ground | raise a volcano there (kept at least its radius + 4 m away from you) |
| RMB during the rumble or eruption | final blast right now |
| R (nothing erupting) | remove all cones |

## Phases

1. **Growth** (about 5 s): seven rock layers of the cone (own voxel models, palette range "rock") are spawned static one after another, each below its place, and lifted into it with `SetBodyTransform` (like the game's elevators). Players and loose objects standing on the spot are pushed out first. Grinding sound, dust ring, shaking.
2. **Rumble** (a quarter of the eruption time): smoke column, tremors (impulses to loose objects around, 20 per physics step), the lava streams and crater start to glow (`SetShapeEmissiveScale` on the server-spawned layer shapes).
3. **Eruption** (three quarters of the time): lava bombs (dynamic bodies, about 3 per second times the strength) are thrown from the crater in arcs; a sudden stop is a landing: `MakeHole` crater, fire, impact sound, light damage within 2.5 m. A quarter of them are lava flows that roll down the slopes from the rim and set fires where they stop. Glowing smoke trails, a spark fountain, crater light, ash falling around you, roar and rumble.
4. **Final blast**: size-4 explosion at the crater and a ring of five more, a big hole that takes the summit off, and a burst of 8-24 bombs launched 2 per step.
5. **Cooling** (15 s): the glow fades; landed bombs fade out and vanish after 20 s. The dead cone stays until you press R.

Budgets per physics step: at most 1 bomb spawned (2 during the burst), 3 craters, 2 fires, 20 tremor impulses, 44 particles; at most 30 bombs alive; up to 4 volcanoes' cones kept (older ones are removed when a fifth is raised).

## Options

| Setting | Default | Key |
|---|---|---|
| Size small 22 m / medium 29 m / large 44 m (base width) | medium | `savegame.mod.size` |
| Eruption strength x0.5-x2 | x1 | `savegame.mod.strength` |
| Eruption length 20-120 s | 45 s | `savegame.mod.duration` |
| Fires | on | `savegame.mod.fire` |
| Ash fall | on | `savegame.mod.ash` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\volcano" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

`tests/scenarios.lua` (43 checks, run both in one VM and split server/client): layers appear one by one and end aligned and static, only the server builds and lights the cone, tremors, bombs launched, craters, fires, bomb cap, blast and summit hole, cooling and clean-up, RMB blast, R removal, one volcano at a time, options, Russian. Not checked offline: how the rising layers look against real terrain, and whether "rock" breaks under the blast the way the hole radii assume.
