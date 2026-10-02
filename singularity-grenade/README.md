# Singularity Grenade (Teardown mod)

A throwable tool for Teardown 2.x. The grenade flies as a physical body,
bounces, and then rises and opens into a short-lived singularity:

- it pulls loose dynamic bodies, debris and players towards its core (the pull falls off with distance, heavy bodies resist);
- bodies that reach the core are squeezed onto a tight spinning orbit;
- it punches small holes in glass, wood, plastic, plaster and foliage around it (metal, concrete, brick and rock are not touched);
- after a few seconds it implodes and collapses: a white flash, an outward blast that throws everything it gathered, and a scorch mark.

Russian version: [README.ru.md](README.ru.md).

## Controls

| Input | Action |
|---|---|
| Hold LMB, release | Throw. Holding longer (up to 1 s) throws farther |
| RMB | Short toss at your feet (ignored while you look at a body you can grab) |

The grenade opens 1.5 s after it comes to rest (default) or right after the first hit (option).
Ammo: 5 by default, no reload. In sandbox the game gives unlimited ammo and the mod does not spend it.
At most 4 grenades can exist at once; the HUD says so when you hit the limit.

## Options (Mod Manager -> Singularity Grenade -> Options)

| Setting | Range | Default | Registry key |
|---|---|---|---|
| Radius | 3-20 m | 8 m | `savegame.mod.radius` |
| Strength | x0.2-x3 | x1 | `savegame.mod.strength` |
| Duration | 1-15 s | 4 s | `savegame.mod.duration` |
| Grenades | 1-50 | 5 | `savegame.mod.ammo` |
| Opens | after stopping / on impact | after stopping | `savegame.mod.impact` |
| Pulls the player | yes / no | yes | `savegame.mod.pullplayer` |
| Damage to players | off / low / high | low | `savegame.mod.damage` |
| Tears weak materials | yes / no | yes | `savegame.mod.tear` |
| Real explosion at the end | yes / no | no | `savegame.mod.blast` |

Radius, strength, duration and the trigger mode are read on every throw, so changes apply to the next grenade.
Ammo is applied when the level starts.

## Install for local testing

The built mod is the `mod/` folder. Link it into Teardown's local mods folder:

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\singularity-grenade" -Target "$PWD\mod"   # run inside the mod folder
```

In the game: Mod Manager -> Local files -> Singularity Grenade -> enable. The tool appears in the
tool bar (scroll wheel / number keys, last group).

## Layout

```
mod/                 the mod as Teardown loads it
  info.txt           name, description (EN/RU), tags, preview
  main.lua           tool logic (#version 2: server.* / client.* / shared)
  options.lua        options screen
  prefab/tool.xml    hand-held tool: vox + first/third person poses + hand IK point
  vox/grenade.vox    generated model: core + two gimbal rings (3 shapes)
  snd/*.ogg          generated sounds (mono Vorbis 44.1 kHz)
  ui/                icon, vignette, slider dot
  preview.jpg        generated preview (1024x576)
tools/               generators: build_vox.py, build_sounds.py, build_images.py, build_all.py
tests/scenarios.lua  offline harness scenarios
```

Shared helpers live in `../_shared` (vox writer/reader, sound synth, voxel renderer, harness).

## Build and test

```powershell
cd <repo>\_shared
python -m venv .venv
.venv\Scripts\python -m pip install lupa numpy pillow
cd ..\singularity-grenade
..\_shared\.venv\Scripts\python tools\build_all.py
```

`build_all.py` regenerates the model, sounds and images, runs the static check
(`check_mod.py`: Lua 5.1 compile, every API call exists in `script_defs.lua`, every
`MOD/` file exists, info.txt) and the harness (`run.py`), which runs the real
`main.lua` and `options.lua` against a fake engine built from `script_defs.lua`
for about 4800 frames, twice: in one Lua VM and with separate server/client VMs.
ffmpeg with libvorbis must be in PATH for the sounds.

## Performance budget

- one `QueryAabbBodies` per singularity every 0.2 s, at most 120 tracked bodies;
- at most 40 bodies get an impulse per physics step per singularity (round robin, impulse scaled so the average force stays right);
- holes: 2 rays every 0.12 s (4 rays every 0.05 s during the implosion), at most 48 holes per grenade;
- collapse blast is spread over several physics steps, 50 bodies per step, 160 max;
- particles: at most 40 per physics step across all singularities, plus an 80-particle burst at the collapse.

## Known limits

- Teardown's HUD shows only names for mod tools, so the icon is used in the mod's own UI and preview only.
- The tool is tested offline only; physics feel (pull strength, orbit, blast) may need tuning in the game.

## For other mods

Other scripts can drop a Singularity Grenade (the camera drone mod does) through the registry:
write `level.singularity_grenade.req.<n>.x/y/z/vx/vy/vz` (floats) and `.owner` (int), then set
`level.singularity_grenade.reqcount` to `n`. This mod spawns the grenade on its next tick without
spending ammo and clears the keys. It sets `level.singularity_grenade.available = true` when loaded.

## Multiplayer authority

The grenade body is spawned by the server, so in `#version 2` only server code changes it: the glow (`SetShapeEmissiveScale`) is set on the server from the grenade phase and fuse; clients only read the body and add lights, particles, sounds and camera effects.
