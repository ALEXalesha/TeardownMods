# Gravity Change (Teardown mod)

Switch the gravity of the whole level. Russian: [README.ru.md](README.ru.md).

| Key | Action |
|---|---|
| G (tap; K in the options) | next preset: Earth -> Moon -> Mars -> zero-G -> reverse -> sideways -> Earth |
| G (hold 0.8 s) | back to Earth |
| Space / Ctrl in zero-G | float up / down |

| Preset | Gravity |
|---|---|
| Earth | (0, -10, 0), Teardown's default |
| Moon | -1.62 m/s² |
| Mars | -3.71 m/s² |
| Zero-G | 0 |
| Reverse | +4 m/s² up (option 1-10) |
| Sideways | 6 m/s² towards your right at the moment you pick it (option 2-10) |

## How it works

- Real gravity: `SetGravity` on the scene (server code only: the `script_defs.lua` example uses `server.tick`; the harness now flags client calls). The change is a smooth blend over 1.5 s (option 0-5 s). The game resets gravity when the level restarts. If the scene gravity is reset while the mod still has another preset chosen (the script state survives, for example a quick load), the server sets the preset again on the next tick; on Earth the mod never touches the scene gravity (law `tests/quickload_law.lua`).
- Resting bodies are asleep and would ignore a new gravity, so the mod wakes the dynamic bodies within 60 m of the players with `SetBodyActive`, 40 per tick, after scanning once per second.
- The player follows the scene gravity (lower jumps feel floatier on the Moon by themselves). In zero-G the player is kept upright with `SetPlayerOrientation` and Space / Ctrl push up and down with a little drag.
- Indicator (top right): preset name, strength in g, an arrow pointing to where "down" is from your view (a ring in zero-G) and the transition progress. Floating dust motes appear around you when gravity is low, a soft hum plays in zero-G, and a rising or falling sweep marks each change.
- Optional automatic return to Earth after 10, 30 or 60 s, handy for reverse gravity.

## Options

| Setting | Default | Key |
|---|---|---|
| Key G / K | G | `savegame.mod.key` |
| Transition 0-5 s | 1.5 s | `savegame.mod.trans` |
| Reverse strength | 4 m/s² | `savegame.mod.reverse` |
| Sideways strength | 6 m/s² | `savegame.mod.sideways` |
| Back to Earth after | never | `savegame.mod.autoreturn` |
| Wake objects within | 60 m | `savegame.mod.wakeradius` |
| Zero-G thrusters | on | `savegame.mod.thrusters` |
| Indicator | show | `savegame.mod.indicator` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\gravity" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Gravity Change -> enable. It is not a tool; the key works with anything in hand.
