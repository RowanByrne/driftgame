# Feature: Car edges follow the drawn ground

**Status:** in progress. **Owner task:** T-258 (`feature/car-edges-follow-the-drawn-ground`), steps T-259 on.

## Goal

What the car meets beside the road is the ground the player sees. Until now each side of the road was secretly rock or cliff, left over from the old mountain: on a rock side an invisible wall stood at the grass's outer edge, and on a cliff side the car fell through the drawn ground. Neither is drawn any more.

## How it plays

- Past the grass, the car drives on the drawn ground (the mountain with the road cut into it), with the grass's grip.
- Ground steeper than about 45 degrees (where the drawn ground turns to rock) is a **wall** to a car below its top: a cut beside the road, or a steep rise out on the mountain. To a car above it, it is a **drop**: the car goes over and lands on the ground below.
- Gentle slopes and valleys beside the road can be driven.
- More than 300 studs from the road, the car is wrecked and put back on the road, at the nearest point reached (step 2).
- K-rails, trees and the road itself are unchanged.

## Left out

- The closing barrier behind a run still reaches only across the road and its grass; out on the ground a car could go round it. Step 2's put-back is the guard.

## Rules and numbers

`Config.Drift.OffRoad`:

| Key | Value | What |
|---|---|---|
| `Lattice` | 2 studs | The drawn ground is worked out on this grid (`Road/Ground.at`), the first time a point near it is asked for, and kept; bilinear between |
| `ContextBox` | 48 studs | How much road is gathered at once to work it out |
| `Keep` | 20 000 | Points kept before all are dropped |
| `WallAngle` | 45 degrees | Steeper is a wall or a drop (`Config.Spline.Ground.RockAngle`, and the model's own climb limit) |
| `WallStep` | 1.5 studs | A steep point is a wall once it stands this far above the car's wheels |
| `PutBack` | 300 studs | Further than this past the tarmac's edge of the nearest road (any leg), the car asks the server to put it back (`CarRespawn`), as a fall does; the server's `SafeStart` finds the nearest road from that far out, never behind the closing barrier |
| `PutBackEvery` | 0.25 s | How often the client checks |

What is kept is dropped when new road is laid (or old road trimmed) within reach of it.

A road with no mountain (the tests' bare yardstick road) keeps its rock faces and cliffs.

## Server and client

All on the driving client (`Drift/SplineWorld`, `Drift/OffRoadGround`): the server never simulates the car. The put-back is the server's `CarRespawn`, as a fall is.

## Testing

- `SplineWorld.stats`: `offRoad` (probes on the drawn ground), `groundStops` (steep ground stops); `SplineWorld.offRoad.stats`: lattice points worked out, gatherings, drops.
- In a lane: the car's ground against the drawn mesh off the road; driving at a steep cut (stops), up a gentle slope (climbs), over a drop (lands below); frame cost on and off the road.

## Open questions

None.
