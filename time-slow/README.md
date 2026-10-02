# Time Slow (Teardown mod)

Hold a key to slow the world down. Russian: [README.ru.md](README.ru.md).

- **H** (hold, or toggle; the key can be H, Y, T or the middle mouse button) - slow motion;
- **J** - switch the speed: x0.5, x0.25, x0.1;
- smooth ramp in and out (0.05-1.5 s, measured in real time with `GetTime`, so it does not slow itself down);
- blue tint and desaturation through `SetPostProcessingProperty("saturation" / "colorbalance")`; the original values are read when the effect starts and written back when it ends;
- music low-pass (`SetMusicLowPass`), heartbeat loop (`UiSoundLoop`), whooshes on enter and exit, a blue vignette;
- energy meter: drains while slowed (8 s by default), refills 1 s after release (12 s to full); when it runs out the effect stops and is locked until 30% is back. Can be turned off;
- HUD: hourglass icon, current speed, energy bar.

## What the API allows

- `SetTimeScale(scale)` is **server-only** in `#version 2` (the `script_defs.lua` example uses `server.tick`, and the game's own v2 scripts call it from server code; called from client code it is silently ignored). The client computes the ramp in real time and sends the wanted scale with `ServerCall`; the server calls `SetTimeScale` every tick (with several players the slowest request wins). It takes 0..2 and lasts one frame. The game docs say that since 1.5 it works
  through rendering interpolation and does not change physics behaviour. This mod never goes below 0.1.
- There is no per-entity time scale, so the player is slowed too. The "faster walking" option raises
  `SetPlayerWalkingSpeed` by 1/scale (up to x4) on the server. That is an approximation: jumping, falling,
  looking around and tools stay slowed.
- World sound is pitched down by the engine itself; there is no API for a low-pass on world sounds, only on music.
- In multiplayer the time scale is global: when any player slows time, everybody sees it.

## Options

| Setting | Default | Key |
|---|---|---|
| Slow motion key: H / Y / T / middle mouse | H | `savegame.mod.key` |
| Mode: hold / toggle | hold | `savegame.mod.toggle` |
| Starting speed x0.5 / x0.25 / x0.1 | x0.25 | `savegame.mod.preset` |
| Ramp time 0.05-1.5 s | 0.35 s | `savegame.mod.ramp` |
| Energy meter | on | `savegame.mod.energy` |
| Energy lasts 2-60 s | 8 s | `savegame.mod.capacity` |
| Full recharge 2-60 s | 12 s | `savegame.mod.recharge` |
| Blue tint 0-1 | 0.8 | `savegame.mod.tint` |
| Faster walking in slow-mo | off | `savegame.mod.walk` |
| Hint at level start | show | `savegame.mod.hint` |

## Install, build, test

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\Documents\Teardown\mods\time-slow" -Target "$PWD\mod"   # run inside the mod folder
..\_shared\.venv\Scripts\python tools\build_all.py
```

Mod Manager -> Local files -> Time Slow -> enable. It is not a tool: it works with any tool in hand.
