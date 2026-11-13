# Feature: Sky and the day-night cycle

**Status:** building. Plan approved 2026-11-12 (`T-144`); step 1, the cycle and its looks, is `T-145`; step 2, the headlights, `T-146`. **Owner task:** `T-144`.

## Goal

The user, 2026-11-12, after the mountain road (`mountain-road.md`) went in: *"add a skybox that
fits, and a day night cycle. 2 mins each, with nice cinematic sunrise/sunsets."*

The mountain road gets a sky over it, and time passes while you drive: a day, a sunset, a night, a
sunrise, round and round. The sunrise and sunset are the moments to look good in.

## How it plays

1. **Day** lasts 2 minutes: a clear blue mountain sky with soft clouds, the sun crossing it.
2. **Sunset**, about 20 seconds at the end of the day: the sun sinks low and warm, the sky and the
   haze over the cliffs go orange and pink, long shadows, a soft glow round the sun.
3. **Night** lasts 2 minutes: a deep blue moonlit sky with stars and the moon. Dark, but the road,
   the grass and the edges are still easy to read.
4. **Sunrise**, about 20 seconds, the sunset's colours in reverse, cooler and paler.
5. **Headlights** come on as the sun sets and go off as it rises.
6. **Every player sees the same time.** Joining mid-night lands you in the night.

## Left out

- **A picture skybox.** A skybox made of six images can't change with the time of day: it would
  cut from a day picture to a night picture. So the sky is **Roblox's own sky**, which moves its
  sun, moon, stars and colours with the clock, tuned with its atmosphere, clouds and colour
  grading. A painted horizon (mountain silhouettes) can come with the scenery feature.
- **Weather:** rain, fog banks, wet roads.
- **Scenery** past the edges: still the next feature (`mountain-road.md` "Left out").
- **Street lamps or lit buildings** at night.
- **A choice of time:** no setting to stop the clock or pick a time.

## Rules and numbers

All numbers in a new `Shared/Config/DayNight.luau`.

| | Start | Notes |
|---|---|---|
| Day | 120 s | From sunrise's end to sunset's start |
| Night | 120 s | From sunset's end to sunrise's start |
| Sunset, sunrise | 20 s each | So a whole cycle is 280 s |
| Clock | From the server's time (`GetServerTimeNow`) | Every client works the same time out itself; nothing is sent |

- **A set of keyframes,** each a look: clock time, ambient and outdoor ambient, brightness,
  atmosphere (density, haze, colour, decay, glare), cloud cover and colour, colour correction
  (tint, contrast, saturation), bloom and sun rays. Between keyframes everything blends smoothly.
  At least: noon, golden hour, sunset, dusk, night, dawn, sunrise.
- **The sun moves faster through the horizon** than across the day, so the 20 seconds of sunset
  are spent with the sun low, where it looks best, not crossing the middle of the sky.
- **The cliffs' haze follows the sky.** The foot of each cliff fades into the atmosphere's colour
  at that moment, so it doesn't glow pale at night (today it is a fixed colour in the road mesh,
  `Config.Spline` `HazeColour`).
- **Night is readable:** the road at midnight stays easy to read, so the drift is never driven
  blind. It is judged by eye, in the lane: a playtest cannot read a frame's pixels (measured:
  a `CaptureService` capture cannot be opened as an `EditableImage`), so there is no number to
  hold it to. The night's `OutdoorAmbient`, moon `Brightness` and `Exposure` are what keep it lit.
- **Headlights** are a spotlight down the road from each headlight, on from dusk to dawn. They
  are not inside the car (DECISIONS.md 2026-11-03: the car holds no Light), but ride its nose.
  The garage room keeps its own lighting.
- **It runs everywhere,** not only in the endless run, since Roblox has one sky per server. The
  garage room is lit by its own lamps and is unaffected.

## UI

None.

## Server and client

- **Client:** works out the time from the server's clock and sets the lighting. Nothing is sent.
- **Server:** nothing.

## Contracts

None. The lighting is set by one client controller.

## Analytics

None.

## Monetization

None.

## Platform risks

None. No outside assets: Roblox's own sky, clouds and effects.

## Art and sound

Lighting only, from Roblox's own sky, atmosphere, clouds and post effects. No new art. Night
ambience sounds are left out.

## Testing

- **Unit test:** the clock maps to the right phase and blend at each boundary, and two clients at
  the same server time get the same look.
- **In the lane:** run the cycle sped up and record each keyframe's values; measure the road's
  brightness at midnight; check the headlights switch at dusk and dawn; frame time with the post
  effects on.
- **Review shots:** noon, sunset, night and sunrise from the same spot on the road, at most 3 per
  round, for the user to judge the look.

## As built (step 1, `T-145`)

- `Shared/DayNight` is the maths, pure; `Controllers/SkyController` sets the client's Lighting
  from it 30 times a second; every number is in `Config.DayNight`.
- Nine keyframes: morning, noon, afternoon, golden hour, sunset, dusk, night, dawn, sunrise.
  A keyframe sits at a fraction of its phase, so a phase's length can change alone.
- The clock runs a monotone cubic through the keyframes' clocks: 0.093 h/s across the day,
  0.04 h/s through the sunset and sunrise (17:36 to 18:24, 5:36 to 6:24), and the sun's speed
  never jumps (unit test).
- Roblox's sun is on the horizon at 6:00 and 18:00 (measured in the lane, latitude 41.7).
- The sky is Roblox's own `Sky` (stars and moon), an `Atmosphere`, Terrain `Clouds`, and a
  colour grade, bloom and sun rays of the controller's own. `GlobalShadows` is turned on.
- The cliffs' haze is a colour id in each road chunk's mesh, rewritten in place when it has
  moved 2/255.
- Cost: the sky's step is 0.17 ms at worst, with the cycle run 70 times as fast.

## As built (step 2, `T-146`)

- Headlights come on 60% into the sunset (132 s, the sun just under the horizon) and go off
  halfway through the sunrise (270 s), fading over 0.6 s. Every client switches every car at
  the same moment.
- Nothing goes inside the car: two SpotLights per car (range 60, 70 degrees, tilted 6 degrees
  down) in parts of the client's own, moved to the nose each frame. The pop-up pods open and
  the headlight and tail-lamp lenses glow Neon while they're on.
- **Longer beams were tried and taken out** (2026-11-12, the user: "no this just isn't working.
  revert this back to the way it was with the initial short range headlights for now. i will
  revisit later"). A SpotLight stops at 60 studs. Spotlights hung down the road ahead made a
  chain of separate pools; SurfaceLight strips hung over the road made one throw, but its edges
  still showed (a light stops dead at its Range; at 55 that softened but did not go). Whatever
  comes next for a longer throw has to beat both.
- Off in the garage room (inside its bounding box), pods down.
- Cost: no measurable frame time (5.6 ms average with them on and off).

## Clouds (`T-163`)

The user, on the first build: "why are the clouds all blurry like that?" Roblox's clouds are soft
by design (and softer at low graphics quality); the daytime haze washed them out further. Tuned,
not replaced: daytime `AtmosphereHaze` 1-1.4 down to 0.3-0.5, `CloudDensity` 0.6 up to 0.85-0.9 by
day and 0.7-0.8 at the sunsets and night, whose haze was kept.

## The low moon (`T-179`)

The problem (measured, `T-178`): the headlights are on for 138 s of the 280 s cycle, and for 47 s
of that the moon was under 20 degrees up (29 s under 10, lowest 0.6 at a 1 s sample), so a
5-stud car threw its shadow 30 to over 500 studs, onto far rock faces.

- **Roblox's moon mirrors the sun:** its height is always the sun's, negated (measured in the lane,
  latitude 41.7), so both cross the horizon at 6:00 and 18:00. The moon cannot be kept high
  through dusk without the clock jumping, so its light is faded instead.
- **The direct light fades with the height of whichever is lighting the world:**
  `Lighting.Brightness` is the keyframe's times a smoothstep, `Config.DayNight.LightFade`. The
  moon gives none under 12 degrees and all of it from 28; the sun fades over only its last 2
  degrees (the last 4 s of the sunset, the first 4 s of the sunrise), so the golden hour's long
  shadows stay. Both give none on the horizon, so the hand-over from sun to moon cannot pop. The
  sky, the ambient light, the moon and the stars are untouched; the clock, the cycle and the
  sun's path are as before.
- **Measured, the full cycle sampled every second in a playtest:** of the 138 s with headlights
  on, 33 s have no direct light (from the lights coming on to the moon at 12 degrees, about 15 s,
  and the same before dawn), lit by the ambient and the headlights. The lowest the moon lights
  anything from is 12.7 degrees, and the longest car shadow is **22 studs** (it was 513), faint
  there: 18 at a tenth of the moonlight, 14 at half. The brightness never moves more than 0.82 a
  second (the sun's 4 s fade). Unit test: no direct light at the horizon, none under the moon's
  `From`, all of it at `To`, and never less as either climbs.

## Open questions

- None blocking. The look of each keyframe is the user's to judge from the lane.
