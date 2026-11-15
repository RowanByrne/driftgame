# Feature: Road biomes

**Status:** built as T-203, then rolled back on 2026-11-15 at the user's request (`DECISIONS.md`); none of it is in the game. This is the spec as first written. The built work is on the `feature/linked-biomes` branch.

## Goal

Break up the almost constant cliffs with distinct stretches of Japanese mountain road: steep cliffs, smaller cliffs and open fields. The road moves back and forth between them through continuous terrain, so the player feels a change of place rather than a new scenery choice at every bend.

The user's brief (2026-11-14) is steep cliffs on both sides with lots of guardrails and tight, twisty road; small cliffs with a drop on one side and a semi-steep to smooth terrain ramp on the other; and mostly flat fields with a slight dip down the mountain. This extends `mountain-road.md`, `mountain-direction.md` and the **As built** sections of `continuous-mountain.md`.

## How it plays

1. Start the same endless run. Long, linked terrain stretches are chosen from the run's seed and shared by everyone on that road.
2. Fields open the view and the land beside the road. Smaller-cliff sections bring back a one-sided drop and a rising hillside. Steep stretches feel more exposed, with tighter road and substantially more protection at hazardous edges.
3. Grass, terrain slope, cliff height and road rhythm blend between those settings over a real stretch of road. The road never teleports to a new elevation or swaps a field straight into a vertical wall.
4. The sequence keeps returning to gentler terrain; steep cliffs become an occasional contrast rather than the permanent setting.
5. Running onto a field or a low traversable bank meets the ground the player sees. Actual drops still drop, and a guardrail still stops the car. Drift, tyres and scoring keep their existing rules.

## The three starting biomes

| Biome | Terrain | Road and protection |
|---|---|---|
| Steep cliffs | **Plan interpretation:** occasional ridge-like stretches with exposed drops on both sides, joined back into the mountain at their ends | Tight and twisty within the existing drivable radius, grade and bank limits. More guardrail runs, with each exposed side assessed independently |
| Small cliffs | A smaller drop on the downhill side; a semi-steep bank easing into a smoother rising slope on the other | Mixed bends with breathing room. Rails follow actual exposed edges and bends, with fewer runs than steep cliffs |
| Fields | Broad, mostly flat grass with a gentle fall in the mountain's downhill direction; no mandatory cliff immediately past the runoff | More open, sweeping road with fewer barriers. Grass retains its current grip and score behaviour |

The interpretation of steep cliffs is stated on the plan for review: both-side drops imply a ridge, rather than the current uphill rock wall/downhill drop. The global mountain direction still makes sense; a ridge is a local terrain form, not a random flip of the fall line.

## Left out

- Extra biomes, villages, forests, farmland props, new weather, ambient audio or final scenery art.
- Changing the tarmac width, the drift/tyre model, car-body physics, grass grip/score values or the run's score rules.
- Road crossings, stacked roads or relaxing existing crossing and escape safety to fit a prettier stretch.
- An unlimited drive-anywhere world, shortcuts or a new off-road progression system. Traversable field extents must be finite, visible and documented.
- Restoring hedges as structural road edges, changing the far horizon or rebuilding the playground/hand-made track.

## Rules and numbers

Starting proposals, not measured tuning; keep the values in `Shared/Config/Spline.luau` and settle them in the feature's lane:

| Item | Starting proposal |
|---|---|
| Long-run distance mix | Fields 45%, small cliffs 35%, steep cliffs 20%; gentler terrain remains the majority |
| Established stretch length | About 1,600-3,200 studs, subject to fitting a coherent terrain/road transition |
| Transition length | About 300-600 studs, long enough to blend the terrain and road parameters |
| Same-biome repeats | Join them into one stretch or choose another; no pointless repeated boundary |
| Field slope | A slight downhill fall, first try 2-6 degrees beside the road; fit safely between existing road legs |

The mix is a distance target, not a blind per-section coin toss. Measure actual proportions across long seeded roads, including how transitions are counted, rather than claiming the configured weights are the resulting mix.

Use a seeded biome schedule with stable endpoints and an explicit transition parameter. Independent scenery changes must not unpredictably reroll later biome choices. Turn previews clone all relevant random/schedule state, so rejected candidates do not change the final sequence. Server-chosen section data and late-join snapshots contain what clients need to replay the same result.

Retain the fall line, rare deliberate turnarounds, periodic recovery climbs and height safety. Biomes bias the road's bend mix, radii, spacing and rail coverage; they do not bypass curvature/grade easing, no-crossing, terrain turn fitting or the escape test. A field need not make the whole run level, and a steep biome must not force an unsafe hairpin.

Blend terrain height and slope continuously. Adjoining chunks and neighbouring legs must agree on shared ground; a transition must not create a shelf, crack, intersecting road, face through the tarmac or ground changing under a car when another chunk streams in.

## UI

No new player UI. Provide Studio/debug inspection of the biome at a road distance, the next transition, the schedule and measured distribution, so testers can find every case without waiting through a long drive. Keep existing run controls and shortcuts.

## Server and client

The server chooses the road and biome schedule. Clients replay the supplied section/profile data; they do not choose their own biomes.

The physical and drawn surface must share an efficient terrain definition: height, normal, surface type, traversable extent and solid/drop boundaries. Use it for rendered banks/fields, the car's four wheel queries and walking support. The existing car and body simulation consume different ground, not a new physics engine.

Current code is an important boundary: `SplineHill` draws the wider mountain, but `Drift/SplineWorld` still treats rock as a wall and the cliff lip as a fall. `SplineHill.heightAt` is a slow measurement helper, not a per-wheel runtime sampler. Simply shrinking the drawn cliffs would leave invisible collisions and drops, so build a suitable shared query before making fields traversable.

Review road projection/progress and off-road lookup limits together (`SplineSequence`, `SplineWorld` and `RoadGroundController`). Broad fields must not make a car attach to the wrong nearby road leg, skip the closing barrier, move run progress forward by cutting across a field, or respawn in the wrong world. Leaving the finite supported ground retains the existing fall/recovery behaviour. Include visible fallback ground when EditableMesh is unavailable; today's `SplineParts` fallback is tarmac-only.

Keep streamed work bounded and preserve the current eight-mesh budget. Coarsen distant scenery before road or near-ground fidelity. Ground ownership and height near a car must stay stable when neighbouring sections arrive or are retired.

## Contracts

No contracts change in this planning commit. Implementation proposes and records the biome/transition/profile section fields, validation, compatible defaults, snapshot/replay rules, shared ground query and debug API in `CONTRACTS.md` and `ARCHITECTURE.md` with their code. Shared contract changes land before dependent tasks.

Do not remove the existing edge fields or change their meaning without adapting every consumer: generator, replay validation, turn preview, mesh, fallback, car, walking support, rails and tests. Older sections without biome data need an explicit supported default or migration at the owning boundary.

## Analytics

No new analytics event is required for the layout sketch. Audit existing run/scenery events during implementation and document any agreed biome field/event in `EVENT-CATALOG.md` before emitting it. Debug distribution measurements are not player telemetry by default.

## Monetization

None.

## Platform risks

None added; original generated scenery and the game's existing approved materials/assets.

## Art and sound

Use the existing grass, gravel, rock, guardrail and mountain palette. No new texture uploads or sound work in this feature. Before building, show a representative route sketch and the three terrain cross-sections with their transition distances; the user approves the layout. Block it out in the feature lane, then get the user's drive-through approval before final scenery tuning, following `WORLD-BUILDING.md`.

## Testing

- Deterministic schedule/profile tests: same seed and section history give the same biomes, terrain and joins; rejected turn previews do not consume state; late join and streamed replay match. Measure the three biome proportions and actual stretch lengths over several long seeds.
- Exercise all six directed transitions between the three biomes, both sides of the road, valley floors/passes, recovery climbs, hairpins and nearby parallel road legs. Adjacent chunk contexts must agree on shared height and normals without a new visible seam.
- Field and bank fixtures: wheel ground height/normal matches visible terrain; cross the road edge and transition at slow and high speed, stop on a bank, re-enter from grass and get out/walk/get back in. No invisible cliff or wall where the land is traversable, and no invisible floor over a real drop.
- Verify field extent/projection, off-road progress, closing barrier, falling and respawn. Leaving one road leg's field must not jump to another leg or advance the run illegitimately. Validate rail geometry and collision on both exposed sides, including transitions and tight bends.
- Check the mesh-unavailable fallback, day/night readability, fixed triangle/mesh budgets and streamed build/frame cost on representative steep, gentle and field stretches. Existing road/turn, hillside, mesh, world, streaming, body/suspension and run checks still apply; record pre-existing failures separately.
- Source-gate the changed scripts, run quiet lane playtests, inspect the console and stop every playtest. Use numbers and debug profiles to prove behaviour; at most three visual screenshots per task. The user drives each biome and the joins in the feature lane before merge.

## Planned steps

1. **Sketch biomes and linked stretches** - route/cross-section sketch, distribution and transition plan; the user reviews the ridge interpretation and approves the layout.
2. **Build shared biome terrain** - deterministic section contract/schedule, efficient shared ground, continuous profiles and the lane blockout, with matching car/walking/fallback support.
3. **Shape roads and rails by biome** - safe changes to bend rhythm and hazard-based guardrails; dress the chosen profiles with existing scenery.
4. **Check and tune long biome runs** - every transition, replay, off-road behaviour, long-run distribution, streaming budgets and representative user drives.

The feature's own agent owns these sequential steps and reserves its lane after plan approval. The conductor handles the final merge request.

## Open questions

- The plan treats cliffs on both sides as a ridge with two exposed drops; the user can revise that interpretation before the layout is built.
- Exact field width, small-cliff height, ridge profile and rail coverage are settled against the layout sketch and measured blockout. They are not permission to widen the tarmac or change grass handling.
- Initial distribution and stretch/transition lengths above are proposed tuning, to be adjusted by the user's drive.
