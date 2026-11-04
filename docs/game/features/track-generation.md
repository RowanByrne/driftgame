# Feature: Track pieces and the endless road

**Status:** specced, waiting on approval to build. **Owner task:** none yet; `T-030`.

Written from the reference game's own road generator, read off the decompile, the same way
`drift-model.md` was. What we take is how the system works; none of its source, art or names come
near this game (`PLATFORM-RISKS.md`).

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

| It carries | What for |
|---|---|
| `start`, `end` | The sockets. A piece's end is the next piece's start |
| `footprint` | A flat convex outline plus a height range, for the overlap test. **Not** the thing that is drawn — it is a rough shape, deliberately cheap |
| `kind` | Which piece type this is, so the chooser can count how often it has been used |
| `weight` | How often it should turn up relative to the others |
| `minPieces` | How far into a run before this piece may appear at all. Gates the hard ones |
| `mirror` | Whether a left-hand version should exist. A mirrored piece doubles the set for free |
| `safeStart` | Where a car respawns if it is put back onto this piece. Defaults to the start socket |
| `path` | A line of points down the middle, for "how far along this piece are you" (see "Progress") |
| `surface` | `tarmac` or `dirt`, per part, through the existing `Surface` attribute (`CONTRACTS.md`) |

### Joining

**Rotate the new piece about its own start socket until that socket's heading matches the previous
piece's end socket, then translate it into place.** That is the whole join. No splines, no curve
fitting, no runtime geometry. Every piece is built so its sockets are flush, so the road is
continuous by construction.

### The window

The generator keeps a window of road around the car and nothing else:

| Number | Start | What it does |
|---|---|---|
| `AheadPieces` | 10 | How many pieces are built in front of the car |
| `BehindPieces` | 4 | How many are kept behind it before the oldest is destroyed |
| `BarrierBehind` | 2 | How many pieces back the closing barrier sits |

So the world stays about 14 pieces big however long the run is, which is also why
`StreamingEnabled` can stay off (`ARCHITECTURE.md`).

### Choosing the next piece

Not uniform random — **biased against what it has just used.** For each piece type, count how many
are currently in the window; its weight is `(1 + mostUsedCount − thisCount) × piece.weight`. A type
the window is full of drops to the floor; a type it has not used in a while rises. Then a weighted
shuffle picks the order to try.

That one line is most of why the reference's road does not feel repetitive, and it costs nothing.

### Looking ahead, so the road cannot trap itself

A generator that only checks the next piece will eventually place one that leaves nowhere to go —
a hairpin into road it already laid. So before committing, it **searches `LookAhead` pieces deep**,
depth-first in the preference order above, and only accepts a first piece that has a legal
continuation that far. A combination is illegal if any candidate's footprint overlaps any piece
already in the world or any earlier candidate.

| Number | Start | What it does |
|---|---|---|
| `LookAhead` | 5 | Pieces deep the search must find a legal continuation |
| `SearchStepsPerFrame` | 1 | The search runs a little each frame rather than all at once, so it never stalls a frame. It is only forced to finish when a piece is actually needed |

If no legal choice exists at all, **nothing is placed** — the road stops growing rather than
growing wrongly. That is a bug to catch in testing, not a state to ship.

### Progress

Each piece knows its number `N` in the run, and a point on it maps to a `t` from 0 to 1 along the
piece's `path`. Together they say exactly where the car is in the run, which gives three things:

- **The window** — which pieces to build and which to destroy.
- **"Forward on new road"** — the car is on a piece number it has not exceeded, or further along the
  one it is on than it has been. This is the flag a scorer needs, and the reason the road owns it.
- **Going backwards** — more than one piece behind the furthest reached. The reference fires an
  event here; what the game does about it is a design decision, not a road one.

### The barrier

An invisible wall sits `BarrierBehind` pieces behind the car and moves up with it, so a player
cannot drive back down the road they came from into pieces that are about to be destroyed. It is
part of the generator, not scenery.

## Rules and numbers

Every number above lives in `Shared/Config/Track.luau`, its own config module beside
`Config/Drift.luau`, none of them in the logic.

**The pieces are built by code, parametrically — not modelled.** Radius, arc, width, bank and
length are numbers; a builder turns them into parts, the same way `ServerScriptService/Playground`
builds the plate today. The whole track set is then text in git, and a corner's radius changes in a
commit.

**Smooth curves do not need meshes, and this is measurable.** The car does not use Roblox physics —
it finds the ground with four downward rays — so a curve made of short straight segments is
*physically identical* to a smooth one as long as each segment is short next to the `Wheelbase`
(9.6 studs). It is purely a question of how it looks. For a 90° corner of 200-stud radius:

| Segments | Each segment | Furthest from the true arc |
|---|---|---|
| 12 | 26.2 studs | 0.428 studs |
| 24 | 13.1 studs | 0.107 studs |
| 48 | 6.5 studs | 0.027 studs |

A tenth of a stud is invisible at 150 studs/s. **Banking is the same trick:** roll each segment a
little further than the last.

**If segmentation ever shows,** Roblox can generate real meshes from code at runtime
(`AssetService:CreateEditableMesh`, tested working in this game's Main place, 2026-11-03). The same
numbers would extrude a genuinely smooth surface without changing the piece system and without
Blender. Blender is worth it for things that are not road — buildings, props, scenery with real
shape — and that is its own decision.

### The starting set

Enough to prove the system, not a content pass. Each mirrors except the straights.

| Piece | Shape | Why it is in the set |
|---|---|---|
| `Straight` | A plain length | Breathing room, and the piece that makes a long corner feel long |
| `Sweeper` | A long, large-radius corner | The corner the car is happiest drifting: enters fast, holds |
| `Corner` | A medium corner | The staple |
| `Hairpin` | A tight corner | Needs the car slowed and rotated. `minPieces` gated |
| `Chicane` | Left then right | Tests the catch between two slides, which is the skill the model is built on |
| `Crest` | A straight with a rise and fall | Proves pieces may change height and the car lands cleanly |

## Server and client

**The server builds the road and owns it,** as it owns the playground today
(`PlaygroundService`): one world, replicated, identical for everyone in the place. The client's car
simulation rays it like any other ground and needs no special knowledge.

**The seed is the server's.** A run's road is a seeded sequence, so the same seed gives the same
road — which is what makes a run reproducible, a ghost possible, and a score checkable. The client
is never asked where the road is.

**Progress is the server's too,** for the same reason: a client that reports its own `N` and `t`
reports its own score later. The road is where that line gets drawn.

## Contracts

New in `CONTRACTS.md` when it is built:

- `TrackService:DebugState()` — the window, each piece's kind, `N`, sockets and footprint, the
  seed, and the search's state.
- `TrackService:Generate(seed)` and `TrackService:PieceAt(position)`.
- `Shared/Config/Track.luau` as a new config module.
- The `Surface` attribute is already contracted and unchanged.

## UI

None. The road has no HUD.

## Analytics

Not yet — the loop's events are designed with scoring, which is not built.

## Monetization

None.

## Platform risks

None beyond what `drift-model.md` already records. The pieces are our own geometry built from
numbers; nothing is taken from the reference but the method.

## Art and sound

Programmer art: flat coloured parts, tarmac and dirt distinguished by colour. A real look is its
own task, after the system works.

## Testing

Measured, not guessed. `ServerScriptService/Tests/TrackTests.luau`:

| Check | What proves it |
|---|---|
| **The road is continuous** | Every piece's start socket matches the previous piece's end socket, position and heading, to a thousandth of a stud, over 500 generated pieces |
| **The road never crosses itself** | No two pieces' footprints overlap, over 500 pieces |
| **The window holds** | Pieces in the world stays at `AheadPieces + BehindPieces` ± 1 through a long drive, and memory does not grow |
| **A seed is a road** | The same seed gives the same sequence of piece types and positions, twice |
| **It does not repeat** | Over 500 pieces, no piece type exceeds its share by more than a stated margin, and the longest run of one type is small |
| **The lookahead works** | Forced into a corner by hand, the generator declines rather than placing an overlapping piece — and the test fails if it ever has nothing to place during a normal run |
| **A car can actually drive it** | `DebugDrive` the model down 50 generated pieces at speed: never airborne beyond a crest, never stuck, never off the road |
| **Progress is right** | `N` and `t` increase monotonically along a forward drive, and the "forward on new road" flag is false when driving back |
| **Pieces are drivable ground** | Every road part carries `DriftSurface` and a `Surface` value; the ground rays find them |
| **No physics** | No piece holds a BodyMover, constraint or unanchored part |

## Open questions

- **What a run is** ("What this spec does NOT decide"). The road is the same either way, but the
  window, the barrier and the respawn all read differently if a run can be finished rather than
  only ended.
- **How wide the road is.** It sets how much room there is to drift and is the single biggest feel
  number here. The car is 16.6 studs long; the playground's open plate is what the feel was
  approved on, and a road is much tighter than a plate. Wants a playtest, not a guess.
- **Whether elevation earns its place.** `Crest` is in the starting set to prove pieces may change
  height, but hills make every other problem harder — the camera, the rays, the overlap test, which
  becomes genuinely 3D. Could be dropped to flat for the first build.
- **Whether the plate survives.** The playground is where the feel was approved and is useful for
  tuning. Keeping both means a place with two worlds in it, or a switch.
