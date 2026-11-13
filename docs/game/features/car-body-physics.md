# Feature: The car's body rides the ground

**Status:** specced, waiting for the user's approval (from `T-192`). **Owner task:** none yet.

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

`Drift/Model` `State` gains the body's vertical speeds; `T-184`'s `stepTilt`/`surfaceUp` and
`T-192`'s `hopping`/`rideVy`/`hopRest`/`kickWheelY` go. Recorded in `CONTRACTS.md` in the same commit.

## Open questions

- None blocking.
