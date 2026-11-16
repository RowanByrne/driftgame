# Feature: Painted vista

**Status:** step 1 (the trial) in a lane for the user. **Owner task:** T-266 (step 1: T-267).

## Goal

The user, 2026-11-16, after asking how custom skyboxes are made: *"what's a creative way of doing
this that could work? could we create huge spheres and put artwork on the inside? could we put huge
parts in the distance with textures that get lit by the daylight? ... i want to achieve the effect
we have in the concept art."*

The view off the road should feel like the concept art (`ART-DIRECTION.md`, "Environment mood"):
ridge behind ridge fading into haze, and a sea of cloud filling the valleys below, all lit by the
time of day. It's built like a stage set. Painted ridge layers stand around the camera, and a layered
cloud sea lies below the road. Above them is **Roblox's own sky, unchanged**, so the day-night cycle
(`day-night.md`) keeps working and there's no "sunset at noon".

This brings back distant scenery, which `T-243` removed (DECISIONS.md, 2026-11-16: *"no need to
render anything physical in the distance"*). The difference is that it's a few painted panels
instead of built ridges. On approval, log the reversal in DECISIONS.md.

### Why not a skybox, a sphere, or built ridges

- **A painted skybox** has its time of day painted in, and Roblox can't blend two skyboxes, so the
  day-night cycle would jump from one picture to the next (`day-night.md`, "Left out").
- **A huge sphere with art inside** needs an inside-out mesh, and one mesh is at most 2 048 studs
  across (measured, `horizon.md`). That puts the sphere about 1 000 studs out, closer than the ground
  drawn round the car (1 100–2 100 studs), so it would hide the road ahead.
- **Built low-poly ridges** were `horizon.md` (removed). With no painted detail, and with the day's
  haze turning everything past 2 500 studs pale blue, they read as flat shapes, not the concept
  art. The painted layers below keep what worked there: the layers following the camera, the
  parallax, rising with the road, and costing almost nothing.

## How it plays

1. **Past the drawn ground, three painted ridge layers stand on the horizon** all the way round.
   The nearest are dark forested ridges, sharp and detailed. Behind them are blue-green ridges, and
   furthest out pale snow peaks, nearly lost in the haze. The haze does the fading: each layer's
   distance decides how much of it covers that layer.
2. **They stay distant, like real mountains.** They move with the car, so you never reach them. The
   nearest layer trails a little, so on a long bend the layers slide past each other.
3. **Below the road lies a sea of cloud.** It covers everything past the edge of the drawn ground.
   Look over a cliff and you see down onto it, drifting slowly. Where the real ground dips into a
   valley, the cloud fills it. Where the ground rises, the ground hides it.
4. **The time of day lights all of it.** Roblox's real sun lights the panels. At sunset, the
   ridges facing the sun turn warm and the ones with the sun behind them go dark, the way they do
   in `snow-pass-sunset.png`. At night they go deep blue under the moon. The cloud sea is tinted
   to match.
5. **If the art doesn't load,** you see what you see today: the sky and the drawn ground.

## Left out

- **A painted sky.** Roblox's own sky, clouds, sun, moon and stars stay as `day-night.md` set them.
- **A set of art per scenery** (autumn maples, cherry blossom, snow) that changes with where you
  are on the range. That comes later, once one set works.
- **Mountains you can reach.** The layers are scenery only (`T-241` dropped matching them to the
  real range).
- **Weather, waterfalls, and wisps of mist drifting across the road.**
- **The garage room,** which is lit by its own lamps and doesn't change.

## Rules and numbers

Starting guesses, to be measured and tuned in the lane, as `horizon.md`'s were. Every number goes in
`Config.Vista` (new).

### Ridge layers

| Layer | Distance | Top of the ridges on screen | Art | Trails the camera |
|---|---|---|---|---|
| Near | 2 400 studs | 2–4° above level | Dark forested ridges | Up to 3 s, never more than 250 studs |
| Middle | 3 200 studs | 3–5° | Blue-green ridges | 1.5 s |
| Far | 3 200 studs (measured: 4 500 washed out in the haze) | summit 8° (5.5° barely cleared the ground) | Pale snow peaks | 0.6 s, at most 120 studs |

- **Beyond the drawn ground:** the near layer stays further out than the ground's widest reach
  (2 100 studs today, `mountain-range.md`) at every Road ahead setting (`T-263`), even when it
  trails the car by the most it can.
- **Only a few degrees tall:** the chase camera shows only about 8° of sky above level
  (`horizon.md`, measured), so the ridges stand 2–6° up, with sky above them.
- **No bottom edge in sight:** each layer reaches down below the horizon into the cloud sea.
- **Rises and falls with the road by three quarters** of the camera's height above the road's
  start, eased over 2 s, as the horizon did.
- **Panels (as built in the trial):** each layer is a ring of flat panels, each under 2 048 studs
  wide (10 for the far layer). Each is an invisible part with the art as a `Decal` on its inner
  face, which the real sun lights, with a plain skirt below in the art's base colour. No mesh is
  uploaded. The normal map would need a MeshPart with a SurfaceAppearance; not tried yet.
- **The whole layer moves together:** each layer's panels are welded to one invisible anchor, and
  only the anchor moves, which measured 0.10 ms a frame for the horizon.

### Cloud sea

- **Three stacked layers,** 30 studs apart, the top one 150 studs below the road's start, and
  never nearer than 120 under the camera. They rise with the road by three quarters, like the
  ridges.
- **The top layer** is 5 × 5 parts of 2 048 studs, so it reaches past the ridge ring and its edge
  is never seen (3 × 3 showed its edge in the lane); the two under it are 3 × 3.
- **Seamless cloud:** a tiling cloud texture (`Texture`, 2 048 studs a tile: 1 024 read as a
  snowfield). The parts move in whole tiles, so the clouds don't slide when they follow the car.
  Each layer drifts about 2 studs a second, at a slightly different speed and direction.
  Transparency is 0.25, 0.4 and 0.6, top to bottom.

### Time of day

- **New keyframe values** in `Config.DayNight`: `VistaTint` (one tint for every layer, since the
  haze already handles distance) and `CloudSeaColour`. Every keyframe names them, which the
  existing unit test checks.
- **`SkyController` sets them** each step, from the same look it uses for everything else.
- **Real sunlight does the rest:** a panel facing the sun is lit, and one with the sun behind it
  is dark.

### For every part

- Nothing collides, is touched, is hit by a ray or casts a shadow (`CanCollide`, `CanTouch`,
  `CanQuery`, `CastShadow` all off).
- Fewer than 100 parts in all. The update costs under 0.2 ms a frame (median while driving).

## UI

None.

## Server and client

All on the client, as the horizon and the sky are. It's built with the run's road and taken down
with it (`DriftController:UseSpline`), so every client builds the same view, and nothing is sent.

## Contracts

None.

## Analytics

None.

## Monetization

None.

## Platform risks

Generated art, uploaded as images. It's original art made with the image tool from the user's own
concept images used as references, not copied pixels from them (ART-PIPELINE.md, "Original art
only").

## Art and sound

Made with the image tool (`tools\imagegen.ps1`) and recorded in `assets/painted-vista/MANIFEST.md`
(ART-PIPELINE.md). Nothing is uploaded until the user picks it.

- **Ridge strips,** one set per layer, each a wide strip with a transparent sky (`-Transparent`).
  They're generated from `snow-pass-sunset.png` and `autumn-maple-cliffs.png`
  (`assets/reference/environment-mood/`) as references. The prompt asks for:
  - flat, even light with no sun direction painted in and no cast shadows, since the game lights
    them;
  - no road, car, buildings or foreground;
  - both ends of each strip dropping to the **same low saddle**, so any two strips join there
    without a seam.
- **The look (proposed):** the trial makes candidates in two styles, so the user picks by seeing
  them. One is flat-shaded, faceted low-poly ridges with painterly haze (ART-DIRECTION.md calls
  the concept art "the look to aim for in low poly"). The other is painted like the concept art
  itself.
- **The normal map (an experiment in the trial):** the image tool is asked for a matching
  greyscale height version of the picked strip, and a script turns it into an OpenGL normal map.
  With that, the sun lights each ridge's slopes, not just whole panels. If the height version
  doesn't line up with the strip, or looks wrong, the layers go without one and are lit by panel
  and tint only.
- **A cloud texture:** one tiling cloud image with real transparency.
- **The scripts** (new, `tools\vista\`): join each layer's strips at their saddles, upscale them,
  cut them into one image per panel, and make the normal map. Every cut is logged in the manifest.
- **The arc mesh:** one curved panel, made once and uploaded. Its curve is right for the near
  layer and close enough for the others.

## Testing

- **`VistaView:DebugState()`:** each layer's parts, distance, and trail behind the car; the cloud
  sea's height; the update cost (median and worst); how many textures have loaded.
- **Admin command `vista`:** turn it on and off, and hide one layer at a time, for review shots.
- **Unit tests (`Tests/VistaTests`):**
  - every panel is under 2 048 studs;
  - the near layer stays beyond the drawn ground at every Road ahead setting, even at its full
    trail;
  - every keyframe names the new values;
  - nothing collides, is queried, is touched or casts a shadow.
- **Review shots, from one spot on the road, held with `SkyController:DebugHold`:** noon, sunset
  and night, plus one at sunset looking over a cliff. Before and after, side by side, for the user
  to judge.
- **Cost:** measured while driving: update time, part count, and texture memory
  (`Stats:GetMemoryUsageMbForTag`).

## Steps

1. **Trial: one ridge layer and the cloud sea** (lane, Standard).
   - Make 4 candidates for the far layer, 2 in each look, and show them to the user, who picks one.
   - Build that layer and the cloud sea, with the tint at every time of day, and try the normal map.
   - Take the review shots.
   - **The user decides** whether to go on, change it, or stop.
2. **The full vista** (lane, Standard): the near and middle layers' art, the parallax between the
   three layers, every time of day tuned, and the cost checked at low graphics quality.

## Open questions

- **All the way round, or uphill only?** The old ridges covered only the uphill half (`T-232`, the
  user's request). The concept art's view is over the drop, which is downhill, so this spec
  proposes all the way round.
- **The look:** low-poly or painterly. The user picks from the trial's candidates.
- **The day's haze:** the far layer may need the day's `AtmosphereDensity` lowered a little to stay
  visible, which changes how the day looks. That gets tuned in the trial and shown in the shots.
