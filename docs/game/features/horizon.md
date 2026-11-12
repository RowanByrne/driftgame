# Feature: The mountain horizon

**Status:** specced, waiting for the user's OK on the plan (`T-148`). **Owner task:** none yet.

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

## Open questions

- None blocking. Colours and heights are first guesses to judge in the lane.
