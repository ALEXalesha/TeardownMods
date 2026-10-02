# Cutter (Teardown mod)

An angle grinder for Teardown 2.x. Russian: [README.ru.md](README.ru.md).

**Hold LMB on a surface, sweep to the end point, release.** A dashed preview line shows the cut while you hold;
a red dot marks where the saw points. After release the saw cuts a straight kerf from the press point to the release point.

How the cut works:

- the line is split into points every 1.1 kerf radii; for each point a ray finds the real surface (the line may cross bumps and gaps);
- at each point the saw marches into the material along the surface normal with small `MakeHole` calls until two steps in a row remove nothing (it came out the other side) or the max depth is reached;
- materials: soft ones (glass, wood, plastic, plaster, foliage) always; metal (weak) and concrete/brick use the "medium" radius; they are one class for `MakeHole`, so the mod tells them apart per point with `GetShapeMaterialAtPosition`. Concrete and brick cost 3x budget (cut slower). Hard metal and hard masonry are off by default;
- budget: 12 cost units per physics step per cut (option), up to 4 queued cuts per player.

Effects: spinning disc on the hand model, sparks on metal and concrete, sawdust on wood, dust on concrete,
a motor whine loop, spin-up / spin-down sounds, a grinding loop whose pitch depends on the material, a small light at the cut.

## Options

| Setting | Default | Key |
|---|---|---|
| Kerf width 0.1-0.4 m | 0.2 m | `savegame.mod.kerf` |
| Max depth 0.2-3 m | 1 m | `savegame.mod.depth` |
| Max cut length 0.5-10 m | 4 m | `savegame.mod.maxlen` |
| Reach 2-15 m | 6 m | `savegame.mod.reach` |
| Holes per step (speed) 4-40 | 12 | `savegame.mod.budget` |
| Cuts metal | yes | `savegame.mod.metal` |
| Cuts concrete and brick | yes | `savegame.mod.masonry` |
| Concrete is slower by x1-x6 | x3 | `savegame.mod.masonrycost` |
| Cuts hard metal | no | `savegame.mod.hard` |
| Sparks and dust | yes | `savegame.mod.sparks` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\cutter" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Cutter -> enable; the tool "Cutter" is in the last tool group.
