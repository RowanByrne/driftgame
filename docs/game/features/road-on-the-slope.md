# Feature: Road on the slope

**Status:** specced, plan waiting for the user (2026-11-15). Builds on the mesh ground picked in `ground-trial.md`. **Owner task:** none yet.

## Goal

The road should sit on the mountain the way a real touge does: cut into a steep slope as a bench, laid almost flat on gentle ground, never trenched deep between two walls or raised on a causeway between two drops. The shape beside the road comes from how steep the mountain is across it, so the ground reads as one believable mountainside.

The user, 2026-11-15 (C-28c642): "right now i'm noticing that there is alot of 'trenching' (where the road cuts deep into the mountain, creating high vertical walls on both sides of the road) and 'bridging' (where the road gets heightened up on a sort of causeway, with steep drops on both sides). This isn't the vibe we are looking for." Their sketch: `assets/reference/road-cross-sections-sketch.png`.

## Why it happens today

The road is not laid on the mountain and then moulded. It is made in this order (`ground-trial.md` "As built (step 1)"):

1. **The mountain**, h(x, z): a 7-degree plane down the fall line, plus three octaves of ridges and gullies (about +-75 studs).
2. **The road's path** is fitted turn by turn, sampling h to choose where it goes. **Its height follows its own rule:** a steady descent of about 1 in 25, kept within 40 studs of the plane. It does not follow the ridges and gullies of h.
3. **The ground is pressed to the road:** under the road and runoff it sits just below them; past the runoff's edge it blends back to h over 20 to 60 studs at about 45 degrees, whatever the mountain is like there.

So where a ridge rises over the road's line the ground is cut both sides (a trench, measured up to 140 studs deep), and where a gully drops below it the ground is filled both sides (a causeway, up to 104 studs). The runoff's width is chosen at random (12 to 40 studs), not from the slope.

## How it plays

Driving a ground run (console `ground mesh`, then `start-run`), the road follows the mountain's surface closely, and what is beside it depends on the slope across the road at that point:

| Slope across the road | Uphill side | Downhill side | Runoff |
|---|---|---|---|
| **Steep** | A tall wall cut into the hill | A steep drop | Thin (about the minimum) |
| **Middle** | A lip, its height from the slope | A drop, its depth from the slope | Between |
| **Shallow / flat** | A slight lip | A slight drop | Wide |

Between those, the sizes slide smoothly with the slope. Deep cuts on both sides and fills on both sides become rare: only where the road truly cannot follow the ground (a sharp ridge or gully across its path).

## Left out

- The touge kit (walls' rock, guardrails, forest, props), seasons, backdrop: after this.
- Roblox Terrain (option 2), and today's non-ground road: unchanged.
- Making a ground run the game's default: later.
- The car's physics: it still drives on the spline maths; only where its drivable edge is moves with the runoff.

## Rules and numbers

Starting values, in `Config.Spline.Ground`, tuned in the lane:

- **The road hugs h:** the road's target height is h along its centre line, smoothed over a few hundred studs so it stays drivable (within today's grade and vertical-curve limits). Climbs are allowed where the mountain rises, so a run no longer only descends. Measured target: the centre line within about 6 studs of h over most of a run, and cut or fill at the centre line over 20 studs rare (under 5% of stations).
- **Side slope:** at each road station, the mountain's slope across the road (from h either side, over about 40 to 60 studs), as an angle. Steep from about 30 degrees, shallow under about 8.
- **Runoff from the slope:** wide (about 40 studs) on shallow ground, thin (about 12) on steep, eased between.
- **Uphill and downhill:** the wall and drop are what it takes to cut a flat bench of that width into that slope, so their heights follow from the slope; on shallow ground a small lip and drop (a few studs) either side.

## Server and client

Pure maths from the seed, as today: the server lays the road and checks the car, the client draws the same ground from the same seed. No new remote.

## Contracts

The road's start message is unchanged unless a new ground number has to travel with it (then in `CONTRACTS.md` with the code). The runoff width at a station comes from the slope instead of random knots in a ground run.

## Platform risks

None.

## Art and sound

None new.

## Testing

`GroundTests` extended, and measured on three seeds over 5 000 studs:

- Cut and fill at the centre line: the spread (median, 95th percentile, worst), before and after. Count of trench stations (cut both sides over a threshold) and causeway stations (fill both sides), before and after.
- Side slope against runoff width and wall/drop height: they follow the table above.
- Road still drivable: grades and vertical curves within limits; no ground above the road; no seams.
- Frame and build cost unchanged.
- Up to 3 screenshots of a steep, a middle and a shallow stretch for "does it look right".

## Open questions

- How smooth the road's height should be against how closely it follows h: tuned in the lane by eye.
