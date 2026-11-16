# Feature: Remove the old road and ground systems

**Status:** specced (plan waiting for the user's OK). **Owner task:** none yet.

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
