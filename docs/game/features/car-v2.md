# Feature: Car v2

**Status:** approved 2026-11-10 (T-093), building: T-094 rig, T-095 suspension, T-096 get in and out, T-097 sparks. **Owner task:** see `docs/CLAIMS.md`.

## Goal

Get the game ready for the car being modelled in `features/car-model.md`: a car with parts that move, a driver you can see, wheels that work like suspension, and a body that reacts to the ground the way a real one does. The drift feel (`features/drift-model.md`) must not change: everything here sits on top of the model's line, it does not move it.

## How it plays

- **You start in the driver's seat**, as today: the game opens driving. Your Roblox avatar sits behind the wheel (right-hand drive), visible through the glass, and other players see theirs.
- **Getting out:** stop (or nearly) and press **Get out** (a button on screen, `F` on a keyboard). The driver's door swings open, your avatar steps out beside it, the door closes, and you walk with the normal Roblox controls and camera. The car stays parked where you left it.
- **Getting in:** walk up to your car's driver's door; a **Get in** prompt shows. Press it: the door opens, you sit, the door closes, and the drift camera and the one-finger control are back.
- **Wheels:** each wheel rides up and down on its own as the road changes under it, and the body pitches and rolls on top of them. Over a crest or off a jump the wheels drop to the bottom of their travel and hang there, and they take the load again on landing.
- **Edges:** if the back wheels roll off a ledge while the fronts are still on it, the rear drops, the car's floor lands on the edge, and it grinds across it with sparks and a scrape until the car is clear and falls. The same goes for any corner: the car rests on whichever of its wheels and its floor are touching something.

## Left out

- Opening the hood, hatch, pop-up lights, windows and wipers from play: the rig carries them and code can move them, but no button does yet.
- Other players getting into your car, passengers, stealing cars, more than one car per player.
- Collisions between the character and other cars beyond Roblox's normal ones; running over players.
- Damage, and any change to grip, speed or score from the floor scraping (see "Open questions").
- The real textured car: no stand-in is built (the user, 2026-11-10: "we are going to import a brand new model. just setup architecture for it and move on"). The rig is architecture (`Shared/Cars/Rig`, `Shared/CarParts`, CONTRACTS.md "The car rig"), and the new model goes in through `Rig.assemble` when it is imported. Until then suspension and getting in and out are built and tested on today's cars, with fallback seat, exit and floor points.

## Rules and numbers

**The no-physics rule stands** (DECISIONS.md, 2026-11-03). The car stays anchored and moved by code; the seated avatar is anchored too and placed by the same code each frame. No `Seat`, weld, joint or constraint goes in the car.

**The rig.** A car is a `Body` and its parts, each with its pivot on its real hinge, named as `pivots-gray2.json` names them: the doors, door glass, hood and prop rod, hatch and struts, pop-up pods, four wheels (each a suspension hub that moves up and down, a wheel that spins, a caliper that doesn't spin), steering wheel, needles, pedals, wipers, and the lights. Plus points the code reads: the driver's seat, where you get out, and the floor's contact points. One module turns any part to an angle or opens it over time, and knows the orders that matter (the hood lifts before the prop rod swings).

**Suspension**, per wheel, all faked from the ground rays the model already casts (`Drift/Suspension`, T-095). Every number is in `Config.Drift.Suspension`:

| Number | Value | What it is |
|---|---|---|
| `Travel` | 0.6 studs | how far a wheel moves, up from fully hanging to fully compressed |
| `Rest` | 0.25 studs | how far up from hanging a wheel sits on flat ground: where the wheels were always drawn |
| `Stiffness` / `Damping` | 300 / 22 | how springy the body looks on its wheels: about 2.8 Hz at 0.64 of critical, so a landing settles in about a third of a second |
| `DropTime` | 0.15 s | how fast a wheel falls the whole of its travel with nothing under it |
| `LandingSquash` | 0.15 | share of a change in vertical speed on the ground the body takes as a jolt: a 30 studs/s landing dips it about a quarter of a stud |
| `MaxBodyTilt` | 4 deg | the most the body pitches or rolls on its springs off the car's frame |
| `HangSlack` | 0.75 studs | how far past full hang a wheel's ground must be (two wheels at least) before the floor solve runs: a 2-stud drop under an axle or a side. A kerb never; nor does the road, whose touge pieces twist the four wheels up to 0.66 off one plane at a crawl (measured) |
| `HangSpeed` | 15 studs/s | the floor solve only starts slower than this: faster, a car is over an edge and gone before it could tip, and flies the line it always flew (the playground's ramp jumps are unchanged) |
| `HangHold` | 0.25 studs | once running, the floor solve lets go as soon as the pose the wheels alone would give is within this of what the floor and the tyres' travel allow, which on a road is at once |
| `TipAccel` | 6 rad/s² | how fast the car may start to tip toward resting on its floor: off a ramp lip at speed it turns under a degree, rolled off a ledge slowly it settles in a fraction of a second |
| `MaxTilt` | 30 deg | the most the floor solve tips the car; a car with all its supports to one side of its centre of mass tips this far and slides off |
| `FloorTouch` | 0.05 studs | a floor point this close to its ground is touching (sparks, T-097) |
| `EdgeDrop` / `EdgeSteps` | 0.5 studs / 8 | two floor points this far off each other's plane have an edge between them, found by halving the gap 8 times (to 0.03 studs on a 7-stud segment) |
| `FloorClearance`, `FloorWidth`, `FloorLength` | 0.5 studs, 1, 1.05 | the stand-in floor box, until a drawn car hands the model its own |
| `LiftRange` | 1 stud | each wheel's lift either way of zero over `CarState` |

**Each wheel** touches when its ground is within its hang of where it sits; then its travel is whatever puts it on the ground, pushed up at once and dropped no faster than `DropTime`. With nothing under it, it falls to the bottom of its travel and hangs. **The body** sits on the car's frame plus a sprung offset (heave, pitch, roll) toward the plane the touching wheels are on, jolted by landings and the foot of a ramp, and stopped where a wheel would pass the top of its travel. All of this is drawn: nothing in the model reads it, and on flat ground every wheel is at `Rest` and the offset is zero.

**The body's height and tilt** come from whatever is holding the car up: the wheels that touch, and, when the wheels can't, the floor's contact points. **On flat ground and on every road the car drives today the model is unchanged**: all four wheels are within their travel of the pose it always computed, and the drift tests pass with the same numbers. **When two wheels or more run out of travel** (their ground more than `Rest` + `HangSlack` below them, or nothing under them at all) at under `HangSpeed`, and until handing the car back to its wheels is safe (`HangHold`), the car is a rigid body on point supports: each touching wheel at ride height, the floor's points, and every place an edge crosses a segment between two of them (rows, columns and short diagonals, since a floor is not flat). It rests at the tilt that puts its centre of mass lowest, tipping toward it no faster than `TipAccel`; the floor is hard (never below its ground) and a wheel is not (it can be pushed up into its travel). A wheel hanging off the edge drives and grips nothing. Rolled rear first off a ledge, the rear drops, the floor lands on the edge and grinds along it; once the edge is past the centre of mass the car tips to `MaxTilt` and slides off, and it falls when its floor is clear. **The floor's points** are a v2 rig's `Floor*` points, or else nine points (`FloorFL` … `FloorRR`, `FloorMC` in the middle) read off the drawn body's lower parts, or the block car's box.

**Floor scraping:** while a floor point touches, sparks come off it and a scrape sound plays, louder the faster it slides. It does not slow the car (see "Open questions").

## UI

- **Get out** button, bottom corner on phone, away from the steering finger; `F` on keyboard. Only while slow enough (`ExitSpeed`, 8 studs/s to start).
- **Get in** prompt on the driver's door, Roblox's `ProximityPrompt`, within 8 studs.
- Programmer art until the UI phase.

## Server and client

- **Characters come back.** Today `CharacterAutoLoads` is off and the player is the car. The server spawns the character, and decides who is in which car: getting in and out is a request (`CarEnter` / `CarExit`), checked against distance and speed, and the answer moves the character.
- **In the car:** the driving client simulates and draws the car as today, and places its own seated avatar. Other clients place each driver in the car they draw (`RemoteCars`), so the driver never lags the car.
- **Out of the car:** the character walks with Roblox's own movement. The parked car is still anchored and stays where the server last agreed it was; the client stops sending `CarState` for it.
- **Suspension and scraping are drawn**, on every client, from the pose; only what the model needs (the floor holding the car up) is in the simulation.

## Contracts

All in `CONTRACTS.md`, in the first step's commit:

- The car rig: group names, pivots, the seat and exit points, the floor points (replaces "a `Body` and four `Wheel*`").
- Remotes `CarEnter`, `CarExit`; an attribute on the car for its driver; `CarState` gains each wheel's suspension height so others see it.

## Analytics

`CarEnter` and `CarExit` events, with where and how fast, when analytics are built (EVENT-CATALOG.md).

## Platform risks

None new. The avatar is the player's own. The car's own risk is unchanged (`assets/car-ae86/MANIFEST.md`).

## Art and sound

- No stand-in car: the new model is imported later, into the rig.
- Sparks: programmer art. Scrape sound: a Creator Store candidate for the user to pick (AUDIO-PIPELINE.md).
- Door open and close sounds: Creator Store candidates, same way.
- The seated avatar's pose: Roblox's sit pose, with hands toward the wheel if it's cheap; a proper driving pose later.

## Testing

- **The feel doesn't move:** DriftTests, TrajectoryTests and JitterTests pass with the same numbers on flat ground and every playground road.
- **Suspension:** each wheel's height logged over a kerb, a crest and a jump: hangs at the bottom in the air, back to `Rest` within half a second on flat ground.
- **Ledge:** a test ledge in a lane; drive the rear off slowly: the body's tilt, the floor point touching, sparks on, and nothing of the car below the ledge's top.
- **Get in and out:** 10 times each, with a second player watching: the avatar always in the seat, the car never moving while parked, no errors.
- **Debug:** `DebugState()` reports each wheel's travel, which floor points touch, and who is in the car.

## Open questions

- **Should scraping slow the car?** Proposed: no, it's looks only for now, so the feel stays.
- **The wheel size:** the model's wheels are 2.6 across, the game's are 2.3 (`features/car-model.md`). Wheels bigger than `WheelDiameter` spin about 12% too fast until it changes; the user's call when the real car goes in.
- **Spawn on foot instead?** Proposed: spawn in the car, as today.
