# Feature: Tight hairpins

**Status:** specced, waiting on T-326. **Owner task:** none yet.

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
- **Turnaround radius:** about 40 studs to the centre line (an inside edge radius of about 15), against today's tightest 70 (`Config/Spline.MinRadius`). Step 1 measures what the car can actually get round, and the radius is set from that.
- **The island:** at least about 10 studs of ground between the two road edges at its narrowest, widening away from the tip. The legs run side by side for at least about 120 studs before they part.
- **Height between the legs:** set by the face's grade, within what a bank between them can take at the steepest slope the ground allows, so the island is a bank, never a wall or an overhang. Where the face is too steep or too gentle for that, no tight hairpin is laid there.
- **How often:** rare, about one every 4 000 to 6 000 studs on steep faces, and never within about 1 500 studs of another.
- **Barriers:** the outside of the turnaround and the downhill edge of the lower leg take rails as any hairpin with a drop does. The island side takes none, as on the photo's inside.

## Server and client

As for the rest of the road: the server lays it, the clients replay it from the section. The island's shape goes with the section, so every device draws the same ground.

## Contracts

The section may carry a new kind of bend (a tight hairpin template) and the island's shape. Recorded in `CONTRACTS.md` with the code if the section format changes.

## Platform risks

None.

## Art and sound

None new.

## Testing

- **Step 1:** the car driven round turnarounds of several radii (35 to 70 studs) on a test pad, by drift and by grip: the tightest it gets round without spinning out or stopping, and at what speed.
- **Step 2:** over several seeds, every tight hairpin laid: its radius, the island's narrowest width, the height between the legs, and the island's steepest slope. No ground through the tarmac and no gap at an edge (read off the ground every few studs along both edges and the tip). A real Studio drive round one, and an F2 teleport to it for the user.
- The existing road, ground and hairpin tests still pass, and the planner's time per section stays near today's.

## Open questions

- The turnaround radius, from step 1's numbers.
- How often they come (rare, proposed).
