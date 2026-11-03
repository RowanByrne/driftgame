# Feature: Drift model and one-input control

**Status:** specced. **Owner task:** none yet (`docs/CLAIMS.md`).

The prototype's whole point: prove the drift feels great before anything else is built
(`PITCH.md` "Biggest risks", `ROADMAP.md` "Next").

## Goal

A car that slides the way the hook promises: one input breaks it loose, holding it carries the slide through a corner, and catching the exit clean carries speed into the next one. It must feel good on a phone with one thumb, and the same on desktop and gamepad.

Roblox's physics does not drive the car (`PITCH.md` "Not doing"). The car is moved by our own code every frame: a kinematic simulation we control completely, so the slide is repeatable instead of random.

## How it plays

1. The player spawns in the playground sitting in a car, already in control.
2. Throttle is automatic in the prototype: the car accelerates toward its top speed on its own, so a first-time player only has to steer and drift. Brake and reverse are on a second input.
3. Steering is an axis: left and right.
4. **One input starts the drift.** Hold it with any steering angle and the rear breaks loose; the car rotates into the slide and keeps rotating while held.
5. While sliding, steering is counter-steer: it sets how wide the slide runs, and the slide itself bleeds speed, so a corner is taken by sliding rather than by braking.
6. Releasing the input hooks the rear back up. Grip returns over a short blend, not instantly, so an exit can be caught cleanly or botched.
7. Hitting an obstacle or a wall scrubs speed and straightens the car; it never flips or ragdolls. Falling off the world respawns the car at the nearest spawn point.

**(proposed)** The touch scheme is: the left half of the screen steers (a virtual stick), the right half held is drift. The alternative, one finger doing both (drag sideways to steer, hold to drift), is the closer match to the comparison game. Build the two-thumb scheme first because it separates the variables; the one-finger scheme is a config switch to try in the same playtest. The user picks after feeling both ("Open questions").

## Rules and numbers

Every number below lives in `Shared/Config/Drift.luau`, none of them in the logic. These are starting values to tune in the playtest, not decisions.

**The model.** A bicycle model: one front contact point and one rear contact point, each producing a lateral force from its slip angle, integrated by hand at a fixed step.

| Number | Start | What it does |
|---|---|---|
| `TopSpeed` | 90 studs/s | Free speed on a straight |
| `Accel` | 45 studs/s² | How fast it reaches top speed |
| `BrakeDecel` | 90 studs/s² | Brake input |
| `CoastDecel` | 12 studs/s² | Drag with no input |
| `SteerAngleMax` | 32° | Front wheel angle at full lock, at low speed |
| `SteerAngleMin` | 12° | Front wheel angle at full lock, at top speed |
| `SteerRate` | 6 /s | How fast the wheels reach the commanded angle |
| `GripFront` | 1.6 | Front lateral grip coefficient |
| `GripRear` | 1.5 | Rear lateral grip, gripping |
| `GripRearDrift` | 0.55 | Rear lateral grip while the drift input is held |
| `GripBlendIn` | 0.08 s | Grip fall-off when the drift input goes down |
| `GripBlendOut` | 0.35 s | Grip return when it is released: the catch |
| `SlipSpeedBleed` | 0.6 | What a degree of slip angle costs in speed per second |
| `DriftYawAssist` | 1.1 | Extra yaw while drifting, so a slide starts without fighting it |
| `SlipAngleMax` | 55° | Past this the car is spinning out and straightens itself |
| `Wheelbase` | 6 studs | Distance between the contact points |
| `FixedStep` | 1/120 s | Simulation step, independent of frame rate |

**Ground.** One downward ray per contact point each step finds the surface; the car's height and pitch and roll follow the surface normal over `GroundFollow` (0.12 s), so ramps and berms read as shape rather than as steps. Airborne (no hit within `RideHeight` + 2 studs) the car keeps its velocity, falls at `Gravity` (110 studs/s²), and steering only rotates it in yaw.

**Determinism.** The step is fixed and the model takes no random input, so the same inputs from the same start produce the same line. That is what makes a drift learnable, and what will make a score worth chasing later.

## UI

A programmer-art debug readout only, top left, toggled by a key or button: speed, slip angle, yaw rate, grip state (gripping, breaking, drifting, catching), airborne, and the frame step. Nothing else. The real HUD waits for scoring (`ROADMAP.md`).

Touch controls are programmer art: a plain steering stick on the left and a plain drift button on the right, both sized for a thumb (`docs/workflow/UI.md` layouts).

## Server and client

The player's own car is simulated on the client that drives it, because feel cannot survive a round trip. The server owns spawning and despawning, and replicates each car's state to the other clients.

For the prototype that is the whole contract: there is nothing scored, sold or saved to cheat for yet. **Before anything is scored or paid for**, the server has to validate each car's reported state against what the model allows (top speed, acceleration, no teleports). That is a task of its own, noted in "Open questions".

## Contracts

New, all added to `CONTRACTS.md` in the same commit as the code:

- Remote `CarSpawn` (server to client, event): the car model and its spawn CFrame.
- Remote `CarState` (client to server, unreliable event): CFrame, velocity and drift state, at 20 Hz.
- Remote `CarStateOther` (server to client, unreliable event): the same for other players' cars.
- `DriftController:DebugState()` returns the model's full state, for tests and agent playtests.

## Analytics

None in the prototype: there is nothing to measure until a run is scored. The loop's events are designed with the scoring feature (`docs/workflow/ANALYTICS.md`), not bolted on here.

## Monetization

None.

## Platform risks

**Copyright:** the prototype car is an untextured block of our own, with no manufacturer's shape, name or badge (`PITCH.md` "Biggest risks"). The comparison game's name stays out of the code, the place, and anything a player sees.

## Art and sound

Placeholder: the car is a box with four cylinders, built by code. No sound in the prototype; engine and tyre sound are their own task once the feel is agreed (`AUDIO.md`).

## Testing

Measured, not guessed (`docs/workflow/TESTING.md`):

- **A repeatable line.** `DebugDrive(inputs, seconds)` feeds a recorded input sequence to the model with no player and returns the path. Running it twice gives the same path to within a stud: that is determinism.
- **A corner.** From a standing start, a scripted input sequence takes a 90° corner of the playground. The log gives entry speed, peak slip angle, exit speed, and the time from input to the rear breaking loose. Those are the numbers the tuning conversation uses.
- **Frame independence.** The same input sequence at 30, 60 and 120 FPS ends within 2 studs of the same point.
- **No physics.** The car's parts are anchored, and the car model holds no BodyMover, VectorForce or constraint: asserted in an automated test, because this is the rule most easily broken later.
- **Playtest:** drive it. The user decides whether it feels right; that is the gate.

## Open questions

- **The touch scheme:** two thumbs or a true one finger (above). The user decides after feeling both.
- **Automatic throttle:** keeping it for good is a real design choice (accessibility, mobile), not only a prototype shortcut. Decide after the playtest.
- **Server validation of car state**, before anything is scored or sold. Not in the prototype.
- **Car dimensions and weight balance:** one car for now. Cars that feel different from each other is a meta decision, and waits on the open direction in `PITCH.md`.
