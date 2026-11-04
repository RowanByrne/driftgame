# Feature: The drift camera's style

**Status:** specced, waiting on the user's approval of the plan. **Owner task:** none yet
(`T-069`).

The camera itself is built and approved (`drift-model.md` "Camera", `DECISIONS.md` 2026-11-03): a
port of the reference game's in-game camera, fixed radius, no roll, no zoom, no position smoothing.
This is the layer of style on top of it. The user asked for five things:

> *"bring the camera in closer by default, then have it pickup some fov while the speed increases,
> just slightly. add some more stylish camera effects you might see in drift games too. the way it
> adjusts automatically to look more in the direction of the drift, a touch of roll maybe? idk see
> what games do that are popular drifting games for the camera."*

## The useful surprise: three of the five already exist

They are numbers, not new code. That is worth saying first, because it changes what this plan is.

| What they asked for | What the camera does today | What it needs |
|---|---|---|
| **Closer by default** | `CamOffset = (0, 14.3, 53.6)` studs — a **55.5-stud radius**, 14 up and 54 back. The reference's own default is 8 m up and 10 m back, which is **45.7 studs** and much steeper | One number, driven and chosen |
| **FOV picks up with speed** | **Already ported.** `CamFovBase 60 + CamFovPerSpeed 0.14 × speed`, eased at `CamFovRate 0.5/s`. At 179 studs/s that targets **85°** | Nothing new — but see below, because 25° of swing is not "just slightly" and the ease is slow enough that it may never arrive. **Measure what it actually reaches before changing anything** |
| **Looks more into the drift** | **Already ported,** and deliberately tiny: the camera eases toward a point behind the car's *travel* by an ease-in-out of slip, and then only `CamVelocityBlend = 0.05` of that is taken. The 5% compounds frame to frame because the leaned target feeds the next frame's resting direction | One number, raised carefully — it is a feedback loop, so it does not scale linearly |
| **A touch of roll** | **None, on purpose** | New code. See below |
| **More stylish effects** | None | New code. See below |

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

Camera numbers live in `Config/Drift.luau` today, among the model's. **They should move to their own
`Config/Camera.luau`** as part of this work: there are already seventeen of them, this adds four to
six, and they have nothing to do with how the car drives.

| Number | Start | What it does |
|---|---|---|
| `CamOffset` | to be driven | Closer than today's 55.5-stud radius. The reference's own default is 45.7, steeper. Pick it by driving, not by arithmetic |
| `CamFovPerSpeed`, `CamFovRate` | measure first | What the FOV **actually reaches** on a real drive, against the 85° it targets. "Just slightly" is a judgement about the number you feel, not the one in the config |
| `CamVelocityBlend` | 0.05 → up | How much it leans into the drift. **Compounds frame to frame**, so raise it in small steps and measure where the camera settles, not what the number says |
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

In `CONTRACTS.md`, in the same commit: `Config.Camera` if the numbers move, every new number, and
any change to `CarCameraController`'s `DebugState()`.

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
| **Zeroing it all gives today's camera back** | Every new number at zero: the camera's position and look-at over a recorded drive are **identical** to the current build, step for step. This is the check that protects what the user approved |
| What the FOV really does | FOV sampled over a 60-second drive against speed: what it reaches at 40, 80 and 110 studs/s, and how far behind its own target it runs. **Do this before changing the number** |
| The roll stays small | Peak roll over a full-lock drift, and the slip it took to get there. Against the predecessor's 45° at 20° of slip, which is the thing being avoided |
| The lean | Where the camera settles behind a steady drift, at the old blend and the new one. It compounds, so the relationship is not linear and the number alone does not tell you |
| The shake is speed-scaled | Kick size at a standstill, at half speed and at top speed |
| **Frame rate does not change the camera** | The recorded drive at 30, 60 and 120 FPS puts the camera in the same place. This already held and must keep holding — it is why the targets are stepped |
| The pan still cannot disturb it | `T-036`'s existing checks, unchanged |
| It does not cost frames | Frame time over a 60-second drive, before and after |

## Open questions

- **How close is closer?** A number to drive, not to derive. Two or three candidates in one session
  beats guessing.
- **Does the drift pull-back come back?** Same history as the roll.
- **Does the speed vignette get built?** It is cheap, it reads well on a phone, and it is the one
  item here that is not a camera at all.
- **Whether any of it becomes a setting.** `SETTINGS.md`, the UI phase.
