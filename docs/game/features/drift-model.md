# Feature: Drift model and one-input control

**Status:** built, driven and **approved by the user on 2026-11-03** — the model (`T-012`), the
one-finger control (`T-013`) and the camera (`T-014`), all merged and measured. The **Score**
section below is specced and **deliberately not built**: the user deleted that task
(`DECISIONS.md`, 2026-11-03). Everything else here describes code that exists. **Owner task:**
none; the plan was `T-011`.

Tuning is numbers in `Shared/Config/Drift.luau`, not code. One open tuning question survives the
approval and is in "Open questions": only the bottom fifth of the finger's travel is usable before
the car spins rather than drifts.

**Two changes have been made since that gate, and both are switches that give it back exactly:**
`GravityOnGround` ("Gravity", `T-065`) and `UnstickSpeed` ("Pinned against a wall", `T-074`). Each
has a check whose only job is to prove the flat road is untouched.

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
   car at top speed. There is no brake pedal — **the handbrake is a latch** (`T-041`): one press
   stops the car and it stays stopped, a second drives off again, and the button and the key share
   one latch so they cannot disagree. A respawn or a car switch clears it, because both are the
   server handing over a fresh car. You can still rotate the car while it is stopped, which is how
   a shot gets lined up.
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
| `Gravity` | 35 studs/s² | exact | 9.8 m/s². **Not Roblox's 196** — the reference turns Unity's gravity off and applies its own, and the whole feel is built on that. Applied every step, in the air and on the ground both ("Gravity", below) |

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

### Gravity (`T-065`)

Gravity is applied **every step, grounded or not** — and that is a change made on 2026-11-04, the
first change to this model since the user approved the feel. It was conditional before: full
gravity in the air, none at all on the ground, *"on it, the height and the vertical speed both come
from the surface below"*. On a flat road those are the same thing. On a slope they are not, and the
conditional one is wrong.

**What the reference does.** `CustomGravity.FixedUpdate` is two lines and has no condition in it:
`rigidbody.velocity -= Vector3.up * 9.8 * dt`. The car is a Rigidbody held up by four suspension
springs (`CarSuspension`), and each spring pushes along **the car's own up axis**. A spring pushes
along that axis; gravity pulls straight down; **on a slope the two differ and the difference is
never cancelled** — so the car runs away downhill with no code anywhere that mentions a slope. The
behaviour is emergent, not scripted.

**What we do.** Our car is kinematic — four downward rays and the surface height written straight
in — so there is no spring to port. It does not need the spring; it needs the spring's *result*:

```
g_along   = g − up * (g · up)
velocity += g_along * GravityOnGround * dt       -- while grounded. Airborne is unchanged
```

| Number | Start | Source | What it does |
|---|---|---|---|
| `GravityOnGround` | 1 | ours, from the reference's behaviour | Share of gravity that acts along the surface while grounded. **1 is the reference. 0 is exactly the model the user approved** — a switch, because this is the first change since that gate |

Four things about it, and the last two are the ones that are easy to get wrong:

- **On flat ground `g_along` is exactly zero.** Not small: zero, because `up` is exactly vertical
  and stays there. Flat driving is untouched at any value of this number, and that is a measurement
  (below), not an argument.
- **A bank needs no special case.** `g_along` on a bank points down the banking, and the grip that
  holds the car on it already acts in the surface's plane along the car's tilted right axis
  (`basis`). That is *"how the tyres grip the road when you are on an angle"*, and it falls out.
- **`up` is the SMOOTHED body up, not the raw normal the rays found,** and that is deliberate
  twice over. It is the reference's own choice — the springs cancel gravity along `transform.up`,
  the body's attitude, which lags the road because it is sprung — and it is the axis the grip
  already acts in, so the model keeps **one frame for both forces**. The raw normal stays on the
  constraint, where a raycast length is in the reference: the ground follow uses it to decide how
  fast the surface is climbing. Over a crest the lag means the pull downhill arrives as the car
  settles on to the new slope, rather than the instant a ray sees it.
- **It is not double-counting `climb`.** `g_along` has a vertical part, and while the car is
  grounded `climb` *overwrites* the vertical speed from the horizontal velocity and the surface —
  so only the horizontal part of `g_along` survives a grounded step. That part is `g·sin(t)·cos(t)`,
  which is exactly what a velocity held in the surface's plane needs: measured, the along-slope
  deceleration is `g·sin(t)` to three decimals, every step. The vertical part survives only on the
  one step the car leaves the ground, which is the step it should.

### Pinned against a wall (`T-074`)

**The second change to this model since the user approved the feel, and like the first it is a
switch.** `UnstickSpeed = 0` is the approved model exactly — measured, not asserted: the same corner
with it on and off is bit-identical, and the whole 50-piece road drive at `0` reproduces every
number the drive produced before this existed.

**The trap, which is arithmetic rather than a bug in anything.** Let `t` be the angle between the
car's nose and a wall it is touching. Along that wall:

```
the drivetrain pushes   MaxAcceleration * cos(t)      = 14.3 cos(t)
the grip pulls back     f(t) * sin(t)                 = (14.3 + 14.3·t + 14.3·t²) sin(t)
```

The grip's pull is `carRight × sign(b)` — sideways **in the car's frame** — so with the nose into a
wall and the travel along it, "sideways" *is* along the wall and backwards. The wall deletes the
into-the-wall half of both and what is left is a brake against a push. **They cross at about 27° of
nose angle**, and past it the car stops at 0.07 studs/s and never moves again: the reference's
per-axis clamp holds it at exactly what one step of drivetrain adds. Above about 45° the `WallScrub`
takes over as well — a car whose own engine is the biggest thing pointing into the wall is charged a
crash on every step, keeping half of what little it has, 120 times a second.

Three things the measurement settled that guessing had not:

- **It is not the past-90° brake.** A car nose-*on* to a wall scrapes along it at 120 studs/s on a
  30° bank quite happily. The trap bites from 27° of nose, where the grip is still an ordinary
  sideways pull and nothing in it is a brake by intent.
- **It is not the bank.** The equilibrium is 0.07 studs/s at 10° of bank and at 30° alike. The
  bank's only job is to keep feeding the car back into the wall so the nose-in state lasts.
- **A player can get out and the test autopilot cannot.** Point the nose within ~15° of the wall and
  the engine pulls the car out to 50 studs/s. That window is about 25° wide and the car gives no
  feedback at all while it is stopped, which is why this is fixed rather than left to the driver.

**What the fix is: withholding, never pushing.** While the car counts as pinned, the grip is not
applied and the wall scrub is not charged. Nothing is added to the velocity, the car is moved
nowhere, and `vel -= n·into` and the sweep's position clamp are untouched — **a wall is still a
wall**, measured at 0.000 studs of penetration through an escape from every nose angle.

**Pinned means *held*, not *touching*.** The first version asked for unbroken contact and never
fired once: on the real road a car held against a barrier for 40 s reported a wall on **387 steps
out of 4 824** — one in twelve — because `WallPush` holds it a fifth of a stud clear and gravity has
to carry it back across that gap before the next Blockcast reaches anything. So it is two clocks,
both in `UnstickSeconds` and both load-bearing: a **dwell** (that slow for that long — without it a
car that merely *dips* under the speed in a corner loses the grip that rotates it, and the 50-piece
drive falls from 50 pieces to 37) and a **window** (a wall touched inside it — without which nothing
fires at all, because of the gaps).

| Number | Start | Source | What it does |
|---|---|---|---|
| `UnstickSpeed` | 5 studs/s | ours | Slower than this, with a wall about, the car is pinned. **0 turns the whole thing off.** The pin's own equilibrium is 0.07 studs/s, so a genuinely stuck car is far under this |
| `UnstickSeconds` | 0.2 s | ours | Both clocks: how long that slow, and how recently a wall. Long enough to bridge the gaps between touches, and no longer |
| `UnstickRelease` | 45 studs/s | ours | The pin also ends at this speed, even if the car is still scraping. The guard against a car that never loses contact keeping its grip off at speed |

**Both numbers fail the same way when they are too big, and that is measured.** Make either one
generous and the grip comes off a car that is merely *slow near a barrier* — which is a hairpin,
where the grip is what rotates the car. Over 50 generated pieces at 10° of bank: `UnstickSpeed` at 5
drives all 50 and is stopped 1.4 s, **at 15 it drives 37 and is stopped 13.2 s**; `UnstickSeconds`
at 0.2 is better than or equal to the unstick being off on every seed tried, **at 0.5 one seed falls
from 214 s stopped to 0.7 and another climbs from 40 to 173.** This may only ever fire on a car that
has genuinely stopped, right next to the thing that stopped it.

**What it does and does not buy, honestly.** In isolation it is decisive: a car nose-in to a barrier
goes from *never moving again* to **off the wall inside 4 s from every angle but a right one**. On
the real road, where the test autopilot drives, it is a clear gain on the seeds where the pin is
what stopped the car (8080: 40.2 s → 1.4 s stopped, all 50 pieces either way; 99991: 105 s →
90.5 s) and no change at all on the seeds where something else did (seed 1: 213.9 s either way,
41 pieces either way). **A 400-second autopilot drive is
chaotic and one seed's stopped-time is noise** — the same change reads 1.4 s and 213.9 s on two
seeds — so the numbers above are chosen on the distribution and on the mechanism, never on one run.
Getting the rest of the way is a respawn backstop and a better test driver, not more model.

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

Three rules the ground code lives by, all three of them learned the hard way (`T-026`):

- **The follow moves the car's height and nothing else.** The vertical speed is the speed the
  *surface* is climbing under the car — the velocity's own component in the plane of the ground,
  and zero if the ray came back with a normal too steep to stand on. Taking it from the follow
  instead (`(newY - y) / dt`) makes the follow an undamped spring at about 8 per second: every
  landing rang at 5 Hz for a second, and a kerb the rays found above the car threw it. Measured,
  the playground's 8.35-stud rim took the car from 0 to 141 studs/s upward in two steps.
- **Only the wheels that are carrying the car set its height and tilt.** A wheel whose ground is
  more than a ride height below the highest is hanging over a drop; averaging it in sinks the body
  into the edge the other wheels are still on. Grip and score still count all four, so what a slide
  does at an edge is unchanged.
- **A floor's sides are walls** — that is `Drift/World`'s business, not the model's, but it is the
  other half of the same problem. A ramp is 14 studs thick and its flanks are as solid as a
  building's.

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

**Corrected 2026-11-03, after the user drove the first build:** "the camera is off in a big way. it
spins/rotates wayyyyy to far and i'm not even sure if it's the right direction. just copy drifto for
now." The cause was this spec, not the build. The decompile contains **two** cameras and this
section described the wrong one. The game's camera is the one whose field another script calls
`...New`, which the player's camera-mode setting drives and which the FOV controller reads; the
other is its predecessor, kept in the binary and driven by nothing the game runs. **The roll and the
zoom were the old one's, and the game has neither.**

So: no roll, no zoom, no position smoothing. The camera is **placed** each frame, not eased into
place — the easing is all inside how its target is worked out — and it simply looks at the car, so
the horizon is always level.

What it does:

1. **It looks at a point just ahead of the car** (`CamLookAt`), with only that point's *height*
   eased (`CamHeightRate`).
2. **It sits at `CamOffset`'s distance from the car, in a direction that follows the car round.**
   The direction, not the position, is what eases (`CamAngleRate`) — so the camera swings around
   the car at a fixed radius instead of being dragged behind it.
3. **It leans that place toward being behind the car's travel as the slip angle opens**, by an
   ease-in-out of `|slip| / 180°`, toward a point that itself eases (`CamSwingRate`). Then only
   `CamVelocityBlend` of that lean is taken.
4. **The FOV opens with speed** (`CamFovBase` + `CamFovPerSpeed` × speed, eased at `CamFovRate`).

On a run ending the camera lets go and holds its last target.

**`CamVelocityBlend` is 0.05 and that is not a typo.** The reference feeds its *blended* target back
in as the next frame's resting direction, so the 5% is applied again every frame and compounds: what
the player sees is not a side-on shot but the camera **dropping and swinging wide** through a drift.
Raising it is the dial for a more dramatic camera, and it mostly buys height drop.

**The targets run on their own fixed step** (`CamTargetStep`, 1/60, the rate the reference ran at).
That feedback means where the camera settles depends on how often it is stepped, so left at frame
rate it sits at a different height on every machine — measured, 16.2 studs up at 30 FPS against 10.1
at 120. The model's step is deliberately separate and finer.

| Number | Start | Source | What it does |
|---|---|---|---|
| `CamOffset` | (0, 14.3, −53.6) studs | fallback | Resting place: how far behind and above. Its **length** is the radius the camera keeps; its direction is the resting direction. (0, 4, −15) m, from the camera-mode setting's own default — low and well back, which is most of why the reference reads flat and fast |
| `CamLookAt` | (0, 0, 10.7) studs | exact | The point it looks at, ahead of the car |
| `CamVelocityBlend` | 0.05 | exact | How much of the lean toward the travel is taken each frame — and it compounds (above) |
| `CamSwingRate` | 1 /s | fallback | How fast the behind-the-travel point follows |
| `CamAngleRate` | 1 /s | fallback | How fast the resting direction follows the car round. **The main feel dial:** low is a camera that lags and lets the car rotate in front of it, high is one glued behind the nose |
| `CamHeightRate` | 1 /s | fallback | How fast the look-at's height follows |
| `CamFovBase` | 60° | fallback | FOV at a standstill |
| `CamFovPerSpeed` | 0.14 °/(stud/s) | fallback | How much it opens with speed: 85° at top speed. (0.5 per m/s) |
| `CamFovRate` | 0.5 /s | fallback | How fast the FOV follows. Slow on purpose |

### The pan (`T-036`) — ours, not the reference's

Hold the **right** mouse button and drag to look around. It is an **orbit offset**, not a second
aim: a yaw and a pitch the placed camera is rotated by *about the car*, at the same radius, still
looking at the same point. So the car stays centred and followed, the lean and the FOV keep doing
exactly what they did, and the player is only moving round the car to see something.

**It is applied to the rendered position, after the fixed-step targets are done with, and written
nowhere the targets can read it.** That is the whole reason it cannot disturb the camera — part 3
feeds back into part 2, and the pan is downstream of both. Proven rather than asserted: `main`'s
camera and this one, run side by side through the same probe at 30, 60 and 120 FPS and at 0° and
45° of slip, differ by **exactly 0** on distance, height, lean, FOV and roll.

**The mouse is deliberately not locked.** Steering is measured from where the cursor *is*, so
locking it would freeze the car's rate of turn the moment the right button went down. The cost is
that a pan stops at a screen edge, which is the better half of that trade.

Let go and it comes back: a moment's grace so a nudge does not snap the view out of the player's
hand, then an ease home over about three seconds.

**Touch and gamepad have no pan.** A second finger would collide with the steering finger, and
nobody has asked for one — it is a decision, not an oversight.

| Number | Start | Source | What it does |
|---|---|---|---|
| `CamPanSensitivity` | 0.005 rad/px | ours | 0.286°/px, so a 400-pixel drag is 114.6°. About what Roblox's own camera does |
| `CamPanRate` | 9 /s | ours | How fast the view follows the hand: a 111 ms time constant. **The "slightly smoothened" dial** — lower is more cinematic, and past about 5 it reads as lag rather than weight |
| `CamPanReturnDelay` | 0.5 s | ours | How long after letting go before it starts coming home |
| `CamPanReturnRate` | 2 /s | ours | How fast it comes home once it starts |
| `CamPanPitchMin` / `CamPanPitchMax` | −12° / 60° | ours | How far the view may be dragged down and up, as an offset |
| `CamPanElevationMin` / `CamPanElevationMax` | 1° / 80° | ours | The hard guard, on the **result**: never under the road, never straight down the roof |
| `CamTargetStep` | 1/60 s | ours | The step the targets run at, interpolated between (above) |
| `CamMaxTargetSteps` | 8 | ours | Safety: a stalled frame is not paid back as a burst |

**Not built, and deliberately:** the reference also has three camera modes the player picks between
(normal, far, chase — only their class default is in the decompile) and a speed-based camera shake.
Both are their own task if the user wants them.

## Score

> **Specced, not built, and that is deliberate.** This was the fourth step of the plan and the user
> deleted it on 2026-11-03 (`DECISIONS.md`). Nothing below exists in the code. It is kept because
> the maths was read off the reference and is worth not having to read again — build it from here
> if and when a run is worth scoring.

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

**The reference game.** Its name, art, sound, text and source stay out of this game, its repo and
anything a player sees — the decompile is read in `_decompiled\`, outside the repo, and nothing
from it is committed. What we take is how the maths works, which is not what copyright covers.

**The car is no longer ours, and this is the open risk.** Since `T-020` it is a real
manufacturer's car, taken from a third party's Creator Store upload that the uploader near
certainly had no right to make, and the manufacturer's model name is now in our own source as mesh
part names. No Initial D livery came across — every decal and texture was checked, and the body is
plain white — so the anime trade dress is absent and the vehicle design is not. A takedown would
land on the **owner's account**, not the uploader's.

**It is a placeholder for the feel test and is not approved to publish.**
`assets/car-ae86/MANIFEST.md` records where it came from and says so; a user decision in
`DECISIONS.md` comes before it goes anywhere near a published place. Swapping it is one module in
`Shared/Cars` and one string in `Config.Drift.CarBody`.

## Art and sound

Placeholder: the AE86 the user added to the Main place, read out of it and written down as Luau in
`Shared/Cars/AE86` (`T-020`) — 98 anchored parts, scaled onto the config's wheelbase and wheel
diameter rather than the config being bent to the car. Its PBR maps did not survive: a running game
cannot create a `SurfaceAppearance` (plugin-only), so each mesh keeps its colour map as a
`TextureID` and the normal, metalness and roughness maps are dropped.

The box with four cylinders is still there as `CarBody = "block"`, for a place whose meshes will not
load and for the tests. No sound yet; engine and tyre sound are their own task once the feel is
agreed (`AUDIO.md`).

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
| **Walls are solid** | Ram a building, a pillar and a cone head-on at top speed, plus a glancing hit, a sideways slide and the slowest possible nudge: the car's body never enters the part, and driving along a wall neither sticks nor climbs. `DebugCollisionTests` |
| **A ramp is a jump** | The playground's ramp at five speeds from a crawl to top speed, square on and at 15 and 25 degrees off: the car leaves the ground, comes down on it, and never ends a step inside the ramp. `DebugCollisionTests` |
| **A bowl is a surface** | The banked circle crossed at 60, 120 and 179 studs/s, square to it and on a chord through the band, driven out of the middle, driven round on the band and crawled into at a quarter of a stud a second: never airborne, never inside anything, and no vertical speed the ground cannot explain. `DebugCollisionTests` |
| **Nothing is random** | The same approach at the bowl and the ramp twice, within a stud. `DebugCollisionTests` |
| **The car is drawn where it is** | `drawnGap` stays near zero, and the drawn car's frame-to-frame step error stays under a tenth of a simulation step — **measured on a frame clock that does not divide `FixedStep`.** A dead-steady 30, 60 or 120 FPS all divide 1/120 exactly, empty the accumulator every frame, and measure this at 0.0002 studs whether it is broken or not. `DebugJitterTests` |
| **The car never stops being drawn** | `drawnGap` stays near zero across a long drive, a fall and respawn, and a server-side car replacement. A Model replicates before its parts do, and a rig taken in that gap draws nothing for ever (T-016) |
| No runaway | Lock-to-lock for 12 s: speed and yaw stay inside their ceilings |
| No physics | Every car part anchored, no BodyMover, VectorForce, constraint or joint |
| The numbers live in Config | Halving `MaxSteeringSpeed` halves the rate of turn |
| The server still holds | A playtest with 0 dropped `CarState` packets, and a jump the server did not decide still rejected |
| **Gravity never touches flat ground** | `g_along` exactly zero every step on the flat, and the same corner at `GravityOnGround` 1 and 0 matching at every sample. The check that protects the approved feel |
| **A hill pulls** | A coast with the engine and the grip off, down a slope and up it: speed at each end against `v² = v0² + 2g·Δh`, with Δh read off the surface |
| **A drift downhill scrubs less** | The same finger for the same time, flat and downhill: the speed each lost |
| **A bank holds you** | A steady finger round a banked circle with the term on and off: how far round the band it got, and its radius at a fixed time |
| **The wall trap is real** | With `UnstickSpeed = 0`, a car nose-in to a barrier at 30, 60, 120 and 150° on a 10° and a 30° bank: still under 1 stud/s after 8 s, every time, and never flagged pinned |
| **Pinned, the car drives itself off** | The same eight starts with the unstick on: past 20 studs/s within 4 s, with no steering and nothing pushing it |
| **It does not fire when it should not** | 12 s leaning on a barrier at the bottom of a 30° bank at speed: touching the wall throughout, pinned on zero steps |
| **A pinned car is still stopped by a wall** | Seven nose angles, the whole escape: the deepest the box ever gets past the barrier's face |
| **The unstick cannot touch the flat road** | The same corner with `UnstickSpeed` at 5 and at 0, bit-identical. The second check that protects the approved feel |

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

### What gravity on the ground measured, 2026-11-04 (`T-065`)

All 45 `DriftTests` pass with `GravityOnGround` at 1, and so do `RoadTests` (34), `RunTests` (15),
`PlaygroundTests` (45), `JitterTests` (11) and `TrajectoryTests` (13).

| | |
|---|---|
| **The flat road is untouched** | On the flat, `g_along` is **0** studs/s² at its largest over 600 steps, and the five-second corner at `GravityOnGround` 1 and 0 matched at **all 602 samples, worst gap 0 studs**, ending at 28.866060 studs/s both times. The 50-piece autopilot drive down the generated road is identical in every number, `speedSum` included, to six decimals over 28 350 steps |
| A hill pulls | 9.3° (the playground ramp at its steepest), 60 studs/s in, engine and grip off, 4 s. Downhill: 46 studs dropped, 82.62 studs/s against the 82.63 energy asks for. Uphill: 31 studs climbed, 37.38 against 37.39. The step-by-step deceleration is 5.656 studs/s², which is `g·sin(9.3°)` exactly |
| The same hill, on the playground itself | Down the real ramp from the lip, 20 studs/s in, 2 s coasting: **29.95 studs/s with it on, 19.89 with it off**, having dropped 7.09 studs. Up it from the plate, 60 in: 55.50 with it on, **60.79 with it off** — the old model climbed a hill at a constant *horizontal* speed and so paid nothing for it at all |
| **A drift downhill scrubs less** | The same finger for 1.5 s, 52° of slip on the flat and 54° down the hill. Flat: 124.2 → 113.0 studs/s, **lost 11.2**. Downhill: 129.7 → 125.2, **lost 4.4**. 6.8 studs/s less scrubbed, and it entered the slide 5.5 studs/s faster for the same second of straight before it. That is the user's sentence as a number |
| A bank holds you | A cone at the circle's own radius and bank (150, 8°), 80 studs/s on one steady finger: held the 60-stud band for 50° of the circle with it on and 45° without, and sat 6.0 studs further down the bank at 2 s. On the playground's real circle at a firmer finger, 2.1 / 5.1 / 5.9 / 7.8 studs further in at 1 / 2 / 3 / 4 s |
| What it costs | 60 s of simulation is 7200 steps: 2.60 µs a step with it off, 2.74 µs with it on. **+0.14 µs a step, about 1 ms over a whole minute of driving** |

Two things the measurements turned up that are nobody's new bug, and both were mistaken for this
one before being chased down:

- **A fresh state believes it is on tarmac** until its first ground ray comes back (`Model.new`
  says so on purpose, so a car spawned on the road grips on step one). A test that starts a car
  facing one way and moving the other therefore gets one step of the brake past square-on, worth
  0.6 studs/s, on a surface whose grip is zero.
- **Downforce lowers the car's position even on the ground.** It is a no-op for the *velocity*,
  because the ground follow overwrites the vertical speed — but it still lowers the position that
  follow is easing, so a climbing car rides a hair below its ride height. Nothing a player can see,
  and it is why the hill check reads the height off the **surface** rather than off the car.

## Open questions

- **The car cannot climb a bank steeper than 24°, and that is a number in this spec rather than a
  bug** (`T-074`). `MaxAcceleration` is 14.3 studs/s² and gravity along a surface leaning `t` is
  `35·sin(t)`; the two cross at **`asin(14.3/35) = 24.1°`**, and the drivetrain's own falloff with
  speed means the real ceiling is lower. Above it a car that has lost its speed on a bank can only
  drive *along* the bottom of it — the grip can still haul it up at speed, but nothing can from a
  crawl. Measured over 50 generated pieces at the showcase corner on seed 8080, pieces reached and
  seconds stopped with the unstick on: 5° 50 / 0.4 s, 10° 50 / 1.4 s, 15° 41 / 54.6 s, 20° **25** /
  0.4 s, 25° **8** / 6.1 s, 30° **8** / 4.1 s. Past 20° the car stops being *stuck* and starts
  being merely unable to get anywhere: at 30° it crawls the bottom of the bank at a mean of 7
  studs/s. **The unstick ends the pin; it does not make a steep bank drivable.**
  `road-elevation.md` asks for 30° of bank and this is why it cannot have it. The answer is
  `MaxAcceleration`, or a bank the car can climb, and both are the user's call rather than a
  worker's.
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
