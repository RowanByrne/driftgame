# Feature: The car's body rides the ground

**Status:** plan approved by the user 2026-11-13 (`T-196`). Step 1, the real height, pitch and roll, is built (`T-197`) and waits for the user's drive; the test pad and feel tuning are step 2. **Owner task:** `T-196`.

## Goal

The user, 2026-11-13, on the kerb-hop build (`T-192`): *"are we faking this by trying to detect when a
car is going fast enough to get air, then giving the whole car an upwards impulse? ... if 1 tyre goes
off the road, but the car is moving fast, when that 1 tire rejoins, the whole car suddenly takes off
in the air. that's not the intended behavior. the way i want this to work is for it to have nothing
special going on with the curb itself. if there's a random small ledge in the road, I want driving off
that ledge to cause the car to fly as it should. if the 2 back wheels go up a ramp but the front two
stay planted in a drift, I want the car to get pitched up on its nose as the ass end gets lifted by
the ramp and the front stays down."*

Yes, `T-192` faked it: it detected the bevel's rise and pushed the whole car up. Before that, `T-184`
drew the car's tilt on a step without the physics feeling it. Both are stand-ins. This feature
replaces them with the real thing.

## How it plays

- Any shape in the ground does what it should, with nothing special for kerbs: a ledge drops you off
  it, a ramp throws you, a kerb under one wheel kicks that corner up and tips the car.
- One rear wheel up a ramp lifts that corner. Both rears up it pitch the car onto its nose while the
  fronts stay planted.
- On flat, smooth tarmac the car drives and drifts exactly as it does now: the approved feel
  (DECISIONS.md, 2026-11-03) doesn't move.

## Left out

- New tyre or grip models (including per-wheel grip from load), damage, rollovers beyond what the springs give (the car is kept upright
  past a set roll and pitch, and always lands on its wheels).
- Any change to the drift tuning, the controls or the camera's approved behaviour.

## Rules and numbers

### The body

Today the drift model is a flat (planar) model: position, heading, velocity and yaw rate across the
ground, with the height and tilt eased onto the ground under the car. This feature keeps the planar
model as it is and adds **three real vertical motions on top of it**: height, pitch and roll, each with
its own speed.

- **Four springs.** Each wheel probes the ground under it (the probes already exist). Its spring
  pushes on the body by how far it's compressed, damped by how fast; a wheel whose ground falls away
  extends to full droop, then leaves the ground.
- **Gravity** pulls the body down; the springs' forces add up to lift, pitch and roll it.
- **Airborne:** with no wheel touching, the body flies under gravity and keeps its pitch and roll
  speeds; it lands on whichever wheels touch first and the springs take it.
- **Nothing special anywhere:** the gravel bevel, a crest, a ledge or a ramp all act through the
  same four springs. `T-192`'s kick and `T-184`'s drawn-only tilt go.
- **Safety:** pitch and roll are held under set limits so the car can't flip, and a landing never
  puts it in a wall.

### Not Roblox physics, and the tyres stay as they are

The user, 2026-11-13: "is this using roblox physics? or still faking it? i don't want to necessarily rewrite how we run car physics and tyre simulation right now". So: it is **our own model, not Roblox physics**, as the drive is today, and the **tyre and grip simulation is not touched**. The vertical motion is a layer on top: the planar drift model runs exactly as now, and the body's height, pitch and roll come from the springs. A wheel in the air still grips as the model already decides (the whole car loses grip only when it's fully airborne, as now); per-wheel grip from load is a possible later feature.

### Starting numbers

Spring stiffness, damping, ride height and travel come from today's suspension values
(`Config.Drift.Suspension`), so a car at rest sits as it does now. Body inertia in pitch and roll is
set from the car's size. All in `Config.Drift`; tuned by the user's feel in a lane.

| `Config.Drift.Body` | Value | What it is |
|---|---|---|
| `PitchInertia` / `RollInertia` | 1 / 1 | times the inertia of a box the car's `BodyLength` / `BodyWidth` across. More is slower to tip and slower to come back |
| `MaxPitch` / `MaxRoll` | 25° / 20° | the most the body tips off the ground's own slope. Hard limits: the car can't go over |
| `DamperMaxSpeed` | 15 studs/s | the dampers resist a strut moving no faster than this. A kerb is a step; an unlimited damper turns it into a launch |
| `DamperBump` | 0.5 | share of the damping that resists a wheel being pushed up (dropping back gets all of it). Less passes less of a kerb to the body |
| `AirDamping` | 8 /s | how fast pitching and rolling die away in the air. The spec said "keeps its speeds" (0); at 0 every crest and jump lands on its nose, because the rear is still being pushed up as the front leaves. To tune with the user |

`Config.Drift.AirborneMargin` (2 studs) keeps its old job for the drift model only: how far above ride height the body may be before the car loses grip and drive.

### How it is built (`T-197`)

- **`Suspension.ride`** (`Drift/Suspension`), called from `Drift/Model.step` after the car has moved across the ground. Each step: the body moves at the speeds it had; each wheel's strut is read against its ground ray (pushed up to `Travel - Rest` above where it sits on the flat, hanging to `Rest` below, in the air past that); spring and damper push on the body's height, pitch and roll; gravity and downforce pull; wheels past their bump stop have their corner lifted off it and stopped, without a bounce; the tilt is held inside its limits.
- **A spring carries a quarter of the car at rest,** and the code works in the difference from that, so on flat ground every force is exactly zero and the body does not move at all.
- **Downforce presses on the springs too,** and they are wound up to carry it, so ride height doesn't change with speed, but a crest has to beat gravity and downforce before a wheel lifts.
- **Two frames.** `State.up` is the body's (drawn and sent). `State.groundUp` is the ground's smoothed normal, what `State.up` used to be: grip, drive and gravity act in it and the camera reads its grade. A body bouncing on its springs moves neither.
- **The drift model's velocity** keeps its vertical part as the slope's climb while the car is within `AirborneMargin` of ride height, as before. Past that the car is airborne to it and the vertical part is the body's real speed (`State.heave`).
- **The slow ledge** (rolled off rear first, the floor grinding on the edge, `T-095`) is unchanged: the floor solve still takes over under `HangSpeed`, and hands the body back to its springs.
- **Gone:** the drawn body springs, the landing jolt (`LandingSquash`, `MaxBodyTilt`), the plane through the wheels (`StepTiltDead`, `Hit.stepped`), and the ease of height on to the ground.

### Measured (`BodyTests`, DR-Lane2, 2026-11-13, the balanced car)

- **Flat ground:** 20 s of straights, slides and a spin in three cars end at the same position, heading and velocity as the model before `T-196`, to the last bit, and the body never moves. A smooth hill is the same line too.
- **At rest:** exactly ride height, every wheel at `Rest`. Dropped from half a stud: lowest 2.27 (bump stops at 2.05), settled in 0.62 s.
- **A 3-stud ledge at 60 studs/s:** all four wheels in the air for 0.2 s, falling at up to 11.8 studs/s, nose down 9° at most, settled 0.43 s after landing. A 1-stud ledge: falls at 4.7 studs/s, nose down 6°, never loses grip, and is the same line as flat ground to the bit.
- **0.8 studs under the left wheels:** the car leans 8.2° to the right (the ground is 8.1°).
- **Both rear wheels up a 1.2-stud ramp, the front on the flat:** nose down 7.2° (the ground is 7.1°), the front wheels never leave the ground. One rear wheel first lifts that corner.
- **Coming back over the road's bevel** (1 stud up, 3 across) at 60 to 179 studs/s, closing at 6 to 60: never airborne to the drift model, the car's middle at most 0.52 studs over ride height, same line as flat ground.
- **Thrown by a 25° ramp under one side at 120 studs/s:** pitch and roll stay inside their limits, and it lands and stands level.
- **Cost:** 5.6 µs a step on flat ground, 7.4 on ground that works all four springs (5.9 before).

### The test pad (`T-198`)

Three lanes in the playground's yard, built by code (`Layout.BodyPad`, 13 parts), each driven
in +Z. Get there with `tp BodyPad`, `tp BodyPadLedge` or `tp BodyPadKerbs` in the admin console.

| Lane | What's on it |
|---|---|
| Ledge | A long easy climb to a deck 2.5 studs up that just ends; further on, the same 1 stud up |
| Ramp | A 0.8-stud ramp and deck under one side's wheels only; then a short steep kicker (2.5 up over 12) |
| Kerbs | A 0.3 kerb under one side, a 0.3 kerb right across, a 0.6 kerb under the other side, and a 1-stud kerb with sloped faces (1 up over 3) |

**Slopes are tilted boxes, never `WedgePart`s:** `Drift/World.penetration` knows a part by its
box, so the thin end of a wedge was a wall and stopped the car dead.

**Measured live (DR-Lane2, the player's own car, about 90 studs/s, 2026-11-13):**

- **The 2.5 ledge:** falls at up to 11 studs/s, nose down 6.5° at most, lowest 2.10 (bump stops 2.05).
- **One side on the 0.8 ramp:** rolls 11.4°, nose up 3.7°; back level within a second of its end.
- **The kicker:** leaves at 18.7 studs/s upward, nose up 13°, about 5.5 studs of air for 0.6 s.
- **Kerbs:** the 0.3 kerbs move the body under a tenth of a stud (1° of pitch or roll); the 0.6 kerb rolls it 3°.
- **The 1-stud sloped kerb, one side, square on at 99 studs/s:** that side is thrown, the car's middle rises 1.45 studs and it rolls to the 20° limit, three wheels off for about half a second. It is a real 18° ramp; the road's own gravel edge reads as level ground to the car and does much less (above).
- **No wall hits** on any lane; worst frame 10.9 ms, mean 8.3 ms (120 a second).

### What changed for other things

- **A sharp crest or a bank now throws the car** where the old model held it to the ground: the playground's bowl crossed at 120 studs/s flies for most of a second (`CollisionTests` used to demand no air there).
- **`wheelsDown`** is true only for a wheel that really reaches its ground, so a lifted corner lays no smoke or marks. The drive and the grip still ask only for ground under the wheel.

## Testing

- **Unit:** the car at rest settles at today's ride height; flat-ground drift numbers match today's
  model; a ledge drop flies and lands on four wheels; one wheel up a ramp tips the car toward the
  other side; both rears up a ramp pitch it nose-down while the fronts stay on the ground; one wheel
  rejoining at speed never launches the car.
- **In the lane:** a test pad with a ledge, a ramp and a kerb, plus the endless road's gravel bevel,
  measured (height, pitch and roll through each), and frame time.
- **Then the user drives it** before it merges.

## Server and client

Client only, as the drift model is. Other players see the body's pose through `CarState` as now.

## Contracts

`Drift/Model` `State` gains `groundUp`, `heave`, `height` and `strut`, and `tiltRate` becomes the
body's own; `T-184`'s `Hit.stepped`, `stepTilt` and `surfaceUp` go (`T-192`'s kick was never
merged). Recorded in `CONTRACTS.md`.

## Open questions

- **Feel, for step 2 with the user:** how hard a kerb kicks (`DamperBump`, `DamperMaxSpeed`), how
  much the car keeps turning in the air (`AirDamping`), and whether a small hop should cost grip
  (`AirborneMargin`).
- **The body can clip a ledge's edge at speed:** between the front wheels dropping off and the
  rear following, nothing holds the floor off the edge above `HangSpeed`. Not seen as a problem
  in the tests; to look at on the test pad.
