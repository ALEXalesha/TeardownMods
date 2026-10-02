# Teardown mods: shared tooling

Helpers used by every mod of this repository (`<mod>/tools`).

| File | What it does |
|---|---|
| `tdlib/voxio.py` | MagicaVoxel `.vox` writer and reader (several named shapes, palette, MATL materials) |
| `tdlib/synth.py` | numpy sound synthesis, OGG Vorbis export through ffmpeg, sound checks (length, clipping, loop seam) |
| `tdlib/render.py` | isometric voxel renderer for previews and icons |
| `tdlib/art.py` | preview helpers: gradients, glow, text, voxel debris, JPEG under 1 MB, UI textures |
| `tdlib/apidoc.py` | look up a function in the game's `data/script_defs.lua` |
| `tdlib/palette.py` | Teardown material ranges by palette index, read from the game's annotated `data/built-in/palette.vox` (NOTE chunk): glass 1-8, grass 9-24, dirt 25-40, rock 41-56, wood 57-72, concrete 73-88, brick 89-104, plaster 105-120, weak metal 121-136, heavy metal 137-152, plastic 153-168, hard metal 169-176, hard masonry 177-184, reserved 185-224, unphysical 225-240, reserved 241-255. `python palette.py` re-checks them against the game file |
| `tdlib/check_mod.py` | static mod check: Lua 5.1 compile, API names against script_defs, `MOD/` paths, info.txt, and that world-spawned vox files use real material indices (not reserved/unphysical) |
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
