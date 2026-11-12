# Feature: The mountain horizon

**Status:** building (`T-150`): step 1, the ridges and the snow peak (`T-153`), and step 2, the valley floor (`T-157`), in the lane. **Owner task:** `T-150`, lane 2.

## Goal

The user, 2026-11-12, after the day-night cycle went in (`day-night.md`): *"skybox is solid, but i
think we need to have a sort of horizon effect painted in, instead of being endless void. so a
horizon painted with japanese mountains and stuff if that makes sense?"*

Asked how to draw it, they chose **low-poly ridges built in code** over painted images
(DECISIONS.md, 2026-11-12). So the mountain road sits in a range of mountains: ridge behind ridge to
the horizon, fading into the haze, with one tall snow-capped peak standing out, and a valley floor
far below the cliffs.

## How it plays

1. Wherever you are on the road, mountains ring the horizon in **three layers**: dark green
   forested ridges nearest, blue-green ones behind, pale far peaks behind those.
2. **One tall snow-capped peak** stands above the far layer, a landmark, in one fixed direction.
3. **You never reach them.** However far you drive, they stay on the horizon (they follow you,
   the farther layers more slowly, so they shift a little as you go, like real distance).
4. **Look over a cliff** and the haze thins out onto a valley floor far below, not empty sky.
5. **They follow the day-night cycle** by themselves: bright and hazy by day, warm and dark against
   a sunset, black silhouettes against the night sky.

## Left out

- **Painted images** (the other way to draw it, not chosen).
- **Anything you can drive to or near:** trees on the roadside, villages, temples, torii, power
  lines, rivers. The horizon is backdrop only.
- **Weather and moving clouds** beyond what the sky already has.
- **Final art.** Programmer colours, chosen to sit with the sky; the look is judged in the lane.

## Rules and numbers

All numbers in a new `Shared/Config/Horizon.luau`.

| | Start | Notes |
|---|---|---|
| Near ridges | ~2 500 studs out, 150–400 studs tall, dark green | Follow the camera fully |
| Middle ridges | ~5 000 studs out, 300–700 tall, blue-green | |
| Far peaks | ~9 000 studs out, 600–1 400 tall, pale blue-grey | |
| The snow peak | ~11 000 studs out, ~2 400 tall, snow on its top third | One fixed bearing |
| Parallax | The far layers trail the camera by a fraction of its movement | So they shift slightly, never get closer |
| Valley floor | ~500 studs below the road's start, dark green | Follows the camera; its edges are lost in the haze |

- **Low poly, built from numbers:** each ridge line is a seeded run of peaks and saddles, faceted
  and flat-shaded (`ART-DIRECTION.md`: very low poly is fine for anything the car doesn't touch).
- **The haze does the depth:** each layer is lighter and bluer than the one in front, and the
  atmosphere fades them further, so the day-night cycle relights them for free.
- **Cheap:** a few hundred parts or triangles for the lot, none of which collide or are queried.
  The road keeps its meshes: the road uses six of the eight `EditableMesh`es a client may hold
  (`spline-road.md`), so the horizon uses at most the two left, or plain parts.
- **On the client only.** The same on every client (seeded), nothing sent.
- **Only in the endless run.** The garage, the playground and the track keep their own
  surroundings.

## UI

None.

## Server and client

Client only. The server knows nothing about it.

## Contracts

None.

## Analytics

None.

## Monetization

None.

## Platform risks

None. Generic mountains; the snow peak is a mountain, not a copy of a real one's outline.

## Art and sound

No art assets: geometry in code, colours in config.

## Testing

- **In the lane:** drive a long run and measure that every layer stays at its distance from the
  camera; count parts and triangles; frame time with and without it; check nothing collides or is
  hit by the car's queries.
- **Review shots:** noon, sunset and night from the same spot on the road, plus one looking over a
  cliff, at most 3 per round, for the user to judge.

## As built (step 1, `T-153`)

- `Shared/Horizon` is the shapes, pure (triangles from the seed); `Drift/HorizonView` draws
  them; `DriftController:UseSpline` makes one with the run's road and takes it down with it.
  Every number in `Config.Horizon`. Unit test: `Tests/HorizonTests` (22 checks).
- **Plain wedge parts, not a mesh:** one mesh may be at most 2 048 studs across (measured:
  "Mesh extents size too large"), so each triangle is two wedges; 237 triangles, 474 parts.
  The road's eight-mesh budget is untouched.
- **Each layer is welded to one invisible anchor** and only the anchor moves: moving all 496
  parts each frame cost 0.33 ms; the horizon's whole update now costs 0.10 ms a frame
  (median while driving, 0.39 worst). Welded to an anchored part, the parts survive the fall
  height. Built 120 parts a frame at the run's start, 5 ms in all.
- **Parallax the right way round:** the nearest layer trails the camera most (eased over 3 s,
  never more than 250 studs behind), the middle 1.5 s, the far 0.6 s, and the snow peak not
  at all, so it holds its bearing. The spec had the far ones slower; that would make them
  shift more than the near ones, which reads as nearer.
- **Nearer and lower than the spec's first guesses,** measured in the lane:
  - The chase camera shows only about 8 degrees of sky above level. At the spec's sizes
    (9-12 degrees up) the ridges filled the whole sky like a wall. Now the ridges stand 2-5
    degrees up and the snow peak's summit 5.5, with sky above.
  - The day's haze washed everything past 2 500 studs to one pale blue. Now: near 2 400
    studs (70-190 tall), middle 3 200 (120-250), far 4 500 (180-370), the snow peak 6 000
    (580, snow from about 350 up), and the near colours are darker so the haze grades them
    rather than erasing them.
  - The nearest faces stay beyond the road drawn ahead (1 600) wherever the road could be,
    even at the near layer's full lag (unit test).
- **They rise and fall with the road by three quarters** of the camera's height above the
  road's start (eased over 2 s): all of it would pin them in the frame, none would swing them
  4 degrees on a 160-stud climb. So climbing still sinks them a little.
- Nothing collides, is touched, is hit by a ray or casts a shadow (measured: 0 of 478).
- **Looking over a cliff** showed the near ridges' lower faces through the haze, down to 560
  below the road's start, until step 2's valley floor.

## As built (step 2, `T-157`)

- **The valley floor:** nine dark green plates, 1 800 studs square each (a part is at most
  2 048), 5 400 across in all, their top 500 below the road's start. Numbers in
  `Config.Horizon.Floor`.
- **Welded to the near layer,** so it moves with those ridges: its edges stay hidden behind
  them, and it costs nothing more a frame. The near and middle ridges' feet sink into it.
- **It rises with the road** like the ridges, and stays below every cliff's face: at most 380
  below the road's start against cliffs drawn down to 240 (unit test).
- Measured in the lane: every downward sight line from the camera, all the way round, from
  straight down to 12 degrees down, lands on it (1 440 of 1 440); shallower ones meet the
  near ridges. At noon it reads mostly as haze from the road; the look is the user's.

## Open questions

- None blocking. Colours and heights are first guesses to judge in the lane.
