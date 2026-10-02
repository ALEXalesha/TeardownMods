# Portal Gun (Teardown mod)

Blue and orange portals. Russian: [README.ru.md](README.ru.md).

| Input | Action |
|---|---|
| LMB | place the blue portal |
| RMB | place the orange portal |
| R | close both portals |

## What the API allows (checked against `script_defs.lua`)

| Capability | Result |
|---|---|
| Teleport the player and keep momentum | yes: `SetPlayerTransformWithPitch` (it zeroes velocity) followed by `SetPlayerVelocity` with the velocity rotated into the exit frame; the view (yaw and pitch) is rotated the same way |
| Teleport dynamic bodies | yes: `SetBodyTransform` + `SetBodyVelocity` + `SetBodyAngularVelocity`, all rotated |
| See through a portal | **no**: there is no render-to-texture, mirror or camera feed function (in-world screens only run UI scripts). The portal surface is an animated swirl (`DrawSprite`, two counter-rotating layers, additive) with a pulsing glowing rim, rim sparks and a coloured light |

## How it works

- Placement: a ray from the eye (100 m by default). The spot must be flat and solid over the portal's size (four rays around the centre must hit the same plane within 12 cm, normals within ~25°) and free in front; it cannot overlap the other portal. Static surfaces only by default (option: allow moving objects, the portal then follows its body). Failures fizzle with a sound and sparks.
- Frame: on walls the portal's "up" is world up; on floors and ceilings "up" is the view direction, so floor-to-wall trips come out the way you were facing.
- Crossing: entering A along its normal and leaving B is the mapping local (x, y, z) -> (-x, y, -z). Positions, velocities and rotations go through it. Exits get at least 2 m/s (player) / 1 m/s (bodies) out of the portal so nobody gets stuck in it.
- Player: the capsule point (feet, centre or head) nearest the portal plane must come within 0.5 m inside the portal outline while not moving away. Standing on a floor portal drops you through.
- No ping-pong: after every teleport the player and every body get their own 1 s cooldown, and they must also step at least 1 m away from the exit portal before that portal can take them again.
- Bodies: checked every physics step near each portal, with a one-step look-ahead so fast throws are caught before they bounce off the wall. A body passes if its extent fits the portal outline and its centre of mass comes within its own half-thickness + 15 cm of the plane. Bodies bigger than the portal simply hit the wall (no half-in, half-out state). Vehicles are not teleported (wheels are separate bodies). Mass limit 500 kg (option).
- Surface destroyed: every 0.25 s three rays check that the surface under the portal is still there; if not, the portal closes with a sound.

Sounds: two firing sounds, open, close, pass-through, fizzle, and a hum loop at each open portal.

## Options

| Setting | Default | Key |
|---|---|---|
| Range 20-200 m | 100 m | `savegame.mod.range` |
| Portal size small / normal / large | normal | `savegame.mod.size` |
| Objects pass through | yes | `savegame.mod.bodies` |
| Heaviest object 50-3000 kg | 500 | `savegame.mod.masslimit` |
| Portals on moving objects | no | `savegame.mod.dynamic` |
| Portal hum volume | 0.5 | `savegame.mod.hum` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\portal-gun" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Portal Gun -> enable; the tool "Portal Gun" is in the last tool group.
