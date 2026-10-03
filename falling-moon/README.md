# Falling Moon (Teardown mod)

Call the moon down. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB | mark the impact point (aim point; if it is closer than 25 m or nothing is hit, 80 m ahead on the ground) and start the fall |
| RMB during the approach | send the moon back (it recedes over 4 s); not possible any more once it has become a real body ("Too late to stop it!") |

## Timeline

1. **Approach** (1-5 min, default 2): the moon - a sphere of 30, 45 or 60 m radius (option) - comes in from 41 radii away, accelerating like something falling. Far away it is a camera-facing sprite (`DrawSprite`): opaque, sphere-shaded (light and terminator, limb darkening, maria, craters made from a height field so each one is lit on one side), **depth-tested** so trees and buildings in front of it hide it, kept within 450 m of the camera and scaled to the angular size the real sphere has at its real distance. Within 8 radii (the last 4+ s) the server spawns the **voxel moon** in exactly that place - a hollow shell of 230k voxels (rock), tagged `unbreakable nocull` like the game's own prefab parts - and moves it every physics step until it sits in the crater, its centre a quarter radius below the impact point. From then on no sprite is drawn; the real body occludes the sun and the scenery properly. A countdown runs at the top (can be hidden), beeps in the last 10 s, a roar in the last 6 s.
2. **Escalation** (from 35% of the time): tremors (impulses to dynamic bodies within 60 m of the players, 30 per physics step), from 50% light objects (< 80 kg) start to lift and drift in a wind blowing away from the moon; camera shake, rumble and wind loops rise; the sky turns red through `SetEnvironmentProperty("skyboxtint" / "fogColor" / "sunColorTint")` (server code, like the game's own weather; the original values are read at the start and restored at the end) plus a red screen wash.
3. **Impact**: a blinding flash, seven size-4 `Explosion`s (centre and around the moon), and a **crater ring** dug around the moon (`MakeHole` tiles from its rim out to 1.3 radii, deepest at the rim, hard materials included).
4. **Shockwave**: rolls outwards at 60 m/s up to the radius (150 m by default). Bodies in reach are thrown outwards and up hard (up to 53 m/s near the centre with the default destruction level). Behind the front a **destruction worker** works through the swept area: each probe takes a random point in the band (weighted to the ground floors, so buildings lose their supports and collapse), finds the nearest solid thing within 3.5 m and punches a hole there - 7.4 m near the centre down to 3.4 m at the edge with the Total level, hard materials too within 45% of the radius; open ground is skipped. Explosions ride the inner part of the front, fires start along it. The work is budgeted per physics step (holes up to a total of 700 m2 of radius squared, at most 45 holes and 90 probes), so the collapse keeps going behind the front for a few seconds instead of freezing the game. Players are pushed and damaged once when the front passes them; a rolling dust cloud follows the front.
5. **Aftermath** (30 s): settling dust, the rumble fades, the sky slowly returns to normal.

## Options

| Setting | Default | Key |
|---|---|---|
| Time until impact 60-300 s | 120 s | `savegame.mod.duration` |
| Shockwave radius 50-300 m | 150 m | `savegame.mod.radius` |
| Damage to players off / normal / deadly | normal | `savegame.mod.damage` |
| Fires | on | `savegame.mod.fire` |
| Red sky 0-1 | 0.8 | `savegame.mod.tint` |
| Tremors and wind | on | `savegame.mod.tremors` |
| Countdown | show | `savegame.mod.countdown` |
| Destruction strong / heavy / total | total | `savegame.mod.destruction` |
| Moon size 30 / 45 / 60 m | 45 m | `savegame.mod.moonsize` |

## Tests

`tests/moon_law.lua` builds a city of 2 m blocks (hollow masonry and wood buildings, hard pillars near the centre, buildings beyond the radius) and checks with numbers: every far-moon sprite is depth-tested and opaque; the voxel moon falls for 4+ s, only gets closer, ends on the aim point and is unbreakable; at least 90 % of the blocks within half the radius and 75 % within the radius are destroyed (measured: 93-95 % and 85-86 %), at least 70 % of the hard pillars (79-83 %), at most 10 % beyond 1.1 x radius (0 %), bodies are thrown at 25+ m/s (39), per-step work stays within budget. Each of these fails when the matching part of the code is broken (mutation check). Not measurable offline: the real frame cost of moving a 230k-voxel body and of the holes on a big map - if the game hitches, pick a lower destruction level or a smaller moon.

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\falling-moon" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Falling Moon -> enable; the tool "Moon Caller" is in the last tool group.
