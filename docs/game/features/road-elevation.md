# Feature: Elevation, and the downhill road

**Status:** specced, waiting on the user's approval of the plan. **Owner task:** none yet
(`T-058`).

The endless road is **dead flat** and says so in its own config: *"`SurfaceY = 0`, world Y of the
road's top. FLAT, everywhere: no elevation in this build at all (no crest, no banking)"*
(`Config/Road.luau`). This feature gives it a third dimension and then uses it: a descending
mountain road, the shape the user asked for.

Their words: *"check out the touge map from drifto, there's track pieces there which would be
really good for our first downhill map. make some track pieces that have that downwards tilt and
profile just like that one."*

## First, the thing I could not do

**The touge map is not in what we hold.** The decompile in `..\scratch\reference\` is four folders
of C# — `camera`, `car`, `input`, `score` — and no level data, no road configuration and no piece
set. The road generator this game's road was ported from was read off that same decompile
(`track-generation.md`), which is why *how the road is built* could be copied exactly and *what the
map looks like* cannot be.

So the gradients, the piece lengths and the profile below are **ours**, chosen from what a real
mountain road is and what our car can drive, not read off theirs. **If the user has the map — a
screenshot, a video, the files — the numbers get replaced with measurements and this paragraph
goes away.** That is worth asking for before step 3 rather than after.

## Goal

A road that goes downhill. Not as a look: a descent you can feel in the car, where a long
right-hander falls away under you, where you arrive at a hairpin carrying speed you did not ask
for, and where the horizon is below you rather than at eye level.

## How it plays

You start at the top. The road falls away ahead — you can see three or four corners' worth of it
dropping, which is the view a flat road can never give you. Carrying speed into a descending
sweeper, the car wants to run wide; the hairpin at the bottom of a long straight arrives faster
than the same hairpin on the flat. Climbs appear too, short ones, and they bleed speed and settle
the car.

Fall off the side and you come back on the road where you left it, at the height the road is at
there — not at Y = 0, which is 400 studs above you by then.

## What this changes, in one picture

```
today                            after
----------------------------     ----------------------------
piece: start/finish sockets       piece: start/finish sockets
  (x, z, heading)                   (x, y, z, heading, PITCH)
join: rotate about yaw            join: rotate about yaw, then pitch
builder: box top at SurfaceY      builder: box top on a pitched plane
footprint: 2D quads               footprint: 2D quads   <-- UNCHANGED, on purpose
fall: y < RespawnBelowY (-150)    fall: more than FallBelowSurface under THIS piece
gravity: only when airborne       gravity: a slope term on the ground too  <-- a choice
```

**The footprint stays two-dimensional and that is deliberate.** Two stretches of road that cross in
plan view but miss each other by 80 studs of height would be a legal bridge, and the generator will
still refuse it as a collision. Refusing a legal road is cheap; building one piece through another
is not, and the lookahead that stops the road trapping itself was expensive to get right (`T-052`,
`track-generation.md` "The lookahead"). Three dimensions of collision is a later feature with a
measurement behind it, not a free extra.

## The four parts, and why they are four

### 1. The vertical profile

A socket grows a **`y`** and a **`pitch`**. A piece grows a **`rise`** — how far its finish socket
is above or below its start — and the join gains one rotation: match the new piece's start pitch to
the previous finish pitch, exactly as it already matches heading.

Every piece is still defined in its own frame with its start socket at the origin facing −Z, so the
road stays flush **by construction** and the gap between one piece's end socket and the next one's
start stays exactly zero — the property `track-generation.md` measures at 500 pieces. A pitched
join does not weaken it; it is the same construction with one more angle.

**Pitch is carried, not reset.** A piece that descends at 6% hands the next piece a start pitch of
−6%, and a piece whose own `rise` is zero continues at that pitch rather than levelling out. That
is what makes a descent a descent rather than a staircase of ramps.

**A limit on how fast pitch may change.** The car's ground rays find the surface with four downward
rays and the body follows the smoothed normal, so a kink between two pitches is felt as a bump and,
if it is sharp enough, as a launch. `MaxPitchStep` bounds how much pitch may change across one
join; anything steeper is cut into segments the way a curve already is (`MaxSegmentChord`).

### 2. The fall test stops being absolute

`RespawnBelowY = -150` is a world Y, and so is `FallY`, *"so both worlds' ground is still Y = 0 and
the one `FallY` / `RespawnBelowY` pair is right for both"* (`Config/Drift.luau`). A road that
descends at 6% over 200-stud pieces drops about 12 studs a piece, so **by about piece twelve every
car on it is "fallen"** and asks the server to respawn it, for ever.

The fix is small and local: on the road, the test becomes *more than `FallBelowSurface` studs below
the surface of the piece you are on*. `RoadService` already answers "which piece is this position
on" (`PieceAt`), and `Pieces.poseAt(piece, t, y)` already takes a height — the pieces of this were
built for other reasons and fit. The track and the playground keep the absolute test they have.

**This step is not optional and it is not cosmetic.** Nothing else in the feature works until it is
in, which is why it is its own step and goes first alongside the profile.

### 3. The piece set: a touge profile

New variants, each a descent, built on the flat set's radii and arcs so the corners are ones the
car is already known to be able to take:

| Variant | Shape | Grade |
|---|---|---|
| `DescentStraight` | The straight, falling | Steady, the set's working grade |
| `DescentSweeperL` / `R` | The sweeper, falling | Steady |
| `DescentCornerL` / `R` | The corner, falling | Steady |
| `DescentHairpinL` / `R` | The hairpin, falling **harder** | A hairpin on a mountain road is a switchback and drops more than the road either side of it. Gated at `minPieces` like the flat hairpin |
| `CrestL` / `R` / straight | A short climb | Not for variety's sake: a touge with no climbs is a ramp. They settle the car and bleed the speed the descents gave it |

**Which of these is "just like that one" is the open question** above. The grades below are a
starting point and the user's reference, if they have it, replaces them.

### 4. Does the hill pull the car?

**This is the real decision in this feature and it is the user's, because it changes the approved
drift model.**

Today the drift model applies gravity **only in the air**: *"Our own gravity, not Roblox's, and only
while the car is off the ground: on it, the height and the vertical speed both come from the
surface below"* (`Drift/Model`). The car follows the ground's height perfectly and is pushed along
its own nose by the drivetrain, and **nothing about a slope changes its speed.** So:

| | A downhill road |
|---|---|
| **Without a slope term** | Looks like a descent. Drives exactly like the flat road: same speeds, same corner entry, same everything. A view, not a hill |
| **With a slope term** | Gains speed going down and loses it going up, by `Gravity × sin(pitch) × SlopeFactor`, projected into the surface. A 6% grade is about 2.1 studs/s² — roughly 15% of the car's own acceleration — so a long descent genuinely runs away from you and a climb genuinely settles it |

The second is what a touge *is*. It is also the first change to the drift model since the user drove
it and approved the feel on 2026-11-03 (`DECISIONS.md`), so it goes **last**, on its own, behind the
rest, and it goes in with `SlopeFactor` as one number that can be set to 0 to get the first column
back. The flat road is unaffected either way: `sin(0)` is 0.

## Left out

- **Banking.** Corners stay flat across their width. It is the obvious next thing and it is a
  different change — a roll angle per segment rather than a pitch per socket — and mixing the two
  would make both harder to measure.
- **Three-dimensional collision,** and so bridges, tunnels and road over road (above).
- **An endless descent.** See "Open questions": a road that only ever falls has no floor, and that
  is a design question before it is a technical one.
- **A start-at-the-top, finish-at-the-bottom run.** That is what a run IS, still open
  (`endless-run.md`, `PITCH.md` is Draft).
- **Any art for a mountain:** no walls of rock, no trees, no drop into cloud. The road keeps its
  programmer-grey barriers and whatever surface `T-055` gives it.
- **The hand-built kart circuit in `DR-Main`**, which is the user's and is not touched
  (`PROJECT.md`).

## Rules and numbers

In `Config/Road.luau`, alongside the geometry it already holds. **Starting points, to be driven and
tuned, not measurements** — except where a number is forced by something already measured.

| Number | Start | Why |
|---|---|---|
| `WorkingGrade` | 0.07 (7%, 4.0°) | What a real mountain road runs at. Over a 200-stud piece that is 14 studs of drop |
| `HairpinGrade` | 0.12 (12%, 6.8°) | A switchback drops harder |
| `ClimbGrade` | 0.05 (5%) | Climbs are shorter and gentler than the descents |
| `MaxGrade` | 0.25 (14°) | A hard ceiling, far under the 46° at which `Drift/World` calls a surface a wall — the car would be stopped against it as if it were a building |
| `MaxPitchStep` | 0.02 per segment | How much grade may change in one segment, so no join is a jump |
| `FallBelowSurface` | 150 studs | The old `RespawnBelowY` distance, measured from the road instead of from zero |
| `SlopeFactor` | **0 until the user says otherwise**, then 1 | Part 4. Zero is today's behaviour exactly |
| `NetGradeBand` | −600..0 studs | How far below the start the road may wander before climbs are preferred over descents. See "Open questions" |

## UI

None.

## Server and client

Unchanged in shape. The road is built by the server and the client's ground rays find whatever is
there; a pitched surface is a surface. Two things to prove rather than assume:

- **The ground rays.** They are four downward rays at the wheels. On a 7% grade the front and rear
  rays differ by about 0.7 studs over the 9.6-stud wheelbase, which is what tilts the body. On the
  flat they agree. Nothing here is new code, but it is the first time it matters.
- **The pose the server puts a car in.** `SafeStart`, `JoinCFrame` and the respawn all go through
  `Pieces.poseAt`, which already takes a height. They must take the piece's height, not zero.

## Contracts

In `CONTRACTS.md`, in the same commit:

- The socket and piece shape: `y`, `pitch`, `rise`.
- `Config.Road`'s new numbers, and `Config.Drift.SlopeFactor` if part 4 is built.
- Any change to how a fall is decided, which `CarService` and `RoadService` both read.

## Analytics

None.

## Monetization

None.

## Platform risks

None new. No asset, art, sound, name or text comes from anywhere outside this repo.

## Art and sound

None this round. A mountain road that looks like a mountain road is scenery, and scenery is its own
feature with the user's art direction behind it (`ART-DIRECTION.md`).

## Testing

Everything below is a number, because every one of them is a thing that is silently wrong if nobody
looks:

| Check | Measured |
|---|---|
| The join still has no gap | Over 500 generated pieces on a mixed descending set, the worst distance between one piece's finish socket and the next one's start — **expected exactly zero**, as it is today |
| Pitch is carried | A descent, a flat piece, a descent: the flat piece's finish is lower than its start by its own grade, not level |
| No join is a step | The largest pitch change between two neighbouring segments across 500 pieces, against `MaxPitchStep` |
| Nothing is a wall | The steepest surface normal generated over 500 pieces, against the 46° at which `Drift/World` stops the car dead |
| The generator did not get worse | The stall rate over the same five seeds `track-generation.md` measures at 50 studs wide, before and after. The footprint is unchanged, so this should not move; if it moves, something is wrong |
| A fall on a descending road | Drive to piece 30 (about 400 studs down), fall off on purpose: the car comes back **on the road at that height**, still in the run, `furthestN` unmoved. On today's code this is the check that fails |
| The body follows the slope | The car's `up` and the surface normal on a 7% grade, and on the flat; the front/rear ray difference against the 0.7 studs the geometry predicts |
| The hill pulls (part 4 only) | Coast at zero throttle from 60 studs/s down a 200-stud 7% descent: speed at the bottom, against `Gravity × sin(pitch)` integrated. And the same up a climb |
| The flat road is unchanged (part 4) | With `SlopeFactor` at 0 and on a flat road, a pinned-seed autopilot drive reproduces `RunTests`' end-to-end numbers — 30 pieces, 40..117 studs/s, 71% drifting — **unchanged** |

`RoadTests.luau` grows the first six; the last two are drives.

## Open questions

- **The touge map.** Does the user have it — a screenshot, a video, the files? The profile numbers
  are ours until they do ("First, the thing I could not do").
- **Does the hill pull the car?** Part 4, and the one real decision here. It changes the approved
  drift model, so it is asked before it is built, not after.
- **Does the road descend for ever?** A touge descends; an endless road cannot descend for ever, or
  at piece 500 it is 7 000 studs below the start, far outside the world the other two live in. Three
  honest answers: *(a)* **a band** — descents and climbs, net downward, kept inside `NetGradeBand`,
  which is what this spec assumes; *(b)* **a true endless descent**, which needs the whole road
  periodically lifted back up under the car, a seam the player must not see; *(c)* **a run that
  starts at the top and ends at the bottom**, which is not an endless road at all but is the most
  touge answer of the three. This is downstream of what a run IS and is the user's.
- **Banking,** once pitch is in and proven.
