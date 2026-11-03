# Feature: Drift model and one-input control

**Status:** built, waiting on the user's feel judgement. **Owner task:** none; built by `T-003`
and extended by `T-005` (the server owning respawns), both merged (`docs/CLAIMS.md`).

The prototype's whole point: prove the drift feels great before anything else is built
(`PITCH.md` "Biggest risks", `ROADMAP.md` "Next").

## Goal

A car that slides the way the hook promises: one input breaks it loose, holding it carries the slide through a corner, and catching the exit clean carries speed into the next one. It must feel good on a phone with one thumb, and the same on desktop and gamepad.

Roblox's physics does not drive the car (`PITCH.md` "Not doing"). The car is moved by our own code every frame: a kinematic simulation we control completely, so the slide is repeatable instead of random.

## How it plays

1. The player spawns in the playground sitting in a car, already in control.
2. Throttle is automatic in the prototype: the car accelerates toward its top speed on its own, so a first-time player only has to steer and drift. Brake and reverse are on a second input.
3. **One gesture does everything.** A finger goes down, or the mouse button does, and from then until it comes up the only thing that matters is how far across the screen it has moved from where it went down (`DECISIONS.md`, 2026-11-03). A little offset steers.
4. **The same offset starts the drift.** Hold it past `DriftOffset`, or flick it across faster than `DriftFlickRate`, and the rear breaks loose. There is no drift button: the patient way in and the quick way in are two numbers, so which one a player settles on is tuning and not a decision buried in the code. Once loose it stays loose while the pointer is down.
5. While sliding, the offset is not the steering wheel: it asks for a *slide angle*, full lock being `DriftAngleMax`, and the front wheels counter-steer to it by themselves. A real slide is an unstable balance held by several corrections a second, and a thumb on a phone cannot do that and should not have to. The car turns in, the wheels unwind as the angle builds, and they catch it the moment it goes past what was asked for. **Easing the finger back toward the middle is the counter-steer** — asking for a narrower slide — which is why it is not a separate mode and there is nothing else to press. The slide bleeds speed, so a corner is taken by sliding rather than by braking.
6. Lifting the finger hooks the rear back up. Grip returns over a short blend (`GripBlendOut`), not instantly, so an exit can be caught cleanly or botched.
7. Hitting an obstacle or a wall scrubs speed and straightens the car; it never flips or ragdolls. Falling off the world puts the car back at the spawn: the client asks, the **server** picks the place and moves it ("Server and client").

**Touch and mouse are the same gesture and the same code** (`Drift/DragControl`), so there is one scheme to tune rather than two. Keyboard and gamepad cannot slide a thumb, so they keep a steering axis and a discrete drift button; every device works, but only one of them is the scheme the game is designed around.

## Rules and numbers

Every number below lives in `Shared/Config/Drift.luau`, none of them in the logic. These are starting values to tune in the playtest, not decisions.

**The model.** A bicycle model: one front contact point and one rear contact point, each producing a lateral force from its slip angle, integrated by hand at a fixed step. Three things are easy to get wrong and were, so they are written down:

- **The body axes turn.** `u` and `v` are measured along axes that rotate at the yaw rate, so a velocity that is not changing in the world still moves between them: `u̇` gains `v·r` and `v̇` loses `u·r`. Both halves, or the car's velocity is dragged round with its nose and the model pumps speed into itself until it runs away. They also give the airborne case for free: with no tyre force, those two terms alone hold the world velocity still while the body yaws.
- **The front tyre's force is square to the wheel, not to the body.** At a steering angle it therefore has a backwards component as well as a sideways one. That component is cornering drag; without it the steered wheel does positive work on the car and a long corner accelerates past top speed.
- **The slide angle is a free mode.** Once both tyres are saturated they hold whatever angle the car is already at and pick none of their own, so no amount of grip tuning produces a slide. `DriftYawAssist` is what drives it, and it drives the *yaw rate*, not a moment: the slip angle only moves when the nose turns faster than the velocity does, and the velocity turns at (lateral force ÷ speed), so the rate that holds the slide still is known exactly and anything above it opens the slide further.

| Number | Start | What it does |
|---|---|---|
| `TopSpeed` | 90 studs/s | Free speed on a straight |
| `Accel` | 80 studs/s² | How fast it reaches top speed. It has to cover what a slide scrubs off, or every drift decays into a donut |
| `BrakeDecel` | 90 studs/s² | Brake input |
| `CoastDecel` | 12 studs/s² | Drag with no input |
| `SteerAngleMax` | 32° | Front wheel angle at full lock, at low speed |
| `SteerAngleMin` | 12° | Front wheel angle at full lock, at top speed |
| `SteerRate` | 6 /s | How fast the wheels reach the commanded angle |
| `DriftAngleMax` | 35° | The slide the stick asks for at full lock. The car settles a little under it, about 23° at these numbers, because the tyres fight it the whole way |
| `CounterSteer` | 0.05 | How far past the travel direction the wheels are nudged, per radian of slide still wanted. Small because the nudge is a tyre *slip* angle and the tyre is saturated by 16° |
| `GripFront` | 1.6 | Front lateral grip coefficient |
| `GripRear` | 1.5 | Rear lateral grip, gripping |
| `GripRearDrift` | 0.4 | Rear lateral grip while the drift input is held |
| `GripBlendIn` | 0.08 s | Grip fall-off when the drift input goes down |
| `GripBlendOut` | 0.35 s | Grip return when it is released: the catch |
| `SlipSpeedBleed` | 0.35 | What a degree of slip angle costs in speed per second, on top of what the lateral force already scrubs |
| `DriftYawAssist` | 18 /s | How hard the car is held to the yaw rate its slide needs |
| `DriftAngleTime` | 0.3 s | How long it takes to swing to the angle asked for |
| `SlipAngleMax` | 55° | Past this the car is spinning out and straightens itself |
| `Wheelbase` | 12 studs | Distance between the contact points |
| `FixedStep` | 1/120 s | Simulation step, independent of frame rate |

**The car's size is a handling number, not decoration.** The wheelbase and the steering lock together fix the tightest circle the car can physically describe, `Wheelbase / tan(lock)`. At the 6 studs this spec first guessed, full lock is a 10-stud circle on a car 8 studs long: the car pirouettes rather than slides, and no tyre tuning reaches past that, because the geometry gets there first. The built car is 16 studs long on a 12-stud wheelbase — 19 studs at full lock, 56 at top speed — and `YawInertia` (25 studs²) is that body's own, `(length² + width²) / 12`. Change the body and change both.

**Ground.** One downward ray per contact point each step finds the surface; the car's height and pitch and roll follow the surface normal over `GroundFollow` (0.12 s), so ramps and berms read as shape rather than as steps. Airborne (no hit within `RideHeight` + 2 studs) the car keeps its velocity, falls at `Gravity` (110 studs/s²), and steering only rotates it in yaw.

**Determinism.** The step is fixed and the model takes no random input, so the same inputs from the same start produce the same line. That is what makes a drift learnable, and what will make a score worth chasing later.

## UI

A programmer-art debug readout only, top left, toggled by a key or button: speed, slip angle, yaw rate, grip state (gripping, breaking, drifting, catching), airborne, and the frame step. Nothing else. The real HUD waits for scoring (`ROADMAP.md`).

The control's own art is programmer art (`docs/workflow/UI.md` layouts): while a finger or the mouse is down, a track across the bottom of the screen with the middle marked and a knob showing the offset, turning red and reading DRIFT once the rear has let go. It is there so a tester can see what the gesture is being read as; it is not the shipping HUD. A plain BRAKE button sized for a thumb, and a DBG button for the readout, are the only other things on screen.

| Number | Start | What it does |
|---|---|---|
| `DragFullLock` | 140 px | Horizontal travel from where the finger went down to full lock |
| `DragDeadzone` | 0.06 | Share of full lock ignored around the origin |
| `DriftOffset` | 0.55 | Share of full lock held out past which the rear lets go |
| `DriftFlickRate` | 1400 px/s | Lateral speed that breaks the rear loose whatever the offset |
| `DriftFlickSmoothing` | 0.06 s | What the flick rate is averaged over, so one jittery sample cannot start a drift |

## Server and client

The player's own car is simulated on the client that drives it, because feel cannot survive a round trip. The server owns **where a car may be put** — its spawn and every respawn — and replicates each car's state to the other clients.

**A respawn is the server's, not the client's.** Throttle is automatic, so a car left alone drives off the edge and falls; below `RespawnBelowY` the client *asks* over `CarRespawn` and keeps falling until it is answered. The server picks the spot (`SpawnCFrame()`), moves the car, records that position as where it expects the car, and sends it back. The client restarts its simulation there, and sends nothing in between.

That is what makes the movement check worth having. The server is comparing each `CarState` against a position it chose or last agreed to, so a packet that follows from neither is dropped — **and the next one is compared against the same position, for ever.** There is no run of drops that wears the server down into taking the client's word: the one case that used to need it, a respawn, is now a thing the server did itself. The only forgiveness left is `RespawnGrace`, and it is not forgiveness: for a moment after a respawn, a packet may instead be checked against the position the car was moved *from*, because an unreliable packet sent before the respawn can land after it, and that is a place the server also knows the car was.

For the prototype that is the whole contract. The server bounds speed and distance; it does not re-run the model, and nothing is scored, sold or saved to cheat for yet. **Before anything is scored or paid for**, the server has to validate each car's reported state against what the model allows. That half is still a task of its own, noted in "Open questions".

## Contracts

In `CONTRACTS.md`:

- Remote `CarSpawn` (server to client, event): the car model and its spawn CFrame.
- Remote `CarState` (client to server, unreliable event): CFrame, velocity and drift state, at 20 Hz, with every check the server makes on it.
- Remote `CarRespawn` (both ways, event): a request with no payload, answered with the CFrame the server has just put the car at.
- Remote `CarStateOther` (server to client, unreliable event): the same for other players' cars.
- `CarService:SpawnCFrame()`, `CarService:Respawn(player)` and `CarService:DebugState()`.
- `DriftController:DebugState()` returns the model's full state, for tests and agent playtests.
- `DriftController:DebugDrive(inputs, seconds, opts)` returns the path **and** a summary of what the drive did: entry and exit speed, peak slip, when the rear let go, how far round the car came.
- `CarInputController:DebugSetInput(steer, drift, brake)` and `DebugClearInput()` drive the live car from a test with no keyboard.

## How it is laid out

`DriftController` is only the lifecycle: take the car the server spawned, read the input once a frame, spend the frame in whole simulation steps, draw it, tell the server. The work is in `StarterPlayerScripts/Drift/`:

| Module | What it is |
|---|---|
| `Model` | The model: pure maths plus two injected world queries. No player, no car, no Workspace — which is what makes `DebugDrive` and the determinism test possible at all |
| `Sim` | The fixed-step accumulator, in one place, shared by the live loop, `DebugDrive` and the tests, so all three run the same code |
| `World` | The only two questions the model asks the Workspace: the ground under a contact point, and anything solid in the way. `World.flat(y)` is the same interface over a plane |
| `Render` | Writes each part's CFrame from the state. Front wheels show the *real* wheel angle, counter-steer included |
| `DebugHud`, `TouchControls`, `RemoteCars` | The readout, the thumb controls, and the other players' cars |

## Analytics

None in the prototype: there is nothing to measure until a run is scored. The loop's events are designed with the scoring feature (`docs/workflow/ANALYTICS.md`), not bolted on here.

## Monetization

None.

## Platform risks

**Copyright:** the prototype car is an untextured block of our own, with no manufacturer's shape, name or badge (`PITCH.md` "Biggest risks"). The comparison game's name stays out of the code, the place, and anything a player sees.

## Art and sound

Placeholder: the car is a box with four cylinders, built by code. No sound in the prototype; engine and tyre sound are their own task once the feel is agreed (`AUDIO.md`).

## Testing

Measured, not guessed (`docs/workflow/TESTING.md`). `ServerScriptService/Tests/DriftTests.luau`, through the server bridge as `DebugDriftTests`. Measured 2026-11-03 on `DR-Lane1`:

| Check | Measured |
|---|---|
| **A repeatable line.** `DebugDrive` twice from the same start, within a stud | 142 points, worst deviation **0.000000 studs** |
| **Frame independence.** The same inputs at 30, 60 and 120 FPS, within 2 studs | worst gap **0.727 studs**, all of it the leftover in the accumulator (839 steps against 840) |
| **A corner.** A scripted 90° corner from a standing start | entry **83.9** studs/s, peak slip **25.8°**, exit **70.4** studs/s (84% of entry), rear loose **0.242 s** after the input, turned **94.6°** |
| **No runaway.** 12 s of lock-to-lock with the drift held | top speed **61.3** (ceiling 103.5), top yaw **3.58 rad/s** (ceiling 4.0) |
| **No physics.** No BodyMover, VectorForce, constraint or joint, every part anchored | a fresh car and every live car: **5 parts, all anchored, nothing that moves them** |
| **A bare plate is drivable**, with nothing tagged `DriftSurface` | 87.5 studs/s, 0 s airborne |
| **The numbers live in Config.** Halving `TopSpeed` halves the car | 89.9 → 45.0 studs/s |
| **A respawn is not a teleport.** The packet after a respawn, and one in flight over it, both check out | both fit; the fall checks out at **200 studs/s** down |
| **A jump the server did not decide stays rejected.** The same jump, over and over, against a track that never moves | **20 of 20** packets 707 studs from where the server put the car rejected, and no `StateResyncDrops` left in Config |

**The respawn, measured live on `DR-Lane1`, 2026-11-03.** The number this replaced: **340 dropped `CarState` packets** in one playtest before the server owned respawns.

| Driven | Measured |
|---|---|
| Drive off the edge of the plate (x ≈ 1050) and fall to y = −137 | the car comes back at the spawn (−160, 3, −75) 0.1 s later; **0 dropped packets** across the whole respawn |
| Six respawns in a row: two falls and four `DebugReset`s | **0 dropped packets**, 0 refused; the ask-to-answer round trip is **34–40 ms**; 1 packet in flight over a respawn kept by `RespawnGrace` |
| From the spawn to the first fall, 10 s of driving | **0 dropped packets** (it was 32 before the send clock was clamped: a long first frame used to be paid back as a burst at frame rate, which the rate limit dropped) |
| A client that jumps 900 studs **without** asking (`DebugTeleport`) | **69 packets dropped in a row**, nothing accepted; the old code gave in after 5. The server starts agreeing again only once the car has driven back inside what it could honestly have covered — which is what a distance budget can prove, and all it can |
| 20 `CarRespawn` requests in one second, fired at the raw remote with a CFrame payload | **2 granted, 18 refused** (`RespawnCooldown` 0.5 s); the payload ignored; 0 dropped `CarState` |

The same corner driven live on the playground, through the client bridge: entry 90 studs/s, slide held at **−25.8°** with the front wheels counter-steered **−22.1°**, 72.4 studs/s through the corner, exit 81.8 studs/s, turned **−93.4°**.

- **Playtest:** drive it. The user decides whether it feels right; that is the gate. Nothing above is a feel judgement — those checks only catch a model that has stopped working.

## Open questions

- ~~**The touch scheme:** two thumbs or a true one finger.~~ **Decided 2026-11-03:** one finger or the mouse, slid left and right, the same offset steering and drifting. The two-thumb scheme is dropped (`DECISIONS.md`).
- **Where the two ways into a drift land.** `DriftOffset` (hold it out) and `DriftFlickRate` (snap it across) are both live, and the starting numbers are a guess at where a thumb sits. Which one a player ends up using, and whether the other should go, is a playtest answer.
- **How much the car drifts for the player.** The stick asks for a slide angle and the front wheels counter-steer to it on their own (`CounterSteer`, `DriftAngleMax`, `DriftYawAssist`). That is a design decision, not only a tuning one: a car that holds its own slide is one a thumb can drive, and a car that does not is one the player learns to catch. Only the user can say which this game wants. The dials are there either way.
- **Automatic throttle:** keeping it for good is a real design choice (accessibility, mobile), not only a prototype shortcut. Decide after the playtest.
- **Server validation of car state.** Half done. ~~The server cannot tell a respawn from a teleport, so after a few rejections in a row it takes the client's word (`StateResyncDrops`).~~ **Done 2026-11-03:** the server owns spawn and respawn positions, records what it expects, and `StateResyncDrops` is gone with the path that used it ("Server and client"). **Still open:** the checks bound speed and distance, they do not re-run the model — a client that feeds the server a legal-looking line it never drove is not caught, and `drifting` is taken on trust. Before anything is scored or sold, the server has to re-check or re-simulate the model, and decide what happens to a client that fails (today everything is dropped, nothing is kicked).
- **Car dimensions and weight balance:** one car for now, 16 studs long on a 12-stud wheelbase, with the contact points evenly split. Cars that feel different from each other is a meta decision, and waits on the open direction in `PITCH.md`.
