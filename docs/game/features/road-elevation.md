# Feature: Elevation, banking, and the downhill road

**Status:** specced, revised once by the user, waiting on their approval of the plan.
**Owner task:** none yet (`T-061`).

The endless road is **dead flat** and says so in its own config: *"`SurfaceY = 0`, world Y of the
road's top. FLAT, everywhere: no elevation in this build at all (no crest, no banking)"*
(`Config/Road.luau`). This feature gives the road height and bank, and then builds a mountain road
out of them.

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

A socket is `{ x, z, yaw }` today. It becomes `{ x, y, z, yaw, pitch, roll }`, and the join —
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
| `MaxGrade` | 0.25 (14°) | A hard ceiling, well under the 46° at which `Drift/World` calls a surface a wall and stops the car dead against it |
| `MaxBank` | 30° | The banked-30's showcase angle. Also under the wall threshold, which matters because a bank is a surface normal too |
| `MaxPitchStep`, `MaxBankStep` | 0.02, 1.5°/segment | How much either may change in one segment, so no join is a step and no bank is a kink |
| `FallBelowSurface` | 150 studs | The old `RespawnBelowY` distance, measured from the road instead of from zero |
| Per piece | — | Each of the four shapes carries its own height and bank profile; they are the piece's, not global |

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

| Check | Measured |
|---|---|
| **The flat road is untouched** | `GravityOnGround` at 1, on flat ground: `g_along` is **exactly zero** every step, and a pinned-seed autopilot drive reproduces `RunTests`' end-to-end numbers unchanged. This is the check that protects the approved feel |
| The hill pulls | Coast at zero throttle from 60 studs/s down a 200-stud 7% descent, and up the same climb. Speed at each end against `g·sin(pitch)` integrated |
| **A drift downhill scrubs less** | The user's own words, as a number: the same slide, same entry speed, same angle, on the flat and on a descent — speed lost over the slide, both times |
| The bank holds you | A steady drift round the banked 30 at a fixed finger, with the bank and with it flattened: lateral distance travelled before the car runs wide |
| Nothing is a wall | The steepest surface normal over 500 generated pieces, against the 46° threshold. Bank and grade together, not separately — they compound |
| The join still has no gap | Worst finish-to-start socket distance over 500 pieces: **expected exactly zero**, as today |
| No join is a step | Largest pitch and roll change between neighbouring segments, against their limits |
| The generator did not get worse | Stall rate over the same five seeds `track-generation.md` measures, before and after. The footprint is unchanged, so this should not move |
| A fall on a descending road | Drive to piece 30, around 400 studs down, fall off on purpose: back **on the road at that height**, still in the run. On today's code this is the check that fails |
| The body follows the surface | The car's `up` against the surface normal on a 7% grade and a 30° bank, and the per-wheel ray differences against what the geometry predicts |

The first three are drives. The rest grow `RoadTests`.

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
