# Feature: The mountain has a direction

**Status:** building (`T-166`): steps 1 and 2 built in lane 1, being driven. **Owner task:** `T-166`.

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
6. **Short detours are fine** (the user, 2026-11-13: "it's okay for the road to quickly invert back
   the way it came and then continue back to the proper direction, as long as that flip flop happens
   over a short distance, like a double hairpin. it's also okay for the road to run sideways to the
   proper direction for short to medium distances"):
   - **A double hairpin:** two hairpins close together, so the road runs back the way it came for a
     short stretch, then carries on its leg. The cliff swaps for that stretch and swaps back, because
     it follows the heading.
   - **Running sideways:** the road may run straight up or down the slope for a short to medium
     stretch before turning back onto its leg. The cliff side holds through it.

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
| Double hairpin | `DoubleHairpinChance` 0.15 per leg; the reversed stretch 150 to 500 studs | Then the leg carries on in its own direction |
| Sideways stretch | `SidewaysChance` 0.2 per leg; up or down the slope for 300 to 1 200 studs | Bends inside it may go past `LegHeadingLimit`, never past 120° off the leg; the side holds (hysteresis) |
| Cliff swap | Through a turnaround or a double hairpin only | Edges either side of the hairpin pass through the existing hedge-both-sides transition (since T-189: no hedge; both sides change at one point, mid-turn, `mountain-road.md`) |
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

## As built (step 1, T-167)

The fall line, the legs and the turnarounds, and the descent.

- **The plan** (`Road/SplineGen`): each leg is a stretch of the old random sections, kept
  within `LegHeadingLimit` (60°) of the leg's heading downhill but only `LegUphillLimit` (30°)
  uphill, and leaning back toward the leg's own line (`LineReach`), so a leg keeps its level on
  the slope. Turnarounds, double hairpins and the bends in and out of a sideways stretch are
  **planned turns**, built to land exactly on the next heading; when the road is more than
  `TurnWindow` (20°) off its leg first, a gentle bend brings it back. A planned turn that would
  crowd old road is refused and retried `RetryAfter` (120) studs on: 0 refused in 20 roads of
  30 000 studs.
- **Sideways climbs are off** (`SidewaysUpShare = 0`): at 0.3 a sideways climb ran into the leg above
  and boxed the road in on 2 seeds of 40. Sideways stretches go down the slope only, and their
  bends stay within 25° of it (inside `AlongFallLine`, so the side will hold through them).
- **The descent** is the moving band: its centre drops `DescentRate` per stud of road.
  Measured: 36.4 studs per 1 000 (the band is planned per section, so a little under 40).
- **Measured** over 40 roads of 30 000 studs: no road boxed in; per 10 000 studs 3.0 legs,
  2.7 turnarounds, 0.5 double hairpins, 0.7 sideways stretches; the road turns back across
  the slope only inside a planned turn (228 of 228 changes); 0.16 ms a section, worst 2.7 ms.
- **Climbs** (the user's call, DECISIONS.md 2026-11-13): the band's centre drops to
  `DescentFloor` (-280), then climbs at `ClimbRate` (1 in 10) to `ClimbTop` (0) and drops again,
  so a run of hours stays above Roblox's fall-kill height (Y -500): a 150 000-stud road's
  lowest point is Y -396. The descent itself measures 36 studs per 1 000.
- **No hairpin in the first 1 500 studs** (`Bends.Hairpin.minS`), as before.

## As built (step 2, T-168)

- **The side from the heading** (`_terrain`): sampled every 4 studs; inside `AlongFallLine` the side
  holds; coming out on the other side, the edges change at that point, with hedge both sides
  through the band. `UphillStretch` is gone. Measured over 10 roads of 10 000 studs: wrong side at
  0 of about 17 600 points; 4.1 changes a 10 000 studs (3.5 before), all inside planned turns.
- **Low past a turn** (the user, 2026-11-13): after the mountain changes sides the uphill side
  stays hedge for `Terrain.UphillLowAfterTurn` (400) studs, since the leg you came down is right
  above. The drop side keeps its cliff. **Replaced by T-189** (DECISIONS.md 2026-11-13): no hedges; the edges change sides at one point, where the heading crosses the fall line, and the uphill side is rock right away, drawn low where the leg above leaves no room (`mountain-road.md` "One mountain through the turns").
