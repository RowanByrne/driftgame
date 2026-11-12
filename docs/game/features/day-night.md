# Feature: Sky and the day-night cycle

**Status:** specced, waiting for the user's OK on the plan (`T-143`). **Owner task:** none yet.

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
- **Night is readable:** the measured brightness of the road at midnight stays above a floor the
  build sets in a lane, so the drift is never driven blind.
- **Headlights** are lights in the car's headlight parts (a spotlight down the road), on from dusk
  to dawn. The garage room keeps its own lighting.
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

## Open questions

- None blocking. The look of each keyframe is the user's to judge from the lane.
