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
- Nothing goes inside the car: SpotLights in parts of the client's own, moved with the car each
  frame. A SpotLight reaches 60 studs at most, and the user wanted 2-3x that, so besides one
  beam per lamp the throw is two flat strips hung high over the road ahead, lit from underneath
  (a SurfaceLight lights from its whole face: no cone, no gap): a wide one to 105 studs and a
  narrow one to 165, so the light is brightest near and thins and fades as it goes. Spotlights
  hung down the road were tried first and made a chain of separate pools (the user: "quite off
  with the repeating cones of light"). The pop-up pods open and
  the headlight and tail-lamp lenses glow Neon while they're on.
- Off in the garage room (inside its bounding box), pods down.
- Cost: no measurable frame time (5.6 ms average with them on and off).

## Open questions

- None blocking. The look of each keyframe is the user's to judge from the lane.
