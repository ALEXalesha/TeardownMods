# Teardown mods: shared tooling

Helpers used by every mod of this repository (`<mod>/tools`).

| File | What it does |
|---|---|
| `tdlib/voxio.py` | MagicaVoxel `.vox` writer and reader (several named shapes, palette, MATL materials) |
| `tdlib/synth.py` | numpy sound synthesis, OGG Vorbis export through ffmpeg, sound checks (length, clipping, loop seam) |
| `tdlib/render.py` | isometric voxel renderer for previews and icons |
| `tdlib/art.py` | preview helpers: gradients, glow, text, voxel debris, JPEG under 1 MB, UI textures |
| `tdlib/apidoc.py` | look up a function in the game's `data/script_defs.lua` |
| `tdlib/check_mod.py` | static mod check: Lua 5.1 compile, API names against script_defs, `MOD/` paths, info.txt |
| `harness/engine.lua` | fake Teardown engine (registry, bodies, players, tools, queries, simple physics, UI) |
| `harness/driver.lua` | frame loop (server/client callbacks, shared sync, ServerCall/ClientCall), scenario API `T` |
| `harness/run.py` | runs a scenario twice: one VM (host) and split server/client VMs |

Every API call made by a mod goes through a checker generated from `script_defs.lua`:
unknown functions, missing required arguments, wrong basic types (number, string, boolean,
TVec, TQuat, TTransform), NaN, Ui* calls outside draw, client writes to `shared` and missing
`MOD/` files are reported as errors. Per-frame call counts are kept for budget checks.

Authority model (`#version 2`): every entity belongs to the side that created it. Level entities and everything spawned from server code are server-authored; a mutating call from client code on them (`SetShapeEmissiveScale`, `SetShapeLocalTransform`, `SetBodyVelocity`, `Delete`, `SetTag` and the rest of `H.MUTATING`, 47 functions) raises the game's error "invalid attempt to access server authored entity from client script" and aborts the callback, like the game does. Tool bodies are client-local. Server-only functions (`H.SERVER_ONLY`, currently `SetTimeScale`, `SetGravity` and `SetEnvironmentProperty`) called from client code are reported because the game silently ignores them. `harness/selftest/` checks the model itself. Spawned `.vox` files create one shape per model with the real size, so code that finds shapes by size is exercised.

Setup:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install lupa numpy pillow
```

Nothing here starts the game.
