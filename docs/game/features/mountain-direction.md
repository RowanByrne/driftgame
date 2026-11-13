# Feature: The mountain has a direction

**Status:** specced, waiting for the user's approval (`T-165`). **Owner task:** none yet.

## Goal

The user, 2026-11-13: *"I want to create the understanding that the mountain goes uphill on one side,
and downhill on the other. We can totally change the direction that the player is traveling with a
switchback or hairpin, but don't want to do it so frequently that we run into this issue: right now,
you can be going one way with the cliff on your left, and then in just one quick turn, the cliff is
on your right. I want to solve that and ground the setting better."*

Today the uphill side is picked per side of the road (`mountain-road.md` "Where each edge goes") and
swaps at random every 900 to 2 600 studs, while the road wanders within 115° of its start heading.
Nothing ties the cliff to the world, so it can sit on the wrong side after a turn. This feature gives
the mountain a fixed direction in the world, and makes the road travel down it.

## How it plays

1. The mountain has one **fall line**, fixed in the world for the whole run: uphill one way (call it
   north), the valley the other (south).
2. **The cliff side follows from the heading.** Driving across the slope eastward, the mountain is on
   your left and the drop on your right; after a hairpin back west, the mountain is on your right.
   The edge sides are never picked at random any more.
3. **The run is a descent.** The road is made of long **legs** across the slope, joined by
   **hairpins** (and the odd switchback of tighter bends) that turn it back the other way. Over a run
   it works its way toward the valley, and its height drops with it.
4. **The local grade still mixes up and down,** as it does now (the user, 2026-11-13: "I do like the
   current mix of uphill and downhill"). Only the long-run trend points down.
5. **Turning back is rare and deliberate:** the road reverses only through a hairpin or switchback at
   the end of a leg, never with a quick ordinary bend, so the cliff can't swap after "one quick turn".

## Left out

- **Ascent and traverse.** Planned for, not built: the direction is one setting per stretch
  (`descent`, `ascent`, `traverse`) so a later change can switch it for sections of a run. Only
  `descent` is used now.
- **The valley floor and distant mountains** you'd see below: `horizon.md` and the next art work.
  The haze past the cliff stays.
- **Road stacked over road** (seeing the leg below you): the no-crossing rule still keeps legs apart
  in plan.
- **Any change to how the car drives,** the score, the edges' looks or the K-rails' rules.

## Rules and numbers

Starting values, all in `Config.Spline` (a `Mountain` block), numbers not code.

### The fall line

- Chosen once per road, from its seed, by the server; sent with the road and replayed by clients
  like everything else (`RoadSpline`). Starting value: the fall line points along the start heading
  turned 90° (so the first leg runs across the slope).
- **Uphill side** at any point = the side of the road the uphill direction is on: the sign of the
  road's right vector dotted with uphill. Heading within `AlongFallLine` (30°) of straight up or down
  the slope counts as neither: the side holds what it was (hysteresis), so a wiggle can't flip it.

### Legs and turnarounds

| | Start | Notes |
|---|---|---|
| Leg heading | Across the slope, tilted `LegTilt` 10 to 25° downhill | A leg's own bends stay within `LegHeadingLimit` (60°) of it, so no ordinary bend reverses the road |
| Leg length | 1 200 to 3 000 studs | Then a turnaround |
| Turnaround | A hairpin (most), or a switchback of two tight bends | Turns the road onto the next leg, the other way across the slope |
| Cliff swap | Through the turnaround only | Edges either side of the hairpin pass through the existing hedge-both-sides transition |
| No-crossing | As now | A new leg must clear the one above it; the build measures how often a turnaround is refused and the road extends the leg instead |

### Height

- The height band (`MinHeight..MaxHeight`, ±160 studs today) **moves with the road**: its centre
  follows the descent, dropping `DescentRate` (start: 1 stud per 25 of road, about 2.3° net) as the
  road advances, so local grades still go up and down but the trend is down.
- Equivalently, height tracks how far the road has gone down the fall line; the build picks
  whichever keeps the grade rules (`MaxGrade` 8°, `MaxGradeRate`) and measures the net drop per
  1 000 studs.
- For `ascent` the sign flips; for `traverse` the band stays put, as today.

### Edges

- `mountain-road.md` "Where each edge goes" changes: **uphill side comes from the heading**, not
  from `UphillStretch` and a random swap. `UphillStretch` goes. Rock, hedge, cliff and K-rail odds
  are unchanged.

## UI

None.

## Server and client

- **Server:** chooses the fall line, the legs and the turnarounds with the curve, as now.
- **Client:** replays them; nothing chosen on the client.

## Contracts

- `RoadSpline` road data gains the fall line (a heading) and the direction mode (`CONTRACTS.md`, same
  commit). Section edge data is unchanged in shape.

## Analytics

None.

## Monetization

None.

## Platform risks

None.

## Testing

- **Unit tests** (spline tests): over long seeded roads, the uphill side always matches the heading
  against the fall line (outside the hysteresis band); the cliff swaps only inside a turnaround; no
  ordinary bend turns the heading past `LegHeadingLimit`; net height drops by roughly `DescentRate`;
  grade rules and no-crossing still hold; server and client replays match.
- **Measured in the lane:** legs per 10 000 studs, cliff swaps per 10 000 studs (before and after),
  turnarounds refused, generator time per section, and whether the road ever boxes itself in over
  20 seeds.
- **Then the user drives it there,** before it merges.

## Open questions

- None blocking. The numbers are first guesses to drive and tune.
