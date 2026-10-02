# Teardown Mods

A collection of Teardown 2.x mods (scripting API `#version 2`: `server` / `client` / `shared`).
Every mod has its own folder with the built mod in `mod/`, generators in `tools/`, offline tests in `tests/`
and its own README in English and Russian. Russian version of this page: [README.ru.md](README.ru.md).

<!-- mods -->
| Folder | Mod | What it is |
|---|---|---|
| [cutter](cutter) | Cutter | Angle grinder: cut straight kerfs through walls and vehicles. |
| [drone](drone) | Camera Drone | Deployable camera drone with bomb drop. |
| [earthquake](earthquake) | Earthquake | Seismic detonator: earthquakes from weak to catastrophic. |
| [mover](mover) | Mover | Gizmo gun: grab, rotate, freeze, clone, scale and undo. |
| [portal-gun](portal-gun) | Portal Gun | Blue and orange portals for players and objects. |
| [singularity-grenade](singularity-grenade) | Singularity Grenade | A throwable gravity grenade that opens into a short-lived singularity. |
| [time-slow](time-slow) | Time Slow | Hold a key to slow the world down. |
| [tornado](tornado) | Tornado | Spawn a wandering or steerable tornado. |
<!-- /mods -->

More mods are in progress (volcano, tsunami,
trampoline floor, gravity, falling moon, vehicle remote control, telekinesis).

## Shared tooling

[`_shared`](_shared) holds the generators and the offline test harness used by every mod:
MagicaVoxel `.vox` writer/reader, procedural sound synthesis with OGG export (ffmpeg),
an isometric voxel renderer for previews and icons, a data-driven options screen generator,
a static checker and a fake Teardown engine that runs the real mod scripts in Lua 5.1 (lupa)
against an API surface generated from the game's `data/script_defs.lua`.

```powershell
cd _shared
python -m venv .venv
.venv\Scripts\python -m pip install lupa numpy pillow
cd ..\<mod>
..\_shared\.venv\Scripts\python tools\build_all.py
```

`build_all.py` regenerates models, sounds, images and the options screen, then runs the static check
and the harness scenarios (each twice: one Lua VM, and separate server/client VMs).
The game itself is never started by these tools.

## Trying a mod locally

Link the mod's `mod/` folder into Teardown's local mods folder (run inside the mod folder):

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\<mod>" -Target "$PWD\mod"
```

Then in the game: Mod Manager -> Local files -> enable the mod.
