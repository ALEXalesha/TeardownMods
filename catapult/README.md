# Catapult (Teardown mod)

A giant wooden trebuchet that throws boulders, barrels, cars, crates and you. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB | place a catapult 14 m in front of you, facing where you look (up to 4) |
| F, or E on the machine | fire (E works with any tool in hand) |
| Mouse wheel | power (tool switching is locked while a catapult is selected) |
| Z / C | turn the machine left / right |
| X / V | lower / raise the angle (20-70°, default 45°) |
| 1 2 3 4 | load a boulder / explosive barrel / car / pile of crates |
| RMB | load the selected ammo |
| R | remove all catapults and the ammo they spawned |

The catapult you are nearest to (within 40 m) is selected: it gets an outline, the HUD shows power, angle, ammo and state, and a dashed **arc preview** with a ring shows where the load will land (and the range in metres).

## How it is built

- One prefab spawned in front of you: a **static wooden frame** (about 13 m tall with the counterweight up, real destructible voxels) with an iron axle, and the **arm** - a dynamic body made of a cube hub, a 14.4 m beam, a bucket and a hollow counterweight - hanging on a **real hinge joint** (`<joint type="hinge">` in the hub, the way the game's own prefabs hang doors and lids). Where the game puts a spawned vox relative to its `pos` is not documented: the first version assumed the centre of the bottom face and in the game the frame sank half into the ground, the axle floated above it and the arm was thrown away. Now a small probe model is spawned for one tick before each placement and its world bounds are read at once (`GetShapeBounds`, like the game's own spawn menu does), which gives the pivot per axis and which model axis points up; every part and the hinge are placed from that measurement. The arm and the frame are told apart by being dynamic / static, the axle and the bucket by their sizes in any axis order; if anything is missing, everything spawned is deleted again. Aiming uses the real geometry measured from world bounds (axle centre, bucket).
- **Firing**: the hinge motor (`SetJointMotor`) swings the arm. The hinge's sign convention is not documented, so after 0.06 s the mod checks which way the arm went and reverses once if needed. Everything in the bucket - bodies and players - is held to the bucket while it swings (`ConstrainPosition`; players by position) and released when the bucket's motion points along the set angle (the arm 90° minus the angle above the horizontal, behind the axle), or after a timeout if the motor does not get there. At the release every load gets exactly the planned speed, 14 m/s at power 0 to 56 m/s at full power, so range and the arc preview agree. Right after the release the motor brakes so the bucket cannot catch the load; after half a second it returns the arm to rest (`SetJointMotorTarget`) and the catapult reloads (option).
- **Ammo**: boulder (1.8 m of rock), explosive barrel (explodes where it lands, but never within 12 m of the catapult), a car - the game's own small car prefab if it can be spawned, otherwise the mod's car body - and a pile of six crates. Loaded ammo is held gently in the bucket while the catapult stands. Anything else put into the bucket, including you, is thrown too; a launched player gets no fall damage by default.
- **Impacts**: losing more than 45 % of the speed in one step while flying faster than 12 m/s is a hit. Holes scale with speed and the load (boulder 1, car 0.85, barrel 0.7, crates 0.5): soft materials always, brick and concrete from 25 m/s, hard materials from 45 m/s; a boulder punches two more holes along its path. Up to 3 hits per load.
- **Breaking it and removing it**: the frame and the arm are ordinary voxels; explosions break them. If the hinge breaks or a part is destroyed, the catapult is marked broken and does not fire. Every body and shape the mod spawns is tagged (`catapult_part`, `catapult_ammo`), and R deletes everything with those tags - also pieces broken off, catapults the mod lost track of, and parts left by the first version (tags `catapult`, `catapult_arm`).

Limits: at most 4 catapults, 24 mod-spawned ammo bodies (the oldest go first), 3 cars, 24 tracked flying loads, 8 holes per physics step; the arc preview is recomputed 6-7 times a second (up to about 80 raycasts in that frame).

## Options

| Setting | Default | Key |
|---|---|---|
| Ammo at start: boulder / barrel / car / crates | boulder | `savegame.mod.ammo` |
| Reload automatically | on | `savegame.mod.reload` |
| Impact damage x0.25-x2 | x1 | `savegame.mod.damage` |
| Fall damage for a launched player | off | `savegame.mod.falldamage` |
| Arc preview | on | `savegame.mod.arc` |
| Debug line (for testing) | on | `savegame.mod.debug` |

The debug line (bottom left, while the tool is in hand and a catapult is selected) shows the measured assembly: `catapult: pivot fx fy fz | ground | frame bottom | axle (want +9.6) | bucket floor | hinge attached/BROKEN | arm m/s`, all heights relative to the frame's base.

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\catapult" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

The harness models the game's spawn (vox pivot at the bottom-face centre, transform reported one tick late) and the hinge motor. `tests/throw_law.lua`: range grows with power - 63-64, 107-109, 166-169, 239-242 and 328-330 m at power 0.2, 0.4, 0.6, 0.8 and 1.0 (at least 150 m required at full power); the load leaves at the planned speed (within 2 %), is clear of the bucket 10 frames later and nothing holds it; the arc preview lands within 5 % of the real landing; a player in the bucket flies 329 m without fall damage. `tests/assembly_law.lua` and `tests/assembly_corner_law.lua` reproduce the in-game screenshot (vox centred on its pos; and the corner variant): the frame must stand on the ground, the axle sit on it at 9.6 m, the hinge be attached and the arm hang still with the bucket above the ground - the old code fails exactly like the screenshot (frame bottom at -4.8 m, axle at 9.0 m above a 4.8 m frame, hinge not attached). `tests/removal_law.lua`: with body tags unreadable, a planted broken piece and a part of the first version, R must leave nothing (the old code left 2 bodies and could not register the catapult). `tests/impact_law.lua`: boulders hitting a wood and a brick wall at 37 m/s break holes of 18-19 m² and 10-11 m²; crates, barrel and car are thrown, the barrel explodes; E, turning and the angle work; a broken hinge stops the machine; at most 4 catapults and 24 mod ammo bodies even after six crate volleys; R removes everything. Every check fails when the matching code is broken (mutation check).

**Needs an in-game check**: whether the hinge motor really swings the 13 m arm (if it does not, the release still happens after the timeout), whether the arm rests stably between shots, and whether the game's car prefab path works.
