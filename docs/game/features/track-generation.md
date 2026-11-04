# Feature: Road pieces and the endless road

**Status:** **steps 1 and 2 built** (`T-049`, `T-050`): the generator on five flat piece types,
every number measured. Step 3 (the start button, spawning, falling, getting back to the other
worlds) is `T-051` and is not built here. **The set is now nine types in sixteen variants** — the
five flat ones here plus the four touge pieces that carry a height and a bank
(`road-elevation.md`, `T-068`). **Owner task:** `T-044` is the plan; specced as `T-030`.

Written from the reference game's own road generator, read off the decompile, the same way
`drift-model.md` was. What we take is how the system works; none of its source, art or names come
near this game (`PLATFORM-RISKS.md`).

## The name is Road, not Track

`Services/TrackService.luau` already means something else: it adopts the **hand-placed kart
circuit** that lives only in `DR-Main` and that git never sees. The endless road is a separate,
third world and must not collide with it, so everything here is `Road`:

| | |
|---|---|
| `src/ReplicatedStorage/Shared/Config/Road.luau` | Every number |
| `src/ReplicatedStorage/Shared/Road/Pieces.luau` | What a piece is, and the join, as pure maths |
| `src/ReplicatedStorage/Shared/Road/Generator.luau` | The sequence: the bias, the lookahead, the window, progress |
| `src/ReplicatedStorage/Shared/Road/Builder.luau` | A placed piece turned into parts |
| `src/ServerScriptService/Services/RoadService.luau` | The service that owns the parts and follows the car |
| `src/ServerScriptService/Tests/RoadTests.luau` | 29 checks, and the two measurement harnesses |

## Goal

A road that goes on for ever, is different every run, and is **made of corners worth drifting**. The
player should never see the same stretch twice in a run, never meet a corner the car cannot take,
and never fall off the end of the world.

## What this spec does NOT decide

This is the road, and only the road. Three things it needs as inputs are still the user's and are
deliberately left open (`PITCH.md` is still Draft):

- **What a run is.** Endless until you crash? A set distance? A time limit? The generator is the
  same either way; what ends a run is not in here.
- **Scoring.** Specced in `drift-model.md` "Score" and deliberately not built (`DECISIONS.md`,
  2026-11-03). The road only has to tell a scorer "this is new road, and you are going forward on
  it" — which it does, see "Progress".
- **Crashing.** The reference ends a run on a hard hit or on the car landing upside down. Walls are
  solid here (`T-018`) and nothing ends a run yet.

## How it plays

The player drives forward and the road keeps arriving: a corner, a straight, a sweeper, a chicane,
in an order they have not seen before. Behind them it quietly disappears. There is no visible seam
and no loading pause. They cannot drive backwards past a certain point — the way they came is
closed off — and they cannot drive onto road they have already used, because the generator will not
build a piece that would cross it.

## How it works

### A piece

A piece is one length of road with **two sockets**: a **start** and an **end**, each a position and
a heading. That is all the geometry the joining needs.

| It carries | What for | Built? |
|---|---|---|
| `start`, `finish` | The sockets. A piece's end is the next piece's start | Yes |
| `quads` | The footprint: a flat list of oriented rectangles, one per segment, covering the road and both barriers, plus a bounding box for a quick reject. **Not** the thing that is drawn — it is rough and deliberately cheap | Yes |
| `kind` | Which piece type this is (`Straight`, `Corner`, `Sweeper`, `Hairpin`, `Chicane`) | Yes |
| `id` | Which **variant**: `Straight`, `CornerL`, `HairpinR` and so on. The placeable unit, and what the chooser counts | Yes |
| `weight` | How often it should turn up relative to the others | Yes |
| `minPieces` | How far into a run before this piece may appear at all. Gates the hard ones | Yes — the hairpin is gated at 8 |
| `mirror` | Whether a left-hand version should exist. A mirrored piece doubles the set for free | Yes |
| `nodes`, `cum`, `length` | A line of points down the middle and the arc length at each, for "how far along this piece are you" (see "Progress") | Yes |
| `surface` | `tarmac` or `dirt`, per part, through the existing `Surface` attribute (`CONTRACTS.md`) | Tarmac only; every slab carries the attribute |
| `safeStart` | Where a car respawns if it is put back onto this piece | **No.** Nothing respawns onto the road yet, so it would be unread code. `Pieces.poseAt(piece, t, y)` is what would give it |

**The variant is the unit, not the kind.** Counting corners rather than left-corners and
right-corners would let the road spiral: the bias would be happy with nine left-handers in a row.
Each of `Straight`, `CornerL` and `CornerR` carries its own weight and its own count.

### Joining

**Rotate the new piece about its own start socket until that socket's heading matches the previous
piece's end socket, then translate it into place.** That is the whole join. No splines, no curve
fitting, no runtime geometry. Every piece is defined in its own frame with its start socket at the
origin facing -Z, so the road is flush **by construction**, and it measures that way: over 500
generated pieces the worst gap between one piece's end socket and the next one's start is
**exactly zero** — the sockets are the same float64 numbers, not two numbers that agree. All nine
variants, placed on a socket turned 37° and moved a thousand studs, come out with a start-socket
gap and an end-socket gap of exactly zero too.

A piece's shape need not be one shape. The chicane is **an arc, then the other way**, appended to
the same open centre line, so the join inside a piece is the same construction as the join between
two: `Shape` (`straight`, `arc`, `chicane`) says how a piece is drawn and `kind` says what it is
called, and a corner, a sweeper and a hairpin are all `arc` with different numbers.

### The window

The generator keeps a window of road around the car and nothing else:

| Number | Value | What it does |
|---|---|---|
| `AheadPieces` | 10 | How many pieces are built in front of the car |
| `BehindPieces` | 4 | How many are kept behind it before the oldest is destroyed |
| `BarrierBehind` | 2 | How many pieces back the closing barrier sits |

So the world stays about 14 pieces big however long the run is — **measured at a peak of 1 340
parts**, the biggest single piece being 100 — which is also why `StreamingEnabled` can stay off
(`ARCHITECTURE.md`). The 909 this said before was step 2's; on the same harness the window now
reads **1 182 parts without the centre line and 1 340 with it**, which is what the markings cost
(see "The surface").

**The window only ever moves forward.** A piece behind the car has been destroyed, and nothing can
un-destroy it, so a player who turns round does not drag the window back with them. The closing
barrier is behind the window's furthest point for the same reason: turning round must not open the
way back up.

### Choosing the next piece

Not uniform random — **biased against what it has just used.** For each variant, count how many
are in the recent window; its weight is `(1 + mostUsedCount − thisCount) × weight`. A variant the
window is full of drops to the floor; one it has not used in a while rises. Then a weighted shuffle
picks the order to try.

That one line is most of why the reference's road does not feel repetitive, and it costs nothing.
Measured over five seeds of 500 pieces with nine variants, the worst share was **10.1 points off**
its weighted share — the straight, which is weighted 3 and is after the bias 18% of the road
rather than 27% — and the **longest run of any one variant was 4**.

### Looking ahead, so the road cannot trap itself

A generator that only checks the next piece will eventually place one that leaves nowhere to go.
So before committing, it **searches `LookAhead` pieces deep**, depth-first in the preference order
above, and only accepts a first piece that has a legal continuation that far. A combination is
illegal if any candidate's footprint overlaps any piece already laid or any earlier candidate.

| Number | Value | What it does |
|---|---|---|
| `LookAhead` | **14** (the spec said 5; see below) | Pieces deep the search must find a legal continuation |
| `SearchNodeBudget` | **2 000** (step 2 had 40 000) | Placements the plan may try for one piece before it relaxes. It went DOWN because hitting it no longer stops the road, so it is now set where it bounds the worst call: 40 000 gave 1 422 ms, 8 000 gave 263 ms, 2 000 gives 8.15 ms |
| `SearchMillisPerTick` / `SearchMillisUrgent` / `UrgentAheadPieces` / `MinAheadPieces` | **2 ms / 8 ms / 4 / 1** | What the spec called `SearchStepsPerFrame`, **built** (`T-052`). The lookahead is a standing plan sliced across ticks: 2 ms of work a tick normally, 8 ms when fewer than 4 pieces of road are left ahead, and below 1 piece the clock is ignored entirely, bounded by `SearchNodeBudget` |

If no legal choice exists at all, **nothing is placed** — the road stops growing rather than
growing wrongly, and it warns loudly naming the piece number and how many placements it tried.

**`LookAhead = 5` is not enough, and that is measured, not an opinion.** With step 1's two piece
types a 90-degree corner whose radius equals the straight's length puts the whole road on a
220-stud square lattice, and a self-avoiding walk on a square lattice traps itself: four corners
the same way close a ring exactly, and then every exit runs along road that is already there.
Measured then, 40 runs of 400 pieces: depth 3 stalled 35 times, 5 stalled 13, 7 stalled 3, 9
stalled once, 11 and 14 never.

**Step 2 expected that four more piece types would mean shallower looking was enough. It is the
opposite, and the measurement says so.** From `RoadTests:stalls` on the five-piece set, 20 runs of
400 pieces each, with the budget held well clear so what is measured is the depth and not the
giving up:

| `LookAhead` | Boxed itself in | Earliest | Worst search | Cost a piece | Worst single piece |
|---|---|---|---|---|---|
| 3 | 19 of 20 | piece 15 | 81 nodes | 0.11 ms | 2 ms |
| 5 | 13 of 20 | piece 15 | 261 | 0.23 | 7 |
| 7 | 8 of 20 | piece 43 | 989 | 0.36 | 30 |
| 9 | 8 of 20 | piece 126 | 2 925 | 0.59 | 65 |
| 11 | 3 of 20 | piece 116 | 7 902 | 0.82 | 175 |
| **14** | **2 of 20** | **piece 231** | **22 779** | **1.30** | **356** |
| 18 | 1 of 20 | piece 172 | 80 000 (the cap) | 3.95 | 2 321 |

**More ways to turn is not more ways out.** A hairpin folds the road back on itself 140 studs from
where it came and a chicane steps it 65 studs sideways without turning it: both make corridors the
road then has to thread. Counting what the road was standing on when it ran out of room puts the
hairpin and the chicane at about half the stalls between them while they are a third of the pieces
— but taking either one out measures **worse**, not better (10 of 20 with no hairpin against 6 of
20 with it, at depth 7), because a hairpin is also the one piece that can turn round inside a dead
end. Shifting the sweeper's arc off 45° to break the heading lattice does not help either (10 of
20 at 50°, 9 at 55°, against 6 at 45°).

So **14 stays** — now the best point on a curve rather than the first clean one. It is still
`AheadPieces + BehindPieces`, how many pieces the window remembers, so what the search proves is
"there is a way out of this window". 18 halves the stalls again but costs three times as much a
piece and its worst single choice is 2.3 seconds, by which point the search is hitting the budget
rather than finishing.

**What did have to change is the budget, and what a node costs.** At 4 000, every stall at depth 14
was the search giving up rather than the road running out — the budget was deciding the answer.
`Pieces.quadsOverlap` is the only thing a search does, millions of times a run, and rewriting it to
allocate nothing took a node from **0.104 ms to 0.032** and the worst single choice from **3.0
seconds to 0.93**. With the budget at 40 000 all five of the test suite's seeds run 500 pieces
without a stall, where seed 7 stopped at piece 42 on a budget of 20 000.

**Both of those problems are now fixed, and the fix is `T-052`.** The search is explicit state
advanced by a `step()` that reads no clock, so the time slice decides only HOW MANY steps run in
one call, never which — slicing cannot reach the choice, and a seed is still a road. The worst
single call went from **1 422 ms at this width to 8.31 ms**, measured over 282 360 calls across 40
seeds driven at 145 studs/s. And the road stopped trapping itself: backtracking re-chooses pieces
decided but not yet built, and when no chain 14 long exists it lays the best chain it did stand up
rather than refusing. At 50 studs the old generator boxed in on all five suite seeds between
pieces 187 and 448; this one reaches 500 on all five, and 0 of 20 runs box in over 400 pieces.

**And then the set went from nine variants to sixteen (`T-068`), and the budget moved with it.**
The tree a search spends its budget on is `variants ^ depth` wide, so a budget set for nine does
not prove fourteen deep over sixteen; it runs out and the generator lays the best chain it found
instead, and a piece laid on one piece of proof is how a road walks into a dead end. Measured over
**45 runs of 500 pieces** — the five suite seeds and two pools of twenty — counting the pieces laid
on less than a full `LookAhead`:

| set and budget | boxed itself in | pieces on short proof | worst driven call |
|---|---|---|---|
| the flat nine, 2 000 | 0 of 45 | 58 | — |
| the sixteen, 2 000 | **1 of 45** (piece 227) | 92 | 8.20 ms |
| **the sixteen, 2 500** | **1 of 45** (piece 59) | **72** | **8.60 ms** |
| the sixteen, 3 000 | 0 of 5 measured | — | **89.81 ms** |

So `SearchNodeBudget` is **2 500**: it takes a fifth off the settling for nothing, and 3 000 is
refused because the one path that ignores the clock (`MinAheadPieces`, the road having already run
out under the car) then pays the whole budget in a single 90 ms call. Raising it does **not** take
the tail stall away — it only moves which seed is unlucky.

**Seven more variants did not make the generator worse.** At the shipped depth both sets box
themselves in about never and the 1-in-45 difference is too small to read anything into, so the
comparison is made where stalls are common enough to count, by cutting the lookahead down
(`RoadTests:stalls`, 20 runs of 400):

| lookahead | the flat nine | the sixteen |
|---|---|---|
| 5 | 11 of 20, 5 098 pieces, earliest stall at piece 25 | 12 of 20, 5 493 pieces, earliest at piece 56 |
| 7 | 7 of 20, 6 775 pieces | **4 of 20, 7 107 pieces** |
| 14 | 0 of 45 × 500 | 1 of 45 × 500 |

More ways to turn is more ways out, which is what step 2 found when it added the hairpin. The
tallies of what the road was standing on when it ran out of room put the `HairpinStack` — much the
biggest plan footprint in the set, 280 × 140 studs — at **0 of 4** stalls at depth 7 while it is a
tenth of the pieces.

### Progress

Each piece knows its number `N` in the run, and a point on it maps to a `t` from 0 to 1 along the
piece's centre line. Together they say exactly where the car is in the run, which gives three
things:

- **The window** — which pieces to build and which to destroy.
- **"Forward on new road"** — the car is on a piece number it has not exceeded, or further along the
  one it is on than it has been. This is the flag a scorer needs, and the reason the road owns it.
- **Going backwards** — more than one piece behind the furthest reached.

`progress` also returns `lateral` (studs from the centre line) and `onRoad`, which is what the
drive test reads to say the car never left the road.

**Where a car is, on the server, is not its pivot.** The client simulates its own car and writes
the CFrames locally; those writes never replicate, so the server's copy of the model sits at its
spawn for the whole run. `RoadService` reads `CarService:BelievedPosition(userId)` — the last
`CarState` packet the server accepted — and falls back to the pivot only when there is no
`CarService`, which is what a test with no player in it looks like.

### The barrier

A wall sits `BarrierBehind` pieces behind the window and moves up with it, so a player cannot drive
back down the road they came from into pieces that are about to be destroyed. It is part of the
generator, not scenery. The spec calls it invisible; while this is a prototype it is a translucent
red-grey, so it can be driven at on purpose.

### The surface, and how a player sees their speed

**On smooth plastic a player cannot tell 40 studs/s from 120** (the user, 2026-11-04). A flat colour
has nothing in it to stream past the camera, so the road read as a static plane at every speed. The
fix is three things, strongest first, and all of them are built-in materials and colours — **no
uploaded asset and no Creator Store insert anywhere in the road** (`ART-PIPELINE.md`):

| | What it is | What it costs |
|---|---|---|
| **A dashed centre line** | 10 studs of white every 24, laid at a fixed interval along the **whole run** | +158 parts in the window, **+13.4%** |
| **Asphalt on the slab** | `Enum.Material.Asphalt`, grain projected in world space | nothing |
| **Concrete on the barriers** | `Enum.Material.Concrete`, for peripheral vision | nothing |

**The interval is measured along the run, not along a piece, and that is the whole point.** A mark
passes the car at `speed / MarkInterval` and at nothing else — not the piece length, not the corner
radius, not how finely a curve is cut. At 24 studs that is **4.6 marks a second at 110 studs/s and
1.7 at 40**, which is the range the car actually does. So the builder carries the run's arc length
across every join, and a dash that runs off the end of a piece is **clipped and finished at the
start of the next** rather than skipped: skipping would leave one double-length gap at every join,
the one irregularity a player would see. Measured, the two halves meet within **0.089 studs**.

**Even spacing through a corner is the thing most likely to be wrong,** so it is measured. Marks are
placed with `Pieces.poseAt(piece, t, y)` — by arc-length fraction, not by segment — and over a
40-piece road the gap between consecutive marks is:

| Piece | Gaps | Measured spacing |
|---|---|---|
| Straight | 18 | 23.991..24.003 |
| Sweeper | 26 | 23.994..24.000 |
| Corner | 28 | 23.983..23.997 |
| Chicane | 24 | 23.946..23.997 |
| Hairpin | 28 | 23.895..23.997 |

**Worst deviation from the configured 24 studs: 0.105 studs, on the hairpin** — and that is not an
error in the spacing, it is the chord of a 24-stud arc at radius 70 being 0.12 studs shorter than
the arc. The spacing in arc length is exact.

Per piece, the centre line costs: Straight **+10** (3 parts to 13), Hairpin **+10** (90 to 100),
Chicane **+8** (60 to 68), Sweeper **+13** (75 to 88), Corner **+15** (81 to 96).

**A marking is decoration and the ground rays never see it.** It is not tagged `DriftSurface`, it is
`CanCollide = false` and `CanQuery = false`, and its painted face sits `MarkLift` = 0.02 studs above
`SurfaceY` with the rest of its 0.4 studs buried in the slab, so nothing z-fights and nothing is a
kerb. Measured on a live road: 131 marks, every top at Y = 0.0200, **0 tagged, 0 queryable, 0
colliding**, and the drive is unchanged — `RoadTests`' 50-piece drive reports the same 28 182 steps
and 0 steps off the road as before, and a real run reports `grounded`, `surfaceGrip 1.00`, four
wheels down.

**What is deliberately not built:** solid edge lines. They cost one part per segment per side —
**about +460 parts, +40%** — against a budget of about +25%, and dashed edge marks at every second
interval would be +158 more on top of the centre line (+26.7% in total). The centre line already
carries the speed cue; if the edges want detail later, the cheap version is edge marks every third
interval (+105, +22% in total). `BarrierMaterial` is the other free knob: `Brick` or `Slate` has
much stronger world-space grain than `Concrete` if peripheral motion ever needs more.

## Rules and numbers

Every number above lives in `Shared/Config/Road.luau`, its own config module beside
`Config/Drift.luau`, none of them in the logic.

**The pieces are built by code, parametrically — not modelled.** Radius, arc, width and length are
numbers; a builder turns them into parts, the same way `ServerScriptService/Playground` builds the
plate. The whole road set is text in git, and a corner's radius changes in a commit.

**Smooth curves do not need meshes, and this is measurable.** The car does not use Roblox physics —
it finds the ground with four downward rays — so a curve made of short straight segments is
*physically identical* to a smooth one as long as each segment is short next to the `Wheelbase`
(9.6 studs). It is purely a question of how it looks, and the deviation from the true arc is
`chord² / (8 × radius)`. A straight is **one part** however long it is, because it is straight.

**The chord was a proxy and the deviation is the thing**, which only showed once step 2 added a
radius tighter than 220. At `MaxSegmentChord` = 13 studs the 220-radius corner is 0.093 studs off
the arc but a 70-radius hairpin is **0.299** — three times as far out, on the piece where the car
is slowest, closest to the barriers and most able to see it. So a curve is now cut by whichever of
two limits bites, the chord or `MaxArcDeviation` = 0.1 studs, which takes the hairpin from 17
segments to 30 and the whole set to a worst deviation of **0.096 studs**.

**If segmentation ever shows,** Roblox can generate real meshes from code at runtime
(`AssetService:CreateEditableMesh`, tested working in this game's Main place, 2026-11-03). The same
numbers would extrude a genuinely smooth surface without changing the piece system and without
Blender.

### Where the road is

`Config.Road.Offset` is **(0, 0, -20 000)**, and the three worlds and the reasoning are in
`WORLD.md` "The three worlds". Short version: the road is not a place on a plate, it grows away
from its start for as long as the run lasts, so it gets a quarter of the world to itself; -Z is the
empty one; `RoadTests` asserts the live window stays clear of the other two (18 761 studs at the
last measurement).

### The numbers, and the drives behind them

**Road width is 50 studs, and it is the user's number** (`DECISIONS.md`, 2026-11-04). It was 35
first; they drove it and asked for 50. The car is 14.83 studs long and 7.14 wide as it is actually
built, and a default R15 avatar is 5.46 tall, so the car is within 6% of real car-to-person
proportions. 50 studs is 7.0 car widths. **The car is not rescaled to the road and the road is not
rescaled to the car.**

**Widening is not free, and it is not only a feel number.** A piece's footprint is half the road
width plus the barrier, so every piece takes 15 studs more room at 50 than at 35 and the road
crowds itself SOONER. That is measurable: at 50 the pre-`T-052` generator boxed itself in on all
five suite seeds where at 35 it managed 500 pieces. Changing this number means re-measuring the
stall table, not re-typing it.

**Flat, when this was written.** No elevation at all, no crest, no banking: every surface topped out
at Y = 0. **Both halves of that have since changed.** A piece can carry a height and a bank
(`T-066`, `features/road-elevation.md`), and a fall is no longer an absolute world height but a
distance below the last ground the car touched (`T-067`), because a descending road would otherwise
drown every car on it by about piece eleven. The nine pieces in the set below are still flat.

**The corner's radius and the straight's length were measured, not chosen.** `RoadTests:drive` is
an autopilot — a pure-pursuit controller aiming a fixed distance down the road's own centre line,
converting the angle it is off by into the one number the model takes, and using the handbrake only
to shed speed it cannot carry into a corner it can already see. It is a test fixture and a stand-in
for a player, and it exists so "can a car drive this road" has a number in the answer.

First, what the car can hold at all, with a steady finger on a flat plane (`Sim.drive`, 60 FPS,
eight seconds, entering at 100 studs/s):

| Finger | Settled speed | Settled slip | Path radius |
|---|---|---|---|
| 0.05 | 147 studs/s | 0° | 1 475 studs |
| 0.10 | 128 | 19° | 642 |
| 0.15 | 95 | 32° | 318 |
| 0.20 | 61 | 32° | 152 |
| 0.30 | 44 | 18° | 74 |
| 0.50 | 31 | 34° (peaks past 90° — it spins) | 31 |

Then, twelve generated pieces driven by the autopilot on the real road and the real Workspace
(`RoadTests:sweep`, seed 8080):

| Radius | Speed through the run | Sideways | Worst off the centre line |
|---|---|---|---|
| 100 | 41..95, mean 61 | 66% | 13.6 of 17.5 studs |
| 140 | 45..103, mean 66 | 68% | 13.3 |
| 180 | 46..107, mean 72 | 76% | 14.1 |
| **220** | **53..111, mean 79** | **71%** | **14.1** |
| 260 | 60..109, mean 85 | 69% | 13.8 |
| 320 | 60..113, mean 91 | 63% | 14.1 |
| 400 | 60..129, mean 100 | 66% | 14.1 |

Every one of them is drivable and none of them put a wheel off the road. **220 is chosen because it
is the radius at which the corner still costs the car half its speed** — 111 studs/s down the
straight, 53 at the corner's slowest — while leaving it sideways for 71% of the run. Above 250 the
corner stops costing anything (320 gives back 60 of 113) and the road reads as one long sweeper;
below 180 the car is never travelling fast enough for the loss to mean anything. A 90-degree arc at
220 is 345.6 studs.

The straight, at radius 220:

| Length | Speed through the run | Sideways |
|---|---|---|
| 100 | 57..102, mean 77 | 78% |
| 150 | 60..104, mean 78 | 69% |
| **220** | **53..111, mean 79** | **71%** |
| 300 | 53..120, mean 81 | 72% |
| 400 | 53..132, mean 84 | 62% |

**220 studs is what the car needs to go from the speed a corner leaves it at (53 studs/s) to a
speed the next corner cannot be held at (111 against the ~75 a 220-radius corner holds)**, so every
straight ends in a real corner entry. At 100 it only reaches 102 and the entry stops being a
decision; at 400 it reaches 132 and the road is mostly straight line.

### The three pieces step 2 added

**A number about the road cannot choose a piece.** Twenty generated pieces containing three
hairpins report mostly what the straights and the corners did, so `RoadTests:sweep` grew two
things: it can push every other piece out of the run (`only = { "Straight", "Hairpin" }`, by
setting their `minPieces` past any run), and the drive now keeps its numbers **per piece type**,
one visit at a time, so "the hairpin never put a wheel off the road" is a sentence about the
hairpin. Every table below is per-piece, from twenty-piece drives at seed 8080.

**`Sweeper`, 400 radius and 45°** — the corner the car is happiest drifting:

| Radius (arc 45°) | Speed on it | Drifting it | Held the slide the whole way | Longest slide |
|---|---|---|---|---|
| 280 | 49..135 | 83% | 5 of 10 | 4.8 s |
| 340 | 70..132 | 82% | 3 of 10 | 5.8 |
| **400** | **79..138** | **84%** | **5 of 10** | **6.1** |
| 500 | 83..141 | 79% | 3 of 10 | 5.9 |
| 650 | 91..145 | 76% | 3 of 10 | 5.8 |

Arc, at radius 400: 30° drifts 81% for 53 steps on a barrier, **45° drifts 84% for 63**, 60° drops
to 81% for 111, 90° to 77% for 103, 120° to 76% for 143. 400 and 45 is where **the slide lasts
longest without the car running out of road**: the longest unbroken slide of any sweep run, the
highest share of the piece spent sideways, and the car never below 79 studs/s where a 220 corner
takes it to 53. Opening it further only makes it a straight; winding the arc on costs the road,
because a long fast corner runs the car wide for longer.

**`Hairpin`, 70 radius and 180°, gated at 8 pieces** — the piece that has to stop the car:

| Radius (arc 180°) | Speed on it | Drifting it | Peak slip | Barrier steps per hairpin |
|---|---|---|---|---|
| 40 | 22..55 | 70% | 72° | 2.1 |
| 50 | 27..57 | 74% | 65° | 2.1 |
| 55 | 30..60 | 71% | 64° | 2.7 |
| 65 | 28..65 | 78% | 61° | 4.1 |
| **70** | **30..68** | **81%** | **63°** | **5.0** |
| 80 | 32..72 | 81% | 57° | 6.7 |
| 100 | 35..81 | 83% | 56° | 8.1 |
| 120 | 33..88 | 84% | 62° | 9.9 |
| 150 | 38..99 | 78% | 61° | 9.4 |

**The autopilot gets round every one of them** — 0 steps off the road at every radius from 40 to
150 — so the choice is not where it stops working. 70 is the tightest radius that still holds the
car in a slide for four fifths of the piece (against 70–74% at 40–55, where it is being braked
rather than drifted) while keeping peak slip at 63°, well short of the 90° where the grip force
turns into a brake and the car spins. The arc is 180° because 120° leaves it drifting 79% and 150°
72%, against 81%. **The tight radius costs the generator** and that is a real trade: a 70-radius
fold leaves a 140-stud corridor nothing else fits down, and at lookahead 11, radius 70 stalled 3
runs of 20 where 110 stalled 2 and 150 stalled 1.

`minPieces = 8` is the gate, in pieces because that is what the generator counts: the first eight
pieces are 1 780–2 200 studs and about **30 seconds** of driving, so a hairpin can never be the
second thing a player meets.

**`Chicane`, 140 radius and 40° each way, no straight between** — the catch between two slides, so
the number that chooses it is how often the car actually swaps a slide one way for one the other
(the slip passing all the way through zero, from 12° one side to 12° the other):

| Radius (arc 40°) | Speed on it | Drifting it | Caught and swapped | Barrier steps per chicane |
|---|---|---|---|---|
| 110 | 49..90 | 69% | 1.1 | 2.2 |
| **140** | **47..96** | **78%** | **1.5** | **5.6** |
| 180 | 54..108 | 82% | 1.6 | 9.4 |
| 240 | 63..125 | 84% | 1.7 | 13.9 |
| 320 | 73..131 | 86% | 1.7 | 16.6 |

Arc, at radius 140: **25° is the proof the piece earns its place** — the car straight-lines it,
drifting 31% and swapping once in ten chicanes. 40° drifts 78% and swaps 1.5 times; 55° drifts 89%
for 12.0 barrier steps; 70° drifts 91% for 14.6. 140 and 40 is the shallowest pair that transitions
every time. `Middle`, a straight between the two bends, is **zero**: 30 studs of it buys 16 swaps
against 15 and takes barrier contact from 5.6 steps a chicane to 9.4.

**The barriers get touched, and that is intended.** On the 50-piece drive of the full set the car
was within 3.5 studs of the edge at its worst and brushed a barrier on 181 of 23 910 steps — 0.8%
of the time. The road is meant to be technical.

**One number here is the driver, not the road, and it is written down so it is not mistaken for a
result:** the autopilot's lookahead. At 0.55 seconds it chased its own slide round every corner and
crawled the road at a mean of 49 studs/s; at 0.9 it drives it at 91. Nothing about the road changed.

### The piece set

Enough to prove the system, not a content pass. Each mirrors except the straights.

| Piece | Shape | Why it is in the set | Step |
|---|---|---|---|
| `Straight` | A plain 220-stud length, weight 3 | Breathing room, and the piece that makes a long corner feel long | **1, built** |
| `Corner` | 220 radius, 90°, mirrored | The staple, and the thing the whole machine is proven on | **1, built** |
| `Sweeper` | 400 radius, 45°, mirrored (314 studs) | The corner the car is happiest drifting: enters at 79 studs/s, holds the slide for 84% of it | **2, built** |
| `Hairpin` | 70 radius, 180°, mirrored (220 studs), gated at `minPieces = 8` | Needs the car slowed and rotated: it leaves at 30 studs/s where a straight gives 94 | **2, built** |
| `Chicane` | 140 radius, 40° each way, mirrored (196 studs, 65 across) | Tests the catch between two slides, which is the skill the model is built on: 1.5 slides caught and swapped per chicane | **2, built** |
| `Crest` | A straight with a rise and fall | Proves pieces may change height and the car lands cleanly. **Deliberately out of steps 1 and 2** | Replaced by the four below |
| `Link` | A 140-stud straight that levels the road and hands on a 7° climb | The breather, and the only thing in the set that climbs | **4, built (`T-068`)** |
| `Banked30` | 400 radius, 30°, mirrored (209 studs), banked 5° in and out, losing 14 studs | The showcase: a direction change with superelevation through it | **4, built (`T-068`)** |
| `HairpinStack` | 70 radius, 180° each way, mirrored (440 studs, 280 across), losing 40 studs, gated at `minPieces = 14` | Two hairpins back to back, opposite hands: how a mountain road loses height | **4, built (`T-068`)** |
| `Corkscrew` | 150 radius, 45° each way, mirrored (236 studs, 88 across), losing 20 studs and handing on a 5° descent, gated at `minPieces = 10` | Flat entry, then the floor leaves — and it is what *starts* a descent | **4, built (`T-068`)** |

**Each piece's numbers were measured, not chosen** — "The numbers, and the drives behind them"
below has every table. The straight is weighted 3 and everything else 1, so a straight is 27% of
the road rather than one piece in nine; the drive barely tells the two apart and that is written
down rather than dressed up.

## Server and client

**The server builds the road and owns it,** as it owns the playground today
(`PlaygroundService`): one world, replicated, identical for everyone in the place. The client's car
simulation rays it like any other ground and needs no special knowledge — measured: with the road
built and the client's own car driven on to it, `surfaceGrip` reads 1.00, `grounded` is true, and
the server dropped none of its `CarState` packets.

**The seed is the server's.** A run's road is a seeded sequence, so the same seed gives the same
road — which is what makes a run reproducible, a ghost possible, and a score checkable. The client
is never asked where the road is.

**What had to change for a seed to really be a road.** The spec counts the pieces "currently in the
window" and tests against "any piece already in the world", and both of those depend on where the
*car* is — so two players with the same seed who drove at different speeds would get different
roads. The generator therefore keeps its own fixed-length tail of the sequence it has generated
(`AheadPieces + BehindPieces` pieces) and counts and tests against that. In normal play the tail and
the live window are the same pieces; the difference is only that the tail does not care how fast
anyone drove.

**Progress is the server's too,** for the same reason: a client that reports its own `N` and `t`
reports its own score later.

## Contracts

In `CONTRACTS.md`:

- `RoadService:Generate(seed)`, `Stop()`, `HasRoad()`, `SpawnCFrame()`, `PieceAt(position)`,
  `Progress(position)`, `Bounds()`, `DebugState()` and the Studio-only `DebugAdvance`,
  `DebugAdvanceTo`, `DebugGenerator`, `DebugPieces`.
- `Shared/Config/Road.luau` as a new config module, `Shared/Road/Pieces`, `Shared/Road/Generator`
  and `Shared/Road/Builder` as new shared modules.
- `Workspace.Road` as a new path, present only while a run is going.
- The `DriftSurface` tag and the `Surface` attribute are already contracted; the row for the tag now
  names the road's builder and says why the barriers are **not** tagged.
- The `N`, `Kind` and `Variant` attributes on a `Piece_<n>` folder.
- `Mark_<n>_<k>` parts inside a piece's folder: the centre line. **Never tagged**, never queryable,
  never collidable — decoration, and nothing may rely on them. `k` is the dash's index along the
  whole run, which is why one dash can appear as two parts in two neighbouring pieces.

## UI

None. The road has no HUD. The start button is step 3's.

## Analytics

Not yet — the loop's events are designed with scoring, which is not built.

## Monetization

None.

## Platform risks

None beyond what `drift-model.md` already records. The pieces are our own geometry built from
numbers; nothing is taken from the reference but the method. The car on the road is still the AE86
placeholder, which is **not approved to publish** (`drift-model.md` "Platform risks").

## Art and sound

Programmer art, and nothing else: asphalt-grey road, concrete barriers, a white dashed centre line
("The surface" has every number). Built-in materials and colours only — no uploaded asset, no
Creator Store insert. A real look is its own task, after the system works.

## Testing

`ServerScriptService/Tests/RoadTests.luau`, 29 checks, run from the server debug bridge:
`game.ServerStorage.DebugBridge:Invoke("DebugRoadTests", "run")`. All 29 passing, 26 s.

| Check | What proves it | Measured |
|---|---|---|
| **The piece set is what the config says** | Variants, kinds, segments, chord, deviation from the true arc | 5 kinds in 9 variants; worst deviation **0.096** studs (the hairpin, 30 chords of 7.33) |
| **Every variant joins flush** | All nine placed on a socket turned 37° and moved a thousand studs | Worst start-socket gap **0.000e+00** studs, worst end-socket gap **0.000e+00**, no seam inside a piece |
| **The chicane's two bends are opposite** | The yaw each half turns, the net turn, and how far across it steps | +40.0° then −40.0°, net **5.6e-15**, stepping **65.5** studs across a 35-stud road |
| **The road is continuous** | Every piece's start socket against the previous piece's end socket, over 500 pieces | Worst gap **0.000e+00** studs and radians |
| **The road never crosses itself while it exists** | At every moment of a 500-piece run, no two pieces alive at the same time overlap | **0** overlapping pairs. Ignoring the window: 38 pairs over the whole run, the closest 16 pieces apart — all long destroyed |
| **The window holds** | Pieces in the world through a 150-piece drive, against folders, built pieces and generator pieces | 11..15 against 14; **0** disagreements; peak **1 340** parts, biggest piece 100 (1 182 and 90 before the centre line) |
| **Driving back does not drag the window back** | Told the car is at piece 40 after reaching 150 | Window still 146..160 |
| **The closing barrier follows** | Walked 148 pieces, against where it belongs | **0** times absent, worst **0.0000** studs out, 39 studs wide on a 35-stud road |
| **A seed is a road** | Two seeds, 200 pieces each, twice | Identical by variant and by position; a different seed differs in 177 of 200. A seed that boxes itself in stops at the same piece both times, which is the same road, not a difference |
| **It does not repeat** | Shares and longest same-variant run, 5 seeds × 500 pieces | Worst share **10.1 points** off its weighted share; longest run of one variant **4** |
| **The gated pieces never appear too early** | Every piece with a `minPieces`, 5 seeds × 500 pieces | **0** appearances too early; the earliest hairpin of all was at piece **9**, gated at 8 |
| **The lookahead works** | 5 seeds × 500 pieces; then forced into a closed ring by hand | **0** stalls, worst search 29 297 placements against a budget of 40 000. Driven into the ring it places **nothing** and warns; three corners in, it declines the ring-closing corner — which crosses nothing one piece deep — and places a chicane instead |
| **Progress is right** | 150 samples down 30 pieces, then 120 back up | Monotonic, forward-on-new-road true throughout; driving back, **0** of 120 read as new road and the backwards flag came up for 112 |
| **Pieces are drivable ground** | Every part's tag, `Surface`, anchoring; 1 353 rays down the road | **0** wrongly tagged, **0** missing a `Surface`, **0** rays missed, worst height off **0.00000** studs. It counts anything not named `Road_*` as a wall, so the 118 centre-line marks in the window are in its "485 barrier parts" — what it asserts of them (untagged, anchored) is exactly right, only the word is wrong |
| **No physics** | BodyMovers, constraints, scripts, unanchored parts | **0** of each |
| **The road is nowhere near the other worlds** | The live window's box against the playground's and the track's | 18 115 studs clear |
| **A car can actually drive it** | The autopilot down 50 generated pieces at speed | 50 pieces, 199 s, 23 910 steps; 24..117 studs/s, mean 65; drifting 73%, 34 slides caught and swapped; worst 14.0 of 17.5 studs from the centre line; **0** steps off the road, **0** airborne, **0** stuck |
| **It drove all five piece types** | Which kinds the drive met, and what the car did on each | All five met: 10 straights, 8 corners, 11 sweepers, 12 hairpins, 8 chicanes; **0** steps off the road on any of them. Sweeper 45..115 drifting 70%, hairpin 24..68 drifting 80%, chicane 49..103 drifting 78% with 7 slides swapped |

Two measurement harnesses sit beside the checks and are kept so the next person can repeat the
work rather than take it on trust:

- `DebugRoadTests "sweep"` — mutates `Config.Road` in the live VM, rebuilds the piece set, drives,
  and puts everything back. Every piece's table above is its output. It takes `piece`, `field` and
  `values` to sweep anything, `set` to hold other numbers somewhere else while it does, and `only`
  to push every other piece out of the run so the answer is about the piece.
- `DebugRoadTests "stalls"` — how often a long run boxes itself in, against `LookAhead`,
  `SearchNodeBudget` and a corner's arc. The lookahead table above is its output. It reports
  **why** a run stalled — out of budget or out of road — because those want opposite fixes, and
  which piece the road was standing on when it ran out of room.

**The other six suites are unmoved by this work:** DriftTests 40/40, CollisionTests 39/39,
PlaygroundTests 45/45, JitterTests 11/11, TrajectoryTests 13/13, GarageTests 24/24.

### One check the spec asked for that cannot be true

The spec asked that no two pieces' footprints overlap over 500 pieces. **A bounded window cannot
promise that, and it is not what the generator checks.** It keeps the last 14 pieces and tests
against those, because the rest have been destroyed and are not in the world to cross. Measured,
500 pieces of one seed contain 38 pairs that would overlap if they both still existed, the closest
of them 16 pieces apart — about 5 000 studs of road and a minute of driving. The check that is
true, and the one that matters, is the one in the table.

## Open questions

- **What a run is** ("What this spec does NOT decide"). The road is the same either way, but the
  window, the barrier and the respawn all read differently if a run can be finished rather than
  only ended.
- ~~Whether 35 studs is right once a person drives it.~~ **Answered by the user on 2026-11-04:
  50 studs.** Whether 50 is right is now the open one, and it is still theirs, not a measurement.
- ~~Whether the road may stop growing, and what a run does if it does.~~ **Answered by `T-052`:**
  it recovers rather than refusing. 0 of 20 runs box in over 400 pieces; when no chain 14 long
  exists it lays the best chain it found. The road stops only when nothing at all is legal, which
  no sweep has produced.
- **Whether elevation earns its place.** `Crest` is dropped from this build. Hills make every other
  problem harder — the camera, the rays, the overlap test, which becomes genuinely 3D.
- **Whether a long run can wander back into the other two worlds.** Measured, it would take some
  three hours of continuous driving and only fourteen pieces exist at once; the test asserts the
  current window is clear. If a run is ever unbounded in time, the honest fix is to move the
  road's origin with the window rather than to move `Offset` further out.
- **What a fall does, where a player spawns, and how they get back to the other two worlds.** Step
  3's, deliberately not touched here: `Config.Drift.StartWorld` is still `"track"` and nothing
  spawns anyone onto the road.
