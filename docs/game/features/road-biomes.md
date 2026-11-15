# Feature: Road biomes

**Status:** layout, shared terrain, road/rail and consistent-grade checkpoints approved (T-204/T-209/T-210), with the isolated future-braking correction approved in T-213. Final distant-terrain, reach, join and streaming work is in progress in T-212. **Owner task:** T-203, built step by step in lane 2 on `feature/linked-biomes`.

## Goal

Break up the almost constant cliffs with distinct stretches of Japanese mountain road: steep cliffs, smaller cliffs and open fields. The road moves back and forth between them through continuous terrain, so the player feels a change of place rather than a new scenery choice at every bend.

The user clarified the brief on 2026-11-14: "we are not majorly redesigning the style of the terrain we already have, just creating categories to fit it into." Steep cliffs keep today's uphill mountain and downhill cliff. Small cliffs have a smaller downhill drop and a semi-steep to smooth rising bank uphill; fields are mostly flat with a slight fall down the mountain. Categories change frequently and blend while driving within an existing road section; switchbacks do not mark their boundaries. This extends `mountain-road.md`, `mountain-direction.md` and the **As built** sections of `continuous-mountain.md`.

## How it plays

1. Start the same endless run. Shorter linked terrain categories are chosen from the run's seed and shared by everyone on that road, independently of road-section and switchback boundaries.
2. Fields open the view and the land beside the road. Smaller-cliff sections bring back a one-sided drop and a rising hillside. Steep stretches feel more exposed, with tighter road and substantially more protection at hazardous edges.
3. Grass, terrain slope, cliff height and road rhythm blend between those settings over a real stretch of road. The road never teleports to a new elevation or swaps a field straight into a vertical wall.
4. The sequence keeps returning to gentler terrain; steep cliffs become an occasional contrast rather than the permanent setting.
5. Running onto a field or a low traversable bank meets the ground the player sees. Actual drops still drop, and a guardrail still stops the car. Drift, tyres and scoring keep their existing rules.

## The three starting biomes

| Biome | Terrain | Road and protection |
|---|---|---|
| Steep cliffs | Today's tall uphill mountain/rock face and deep downhill cliff, retaining the current shaping and safe fitting | Tight and twisty within the existing drivable radius, grade and bank limits. More guardrail runs protecting actual exposed edges |
| Small cliffs | A smaller drop on the downhill side; a semi-steep bank easing into a smoother rising slope on the other | Mixed bends with breathing room. Rails follow actual exposed edges and bends, with fewer runs than steep cliffs |
| Fields | Broad, mostly flat grass with a gentle fall in the mountain's downhill direction; no mandatory cliff immediately past the runoff | More open, sweeping road with fewer barriers. Grass retains its current grip and score behaviour |

The user rejected the two-drop ridge interpretation in v1. Keep the existing mountain shape and compass direction: one side uphill, the other downhill. This feature categorises and blends the terrain already in the game, with fields and gentler banks reducing how often tall cliffs dominate.

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
| Category stretch length | Seeded semi-random lengths within configured minimum/maximum bounds, starting at 400-900 studs between boundaries; do not repeat the sketch's lengths |
| Transition length | At least the proposed 180 studs, centred on a category boundary and lengthened where needed for a gradual physical profile change. Reserve enough space for the transition before choosing the next one |
| Same-biome repeats | Join them into one stretch or choose another; no pointless repeated boundary |
| Field slope | A slight downhill fall, first try 2-6 degrees beside the road; fit safely between existing road legs |

The mix is a distance target, not a blind per-section coin toss. Measure actual proportions across long seeded roads, including how transitions are counted, rather than claiming the configured weights are the resulting mix.

Use a seeded biome schedule with stable endpoints and an explicit transition parameter. Independent scenery changes must not unpredictably reroll later biome choices. Turn previews clone all relevant random/schedule state, so rejected candidates do not change the final sequence. Server-chosen section data and late-join snapshots contain what clients need to replay the same result.

The user approved the corrected layout with two requirements: terrain must actually
transition gradually from hills to steep cliffs, and each category's length must be
semi-random within minimum/maximum bounds. Randomise lengths independently from bend
and scenery choices using a seed-derived stream. Do not cycle fixed lengths, evenly
alternate the categories or reroll a length during a rejected turn preview. The
sketch is explanatory only. A minimum blend distance is not permission to turn a
low bank into a tall cliff too rapidly: limit the rate of physical profile change,
reserve the required transition space and avoid a second transition interrupting it.

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

## Revised layout v2 (T-204)

Review drawings: [representative route](../../../assets/reference/road-biomes/route-v2.png)
and [terrain cross-sections](../../../assets/reference/road-biomes/profiles-v2.png).
The source beside them rebuilds both drawings with Pillow; these are design diagrams,
not output from the road generator or measured drive results.

The user rejected v1's long, switchback-to-switchback drawing and two-drop ridge.
The first two cross-sections were accepted as suitable; retain their field and small
cliff shapes. The revised third profile shows the existing tall uphill rock face
and deep downhill cliff. The v1 images remain only as superseded review history.

The revised route shows one 4,000-stud example on a continuous road: fields 600,
small cliffs 700, steep cliffs 400, fields 600, small cliffs 700, steep cliffs 400,
then fields 600. Its nominal mix is 45% fields, 35% small cliffs and 20% steep
cliffs. This is an example rather than a repeating pattern. Grey markers show
arbitrary existing road-section ends independently of the category boundaries.
They illustrate that blends can begin and finish partway through a section or bend.

Category stretches are sampled semi-randomly between configured minimum and maximum,
starting at 400-900 studs **boundary to boundary**. The 180-stud blend in v2 is a
starting minimum, not a fixed duration for every terrain change. A stronger profile
change must receive enough distance to meet the profile-rate limit. Reserve that
distance when placing transitions; do not overlap or interrupt a reshaping cliff.
For the minimum 180-stud case, 90 studs each side leaves 220-720 studs fully
established. Longer blends use correspondingly more of the available stretch. Use a continuous
smooth blend, with a flat derivative at both ends, for terrain parameters. Road
preference changes over the same interval while curvature/grade/bank keep their own
existing easing limits. Count transition distance by its biome weights (half to each
neighbour over a symmetric complete blend). Avoid identical consecutive biomes; pick
the next stretch with a seed-derived, distance-deficit schedule rather than rerolling
scenery per bend. All six directed transitions remain possible. Measure the resulting
mix over long seeds before claiming the target is met.

At an illustrative 100 studs/s, the initial 400-900-stud boundaries arrive every 4-9
seconds and the minimum 180-stud transition takes 1.8 seconds; longer physical
transitions take longer. The pictured route is 40 seconds. This pace is below the
stock cars' top speeds (150-215 studs/s); it is not a measured average. Actual bends
and drifts take longer.

| Profile | Proposed starting shape at an ordinary mid-stretch point | Road rhythm and protection |
|---|---|---|
| Fields | 80 studs of gently sloping grass past each asphalt edge (210 studs across including the road); about 3.5 degrees down the mountain, easing from the road's bank. Visible outer banks delimit supported ground | Mostly sweeping bends and breathing room. Few rails unless a real nearby hazard remains |
| Small cliffs | About 20 studs of runoff, a smooth-to-semi-steep uphill bank rising roughly 15-35 studs, and a 25-50-stud drop downhill | Mixed bends. Rails protect exposed bends; a gentle bank is ground rather than an invisible wall |
| Steep cliffs | Preserve today's tall uphill mountain/rock profile and deep downhill drop, with the same runoff and local clearance fitting. Current grand faces can reach 140-220 studs uphill and up to 200 studs downhill; these are existing maxima, not a new target forced everywhere | Prefer tighter bends within today's limits, with much more rail coverage at actual exposed edges |

These are blockout targets for review, not minimums that overrule safe fitting. Close
road legs and tight turns may reduce widths/heights; the visible ground must show
that reduction. Tight gravel cliff edges can still occur where fully protected, but
fields must not inherit random cliffs or tree walls immediately beside the asphalt.
No new tree or prop art is needed. Leave field sightlines open.

Keep the existing profile topology, mountain joins, grandeur/turnaround reductions
and neighbouring-road caps. A category smoothly adjusts the scale and slope of those
forms. It does not replace the mountain with a new terrain style or require a
switchback at a category change. Bend selection is a gentle preference: its existing
curvature, grade and bank safety easing can outlast the shorter terrain blend.

The field is finite, not an invisible plane. The broad, gently sloped part ends in a
drawn outer bank/rim; a real drop has no supporting floor. Any steep uphill boundary
uses the same visible solid slope in car and walking queries. Exact slope/support
limits and outer profile samples are settled and documented with the shared ground
implementation. Never switch physical support off at an arbitrary point on an
otherwise visibly flat field.

### Boundaries for the next build

- Resolve supported terrain before it becomes visible or driveable. Its height,
  normal and owner must remain stable when another leg streams in. Today's distant
  `SplineHill` joins are recalculated when more road arrives, so they cannot simply
  become the per-wheel ground query. Keep distant scenery joining continuously
  outside the stable near-ground corridor.
- Store sufficient numeric biome/profile data in server sections for deterministic
  replay and late join; use an explicit compatible default for sections without it.
  Any schedule state in speculative turn fitting must be isolated from the live
  schedule. Share the face endpoint convention across profile, hill and mesh code.
- Give cars, walking, mesh and parts fallback one efficient supported-ground
  definition. Match traversable banks, solid faces and real drops, retain the
  current gravel lip/grass handling, and fit near-ground tessellation to that data.
- Keep road-leg ownership through off-road motion. Extending field lookup must not
  snap a car to another leg, earn progress by cutting across it or bypass the
  closing barrier. Widen that barrier's physical and drawn coverage with the finite
  supported corridor. Keep respawns on their accepted road leg.
- Retain crossing/escape safety, the fall line, recovery climbs and the eight-mesh
  budget. Near-ground fidelity takes priority over far scenery. The renderer must
  use a visible supported-ground fallback when EditableMesh is unavailable.

The user approved this direction with gradual-transition and semi-random-length
requirements. No runtime section, API, analytics or physics change is made in this
sketch step. The user drives the shared terrain blockout
before road/rail dressing and final tuning.

## Testing

- Deterministic schedule/profile tests: same seed and section history give the same biomes, terrain and joins; rejected turn previews do not consume state; late join and streamed replay match. Measure the three biome proportions and actual stretch lengths over several long seeds.
- Exercise all six directed transitions between the three biomes, both sides of the road, valley floors/passes, recovery climbs, hairpins and nearby parallel road legs. Adjacent chunk contexts must agree on shared height and normals without a new visible seam.
- Field and bank fixtures: wheel ground height/normal matches visible terrain; cross the road edge and transition at slow and high speed, stop on a bank, re-enter from grass and get out/walk/get back in. No invisible cliff or wall where the land is traversable, and no invisible floor over a real drop.
- Verify field extent/projection, off-road progress, closing barrier, falling and respawn. Leaving one road leg's field must not jump to another leg or advance the run illegitimately. Validate rail geometry and collision on actual exposed edges, including transitions and tight bends.
- Check the mesh-unavailable fallback, day/night readability, fixed triangle/mesh budgets and streamed build/frame cost on representative steep, gentle and field stretches. Existing road/turn, hillside, mesh, world, streaming, body/suspension and run checks still apply; record pre-existing failures separately.
- Source-gate the changed scripts, run quiet lane playtests, inspect the console and stop every playtest. Use numbers and debug profiles to prove behaviour; at most three visual screenshots per task. The user drives each biome and the joins in the feature lane before merge.

## Planned steps

1. **Sketch biomes and linked stretches** - route/cross-section sketch, distribution and transition plan; the user reviews shorter categories of the existing terrain and approves the layout.
2. **Build shared biome terrain** - deterministic section contract/schedule, efficient shared ground, continuous profiles and the lane blockout, with matching car/walking/fallback support.
3. **Shape roads and rails by biome** - safe changes to bend rhythm and hazard-based guardrails; dress the chosen profiles with existing scenery.
4. **Check and tune long biome runs** - every transition, replay, off-road behaviour, long-run distribution, streaming budgets and representative user drives.

The feature's own agent owns these sequential steps and reserves its lane after plan approval. The conductor handles the final merge request.

## Open questions

### Road and rail implementation checkpoint (T-210)

Regular bend weights, straight choices and bend-direction choices blend with the same
centred biome phase. Fields prefer sweeping bends; steep stretches prefer tighter
bends. Mandatory mountain planning, curvature/radius limits, grade/bank limits and
clearance checks remain in force. Final same-seed 150000-stud measurements show
regular field heading change114degrees/1000studs versus steep182, with tight-bend
distance5.2% versus19.9%. Existing-rail coverage of eligible exposed ground is4.3%
in fields versus35.3% in steep stretches; no sampled rail extends into broad fields
or non-cliff ground, and no mandatory gravel protection is missing.

Only the existing asphalt-edge guardrail is used. Discretionary runs are clipped to
actual fitted CLIFF spans within80studs of the asphalt, excluding groves; broad
fields receive no discretionary rail. Density is higher on steep exposed edges,
and the final roll uses the placed run's local biome phase. Mandatory tight gravel
protection stays covered at zero discretionary density. A separate fixed-draw RNG
keeps density changes from altering road geometry, other scenery or later seeds.

Hairpins and switchbacks keep one grade sign through their curved portions and
40-stud buffers. Paired bends retain that sign across the connecting gap. A clear
approach straight prepares the grade when needed; reversal happens in the truly
straight outgoing continuation. The mountain still changes sides at its fall-line
crossing, but the height band pauses until the whole maneuver and its straight
grade transition finish. Both floor and top reserve enough room to brake to a
stopped band, rather than assuming the earlier moving rate continues.

Policy and generated-car contact checks pass after latest Main integration. The
exact grade audit finds96 protected scopes with no reversals over five30k roads.
Limits, crossing, replay, periodic recovery (including150k), hillside and corridor
checks pass. Owner generation measurements reached19.556ms, but independent
Lane5 checks measured28.140ms and per-seed repeats21.159-42.896ms against the
unchanged20ms guard. Generation performance is therefore flagged for T-212
alongside rendering cost; the earlier owner pass does not clear it. The
bank-join regression is fixed by adaptively inserting hill rays
before face caps are interpolated. All six directed transitions, measured together
with neighboring chunks, have no missing ground and at most0.035stud height error
or4.14degrees normal error. The parts fallback is also measured from above every
local wedge, so protrusions cannot hide above a short ray origin.

Rendering performance remains flagged for T-212: the whole-road mesh test passes
15/17 checks, with mean158.38ms/worst219.96ms aggregate chunk work versus the
unchanged40ms guard, and a9.98ms worst slice versus9ms. This exceeds the older
T-206 accepted aggregate overrun; that approval does not waive these checks. A live
client run built7chunks with5resident meshes and no fallback, worst slice8.03ms;
this is an API-driven check, not a user drive. Distant-ground simplification,
colour, doubled reach, join cleanup and streaming costs remain in T-212 before
the feature is finished. All automated playtests are stopped before lane review.

T-213 isolates a constructed stopping-reserve gap found in review of T-210.
When a floor/pass clamps just after a section, its unchanged end grade can
still need a substantial braking ramp. The certificate now checks complete
immediate, early and late stopping paths through that clamp, using both bounds
from one path. Every ordinary-grade fallback and the last escape are checked.
The review fixtures reproduce the gap; no naturally generated failing seed was
identified. This correction contains no final-pass terrain changes.

### Follow-up terrain requirements (2026-11-14)

The user reviewed the blockout in four pictures (C-330666 forwarding C-e1ae58).
Fold these into steps 3/4 without reopening the approved T-209 checkpoint:

- Reduce tessellation with distance from the road; far terrain should be visibly low poly.
- Remove explicit far-ground colour blotches. Keep lighting-based face shading.
- Clean up the terrain joining the two legs of hairpins, including protruding wall lobes.
- Keep each hairpin inside a consistent uphill, downhill or flat run. Do not turn a descent into a climb at the hairpin; this supersedes the previous mid-turn grade reversal.
- Double the terrain reach on both sides. Cliffs need not grow taller; use coarse distant ground.
- Retain and verify the lighting-block correction alongside the revised terrain.

The user added a specific near-level switchback rule (C-bb5b19 forwarding
C-d8ba9f, 2026-11-14): flatten the land between nearby approach/exit legs when
their actual elevations are similar. Do not force opposing uphill/downhill
profiles to form a ridge there. Fit the shared ground to the real road/bank
edges and available space; blend into the ordinary mountain join as the height
difference grows. Car, walking, normal drawing and fallback must agree, and
crossing grass still earns no asphalt progress. The carved-apex feature remains.
Initial fitting thresholds are to be measured in Lane2; this is part of T-212.

T-215 follows the user's traverse drawing (C-6361cd forwarding C-666d71,
2026-11-14): longer runs across the slope, with cliffs, fields and tight/twisty
sections within each run, then an occasional actual turnaround. Measure completed
turnarounds per distance and actual traverse lengths, including mandatory leg
limits, optional double hairpins and phase-recovery turns. Changing a bend's
direction-alternation probability alone does not satisfy this requirement.
Keep the approved grade envelope, clearance, replay, bank safety and independent
biome schedule. Trial cadence is selected from measured accepted roads in Lane2.

The separate retired-runner progress correction T-211 is approved and merged with
the approved terrain. T-210 includes that Main integration; the remaining terrain
look, reach and streaming tuning is tracked in T-212.

- The steep category keeps the current uphill mountain/downhill drop; the user explicitly rejected a two-drop ridge. No terrain style redesign is authorised.
- The first two v1 side profiles are suitable. Exact safe field extent, small-cliff fitting and rail coverage are settled in the measured blockout. They are not permission to widen the tarmac or change grass handling.
- Category lengths must be seeded semi-random within bounds, and terrain transitions physically gradual. Initial mix, limits and transition-rate tuning are adjusted by the user's blockout drive.

### Shared terrain blockout (T-209)

The seeded schedule, fitted finite field/bank corridors and serialized signed bank heights now drive car, walking, mesh and parts-fallback ground. Supported extents stay frozen as neighbours stream in. Existing distant mountain joins remain; a low rock foot marks the uphill extent. The added outer field rails and their collision were removed after the user drive-through; only the existing road-edge guardrails remain. The normal mesh uses finer near-ground rows and grass strips while keeping one mesh per chunk. The fallback includes finite grass, bevels, faces and joined hills, built in bounded slices. Road rhythm and biome-specific rail density are still the next step.

Per-runner projection and recovery stay on the accepted road leg. Grass does not move the streaming window; returning to asphalt cannot convert a field shortcut into an unbounded progress jump. Lane verification includes actual emitted mesh triangles and fallback wedge rays, all six transitions, ownership beside a nearer road leg, and explicit placement resets.

Blockout measurements: all six directed transitions have matching emitted mesh ground (largest sampled height error0.043studs; normal difference2.32degrees), and fallback wedge rays differ by at most0.052studs in the sampled fixtures. Generation keeps its existing20ms budget on the checked runs. A forced full-window fallback initially exposed a102ms publication hitch; progressive192-part batches and sliced retirement replace that single large publication. Broader seed and performance tuning remains step4.

The corrected forced fallback measured5.1ms worst slices for a complete480-stud chunk; its cancellation, bounded retirement and immediate mesh-slot release checks pass. In the live client, three forced fallback chunks measured5.8ms worst slices. Walking at the former narrowing-bank failure now differs from drawn/shared ground by0.001stud. All agent playtests are stopped before handoff.

### Near-level connector integration in progress (T-212)

Frozen paired-bank fields now have one shared triangle floor and separate physical
contact/earned progress. Car, prediction, server credit and walking integrations
are checked in Lane2. Walking copies the parked car's history once, uses exact
nearby colliders and immediate local support, and cancels stale work on re-entry,
respawn or run stop. Actual avatar exit, walking, jump and both field endpoints
retain support without changing the parked car's debt. Retained drawing and
colliders clip the same frozen closure scalar.

Immediate walking support also verifies the current accepted field revision and
actual collider availability before reuse. A new disjoint patch inside an older
floor's radius receives new support without yielding; failed warm attempts never
certify that older coverage. Dense accepted geometry can reduce the immediate
radius within the existing triangle cap, with support rechecked each walking
frame while the full floor builds.

Generated connectors remain disabled. Ordinary scenery subtraction, exact end
stitching, a nearby complete-field view and atomic generation publication are
implemented. The live view uses the actual published road scenery and changes
its matching field seams in the same publication. Offline scheduling checks
cover cancellation, retirement and the global mesh limit; actual forced-fallback
publication timing still needs the final candidate checked in Studio.

The paired banks now share actual accepted road-cell and terrain-track stations.
Extra rows bound curved-bank sag without altering frozen global road footprints.
A finite curve/chord gap can provide grass support only where the outward bank
ray enters that opening's supported triangle and its retained closure scalar.
Natural generation, walking collider/render agreement and final timing remain
gates before enabling this. Historical blockout timings above do not establish
a pass for the final terrain: whole-mesh and generation timing flags from the
wider T-212 trials remain open.
