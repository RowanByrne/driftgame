# Feature: Mountain range

**Status:** specced (plan for the user; revised 2026-11-15: no biomes yet). Builds on `road-on-the-slope.md` (T-226) and the mesh ground picked in `ground-trial.md`. Replaces nothing of `road-biomes.md`, which was rolled back. That spec chose biome stretches at random from the seed; this one reads them off where you are on the mountain.

## Goal

The run crosses a real-shaped mountain range: it climbs to passes, runs along ridges, drops through valleys and climbs again, so runs go up as well as down and can last hours without reaching the bottom of the world. Later, where you are on the range (high, steep, on a ridge, in a valley) will set the biome you drive through, aiming at the six environment mood images in `ART-DIRECTION.md`; **biomes are not in this feature** (the user, 2026-11-15: "don't do the actual biomes yet - we can determine how they get chosen during live generation later").

The user, 2026-11-15 (C-dd9f36): "we basically create a realistic shaped mountain range as the mesh terrain surface, and the road gets put on it. we go up and down, we go along ridges, through passes, down through valleys, etc. i want us to detect where we are and use that to determine the biome we will be in, like the concept art you stored earlier. when up high, that can be made a snowy peaks section, etc". Explainer pictures: `art/generated/mountain-passes/pass-aerial-01.png`, `pass-profile-01.png` (outside git).

## How it plays

### Seed 7 Studio drive (T-323)

The review build's **Start Endless Run** button starts the approved seed 7 route. The first climb has a close pair of switchbacks at 7,512 and 7,924 studs. After the first ridge at 11,873, the road descends to the valley, then climbs through a wider pair at 29,632 and 30,555. It crosses the second ridge at 36,499.

For a shorter drive, use the Studio console (F2) and enter `tp me road 7000` for the first pair or `tp me road 28800` for the second. The ordinary range planner continues from the recorded steering's final sample at 36,555 studs.

The steering samples and the mountain's branching channels come from the approved preview. The game fits the road grade, bank, gravel and guardrails as it streams each section. The server and clients build the same terrain from the seed. Explicit alternate seeds and live runs use the usual procedural range.

### The endless range

1. A run starts low on a range. The road climbs a face in switchbacks that hug it (DECISIONS.md, 2026-11-15, hairpins hug the steep face).
2. It reaches a pass, a saddle between two peaks. It crests, and the next valley opens below.
3. It descends the far side, sometimes runs along a ridge with drops on both sides or along a valley floor beside a river line, then climbs to the next pass.
4. The scenery looks as it does today; biomes come later.
5. Height stays within a band. The road never reaches Roblox's fall-kill height however long the run.

## Left out

- **Biomes:** which biome a spot gets, and how each looks. Decided later, during live generation. The sketch below is kept only as a starting idea.
- Props: trees, rocks, rails beyond today's, shrines, lamps, waterfalls and rivers as objects.
- Weather systems (rain, snow falling).
- Changes to the drift model, the car, the score or the tarmac's width.
- Driving off the road into the range.

## Rules and numbers

Starting values, tuned in a lane:

- **The range, h(x, z):** still one pure function of seed and position, the same on every device, and still the thing the road follows ("The mountain leads, the road follows", `road-on-the-slope.md`).
  - Ridges lie roughly across the run's way, about 8 000 to 18 000 studs apart (doubled by T-245, below), each with saddles 500 to 1 000 studs lower than its peaks.
  - Valleys lie between the ridges, with spurs and side ridges off the main ones.
  - Peaks rise 1 200 to 2 400 studs above the valley floors.
  - The whole range sits in a height band whose bottom is well above -500, the fall-kill height.
- **The road's route:**
  - Heads for the next pass: the lowest good saddle in the ridge ahead.
  - Climbs to it as switchbacks on the face, crosses it, and descends into the valley.
  - May follow a ridge or valley floor when that is the way on.
  - Grade, curve and hairpin rules as today: at most 8 degrees, and hairpins hug the face.
  - Climbs are as common as descents over a long run.
- **Where you are:** a pure function of position that reads h. It works out the height in the band; the slope; whether the spot is a ridge, valley, face or pass (from the curvature of h); and the distance to the nearest crest. Every device gets the same answer.
- **Later, not built here: biomes from where you are**, a first idea, from the mood images:

  | Where | Biome | From |
  |---|---|---|
  | High, above the snow line | Snowy pass: snow ground, alpenglow, cloud sea below | `snow-pass-sunset` |
  | Open ridge or high shallow ground | Pampas ridge: pale grass, wind, open sky | `moonlit-pampas-ridge` |
  | Steep faces, mid height | Maple cliffs: pale rock, red-orange canopy colour | `autumn-maple-cliffs` |
  | Low, gentle slopes | Sakura: soft pink and green, warm dusk light | `sakura-shrine-dusk` |
  | Valley bottoms | Cedar forest: dark greens, damp, low light | `rainy-forest-night`, `waterfall-gorge-rain` |

  

## UI

None.

## Server and client

- The server lays the road, as now.
- The range is pure maths, so the server and every client compute the same ones from the run's seed.
- Clients draw the ground as now.
- Nothing is sent but the seed, as now.

## Contracts

- `Road/Ground`'s field gains the range.
- Rows added to `CONTRACTS.md` with the code.

## Analytics

None yet.

## Monetization

None.

## Platform risks

None.

## Art and sound

None: the ground looks as it does today.

## Testing

- **GroundTests extended:**
  - h stays inside its band on 20 seeds.
  - A run of 50 000 studs never goes below the floor.
  - The share of road climbing is about the same as descending.
  - Passes are found and crossed.
  - Trench and causeway shares stay as low as `road-on-the-slope.md` measured.
- **Live in a lane:** drive over a pass, and check the ground is drawn the same, there are no seams, and the cost per frame stays as today.

## Open questions

- Biomes, later: how they are chosen, during live generation (the user), and whether each brings its own time of day and weather.
- How long between passes: about one every few minutes of driving, or longer?

## As built: no lobe inside hairpins (T-237)

Folded into this feature by the conductor (the user: "the remnants of the 'lobe' problem are still here. I want to fix that"). `Road/Ground` `at`:

- **Why it showed:** each station shaped only the points within 16 studs of square beside it. Inside a tight hairpin the bend's reach ended as an arc and each leg's as a straight line, and they didn't line up: a notch at each end of the arc, measured on seed 31337's first hairpin (radius 76).
- **Now:** how far a point is past the edge is measured from the nearest point of the road's centre line (each station answers for its 8 studs to the next). Along the road the stations hand over smoothly (a quadratic B-spline over a stretch and a half either way), with how far along the road a point is corrected for the bend. Between two stretches the nearer edge still wins (`Soft`). The inside of a hairpin is one V-shaped pocket whose two drop lines meet at the apex, with no arc.
- **Measured (DR-Lane1, GroundTests):** ground above the road or runoff: 0 of 18 870 points (1 before, 0.006 studs); the ground meets the runoff's edge within 0.14 studs of `Under` (0.35 before); no seams; a client's replay the same; a point 2.7 microseconds (as before). The one failing check, "cut or fill at the centre line over 20 studs" (48 of 936), is the road's own following and failed the same before.

## As built: step 1, the range (T-235)

`Road/Range` (new), `Road/Ground` (`field`, `base`, `h`, `relief`, `where`, `passAhead`), numbers in `Config.Range` (new). **Switched off for runs** (`Config.Range.Shape = "belts"`): today's road can only work its way down, so a run keeps the belts until step 2 lets the road climb to a pass. Tests and step 2 ask for the range by name (`Ground.field(seed, origin, fall, "range")`).

- **The frame:** `t` along the way the run goes (the belts' downhill, so the run sets off the same way), `v` across.
- **Ridges** lie across the way, one every 5 500 studs give or take 1 200, each wandering 850 studs either way over 6 500 across (measured 2 200 to 8 900 apart on 20 seeds). Along its crest a ridge rises and falls a fifth either way over 9 000 studs, and dips to a **saddle** about every 3 000 studs (a wave whose spacing and depth wander, so no ridge goes long without one); no saddle lower than 380 studs over the start valley.
- **Valleys** lie between, their floors 40 to 60% of the way across, 110 studs below to 80 above the start valley's floor and wandering 60 either way. Each **face** falls from the crest as (1 - x)^1.2 to 1.8, steep near the crest and easing out at the floor; crests rounded over 40 studs.
- **Spurs and gullies** run down the faces (ridge, gully and fine octaves of 170, 60 and 10 studs), a seventh of them on the valley floors and all of them from a third of the way up.
- **The start** is on the floor of the first valley, square across from where the road begins, so a run starts low and climbs first.
- **Where you are** (`Ground.where`): pass, ridge, valley or face; height in the band; slope; distance to the crest; which ridge; how near a saddle. A pure function of the place.
- **The pass ahead** (`Ground.passAhead`): on the next ridge, the saddle within 4 000 studs either way across whose height plus 0.08 a stud off to the side is least.
- Noise offsets are kept small on the range: far from its origin `math.noise` steps (a tenth of a stud every third of a stud on the finest octave).

### Measured (DR-Lane2, RangeTests 14 of 14)

20 seeds, a 90 000 by 40 000-stud box each:

- Height: -263 to 1 343 studs (the fall-kill height is -500). Crest over the valley floors: 286 (the lowest saddle) to 1 252 (the highest peak).
- 692 saddles on 220 ridges, every one a real dip (60 studs or more on both sides); every ridge has one within 4 000 studs of any line across. The pass ahead of the start is on the first ridge, at its crest, on all 20.
- Along lines across the range: steeper than 30 degrees 25%, under 8 degrees 20%; pass 6%, ridge 5%, valley 28%, face 62%.
- No seams; h costs 0.6 microseconds a point. GroundTests unchanged (the belts are untouched).

## As built: step 2, the road crosses passes (T-238)

`Road/SplineGen` (`_planRange`, `_target`, `_rescue`, range branches in `_slopeAim`, `_turn`, `step`), `Road/Range.ridgeAhead`, numbers in `Config.Range` (the road block) and `Config.Spline.Ground` (`TurnFill`, `TurnMaxCut`). **The range is switched on** (`Config.Range.Shape = "range"`): every ground run (`ground mesh` / `ground terrain`) gets it. Today's non-ground road is unchanged.

- **The pass ahead:** the road heads for the saddle `Ground.passAhead` picks on the ridge ahead, kept until it crosses that ridge; then the plan is dropped and the next pass picked.
- **Climbing or coming down** is read where the road is: on the face of the ridge the pass is on, it climbs; anywhere else it comes down toward the valley.
- **Legs:** across the face (its slope read where the road is, over 200 studs, with a third of the spurs' slope), tilted toward the way on: up on a climb, down on a descent. Each runs to 1 500 studs past the pass across, then a hairpin the short way round onto the next leg the other way: switchbacks stacked under the pass. Every leg makes at least 8 degrees of headway along the way on; where the slope's level line curls back (a bowl under the pass, a peak's flank) it follows the line forward the other way first.
- **The last stretch:** straight for the pass once within 900 studs and 3 degrees.
- **Hairpins hug the face** (DECISIONS.md 2026-11-15): on steep ground as tight as the road allows (70 to 80 studs), and fitted so each stud above h counts 4 times one below: they sit in a cut with a wall on the inside (up to 45 studs below h) rather than out on fill (20 at most).
- **Never boxed in:** a planned turn refused 6 times replans the way to the pass; and when the road is about to box itself in, it tries every bend (20 to 160 degrees either way, 70 to 400 studs radius) for one that gets it clear before giving up.
- **The range was made gentler for the road:** ridges 6 500 studs apart on average, peaks 550 to 900, faces (1 - x)^1.0 to 1.4, spurs 60 studs (100 and 170 left the road unable to follow them).

### Measured (DR-Lane2, `RangeTests.road`, 16 seeds x 25 000 studs)

- **Climbs and descents:** climbing 51% of the road, descending 46%.
- **Passes:** 34 ridges crossed, about one every 10 000 studs, at the crest's height there give or take (worst 196 studs off it, where the road crossed beside the saddle).
- **Height:** lowest point -155 (the fall-kill height is -500), highest 616.
- **Stalls:** 1 of 16 roads boxed itself in, at 23 600 studs (before the rescue: about 1 in 8).
- **On the slope:** median 1.5 studs off h; **15% of the road over 20 studs off it**, nearly all cuts, worst on the steeper faces near passes. (On the belts it was 5 to 10%.) GroundTests' trench count fails on the range for the same reason.
- Generator worst step 27 ms (11 to 16 on the belts).

### Known

- **Cuts:** a road crossing a range's faces digs in more than it did on the belts. Lower spurs, a gentler range, and narrower switchback zones were tried and moved it little; forcing headway is most of it, and without it the road stalls.
- **A rare stall** remains: about one per 400 000 studs of road.
- Not driven live by the agent: the car could not be put on the road from the server in the lane; the client draws from the same maths (GroundTests' replay check passes).

### Fixed: T-242, the road doubling back into a deep trench

The user drove a range run whose road turned back the way it came and ran along the bottom of a cut far below a cliff wall. It was the road's layout on the range, on main, not the far-mountains change in that lane (that one only drew the horizon, since removed: `T-243`).

- **Why:** a leg's heading follows the face's level line, and where that line ran square to the way on, the leg swapped to the other way along it from one section to the next: about a quarter of a leg's heading updates jumped more than 60 degrees, most of them 100 to 180. No ordinary bend can turn that far, so the road laid its escape, a straight, again and again: 12% of the road was escapes, they ran on 1 000 studs and more, back the way the road came, climbing at 8 degrees into a face that rose faster. Smaller causes: the nearest-fitting bend was laid however far it strayed, and a bend straightening the road before a hairpin was never checked against h (one ran 100 studs into the face).
- **Now** (`SplineGen._slopeAim`, `_follow`, `_planned`; numbers in `Config.Range`):
  - A leg changes to the other way along its level line only where the way it is going heads back by `LegOnward` (8 degrees) and the other way heads on by as much, and it keeps to that.
  - A leg's heading is checked against h itself, 60 and 120 studs ahead, within 40 degrees either way of the face's heading (`AimLocal...`).
  - When no random section stays within 10 studs of h, the road takes the straight or bend (up to 60 degrees, radius 120 or 250) that best brings it back to h, judged 100 studs past it, with heading back the way on costing heavily (`Follow...`). This replaced most escapes.
  - A straightening bend before a hairpin is laid only if it stays within 20 studs of h (`StraightenMaxOff`); otherwise the hairpin turns from the heading the road has.
- **Doubling back** is the road falling back more than 300 studs along the way on behind the furthest it has reached. A switchback is not one: its legs stack up the face, each further on, and a hairpin reaches back less than its width.

Measured (DR-Lane1, `RangeTests.road`, seeds 1 to 16 x 25 000 studs, before, then after):

| | Before | After |
|---|---|---|
| Doubling back | 3 times, worst 706 studs | none |
| Deepest cut | 290 studs | 138 |
| Road over 60 studs below h | 2.3% | 0.6% |
| Longest stretch over 60 deep | about 1 300 studs | 512 |
| Road over 20 studs off h | 14.6% | 10.4% |
| Stalled | 1 of 16 | none |
| Climbing / descending | 51% / 46% | 52% / 45% |
| Ridges crossed | 34 | 31 |
| Generator's worst step | 23 to 24 ms | 24 to 25 ms |

On 32 more seeds (17 to 48): none stalled, 10.1% over 20 studs off h, 0.55% over 60 deep (longest 400 studs, deepest 116). The road fell back once, 870 studs, on seed 26 at 23 800 studs, boxed in between its own legs below a pass. Before T-242, seeds 25 to 48 had 5 falls back (worst 531), 3 stalls, 3.3% over 60 deep and a deepest cut of 278.

RangeTests checks it now on seeds 1 to 16: no doubling back, and no trench (at most 1% of the road over 60 studs deep, no such stretch over 600 studs, none over 150).

Known: deep cuts are rarer and shorter, not gone, and the road can still fall back where it is boxed in, about once in a million studs. The deep ones left come where a leg must turn round on a steep face away from a planned hairpin; nothing tried (heavier costs on depth, a hairpin at each turn-round, smoothing the heading) cut them further without the road going back the way it came. GroundTests: following the mountain now passes; trench stations 95 of 936 (129 before). Its trench, over-20 and seam checks failed until T-244 brought them up to the range (below).

### The road's tests brought up to the range (T-244)

Six road suites were failing on main. None was the road misbehaving; each test's expectation was from before an approved change:

- **RangeTests:** ridge spacing is now checked against the config's own limits (6 500 studs apart give or take jitter and wobble, since T-238), not the old 3 000 to 8 000.
- **GroundTests:** the trench and over-20 limits are the range's (under 12% each; 10.1% and 9.0% measured), with how deep and how long a trench may be left to RangeTests. A jump is a seam only if it doesn't shrink with the step: the one wall on seed 2024 (a slope of 11) is continuous.
- **SplineWorldTests:** both normals are judged on the surface and the wall themselves; the parts, flat triangles and 4-stud chords, are judged on the mean. The K-rail search may take a bend of 200 studs or wider: every rail in the seed's first 8 000 studs is on a bend now. On a banked bend the car is held at a K-rail by its push-out, not its sweep (0.3 to 0.45 studs short of the face).
- **SplineTests:** a section's cost is judged on the mean (2.0 ms) and the median road's worst (about 15 ms). The single worst section of all 20 roads swings between 20 and 26 ms from run to run, a different road each time.
- **RoadTests, RunTests:** they test the piece road, and since T-141 a run lays the spline road, so they switch the next run to the piece road themselves and put it back.

## As built: the range twice the size (T-245)

The user, 2026-11-16: "I want to basically 2x the scale of the mountains and valleys that we have now. the goal being to create more space to put in our biomes in the future. the steepness and shallowness is good the way it is ... 2x it."

`Config.Range` (and `Road/Range`, whose saddle easing was 40 studs written in: now `SaddleEase`). Every face keeps its steepness; the range grows.

- **Doubled, across and up together:** ridge spacing (13 000 give or take 2 400), the crest's wander (1 700 over 13 000), peaks (and their rise and fall along the crest, over 18 000), saddle depth and floor (`SaddleMin`), a saddle every 6 000, a saddle's rise and span (120 within 4 000), the valley floors' heights and wander (120 over 12 000), the crest's rounding (80). With the same seed the base shape is exactly twice the old one, but for the lift below.
- **Lifted 200 studs:** the valley floors and the crests sit 200 studs above twice T-238's; the start valley stays the zero. Doubled as they were, the lowest ground came to -329, 171 studs above the fall-kill height (-500). So the start valley lies a little lower among the others, and the faces either side of it are about a tenth taller (the first climb is a little steeper than twice the old one).
- **Doubled with it, the range's own geography:** where a pass and a ridge are read (`PassReach` 700, `RidgeReach` 500), the window the pass ahead is looked for in (`PassWindow` 8 000, sampled every 100), the switchback band below a pass (`PassBand` 6 000) and the longest leg (`LegMax` 12 000), and how far off the road heads straight for a pass (`DirectReach` 1 800).
- **Kept as they were, the road's size:** the spurs and gullies the road follows (`Octaves`: the 1 400/60 "ridge" octave too: 120 studs tall, the road could not follow it), hairpin, rescue and follow turns and radii, `PassOver`, `LegMin`, `AimSpan`, `DirectGrade`, `PassLean` (a height per stud: the same ratio doubled).
- **One road number changed:** `AimLocalBackCost` 200 to 400. Legs are twice as long, so a heading a little back the way on fell back twice as far over one (4 times in 96 roads of 50 000 studs, to 1 140, where it was twice before, to 874). At 400 the rate is what it was.

### Measured (DR-Lane1, 12 seeds for the shape, 96 roads of 50 000 studs for the road)

| | Before | After |
|---|---|---|
| Ridges apart (median) | 6 486 | 13 070 |
| Peaks over the valley floor (median, highest) | 863, 1 140 | 1 690, 2 296 |
| Saddles over the floor (median) | 471 | 950 |
| Face slope, the range alone (median, mean) | 10.6, 11.2 degrees | 10.6, 11.3 |
| Face slope, with spurs and gullies (median, mean) | 15.4, 16.5 degrees | 15.3, 16.4 |
| Ground (20 seeds) | | -249 to 2 449 |
| Road to the first pass (median) | 5 500 studs | 13 200 (10 000 to 31 000) |
| Ridges crossed, 48 roads | 193 | 93 |
| Fell back over 300 studs, 96 roads | 2 (874, 342) | 2 (313, 336) |
| Stalled, 96 roads | 1 | 1 |
| Trench stretches over 600 studs, 96 roads | 2 (720, 880) | 2 (640, 880) |
| Deepest cut, 48 roads | 138 | 130 |
| Road over 60 deep / over 20 off h, 48 roads | 0.54% / 10.9% | 0.59% / 10.9% |

The climb to a pass is over twice as long as before: the first pass is a little more than twice as high (960 or more over the start, from 380), as the lift adds to it.

**Tests:** RangeTests lays its roads to 50 000 studs (twice as far, so they cross as many ridges), its bounds are twice as big, and its doubling-back check allows the rate measured before and after (once in its 800 000 studs, never past 600): the road falls back about twice in 5 million studs either way, and with zero allowed which seeds passed was luck. Before T-242 it was 3 times in 400 000, to 706, which still fails. RangeTests, GroundTests, SplineTests and SplineWorldTests pass.

**Not changed, and worth a look:** the ground is drawn 1 100 to 2 100 studs round the car (`Spline.Ground.Detail` `Reach`); with ridges 13 000 apart, a valley shows its own faces and little of the ridge beyond, as was nearly so before.
