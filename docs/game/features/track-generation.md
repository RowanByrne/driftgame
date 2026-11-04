# Feature: Road pieces and the endless road

**Status:** **step 1 of 3 built** (`T-044`), the generator proven on two piece types. Steps 2
(the other four pieces) and 3 (the start button, spawning, falling, getting back to the other
worlds) are not built. **Owner task:** `T-044`; specced as `T-030`.

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
| `src/ServerScriptService/Tests/RoadTests.luau` | 25 checks, and the two measurement harnesses |

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

| It carries | What for | Built in step 1? |
|---|---|---|
| `start`, `finish` | The sockets. A piece's end is the next piece's start | Yes |
| `quads` | The footprint: a flat list of oriented rectangles, one per segment, covering the road and both barriers, plus a bounding box for a quick reject. **Not** the thing that is drawn — it is rough and deliberately cheap | Yes |
| `kind` | Which piece type this is (`Straight`, `Corner`) | Yes |
| `id` | Which **variant**: `Straight`, `CornerL`, `CornerR`. The placeable unit, and what the chooser counts | Yes |
| `weight` | How often it should turn up relative to the others | Yes |
| `minPieces` | How far into a run before this piece may appear at all. Gates the hard ones | Yes (nothing uses it yet: both pieces are 0) |
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
**exactly zero** — the sockets are the same float64 numbers, not two numbers that agree.

### The window

The generator keeps a window of road around the car and nothing else:

| Number | Value | What it does |
|---|---|---|
| `AheadPieces` | 10 | How many pieces are built in front of the car |
| `BehindPieces` | 4 | How many are kept behind it before the oldest is destroyed |
| `BarrierBehind` | 2 | How many pieces back the closing barrier sits |

So the world stays about 14 pieces big however long the run is — **measured at a peak of 1 059
parts**, the biggest single piece being 81 — which is also why `StreamingEnabled` can stay off
(`ARCHITECTURE.md`).

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
Measured over five seeds of 500 pieces with three equally weighted variants, the worst share was
**1.3 points off** an even third, and the longest run of any one variant was **5**.

### Looking ahead, so the road cannot trap itself

A generator that only checks the next piece will eventually place one that leaves nowhere to go.
So before committing, it **searches `LookAhead` pieces deep**, depth-first in the preference order
above, and only accepts a first piece that has a legal continuation that far. A combination is
illegal if any candidate's footprint overlaps any piece already laid or any earlier candidate.

| Number | Value | What it does |
|---|---|---|
| `LookAhead` | **14** (the spec said 5; see below) | Pieces deep the search must find a legal continuation |
| `SearchNodeBudget` | 4000 | Placements one search may try before it gives up. A guard, not a tuning number: the worst search over 150 000 generated pieces tried **527**, and a normal choice costs fourteen |
| `SearchStepsPerFrame` | not built | Spreading the search over frames. Deferred: the whole search costs **0.46 ms** and a piece arrives every three seconds or so |

If no legal choice exists at all, **nothing is placed** — the road stops growing rather than
growing wrongly, and it warns loudly naming the piece number and how many placements it tried.

**`LookAhead = 5` is not enough, and that is measured, not an opinion.** With only two piece types
a 90-degree corner whose radius equals the straight's length puts the whole road on a 220-stud
square lattice, and a self-avoiding walk on a square lattice traps itself: four corners the same
way close a ring exactly, and then every exit runs along road that is already there. From
`RoadTests:stalls`, 40 runs of 400 pieces each:

| `LookAhead` | Runs that boxed themselves in | Worst search |
|---|---|---|
| 3 | 35 of 40, by piece 9 | 21 nodes |
| 5 | 13 of 40, by piece 16 | 45 |
| 7 | 3 of 40, by piece 21 | 75 |
| 9 | 1 of 40, by piece 263 | 117 |
| 11 | 0 of 40 | 156 |
| **14** | **0 of 300 runs of 500 pieces** | **527** |

14 is not a round number: it is `AheadPieces + BehindPieces`, how many pieces the window
remembers. Look that far and a legal continuation reaches past everything currently being avoided,
so what the search proves is "there is a way out of this window", which is the question. Over
**150 000 generated pieces — about fifty hours of driving — it never once had nothing to place.**

Step 2 adds four more piece types, and more ways out means shallower looking is enough. Re-run
`RoadTests:stalls` then rather than keeping 14 out of habit.

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
`chord² / (8 × radius)`. `MaxSegmentChord` is 13 studs, so the built 220-radius corner is **27
chords of 12.80 studs, 0.093 studs off the true arc**. A straight is **one part** however long it
is, because it is straight.

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

**Road width is 35 studs, and it is the user's number** (`DECISIONS.md`, 2026-11-04). The car is
14.83 studs long and 7.14 wide as it is actually built, and a default R15 avatar is 5.46 tall, so
the car is within 6% of real car-to-person proportions. 35 studs is 4.9 car widths — deliberately
tight. **The car is not rescaled to the road and the road is not rescaled to the car.**

**Flat.** No elevation at all in this build: no crest, no banking. Every surface tops out at Y = 0,
which is why the other two worlds' `FallY` / `RespawnBelowY` pair is right for this one too.

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

**The barriers get touched, and that is intended.** On the 50-piece drive the car was within 3.4
studs of the edge at its worst and brushed a barrier on 303 of 22 168 steps — 1.4% of the time.
The road is meant to be technical.

**One number here is the driver, not the road, and it is written down so it is not mistaken for a
result:** the autopilot's lookahead. At 0.55 seconds it chased its own slide round every corner and
crawled the road at a mean of 49 studs/s; at 0.9 it drives it at 91. Nothing about the road changed.

### The piece set

Enough to prove the system, not a content pass. Each mirrors except the straights.

| Piece | Shape | Why it is in the set | Step |
|---|---|---|---|
| `Straight` | A plain 220-stud length | Breathing room, and the piece that makes a long corner feel long | **1, built** |
| `Corner` | A 220-radius, 90-degree corner, mirrored | The staple, and the thing the whole machine is proven on | **1, built** |
| `Sweeper` | A long, large-radius corner | The corner the car is happiest drifting: enters fast, holds. The 320 and 400 rows above are what it would feel like | 2 |
| `Hairpin` | A tight corner | Needs the car slowed and rotated. `minPieces` gated. The 100 row is the shape of it | 2 |
| `Chicane` | Left then right | Tests the catch between two slides, which is the skill the model is built on | 2 |
| `Crest` | A straight with a rise and fall | Proves pieces may change height and the car lands cleanly. **Deliberately out of this build: flat, no elevation at all** | 2, if elevation earns its place |

**Two piece types exercise every part of the machinery** — one that does not turn, one that does,
and the mirror that makes left and right both exist — which is why step 1 stops here rather than
stubbing four more.

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

Programmer art, and nothing else: flat grey road, plain grey barriers. A real look is its own task,
after the system works.

## Testing

`ServerScriptService/Tests/RoadTests.luau`, 25 checks, run from the server debug bridge:
`game.ServerStorage.DebugBridge:Invoke("DebugRoadTests", "run")`. All 25 passing, 9.4 s.

| Check | What proves it | Measured |
|---|---|---|
| **The piece set is what the config says** | Variants, segments, chord, deviation from the true arc | 3 variants; corner 27 chords of 12.80 studs, 0.093 off the arc |
| **The road is continuous** | Every piece's start socket against the previous piece's end socket, over 500 pieces | Worst gap **0.000e+00** studs and radians |
| **The road never crosses itself while it exists** | At every moment of a 500-piece run, no two pieces alive at the same time overlap | **0** overlapping pairs. Ignoring the window: 29 pairs over the whole run, the closest 15 pieces apart — all long destroyed |
| **The window holds** | Pieces in the world through a 150-piece drive, against folders, built pieces and generator pieces | 11..15 against 14; **0** disagreements; peak 1 059 parts |
| **Driving back does not drag the window back** | Told the car is at piece 40 after reaching 150 | Window still 146..160 |
| **The closing barrier follows** | Walked 148 pieces, against where it belongs | **0** times absent, worst **0.0000** studs out, 39 studs wide on a 35-stud road |
| **A seed is a road** | Two seeds, 200 pieces each, twice | Identical by variant and by position; a different seed differs in 141 of 200 |
| **It does not repeat** | Shares and longest same-variant run, 5 seeds x 500 pieces | Worst share **1.3 points** off a third; longest run **5** |
| **The lookahead works** | 5 seeds x 500 pieces; then forced into a closed ring by hand | **0** stalls, worst search 142 nodes. Driven into the ring it places **nothing** and warns; three corners in, it declines the ring-closing corner — which crosses nothing one piece deep — and places a right-hander instead |
| **Progress is right** | 150 samples down 30 pieces, then 120 back up | Monotonic, forward-on-new-road true throughout; driving back, **0** of 120 read as new road and the backwards flag came up for 112 |
| **Pieces are drivable ground** | Every part's tag, `Surface`, anchoring; 1 353 rays down the road | 193 road parts, 387 barriers; **0** wrongly tagged, **0** missing a `Surface`, **0** rays missed, worst height off **0.00000** studs |
| **No physics** | BodyMovers, constraints, scripts, unanchored parts | **0** of each |
| **The road is nowhere near the other worlds** | The live window's box against the playground's and the track's | 18 761 studs clear |
| **A car can actually drive it** | The autopilot down 50 generated pieces at speed | 50 pieces, 185 s, 22 168 steps; 43..120 studs/s, mean 81; drifting 68%; worst 14.1 of 17.5 studs from the centre line; **0** steps off the road, **0** airborne, **0** stuck |

Two measurement harnesses sit beside the checks and are kept so the next person can repeat the
work rather than take it on trust:

- `DebugRoadTests "sweep"` — mutates `Config.Road` in the live VM, rebuilds the piece set, drives,
  and puts everything back. The radius and length tables above are its output.
- `DebugRoadTests "stalls"` — how often a long run boxes itself in, against `LookAhead` and the
  corner's arc. The lookahead table above is its output.

**The other six suites are unmoved by this work:** DriftTests 40/40, CollisionTests 39/39,
PlaygroundTests 45/45, JitterTests 11/11, TrajectoryTests 13/13, GarageTests 17/17.

### One check the spec asked for that cannot be true

The spec asked that no two pieces' footprints overlap over 500 pieces. **A bounded window cannot
promise that, and it is not what the generator checks.** It keeps the last 14 pieces and tests
against those, because the rest have been destroyed and are not in the world to cross. Measured,
500 pieces of one seed contain 29 pairs that would overlap if they both still existed, the closest
of them 15 pieces apart — about 5 000 studs of road and a minute of driving. The check that is
true, and the one that matters, is the one in the table.

## Open questions

- **What a run is** ("What this spec does NOT decide"). The road is the same either way, but the
  window, the barrier and the respawn all read differently if a run can be finished rather than
  only ended.
- **Whether 35 studs is right once a person drives it.** The autopilot keeps the car 3.4 studs
  inside the edge at its worst and brushes a barrier 1.4% of the time; a human on a touchscreen is
  not an autopilot. This wants the user, not another measurement.
- **Whether elevation earns its place.** `Crest` is dropped from this build. Hills make every other
  problem harder — the camera, the rays, the overlap test, which becomes genuinely 3D.
- **Whether a long run can wander back into the other two worlds.** Measured, it would take some
  three hours of continuous driving and only fourteen pieces exist at once; the test asserts the
  current window is clear. If a run is ever unbounded in time, the honest fix is to move the
  road's origin with the window rather than to move `Offset` further out.
- **What a fall does, where a player spawns, and how they get back to the other two worlds.** Step
  3's, deliberately not touched here: `Config.Drift.StartWorld` is still `"track"` and nothing
  spawns anyone onto the road.
