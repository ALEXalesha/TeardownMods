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
| `tdlib/keymap.py` | every keyboard key of every mod and where it works (always / with the tool / in the replay / flying / driving), and the law that no key does two things when several mods are on: an always-active key (and every choice of it in the options) is used nowhere else, no mod takes the game's keys, the table matches each `main.lua` and `options.lua`; it has a self-test that plants each clash. `--readme` writes the key tables in the top-level READMEs. Part of `ci_all.py` |
| `harness/engine.lua` | fake Teardown engine (registry, bodies, players, tools, queries, simple physics, UI) |
| `harness/driver.lua` | frame loop (server/client callbacks, shared sync, ServerCall/ClientCall), scenario API `T` |
| `harness/run.py` | runs a scenario twice: one VM (host) and split server/client VMs |

Every API call made by a mod goes through a checker generated from `script_defs.lua`:
unknown functions, missing required arguments, wrong basic types (number, string, boolean,
TVec, TQuat, TTransform), NaN, Ui* calls outside draw, client writes to `shared` and missing
`MOD/` files are reported as errors. Per-frame call counts are kept for budget checks.

Authority model (`#version 2`): every entity belongs to the side that created it. Level entities and everything spawned from server code are server-authored; a mutating call from client code on them (`SetShapeEmissiveScale`, `SetShapeLocalTransform`, `SetBodyVelocity`, `Delete`, `SetTag` and the rest of `H.MUTATING`, 47 functions) raises the game's error "invalid attempt to access server authored entity from client script" and aborts the callback, like the game does. Tool bodies are client-local. Server-only functions (`H.SERVER_ONLY`, currently `SetTimeScale`, `SetGravity` and `SetEnvironmentProperty`) called from client code are reported because the game silently ignores them. `harness/selftest/` checks the model itself. Spawned `.vox` files create one shape per model with the real size, so code that finds shapes by size is exercised. A Spawn text with several top-level elements is an error, and only the first element is spawned, like the game does (in-game 10.10: the catapult's frame and arm side by side came out as the frame alone); several bodies go into one `<prefab><group>...</group></prefab>` document. Voxel content is modelled as a name (`H.contentOf(shape)`): `CopyShapeContent` copies it, `ClearShape` empties it, and the destruction model `H.breakShape(shape, n, pos, vel)` takes n voxels out of a shape in place (all of them: the shape is gone) and throws them off as a new dynamic body with a higher handle, like the game; `QueryAabbShapes` also returns shapes a script created on the world body and never deleted ones. Test knobs: `H.spawnModel.maxBodies` (a partial spawn), `H.noGround` (no ground plane), `H.printed` (what scripts `print`, which the game writes to its log).

Setup:

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install lupa numpy pillow
```

Nothing here starts the game.
