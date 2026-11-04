# Feature: The drift camera's style

**Status:** approved, **and built** — step 1 (`T-071`): the three numbers that already
existed, measured and then chosen, and the move to `Config/Camera.luau`; step 2 (`T-072`):
the roll and the speed shake. **Owner task:** `T-071`, then `T-072`. What is left is the
user's: how close is closer, whether the roll goes the right way round, and the two
offers below that were deliberately not built.

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
| **A touch of roll** | **None, on purpose** | **Done** (`T-072`): 4 deg, saturating at 45 deg of slip, eased at 6/s. See "The roll, and why it was taken out" |
| **More stylish effects** | None | **Done** (`T-072`): the reference's own speed shake. See "The stylish effects" |

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

So: **the shape is right and the numbers were violent.** The same formula at a ninth of the gain is
a lean you feel and do not notice. That is what "a touch" means, and it ships as three numbers the
user can turn to zero.

**What `T-072` built, measured.** `CamRollMax = 4°`, `CamRollAtAngle = 45°`, `CamRollRate = 6/s`,
against the predecessor's 45 / 20 / 20:

| Slip held | This camera leans | The predecessor leaned |
|---|---|---|
| 10° | **0.89°** | 22.5° |
| 20° | **1.78°** | **45°** — already at full tilt |
| 30° (an ordinary drift) | **2.67°** | 45° |
| 45° and past it | **4.00°**, the stop | 45° |

The **horizon** tilts 3.92° where the camera is told to roll 4.00°, because the camera is pitched
down and some of a roll about the look axis goes into the pitch instead. Four degrees moves the edge
of a 1080-line screen by **67 pixels**, so this is nothing like invisible.

**And it is a lean, not a flick.** Over a hard 20-second drive the worst single frame of roll is
**0.147°** at 60 FPS — a twenty-fifth of the whole lean — and 0.293° at 30 and 0.073° at 120, which
is the same angular speed at every frame rate. The predecessor chased at rate 20 against this 6.

**Which way round it goes is the one judgement in it, and it is the user's.** The camera banks *into*
the corner, the way a motorcycle does: a positive slip is the car travelling out to its left, which
is a **right-hand** drift (the nose is turned into the corner, the tail is out to the left), and the
camera rolls right with it. The user said of the predecessor that they were "not even sure if it's
the right direction" — **negating `CamRollMax` is the other convention**, and it is one character.

**If roll comes back at anything like the old gain, it is the wrong camera again.** That sentence is
in `CarCameraController`'s header; `T-072` amended it rather than deleting it, because one of the
three *is* back and the file should say so.

## The stylish effects, and what Roblox can actually do

The user asked what popular drift games do. Honestly, with what is and is not possible here:

| Effect | What it is | Verdict |
|---|---|---|
| **Speed shake** | The reference has it — `CameraShake.cs`. A random rotation and position kick every `_shakePeriod` (0.05 s), scaled by speed as a share of top speed, lerped back toward zero continuously. The result is a camera that gets *busy* at speed rather than violent | **Built** (`T-072`). See "What the shake really is" |
| **Pull back when sideways** | The predecessor's drift zoom: distance × up to 1.5 at 90° of slip. Very common in drift games — the car gets smaller as it goes sideways, so you can see the whole slide | **Offer it.** Same caution as the roll: it was removed for being the wrong camera, and the same formula at a small multiplier is a different thing from the old one |
| **Speed vignette** | Darkened corners that close in with speed. Not a camera effect — a full-screen UI gradient | **Offer it, cheaply.** No post-processing needed, one `ImageLabel`, and it reads strongly on a phone |
| **Directional / motion blur** | What most racing games use for speed | **Cannot.** Roblox has a `BlurEffect` but it is uniform, not directional — it blurs the car and the road equally, which reads as "out of focus", not "fast" |
| **Chromatic aberration** | Colour fringing at the edges at speed | **Cannot.** No such post effect, and faking it per-frame is not affordable |
| **Camera whip / lag** | The camera falling behind on a hard turn and catching up | **Deliberately not.** This camera has **no position smoothing** by design — it swings at a fixed radius, and reintroducing lag is the third of the three things that made the predecessor wrong |

## What the shake really is

**The only honest unit for a camera shake is screen pixels.** A rotation of the camera and a
sideways shift of it forty-six studs behind the car are the same thing to the player: both move the
whole picture. So the shake was tuned on what the car does on screen, not on the numbers in the
config — at the FOV the camera is actually running at that speed, on a 1080-line display.

At the shipped `ShakeRotation = (0.15, 0.15, 0.10)°` and `ShakePosition = (0.07, 0.07, 0)` studs:

| Speed | The kick | The picture moves, worst frame | …on average |
|---|---|---|---|
| Standing still | **0.0000°** | **0.00 px** | 0.00 px |
| A quarter of top (45) | 0.043° | 1.16 px | 0.23 px |
| Half (90) | 0.086° | 2.04 px | 0.40 px |
| Three quarters (134) | 0.129° | 2.72 px | 0.54 px |
| Top speed (179) | **0.172°** (2.2 px) | **3.27 px** | **0.65 px** |

**Exactly linear in speed**, as the reference's is, and exactly nothing at a standstill.

**Is that enough, and is it too much?** For scale, the car is about **210 px** tall on that screen,
so the worst frame of the buzz is **one and a half per cent of the car**. The ladder either side was
measured: `0.10` gives 2.2 px worst and 0.44 mean, which is under what is felt; `0.20` gives 4.5 and
0.88; `0.30` gives 6.7 and 1.3, which reads as a shimmer rather than a buzz. `ShakeRestoreRate` is
the texture dial at a fixed size: 8 is a sway (4.0 px worst), 24 is a fizz (2.5).

**The honest answer is that it wants to be small.** A camera that jitters while the player is
placing a drift at 140 studs/s is worse than no shake at all, and the lever that actually sells
speed in this game is still the FOV.

**It does not depend on the frame rate**, which the reference's own does. The kicks are chosen on
their own clock from a seeded sequence and the camera decays toward zero by an *exact* exponential —
two half steps leave it where one whole step would — so 30, 60 and 120 FPS get the same kicks at the
same moments. (The reference *adds* its kick every `Update`, so its shake grows with the frame rate.
That is not ported.)

## How it plays

You sit closer behind the car than you do now. Build speed and the view opens up — not a lot, but
enough that 110 studs/s looks different from 40 — and the picture starts to buzz slightly. Put the
back out and the camera swings wider toward where you are actually travelling, and leans a few
degrees with the slide. Catch it and all of it settles.

**Step 1 (`T-071`) was the closer camera, the reshaped FOV and the wider swing; step 2
(`T-072`) is the buzz and the lean.** All of it is built.

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
and the move was proved free before anything else changed — with the old values in the new
file a recorded drive put the camera and its look point in exactly the same place, step for
step, as the build before the file existed. **`T-072` then added seven** (the roll's three
and the shake's four), and proved the same way that zeroing them gives that build back.

| Number | Now | What it does |
|---|---|---|
| `CamOffset` | **`(0, 17.2, 42.7)`** — 46.0 @ 22° | Was 55.5 @ 14.9°. Nine and a half studs closer, seven degrees steeper to pay for the raised blend |
| `CamFovBase`, `CamFovPerSpeed`, `CamFovRate` | **52, 0.18, 2** | Was 60, 0.14, 0.5. The in-play swing roughly doubles; the top is unchanged |
| `CamVelocityBlend` | **0.12** | Was 0.05. How much it leans into the drift. **Compounds step to step**, so the number is nothing like the answer: what it really moves is how fast the camera gets round, not where it ends up |
| `CamRollMax` | **4°** | The whole roll, at `CamRollAtAngle` of slip. The predecessor's was 45. **Negate it to bank the other way** |
| `CamRollAtAngle` | **45°** | Slip at which the roll saturates. The predecessor's was 20 |
| `CamRollRate` | **6 /s** | How fast the roll follows: a 167 ms time constant. The predecessor's was 20, which is most of why it felt like a flick |
| `ShakePeriod` | **0.05 s** | How often a new kick is chosen. EXACT, the reference's own |
| `ShakeRotation` | **(0.15, 0.15, 0.10)°** | The rotation kick at top speed, linear in speed. 3.3 px of picture in the worst frame, 0.65 in the average one |
| `ShakePosition` | **(0.07, 0.07, 0) studs** | The position kick, in the camera's own axes. About a pixel; the Z is zero because a dolly along the look axis is a 0.2% scale change and nothing else |
| `ShakeRestoreRate` | **14 /s** | How fast a kick settles back to zero: to half of itself before the next one arrives |

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

**`T-072` held to that, and the measurement says so:** with the roll and the shake on, `rig.position`
and `rig.lookPoint` over a 20-second recorded drive are bit for bit what they were without them.
The roll lives in `rig.roll` and the shake in `rig.shakeRot` / `rig.shakePos`, and nothing that
builds a target reads any of the three — they are only ever multiplied into the CFrame that is
returned. The shake's kicks run on their own clock rather than once a frame, and it decays by an
exact exponential, so it is frame-rate independent without being stepped at all.

## Contracts

In `CONTRACTS.md`: `Config.Camera` now that the numbers have moved, every new number, and
any change to `CarCameraController`'s `DebugState()`. `T-071` changed no debug member and no
remote; the one entry it owes is `Shared/Config/Camera`, which it does not own the file to
add.

`T-072` owes three more, and no remote and no tag: `DebugState()` gains **`rolledDeg`**
(the roll the camera was told to take, where `rollDeg` is what the horizon actually did),
**`shakeRotDeg`** and **`shakePosStuds`** (the kick currently applied, decayed to where it
is now); `DebugProbe` gains **`maxRollStepDeg`** and **`rollDeg`**, takes a **`config`**
table of camera numbers to use for one run only, and its `maxRollDeg` is now **signed**;
and there is a new probe, **`CarCameraController:DebugShakeProbe(opts)`** — `{ speed,
seconds, fps, viewportY, config }` — which reports what the shake does to the picture in
degrees of arc and in screen pixels.

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
| **Zeroing it all gives today's camera back** | Every new number at zero: the camera's position and look-at over a recorded drive are **identical** to the current build, step for step. This is the check that protects what the user approved. **`T-071`: passed.** With the old values in the new config file, a 20-second recorded drive sampled every 120 frames matched the previous build to all nine decimals printed, and the summed components over all 1200 frames matched exactly. **`T-072`: passed the same way** — with `CamRollMax`, `ShakeRotation` and `ShakePosition` at zero, the same 20-second drive matched the build before them on camera position, look point and FOV to every digit printed, and the summed components over all 1200 frames matched exactly. **And with the style ON**, `rig.position`, `rig.lookPoint` and the FOV sum are *still* identical to the baseline: only the rendered CFrame differs, which is the proof that neither effect can move where the camera sits |
| What the FOV really does | FOV sampled over a 60-second drive against speed: what it reaches at 40, 80 and 110 studs/s, and how far behind its own target it runs. **Do this before changing the number. `T-071`: done** — see "What the FOV was really doing", and the answer changed the plan |
| The roll stays small | Peak roll over a full-lock drift, and the slip it took to get there. Against the predecessor's 45° at 20° of slip, which is the thing being avoided. **`T-072`: passed.** The camera reaches its **4.00°** stop and the horizon tilts **3.92°**, and it takes **45°** of slip to get there — at 20°, where the predecessor was at full tilt, this leans **1.78°**. The worst single frame of roll on a hard 20-second drive is **0.147°** at 60 FPS, a twenty-fifth of the lean: it is a lean and not a flick. `CamRollMax = 0` measures **0.000000000°** at 90° of slip |
| The lean | Where the camera settles behind a steady drift, at the old blend and the new one. It compounds, so the relationship is not linear and the number alone does not tell you. **`T-071`: done**, at 0.05, 0.08, 0.12, 0.18, 0.25 and 0.4, at 30°, 60° and 90° of slip, settled and one second in |
| The shake is speed-scaled | Kick size at a standstill, at half speed and at top speed. **`T-072`: passed.** **0.0000° / 0.086° / 0.172°**, exactly linear, and the picture moves 0.00 / 2.04 / 3.27 px in its worst frame — see "What the shake really is" for the whole ladder in screen pixels |
| **Frame rate does not change the camera** | The recorded drive at 30, 60 and 120 FPS puts the camera in the same place. This already held and must keep holding — it is why the targets are stepped. **`T-071`: still holds** with the new numbers. A 20-second drive ends within **0.0011 studs** across 30 → 120 FPS, and a sustained 60° drift settles **7.1412 / 7.1413 / 7.1412 studs** above the car at 30 / 60 / 120 — a spread of 0.0001, against the 16.2-vs-10.1 this rule exists to prevent. **`T-072`: still holds with the roll and the shake on.** Ten seconds into the recorded drive the camera sits **48.0810 / 48.0805 / 48.0818 studs** from the car at 30 / 60 / 120 (a spread of 0.0013) at **16.93° / 16.93° / 16.90°** of elevation, and the roll reads **2.583° / 2.574° / 2.581°**. The shake's kicks are chosen on their own clock, so all three frame rates get the same ones at the same moments |
| The pan still cannot disturb it | `T-036`'s existing checks, unchanged. **`T-071`: passed.** The same drive with and without a hand on it leaves `target`, `lookTarget`, `restTarget` and `velTarget` **0.000000000 studs apart**; the pan preserves the radius to 8e-5 studs, comes home to 0.0000° every time, and the elevation guard still holds. **`T-072`: passed, unchanged.** A 20-second drive with a hand on it leaves `target`, `lookTarget`, `restTarget` and `velTarget` **0.000000000 studs** from the same drive without — and the roll **0.000000000°** apart; the radius is preserved to **0.00008011 studs**, bit for bit what `T-071` measured, and every pan figure is identical with the style on and off |
| It does not cost frames | Frame time over a 60-second drive, before and after. **`T-072`: passed.** Sixty seconds of frames through `_advance` costs **0.0011–0.0017 ms a frame** without the style and **0.0016–0.0023 ms** with it: the roll and the shake together are about **half a microsecond a frame**, three thousandths of one per cent of a 60 FPS budget |
| **`JitterTests` still passes** | It measures judder — movement the player should *not* see — as a second difference against a 0.1° limit, and the shake is deliberate movement at 0.37°. **`T-072` turns the shake off for the length of that measurement and nothing else**, which is a six-line change in `JitterTests` with the reason in it. The roll is left ON, and measures nothing: the shimmer figure is **0.0949° either way**, the same number it was before this task |

## Open questions

- **How close is closer?** `T-071` shipped 46.0 studs at 22° and measured four alternatives
  beside it ("How close is closer"). **The user has the last word**; it is one line in
  `Config/Camera.luau`.
- **Is 10° of in-play FOV swing "just slightly"?** It is double what the camera had, with
  the top end unchanged. If it reads as too much, `CamFovPerSpeed` is the dial and
  `CamFovBase` moves with it to keep the top where it is.
- **Does the roll go the right way round?** It banks *into* the corner, like a motorcycle. The
  other convention is `CamRollMax = -4`, one character. The user is the only one who can say, and
  they said of the predecessor that they were not sure it was the right direction.
- **Is 4° the right touch?** It is a ninth of what was rejected and it moves the edge of the screen
  by 67 pixels. `5` is one line away, and so is `0`.
- **Does the drift pull-back come back?** Same history as the roll.
- **Does the speed vignette get built?** It is cheap, it reads well on a phone, and it is the one
  item here that is not a camera at all.
- **Whether any of it becomes a setting.** `SETTINGS.md`, the UI phase.
