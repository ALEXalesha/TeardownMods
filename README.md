# Teardown Mods

A collection of Teardown 2.x mods (scripting API `#version 2`: `server` / `client` / `shared`).
Every mod has its own folder with the built mod in `mod/`, generators in `tools/`, offline tests in `tests/`
and its own README in English and Russian. Russian version of this page: [README.ru.md](README.ru.md).

<!-- mods -->
| Folder | Mod | What it is |
|---|---|---|
| [catapult](catapult) | Catapult | A giant wooden trebuchet, about 13 m tall, that you place in front of you. Its frame is real destructible wood and its arm swings about the axle. Whatever lies in the bucket gets thrown: a boulder, an explosive barrel, a car, a pile of crates - or you. Controls: LMB - place a catapult in front of you; Q, or E on the machine - fire; Mouse wheel - power; Z / X - turn left / right; V / B - lower / raise the angle; 1 2 3 4 - load a boulder / barrel / car / crates; RMB - load the selected ammo; R - remove all catapults. Settings in the Mod Manager (Options). |
| [cutter](cutter) | Cutter | An angle grinder. Hold the mouse button on a surface, sweep to the end point and release: the saw cuts a straight kerf from one point to the other, through walls, floors and vehicles. Controls: Hold LMB, sweep, release - cut a straight line from the press point to the release point. Settings in the Mod Manager (Options). |
| [drone](drone) | Camera Drone | A deployable quadcopter flown from its own camera while your body stays behind. Battery, signal range with static, a target marker and bombs - or Singularity Grenades if that mod is on. Controls: LMB (on foot) - launch the drone / take control again; R (on foot, within 4 m) - pack it up (refills bombs and battery); WASD - fly; Space / Ctrl - up / down; Mouse - look and turn; LMB (flying) - drop a bomb; Q - back to your body (the drone keeps hovering); P - photo mode. Settings in the Mod Manager (Options). |
| [earthquake](earthquake) | Earthquake | A seismic detonator. Start an earthquake at the aim point, from Weak to Catastrophic: things rock and tip over, buildings crack and fall, joints snap, aftershocks follow. Controls: LMB - start a quake at the aim point / stop it; RMB - next preset. Settings in the Mod Manager (Options). |
| [falling-moon](falling-moon) | Falling Moon | A telescope that calls the moon down on the aim point. Over 1-5 minutes it grows in the sky, the ground trembles, dust and wind rise and a countdown runs; then it slams into the ground, sits in a huge crater as a real voxel moon, and its shockwave takes almost everything around with it. Controls: LMB - call the moon down on the aim point; RMB - send it back. Settings in the Mod Manager (Options). |
| [gravity](gravity) | Gravity Change | Switch the real gravity of the whole level with one key: Earth, Moon, Mars, zero-G, reverse and sideways, with a smooth transition. Works with anything in hand. Controls: G (tap) - next preset; G (hold 0.8 s) - back to Earth; Space / Ctrl in zero-G - float up / down. Settings in the Mod Manager (Options). |
| [mover](mover) | Mover | A gizmo gun that moves things: grab any loose object or vehicle, push and pull it, rotate it on three axes, freeze it in mid-air, clone it, resample it and undo your moves. Controls: Hold LMB - grab the aimed object; release drops it; Mouse wheel - push / pull; Q / R - rotate; Z / X - tilt; V / B - roll; T - freeze / unfreeze; G - clone; N / M - resample x0.5 / x2 (experimental); U - undo. Settings in the Mod Manager (Options). |
| [portal-gun](portal-gun) | Portal Gun | Place a blue and an orange portal on flat surfaces and walk, fall or throw things through them. Momentum and direction are kept, so floor-to-wall flings work. Controls: LMB - blue portal; RMB - orange portal; R - close both. Settings in the Mod Manager (Options). |
| [remote](remote) | Vehicle Remote | Point at any vehicle and drive it remotely, like an RC car, while you stay where you are. A chase camera, a signal range with static, and hopping from car to car. Controls: LMB on a vehicle - take control; on another one while driving: hop to it; W / S - throttle / reverse; A / D - steer; Space - handbrake; V - chase camera on / off; Q - let go. Settings in the Mod Manager (Options). |
| [singularity-grenade](singularity-grenade) | Singularity Grenade | A throwable gravity grenade. It bounces, rises and opens into a short-lived singularity that pulls in debris, objects and players, squeezes them into a spinning orbit and then collapses in a blast. Controls: Hold LMB, release - throw (hold up to 1 s to throw farther); RMB - short toss at your feet. Settings in the Mod Manager (Options). |
| [telekinesis](telekinesis) | Telekinesis | A telekinesis gauntlet. Lift the loose objects around your aim point into a spinning ring in front of you, charge, and throw them as a volley - or put them down gently. Controls: LMB (hands empty) - lift the objects around the aim point; Hold LMB (holding), release - charge and throw them as a volley; RMB - put them down gently. Settings in the Mod Manager (Options). |
| [time-slow](time-slow) | Time Slow | Hold a key to slow the whole world down to x0.5, x0.25 or x0.1, with a smooth ramp, a blue tint, muffled music, a heartbeat and an energy meter. Works with any tool in hand. Controls: H (hold, or toggle) - slow motion; J - speed x0.5 / x0.25 / x0.1. Settings in the Mod Manager (Options). |
| [tornado](tornado) | Tornado | A storm caller. Spawn a tornado at the aim point: it forms in place, then wanders the map or follows your aim, sucking in, spinning, lifting and throwing objects, vehicles and you, and tearing weak buildings. Controls: LMB - spawn a tornado at the aim point; RMB - dismiss the nearest one. Settings in the Mod Manager (Options). |
| [trampoline-floor](trampoline-floor) | Trampoline Floor | Place bounce pads, or make the whole ground bouncy. Players, objects and vehicles bounce back at least as high as they fell (with the default bounciness), a little higher each time, and jumping on contact sends you even higher. Controls: LMB - place a pad on flat ground; RMB - remove the nearest pad; R - whole ground bounces on / off; Space on contact - bounce higher. Settings in the Mod Manager (Options). |
| [tsunami](tsunami) | Tsunami | A conch horn that calls a tsunami from where you look. A siren warns while the wave rises on the horizon, then a wall of water rolls in, throws cars, carries away objects and you, tears buildings apart, floods the ground and finally runs back. Controls: LMB - call a tsunami from where you look; RMB - call it off. Settings in the Mod Manager (Options). |
| [volcano](volcano) | Volcano | A magma core tool. Raise a volcano on the ground in a few seconds and watch it erupt in phases: rumble and smoke, lava bombs that punch craters and start fires, lava flows, ash, and a final blast that blows the summit off. Controls: LMB on the ground - raise a volcano; RMB during the eruption - final blast now; R - remove the cones. Settings in the Mod Manager (Options). |
<!-- /mods -->


## Steam Workshop

Every mod is ready for the Workshop (square Steam preview, 16:9 in-game preview, tags, EN/RU descriptions in `<mod>/workshop/`, an upload check). Step-by-step guide and upload order: [WORKSHOP.md](WORKSHOP.md).

Changes: [RELEASE_NOTES.md](RELEASE_NOTES.md).

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
