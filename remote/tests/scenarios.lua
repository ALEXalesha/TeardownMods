-- Harness scenarios for the Vehicle Remote.
local function V(x, y, z) return { x, y, z } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
local function srv() return T.env().server end
local function cli() return T.cenv().client end
local function sh() return T.sharedOf() end
local function me() return sh().rc[1] end
local function callsOf(n) return H.calls[n] or 0 end
local function hold(k, n) for i = 1, n do T.hold(k); T.frames(1) end end

T.budget("DriveVehicle", 1)
T.budget("ServerCall", 2)

H.addPlayer(1, V(0, 0, 0))
H.P(1).pitch = -8
local carBody = H.addBody { pos = V(0, 0.8, -10), mass = 1300, half = V(1, 0.8, 2) }
local wheel = H.addBody { pos = V(1.2, 0.4, -9), mass = 30 }
local car = H.addVehicle(carBody, { wheel })
local car2Body = H.addBody { pos = V(-12, 0.8, -6), mass = 1300, half = V(1, 0.8, 2) }
local car2 = H.addVehicle(car2Body, {})

T.load("main.lua", "main")
T.init("main")
T.frames(2)
T.check(H.toolsRegistered.rcremote ~= nil and H.P(1).enabled.rcremote, "tool registered and enabled")
T.select("rcremote")
T.frames(1)
T.check(cli().aim == car, "the aimed vehicle is detected")
T.check(T.hasText("take remote control"), "hint")

-- nothing aimed
H.P(1).yaw = 180
T.press("usetool"); T.frames(2)
T.check(me().vehicle == 0 and T.hasText("Aim at a vehicle"), "LMB at nothing: message")
H.P(1).yaw = 0

-- take control
T.press("usetool"); T.frames(2)
T.check(me().vehicle == car, "LMB takes control of the vehicle")
T.check(T.soundsPlayed("connect.ogg") == 1, "connect sound")
T.check(H.vehicles[car].driven ~= nil, "DriveVehicle called every tick")
T.check(callsOf("DisablePlayerInput") > 0, "player body frozen")
T.check(H.camera ~= nil, "chase camera")
T.check(T.hasText("km/h"), "driving HUD")

-- throttle and steering go to DriveVehicle on the server
T.press("up"); hold("up", 30)
local dv = H.vehicles[car].driven
T.check(dv.drive == 1 and dv.steering == 0 and dv.handbrake == false, "W: drive 1")
T.check(len(H.bodies[carBody].vel) > 0.5, "the car moves")
T.release("up"); T.press("left"); T.hold("jump"); T.frames(2)
dv = H.vehicles[car].driven
T.check(dv.drive == 0 and dv.steering == -1 and dv.handbrake == true, "A + Space: steer left with handbrake")
T.release("left"); T.release("jump"); T.frames(2)
T.check((H.sideCalls.client.DriveVehicle or 0) == 0, "DriveVehicle only from server code")

-- V toggles the chase camera
T.press("v"); T.frames(1)
H.camera = nil
T.frames(2)
T.check(H.camera == nil, "V turns the chase camera off")
T.press("v"); T.frames(2)
T.check(H.camera ~= nil, "V turns it on again")

-- hop to another vehicle
H.P(1).yaw = 63
H.P(1).pitch = -4
T.frames(1)
T.press("usetool"); T.frames(2)
T.check(me().vehicle == car2, "LMB on another vehicle hops to it")
T.frames(1)
T.check(T.soundsPlayed("hop.ogg") == 1, "hop sound")
H.P(1).yaw = 0
H.P(1).pitch = -8

-- second player cannot take a controlled car
H.addPlayer(2, V(2, 0, 0))
T.frames(1)
H.P(2).tool = "rcremote"
H.P(2).yaw = 63
H.P(2).pitch = -4
H.P(2).pos = V(0, 0, 0)
T.press("usetool", 2); T.frames(2)
T.check(sh().rc[2].vehicle == 0 and sh().rc[2].msg == "taken", "a car driven by someone else is refused")
H.P(2).tool = "sledge"

-- signal range: weak, lost, released
H.P(1).pos = V(-12, 0, 120)
T.frames(3)
T.check(me().weak > 0.2, string.format("signal weakens (%.2f)", me().weak))
T.check(callsOf("UiSoundLoop") > 0, "static sound")
H.P(1).pos = V(-12, 0, 200)
T.frames(3)
T.check(me().lost and T.hasText("SIGNAL LOST"), "signal lost past the range")
T.check(H.vehicles[car2].driven.handbrake == true and H.vehicles[car2].driven.drive == 0, "lost car brakes")
T.frames(200)
T.check(me().vehicle == 0, "lost car is released after 3 s")
T.check(T.soundsPlayed("disconnect.ogg") >= 1, "disconnect sound")
H.P(1).pos = V(0, 0, 0)

-- Q lets go
T.frames(2)
T.press("usetool"); T.frames(2)
T.check(me().vehicle == car, "control again")
T.press("q"); T.frames(2)
T.check(me().vehicle == 0, "Q releases the vehicle")
local f0 = H.vehicles[car].driven.frame
T.frames(5)
T.check(H.vehicles[car].driven.frame == f0, "no more DriveVehicle after release")

-- vehicle deleted while driving
T.press("usetool"); T.frames(2)
H.API.Delete(carBody)
T.frames(2)
T.check(me().vehicle == 0, "control ends when the vehicle disappears")

-- Russian
H.reg["options.language"] = 7
T.frames(1)
T.check(T.hasText("радиоуправление"), "hint in Russian")
H.reg["options.language"] = 0

-- options
T.loadOptions("options.lua")
T.drawOptions(1)
T.check(T.hasText("Vehicle Remote"), "options: title")
H.uiClicks["On at start"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.follow"] == false, "options: chase camera off")
H.uiClicks["Reset to defaults"] = true
T.drawOptions(1)
T.check(H.reg["savegame.mod.follow"] == true and H.reg["savegame.mod.range"] == 150, "options: reset")
