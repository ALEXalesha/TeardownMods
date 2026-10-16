# Telekinesis (Teardown mod)

A telekinesis gauntlet. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB (hands empty) | lift the loose objects around the aim point |
| Hold LMB (holding) | charge; release to throw them as a volley along your view |
| RMB | put them down gently |

- Pick-up: a ray finds the aim point (40 m), then the nearest dynamic bodies within 3 m of it are taken: up to 8, each up to 200 kg. Vehicles and players are never picked.
- Hover: the bodies are pulled with `ConstrainPosition` (server `update`) to slots on a slowly spinning ring 3 m in front of you; while charging the ring tightens, spins faster and comes closer.
- Throw: released one after another every 0.04 s (a volley), speed 14-54 m/s depending on the charge and the throw power, heavy objects a bit slower, with a little spread and spin.
- Energy: holding drains it - the set time (15 s) is for about 200 kg in total, a lighter load lasts longer (at most twice as long), a heavier one runs out sooner; a throw costs 5% (quick) to 15% (full charge); when it runs out the objects drop. It starts to refill 0.8 s after your hands are empty and is full again in 0.6 of the set time (9 s). Can be switched off. Law: `tests/energy_text_law.lua`.
- Held objects get a violet outline and highlight; wisps run from your hand to them, sparkles around them; a hum loop rises with the charge; the gauntlet's orb glows brighter while charging.
- Putting the tool away drops everything. Bodies are moved only by server code; clients only read them.

## Options

| Setting | Default | Key |
|---|---|---|
| Pick-up radius 1-8 m | 3 m | `savegame.mod.radius` |
| Max objects 1-20 | 8 | `savegame.mod.maxbodies` |
| Heaviest object 10-1000 kg | 200 kg | `savegame.mod.masslimit` |
| Throw power | x1 | `savegame.mod.power` |
| Reach 5-100 m | 40 m | `savegame.mod.reach` |
| Energy meter | on | `savegame.mod.energy` |
| Energy lasts 5-60 s | 15 s | `savegame.mod.capacity` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\telekinesis" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Telekinesis -> enable; the tool "Telekinesis" is in the last tool group.
