# Feature: Elevation, banking, and the downhill road

**Status:** approved by the user, and **all four steps are built**. Gravity acts along the ground
(`T-065`), a piece can carry a height and a bank (`T-066`), the fall test is measured from the
surface (`T-067`), the car's collision box follows the surface so `MaxGrade` and `MaxBank` could go
to 20° and 30° (`T-073`), and **the four touge pieces are in the shipped set** (`T-068`, below).
**Owner task:** `T-061` (plan), `T-065`, `T-066`, `T-067`, `T-073`, `T-068` (the pieces).

**What the user should drive, and the one number that is theirs:** the road descends on balance —
**−880 studs over 200 pieces**, 1.75% — in a band about 1 200 studs deep that climbs as well as
falls. That is answer *(a)* to "does the road descend for ever" below, and whether it is the right
answer is theirs. The other thing for them is the **banked 30**: it ships at **10°** of bank (the
user's call, 2026-11-06), and what stops it going further is **the engine**, not the geometry —
`MaxAcceleration` is 14.3 studs/s² against `Gravity × sin(bank)`, so the car cannot climb out of a
bank steeper than about 24°. A bigger bank needs a stronger engine, which is a feel number the user
owns.

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

### The faint bands across the road are geometry, and they cost segments or nothing (`T-066`)

The user saw thin lines running across the road wherever it has grade or bank, and asked how we
would fix it. **The honest answer is that there is nothing free to fix, and the builder is already
at the floor.** The measurement, seed 8080 × 20 pieces, 703 seams between slabs:

| Where | Worst | p90 | Median |
|---|---|---|---|
| Along the **centre line** | **0.0044 studs** | — | — |
| At either **kerb** | **0.2967 studs** | 0.1976 | 0.0804 |
| On a **barrier's** top, over its own 2 studs of width | **0.0183 studs** | — | — |

Two more seeds, same shape: 1234 reads 0.0028 / **0.2174**, and 20260704 reads 0.0214 / **0.4187**.

**It is a wedge, not a step.** Zero in the middle and growing with the distance out from it: two
neighbouring top faces cross *along the centre line*, and each is proud of the other on one half of
the road. That is why the bands in the user's screenshot fade out towards the middle, and why only
one half of each one catches the light — the other half's riser faces away from the camera.

**It is not a sagitta, so the obvious fix is not one.** A slab's top face already passes exactly
through *both* of its end nodes, so a secant box and a tangent box are the same box and along the
centre line the road is continuous to four decimal places. What a flat face cannot do is match the
road's **cross** direction at both of its ends at once: the surface of a graded curve is not
developable, and no flat quadrilateral lies in it. Each box ends up tilted across by the cross-slope
at its own middle, `sin(bank) + tan(grade) × sin(yaw − the seam's yaw) × cos(bank)`, and half the
road's width times the difference between two neighbours **is** the riser — predicted from the nodes
alone that is 0.2975 against the 0.2967 measured, and 1.2% out summed over all 703 seams.

**And the total is conserved, which is the whole answer.** Summed along a piece those differences
telescope into the piece's own turn times its grade, and that total does not depend on how the boxes
are oriented — only on how many of them there are. Driving every seam to zero with one roll per box
was tried and it works, at a price the road cannot pay: **5° to 19° of bank the road never asked
for**, leaving a piece 2° to 10° out at its join, which is a four-stud step in place of a
quarter-stud one. Spreading the total evenly over the seams — what the builder already does — is the
smallest the worst seam can be.

So the levers are, and none of them is free:

| | Cost |
|---|---|
| Cut profiled pieces more finely | **Linear.** ×2 segments halves the step and takes a window from ~1 130 parts to ~2 320; ×6 reaches 0.05 studs at ~7 100. `MaxProfileSegments` is 64 and a hairpin stack is already there |
| Keep grade off the **curves** — descend on straights and links | **Free in parts**, and it removes the defect entirely: the riser is zero on a level corner and zero on a graded straight. It costs the touge road its descending corners, which is the user's call |
| Leave it | Free. Worst 0.30 studs, median zero, and it does not touch the driving |

Three checks in `RoadTests` (`1h`) hold the floor: the centre line is continuous, the kerb step
matches the prediction from the nodes, and the barriers do not have the problem. `RoadTests:seams`
reports the numbers on any seed.

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

### What was built (`T-068`), and the numbers it was built on

Every number is in `Config/Road.luau` beside the piece it belongs to, with its measurement written
out. Nothing here is a flat piece with a grade added.

| | plan shape | height | bank | gate |
|---|---|---|---|---|
| `Link` | 140-stud straight | `EndGrade = 7°`, no drop: the grade blends **linearly** from whatever arrived, so the piece itself gains about 8 studs from level and *falls* when it arrives descending | none | `minPieces 0`, weight 3 |
| `Banked30` | 400 radius, 30° (209 studs) | `Drop = 14, EndGrade = 0` — arrives level, 5.7° at its steepest | `10°, crest` — in and out again, level at both sockets | `minPieces 3` |
| `HairpinStack` | 70 radius, 180° **each way** (440 studs, 280 across) | `Drop = 40, EndGrade = 0`, 7.8° at its steepest — which is the join between the two hairpins | none | `minPieces 14` |
| `Corkscrew` | 150 radius, 45° each way (236 studs, 88 across) | `Drop = 20, EndGrade = −5°` — **the only piece that hands on a descent** | none | `minPieces 10` |

**The road's height is a state machine and these four are its only inputs.** A piece with no
`Height` does not flatten the road, it *carries* the grade it arrived at, so all nine flat pieces
are followers. The corkscrew starts descents, the link ends them and starts climbs, the banked 30
and the hairpin stack end level. That is what makes a band rather than a ramp.

**Driven, the whole set, 50 generated pieces** (`RoadTests` section 11, seed 8080) — 50 of 50
reached, mean 49 studs/s, top **108**, 0 steps off the road, 0 airborne, longest stop **0.45 s**
(**re-measured after the bank went to 10° and `T-074` landed:** still 50 of 50 and still 0 off the
road and 0 airborne, mean 46, top 108, longest stop **1.35 s**; the per-piece rows below are from
the 5° run and have not been re-taken):

| on this piece | speed on it | drifting it | steps on a barrier |
|---|---|---|---|
| `Link` (4) | 39..103 | 52% | 7 |
| `Banked30` (6) | 0..91 | 52% | 21 |
| `HairpinStack` (3) | 2..68 | 70% | 10 |
| `Corkscrew` (7) | 20..99 | 72% | 13 |
| `Straight` (5) | 20..91 | 56% | 0 |
| `Sweeper` (6) | 12..108 | 67% | 8 |
| `Hairpin` (7) | 1..68 | 68% | 10 |

The flat nine on the same seed reach 50 at a mean of **56** and a top of 117, so the touge set is
about 13% slower, which is what a mountain road should be. **The top speed is 108, not 245:** the
fall-test number came from a long unbroken descent, and this set does not have one — the longest
run of pieces that keeps descending is 13, and the link catches it.

### The banked 30 ships at 10°, and what holds it there is the ENGINE

`MaxBank` is 30 and 30° is *geometrically* safe — `T-073`'s audit read the road as a wall 0 times
in 18 865 sweeps at that bank. It is still not drivable, but **the reason written here used to be
the wrong one** and sent readers after the wrong fix.

**It is not the collision box and it is not the car getting pinned.** `T-073` tilted the box onto
the surface, and `T-074` gave a pinned car the ability to drive itself off a wall — after which the
same 50-piece drive at 10° of bank reads **1.35 s** of stopped time where it used to read 40.2 s.
The pinning is fixed and the bank still cannot go up.

**It is that the car has not got the power to climb the bank.** Gravity acts along the surface, so
a bank pulls the car down the slope at `Gravity × sin(bank)` — 17.5 studs/s² at 30° — and the car's
whole drive is `MaxAcceleration = 14.3` studs/s² (`Cars/Archetypes`, the fallback archetype). The
ceiling is therefore

> `asin(MaxAcceleration / Gravity)` = `asin(14.3 / 35)` ≈ **24°**

and lower in practice, because the drivetrain falls off with speed (`1 − (u/TopSpeed)²`) so the full
14.3 is only ever on offer from a standstill. Measured on the same seed, 50 pieces, only
`Bank.Degrees` changing — **pieces completed out of 50**: 10° → **50**, 20° → 25, 25° → 8,
30° → 8. The cliff sits just below the 24° the arithmetic predicts, which is what makes the
explanation the right one.

**So a bigger bank needs a stronger engine, and that is a feel number the user owns** — nobody has
touched `MaxAcceleration`, and raising it changes how the car accelerates everywhere, not just on
this corner. The bank itself is one line in `Config/Road`; the thing in its way is not.

**It ships at 10°**, the user's call on 2026-11-06 (`DECISIONS.md`), against the `5°` the first
measurement had settled on.

### One bug in the piece maths, fixed

`Pieces.bankAt` blended a piece's whole bank profile from what it arrived at with a smoothstep,
which is right for a *constant* bank and wrong for any other: a crest is zero at both ends, so
multiplying it by a smoothstep that is 0.5 in the middle attenuated the whole crest. **A crest
asking for 30° reached 19.24°.** What is blended now is only the step between the arrival bank and
`own(0)`, so a piece's own profile is laid down as written and a constant bank and no bank at all
are algebraically unchanged. The `Horrible` fixture's measurements from `T-066` move with it.

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

`T-068` added six more, all passing (`RoadTests`, 49 checks):

| Check | Measured |
|---|---|
| **The flat nine are still the flat nine** | With the four gated out and the search budget held at the 2 000 it was pinned at, seed 1234 × 500 pieces and the first 20 built: all four fingerprints **identical** |
| Each of the four does what its spec says | Placed from a level socket and from a 5° descent: drop, exit grade, exit roll, peak bank and peak grade all read off the built piece |
| The road is a band, not a ramp | 5 seeds × 200: net −880 studs, lowest −950, highest **+244 above its own start**, longest unbroken descent 13 pieces |
| Nothing is a wall | Steepest surface the shipped set generates: **9.72°** on a hairpin stack, against a 35° lid and the 45.6° that reads as a wall. Driven, **0 of 351** sweeps that stopped the car were stopped by road |
| The bank holds the car | The same corner entered at 90 studs/s, banked and flat, side by side |
| A ray down finds road where the piece says it is | 1 353 rays at both edges and the centre line of a banked, pitched window: worst **0.0498 studs** off `Pieces.poseAt`. (This check used to compare against `SurfaceY`, which was a lie once the road climbed) |

The rest are drives, and belong to the gravity change and to the pieces that use the profile.

## Open questions

- **The touge map.** A screenshot or a video replaces the four shapes' numbers with measurements.
- **Does the road descend for ever?** It cannot: at piece 500 a steady descent is 7 000 studs below
  everything else. Three honest answers — *(a)* **a band**, descents and climbs, net downward, which
  this spec assumes; *(b)* **a true endless descent** with the whole road periodically lifted back
  up under the car, a seam the player must not see; *(c)* **a run that starts at the top and ends at
  the bottom**, which is the most touge answer of the three and is not an endless road at all. This
  is downstream of what a run IS (`endless-run.md`, `PITCH.md` is Draft) and is the user's.

  **The set as built is (a), and here is the number it is (a) by.** 5 seeds × 200 pieces, about
  50 500 studs of road each: net **−880 studs** on average (−4.4 a piece, a 1.75% average grade),
  ranging from −1 412 on one seed to −96 on another. The road's lowest point averages −950 and its
  **highest +244 above where it started** — every seed climbs above its own start — so the band is
  840 to 1 450 studs deep, and the longest unbroken descent is **13 pieces**. Per piece type over
  1 000 pieces: `HairpinStack` −3 879, `Corkscrew` −2 240, `Banked30` −1 610 against `Link` +1 009
  and the flat nine +2 320 between them (they carry whatever the link handed them).

  **It is one number to move.** The whole of it is the link's `EndGrade`: at 0° the net over 200
  pieces is **−2 190** studs and the road never once gets above its own start; at 4° −1 444; at 7°
  (shipped) −880; at 10° −309; at 12° **+78**, which is a road that climbs on balance. Pick a
  number and the road is that road.
- **Whether the drawn body lean should answer to the bank**, as well as to the drift. The reference
  gets this free from its springs; we draw it, so it is a decision.
- **Three-dimensional collision,** and the bridges and crossings it would allow.
