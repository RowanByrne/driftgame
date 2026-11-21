# Feature: Tight hairpins

**Status:** step 1 done (T-330); step 2 (T-333) done: the shape and its island; step 3 (T-337): descents traverse in shorter legs, and a leg ending on steeper ground ends in a tight hairpin (2026-11-20). **Owner task:** T-329.

## Goal

Now and then the mountain road folds back on itself in a true touge hairpin: the two legs run side by side, one above the other, with only a narrow strip of land between them, joined by a turnaround much tighter than any bend the road lays today. These are the corners a drift game on a mountain pass is about.

The user, 2026-11-19 (C-fec3a8), with a photo of a Japanese pass where the legs nearly touch and a thin planted strip separates them: *"I want to be able to have hairpins that are this tight. it's okay if they are pre-planned to ensure that the tiny part of land between the uphill and downhill legs are formed correctly and join neatly."*

## How it plays

1. Descending (or climbing) a steep face, the road straightens into a leg, then folds back in a tight turnaround and runs back along the face just above or below itself.
2. Between the two legs is a narrow island of ground: a bank sloping from the upper leg down to the lower one, meeting each road edge cleanly (no gaps, cliffs, trenches or ground poking through the tarmac), narrowing to a rounded tip at the turnaround.
3. The turnaround is tight enough that it must be drifted or taken very slowly. HAIRPIN AHEAD and the hairpin score events treat it as a true hairpin.

## Left out

- **Painted zebra stripes and signs** like the photo's: a later dressing step (`features/road-dressing.md`), offered once this plays.
- **Any change to the ordinary hairpins** the planner lays now: tight hairpins are a new, rarer kind next to them.
- **Two-leg stacks** (a tight hairpin straight into another): one at a time first.

## Rules and numbers

All starting values are proposed, to tune with the user in a lane.

- **Pre-planned, as a template.** The planner doesn't find a tight hairpin by search: when the ground ahead is steep and falling across the road's path, and the road has room, it lays a fixed shape (leg in, turnaround, leg out), sized to the ground, and the ground between the legs is shaped to fit that shape rather than read off the mountain.
- **Turnaround radius:** 40 studs to the centre line (an inside edge radius of 15), against today's tightest 70 (`Config/Spline.MinRadius`). Picked by the user on 2026-11-19 from step 1 (below).
- **The island:** at least about 10 studs of ground between the two road edges at its narrowest, widening away from the tip. The legs run side by side for at least about 120 studs before they part.
- **Height between the legs:** set by the face's grade, within what a bank between them can take at the steepest slope the ground allows, so the island is a bank, never a wall or an overhang. Where the face is too steep or too gentle for that, no tight hairpin is laid there.
- **How often:** rare, about one every 4 000 to 6 000 studs on steep faces, and never within about 1 500 studs of another. Swapped in for the road's own switchbacks (step 2) that gave only 1 in about 180 000 studs on descents, so the user chose to plan them into the road (step 3, DECISIONS.md 2026-11-20).
- **Planned into descents (step 3, T-337):** a descent crosses the face in legs up to 3 500 studs across (7 000 before), so a face comes down in more zigzags. Where a leg's hairpin site is on a hillside of 10 degrees or more, the road starts the shape its lead and side by side run short of the leg's end, so the turn lands where the survey put the hairpin; it may sit up to 35 studs off the hillside, as the ordinary descent hairpin may (`Range.TraverseTurnMaxOff`). Refused there, the road runs on and lays the ordinary hairpin. Over six seeds of 60 000 studs: 13 tight hairpins, every island 43 degrees at most.
- **Descent legs weave (step 3, after the user's send-back):** along each leg the road swings up and down the face either side of the surveyed line in S-bends, cutting into and building out from the hill (`Range.TraverseWeave`), gone before each hairpin. Over six seeds: 48% of the legs bend tighter than 500 studs (29% without), 24% tighter than 250 (12%).
- **Descents only, for now:** on seed 7 a climb's tight hairpin sent the rest of that climb into trenches walled on both shoulders (`Config/TightHairpin.OnClimbs`).
- **Barriers:** the outside of the turnaround and the downhill edge of the lower leg take rails as any hairpin with a drop does. The island side takes none, as on the photo's inside.

## Server and client

As for the rest of the road: the server lays it, the clients replay it from the section. The island's shape goes with the section, so every device draws the same ground.

## Contracts

A section tagged `"TightHairpin"` carries `th`, six numbers saying where the island is (`CONTRACTS.md`, `RoadSpline`). Every device makes the island from it.

## Platform risks

None.

## Art and sound

None new.

## Testing

- **Step 1:** the car driven round turnarounds of several radii (35 to 70 studs) on a test pad, by drift and by grip: the tightest it gets round without spinning out or stopping, and at what speed.
- **Step 2:** over several seeds, every tight hairpin laid: its radius, the island's narrowest width, the height between the legs, and the island's steepest slope. No ground through the tarmac and no gap at an edge (read off the ground every few studs along both edges and the tip). A real Studio drive round one, and an F2 teleport to it for the user.
- The existing road, ground and hairpin tests still pass, and the planner's time per section stays near today's.

## Open questions

- How step 3 plans them in: where on a descent, and how the road's route bends to make room.

## Step 1: what the car gets round (T-330, 2026-11-19)

`Tests/TightTurnTests` drives the real drift model round 180-degree turnarounds on a 50-stud road, 58 ways each (a grip line, a drift, the tail swung in early from the outside, a feint and flick), arriving at 60, 90 and 120 studs/s, flat and 12 percent downhill.

- **Every radius from 35 to 70 gets round, from every speed,** with the default car. Apex speed about 30 studs/s at 35, 34 at 40, 38 at 50, 46 at 70.
- **It always takes a slide.** No case, even 70, gets round on a grip line: slip peaks at 90 to 105 degrees, where the grip is a brake. Sliding is the only brake there is, and it curves the car toward the inside, so a slide begun too early pins it on the inside wall before the turn.
- **Other cars:** the Gripper and the Bruiser get round every case; the Slider missed two (from 120 into a 35 on the flat, and into a 40 downhill).
- **Test hairpins in the playground** (`drift-playground.md`): 35, 40, 50 and 70, spots `Turnaround35` to `Turnaround70`. The user picked 40 from these numbers.
