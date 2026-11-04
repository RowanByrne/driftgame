# Feature: Elevation, banking, and the downhill road

**Status:** approved by the user. Step 2 of 4 is **built** (`T-066`): a road piece can carry a
height and a bank. The gravity change is `T-065`, the fall test and the four touge pieces are
still to come. `T-073` lifted the limit that `T-066` ran into — the car's collision box now follows
the surface — so the config's `MaxGrade` and `MaxBank` can be raised to 20° and 30°.
**Owner task:** `T-061` (plan), `T-065` (gravity on the ground), `T-066` (the piece profile),
`T-073` (the tilted sweep box).

## What is built, and what the limits turned out to be

`T-066` gave `Road/Pieces` and `Road/Builder` the third dimension. **The nine flat pieces are
byte-for-byte the road they were** -- same sequence, same parts, same places, pinned as
fingerprints in `RoadTests` so it stays that way -- and nothing in the shipped set uses any of it
yet.

| What | Where | Measured |
|---|---|---|
| A socket is `{ x, y, z, yaw, pitch, roll }` | `Road/Pieces` | 200 generated pieces with profiles in them, over 3 258 studs of height: worst finish-to-start gap **exactly 0** in position and in all three angles, as on the flat |
| Pitch persists, bank unwinds, neither steps | `applyProfile` | worst grade change between neighbouring boxes **1.150°** against the 1.15 limit, worst bank change **1.500°** against 1.5 -- across every join as well as inside pieces |
| Nothing reads as a wall | `MaxSurfaceTilt` | the steepest surface the limits allow leans **30.95°**, normal Y 0.858, against the 45.6° (0.70) at which `Drift/World` calls it a wall. Driven: **0 of 7** sweeps that stopped the car were stopped by road |
| `poseAt` answers with the piece's height and bank | `Road/Pieces` | 152 wheel rays over a banked descent and a banked corner: every wheel within **0.11 studs** of ride height along the surface normal, the pose's up within **0.45°** of the four rays' mean |
| The generator is untouched | -- | 5 seeds x 500 pieces: 0 stalls, worst call 2.21 ms (2.15 before). 20 runs of 400: 0 boxed in, 20 of 8 000 on short proof -- identical to before |
| The flat road is unchanged | `PINNED` in `RoadTests` | sequence, geometry, part count and every part's CFrame identical over 500 pieces and 1 448 parts |

### The limit WAS the car's own collision box — and it has been lifted (`T-073`)

The spec chose 14° of grade and 30° of bank against the 46° wall threshold. **That was never the
binding limit.** The car's collision box was swept flat through the world and was **never pitched
and never rolled**, so it rode with 1.44 studs of air under it, 7 studs of nose in front and 3.2
studs of width either side. Above `atan(1.44/7) = 11.6°` of grade its nose was inside the hill it
was climbing; above `atan(1.44/3.2) = 24°` of bank its uphill side was inside the road it was
leaning on. The road is abutting slabs, so what the buried nose met was the **end face of the next
slab** — near-vertical, which the sweep calls a **wall** — and the car stopped dead against its own
road. That is where `MaxGrade = 8` and `MaxBank = 20` came from.

**`T-073` tilts the box on to the surface under it** — `Drift/World` reads the ground ray's own
normal and poses the box the way `Drift/Model`'s `basis` poses the car — and **both limits move at
once.** `World.DebugTilt = false` gives the flat box back exactly, which is how every row below was
measured twice.

**The sweep, asked exhaustively.** The real road, generated at each limit, with the car stood at
ride height at 25 places on every slab × 5 headings — about 16 000 sweeps a row — and every sweep
that read a wall traced to the part that it read:

| the road's grade | flat box | **tilted box** | | the road's bank | flat box | **tilted box** |
|---|---|---|---|---|---|---|
| 8° | 0 of 15 820 | **0** | | 20° | 267 of 17 815 | **0** |
| 12° | 1 316 | **0** | | 25° | 2 216 of 18 340 | **0** |
| 16° | 1 287 | **0** | | 30° | 2 431 of 18 865 | **0** |
| 20° | 898 | **0** | | 35° | 2 429 of 19 390 | 10 |
| 25° | 896 | **0** | | 40° | 2 750 of 19 915 | 38 |
| 30° | 871 | **0** | | | | |
| 35° | 48 | **0** | | | | |

So the road stops reading as a wall **everywhere `MaxSurfaceTilt` allows**, on both axes: zero of
~16 000 at every grade to 35°, and zero at every bank to 30° with 35° only marginal.

**Driven, the same two brackets.** A straight ramp at each grade, 90 studs/s in, no steering:

| grade | before (flat box) | **after (tilted box)** |
|---|---|---|
| 8° | climbs freely | climbs freely, leaves at 138 studs/s |
| 10° | 1 wall, ends at 10 studs/s | climbs freely, 130 |
| **12°** | **stopped dead, 24 studs climbed** | climbs freely, 123 |
| 14° | **stopped dead**, 267 wall steps | climbs freely, 115 |
| 20° | **stopped dead** | climbs freely, 93 |
| 24° | — | climbs freely, 74 |
| **25°** | — | **stops — and not on a wall: 1 touching step against the audit's zero. It is gravity against the drivetrain** |

And a 12-piece road of banked 90° corners, two seeds, the test autopilot driving:

| bank | before | **after** |
|---|---|---|
| 20° | 5/12 and 4/12 pieces, stopped for 96 s and 110 s | **12/12 and 12/12, 0 road walls, 0.00 s stopped** |
| 25° | 3/12 and 4/12, stopped for 110 s and 101 s | **10/12 and 12/12, 0 road walls, 0.00 s** |
| 30° | 3/12 and 3/12, stopped for 112 s and 94 s | **12/12 and 9/12, 0.63 s and 0.46 s slow** |
| 35° | 3/12 and 3/12, stopped for 112 s each | 2/12 and 4/12 — the bank costs plan width and the driver runs out of road |

(The 30° row's two "road wall" attributions come from `RoadTests:drive`'s tracer, which rebuilds a
**flat** box to name the part it hit; with a tilted sweep that over-reports road. The exhaustive
audit, which uses the box the sweep actually used, says zero.)

### What the limits should be now

| number | was | **measured safe** | what binds it now |
|---|---|---|---|
| `MaxGrade` | 8° | **20°** | Not the sweep: that is clean to 35°. **The car's power.** It climbs 24° and cannot climb 25°, so 20 leaves the same four degrees of margin 8 had against 10 |
| `MaxBank` | 20° | **30°** | The sweep, still: 0 of 18 865 at 30°, 10 of 19 390 at 35°. **This is the "30-degree turn with big banking" the spec asked for** |
| `MaxSurfaceTilt` | 35° | **35°, unchanged** | It is the backstop and it is now the thing actually holding the line. 20° of grade and 30° of bank come to 35.5° together, so the lid trims the bank to 29.4° where both are at maximum — which is the lid doing its job |

**20° of grade is a ceiling, not a target, and the `T-066` warning still stands.** A road of nothing
but descending corners: flat reaches 12 of 12 pieces at a mean of 59 studs/s, 4° reaches 12 at a
mean of 68, and 8° reaches 10 at a mean of 36 while touching **120 studs/s against the flat road's
92**. That was never the road failing — the sweep was stopped by road zero times at both grades — it
is the car carrying more speed downhill than a driver aimed on the flat can steer for. **Build a
touge out of 4° descents and level links before reaching for anything bigger.**

**Nothing about the flat world moved.** On level ground the tilted frame IS the flat one and both
queries take the exact expression they always had: 26 of `CollisionTests`' 39 original checks are
byte-identical, every other suite passes unchanged, and a pinned-seed drive down the flat road
reproduces its numbers to the character. The 13 that moved are all on the playground's banked bowl
and its ramp taken at an angle — including the two that **failed** on `main` ("the ramp taken ±15
degrees off square keeps the car out of itself": the car ended 0.182 studs inside the ramp's lip for
3 steps, and now ends inside nothing).

`CollisionTests` grew from 39 checks to 50: five grades and three banks audited exhaustively, and
three drives up a ramp. Eight of the eleven fail with `World.DebugTilt = false`, which is what makes
them a test of this and not of nothing. The whole suite costs 2.3 s.

**The price is two raycasts a step** — one in `sweep`, one in `penetration`, to read the surface the
box is tilted on to. Measured on the road at 120 steps/s: **0.0309 ms a step becomes 0.0436**, which
is 0.025 ms a frame at 60 fps.

### Two things changed shape from the plan

- **A piece's height is the integral of its clamped, rate-limited grade,** not a curve sampled
  directly, which is what makes `MaxGrade`, `MaxPitchStep` and `MaxBankStep` true by construction
  rather than by hope. A profile that asks to fall off a cliff gets a ramp.
- **A barrier follows the grade but not the bank.** Leaning a six-stud wall with a 30° bank
  overhangs the road by three studs, and what that overhang would catch is the car's roof while its
  wheels still have room. **Still right after `T-073`,** and the barrier is still solid with the
  tilted box: 120 rams at 179 studs/s into barriers on a flat, a 20°-banked and a 30°-banked road —
  none went through, worst gap 7.05 studs, and where the flat box let the body touch a barrier for 3
  steps on a bank the tilted one never did.

## Why (the spec as the user approved it)

The endless road **was dead flat** and said so in its own config: *"`SurfaceY = 0`, world Y of the
road's top. FLAT, everywhere: no elevation in this build at all (no crest, no banking)"*
(`Config/Road.luau`, before `T-066`). This feature gives the road height and bank, and then builds
a mountain road out of them.

The user asked for it, and then corrected the first version of this spec. Both halves matter:

> *"check out the touge map from drifto, there's track pieces there which would be really good for
> our first downhill map. make some track pieces that have that downwards tilt and profile just
> like that one."*

> *"ok so we don't just want to take what we have and tilt it. what we have now are good pieces for
> flat driving, but what the touge map does is it has road pieces which start at one height and
> finish at another. there are flat sections between sections with 30 degree turns that have big
> banking, or back to back steep hairpins, or even a flat entry to a sharp downhill chicane not
> unlike the corkscrew at laguna seca... whatever gravity system we add should affect how the tires
> grip the road when you are on an angle... when i slide over a crest and into a downhill drift, im
> sliding faster and not slowing down as much as i would if it was flat. that's what we want to
> replicate."*

## The thing I could not do, and the thing I had not done

**The touge map is not in what we hold.** The decompile in `..\scratch\reference\` is four folders
of C# — `camera`, `car`, `input`, `score` — with no level data, no road configuration and no piece
set. The road generator this game's road was ported from was read off that same decompile
(`track-generation.md`), which is why *how the road is built* could be copied exactly and *what the
map looks like* cannot be. The shapes below are built from the four the user described, not
measured off theirs. **A screenshot or a video of that map replaces them with measurements.**

**The gravity code, though, is in the decompile, and the first version of this spec had not read
it.** It does, now, and the answer it gives is better than the one that spec invented. See below.

## Goal

A mountain road: pieces that start at one height and finish at another, banked where a mountain
road is banked, and a car whose speed and grip answer to the slope it is on. Slide over a crest
into a descent and you carry speed you would not have carried on the flat.

## How the reference does gravity, and why our port diverged

Three of its components, read together, are the whole of it.

### It never turns gravity off

```
CustomGravity.FixedUpdate:   rigidbody.velocity -= Vector3.up * 9.8 * dt
```

Every step, grounded or not, no condition. The car is a Rigidbody and **four suspension springs
hold it up**: `CarSuspension` raycasts down from each wheel and pushes along the **car's own up
axis** with a strength that grows as the spring compresses.

A spring pushes along the normal. Gravity pulls straight down. **On a slope those are not the same
direction, and the difference is never cancelled** — so the car accelerates down the hill, with no
code anywhere that mentions slopes. That is the mechanism the user is describing, and it is
emergent, not scripted.

### Grip acts in the surface's plane, along the car's tilted axis

```
CarFriction._ApplyFriction:
  magnitude = min(Constant + Linear*b + Square*b², Max) * surfaceGrip * FrictionMultiplier * dt
  direction = (|b| > 90°) ? -flow.normalized : (transform.right * sign(b))
  velocity += clamp(magnitude * direction, per axis, to the velocity)
```

`transform.right` is the **car's** right, and the car's attitude is set by the four springs — so on
a banked corner the car leans with the bank and the grip force leans with it. Banking therefore
helps you, and it helps you through the same quadratic grip law we already ported, with no special
case for banks.

### The body's attitude is not animated, it is the springs

Nothing in the reference writes a roll or pitch angle. `_ApplySteering` sets
`angularVelocity.y` — **world** vertical, even on a bank — and the four springs do the rest. The
car leans into a bank because the springs on the low side are compressed harder.

### Where our port diverged, and it is one line

Ours is kinematic — no Rigidbody, no springs, four downward rays and the surface's height written
straight in. So the suspension had nothing to port, and gravity was made conditional instead:

> *"Our own gravity, not Roblox's, and only while the car is off the ground: on it, the height and
> the vertical speed both come from the surface below."* — `Drift/Model`

On a flat road that is exactly right and indistinguishable. On a slope it is **the one thing
standing between us and what the user is asking for.**

## The fix, and why it is small

**Apply gravity every step, and let the surface take back only the part that points into it.**

```
g_along = gravity − n * (gravity · n)        -- n is the smoothed surface normal the model already keeps
velocity += g_along * dt                     -- while grounded; airborne is unchanged
```

That is the suspension's job done in one line, because a kinematic car does not need the spring —
it needs the spring's *result*, which is that the into-the-surface component goes away and the
along-the-surface component does not.

| Surface | `g_along` | What the player feels |
|---|---|---|
| Flat | **exactly zero** | Nothing. Today's approved feel, unchanged, and that is a test, not a hope |
| 7% descent | ~2.5 studs/s² | A long descent runs away from you, and a drift down it scrubs less speed than the same drift on the flat |
| 7% climb | ~2.5 studs/s² against | A climb settles the car |
| A bank | across the corner | Pulls you down the banking. The grip, which already acts in the surface plane along the car's tilted right axis, is what holds you on it — which is *"how the tyres grip the road when you are on an angle"* |

**It is still the first change to the drift model since the user approved the feel**
(`DECISIONS.md`, 2026-11-03), so it goes first, alone, with `GravityOnGround` as one switch that
turns it off and gives today back exactly.

**And it can be proved before a single piece of road is built,** because the playground already has
a banked circle and a ramp (`Playground/Build.luau`: `heightProfile`, `bankProfile`, `frame`,
`ribbon`). Drive those with it on and off and the difference is the whole feature.

## The pieces: designed, not tilted

The user's correction, in full. **We are not taking the flat set and tilting it.** The flat set is
nine good pieces for flat driving. A touge is made of pieces that each *go somewhere* vertically,
and whose shape and bank are chosen together. Four shapes, from their description:

| Shape | What it is | Why it is in the set |
|---|---|---|
| **The link** | Flat, or nearly. Short | *"there are flat sections between sections"*. The breather between two hard things, and what stops a descent being one long ramp |
| **The banked 30** | A ~30° direction change with **big banking** through it, losing height | The corner you can carry real speed through because the bank is holding you. The showcase piece |
| **The hairpin stack** | Two steep hairpins **back to back**, opposite hands, dropping hard | How a mountain road actually loses height. The slowest, most technical thing in the set |
| **The corkscrew** | **Flat entry, then the road drops away** through a chicane | Laguna Seca's Corkscrew: you commit on the flat and the floor leaves. The piece people will remember |

Each carries its own height and bank profile down its length, not one constant grade. **A piece's
exit height, pitch and bank are what the next piece has to start from**, which is what makes them
join into a road rather than a staircase.

## How it works

### A socket gains two angles

**Built (`T-066`).** A socket was `{ x, z, yaw }`. It is now `{ x, y, z, yaw, pitch, roll }` — the
three new fields optional and read as zero, which is what the generator's own first socket is — and
the join —
*rotate the new piece about its own start socket until that socket matches the previous finish, then
translate* — matches all three angles instead of one. Every piece is still defined in its own frame
with its start socket at the origin, so the road stays flush **by construction** and the measured
gap between one piece's finish socket and the next one's start stays exactly zero.

**Pitch and roll are carried, not reset.** A piece that arrives descending keeps descending unless
its own profile says otherwise.

### The builder already knows how to do this, in the other world

`Playground/Build.luau` lays banked, height-profiled ribbons today — `heightProfile`, `bankProfile`,
`levelInnerEdge`, `frame(node, y, bank)`, `ribbon(nodes, opts)` — and that is how the playground's
banked circle and its ramp are built. The road builder is flat because the road was specced flat,
not because the problem is unsolved here. **The shape of the answer is in the repo already,** and
the honest version of this step is to follow it rather than invent a second one.

### The footprint stays two-dimensional, on purpose

Two stretches of road that cross in plan view but miss each other by 80 studs of height would be a
legal bridge, and the generator will still refuse it as a collision. Refusing a legal road is cheap;
building one piece through another is not, and the lookahead that stops the road trapping itself was
expensive to get right (`T-052`). Three-dimensional collision is a later feature with a measurement
behind it.

### The fall test stops being absolute

`RespawnBelowY = -150` is a world Y, *"so both worlds' ground is still Y = 0 and the one `FallY` /
`RespawnBelowY` pair is right for both"* (`Config/Drift.luau`). A road that descends drops about 14
studs a piece, so **by about piece eleven every car on it is "fallen"** and asks to be respawned,
for ever.

On the road the test becomes *more than `FallBelowSurface` studs below the surface of the piece you
are on*. `RoadService` already answers "which piece is this position on", and `Pieces.poseAt` already
takes a height. The track and the playground keep the absolute test.

## Left out

- **Bridges, tunnels, road over road** (the 2D footprint, above).
- **An endless descent that never comes back up.** See "Open questions".
- **Mountain scenery:** no rock walls, no trees, no drop into cloud. The road keeps its
  programmer-grey barriers and the asphalt and centre line from `T-055`.
- **A suspension model.** We are not giving the kinematic car four springs. The body's lean on a
  bank is drawn, as its drift lean already is (`Drift/Render`), not simulated.
- **The hand-built kart circuit in `DR-Main`**, which is the user's and is not touched.

## Rules and numbers

In `Config/Drift.luau` (the gravity switch) and `Config/Road.luau` (everything else). **Starting
points to be driven and tuned**, except where a number is forced by something already measured.

| Number | Start | Why |
|---|---|---|
| `GravityOnGround` | 1 | Share of gravity that acts along the surface while grounded. **0 is exactly today's behaviour** |
| `MaxGrade` | ~~0.25 (14°)~~ ~~8°~~ **20°** | `T-066` cut it to 8 for the car's unpitched collision box; `T-073` tilted the box and the sweep is clean to 35°, so what binds it now is **the car's power**: it climbs 24° and cannot climb 25°. **Still in the config at 8 — the conductor raises it** |
| `MaxBank` | ~~30°~~ ~~20°~~ **30°** | The same box, and the same fix: 0 of 18 865 sweeps read the road as a wall at 30°. That is the spec's showcase piece back. **Still in the config at 20 — the conductor raises it** |
| `MaxSurfaceTilt` | 35° | **Added by `T-066`.** Grade and bank compound -- the normal's Y is cos(grade) x cos(bank) -- so it is the pair that is capped, never one at a time |
| `MaxPitchStep`, `MaxBankStep` | 1.15°, 1.5°/segment | How much either may change in one segment, so no join is a step and no bank is a kink. The spec's 0.02 of grade is 1.15° |
| `MaxProfileSegments` | 64 | **Added by `T-066`.** The ceiling on what those two may cut a piece into, so a careless profile costs a few parts rather than hundreds |
| `FallBelowSurface` | 150 studs | The old `RespawnBelowY` distance, measured from the road instead of from zero. **Not built yet:** it is `CarService`/`RoadService`, not the piece |
| Per piece | `Height`, `Bank` | Each piece carries its own; `Height = { Drop, EndGrade }` and `Bank = { Degrees, Shape }`, both optional, documented in `Config/Road` |

## UI

None.

## Server and client

Unchanged in shape: the server builds the road, the client's rays find whatever is there. Three
things to prove rather than assume:

- **The ground rays on a slope.** Four downward rays at the wheels. On a 7% grade the front and rear
  differ by about 0.7 studs over the 9.6-stud wheelbase, which is what tilts the body; on a 30° bank
  the left and right differ by about 3.2 studs over the 5.6-stud track width. None of that is new
  code, but it is the first time it carries weight.
- **The wall threshold.** `Drift/World` calls anything steeper than about 46° a wall. A 30° bank is
  a long way inside that and must stay there — a bank that reads as a wall stops the car dead.
  **Done and measured (`T-073`):** what was actually reading as a wall was not the surface but the
  end face of the next slab, which the flat sweep box's buried nose met. Tilt the box and it is zero
  of ~16 000 sweeps at every grade to 35° and every bank to 30°.
- **Where a car is put down.** `SafeStart`, `JoinCFrame` and the respawn all go through
  `Pieces.poseAt`, which takes a height. They must take the piece's, not zero — and on a banked
  piece, its bank too.

## Contracts

In `CONTRACTS.md`, in the same commit: the socket and piece shape (`y`, `pitch`, `roll`, the height
and bank profiles), `Config.Drift.GravityOnGround`, the new `Config.Road` numbers, and the change to
how a fall is decided, which `CarService` and `RoadService` both read.

## Analytics

None.

## Monetization

None.

## Platform risks

None new. No asset, art, sound, name or text from outside this repo.

## Art and sound

None this round.

## Testing

The six marked **done** are in `RoadTests` and pass; their numbers are in "What is built" above.

| Check | Measured |
|---|---|
| **The flat road is untouched** (done) | Three pinned fingerprints: the sequence a seed lays, every node and quad of the first 20 pieces, and every Part of those 20. Identical |
| The join still has no gap (done) | 200 profiled pieces: exactly zero, in position and all three angles |
| No join is a step (done) | 1.150° of 1.15 and 1.500° of 1.5, between neighbouring boxes, across joins included |
| Nothing is a wall (done) | 30.95° of the 45.6° threshold; driven, 0 of 7 sweeps stopped by road |
| **The road never reads as a wall, at any grade or bank** (done, `T-073`) | In `CollisionTests`: five grades to 35° and three banks to 30°, the car stood at 25 places on every slab × 5 headings, **0 of 9 375 and 0 of 13 125 sweeps**. On the generated road, the same audit: 0 of ~16 000 a row. Eight of those eleven checks fail with `World.DebugTilt = false` |
| The generator did not get worse (done) | 0 stalls over 5 x 500, worst call 2.21 ms against 2.15 before; 20 x 400 identical |
| Where a car is put down (done) | every wheel within 0.11 studs of ride height, the pose's up within 0.45° of the rays' mean |
| **The flat road is untouched** | `GravityOnGround` at 1, on flat ground: `g_along` is **exactly zero** every step, and a pinned-seed autopilot drive reproduces `RunTests`' end-to-end numbers unchanged. This is the check that protects the approved feel |
| The hill pulls | Coast at zero throttle from 60 studs/s down a 200-stud 7% descent, and up the same climb. Speed at each end against `g·sin(pitch)` integrated |
| **A drift downhill scrubs less** | The user's own words, as a number: the same slide, same entry speed, same angle, on the flat and on a descent — speed lost over the slide, both times |
| The bank holds you | A steady drift round the banked 30 at a fixed finger, with the bank and with it flattened: lateral distance travelled before the car runs wide |
| A fall on a descending road | Drive to piece 30, around 400 studs down, fall off on purpose: back **on the road at that height**, still in the run. On today's code this is the check that fails |
| The body follows the surface | The car's `up` against the surface normal on a 7% grade and a 30° bank, and the per-wheel ray differences against what the geometry predicts |

The rest are drives, and belong to the gravity change and to the pieces that use the profile.

## Open questions

- **The touge map.** A screenshot or a video replaces the four shapes' numbers with measurements.
- **Does the road descend for ever?** It cannot: at piece 500 a steady descent is 7 000 studs below
  everything else. Three honest answers — *(a)* **a band**, descents and climbs, net downward, which
  this spec assumes; *(b)* **a true endless descent** with the whole road periodically lifted back
  up under the car, a seam the player must not see; *(c)* **a run that starts at the top and ends at
  the bottom**, which is the most touge answer of the three and is not an endless road at all. This
  is downstream of what a run IS (`endless-run.md`, `PITCH.md` is Draft) and is the user's.
- **Whether the drawn body lean should answer to the bank**, as well as to the drift. The reference
  gets this free from its springs; we draw it, so it is a decision.
- **Three-dimensional collision,** and the bridges and crossings it would allow.
