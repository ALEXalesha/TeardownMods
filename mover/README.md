# Mover (Teardown mod)

A gizmo gun for Teardown 2.x that moves things. Russian: [README.ru.md](README.ru.md).

| Key | Action |
|---|---|
| Hold LMB | grab the aimed dynamic body (props, debris, vehicles); release drops it |
| Mouse wheel | push / pull along the view (tool switching is locked while holding) |
| Q / R | rotate around the vertical axis |
| Z / X | tilt (pitch) |
| V / B | roll |
| T | freeze the aimed or held body in place / unfreeze |
| G | clone the body next to the original |
| N / M | resample voxels x0.5 / x2 (experimental, small objects) |
| U | undo the last move, freeze or clone |

The held body has a cyan outline and a beam from the gun, frozen bodies a blue outline,
the aimed body a white one. A panel on the right lists the keys (can be hidden).

## How it works (and what the API allows)

- Dynamic bodies are carried with `ConstrainPosition` + `ConstrainOrientation` in `server.update`, so they still collide.
  Vehicles are moved by their main body (`GetVehicleBody`), the wheels follow through their joints.
- Freeze uses `SetBodyDynamic(body, false)`; frozen bodies are carried with `SetBodyTransform`.
  Static level geometry (buildings that were never dynamic, terrain) is **not** grabbable: turning
  the world body dynamic would wreck the level, so the mod refuses.
- Clone: `Spawn` of a 1-voxel static placeholder body, then `CreateShape` + `CopyShapeContent` for every shape,
  placeholder deleted, body made dynamic. Joints, lights and scripts of the original are not copied; vehicles are refused.
- Scale: Teardown has no API to change a shape's voxel size. The mod resamples instead: a new shape is
  created with `CreateShape`/`ResizeShape`, voxels are read with `GetShapeMaterialAtIndex` and written in runs with
  `SetBrush` + `DrawShapeBox` (x2: every voxel becomes 2x2x2; x0.5: one voxel per 2x2x2 block). The job is spread over
  physics steps (2500 voxel reads per step) with a progress bar; limits: 8 shapes, 60 000 source cells, 128 voxels per side.
  The new body keeps the old one's bottom centre.
- Undo keeps the last 12 entries per player (move, freeze, clone). Scaling is not undoable.
- Input is read on the client (raw keys are not replicated) and sent with `ServerCall`; the server owns the state.

## Options

| Setting | Default | Key |
|---|---|---|
| Max distance 5-100 m | 40 m | `savegame.mod.maxdist` |
| Move speed 5-40 m/s | 20 | `savegame.mod.speed` |
| Position snap off/0.1/0.25/0.5/1 m | off | `savegame.mod.possnap` |
| Rotation snap off/15/45/90° | off | `savegame.mod.rotsnap` |
| Rotation speed 30-360°/s | 90 | `savegame.mod.rotspeed` |
| Cloning | on | `savegame.mod.clone` |
| Scaling | on | `savegame.mod.scale` |
| Controls panel | show | `savegame.mod.help` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\mover" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Mover -> enable; the tool "Mover" is in the last tool group.
