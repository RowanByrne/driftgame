# Feature: Drift model and one-input control

**Status:** the model is built and measured (`T-012`), and **waiting on the user to drive it** — the
feel is the gate. The control, the camera and the score below are specced and not yet built; each
is its own task, and all three read the numbers `T-012` has already written into
`Shared/Config/Drift.luau`. **Owner task:** `T-012` for the model; the plan behind `T-010`.

**This spec was rewritten on 2026-11-03 and supersedes the model that was on `main`.** Two
hand-built models have now been driven and neither felt right (`DECISIONS.md`, 2026-11-03): the
first steered the car directly, the second put the finger on the car's rear and made the slide a
fight between a shove and the car's own grip. The user then took the reference game apart and asked
for its gameplay, so the guessing stops here: this spec describes **the reference game's model
exactly**, read off its own code, and the build is a port rather than another attempt.

The prototype's whole point is still the same: prove the drift feels great before anything else is
built (`PITCH.md` "Biggest risks", `ROADMAP.md` "Next").

## What this is a port of, and what we keep of our own

The reference is a Unity game. What we take from it is **the model**: which quantities exist, what
each equation does, and what every number means. We write our own Luau from that description —
none of its source is copied, and none of its names, art, sound or text goes anywhere near this
game or its code (`PLATFORM-RISKS.md`, "Platform risks" below). Game mechanics are not the thing
copyright protects; a transliterated file would be.

What the port **cannot** give us: the reference ships its tuning as editor assets, not as code, so
the decompile has the equations but only the *fallback* values its code declares. Every number in
"Rules and numbers" is therefore either exact (it is written in the logic) or a declared fallback
converted to studs, and each is marked. The fallbacks are a credible starting car — they are not
the shipped car, and the user tunes from them.

Ours and staying ours: the fixed-step simulation and its determinism, the kinematic car (no Roblox
physics on it), the ground raycasts, the server owning spawns and respawns, the playground, and the
whole `Drift/` layout.

## Goal

A car that slides the way the hook promises, with the thing that makes the reference game feel the
way it does: **the player rotates the car directly, and the car's momentum lags behind.** One
finger across the screen is the whole control.

## How it plays

1. The player spawns in the playground already in the car and already moving.
2. **The throttle is not an input.** The car drives itself, and it eases in: half throttle at the
   start of a run rising to full over about five seconds, so a first-time player is never handed a
   car at top speed. There is no brake and no handbrake in normal play; the handbrake exists only
   to stop the car once a run is over.
3. **One finger, held, is the steering.** A finger goes down anywhere and from then on only its
   horizontal distance matters, measured either from the centre of the screen or from where it went
   down — a setting, because the reference ships both and they feel different. Full travel is a
   fraction of the screen that the sensitivity setting sets.
4. **That input is the car's rate of turn, directly.** Not a torque, not a wheel angle, not a
   target: the car's yaw rate *is* the input times `MaxSteeringSpeed`, every step. Centre the
   finger and the car stops turning that instant. This is the thing the two earlier models both
   missed, and it is why the reference feels like holding the car rather than driving it.
5. **The drift is what the car's momentum does about it.** Nothing moves the velocity when the car
   rotates, so the car's nose swings away from where it is actually going and the angle between the
   two — the slip angle — opens up on its own. **Rotating is drifting.** There is no drift button,
   no threshold, no mode.
6. **Grip is what closes that angle again, and it bites harder the wider the angle gets.** A
   lateral force pulls the velocity back toward wherever the nose is pointing, and its size grows
   with the slip angle as a quadratic, up to a ceiling. So a small slide is pulled straight gently,
   a big one is hauled round hard, and past the ceiling the car simply cannot generate more. The
   whole feel of the car is in those four numbers.
7. **Past square-on the grip becomes a brake.** Once the car is more than 90° away from its travel
   it is going backwards relative to its nose; the lateral force stops pointing sideways and points
   straight against the velocity instead. Spinning the car round is how you stop it.
8. **Speed is the drivetrain against the drift.** The engine pushes along the nose, with less to
   give the faster the car is already going (nothing left at top speed). A car that is sideways has
   its engine pushing across its own travel, so a drift costs speed without a single number saying
   so: the cost falls out of the geometry.
9. Downforce pins the car to the road in proportion to its speed, and switches off once the car is
   genuinely falling, so a jump is a jump.
10. A hit above a threshold, or the car ending up on its roof, ends the run. Falling off the world
    puts the car back at the spawn: the client asks, the **server** picks the place and moves it
    ("Server and client").

**Touch and mouse are the same gesture and the same code.** Keyboard and gamepad feed the same
single axis, scaled by their own sensitivity, because the model only ever wanted one number.

## Rules and numbers

Every number lives in `Shared/Config/Drift.luau`, none in the logic. **Units are studs**, converted
from the reference's metres at 1 stud = 0.28 m (× 3.571). Angular rates are unitless in length and
carry over as they are.

Each row says where the number comes from: **exact** (written in the reference's logic),
**fallback** (the value its code declares when an asset does not override it) or **ours**.

### The step

| Number | Start | Source | What it does |
|---|---|---|---|
| `FixedStep` | 1/120 s | ours | Simulation step. The reference uses 1/60; every term below is written per second and multiplied by the step, so the two agree |
| `Gravity` | 35 studs/s² | exact | 9.8 m/s². **Not Roblox's 196** — the reference turns Unity's gravity off and applies its own, and the whole feel is built on that |

The reference applies downforce once per physics step with no step length in it, which makes that
one term depend on its 1/60. We write it per second (below) and it matches at 1/60.

### Steering — the control

Every step: `yawRate = MaxSteeringSpeed × steer × SteeringSensitivity`, and the heading integrates
that. The car's rate of turn is *set*, not pushed. There is no yaw inertia, no yaw damping and no
steering lock in the model, and **adding any of them breaks the feel this spec is for.**

| Number | Start | Source | What it does |
|---|---|---|---|
| `MaxSteeringSpeed` | 2 rad/s | fallback | The car's rate of turn at full finger: 115°/s. **The single biggest feel dial** |
| `SteeringSensitivity` | 1 | exact | Per-car multiplier on it |
| `InvertSteering` | true | ours | Which way a finger turns the car. True is the sense the user asked for in `T-007`: it reads as holding the car's rear |

### Grip — the drift

Every step, if any wheel is on the ground, with `b` the slip angle in radians (signed, from the
nose to the velocity, about the car's up):

```
bc   = min(|b|, pi/2)
f    = min(ConstantFriction + SlipFriction * bc + SlipSqFriction * bc^2, MaxFriction)
f    = f * surfaceGrip * FrictionMultiplier
dir  = if |b| > pi/2 then -normalize(horizontal velocity) else carRight * sign(b)
dv   = f * dt * dir,  each world axis clamped so |dv_axis| <= |velocity_axis|
velocity += dv
```

`surfaceGrip` is the mean of the four wheels' surface grip, so two wheels off the tarmac means half
the grip. The per-axis clamp is the reference's own, and it is what stops the pull overshooting
through zero at low speed. It has one artefact worth knowing before measuring anything: a car
travelling *exactly* along a world axis has no speed on the perpendicular axis for the clamp to
allow, so its sideways pull is suppressed until it has yawed far enough to build one. A player can
never be in that state; a test that starts a car at a heading of zero is, so the tests start theirs
at 15°.

| Number | Start | Source | What it does |
|---|---|---|---|
| `ConstantFriction` | 14.3 studs/s² | fallback | Grip with the car dead straight. Sets how quickly a tiny slide tidies itself up |
| `SlipFriction` | 14.3 studs/s² per rad | fallback | How fast grip builds with the angle |
| `SlipSqFriction` | 14.3 studs/s² per rad² | fallback | The squared term: what makes a big slide bite far harder than a small one. **Raise it for a car that catches itself, drop it for one that keeps going round** |
| `MaxFriction` | 107 studs/s² | fallback | The ceiling on all of it: the tightest circle the car can hold. 3 g |
| `MinSlipAngleForDrift` | 5° | exact | Below this the car does not count as drifting, for the readout and the score |
| `FrictionMultiplier` | 1 | exact | Per-car multiplier |
| `GripTarmac` | 1.0 | fallback | Surface grip on tarmac |
| `GripDirt` | 0.5 | fallback | Surface grip on dirt |
| `GripUnspecified` | 0.1 | fallback | Anything solid that is not a tagged surface. Nearly nothing: off the road the car barely corrects |

### Drivetrain

Rear-wheel drive: the push only happens when at least one rear wheel is down.

```
u = |velocity projected on the car's forward|
a = MaxAcceleration * AccelMultiplier * clamp01(throttle) * clamp01(1 - (u / TopSpeed)^2)
velocity += a * carForward * dt
```

| Number | Start | Source | What it does |
|---|---|---|---|
| `MaxAcceleration` | 14.3 studs/s² | fallback | Push off the line |
| `TopSpeed` | 179 studs/s | fallback | Where the push reaches zero. 50 m/s |
| `StartThrottle` | 0.5 | fallback | Throttle at the start of a run |
| `FullThrottleSeconds` | 5 s | fallback | How long it takes to reach full |
| `HandbrakeDecel` | 36 studs/s² | fallback | Only used to stop the car after a run |

`u` is a *magnitude*, so reversing counts as speed for the falloff. That is the reference's own
quirk and it is kept: it matters only in the rare case of a car travelling backwards under power.

### Downforce

If the car is not falling faster than `DownforceCutoff`:
`velocity += down × speed × DownforcePerSpeed × dt`.

| Number | Start | Source | What it does |
|---|---|---|---|
| `DownforcePerSpeed` | 0.2 /s | **neither** | Extra downward pull per stud/s of speed: at top speed, one extra gravity. The reference's own value is an editor asset the decompile does not have, and its code's fallback is nonsense when converted. **Tune this first; it is the one number in this spec that is a guess** |
| `DownforceCutoff` | −3.6 studs/s | fallback | Vertical speed below which downforce stops, so a real fall is a real fall |

### The car

| Number | Start | Source | What it does |
|---|---|---|---|
| `Wheelbase` | 9.6 studs | fallback | 5.07 front / 4.57 rear of centre. Only the suspension and the wheels use it — the model has no bicycle geometry |
| `TrackWidth` | 5.6 studs | fallback | 5.57 front, 5.71 rear |
| `WheelDiameter` | 2.3 studs | fallback | |
| `CenterOfMass` | (0, 0.71, 0) | fallback | |
| `BodyRollMax` | 10° | fallback | Cosmetic lean, at `BodyRollSpeed` of lateral speed |
| `BodyRollSpeed` | 107 studs/s | fallback | |
| `BodyRollRate` | 10 /s | fallback | How fast the lean follows |

**Ground.** One downward ray per wheel each step; the car's height, pitch and roll follow the
surface. The reference runs a real spring-and-damper suspension per wheel; we keep our existing
raycast-and-follow, because the kinematic car cannot take forces at a point and the suspension's
only job the player can feel is the tilt. If the car later needs to visibly squat and dive, that is
its own task.

**Determinism.** Fixed step, no random input: the same inputs from the same start give the same
line, at any frame rate. That is what makes a drift learnable and a score worth chasing.

## The control

| Number | Start | Source | What it does |
|---|---|---|---|
| `InputMode` | dynamic | exact | `centred`: offset from the middle of the screen. `dynamic`: offset from where the finger went down. The reference ships both as a setting; so do we |
| `SliderWidthMin` | 0.5 | fallback | Full travel as a share of half the screen width, at the highest sensitivity |
| `SliderWidthMax` | 1.2 | fallback | The same at the lowest. Sensitivity 1–10 lerps between them, **backwards**: higher sensitivity means a *shorter* travel |
| `Sensitivity` | 5 | ours | Where that starts, until there is a settings screen |
| `KeySensitivity` | 0.75 | fallback | What a keyboard key or a stick is worth as a share of full travel |

The reference draws the slider only while the finger is down: a track at the finger's height, as
wide as the current travel, with a knob that eases toward the real value. We draw the same, as
programmer art, plus a readout of speed, slip angle, yaw rate, grounded and the step.

## Camera

The reference's camera does three things at once, and together they are most of why its drifts read
as drifts. All three are driven by the same slip angle the model already has.

1. **It swings toward where the car is going, not where it points.** The resting place is behind
   the car's nose; as the slip angle opens, the target slides toward a point directly behind the
   *velocity*, by an ease-in-out of `|slip| / 180°`. So a straight line is a chase camera and a big
   drift is a side-on shot, with everything between.
2. **It rolls.** The whole view tilts about its own forward axis, up to `CamRollMax`, reaching full
   tilt by `CamRollAtAngle` of slip. This is the cheapest and largest part of the effect.
3. **It pulls in.** The distance shrinks toward `CamDriftDistance` of its resting length as the
   slip opens, full in by `CamZoomAtAngle`.

Position eases toward its target rather than snapping; the look-at eases separately and more
slowly, which is what keeps the horizon from jittering. On a run ending the camera lets go and
holds its last target.

| Number | Start | Source | What it does |
|---|---|---|---|
| `CamOffset` | (0, 28.6, −35.7) studs | fallback | Resting place behind and above the car |
| `CamLookAt` | (0, 0, 10.7) studs | fallback | What it looks at, ahead of the car |
| `CamVelocityBlend` | 0.05 | exact | How much of the swing-to-velocity is actually used. **The reference's own value, and it is small** — the swing is a hint, not a side-on shot. Worth raising to taste; it is why its camera looks calm |
| `CamSwingRate` | 1 /s | fallback | How fast the velocity-based target follows |
| `CamAngleRate` | 1 /s | fallback | How fast the resting direction follows the car round |
| `CamHeightRate` | 1 /s | fallback | How fast the look-at height follows |
| `CamRollMax` | 45° | fallback | Full roll |
| `CamRollAtAngle` | 20° | fallback | Slip angle that reaches it |
| `CamRollRate` | 20 /s | fallback | How fast the roll follows |
| `CamDriftDistance` | 0.5 | fallback | Share of the resting distance at full drift |
| `CamZoomAtAngle` | 90° | fallback | Slip angle that reaches it |
| `CamZoomRate` | 1 /s | fallback | How fast the zoom follows |
| `CamSmoothTime` | 0.1 s | fallback | Position easing |
| `CamLookRate` | 8 /s | fallback | Look-at easing |
| `CamFovBase` | 70° | ours | Kept from what is on `main` |
| `CamFovTop` | 86° | ours | At top speed |

## Score

Only while the car is drifting (slip ≥ `MinSlipAngleForDrift`) and making forward progress:

```
base       = |slipAngle| * speed * surfaceScore * ScoreRate * dt
score     += base * multiplier
progress  += clamp(base * ProgressRate - (grounded and MultiplierDecay * multiplier * dt or 0),
                   -MaxProgressDown * dt, MaxProgressUp * dt)
progress > 1          -> multiplier += 1 (to MaxMultiplier), progress -= 1
progress <= MinProgress -> multiplier -= 1 (to 1), progress += 1 - MinProgress
```

So the multiplier climbs while the car is sideways and bleeds away while it is not, and it bleeds
faster the higher it already is — the ladder gets harder every rung.

| Number | Start | Source | What it does |
|---|---|---|---|
| `ScoreRate` | 0.2864789 | exact | Points per radian per stud. (The reference's constant is per metre; this is it converted) |
| `MaxMultiplier` | 9 | fallback | |
| `ProgressRate` | 0.06 | fallback | How fast drifting fills the next rung |
| `MultiplierDecay` | 0.15 /s | fallback | Decay per rung per second on the ground (its `3 × 0.05`) |
| `MaxProgressUp` | 1.0 /s | fallback | Ceiling on how fast the bar fills |
| `MaxProgressDown` | 0.75 /s | fallback | And empties |
| `MinProgress` | −0.25 | fallback | How far below empty before a rung is lost |
| `ScoreTarmac` | 1.0 | fallback | Score multiplier by surface, averaged over the four wheels |
| `ScoreDirt` | 0.5 | fallback | |
| `ReverseDriftBonus` | 400 | fallback | A drift past 90°, held: `floor(ln(t + 1) × 400)` at the end of it |
| `AirTimeBonusMin` | 10 | fallback | Airborne, forward: an exponential in the air time, ignored below this |

## UI

Programmer art only, until the UI phase. Top left: the debug readout. Bottom: the slider while a
finger is down. Top centre: score, the multiplier and its progress bar, and a bonus that pops when
it lands. Nothing else, and none of it is the shipping HUD (`UI-INVENTORY.md`).

## Server and client

Unchanged from what is on `main`, and nothing in this port touches it. The player's own car is
simulated on the client that drives it; the server owns where a car may be put — its spawn and
every respawn — bounds the speed and distance in each `CarState`, and replicates each car to the
other clients. `RespawnGrace` still covers a packet in flight over a respawn.

**Score is client-side and untrusted in this prototype,** like everything else here. Before a score
is ever saved, shown to another player or paid for, the server has to re-derive it from state it
has checked — the same open question the model already carries, and the same answer.

## Contracts

No new remotes. Changed in `CONTRACTS.md` in the same commit as the code:

- `DriftController:DebugState()` loses the departed model's fields (`load`, `slideFrac`,
  `gripBlend`, `weight`) and gains `slipDeg`, `yawRate`, `throttle`, `surfaceGrip` and
  `grounded` (four flags).
- `DriftController:DebugDrive(inputs, seconds, opts)` keeps its shape; its summary loses
  `breakLooseSeconds` (there is no break-loose event any more — rotating is drifting) and gains
  `peakMultiplier` and `score`.
- `CarInputController:DebugSetInput(steer, throttle)` replaces the three-argument form; `drift` and
  `brake` are gone. `DebugDrag(offsetPx)` still acts out the real gesture. **Not done yet:** that
  file belongs to the gesture task. Until it lands, `DriftController` takes the old three-value
  answer and drops the drift flag (rotating is drifting, so it has nothing left to mean) and passes
  the brake through as the handbrake.
- New `ScoreController:DebugState()`: score, multiplier, progress and the live bonuses.

## Analytics

None yet. The loop's events are designed with the scoring feature proper, not bolted on here
(`ANALYTICS.md`).

## Monetization

None.

## Platform risks

**Copyright.** The reference game's name, art, sound, text and source stay out of this game, its
repo and anything a player sees — the decompile is read in `_decompiled\`, outside the repo, and
nothing from it is committed. The car is an untextured block of our own with no manufacturer's
shape, name or badge (`PITCH.md` "Biggest risks"). What we take is how the maths works, which is
not what copyright covers.

## Art and sound

Placeholder: the car is a box with four cylinders, built by code. No sound yet; engine and tyre
sound are their own task once the feel is agreed (`AUDIO.md`).

## Testing

Measured, not guessed (`TESTING.md`). `ServerScriptService/Tests/DriftTests.luau`, through the
server bridge. The checks that must still pass, and the new ones the port needs:

| Check | What proves it |
|---|---|
| A repeatable line | `DebugDrive` twice from one start, within a stud |
| Frame independence | The same inputs at 30, 60 and 120 FPS, within 2 studs |
| **Rotating is drifting** | Hold a steady finger from speed: the slip angle opens on its own, with no drift input anywhere |
| **The finger is the rate of turn** | Heading change over a hold = `MaxSteeringSpeed × steer × time`, within a degree, at any speed |
| **Centring stops the turn at once** | Yaw rate is zero on the next step after the finger centres |
| **Grip grows as a quadratic** | Slip angle held at 15, 30, 45, 60, 80°: measured lateral pull matches `C0 + C1·b + C2·b²`, capped at `MaxFriction` |
| **Past 90° the grip brakes** | A car spun past square loses speed along its travel and gains none sideways |
| **A drift costs speed** | Held drifts at a quarter, half and full finger: speed kept, and the circle each describes |
| **Surfaces matter** | The same drift on tarmac and on dirt: grip and score both halve |
| **The multiplier ladder** | A long drift climbs 1→9; letting go bleeds it down, faster from 9 than from 2 |
| No runaway | Lock-to-lock for 12 s: speed and yaw stay inside their ceilings |
| No physics | Every car part anchored, no BodyMover, VectorForce, constraint or joint |
| The numbers live in Config | Halving `MaxSteeringSpeed` halves the rate of turn |
| The server still holds | A playtest with 0 dropped `CarState` packets, and a jump the server did not decide still rejected |

- **Playtest:** drive it. The user decides whether it feels right; that is the gate. Nothing above
  is a feel judgement — those checks only catch a model that has stopped working.

### What it measured, 2026-11-03 (`T-012`)

All eighteen checks pass. The numbers worth carrying into the tuning conversation:

| | |
|---|---|
| The finger is the rate of turn | A second of half a finger turns the car 56.82°, against the 57.30° `MaxSteeringSpeed` asks for, from 40 studs/s and from 150 alike. The 0.48° is one step of the accumulator's leftover, not the model |
| Centring | Yaw rate exactly 0 and the heading exactly still on the next step |
| Grip, measured against the curve | 15°: 19.0, 30°: 25.7, 45°: 34.4, 60°: 45.0, 80°: 62.1 studs/s², every one within 0.001 of `C0 + C1·b + C2·b²`. Dirt is exactly half |
| Past 90° | 135° of slip, engine off: 72 studs/s² straight against the travel and 0.000 sideways |
| A held finger | ¼: 12° of slip, 40 studs/s, a 79-stud circle. ½: 33°, 32 studs/s, 32 studs. Full: 30°, 15 studs/s, 7 studs — from 140 studs/s in each case |
| Determinism | Identical twice over; 0.24 studs between 30, 60 and 120 FPS over a five-second corner |
| Nothing runs away | 12 s lock to lock from top speed: 179.0 studs/s and 2.000 rad/s, both their own ceilings |

Three things the measurements say about the numbers, for the user to decide on:

- **`MaxFriction` is inert as tuned.** The three friction terms reach only 72 studs/s² at square-on,
  so the 107 ceiling is never touched. Raising `MaxFriction` alone does nothing; the three terms are
  the dial.
- **A hold at speed is a spin, not a drift.** Holding half a finger at 140 studs/s needs 140 studs/s²
  of pull to hold the circle and the car can make 72, so the slip runs past 90°, the grip turns into
  a brake, and the car settles at 28 studs/s. The car can only *hold* a drift at about a quarter of
  its top speed. That is the fallbacks, not the port — it is what "expect to move `MaxSteeringSpeed`,
  the three friction terms and `MaxFriction` together" means in numbers.
- **Downforce is only felt in the air.** A car that follows the ground cannot be pressed into it, so
  the only thing `DownforcePerSpeed` changes is a jump. Off a 1-in-4 ramp at 150 studs/s: 331 studs
  and 2.18 s at 0, 213 studs and 1.40 s at the specced 0.2, 168 studs and 1.11 s at 0.4.

## Open questions

- **`DownforcePerSpeed` is a guess** (above). It is the only number here that is not read off the
  reference. Measured, 0.2 is a fair starting point and the car is neither glued nor floaty on the
  road — because on the road it changes nothing at all (above). It only shortens a jump, and the
  reason a jump feels long is `Gravity` being the reference's 35 studs/s² rather than Roblox's 196.
  If jumps want to feel heavier, raise this to 0.4 before touching gravity.
- **The tuning values are fallbacks, not the shipped car.** The reference's real numbers live in
  editor assets the decompile does not contain. Expect to move `MaxSteeringSpeed`, the three
  friction terms and `MaxFriction` together before it feels like the reference.
- **Centred or dynamic slider.** Both are built and both are in the reference as a setting; the
  user says which this game defaults to.
- **What a run is.** This spec is the car, its control, its camera and its score — the reference's
  endless generated road, its crash-ends-the-run structure, its stages, cars and shop are **not**
  in it, and are not decided (`PITCH.md` is still Draft). The playground stays the place to feel it.
- **Server validation.** Unchanged and still open: the checks bound speed and distance, they do not
  re-run the model, and the score is taken on trust. Before anything is scored, saved or sold, the
  server has to re-derive it.
