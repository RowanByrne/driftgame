# Feature: One continuous mountain

**Status:** specced, waiting for the user's approval (from message `C-9683fd`). **Owner task:** none yet.

## Goal

The user, 2026-11-13: *"we need to sell the idea that we are actually on a endless mountain road here -
that means we can't be constantly looking at the inside of cliffs ... right now i can go into a
switchback and be staring at a mountain lol."* Their idea: let the road get much wider at times,
and have the generator "send out horizontal checks" before sharp turns so the upcoming road doesn't
make unnatural geometry. They asked for a sanity check and better methods.

## What's wrong today

The scenery is a **ribbon that follows the road**: each section draws its own rock face on one side
and its own drop on the other, a fixed distance out. Nothing exists between two legs of road. So:

- Between a leg and the one below it is haze, with each leg's rock and cliff floating as separate
  slabs (the user's screenshots 2 and 3: "mountain" on one leg, "cliff" on the other, nothing
  joining them).
- At a hairpin the ribbon's rock face swings round with the road, so you drive straight at a wall
  that a real mountain wouldn't have there (screenshot 1).

## The recommendation

The user's two ideas help, but neither fixes the cause. The fix is to make the mountain **one
surface in the world** and cut the road into it:

1. **One mountain surface.** The ground is a single height function of world position: falling
   steadily along the fall line (`mountain-direction.md`), with broad, seeded ridges and gullies
   across it. The road is cut into it: where the surface is above the road you get a rock face (a
   cutting), where it is below you get a drop or an embankment. Because every leg is cut into the
   same surface, the ground between a leg and the one below is real mountainside, and a hairpin's
   outside opens onto the slope and the valley instead of a wall.
2. **Fit the turns to the mountain (the user's "horizontal checks").** Before laying a hairpin or
   switchback, the generator samples the surface sideways across the turn and ahead, and only takes
   a turn that keeps the cutting and the drop within limits: a hairpin goes where the slope can hold
   it, and a turn that would aim the road into the hillside is refused or eased. This is where the
   user's idea fits, and it's cheap: a few dozen height samples per candidate turn.
3. **Wider road where it helps.** Real switchbacks are widened at the turn, and the odd wide
   stretch (a lay-by, a run-off apron) reads well. Width varies smoothly from today's width up to
   about double, mostly at hairpins. On its own it doesn't fix the view, so it comes last and is
   optional.

## How it plays

You drive the same road, with the same feel. Looking out from a switchback, you see the leg below
you lying on the same hillside, the slope running down between them, and the valley beyond.
Cuttings rise where the road digs into the hill, and drops fall where it hangs out over it. You
rarely drive into a wall at a hairpin.

## Left out

- Hedges (they come back later as decoration only), new art, trees placed on the open slope
  (follow-up), the far horizon.
- Any change to the car, the drift or the score.

## Rules and numbers

First guesses, all in `Config.Spline` (a `Mountain` block):

| | Start | Notes |
|---|---|---|
| Slope across the fall line | 25 to 35° average | Steep enough for cuttings and drops, gentle enough for legs to share it |
| Ridges and gullies | 300 to 900 studs across, ±40 studs | Seeded noise; gives cuttings and embankments their variety |
| Drawn out to | 400 studs either side of the road | Far enough to meet the next leg; past it the horizon takes over |
| Cutting height | capped by the turn check | So a hairpin never sits in a 200-stud trench |
| Road width | 1x to 2x today's, eased | Widest at hairpins |

- **Seeded and replayed:** the surface is a pure function of the seed and world position, so every
  device computes the same mountain; nothing extra goes over the wire.
- **The car still drives on the maths:** walls are where the cutting is; the drop is where the
  ground falls past the lip.
- **Budget:** still within eight meshes. The wider ground costs triangles; the build measures it and
  coarsens far ground first.

## Server and client

- **Server:** lays the road on the surface, runs the turn checks.
- **Client:** draws the surface around the road from the same function.

## Contracts

The section data may lose fields it no longer needs (the per-section edge kinds become derived from
the surface); the build says what changes in `CONTRACTS.md`.

## Testing

- Unit tests: the surface is identical on server and client; no point of a leg's drawn ground pokes
  through another leg; turn checks refuse turns into the hillside; no-crossing holds.
- Measured: how often you face a wall within 150 studs ahead at a hairpin (before/after), triangles
  and build time per chunk, frame time.
- The user drives it in a lane before it merges.

## Open questions

- Whether step 3 (wider road) is still wanted once steps 1 and 2 are in.
