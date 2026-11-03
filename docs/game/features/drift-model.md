# Feature: Drift model and one-input control

**Status:** rebuilt, waiting on the user's feel judgement. **Owner task:** none; built by `T-003`
and extended by `T-005` (the server owning respawns), then rebuilt by `T-007` after the user drove it
and the drift felt wrong — the finger is now on the car's rear and a slide costs real speed
(`DECISIONS.md`, 2026-11-03).

The prototype's whole point: prove the drift feels great before anything else is built
(`PITCH.md` "Biggest risks", `ROADMAP.md` "Next").

## Goal

A car that slides the way the hook promises: one input breaks it loose, holding it carries the slide through a corner, and catching the exit clean carries speed into the next one. It must feel good on a phone with one thumb, and the same on desktop and gamepad.

Roblox's physics does not drive the car (`PITCH.md` "Not doing"). The car is moved by our own code every frame: a kinematic simulation we control completely, so the slide is repeatable instead of random.

## How it plays

1. The player spawns in the playground sitting in a car, already in control.
2. Throttle is automatic in the prototype: the car accelerates toward its top speed on its own, so a first-time player only has to steer and drift. Brake and reverse are on a second input.
3. **One gesture does everything, and it is on the car's rear.** A finger goes down, or the mouse button does, and from then until it comes up the only thing that matters is how far across the screen it has moved from where it went down (`DECISIONS.md`, 2026-11-03). That offset is **not** where the nose points. It is how hard, and which way, the car's weight is thrown across — the finger is on the tail, so **finger left swings the tail left, which arcs the car right**.
4. **The same offset says how hard the car is sliding.** There is no drift mode to be in and out of and no threshold to cross: a small offset is a shallow fast arc, a big one is a car properly sideways, and the whole range is one continuous thing. `DriftOffset` and `DriftFlickRate` survive only to decide when the readout calls it a drift and what one press of a *discrete* input (keyboard, gamepad, a flick) is worth on the same scale.
5. **The slide is a shove and a fight, never a pose.** The thrown weight puts a yaw *moment* on the car (`SlideKick`); the car's own grip hauls the tail back against it, harder the further out it is (`SlideBite`). The angle the player gets is where the two cancel, so the car leans past it on the way in, sags when the tyres bite, and snaps home when the finger does. Nothing anywhere names an angle for the car to go to — which is what the first version did, by driving the yaw *rate* to whatever held a commanded angle, and what made it feel "like we are directly steering the car but you are just turning it sideways so it looks like we are drifting". The front wheels are the driver's hands and simply follow where the front axle is travelling: once the back is out, that *is* counter-steer, with no second mode and nothing to press.
6. **A slide costs speed, and the finger is the only speed control the car has.** Drifting makes friction and the harder the drift the more of it, so the scrub rises steeply with the slide (`SlideDrag`, `SlideDragPower`) and acts along the car's *travel*, not its nose. The thrown weight also takes the throttle with it (`DriveCutShape`): at a full offset the car has nothing left to drive out of the stop with. **Full offset held is the brake and the panic button** — from top speed to under a tenth of it in 1.7 s — and it is not a brake force bolted on, it falls out of the two.
7. **Weight has mass.** The weight takes `WeightThrowRate` to go across and `WeightSettleRate` to gather back in, and the slide takes about 0.4 s to arrive on top of that. An instant answer is what reads as a cursor rather than a car.
8. Lifting the finger hooks the rear back up. Grip returns over `GripBlendOut`, not instantly, so an exit can be caught cleanly or botched.
9. Hitting an obstacle or a wall scrubs speed and straightens the car; it never flips or ragdolls. Falling off the world puts the car back at the spawn: the client asks, the **server** picks the place and moves it ("Server and client").

**Touch and mouse are the same gesture and the same code** (`Drift/DragControl`), so there is one scheme to tune rather than two. Keyboard and gamepad cannot slide a thumb, so they keep a steering axis and a discrete drift button; every device works, but only one of them is the scheme the game is designed around.

## Rules and numbers

Every number below lives in `Shared/Config/Drift.luau`, none of them in the logic. These are starting values to tune in the playtest, not decisions.

**The model.** A bicycle model: one front contact point and one rear contact point, each producing a lateral force from its slip angle, integrated by hand at a fixed step. Three things are easy to get wrong and were, so they are written down:

- **The body axes turn.** `u` and `v` are measured along axes that rotate at the yaw rate, so a velocity that is not changing in the world still moves between them: `u̇` gains `v·r` and `v̇` loses `u·r`. Both halves, or the car's velocity is dragged round with its nose and the model pumps speed into itself until it runs away. They also give the airborne case for free: with no tyre force, those two terms alone hold the world velocity still while the body yaws.
- **The front tyre's force is square to the wheel, not to the body.** At a steering angle it therefore has a backwards component as well as a sideways one. That component is cornering drag; without it the steered wheel does positive work on the car and a long corner accelerates past top speed.
- **The slide angle is a free mode, so something has to drive it.** Once both tyres are saturated they hold whatever angle the car is already at and pick none of their own, so no amount of grip tuning produces a slide by itself. The finger drives it, and the one thing that matters is *how*: it applies a **moment**, not a yaw rate. Driving the rate — commanding the rate that holds a chosen angle, plus the error over a settling time — closes the loop by cancelling the car's own dynamics, and the car then arrives at the angle asked for, smoothly, from any speed, with nothing fighting. That is a pose, and it is exactly what the user rejected. A moment leaves the yaw inertia, the damping and both tyres in the loop, so what the player gets is a balance and not a number.
- **Two tyre forces, nearly flat in the slide angle, cannot grade it.** A saturated tyre makes the same force at 20° as at 60°, so left alone the car has two states — stuck and gone — with nothing in the middle for a thumb to live in. `SlideBite` is the graded fight that gives the middle of the travel somewhere to be, and `SlideCurve` maps the finger's travel onto the range that results.
- **Grip is a handling number.** At the `GripAccel` of 110 this started from, two saturated tyres pull about 5g and the car pirouettes on a 13-stud radius the moment it slides, so the input can be tuned all day and never reach past it. At 40 a held drift runs a 110-stud circle at half a finger and a 24-stud one at three quarters.

| Number | Start | What it does |
|---|---|---|
| `TopSpeed` | 90 studs/s | Free speed on a straight |
| `Accel` | 80 studs/s² | How fast it reaches top speed |
| `SlideDrag` | 32 studs/s² | What the slide scrubs off at `SlideAngleFull`, along the car's travel. **The dial for what a drift costs** |
| `SlideDragPower` | 2.3 | The shape of that trade. Above 1, a shallow drift is nearly free and a big one is ruinous |
| `DriveCutShape` | 3 | How much of the throttle the thrown weight takes away. At a full offset, all of it — which is what makes full lock held a stop the car cannot drive out of |
| `BrakeDecel` | 90 studs/s² | Brake input |
| `CoastDecel` | 12 studs/s² | Drag with no input |
| `SlideKick` | 78 rad/s² | The shove the thrown weight puts on the tail at a full offset |
| `SlideBite` | 78 rad/s² | The pull the car's own grip answers with at `SlideAngleFull`. **`SlideKick` ÷ `SlideBite` is how sideways the car gets; their size is how violently it answers** |
| `SlideBiteShape` | 1 | How the fight grows with the angle |
| `SlideAngleFull` | 65° | As sideways as this car gets: where the bite is at full and the scrub is at full |
| `SlideCurve` | 0.75 | How the finger's travel maps onto that range. Below 1 the near half of the travel buys more |
| `SlideKickSpeed` | 8 studs/s | Where the shove and the fight are both at full; below it they fade together, so a standstill does not pirouette |
| `WeightThrowRate` | 3.5 /s | How fast the weight goes across (0.29 s centre to full) |
| `WeightSettleRate` | 3 /s | How fast it gathers back in |
| `SteerAngleMax` | 32° | Front wheel angle at full lock, at low speed |
| `SteerAngleMin` | 12° | Front wheel angle at full lock, at top speed |
| `SteerRate` | 6 /s | How fast the wheels reach the commanded angle |
| `CounterSteer` | 0 | How far *past* the travel the front wheels are carried, per radian of slide. Zero is the hands exactly on the travel, which measured best; positive makes the car corner wider the harder it is drifted, negative tightens every radius and makes it swap ends |
| `CrawlSpeed` | 12 studs/s | Below this the wheels take the finger directly, so the car can still be parked |
| `GripFront` | 1.6 | Front lateral grip coefficient |
| `GripRear` | 1.5 | Rear lateral grip, with the weight centred |
| `GripRearDrift` | 0.4 | Rear lateral grip with the weight fully thrown across |
| `GripAccel` | 40 studs/s² | Lateral grip per 1.0 of coefficient: the circle the car can describe |
| `GripBlendIn` | 0.08 s | Grip fall-off as the weight goes across |
| `GripBlendOut` | 0.35 s | Grip return as it comes back: the catch |
| `YawDamping` | 11 /s | The car's mass answering the shove: how far the slide overshoots before it settles |
| `SlipAngleMax` | 88° | Past square across the car is going round, not drifting. A wall, not a feel knob |
| `Wheelbase` | 12 studs | Distance between the contact points |
| `FixedStep` | 1/120 s | Simulation step, independent of frame rate |

**The car's size is a handling number, not decoration.** The wheelbase and the steering lock together fix the tightest circle the car can physically describe, `Wheelbase / tan(lock)`. At the 6 studs this spec first guessed, full lock is a 10-stud circle on a car 8 studs long: the car pirouettes rather than slides, and no tyre tuning reaches past that, because the geometry gets there first. The built car is 16 studs long on a 12-stud wheelbase — 19 studs at full lock, 56 at top speed — and `YawInertia` (25 studs²) is that body's own, `(length² + width²) / 12`. Change the body and change both.

**Ground.** One downward ray per contact point each step finds the surface; the car's height and pitch and roll follow the surface normal over `GroundFollow` (0.12 s), so ramps and berms read as shape rather than as steps. Airborne (no hit within `RideHeight` + 2 studs) the car keeps its velocity, falls at `Gravity` (110 studs/s²), and steering only rotates it in yaw.

**Determinism.** The step is fixed and the model takes no random input, so the same inputs from the same start produce the same line. That is what makes a drift learnable, and what will make a score worth chasing later.

## UI

A programmer-art debug readout only, top left, toggled by a key or button: speed, slip angle, yaw rate, grip state (gripping, breaking, drifting, catching), airborne, and the frame step. Nothing else. The real HUD waits for scoring (`ROADMAP.md`).

The control's own art is programmer art (`docs/workflow/UI.md` layouts): while a finger or the mouse is down, a track across the bottom of the screen with the middle marked and a knob showing the offset, reading the weight as a percentage and which way the tail is going, and turning red and reading DRIFT once the car is actually sliding. It is there so a tester can see what the gesture is being read as; it is not the shipping HUD. A plain BRAKE button sized for a thumb, and a DBG button for the readout, are the only other things on screen.

| Number | Start | What it does |
|---|---|---|
| `DragFullLock` | 140 px | Horizontal travel from where the finger went down to full lock |
| `DragDeadzone` | 0.06 | Share of full lock ignored around the origin |
| `DriftOffset` | 0.55 | Share of full lock past which the readout calls it a drift, and what one press of a discrete input is worth on the same scale. **No longer a gate** |
| `DriftFlickRate` | 1400 px/s | Lateral speed that counts as a flick, whatever the offset |
| `DriftFlickSmoothing` | 0.06 s | What the flick rate is averaged over, so one jittery sample cannot start a drift |
| `KeySteerShare` | 0.35 | What a keyboard key or a stick is worth on its own, with no drift button held. A digital key is always at full travel, and a car that went fully sideways the moment a key went down would be undrivable |

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
- `DriftController:DebugState()` returns the model's full state, for tests and agent playtests. Since `T-007` it reports `load` (where the car's weight has got to) and `slideFrac` (how sideways it is, as a share of `SlideAngleFull`) in place of `wantedSlipDeg`, which named an angle the model no longer has.
- `DriftController:DebugDrive(inputs, seconds, opts)` returns the path **and** a summary of what the drive did: entry and exit speed, peak slip, when the rear let go, how far round the car came.
- `CarInputController:DebugSetInput(steer, drift, brake)` and `DebugClearInput()` drive the live car from a test with no keyboard; `DebugDrag(offsetPx, flickRate)` acts out the real gesture instead, which is what the feel measurements use.

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
| **Frame independence.** The same inputs at 30, 60 and 120 FPS, within 2 studs | worst gap **0.710 studs**, all of it the leftover in the accumulator |
| **The finger is on the car's rear.** A finger one way must swing the tail that way and arc the car the other | finger +0.4 (tail right) for 1.5 s: slip **+20.5°** (tail out to the right), heading **+59.0°** (left), ended 113.7 studs ahead and **36.1 studs to its left** |
| **Every notch of finger buys more slide and costs more speed.** Held 8 s from 87.5 studs/s | 25%: **10°**, 82 studs/s (**94%**), 163-stud circle · 50%: **26°**, 67 (**76%**), 113 · 75%: **36°** leaning to 48, 30 (**34%**), 24 · 100%: leans to **67°**, 5 (**6%**), 4 |
| **A shallow drift is nearly free and a big one is ruinous** | a quarter offset keeps **94%** of entry speed at 10°; three quarters keeps **34%** at 36° |
| **Full offset held kills the car's momentum** | from 87.5 studs/s to under a tenth of top speed in **1.68 s**, settling at **4.9 studs/s** with the car 67° across |
| **And it stays stopped while the finger is held** | still **4.9 studs/s** after 8 s of it: there is no throttle left to drive out with |
| **A corner.** A scripted 90° corner from a standing start, at 70% of a finger | entry **83.9** studs/s, peak slip **43.4°**, exit **57.7** studs/s (**69%** of entry), rear loose **0.242 s** after the input, turned **91.3°** |
| **No runaway.** 12 s of lock-to-lock with the drift held | top speed **31.5** (ceiling 103.5), top yaw **4.00 rad/s** (ceiling 4.00) |
| **No physics.** No BodyMover, VectorForce, constraint or joint, every part anchored | a fresh car and every live car: **5 parts, all anchored, nothing that moves them** |
| **A bare plate is drivable**, with nothing tagged `DriftSurface` | 87.5 studs/s, 0 s airborne |
| **The numbers live in Config.** Halving `TopSpeed` halves the car | 89.9 → 45.0 studs/s |
| **A respawn is not a teleport.** The packet after a respawn, and one in flight over it, both check out | both fit; the fall checks out at **200 studs/s** down |
| **A jump the server did not decide stays rejected.** The same jump, over and over, against a track that never moves | **20 of 20** packets 707 studs from where the server put the car rejected, and no `StateResyncDrops` left in Config |

**Driven live on the playground, 2026-11-03,** through the real drag gesture (`CarInputController:DebugDrag`), not the override behind it. Each hold is 2.5 s from about 80 studs/s, so these are the numbers on the way to the settled ones above, which is what a corner actually uses:

| Finger | Measured |
|---|---|
| 25% right | slip **+10.3°**, still at 102% of entry speed, heading +79.9° (left) |
| 50% right | slip **+26.9°** (leaned to 29.6), **88%** of entry speed |
| 75% right | slip **+39.5°** (leaned to 46.6), **50%** of entry speed |
| 100% right | leans to **66.2°** and is at **7%** of entry speed |
| 50% **left** | slip **−26.9°**, heading −96.2° (right): the exact mirror |
| The throw, to 75% | weight moving in **0.04 s**, slide 90% there at **0.41 s**, leaning to 46.7° at **0.74 s**, settling at 40.5° |
| The catch, from 40.5° | weight home in **0.26 s**, slide back under 5° in **0.39 s**, speed picking up again 44.3 → 51.3 |
| The server, across all of it | **0 dropped `CarState` packets**, 6 respawns, 0 refused: the new speed profile does not trip the server's bounds |

**The respawn, measured live on `DR-Lane1`, 2026-11-03.** The number this replaced: **340 dropped `CarState` packets** in one playtest before the server owned respawns.

| Driven | Measured |
|---|---|
| Drive off the edge of the plate (x ≈ 1050) and fall to y = −137 | the car comes back at the spawn (−160, 3, −75) 0.1 s later; **0 dropped packets** across the whole respawn |
| Six respawns in a row: two falls and four `DebugReset`s | **0 dropped packets**, 0 refused; the ask-to-answer round trip is **34–40 ms**; 1 packet in flight over a respawn kept by `RespawnGrace` |
| From the spawn to the first fall, 10 s of driving | **0 dropped packets** (it was 32 before the send clock was clamped: a long first frame used to be paid back as a burst at frame rate, which the rate limit dropped) |
| A client that jumps 900 studs **without** asking (`DebugTeleport`) | **69 packets dropped in a row**, nothing accepted; the old code gave in after 5. The server starts agreeing again only once the car has driven back inside what it could honestly have covered — which is what a distance budget can prove, and all it can |
| 20 `CarRespawn` requests in one second, fired at the raw remote with a CFrame payload | **2 granted, 18 refused** (`RespawnCooldown` 0.5 s); the payload ignored; 0 dropped `CarState` |

**What the rebuild changed, in one number.** The same 90° corner cost **16%** of its entry speed before (84% kept) and costs **31%** now (69% kept). The old full-lock corner input, unchanged, now turns the car **132°** and leaves it at **29%** — it is no longer a corner, it is the brake.

- **Playtest:** drive it. The user decides whether it feels right; that is the gate. Nothing above is a feel judgement — those checks only catch a model that has stopped working.

## Open questions

- ~~**The touch scheme:** two thumbs or a true one finger.~~ **Decided 2026-11-03:** one finger or the mouse, slid left and right, the same offset steering and drifting. The two-thumb scheme is dropped (`DECISIONS.md`).
- **Whether the flick should survive at all.** `DriftOffset` and `DriftFlickRate` no longer gate the drift — the offset commands the slide continuously — so all a flick does now is commit a small offset to the value of a press. Players of the reference game describe one continuous analogue axis and nothing else (conductor, 2026-11-03), which argues for dropping the flick. A playtest answer.
- **How much the car holds its own slide.** The front wheels follow the travel on their own, so the player never counter-steers (`CounterSteer`, `SlideBite`). That is a design decision, not only a tuning one: a car that holds its own slide is one a thumb can drive, and a car that does not is one the player learns to catch. Only the user can say which this game wants; `CounterSteer` and the `SlideKick`/`SlideBite` ratio are the dials either way.
- **Automatic throttle:** keeping it for good is a real design choice (accessibility, mobile), not only a prototype shortcut. Decide after the playtest.
- **Server validation of car state.** Half done. ~~The server cannot tell a respawn from a teleport, so after a few rejections in a row it takes the client's word (`StateResyncDrops`).~~ **Done 2026-11-03:** the server owns spawn and respawn positions, records what it expects, and `StateResyncDrops` is gone with the path that used it ("Server and client"). **Still open:** the checks bound speed and distance, they do not re-run the model — a client that feeds the server a legal-looking line it never drove is not caught, and `drifting` is taken on trust. Before anything is scored or sold, the server has to re-check or re-simulate the model, and decide what happens to a client that fails (today everything is dropped, nothing is kicked).
- **Car dimensions and weight balance:** one car for now, 16 studs long on a 12-stud wheelbase, with the contact points evenly split. Cars that feel different from each other is a meta decision, and waits on the open direction in `PITCH.md`.
