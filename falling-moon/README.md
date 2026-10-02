# Falling Moon (Teardown mod)

Call the moon down. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB | mark the impact point (aim point; if it is closer than 25 m or nothing is hit, 80 m ahead on the ground) and start the fall |
| RMB during the approach | send the moon back (it recedes over 4 s) |

## Timeline

1. **Approach** (1-5 min, default 2): the moon grows in the sky. It is a camera-facing sprite (`DrawSprite`, own crater texture plus a glow), kept within 450 m of the camera and scaled so its angular size matches a moon at the simulated distance, so it is not cut by the draw distance. A countdown runs at the top (can be hidden), beeps in the last 10 s, a roar in the last 6 s.
2. **Escalation** (from 35% of the time): tremors (impulses to dynamic bodies within 60 m of the players, 30 per physics step), from 50% light objects (< 80 kg) start to lift and drift in a wind blowing away from the moon; camera shake, rumble and wind loops rise; the sky turns red through `SetEnvironmentProperty("skyboxtint" / "fogColor" / "sunColorTint")` (server code, like the game's own weather; the original values are read at the start and restored at the end) plus a red screen wash.
3. **Impact**: a blinding flash, `Explosion` size 4, a big crater (`MakeHole` 8 / 6 / 3.5 m) and a glowing lunar boulder (own voxel model, spawned static, half buried).
4. **Shockwave**: rolls outwards at 120 m/s up to the radius (150 m by default). All bodies in reach are collected once and sorted by distance; each physics step the front throws the ones it has reached (max 80 per step) outwards and up, punches holes along the front (8 probes per step, smaller further out), starts fires near the centre, pushes and damages players once when it passes them. A rolling dust cloud follows the front.
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

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\falling-moon" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Falling Moon -> enable; the tool "Moon Caller" is in the last tool group.
