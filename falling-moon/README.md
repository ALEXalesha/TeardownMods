# Falling Moon (Teardown mod)

Call the moon down. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB | mark the impact point (aim point; if it is closer than 25 m or nothing is hit, 80 m ahead on the ground) and start the fall |
| RMB during the approach | send the moon back (it recedes over 4 s) |

## Timeline

1. **Approach** (1-5 min, default 2): the moon - a sphere of 30, 45 or 60 m radius (option) - comes in from 41 radii away, accelerating like something falling. It is a camera-facing sprite (`DrawSprite`) the whole way: opaque, sphere-shaded (light and terminator, limb darkening, maria, craters lit on one side), **depth-tested** so trees and buildings in front of it hide it, kept within 300 m of the camera and scaled to the angular size the real sphere has at its real distance, with an orange heat glow on its edge that grows as it comes. A countdown runs at the top (can be hidden), beeps in the last 10 s, a roar in the last 6 s.
2. **Escalation** (from 35% of the time): tremors (impulses to dynamic bodies within 60 m of the players, 30 per physics step), from 50% light objects (< 80 kg) lift and drift in a wind blowing away from the moon; growing camera shake, dust lifted from the ground around you, rumble and wind loops rise, a red screen wash. **The sky is not touched** while the moon flies: the flicker reported after the first version came from rewriting three sky properties (`skyboxtint`, `fogColor`, `sunColorTint`) every 0.5 s. The optional red sky is written once when the moon is called and restored once at the end.
3. **Impact**: a blinding flash, seven size-4 `Explosion`s (centre and around the moon), the **voxel moon** spawned once in its crater (a hollow shell of 230k voxels of rock, tagged `unbreakable nocull` like the game's own prefab parts, static, never moved through the sky; its real centre is measured from the next tick and corrected onto the aim point), a **crater** dug around it (`MakeHole` tiles from its rim out to 1.6 radii, 0.45 radii deep at the rim, hard materials included) and a **shockwave ring** on the ground.
4. **Shockwave**: rolls outwards at 60 m/s up to the radius (200 m by default). Bodies in reach are thrown outwards and up hard. Behind the front a **destruction worker** works through the swept area: each probe takes a random point in the band (weighted to the ground floors, so buildings lose their supports and collapse), finds the nearest solid thing within 3.5 m and punches a hole there - 9.1 m near the centre down to 4.9 m at the edge with the Total level, hard materials too within 45% of the radius; open ground is skipped. Explosions ride the inner part of the front, fires start along it. The work is budgeted per physics step (holes up to a total of 1100 m² of radius squared, at most 60 holes and 140 probes), so the collapse keeps going behind the front for a few seconds instead of freezing the game. Players are pushed and damaged once when the front passes them; a rolling dust cloud follows the front.
5. **Aftermath** (30 s): settling dust, the rumble fades.

## Options

| Setting | Default | Key |
|---|---|---|
| Time until impact 60-300 s | 120 s | `savegame.mod.duration` |
| Shockwave radius 50-300 m | 200 m | `savegame.mod.radius` |
| Damage to players off / normal / deadly | normal | `savegame.mod.damage` |
| Fires | on | `savegame.mod.fire` |
| Red sky (set once, restored once) | off | `savegame.mod.redsky` |
| Tremors and wind | on | `savegame.mod.tremors` |
| Countdown | show | `savegame.mod.countdown` |
| Destruction strong / heavy / total | total | `savegame.mod.destruction` |
| Moon size 30 / 45 / 60 m | 45 m | `savegame.mod.moonsize` |

## Tests

`tests/moon_law.lua` builds a city of 2 m blocks over the whole 200 m radius and models the game's spawn (pivot at the bottom-face centre, transform reported one tick late). It checks with numbers: no environment write at all during the event with the default settings, no voxel body moved through the sky, every moon sprite depth-tested and opaque and drawn the whole approach, the voxel moon in its crater on the aim point (0.00 m off), never moved after settling, unbreakable; 100 % of the blocks destroyed within half the radius and 98-99 % within the radius (thresholds 95 % / 88 %), hard pillars 100 % (70 %), 0 % beyond 1.1 x radius, bodies thrown at 25+ m/s, per-step work within budget, a shockwave ring drawn. `tests/env_law.lua` turns the red sky on: each sky property is written exactly twice (apply, restore), only by the server, and restored exactly, also when the moon is sent back. `tests/moon_corner_law.lua` checks the moon's placement with a corner pivot. Each check fails when the matching part of the code is broken (mutation check). Not measurable offline: the frame cost of the holes on a big map - if the game hitches, pick a lower destruction level or a smaller moon.

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\falling-moon" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Falling Moon -> enable; the tool "Moon Caller" is in the last tool group.
