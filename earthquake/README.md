# Earthquake (Teardown mod)

A seismic detonator for Teardown 2.x. Russian: [README.ru.md](README.ru.md).

- **LMB** starts a quake at the aim point (or under the player, see options). LMB again stops it.
- **RMB** cycles the preset: Weak, Moderate, Strong, Severe, Catastrophic.

What a quake does:

- dynamic bodies and vehicles in the radius get the ground's velocity changes as impulses (pushed slightly off-centre, so things rock and tip over); heavy bodies get less;
- the player is jolted while standing on the ground (Moderate and up), the camera shakes, a rumble loop plays, cracks sound around;
- dust rises from the ground and grit falls from ceilings around the player;
- structural damage in a budget: random probes near structures, `MakeHole` only on allowed materials:
  Moderate cracks glass, wood, plaster, plastic; Strong adds concrete, brick and weak metal; Catastrophic also bites hard metal and hard masonry.
  Weak buildings then fail through Teardown's own structural physics;
- joints (hinges, ropes, ball joints) of shaken bodies are detached with a chance that grows with the preset;
- optional aftershocks (2-3, weaker and shorter, 8-22 s apart).

The shaking is a deterministic function of time and a seed, so the server (forces) and the
client (camera shake, seismograph HUD) agree without streaming data.

## Options

| Setting | Range | Default | Key |
|---|---|---|---|
| Duration | 5-60 s | 15 s | `savegame.mod.duration` |
| Starting preset | Weak..Catastrophic | Strong | `savegame.mod.preset` |
| Radius | 20-150 m | 60 m | `savegame.mod.radius` |
| Aftershocks | yes / no | yes | `savegame.mod.aftershocks` |
| Structural damage | yes / no | yes | `savegame.mod.damage` |
| Camera shake | x0-x2 | x1 | `savegame.mod.shake` |
| Epicentre | aim point / under the player | aim point | `savegame.mod.atplayer` |

## Performance budget

- one `QueryAabbBodies` every 0.25 s, up to 220 tracked bodies, 55 impulses per physics step (round robin);
- holes: 1-5 `QueryClosestPoint` probes per physics step, at most 450 holes per quake;
- joints: one check every 0.3 s, at most 2 detached joints per check;
- particles: up to 16 per physics step near the player.

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\earthquake" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

In the game: Mod Manager -> Local files -> Earthquake -> enable; the tool is "Seismic Detonator" in the last tool group.
`build_all.py` regenerates the model, sounds, preview and options screen, then runs the static check and the harness
(`tests/scenarios.lua`, about 3400 frames, host and split server/client modes). See `../_shared/README.md`.
