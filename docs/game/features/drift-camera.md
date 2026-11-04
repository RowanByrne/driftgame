# Feature: The drift camera's style

**Status:** approved. **Step 1 of 2 built** (`T-071`): the three numbers that already
existed, measured and then chosen, and the move to `Config/Camera.luau`. The roll and the
shake are **step 2** (`T-072`) and are not built. **Owner task:** `T-071`, then `T-072`.

The camera itself is built and approved (`drift-model.md` "Camera", `DECISIONS.md` 2026-11-03): a
port of the reference game's in-game camera, fixed radius, no roll, no zoom, no position smoothing.
This is the layer of style on top of it. The user asked for five things:

> *"bring the camera in closer by default, then have it pickup some fov while the speed increases,
> just slightly. add some more stylish camera effects you might see in drift games too. the way it
> adjusts automatically to look more in the direction of the drift, a touch of roll maybe? idk see
> what games do that are popular drifting games for the camera."*

## The useful surprise: three of the five already exist

They are numbers, not new code. That is worth saying first, because it changes what this plan is.

| What they asked for | What the camera did before `T-071` | What happened |
|---|---|---|
| **Closer by default** | `CamOffset = (0, 14.3, 53.6)` studs — a **55.5-stud radius**, 14 up and 54 back. The reference's own default is 8 m up and 10 m back, which is **45.7 studs** and much steeper | **Done:** `(0, 17.2, 42.7)`, a **46.0-stud radius at 22°**. See "How close is closer" below — the radius is the one number here that is a judgement, and the user has the last word on it |
| **FOV picks up with speed** | **Already ported.** `CamFovBase 60 + CamFovPerSpeed 0.14 × speed`, eased at `CamFovRate 0.5/s`. At 179 studs/s that targets **85°** | **Measured first, and the premise was wrong both ways.** See "What the FOV was really doing". Reshaped to `52 + 0.18 × speed` at `2/s` |
| **Looks more into the drift** | **Already ported,** and deliberately tiny: the camera eases toward a point behind the car's *travel* by an ease-in-out of slip, and then only `CamVelocityBlend = 0.05` of that is taken. The 5% compounds frame to frame because the leaned target feeds the next frame's resting direction | **Done, and it is about time rather than angle.** See "What the lean was really doing". `0.05 → 0.12` |
| **A touch of roll** | **None, on purpose** | New code. `T-072`, not built |
| **More stylish effects** | None | New code. `T-072`, not built |

## What the FOV was really doing

Measured over a 60-second drive from a standstill, with the shipped `60 / 0.14 / 0.5`,
before anything was changed:

| | |
|---|---|
| Over the whole drive | **60.0° → 82.1°, a 22.0° swing** |
| Worst it ran behind its own target | **3.6°** |
| Once up to speed (`t > 16 s`) | **76.6° → 82.1° — a 5.4° band**, median 80.1° |
| The speeds actually driven then | 115 → 159 studs/s (p5–p95) |
| At 40 / 80 / 110 studs/s | **63.0° / 68.0° / 76.4°** against targets of 65.6 / 71.2 / 75.8 |

**So `CamFovRate` was never too slow to arrive.** The car takes sixteen seconds to reach
speed and the FOV's time constant was two, so it kept up to within 3.6°.

**And 22° is not what the player sees.** All of it is spent in those first sixteen seconds,
once a run. After that the car lives in a 44-stud-wide speed band, 0.14°/stud buys 6° of
it, and the FOV sits wide — around 80° — and never visibly moves. The user asking for the
FOV to "pick up with speed" was right about what they were feeling and the number in the
config was the wrong place to look.

**So the fix is the shape, not the size:** a lower base and a steeper slope put the swing
inside the speeds that are driven, and a faster rate stops the dips a drift takes out of
the speed being smoothed away. `52 / 0.18 / 2` measures **70.7° → 80.9° in play, a 10.2°
band — nearly double — with the top unchanged** (80.9 against 82.1). Nothing got wider than
it already was; the bottom moved.

## What the lean was really doing

Where the camera **settles** behind a car held at a fixed slip, measured, with how far round
toward the travel that is:

| Slip | `0.05` (shipped) | `0.08` | `0.12` (chosen) | `0.18` | `0.25` |
|---|---|---|---|---|---|
| 30° | 12.2° (41%) | 15.8° (53%) | **18.9° (63%)** | 21.9° (73%) | 24.0° (80%) |
| 60° | 45.9° (77%) | 51.4° (86%) | **54.9° (91%)** | 57.4° (96%) | 58.9° (98%) |
| 90° | 83.1° (92%) | 86.9° (97%) | **89.0° (99%)** | 90.5° (101%) | 91.3° (101%) |

**The settled angle was never the problem:** at 0.05 the camera already ends up 77% of the
way round in a sustained 60° drift. What the number really buys is **how long it takes**,
and a real drift is a second, not twenty:

| One second into a drift | `0.05` | `0.12` | `0.18` |
|---|---|---|---|
| at 60° of slip | 36% round | **52%** | 58% |
| at 30° of slip | 16% round | **28%** | 36% |

Past about 0.25 the camera is behind the travel before the slide has finished opening,
which is the side-on shot the small number existed to avoid.

**The lean also drops the camera** as it swings wide, and that is why `CamOffset` gained
seven degrees of elevation in the same change: at the old flat 14.9°, `0.12` left the camera
**5.9 studs** above the car in a 60° drift against today's 8.5 — roof height. At 22° it
settles at 7.2 and a drift frames about as it does now.

## How close is closer

Measured at `CamVelocityBlend = 0.12`, which is what the drift column assumes:

| | Radius | At rest | In a 60° drift | The car on screen |
|---|---|---|---|---|
| Before | 55.5 @ 14.9° | 14.3 up, 58 away | 8.5 up, 59 away | 13.8° — 17% of frame height |
| **Chosen** | **46.0 @ 22°** | **17.2 up, 48 away** | **7.2 up, 52 away** | **16.5° — 21%** |
| Same flat angle | 46.0 @ 18.1° | 14.3 up, 48 away | 5.9 up, 52 away | 16.5° — 21% |
| Steeper still | 46.0 @ 26° | 20.2 up, 48 away | 8.4 up, 52 away | 16.5° — 21% |
| The reference's other default | 45.7 @ 38.7° | 28.6 up, 48 away | 12.7 up, 51 away | 16.7° — 21% |

**The radius is a judgement, not a measurement, and it is the user's.** All five are one
number in `Config/Camera.luau`.

## The roll, and why it was taken out

This is the one place this feature has to be careful, because the user has already rejected roll
once, in those words:

> *"THE camera is off in a big way. it spins/rotates wayyyyy to far and i'm not even sure if it's
> the right direction. just copy drifto for now."*

**What they drove was the reference's *predecessor* camera**, which the decompile also contains and
which the reference does not run. Its numbers are the whole story:

```
CameraController.cs:  maxAngle = 45°,  driftAngleForMaxCameraTilt = 20°,  maxAngleChangeRate = 20
```

**45 degrees of roll, reached at only 20 degrees of slip.** A car is barely sideways at 20° and the
horizon is already at 45°. That is not a tuning problem, it is a different intention, and it is why
the first build was corrected to the in-game camera with no roll at all (`DECISIONS.md`).

So: **the shape is right and the numbers were violent.** The same formula at `CamRollMax = 5°`
saturating at `CamRollAtAngle = 45°` of slip is about a ninth of the gain — a lean you feel and do
not notice. That is what "a touch" means, and it ships as two numbers the user can turn to zero.

**If roll comes back at anything like the old gain, it is the wrong camera again.** That sentence is
already in `CarCameraController`'s header and stays there.

## The stylish effects, and what Roblox can actually do

The user asked what popular drift games do. Honestly, with what is and is not possible here:

| Effect | What it is | Verdict |
|---|---|---|
| **Speed shake** | The reference has it — `CameraShake.cs`. A random rotation and position kick every `_shakePeriod` (0.05 s), scaled by speed as a share of top speed, lerped back toward zero continuously. The result is a camera that gets *busy* at speed rather than violent | **Build it.** It is in the decompile, it is cheap, and it is the single biggest "this feels fast" lever after FOV |
| **Pull back when sideways** | The predecessor's drift zoom: distance × up to 1.5 at 90° of slip. Very common in drift games — the car gets smaller as it goes sideways, so you can see the whole slide | **Offer it.** Same caution as the roll: it was removed for being the wrong camera, and the same formula at a small multiplier is a different thing from the old one |
| **Speed vignette** | Darkened corners that close in with speed. Not a camera effect — a full-screen UI gradient | **Offer it, cheaply.** No post-processing needed, one `ImageLabel`, and it reads strongly on a phone |
| **Directional / motion blur** | What most racing games use for speed | **Cannot.** Roblox has a `BlurEffect` but it is uniform, not directional — it blurs the car and the road equally, which reads as "out of focus", not "fast" |
| **Chromatic aberration** | Colour fringing at the edges at speed | **Cannot.** No such post effect, and faking it per-frame is not affordable |
| **Camera whip / lag** | The camera falling behind on a hard turn and catching up | **Deliberately not.** This camera has **no position smoothing** by design — it swings at a fixed radius, and reintroducing lag is the third of the three things that made the predecessor wrong |

## How it plays

You sit closer behind the car than you do now. Build speed and the view opens up — not a lot, but
enough that 110 studs/s looks different from 40 — and the picture starts to buzz slightly. Put the
back out and the camera swings wider toward where you are actually travelling, and leans a few
degrees with the slide. Catch it and all of it settles.

**Step 1 (`T-071`) is the closer camera, the reshaped FOV and the wider swing.** The buzz
and the lean are step 2.

## Left out

- **Anything the player can change.** All of this is one look, tuned once. A camera settings screen
  (shake on/off, roll on/off, a distance slider) belongs in `SETTINGS.md` and the UI phase — though
  the reference does carry a camera-mode switch, and these numbers are already shaped to be
  switched off.
- **A cinematic or replay camera.** There is no end of run to cut to yet (`endless-run.md`).
- **Anything that touches how the car drives.** The camera reads the model and never writes to it.
- **The pan** (`T-036`), the player's own right-drag orbit, which is unchanged and must stay
  downstream of everything here.

## Rules and numbers

**The camera's numbers moved to `Config/Camera.luau`** (`T-071`): all seventeen, name for
name, so `CamOffset` is still `CamOffset`. They have nothing to do with how the car drives,
`T-072` adds six more, and the move was proved free before anything else changed — with the
old values in the new file a recorded drive put the camera and its look point in exactly
the same place, step for step, as the build before the file existed.

| Number | Now | What it does |
|---|---|---|
| `CamOffset` | **`(0, 17.2, 42.7)`** — 46.0 @ 22° | Was 55.5 @ 14.9°. Nine and a half studs closer, seven degrees steeper to pay for the raised blend |
| `CamFovBase`, `CamFovPerSpeed`, `CamFovRate` | **52, 0.18, 2** | Was 60, 0.14, 0.5. The in-play swing roughly doubles; the top is unchanged |
| `CamVelocityBlend` | **0.12** | Was 0.05. How much it leans into the drift. **Compounds step to step**, so the number is nothing like the answer: what it really moves is how fast the camera gets round, not where it ends up |
| `CamRollMax` | 5° | The whole roll, at full slip. The predecessor's was 45 |
| `CamRollAtAngle` | 45° | Slip at which the roll saturates. The predecessor's was 20 |
| `CamRollRate` | ~6 /s | How fast the roll follows. The predecessor's was 20, which is most of why it felt like a flick |
| `ShakePeriod` | 0.05 s | How often a new kick is chosen |
| `ShakeRotation`, `ShakePosition` | small | The kick's size at top speed, scaled by speed as a share of it |
| `ShakeRestoreRate` | — | How fast it settles back to zero |

**Every one of them must be settable to zero and give exactly today's camera back.** That is the
test that protects the approved feel, and it is how the roll ships without reopening an argument.

## UI

Only the optional speed vignette, if the user wants it: one `ImageLabel` in its own `ScreenGui`,
below everything else in `DisplayOrder`, never `Active` — the whole screen is a steering pad and a
GUI that takes input is a GUI that steals the finger (`endless-run.md` learned this the hard way).

## Server and client

Entirely the client's. The camera reads `Drift/Model`'s state and writes nothing anywhere.

**The fixed-step rule is load-bearing and must survive all of this.** The camera's targets run on
`CamTargetStep`, not the frame, because the lean feeds back into the resting direction — left at
frame rate the camera sat 16.2 studs above a drifting car at 30 FPS and 10.1 at 120, which is two
players getting different games. **The roll and the shake must not join that feedback loop:** both
are applied to the *rendered* camera, downstream of the stepped targets, exactly as the pan is.
Anything that feeds back has to be stepped, and the cheapest way not to think about it is not to
feed back.

## Contracts

In `CONTRACTS.md`: `Config.Camera` now that the numbers have moved, every new number, and
any change to `CarCameraController`'s `DebugState()`. `T-071` changed no debug member and no
remote; the one entry it owes is `Shared/Config/Camera`, which it does not own the file to
add.

## Analytics

None.

## Monetization

None.

## Platform risks

None.

## Art and sound

None, unless the speed vignette is built, which is one flat gradient and no asset.

## Testing

| Check | Measured |
|---|---|
| **Zeroing it all gives today's camera back** | Every new number at zero: the camera's position and look-at over a recorded drive are **identical** to the current build, step for step. This is the check that protects what the user approved. **`T-071`: passed.** With the old values in the new config file, a 20-second recorded drive sampled every 120 frames matched the previous build to all nine decimals printed, and the summed components over all 1200 frames matched exactly |
| What the FOV really does | FOV sampled over a 60-second drive against speed: what it reaches at 40, 80 and 110 studs/s, and how far behind its own target it runs. **Do this before changing the number. `T-071`: done** — see "What the FOV was really doing", and the answer changed the plan |
| The roll stays small | Peak roll over a full-lock drift, and the slip it took to get there. Against the predecessor's 45° at 20° of slip, which is the thing being avoided |
| The lean | Where the camera settles behind a steady drift, at the old blend and the new one. It compounds, so the relationship is not linear and the number alone does not tell you. **`T-071`: done**, at 0.05, 0.08, 0.12, 0.18, 0.25 and 0.4, at 30°, 60° and 90° of slip, settled and one second in |
| The shake is speed-scaled | Kick size at a standstill, at half speed and at top speed. `T-072` |
| **Frame rate does not change the camera** | The recorded drive at 30, 60 and 120 FPS puts the camera in the same place. This already held and must keep holding — it is why the targets are stepped. **`T-071`: still holds** with the new numbers. A 20-second drive ends within **0.0011 studs** across 30 → 120 FPS, and a sustained 60° drift settles **7.1412 / 7.1413 / 7.1412 studs** above the car at 30 / 60 / 120 — a spread of 0.0001, against the 16.2-vs-10.1 this rule exists to prevent |
| The pan still cannot disturb it | `T-036`'s existing checks, unchanged. **`T-071`: passed.** The same drive with and without a hand on it leaves `target`, `lookTarget`, `restTarget` and `velTarget` **0.000000000 studs apart**; the pan preserves the radius to 8e-5 studs, comes home to 0.0000° every time, and the elevation guard still holds |
| It does not cost frames | Frame time over a 60-second drive, before and after |

## Open questions

- **How close is closer?** `T-071` shipped 46.0 studs at 22° and measured four alternatives
  beside it ("How close is closer"). **The user has the last word**; it is one line in
  `Config/Camera.luau`.
- **Is 10° of in-play FOV swing "just slightly"?** It is double what the camera had, with
  the top end unchanged. If it reads as too much, `CamFovPerSpeed` is the dial and
  `CamFovBase` moves with it to keep the top where it is.
- **Does the drift pull-back come back?** Same history as the roll.
- **Does the speed vignette get built?** It is cheap, it reads well on a phone, and it is the one
  item here that is not a camera at all.
- **Whether any of it becomes a setting.** `SETTINGS.md`, the UI phase.
