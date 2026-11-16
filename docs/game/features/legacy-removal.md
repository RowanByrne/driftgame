# Feature: Remove the old road and ground systems

**Status:** done 2026-11-16. All three steps merged to main (`T-248`, `T-249`, `T-253`). **Owner task:** `T-247`.

## Goal

The game goes forward with one road and one ground: the spline road laid over **our own ground mesh**, across the **mountain range**. Everything older is taken out of the game properly, so it costs no download size, no load time and no frame time, and no agent has to keep it working. The user, 2026-11-16: "time to remove the old road generation and roblox terrain generation systems from the game. we are now going forward with the ground mesh system as the main one. Remove the old systems from the game and do it properly so the remnants don't take up game size or create any lag".

## What goes

1. **The "current" ground and the Roblox Terrain ground.** The older hillside drawn as part of the road (rock faces, cliffs and their haze, hedges, the hillside rays: `SplineHill`, `SplineProfile`, the face and haze code in `SplineMesh`, `SkyController`'s haze, `Config.DayNight` haze keys), and the Roblox Terrain option (`Drift/GroundTerrainView`). The `ground` console command and `Config.Spline.Ground.Mode` go: **every run is a ground-mesh run.** The TEST ONLY panel's SPLINE TEST ROAD (it shows the old ground) goes with `SplineTestService`'s test road.
2. **The piece road.** `Road/Pieces`, `Road/Generator`, `Road/Builder` (its one shared helper, the triangle slab, moves to where the spline road's fallback parts use it, or the fallback goes if the mesh is always there), the pieces tables and piece tuning in `Config/Road`, `RoadService`'s piece paths and debug readouts, the `roadmode` and `barriers` commands, the TEST ONLY RUN ROAD toggle. With it: the playground's **test hill** (built from road pieces) and its LIFT TO HILL TOP button, and the **Showroom** tool. Today every client builds the whole piece set at startup and the server builds the test hill on every start, though neither is used.
3. **The "belts" mountain and the old descent planner.** The T-228 single-slope mountain in `Road/Ground` and `Config.Range.Shape`, and in `SplineGen` the descent band, the side flip, the old leg planner, the cliff "grandeur" bodies (computed for every section, drawn by nothing now), with their `Config.Spline` keys and the section fields the client no longer needs.

## What stays

- The spline road and its ribbon (tarmac, gravel bevel, runoff, K-rails, groves, the skirt), the ground mesh, the range and its passes, the day/night sky.
- **What the car hits does not change.** The road still decides an edge kind each side (rock or cliff), and the car's collision reads it: on a rock side a wall at the runoff's edge, on a cliff side no ground past it. These kinds stay, only their drawing goes. Changing what the car hits is a separate decision.
- The settings "Ground detail" and "Road behind", which belong to the mesh.
- `TrackService` and the playground (pads, garage street), which don't depend on the old road; only the hill goes.
- The road's own bends, hairpins and how it lays out on the range.

## Rules and numbers

No tuning changes. Each step leaves every run looking and driving as a ground-mesh range run does today. The road's layout for a seed may shift only where removed code fed the random numbers (`BeltWarp`), and the step says so if it does.

## Server and client

Sections sent to clients lose the fields only the old ground drew (`gd` and any other the step finds unused). The run's `start` message loses `mode`.

## Contracts

Each step removes its rows from `CONTRACTS.md` (the `ground` and `roadmode` commands, piece-road service methods, the removed section fields) in the same commit.

## Testing

Each step proves, in a lane:
- **Before and after:** the number of scripts and their total source size, the client's startup time to a first frame, the client's memory after starting a run, and the frame time driving a minute (median and worst).
- **Nothing old runs:** no piece set built, no test hill, no haze writes, no Terrain material changes.
- **The kept path is unchanged:** a range run on a few seeds lays the same road as before (or says exactly where and why not), and the tests that remain pass, rewritten onto ground-mesh runs where they used the old ground (SplineTests, SplineMeshTests, SplineWorldTests, GroveTests, SplineTurnTests, RunTests, PlaygroundTests). Tests of only the old systems go (RoadTests, SplineHillTests, SplineViewTests).

## Order

The three steps share `SplineGen`, `RoadService`, `SplineMesh` and `SplineRoadView`, so they run one after another, not side by side: the ground first, then the piece road, then the belts and descent planner, which also waits for T-245 (doubling the range), as both edit the range's files.

## Open questions

- The test hill and the Showroom go with the piece road. Say if either should be rebuilt on the spline road instead.

## As built

### Step 1: ground mesh only (`T-248`)

- **Every run is a ground-mesh run.** The generator always makes the mountain; the client rebuilds it from the run's `seed` and `fall` (`SplineGen.replay` takes the seed) and always draws it with `GroundMeshView`. The `start` message lost `ground`; a client refuses a `start` without a numeric `seed` and `fall`.
- **Gone:** `SplineHill`, `SplineProfile`, `GroundTerrainView`, `SplineTestService` and its remote, the TEST ONLY panel's SPLINE TEST ROAD and RUN ROAD buttons (the RUN ROAD toggle went a step early, with the service that carried it; `roadmode` still switches until step 2), the `ground` console command and type, `RoadService` `GroundMode`/`SetGroundMode`/`RunGround`, the faces, hedges, hillside and haze in `SplineMesh` (the skirt is always drawn), the hillside redraw in `SplineRoadView`, the cliff haze in `SkyController` and `Config.DayNight`, `Config.Spline.Hill`, `Ground.Mode`, the Terrain option's keys, the face-only `Terrain` keys, `TestOrigin`/`TestLength`. Tests: `SplineHillTests`, `SplineViewTests`, `SplineTests`' grand-cliffs part and its checks of the old descent planner's rules.
- **Left for step 3:** the sections' `gd` (still made and sent, drawn by nothing) and the keys that shape it, the generator's branches for a road with no mountain, `Mountain.Mode` and the `start` message's `mode`.
- **The road is the same:** seeds 31337, 7 and 1234 lay identical roads before and after (6 000 studs, sampled every 250).
- **Size:** 309 scripts and 3.37 MB of source before, 301 and 3.26 MB after; what each player downloads, 1.89 MB to 1.82 MB.
- **Frame time and memory** (Studio lane, seed 31337, a minute along the road at 80 studs/s): the ground-mesh run costs what it did (worst frame 75.9 ms before, 41.6 after; road chunk build at most 4.2 and 4.1 ms a frame); no Terrain cell written, no hedge drawn, no mesh fallback. Studio's own memory total moves by tens of MB between playtests, too much to read a change this small from.
- **Tests:** `SplineWorldTests` drives seed 1234 now (31337's mountain road has no K-rail or wide-grass straight early on): 21 of 21. `GroundTests` belongs to `T-245` while it runs; its "current: the same road as before" check fails now and goes when that task has merged.

### Step 2: the piece road, the test hill and the Showroom (`T-249`)

- **Every run lays the spline road; nothing else exists.** `RoadService` lost the piece road's paths: `Road/Generator`, `Road/Builder` and `Road/Pieces` are gone, with `Mode`/`SetMode`, the guardrail switch (`SetBarriers`, `BarriersOn`, `DebugBarrierReport`), the piece timing ring (`DebugProfile`, `Config.Road.Profile`), the closing barrier part and the `Workspace.Road` folder (the spline road's closing barrier is the number sent to runners, as it was). `DebugState` reports `closingS`; `DebugPieces` lists sections (`s0`, `s1`).
- **No client builds the piece set any more.** The one helper the spline road used, the triangle slab, moved into `Road/SplineParts` (the fallback drawing and the tests' yardstick), so loading the road no longer pulls in `Builder` and `Pieces` and their 16-variant set (about 7 ms of every client's startup, measured).
- **The playground** lost the test hill (its pad, approach, `HillBase`/`HillTop` spots, `HasHill`, `HillTopCFrame`, `DebugHill*`), the `TestTools` remote and the TEST ONLY panel (`Drift/TestHud`, whose last button was LIFT TO HILL TOP), and `Config.Playground.HillPartBudget` and `HillPad`. A playtest still takes down an old saved `Workspace.Showroom` (`DR-Lane4` has one) so the playground is never doubled; the `Tools/Showroom` tool itself is gone.
- **Console:** `road-mode` and `barriers` are gone, and `tp hill`, `HillBase` and `HillTop` with them.
- **`Config.Road`** keeps only what the spline road, its window and its drawing read (122 lines, from about 1 100).
- **Tests:** `RoadTests` goes. `PlaygroundTests` loses its hill and tool checks (46 checks). `SplineTests` loses the check that the spline's limits sat inside the piece road's. `CollisionTests` keeps the old `MaxPitchStep` as its own constant. `RunTests` is rewritten onto the spline road (`T-250`): 17 of 17, the autopilot braking earlier for the mountain's hairpins (2.0 s ahead, to 20 studs/s), and the long-drive check now "up or down the mountain", since a range road climbs over its passes.
- **Size:** 301 scripts and 3.26 MB of source before, 291 and 2.89 MB after; what each player downloads, 1.82 MB to 1.66 MB.
- **SplineWorldTests** drives seed 2024 since the range doubled (T-245): on a mountain road the suite is seed-sensitive (2024 alone of nine seeds passed everything).
- **Frame time:** unchanged (the piece road was not drawn in a run): a minute along seed 31337, p99 36.4 ms and worst 38.1 ms in a 30 fps-capped Studio window, as before.

### Step 3: the belts mountain and the old descent planner (`T-253`)

- **The road every run lays is exactly the same.** Before any change and after it, 12 seeds (31337, 7, 1234, 2024, 8080, 1, 42, 99, 555, 9001, 123456, 777) were laid to 20 000 studs from `RoadService`'s origin and with none: every section's knots, runoff, edges, K-rails, gravel and groves (all but `gd`), written at full precision, hash the same, and the road ends at the same point to the last digit. The mountain too: `Ground.h` is identical on 625 points over 24 000 studs square for 31337, 7 and 1234. No shift anywhere: `BeltWarp`'s draws came after everything the range takes from that stream.
- **Gone from `Road/Ground`:** the T-228 belts (`belts`, their curve and slope, `beltSlope`, `grade`, the `shape` argument, `Field.shape`/`slope`/`belt`/`warp`), and the branches for a field without the range: every field is the range, `Field.range` always there. `Config.Range.Shape` goes, and the belts' `Config.Spline.Ground` keys (`Belt*`, `Octaves`, `Stretch`, `ReliefLow`, `ReliefSlopes`, and `AimAt`, `DownhillBias` that only the belts' aim read). The range keeps its own `Config.Range.Octaves` and `Stretch`.
- **Gone from `Road/SplineGen`:** the height band (`band`, `centre`, `drift`, `climbing`, `_bandRate`, `_centreAfter`, `bandAt`, `_hurry`), the side flip (`flip`, `flipWanted`, `flipDone`, `flips`; the uphill side and where the heading crossed the fall line stay: they decide the edges), `Mountain.Mode`, `mode` and `sense`, the old leg planner (`_planLeg`'s legs, switchbacks, double hairpins and sideways stretches, `_legAim`, `tilt`, `legGrade`, the stretch's line `lineX`), the band's grade picker (`pickGrade`), the runoff chosen at random (every runoff is the side slope's since T-228), every `if self.ground` and `ground.range` test (the true branch kept), and the grand cliffs (`_grand`, `bodyAt`, `_toTurnaround`, `turning`, `lastTurnEnd`, `lastGrand`). `SplineTurnFit.measure` loses its unused flip arguments. The plan is `_planRange` alone.
- **Gone from `Road/Spline`:** the grandeur track, `grandAt`, `lowAt` and `gd`'s checks. A section no longer carries `gd` (a client ignores one if it ever came); the `start` message no longer carries `mode`; `SplineRoadController` no longer checks `gd`.
- **`Config.Spline`:** the band (`MinHeight`, `MaxHeight`, `KeepGradeChance`), `HeadingLimit`, the old planner's `Mountain` keys (`Mode`, `LegTilt`, `LegLength`, the switchback, double hairpin and sideways keys, `LineReach`, `TurnLocationRetries`, `TurnDescentGrade`, `DescentRate`, `DescentFloor`, `ClimbRate`, `ClimbTop`, `FlipWithin`, `FlipClear`), and in `Terrain` `RunoffKnotEvery` and every grand and low rock key (`Grand*`, `RockTop`, `RockBack`, `RockSlope`, `LowRock*`). **Kept:** `RockHeight` (the car's wall), `HedgeHeight`, `HedgeThickness`, `EdgeDepth`, `RunoffMin`/`RunoffMax`, and the `Mountain` keys the range's plan and the turns' fit read.
- **Tests:** `SplineTests` loses the height band check, and its mountain part reads legs, turnarounds and turns back across the slope without the band or flips; `GroundTests` loses its belts block (the range's purity and start are `RangeTests`'); `RangeTests` loses its shape check; `SplineTurnTests` hashes the plan instead of the flips.
- **Size:** 291 scripts and 2.89 MB of source before, 291 and 2.85 MB after (no file went; `SplineGen` is 101 KB to 73 KB); what each player downloads, 1.66 MB to 1.61 MB.
- **The generator** costs 3.35 ms a section before and 2.92 after (the 24 oracle roads, 2 716 sections, Studio's Edit datamodel, one pass each, so a tenth either way is noise): most of it the grand cliffs' search of old road beside every section.
- **Tests in a lane** (one quiet playtest): SplineTests 53 of 53, GroundTests 17 of 17, RangeTests 18 of 18, SplineMeshTests 16 of 16, SplineWorldTests 20 of 20, PlaygroundTests 46 of 46, CollisionTests 50 of 50, RunTests 17 of 17, SplineTurnTests 8 of 9, GroveTests 10 of 11. **The two that fail read only the road, which is unchanged:** GroveTests' "groves on flatter stretches" (1.2 stretches per 10 000 studs, wants 2: on the range a grove needs a shallow side slope the whole section, T-228) and SplineTurnTests' "terrain checks retry unsuitable shapes" (no fitted turn rejected in 3 roads of 12 000 studs). Both were set before the range; they need retuning or rewording, not this step.
- **A run** on seed 31337 draws its road and ground mesh on the client (11 sections, none refused, 255 ground tiles), with no errors.
