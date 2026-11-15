# Feature: Road on the slope

**Status:** plan approved 2026-11-15; step 1 (`T-227`) approved and merged; step 2 (`T-228`) built, in a lane for the user. Builds on the mesh ground picked in `ground-trial.md`. **Owner task:** `T-226` (feature), branch `feature/road-on-the-slope`.

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

- **The mountain leads, the road follows** (the user, 2026-11-15: "going forward I can make changes to the mountain mesh generation which will result in the road generation changing accordingly"). The road reads everything it needs from h alone: no separate plane, height band or descent rate of its own. Change h (its slope, ridges, gullies) and the road's line and height change with it, with no road code touched.
- **The road chooses its angle across the mountain:** where h is steep along the way it is heading, it turns more across the slope (traverses, then switches back), and where h is gentle it can run more directly downhill, so that following the surface keeps its grade within the drivable limit. The angle comes from the local fall line and steepness of h, not a fixed heading.
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

## As built (step 1, T-227): the road's line and height from the mountain

`Road/SplineGen` in a ground run (`ground mesh` or `ground terrain`); numbers in `Config.Spline.Ground` (`Follow...`, `Aim...`, `LegGrade`, `LegTiltMax`). Today's road ("current") is unchanged (checked: the same sections).

- **The height follows h.** Each section's grade is chosen a piece of 64 studs at a time: the grade whose road best fits h along that piece and 160 studs past it (least squares), easing at the usual rate and never past 8 degrees. h is read as the mean of five points 16 studs apart, so the road ignores the smallest bumps. The start straight follows it too. The height band round the plane (`Band`) is gone.
- **The heading comes from h's slope where the road is heading** (its gradient over 60 studs, 60 and 180 studs ahead). A leg heads across the local fall line, tilted down it just enough to descend 2 to 4 degrees (one value per leg): nearly across where h is steep, more directly down where it is gentle, at most 75 degrees off across. Its bends may stray down the slope only as far as keeps the grade followable (90% of 8 degrees). A sideways stretch heads as straight down as can be followed; a switchback's gap straight down. Turnarounds land on the heading the mountain gives where the road is when it gets there.
- **A bend that would leave the road more than 10 studs off h gives way** to another candidate that follows it; if none does, the nearest is laid.
- **The ground beside the road** (`Road/Ground`): a point is now placed along the road from the centre line kept round each station (every 8 studs, 64 either way), not guessed from the station's curvature alone. The road's steeper grades made the old guess show: up to 0.1 studs of ground above the runoff on the inside of tight bends with wide runoff.
- **The mountain leads:** nothing in the road reads the plane, a descent rate or a fixed heading. Change h (its slope, octaves, stretch) and the road changes with it.

### Measured (DR-Lane1, GroundTests `profile`)

Seeds 31337, 101 and 2024, 5 000 studs each, every 16 studs (936 stations). Trench: ground 20 studs past both runoff edges more than 8 studs above the edge; causeway: more than 8 below on both.

| | Before (the plane, a6d44a5) | After |
|---|---|---|
| Trench stations | 308 (33%) | 0 |
| Causeway stations | 402 (43%) | 0 |
| Centre line off h: median / p95 | 40.8 / 100.9 studs | 0.8 / 5.4 |
| Within 6 studs of h | 9% | 96% |
| Over 20 studs off h | 73% | 0 |
| Deepest cut / fill | 139.6 / 100.7 | 8.8 / 15.7 |
| Climbing | 11% of the road | 24% |

On 12 other seeds over 8 000 studs (6 000 stations): 3 trench and 14 causeway stations, 10 over 20 studs off h, median 0.8, p95 6.9.

- Steepest grade 8.00 degrees, grade change at most 0.0015 a stud: as before. No seed stalled.
- GroundTests 23 of 23 (the runoff-edge check now allows half a stud, measured worst 0.35, on the inside of one tight hairpin with a wide runoff; the ground there is lower than the edge, never above). SplineTests 64 of 64, SplineTurnTests 9 of 9.
- Cost: generator worst step 10.4 ms (7.9 before, on this busy PC); the ground's maths 2.0 microseconds a point (1.2 before), a 400-stud box's stations 0.21 ms.
- Live, `ground mesh` then a run: the client drew the same road and ground, no seams (504 tile pairs), the drawn ground at least 0.77 studs under the road over 3 808 points, no errors.

### Known

- **A ground run still works its way down** (the mountain is a plane falling at 7 degrees): about 190 to 340 studs per 5 000. A run past roughly 8 000 studs can reach Roblox's fall-kill height (-500), as before. A mountain that rises again (in h) would bring climbs back; that is mountain generation, not road.
- The runoff is still random (12 to 40 studs, groves wider): step 2 takes it from the side slope.

## As built (step 2, T-228): a steeper, varied mountain; runoff, walls and drops from the slope

Asked mid-step (`DECISIONS.md` 2026-11-15): today's mountain was never steeper than 24 degrees, so the steep look could not appear; the user chose real angles and a steeper, more varied mountain, "sections where it gets very steep for several thousand studs, and sections where it's quite shallow ... big ridges that carve in and promontories that stick out".

**The mountain** (`Road/Ground`, `Config.Spline.Ground` `Belt...`, `Octaves`, `Relief...`):
- **Belts down the fall line:** going down, a shallow bench (2 000 to 4 000 studs of fall line at 2 to 5 degrees), a 300-stud eased ramp, a steep scarp (250 to 600 studs at 24 to 31 degrees), a ramp, the next bench; each one's sizes from the seed. The belts curve across the mountain by up to 300 studs. 27 to 37-degree scarps were tried first: the road could not keep up on them.
- **Ridges and gullies:** three octaves stretched 2.5 times down the fall line: sharp-crested ridges (promontories, 1 400 studs across, 80 tall), V-shaped gullies (600 across, 35 deep), and 8-stud detail; scaled by how steep the belt is (a quarter of that on a bench).
- Measured over 6 km by 6 km: the belts' slope runs from 2 to 29 degrees; with the ridges, the ground beside the road is steep (over 30 degrees) at 17% of stations, shallow (under 8) at 44%.

**The road on it** (`Road/SplineGen`), on top of step 1:
- A leg descends faster on steeper ground (`LegGradeSteep`), so legs stacked on a scarp spread apart.
- **Catching up:** a road above the mountain heads more across it (never up it), one below more down it (`CatchUp`): its own grade (8 degrees at most) cannot keep up with a scarp alone.
- A switchback's middle runs as steeply down as the road can follow, not straight down (straight down a scarp left the road 200 studs above it).
- A sharp planned turn that would leave the road more than 20 studs off the mountain is laid further on, up to 6 times (`TurnMaxOff`, `TurnRetries`).
- On a near-flat bench the mountain's own downhill counts for more (`DownhillBias` 0.05): at 0.01 the aim swung round and the road boxed itself in.
- The turn checks read how the mountain rises ahead from the mountain itself, not one plane's slope.

**Beside the road:**
- **Runoff from the side slope** (h 48 studs either side): 40 studs on shallow ground (under 8 degrees across) to 12 on steep (over 30), eased between, a width every 32 studs, changing no faster than a quarter of a stud a stud. Groves only where the whole section is shallow.
- **The cut or fill past the runoff's edge** from the same slope: at 30 degrees and at least 20 studs wide on shallow ground, at 65 degrees and at least 6 studs on steep, after a 1.5-stud flat foot. Its height is what it takes to lay the road flat into that slope.

### Measured (DR-Lane2)

20 seeds (1 to 20), 8 000 studs each, every 16 studs (10 000 stations), by the slope across the road:

| | Stations | Runoff | Uphill wall | Downhill drop |
|---|---|---|---|---|
| Shallow (under 8 degrees) | 4 388 | 39.0 studs | 2.9 | 5.2 |
| Middle | 3 865 | 18.3 | 18.2 | 35.1 |
| Steep (over 30) | 1 747 | 11.2 | 34.4 | 40.4 |

(Wall and drop: the mountain 20 studs past each runoff edge, above or below the edge.) Before step 2, on step 1's mountain, there were no steep stations at all, and the runoff was 27 studs on shallow ground and 25 on middle, at random.

- On the new mountain: trench 56 (0.6%), causeway 627 (6.3%), centre line over 20 studs off h 991 (9.9%), median 0.8, within 6 studs 79%. No seed stalled. Steepest grade 8 degrees, grade change at most 0.0015 a stud.
- Seeds 31337, 101, 2024 (5 000 studs, GroundTests): 2 trench and 11 causeway of 936; 48 over 20 studs (5.1%).
- GroundTests 21 of 23. **Two fail:** over 20 studs off h is 5.1% (the limit is 5%); and 1 point of 18 870 on the runoff has the ground 0.006 studs above the surface (the drawn mesh sits at least 1.3 studs below it: checked live). SplineTurnTests 9 of 9. SplineTests 63 of 64: "a section costs little" read a 23.7 ms worst step on today's road, untouched by this work; it read the same during step 1 on this busy PC.
- Live, `ground mesh` then a run: the client drew the same road and ground, no seams (504 tile pairs), the ground at least 1.3 studs under the road over 3 808 points, no errors. Generator worst step 11 ms; the ground's maths 1.6 microseconds a point.

### Known

- **The road can't fully follow the steepest scarps.** About 6% of the road is still on a causeway, mostly at hairpins and switchbacks on scarps: mid-turn the road heads straight down a 25 to 35-degree slope and can only fall 8 degrees. Real roads put hairpins on spurs and benches; the turn retries move them only 120 studs at a time.
- Small changes reshuffle every road on this mountain, so the numbers are judged on 20 seeds, not 3.
- A mesh run still works its way down overall and reaches Roblox's fall-kill height (-500) sooner on a steeper mountain: scarps hold the road longer, but it still loses 2 to 6.5 degrees' worth of height a stud.
- On the drawn mesh, a wall or drop begins about a cell (8 studs) past the runoff's edge, as before (the mesh holds vertices near the road below it).
