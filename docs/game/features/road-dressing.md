# Feature: Road dressing

**Status:** both steps built (T-328, T-334), waiting on the user's lane test. **Owner task:** T-327.

## Goal

What stands beside the road (crash barriers now, trees, signs, posts and the like later) is chosen by its own layer, one that **dresses** a road that's already laid. The road planner and the terrain decide only where the road goes and what the car drives on. Changing a barrier, or adding a new kind of roadside thing, then never touches the planner, never changes the road it lays, and can be built while planner work runs in parallel.

The user, 2026-11-19, asking for the hairpin barrier fix to wait for T-326: *"we should separate this code out from the road planner and terrain code. it should be procedural generation in it's own layer that 'dresses' the road with stuff."*

## How it plays

The same as today on the first step: the barriers stand where they stand now, look the same and stop the car the same. The player sees no change until step 2 shortens the barriers after hairpins.

1. **Move the barriers into the dressing layer** (no visible change). The road for any seed is identical before and after, and so is every barrier: the same runs, in the same places, to the stud.
2. **Shorten the barriers after hairpins.** On a hairpin, the barrier stops soon after the corner ends rather than running on into the next turn (the user's drawing on C-647207, 2026-11-19: the rail should end at the red line, where the bend straightens, not carry on to the X).

## Left out

- **Moving the trees.** Groves already place their trees in their own module (`Road/SplineGrove.luau`), outside the planner. Only the choice of a grove sits in the planner, because it widens that side's runoff, which the car drives on. Folding the trees into the dressing layer is a later step, offered once this one is approved.
- **Painted lines** (edge lines, the double yellow on tight stretches) stay with the road surface: they're painted on the tarmac, not stood beside it.
- **New kinds of dressing** (signs, chevrons, lamp posts, cones). This makes them easy to add; it doesn't add any.

## Rules and numbers

**What stays in the road and terrain layer** (the planner, `Road/SplineGen.luau`): the centreline, the runoff widths and edges each side, the gravel of a tight cliff edge, and a grove's choice and its widened runoff. These shape what the car drives on, and the planner's look-ahead (`_fitTurn`) still needs them.

**What moves to the dressing layer** (new, `Road/RoadDressing.luau` or similar): where the crash barriers stand, all of "Where the K-rails stand" (`features/mountain-road.md`), and the rail of a tight cliff edge. It runs once a section is laid and the ground beside it is known, reads the section and the ground, and writes the barrier runs.

- **Seeded, and never changes the road.** It has its own random stream. Nothing the dressing does can change a road draw, so a dressing change leaves every seed's road the same.
- **The server still chooses, the clients replay.** The barrier runs still go to the clients with each section, as they do now, so no remote changes. Whether the clients could later dress the road themselves is left for a later step.
- **Not in the planner's look-ahead.** `_fitTurn` stops dressing its previews, which takes work out of every turn the planner tries.
- **Its settings get their own config,** split out of `Config/Spline.luau` "Terrain" (the `KRail*` values).
- **Barrier run-out after a hairpin (step 2):** today every railed corner runs `KRailRunOut` = 60 studs past its end. Hairpins get their own, shorter run-out, about 15 studs (proposed), so the rail ends near where the bend straightens; other corners and cliffs keep 60. The number gets tuned with the user in a lane.

## Server and client

Unchanged: the server lays the road and now dresses it too; clients draw what they're sent.

## Contracts

None changed: the section still carries its barrier runs in the same form.

## Platform risks

None.

## Art and sound

None: the barriers keep their model.

## What step 1 measured (T-328)

- **The road is identical:** seeds 7, 1234 and 98765, 30 000 studs each, 548 sections, every road field the same. A permanent check (`SplineGenTests`) lays each seed with no dressing and finds the same road, unrailed.
- **Barriers: 539 of 548 sections the same.** The 9 that differ are all at tight cliff edges: the dressing reads the drop from the gravel's real lip, where the old code read it from the grass edge before the gravel narrowed it, so a few barriers there end sooner (one leaves a 16-stud gap). The user accepted this (DECISIONS.md, 2026-11-19).
- **How it is wired:** `SplineGen` calls an optional `dress` hook on each accepted section, after it is final and before it is laid; `SplineSequence` attaches `RoadDressing`, and tests that need barriers attach it themselves. Turn previews are never dressed. The carve's old guard against a rail on its inside went with it (a rail needs falling ground, a carve rising ground; `SplineGenTests` checks no carve sits on a railed side). The planner reads the drop for its own choices with `Config.Spline.Terrain.Drop*` and `TightFallDrop`, the dressing with `Config.Dressing.Barrier`.

## What step 2 measured (T-334)

- `Config.Dressing.Barrier.HairpinRunOut` = 15 (proposed, to tune with the user). A tight bend's window runs 15 past its end, not 60, and a railed bend's tightness carries across a section's end.
- Six seeds, 30 000 studs each: rail past a railed hairpin's exit, median 113 -> 105, mean 163 -> 127; total rail 53 589 -> 51 223 studs. Where the run-out alone carried the rail it now ends about 15 past where the bend straightens (seed 2024's hairpin at 9 004: 325 -> 59 past the exit).
- Where a rail still runs on past a hairpin, another rule carries it: a cliff (40+ drop) just after, the next corner's falling outside, or the next tight bend of an S. Shortening those would change those rules, which is the user's call.
- `SplineGenTests` check 7: with the corner and cliff rules off, every railed hairpin side on seed 2024 ends within `HairpinRunOut` (+ a sample) of where the bend straightens (at most 11.6 studs).

## Testing

- **Step 1 is a move, so it's proved by sameness:** for at least three seeds over 30 000 studs, every section's road (centreline, runoff, edges, gravel) and every barrier run are identical before and after (a test compares them). The existing rail, grove, grind and off-road tests all pass.
- The planner's time per section, before and after (it should drop a little, with no dressing in its previews).
- **Step 2:** on hairpins over several seeds, the rail length past each hairpin's end before and after, and a lane drive through a hairpin with a drop.

## Open questions

- Step 2's run-out length: 15 studs is a starting point (proposed), tuned with the user in a lane.
