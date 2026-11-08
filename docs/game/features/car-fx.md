# Feature: The car's sound and wheel effects

**Status:** approved; **built**, all three steps. **Owner task:** `T-056`.

| Part | State |
|---|---|
| Tyre marks and smoke, four gates, per wheel, per surface | **Built** — `Config/Fx.luau`, `Drift/Wheels.luau`, `Tests/FxTests.luau` (`T-062`) |
| Engine note and the gearbox that does not exist | **Built** — `Config/Fx.luau` `Engine`, `Drift/EngineSound.luau` (`T-064`) |
| Tyre squeal | **Built** — `Config/Fx.luau` `Skid`, `Drift/SkidSound.luau` (`T-064`) |
| Backfire | Not built, and deliberately — the user decided against it, 2026-11-04 (`AUDIO.md`) |
| Remote cars | Not built, and out of scope for this round |
| A darkness that varies along a mark | **Built, driven and removed** at the user's call, 2026-11-06. One shade of line now; the record of what it was and what it cost is below, so nobody rebuilds it blind |

The car slides in silence and leaves nothing behind. This is the layer that makes a drift
*read* — engine note, tyre squeal, tyre marks on the road and smoke off the wheels — ported
from the reference game the same way the drift model and the road generator were
(`drift-model.md`, `track-generation.md`). What we take is how the system works; none of its
source, art, sound, names or text come near this game (`PLATFORM-RISKS.md`).

The user asked for it in one line: *"review how drifto handles the audio for gameplay
(drifting/engine noises) tiremarks and smoke vfx. we need a similar system."*

## Goal

A drift you can hear and see the evidence of. Three things, each driven by numbers the drift
model already publishes:

| What | Driven by | Why it matters |
|---|---|---|
| **Engine note** | Road speed, through faked gears | The only cue for speed that works with your eyes on the corner. Pairs with the road markings (`T-055`) |
| **Tyre squeal** | Slip angle, per surface | Tells you the back is out before the camera does, and how far out |
| **Tyre marks and smoke** | Slip angle, throttle, handbrake, per wheel, per surface | The record of the line you just drove. The thing players screenshot |

## How the reference does it, and what we take

Four of its components matter, and all four read the same car state we already have.

### Engine sound: one loop, pitched by a gearbox that does not exist

There is **no engine model and no RPM.** One looping idle clip plays for ever and its *pitch* is
lerped between a floor and a ceiling across the current gear's speed band. The gearbox exists only
to decide which band:

- **Gear tops are a geometric series.** With `GearCount` gears and a length multiplier `m`, the
  first gear's band is `TopSpeed / Σ(m^i)` for `i` in `0..GearCount-1`, and each gear after it adds
  `m^i × that`. At the reference's 5 gears and `m = 1.5`, the divisor is 13.1875, so a 179 studs/s
  car shifts at roughly **13.6, 34, 64, 110** and tops out at **179**.
- **Bands overlap** by `GearOverlap` either side, and a shift needs `MinTimeInGear` since the last
  one, so a car hovering on a shift point does not machine-gun between two gears.
- **Pitch is lerped toward its target**, never snapped, at `PitchLerpSpeed` per second. That lerp
  is the whole reason a shift sounds like a shift: the pitch falls across the gap rather than
  jumping.
- **Airborne pitches straight to the ceiling** — wheels off the ground, engine free-revving.
- A shift fires an event, which is the only thing the backfire listens to.

**This is cheap and it is right for us.** Our model has no engine either: throttle is eased in over
`FullThrottleSeconds` and never an input (`Config/Drift.luau`). Speed is all the information there
is, and speed is all this needs.

### Skid sound: one loop per surface, always on, volume by slip angle

One looping clip **per surface type**, all of them live at once, each one's volume lerped rather
than switched.

**The clip never stops while the car is rolling** (`T-083`, the user's call on 2026-11-08). It is
started the first frame the wheels are on a surface above `MinSpeed` and left running: a straight
car hisses quietly, and a drift is that hiss *swelling*, not a second sound arriving. Started at
the top of every drift instead — which is what it did — a 3-second clip replays its own loop seam
at the top of every drift, and the seam becomes a thing the player hears coming.

- Volume is **0** with no state, in the air, or under `MinSpeed`. Those are the only three ways to
  be silent, and they are also the only two things that *stop* the clip (airborne, too slow).
- **`RollVolume`** (0.12) while the car is grounded and moving but not drifting: the rubber-on-road
  hiss. `RollVolume = 0` puts the old behaviour back exactly — silent until a drift — and `FxTests`
  checks that it does.
- **`lerp(MinVolume, MaxVolume, slip / MaxSlipDegrees)`** while it is drifting: 0.25 at the drift
  threshold up to **`MaxVolume` 0.55** at 90°. The ceiling was a hard-coded 1 and that is most of
  why the squeal was harsh — the reference's own curve only reaches about half at a full drift.
- **There is a step up at the drift threshold**, `RollVolume` to `MinVolume`, deliberate and the
  reference's own shape. `VolumeLerpSpeed` (1/s) carries it like any other change of target, so it
  swells rather than clicks: measured, the largest single-frame move across it is a small fraction
  of the step.
- Only the clip whose surface the wheels are actually on is *playing*; the others are stopped. We
  have one surface in the game today (tarmac) and `dirt` specced but unbuilt, so this is one clip
  now and a table that already has room for the second.

### Tyre marks and smoke: per wheel, per surface, gated on four things

The part worth copying carefully. Each wheel owns a trail and a smoke emitter **per surface**, and
every frame it asks four questions:

| Gate | What it does |
|---|---|
| **Is this wheel's surface this effect's surface?** | Picks which pair emits. Wrong surface, nothing |
| **Is the slip angle past this wheel's threshold?** | **The fronts and the rears have different thresholds, and that is the detail that sells it.** The front wheels are drawn pointing along the travel (opposite lock, `Drift/Render`), so they are not sliding until the slip exceeds that steering angle: their threshold is `slip − Gates.MaxSteerDegrees`, the rears' is `slip > Gates.MinSlipDegrees`, a floating-point floor half a degree wide. The rears mark first and alone through a small slide, and the fronts join in once it is a big one |
| **Is the throttle past `Gates.MinThrottle`?** | A car coasting sideways does not light up the road |
| **Or is the handbrake down?** | The handbrake marks and smokes on its own, above `Gates.MinHandbrakeSpeed`, throttle or no throttle |

Smoke's **emission rate** is lerped from a minimum to a maximum by `slip / π`, so a big angle is a
big cloud. Marks have a fixed lifetime (`Marks.Seconds`), with a hook to keep them for ever
(`Wheels:SetMarkSeconds`) — the reference uses that for its end-of-run replay shot, and we would
want it for the same reason one day.

### Backfire: a pop on the shift

Purely cosmetic, listens to the gearbox's shift event, fires with a probability, and when it does
it plays 1..`MaxBackfireCount` pops `0.05..0.1 s` apart at each exhaust tip, each with its pitch
and volume jittered. The particle flash goes with the pop.

**This is the one piece worth questioning rather than porting,** and it is listed under "Left out":
it needs an exhaust position per car body, and our four bodies are built from parts by code
(`car-archetypes.md`). Cheap to add later, no reason to hold the rest for it.

## What our model already publishes

Nothing in this feature needs a new number out of the drift model. `Drift/Model`'s `State`
(`drift-model.md`) already carries every input the four components ask for:

| The reference asks | We have | Note |
|---|---|---|
| `GetDriftAngle()` | `s.slip` (signed radians) | Take `math.abs` |
| `IsDrifting()` | `s.drifting` | `|slip| >= MinSlipAngleForDrift`, which is 5° |
| `IsGrounded()` | `s.grounded`, `s.airborne` | |
| `GetVelocity().magnitude` | `Model.speed(s)` | studs/s |
| `_acceleration` | `s.throttle` (0..1) | Eased, never an input |
| `_handbrake` | the input's `handbrake` | |
| Per-wheel ground | `s.wheelsDown` (FL, FR, RL, RR) | |
| `GetWheelSurfaceTypes()` | **a gap, and a small one.** `s.surfaceGrip` is the *mean* of four wheels' grip, not four surface names | One surface exists, so the port uses one surface for all four wheels and the per-wheel table is built but fed from one value. The day `dirt` is laid, `Drift/World`'s `Hit` grows a surface name and this reads it. Written down so it is a decision, not an oversight |
| Wheel positions | `Render`'s rig: four wheels with their offsets | The OFFSETS are what the effects use; they hang off the car's `Body` and not off the wheel parts, because `Render` spins a wheel about its axle (see "The budget") |

## How it plays

You press the throttle and the engine note climbs, drops through a shift, climbs again. You turn in
and the back steps out: a squeal fades up with the angle, the rear wheels start laying black on the
road and puffing smoke, and as the slide deepens the fronts join them and the cloud grows. Catch it
and all of it fades back down over about a second, leaving two dark lines through the corner that
stay for `Marks.Seconds` and then fade. Pull the handbrake above `Gates.MinHandbrakeSpeed` and
everything lights up at once, straight or sideways, throttle or no throttle.

**One line of this was wrong, and `T-062` found it by trying to measure it:** *"lift off mid-slide
and the marks stop while the car keeps sliding"*. **There is no lifting off in this game.** The
throttle is not an input — `Drift/Model` eases `s.throttle` from 0 to 1 over
`Config.Drift.FullThrottleSeconds` after a spawn and it stays at 1 for the rest of the run, so the
only moment a live car is ever under `Gates.MinThrottle` is the first third of a second after a
respawn. The gate is real, it is built, and it is measured in `FxTests` (60° of slip at zero
throttle marks nothing; it marks at exactly `MinThrottle` and not a hundredth below) — but no
player will ever see it fire. It earns its place as the thing that stops a car from marking while
it is being eased back onto its feet, and it is **free the day a throttle or a brake becomes an
input**.

Go airborne and the engine screams, the squeal cuts dead, and nothing is laid down until the wheels
are back.

## Left out

- **The backfire** (above). Specced here so it need not be read off the reference twice.
- **Dirt, and any second surface.** The table has room; the game has one surface.
- **Music, ambience, UI sound and the collision/wall-hit sound.** This is the car, not the
  soundtrack. `AUDIO.md` "Direction" is still empty and this feature's approval is what fills it.
- **Anything another player can hear or see.** Step 1 is the local car only. Remote cars
  (`Drift/RemoteCars`) get the same effects in the last step, or not at all this round — see
  "Server and client".
- **A sound when the run starts or ends.** `endless-run.md` already lists that as open.
- **Doppler, engine load, overrun burble, tyre-on-kerb, anything an actual car does.** One loop,
  one pitch.

## Rules and numbers

Every number lives in a new `src/ReplicatedStorage/Shared/Config/Fx.luau`, commented the way
`Config/Drift.luau` and `Config/Road.luau` comment everything. **The values below are the
reference's, converted, and are a starting point to be driven and tuned — not measurements.**
Where the reference's unit is metres, the conversion is 3.571 studs/m.

### Engine

| Number | Start | What it does |
|---|---|---|
| `GearCount` | 5 | How many bands the speed range is cut into |
| `GearLengthMultiplier` | 1.5 | Each gear is this much longer than the one before |
| `GearOverlap` | 10 studs/s | Half-width of the band two gears share (the reference's 3) |
| `MinTimeInGear` | 0.5 s | Shift debounce |
| `PitchLerpSpeed` | 1 /s | How fast pitch chases its target |
| `MinPitch`, `MaxPitch` | 0.7, 2.2 | `Sound.PlaybackSpeed` floor and ceiling. **Ours to choose:** the reference's live on its car config and are not in the decompile. **Kept at the spec's numbers by `T-064`, and still an open question** — see "Open questions" |
| `AirbornePitch` | `MaxPitch` | Wheels up, engine free |
| `Volume` | 0.45 | **Ours, and new.** The engine is a bed and never the loudest thing in a corner (`AUDIO.md` "Mix") |
| `SoundId` | `rbxassetid://5015124019` | The user's pick, by id, nothing uploaded (`AUDIO.md`) |
| `RollOffMin`, `RollOffMax` | 15, 180 studs | **Ours, and new.** `InverseTapered`, so a second car is heard where it is |

### Skid

| Number | Start | What it does |
|---|---|---|
The names below are what is in `Config/Fx.luau` under `Skid`; the first draft's longer names
are in the last column where they differ.

| Number | Start | Was called | What it does |
|---|---|---|---|
| `MinSpeed` | 3.6 studs/s | `MinSkidSpeed` | Below this, silence — and the clip stops |
| `RollVolume` | 0.12 | — | **Ours, and new (`T-083`).** The hiss of a car grounded and moving but not drifting. **0 restores the old silent-until-a-drift behaviour exactly** |
| `MinVolume` | 0.25 | `MinSkidVolume` | The volume a drift that has just begun plays at. There is a step up from `RollVolume` to this at the drift threshold, on purpose |
| `MaxVolume` | 0.55 | — | **New (`T-083`).** The volume at `MaxSlipDegrees`, replacing a hard-coded 1. The reference's curve only reaches about half at a full 90° drift; **1 restores the old ceiling** |
| `MaxSlipDegrees` | 90 | — | The angle the squeal is full at |
| `VolumeLerpSpeed` | 1 /s | `SkidVolumeLerpSpeed` | Fade in and out |
| `Volume` | 0.85 | — | **Ours, and new.** The master the mix sets, on top of the `MinVolume`..`MaxVolume` lerp: the squeal is the loudest thing in a drift and still has somewhere to go (`AUDIO.md` "Mix") |
| `SoundIds.tarmac` | `rbxassetid://124978127809544` | — | The user's pick, by id. **One id per surface, and a surface with no id gets no sound and no error:** `dirt` is specced and has no clip, because a clip is a pick the user makes by ear and not a default an agent chooses |
| `RollOffMin`, `RollOffMax` | 12, 150 studs | — | **Ours, and new.** Tighter than the engine's: a squeal is made at the road |

### Marks and smoke

**Built** (`T-062`). The names below are what is actually in `Config/Fx.luau`, which groups them —
the names in the first draft of this spec are in the last column where they differ. Every value is
still the reference's, converted, except the two marked **ours**.

| Number | Start | Was called | What it does |
|---|---|---|---|
| `Gates.MinThrottle` | 0.2 | `MinThrottleForFx` | Coasting sideways leaves nothing |
| `Gates.MaxSteerDegrees` | 30 | `MaxSteerAngle` | The fronts' extra threshold (see the gates table) |
| `Gates.MinSlipDegrees` | 0.5 | — | **Ours, and new.** A floating-point floor and not a gate. The reference's rear threshold is literally `slip > 0`, which is right in its model; ours is an `atan2` of a velocity that gravity and grip are always nudging. **Measured in `DR-Lane2`: a car running dead straight at 40.2 studs/s reads 0.0916° of slip,** so `> 0` would have marked the whole road black. It is a two-hundredth of `MinSlipAngleForDrift` and is not a second drift threshold |
| `Gates.MinHandbrakeSpeed` | 3.6 studs/s | — | Below this the handbrake smokes nothing |
| `Gates.MaxSlipDegrees` | 180 | — | The angle the smoke rate is full at. This is the reference's `slip / π` written in degrees. **Note it is not the squeal's 90°:** at 90° of slip — a car fully sideways — the smoke is only at 34/s of its 60, which is a tuning question for the user's eye, not a bug |
| `Marks.Seconds` | 5 | `MarkSeconds` | `Trail.Lifetime` |
| `Marks.Width` | 1.2 studs | `MarkWidth` | The gap between the two attachments. A little under the tyre's 1.6 |
| `Smoke.RateMin`, `Smoke.RateMax` | 8, 60 /s | `SmokeRateMin/Max` | `ParticleEmitter.Rate`, lerped by `slip / Gates.MaxSlipDegrees` |

Added in round two, and all of them ours — see the sections below for the measurements behind each:

| Number | Start | What it does |
|---|---|---|
| `Marks.Transparency` | 0.52 | **One darkness, for every mark.** The middle rung of the three-band ladder that used to be here — see "The darkness ramp that was built and removed". Lower is darker |
| `Marks.MinSegment` | 0 studs | `Trail.MinLength`. A mark starts drawing on its first frame. It was 0.5 for one round, as a wrong guess at why marks were breaking up, and that made them worse |
| `Gates.StopSlipDegrees` | 0.25 | The slip gate's lower threshold once a wheel is already marking, so it cannot chatter |
| `Marks.Lift` | 0.25 studs | **Was 0.05**, and that was half the vanishing-mark bug |
| `Heat.FullSlipSpeed` | 60 studs/s | Sideways drag that counts as heating at full rate |
| `Heat.RiseSeconds` / `FallSeconds` | 2.5 / 4 s | Cold to hot at full rate, and hot to cold at rest |
| `Heat.IdleSlipSpeed` | 3 studs/s | Below this the tyre cools whatever the gates say |
| `Stylized.*` | see the file | The second smoke layer: rate, size, lifetime, speed, spread, drag, tilt, colour |
| `Surfaces.<n>.PuffColour` | near white | The stylized layer's colour, per surface |

**The spec named one number for the look and the instances need thirty,** so the rest are ours and
are in `Config/Fx.luau` with a line each: `Marks.FadeAt`, `Marks.LightInfluence`,
`Marks.TextureLength`, and the whole of the `Smoke` and `Stylized` blocks beyond their rates —
lifetime, start and end size, transparency, speed, spread, the upward acceleration, drag, rotation
and lighting. `Surfaces.<name>` carries the three colours. **These are a first pass at a look and
nothing more: the look is the user's call.**

### What it is made of in Roblox

| The reference | Us | Why |
|---|---|---|
| `AudioClip` + `AudioSource` | One `Sound` per role, parented to the car's body part, `RollOffMode = InverseTapered` | 3D by default, so a second car is heard where it is |
| Pitch | `Sound.PlaybackSpeed` | |
| `TrailRenderer` | `Trail` between two `Attachment`s at the wheel's contact patch | Lifetime, width and colour all map directly |
| `ParticleSystem` | `ParticleEmitter` on one `Attachment` at the contact patch | `Rate` maps to `rateOverTime` |

**The budget**, and it is a formula and not a number, because the surfaces multiply it:

```
per car = 4 wheels × (2 Attachments + surfaces × (1 Trail + 2 ParticleEmitters))
```

At one surface that is **20**, plus two `Sound`s — one engine, one squeal per built surface. It was
16 before the stylized smoke layer, **32** with a four-rung darkness ladder, **28** with a
three-rung one, and **20 again** now the ladder is gone (`T-062`). Everything is made once when the
rig is caught and never again; nothing is created or destroyed while driving, and emitters are
switched with `Trail.Enabled` and `ParticleEmitter.Enabled`. **A frame that allocates is the thing
to measure and the thing to fail on.** Measured over a 60-second drive: **20 before and 20 after**,
the car's whole descendant count **62 either side**, 12 134 wheel-frames marking and **0 frames in
which a marking wheel was drawing nothing**.

**They hang off the car's `Body`, not off the wheels, and that is not a detail.** `Drift/Render`
spins each wheel about its own axle every frame (`CFrame.Angles(wheelSpin, 0, 0)`), so an
attachment parented to a wheel and offset down to the contact patch would **orbit the axle** and
draw a circle rather than a line. The `Body` part's CFrame *is* the car's pose, so the four contact
patches are four fixed local offsets on it, read straight off the rig's own wheel offsets.

**And the body LEANS, which is what buried the outside mark.** See "The vanishing outside mark"
below: `Render` rolls the body about the centre of mass, the roll swings each patch through an arc
far larger than the clearance they are drawn at, and the fix is to cancel it.

There is **no folder**: the eight attachments are direct children of `Body` (an `Attachment` has to
be parented to a `BasePart` to have a position), each wheel's `Trail`s and its diffuse emitter hang
off its first attachment, and its stylized emitter off the second. A folder would be one more
instance for nothing.

**A trail must be cut when the car jumps.** A spawn, a respawn or a `DebugTeleport` moves the body
hundreds or thousands of studs in one frame, and a `Trail` that is still enabled across that draws
one straight black line across the world. `Wheels:Cut()` puts everything out, and `DriftController`
calls it on all three paths before the car is put down. **It clears the tyre heat too** — a car that
has just been put down has cold tyres — which has a side effect worth knowing: on a road that is
respawning the car often, the heat never gets a chance to build.

## Round two: what the user asked for after driving it

The user drove the first build on 2026-11-06 and sent back three things. All three are built.

### 1. The vanishing outside mark, which was the body's lean

*"When you start to drift in one direction, the outside tyre stops showing the tyre mark. Almost
like it's being drawn below the road surface."* **It was being drawn below the road surface**, and
the guess was right about the symptom and wrong about the cause: it was not depth-fighting, and it
was not the trail switching off. It was the car leaning.

`Drift/Render` rolls the `Body` part about the car's centre of mass by `s.bodyRoll`, up to
`Config.Drift.BodyRollMax` (10°), so that the car leans out of a slide. The effects hang off that
part, 3.4 studs out from the centre of mass and 3.06 studs below it, so **the roll swings each
contact patch through an arc**: one side rises, the other sinks, and which side sinks flips with the
direction of the drift. That is exactly "the outside tyre".

**Measured, before the fix,** in a 40.3° slide at 49.9 studs/s with only **2.99°** of roll on the
body: the two left attachments sat **0.133 and 0.071 studs below** the road and the two right ones
**0.159 and 0.222 above** it. The trails were `Enabled` the whole time. `Marks.Lift` was 0.05. At
the full 10° the excursion reaches **0.637 studs up and 0.544 down** — more than ten times the
clearance.

**The fix is to cancel the roll, not to pay for it.** The body's transform about the centre of mass
is `C(com) · R(roll) · C(−com)`; each attachment is written the local position that transform maps
back onto the flat contact patch, which is `R(−roll)` about the same point — two scalars of
trigonometry a frame, shared across all eight, and no `CFrame`. The wheels themselves are drawn flat
by `Render` for the same reason, so this makes the marks agree with the wheels that leave them.
Round-tripped across the whole roll range in the tests, the residual is **2.4 × 10⁻⁷ studs**, which
is a `Vector3` being a float32 and nothing else.

**Measured after the fix,** at the worst lean a 60-second drive produced (4.96°): all eight
attachments within **0.0003 studs of each other**, where before they spanned 0.35.

**Half the bug was the clearance, though,** and that half is `Marks.Lift`, now 0.25 instead of 0.05.
With the lean cancelled, what is left is the car's own ride height moving as the model lands it on
the road each step, plus a little pitch over a grade — a range of about 0.4 studs. Over a 60-second
drive at 0.25: **7 frames out of 14 400 samples dipped below the road, by at most 0.031 studs**, and
the worst float was 0.69. The error is pushed **upward deliberately**: a mark below the road
vanishes, which is the bug, and a mark above it still draws. **The cost is that a mark can float up
to about seven tenths of a stud over a grade, and whether that reads is the user's eye.** The
alternative is a raycast per wheel per frame, which would place every mark exactly and allocate a
`RaycastResult` a wheel a frame to do it.

### 2. A second, stylized smoke layer

*"Add another layer on top of what we already have which is more STYLIZED. It should be easy to
trace back this new smoke to the specific wheel that it is coming from. It should also get more
intense the longer that specific wheel is drifting."*

**The diffuse layer is untouched** — the user approved it and it stays exactly as it was. `Stylized`
is a second `ParticleEmitter` per wheel, on top of it, and every number in it is chosen so a puff
can be traced to one tyre: **small** (0.9 studs born, 4.2 died, against the diffuse layer's 2.5 and
11) so four of them stay four of them; **tight** (a 7° cone against 18°) so it stays over its own
contact patch; **fast and draggy** (9–15 studs/s, drag 4.5) so it is flicked off the tyre and stops
near it; **short-lived** (0.30–0.55 s against 0.8–1.6) so the shape stays by the car; **opaque and
faintly self-lit** (0.18 transparency, 0.35 light emission) so it reads against the cloud behind it;
and **tilted 35° backward**, which is why it lives on the wheel's *second* attachment — the tilt is
that attachment's own `Orientation`, and the diffuse layer must not be tilted with it. A rotation
does not move a `Trail`, which reads the two attachments' positions, so the mark is untouched.

**Its rate, and only its rate, moves,** and that is deliberate: `Size`, `Transparency`, `Lifetime`
and `Speed` are each a `NumberSequence` or a `NumberRange`, which are objects, and writing one every
frame is the allocation this feature exists not to make.

### 3. Tyre heat, which drives both the puff and the darkness

The user's own link: *"the longer a drift goes, the hotter the tyres, and the more smoke is
produced — that tyre mark would be darker."* So there is one number per wheel, `heat`, 0..1, and it
is the only state this module keeps between frames.

It rises on **slip speed** — `speed × |sin(slip)|`, the speed the contact patch is being dragged
sideways across the road, which is what a real tyre heats and wears on — and falls when the wheel
stops working. **It takes the gates *and* the slip speed, and that is measured:** heating on the
gates alone left a wheel stuck hot, because a car that has caught a slide and rolled to a crawl
keeps a few degrees of residual slip, so its rear gates stayed open at a slip speed of 0.1 studs/s —
the heat could not rise (nothing was happening) and could not fall (the gate said it was sliding),
and it sat at **0.56 four seconds after the drift had ended**, idling in a cloud of its own stylized
smoke. `Heat.IdleSlipSpeed` is the floor that fixes it.

**Measured live, through one slide and out the other side** — the rears and the fronts, independently:

| | rear left heat / puff | front left heat / puff |
|---|---|---|
| start of the slide | 0.02 / 0.7 per s | 0.00 / 0 |
| +1 s | 0.08 / 3.4 | 0.00 / 0 |
| +2 s | 0.20 / 8.3 | 0.00 / 0 |
| the slide passes 30° | 0.30 / 12.7 | **0.08 / 3.6** — the fronts' gate opens |
| +1 s | 0.43 / 18.3 | 0.22 / 9.2 |
| the slide comes back under 30° | 0.52 / 21.8 | 0.14 / 6.1 — the fronts cool |
| +1 s | **0.57 / 23.9** still climbing | **0.02 / 0.7** nearly cold |

That last pair is the whole of "per wheel": the rears are at 0.57 and building while the fronts are
at 0.02 and cooling, in the same frame, on the same car.

### 4. The darkness ramp that was built and removed

**This section is a record of something that is no longer in the code.** It is here so that
nobody rebuilds it in six months without knowing what it costs.

The user asked for it: *"see if we can add an intensity variable… especially if the drift
continues as the car's speed lowers, meaning more rubber is deposited per foot."* It was built,
driven twice, fixed once, driven again, and then taken out at their word: *"didn't quite work with
the progressive shading — roll that back so it's just one shade of line. smoke and the rest is
good though."*

#### What it was

Darkness was **rubber laid per stud of road**, not per second:

```
speedTerm = (RefSpeed / max(speed, MinSpeedForDensity)) ^ SpeedExponent     slower is denser
angleTerm = |sin(slip)| ^ AngleExponent                                     sideways is more rubber
density   = speedTerm × angleTerm × (1 … HeatGain, by that wheel's heat)
```

It behaved exactly as specified. Measured: 45° of slip gave 0.877 at 30 studs/s against 0.458 at
110 — a slow mark **1.91×** the density of a fast one; 10°/45°/90° at 70 studs/s gave
0.061/0.574/1.000; a fully heated tyre multiplied it by exactly `HeatGain`. **The maths was never
the problem.**

#### Why it had to be a ladder of trails, and why that is fatal

**`Trail.Transparency` applies to the whole live ribbon, not to the segment being laid.** Turn it
down and the five seconds of mark already on the road behind you darken with it, which is not what
rubber does. A mark has to keep the darkness it was laid at — so a varying darkness cannot be a
number at all. It has to be **one trail per darkness**, all strung between the same two
attachments, switching between them.

**And every switch is a hole in the mark**, because the incoming trail has no points yet and draws
nothing until the contact patch has moved. That is not a bug in the implementation; it is the
shape. Measured over 1 081 grounded frames of a drift that slowed across the ladder: the rear
wheels changed band **58 times**, the fronts **30**, and most of those swaps were **0 or 1 stud
apart**.

#### What it cost to make the holes go away

Four numbers, none of which would exist without the ramp:

| | |
|---|---|
| `Marks.SwapOverlap` | The outgoing band keeps drawing after the incoming one starts, so the ribbons overlap and a swap becomes a splice. The only thing that actually closed the hole |
| `Marks.BandHysteresis` | So a density on a boundary does not swap every frame |
| `Marks.Bands` cut 4 → 3 | Every boundary is a swap waiting to happen |
| `Marks.MinSegment` | Set to 0.5 as a **wrong** guess at the cause, which made the dashes longer, then put back to 0 |

It worked: after those, **0 blank frames** over 1 438 grounded frames crossing all three bands. It
cost 12 extra instances a car, two rounds, and a user who had to send the marks back twice.

#### What was kept when it came out

- **The tyre heat** (`Heat.*`, `Wheels.heatStep`, `Wheels.slipSpeed`). It drove the ramp *and* the
  stylized smoke; the smoke is approved, so the heat stays. Nothing else reads it now.
- **`Gates.StopSlipDegrees`**, the sticky slip gate. Found while chasing the holes, but a separate
  fault: a car sitting on the slip threshold flicking its marks on and off is wrong with or
  without a ramp.
- **`Marks.MinSegment = 0`**, so a mark starts drawing on its first frame. Measured after the
  rollback: still 0 blank frames, so the rungs it was once blamed for have not come back.
- **The roll cancel and `Marks.Lift`**, which have nothing to do with darkness.

Gone with it: `Wheels.density`, `bandFor`, `bandWith`, `Marks.Bands`, `BandHysteresis`,
`SwapOverlap`, `RefSpeed`, `SpeedExponent`, `AngleExponent`, `MinSpeedForDensity`, `HeatGain`, and
the band half of `DebugWheels`.

#### What a mark is now

One `Trail` per wheel per surface at `Marks.Transparency` = **0.52**, chosen as the **middle rung
of the three-band ladder that was there** (0.70, 0.52, 0.34). An ordinary drift spent most of its
time in the middle of that ladder, so this reads about as the marks did — without the light end
going faint or the dark end going to paint. **It is one number and the whole look of a mark is in
it**; lower is darker.

## UI

None. The effects are on the car.

A line goes in `SETTINGS.md`: the reference carries a *show effects* switch and a device that
cannot afford smoke will want one. Not built this round; `SetEmitable` is where it would land.

## Server and client

**All of it is the client's, and it must be,** for the same reason `Drift/Render` is: the car is a
client-side simulation and the server never knows the slip angle. The server already re-asserts a
car's parts; effects hang off those parts and are made locally on each client.

- **Your own car:** driven from your own `Drift/Model` state, every frame, exactly as `Render` is.
- **Another player's car:** `Drift/RemoteCars` has position and yaw and **not** slip, throttle or
  handbrake. Two honest options, and the plan's last step picks one with a measurement rather than
  an opinion: *(a)* derive a slip angle on each client from the remote car's own velocity and
  heading, which is what the numbers it already sends make possible; or *(b)* leave remote cars
  silent and unmarked this round. Nothing in the network contract changes either way.
- **Nothing is replicated.** No remote, no new packet field, no server-side instance.

## Contracts

In `CONTRACTS.md`. **What `T-062` built, for the conductor to record at merge:**

| Entry | Surface |
|---|---|
| `Shared/Config/Fx` | `Config.Fx`: `Marks`, `Smoke`, `Gates`, `Surfaces`, `Built`, `Default`, `Names`, and `Engine` and `Skid` which nothing reads until `T-064`. A plain table with no write guard, like `Config.Road` |
| `Drift/Wheels` | `new()`, `Attach(rig) -> boolean`, `Update(state, input, dt)`, `Cut()`, `Clear()`, `SetEnabled(on) -> boolean`, `SetMarkSeconds(s)`, `DebugState(state, input)`, `CountInstances() -> number`, and the pure `Wheels.evaluate(state, handbrake, front, down, marking) -> (emit, rate, slipPast, throttleOk, handbrakeOk)`, `surfaceOf(state, index, down) -> string?`, `slipSpeed(state)`, `heatStep(heat, sliding, slipSpeed, dt)`, `stylizedRate(heat)`, and the roll pair `patchLocal(patch, com, cosR, sinR)` / `applyRoll(p, com, cosR, sinR)`. **`Update` takes the INPUT as well as the state**: the handbrake is a `Drift/Model` *input* and is not on the state. **`evaluate`'s fifth argument is whether that wheel was already marking**, which is the slip gate's hysteresis. **`Cut()` clears the tyre heat as well as the emitters.** **Gone in round four with the darkness ramp:** `density`, `bandFor`, `bandWith` |
| `DriftController` | `DebugWheels() -> { enabled, attached, instances, liveInstances, surfaces, rollDeg, slipDeg, throttle, handbrake, speed, slipSpeed, airborne, wheels: { { name, front, down, surface, thresholdDeg, slipPast, throttleOk, handbrakeOk, emit, emitting, heat, lit, rate, stylizedRate, leanOffsetY, patchResidualY } } }` and `DebugWheelFx(on: boolean?) -> boolean`. Studio only, through the client debug bridge. **`lit` is how many of that wheel's trails are drawing**: 1 while marking, 0 otherwise — and **0 while `emitting` is a gap in the mark**, which is the number the "zero gaps" bar is measured with and the reason the darkness ladder was removed. **Gone in round four:** `bands`, and per-wheel `density`, `band`, `bandOn`, `fading`, `swaps` |
| Instance names on a rig | `Config.Fx.Names`: `FxA_<Wheel>_<L\|R>` (8 `Attachment`s, direct children of `Body`), `FxMark_<Wheel>_<surface>` (4 `Trail`s), `FxSmoke_<Wheel>_<surface>` (4 diffuse `ParticleEmitter`s) and `FxPuff_<Wheel>_<surface>` (4 stylized ones). The trail and the diffuse emitter hang off that wheel's `_L` attachment; the stylized emitter off its `_R` one, which carries the backward tilt |

**What `T-064` added, for the conductor to record at merge:**

| Entry | Surface |
|---|---|
| `Shared/Config/Fx` | `Engine` grows `Volume`, `SoundId`, `RollOffMin`, `RollOffMax`; `Skid` grows `Volume`, `SoundIds` (a table keyed by surface) and the same two roll-off numbers; `Names` grows `Engine` and `Skid` |
| `Drift/EngineSound` | `new()`, `Attach(rig) -> boolean`, `Update(state, input, dt)`, `Cut()`, `Clear()`, `SetEnabled(on) -> boolean`, `ResetMeasure() -> number`, `CountInstances() -> number`, `DebugState(state)`, and the pure `EngineSound.gearTops(topSpeed, out) -> out`, `.gearBottom(tops, gear)`, `.wanted(tops, gear, speed) -> gear` and `.pitchFor(tops, gear, speed) -> pitch`. `Cut()` puts the box back into first: a respawn must not walk down five gears half a second each |
| `Drift/SkidSound` | The same shape, plus the pure `SkidSound.volumeFor(state) -> 0..1` and `.surfaceOf(state) -> string?`. `surfaceOf` delegates to `Wheels.surfaceOf`, so there is exactly one rule in the game for what a wheel is standing on |
| `DriftController` | `DebugSound() -> { engine, skid }`, `DebugSoundMeasure() -> { engine, skid }` (the largest single-frame change in each lerped value since the last call, and reset) and `DebugSoundFx(on: boolean?) -> boolean`. Studio only, through the client debug bridge |
| Instance names on a rig | `Config.Fx.Names`: `FxEngine` (one `Sound`) and `FxSkid_<surface>` (one `Sound` per built surface), both direct children of `Body` |

**No `Hit` change:** the per-wheel surface gap is deferred, as planned. **No remote, no packet field,
no server instance:** `T-064` is the client and the local car only, as this spec says it must be.

## Analytics

None. Nothing here is a player action, and the loop's events are designed with scoring
(`endless-run.md`).

## Monetization

None in this round. It is worth writing down that it is **the obvious hook for the cosmetic
direction already proposed** (`PITCH.md`: "cars, liveries and trail effects"): coloured smoke and
coloured tyre marks are two numbers in `Config/Fx.luau` each, and a sold one would be a value on
the car rather than new code. Not in this plan.

## Platform risks

- **Audio copyright is the real one.** Every sound must be either a Creator Store asset (licensed
  for any experience, nothing to upload) or something from a library that allows games, recorded in
  `assets/audio/<topic>/MANIFEST.md` with its license (`AUDIO-PIPELINE.md`). **No sound from the
  reference game, ever** — not a clip, not a render of one, not a name.
- **No audio generation tool is set up on this PC** (`MODELS.md`: "None yet: the user picks a tool
  and a plan that allows commercial use"), so every candidate this round comes from the Creator
  Store, found by `asset-scout`. If nothing there is right, that is a decision for the user about a
  tool and a plan, not something to work around.
- The car is still the AE86 placeholder, which is not approved to publish
  (`drift-model.md` "Platform risks"). Unchanged by this.

## Art and sound

Two sounds in the end, both 3D and both looping. **Picked by the user on 2026-11-04 and recorded in
`AUDIO.md`,** which is the registry; the ids themselves are in `Config/Fx.luau` so the modules read
one file.

| Role | Shape | What shipped |
|---|---|---|
| Engine | Seamless loop, a low steady note with no obvious pitch movement of its own — it is going to be stretched from 0.7× to 2.2× and anything musical in it will warble | Creator Store `5015124019`, "Car idle", 4.638 s measured |
| Tyre squeal, tarmac | Seamless loop, continuous, no transient at the start | Creator Store `124978127809544`, "tyre_slide", 2.996 s measured |
| Backfire pop | One-shot, short | **None. The user said no** (`AUDIO.md`) |

**Whether either loop is seamless under stretch is the one thing no measurement here answers.** It
is a question for the user's ear on a focused window, and if an answer comes back "it warbles", the
fix is a different pick and not a tuning number.

**The user picks, from candidates, as they do with art** (`AGENTS.md`). Rocco's cards play sound
options, so the pick is a question on a card, not a file to open.

No images: the smoke is a built-in particle texture and the tyre marks are a flat colour.

### The direction, which this feature's approval set

**`AUDIO.md` "Direction" is no longer empty:** approving this plan on 2026-11-04 filled it, and it
is the doc to read and to keep. In short — pillars *weighty, clean, never harsh*; the squeal on top,
the engine under it, everything else under both; realistic and not cartoon.

The mix is two numbers and they are in `Config/Fx.luau`: `Engine.Volume` 0.45 and `Skid.Volume`
0.85, the latter a master over the `RollVolume`/`MinVolume`..`MaxVolume` curve. Both are a first
pass and both are an ear's call.

## Testing

A playtest on the endless road, and a test file, `Tests/FxTests.luau` — but note what can and
cannot be measured: **sound is the user's ear, and the test's job is the state machine, not the
feel.**

| Check | Measured |
|---|---|
| The gearbox | Drive 0 → top speed and record every shift's speed. They must match the computed series within `GearOverlap`, and no two shifts within `MinTimeInGear`. **Done (`T-064`):** the five tops are 13.57, 33.93, 64.47, 110.28 and 179.00 studs/s, which is the series to 1e-6 and `TopSpeed` exactly. Live on `DR-Lane2`'s plate, a straight run to 162 studs/s shifted at **23.63, 44.02, 74.53 and 120.34**, each **+10.05 to +10.09** past its band edge — the overlap, to a hundredth. And slammed from a standstill to top speed in one frame, the box still walks up one gear every 0.517 s against a 0.5 s debounce |
| Pitch is continuous | The largest single-frame change in `PlaybackSpeed` over a full-speed run, which must be bounded by `PitchLerpSpeed × dt`. **Done:** 0.01322 live over the straight run and 0.01379 over a 60-second drive, against a bound of 0.05 at Studio's unfocused 30 fps; 0.01905 against 0.02500 in the synthetic 60 fps run. **What makes a shift a shift, measured:** the pitch target drops 2.20 → 1.44 at the 1-2 and 1.01, 1.17 and 1.28 at the three above it, and the lerp walks the sound down each gap instead of stepping |
| Airborne | Off a crest or a fall: pitch at `MaxPitch`, skid volume 0, no trail emitting. **Done:** off the playground ramp, 135 airborne frames, peak 17.3 studs up — the pitch target was `MaxPitch` on **every one of them** and the pitch climbed 1.89 → 2.10 across the 1.3 s of air (the lerp, not a snap), with the squeal at **0.00000000** and its clip stopped throughout |
| The squeal tracks the angle | Volume at 10°, 45° and 90° of slip against the configured lerp, and 0 when airborne, under `MinSkidSpeed` or with no state. **Done (`T-064`, re-measured for `T-083`):** 10° → 0.2833, 45° → 0.4000, 90° → 0.5500, each **exactly** the configured lerp, worst gap 0.00e+00; it stays at 0.5500 at 120° and 180°. Silent airborne at 90°, silent at 3.59 studs/s and not at 3.60, silent with no state. The `T-064` live figures (10.04° → 0.3337, 45.07° → 0.6256, 89.70° → 0.9975, worst gap 1.11e-16 over 1 921 samples) were against the old ceiling of 1 and are the record of that curve, not this one |
| The roll hiss and the step into a drift (`T-083`) | 0°, 2° and 4.9° all read **0.1200** = `RollVolume`; 4.99° → 0.1200 and 5.00° → 0.2667, a step of **0.1467** at the model's own `MinSlipAngleForDrift`. **It does not click:** the largest single-frame volume move crossing it is **0.00244 at 60 fps** and 0.00489 at 30, against 0.00486 before this change — when the clip started from silence the first frame moved it *twice as far* |
| `RollVolume = 0` and `MaxVolume = 1` restore the old curve | **Done, and checked in `FxTests` so it stays true:** 0/2/4.9/5/10/30/60/90/120° → 0, 0, 0, 0.2917, 0.3333, 0.5000, 0.7500, 1.0000, 1.0000 — the pre-`T-083` numbers exactly, worst gap 0.00e+00 |
| The clip is started once and left running (`T-083`) | **Done, both ways.** On a stand-in body with the master forced to 0: 8 s of straight → 60° of slip → straight gave **1 `Play()` and 0 `Stop()`s**, and the clip stopped only when the car went airborne and when it dropped under `MinSpeed`. Live in `DR-Lane2`, a 14 s quiet playtest sampled four times a second across a drift (slip 0° → −101° → caught → held at −30° → straight) kept the logic's running flag **true for the whole drift**: the only two transitions in the run were the car spinning itself to 2.71 studs/s, under `MinSpeed`, and coming back 0.26 s later |
| A quiet playtest is silent | **Done, and this is the one to re-check whenever a sound is added.** With the `__agent_play` marker set, the two `Sound`s on the car are at **volume 0.0000 and were never started** — of the five `Sound`s anywhere in the datamodel the only non-zero volumes were Roblox's own CoreGui clips, none of them playing. The logic runs anyway, so a silent playtest still measures the whole state machine. The other branch is proved the same way and just as silently: a fresh require with the marker cleared, on a body in `ServerStorage`, gives engine volume 0.4500 playing and squeal 0.6375 = 0.85 × 0.75 at 60° of slip (that 0.75 was the pre-`T-083` curve; the same check today reads 0.85 × 0.45 = 0.3825) |
| The front/rear threshold | Hold a slide at 20° and at 60°: at 20° the two rear trails emit and the two fronts do not; at 60° all four do. **Done (`T-062`):** live in `DR-Lane2` at 18.8° only `WheelRL` and `WheelRR` emitted, at 59.5° all four; and the pure sweep puts the fronts' switch-on at 30.5° against a configured 30 + 0.5 and the rears' at 0.50° |
| Throttle gate | Coast sideways at zero throttle: slip above the threshold, no trail, no smoke. **Done in `FxTests`, and NOT reachable live** — the throttle is never an input in this model (see "How it plays"). 60° of slip at zero throttle marks nothing; it marks at exactly `MinThrottle` and not a hundredth below |
| Handbrake | Handbrake from a standstill (nothing) and from 40 studs/s (all four, smoking). **Done (`T-062`):** live, nothing at 0.00 studs/s; all four emitting at 36.7 studs/s with the car dead straight (`slipPast` false) and off nothing but the brake |
| Smoke rate | `ParticleEmitter.Rate` at 10°, 45° and 90° of slip against the configured lerp. **Done:** 10.89, 21.00 and 34.00 /s against the same three computed from the config, to within 1e-6, and 8.00 .. 60.00 at the two ends |
| It allocates nothing — sounds included | Instance count on the rig before a 60-second drive and after: **identical**. The number that would fail this is the one worth having. **Round one:** 16 → 16, car descendants 56 → 56. **With the sounds (`T-064`):** 2 → 2 Sounds, Body descendants 18 → 18, whole car 58 → 58. **Round two, four bands:** 32 → 32, whole car 74 → 74. **Round three, three bands:** 28 → 28, whole car 70 → 70. **Round four, no bands:** **20 → 20** (4 trails, 8 emitters, 8 attachments) and the whole car **62 → 62** over a 60-second drive with 0 airborne frames; and 20 → 20 over 1 000 synthetic frames in `FxTests` |
| The lean, which was the bug | Each trail attachment's height above the road under it, through a real drift. **Before:** at 2.99° of body roll, the two left ones 0.133 and 0.071 studs **below** the road and the two right ones 0.159 and 0.222 **above** it; at the full `BodyRollMax` the excursion is 0.637 up and 0.544 down against 0.05 studs of clearance. **After:** at the worst lean a 60-second drive produced (4.96°), all eight within **0.0003 studs of each other**; 7 frames in 14 400 samples below the road by at most 0.031 studs, worst float 0.69. The cancelling round-trips to **2.4 × 10⁻⁷ studs** across the whole roll range in `FxTests` |
| The darkness ramp | Measured, worked, and removed at the user's call — the numbers and what they cost are in "The darkness ramp that was built and removed". **What is checked now:** a mark has exactly one darkness and there is no `Bands` table at all |
| The smoke is untouched by the rollback | The heat still builds per wheel and the stylized rate still follows it. Over the same 60-second drive: hottest tyre **0.66**, peak stylized rate **27.7/s**. Through one slide: the front left went 0.02 → 0.46 while the rear left went 0.32 → 0.75, the rears ahead of the fronts throughout, and `lit` was 1 on every sample |
| Tyre heat, per wheel | Live through one slide: the rear left went **0.02 → 0.57** (stylized rate 0.7 → 23.9 per second) while the front left only started once the slide passed its 30° threshold, reached 0.22, and was back to **0.02 and cooling** in the same frame the rears read 0.57 and climbing. In `FxTests`: full in 2.50 s at full slip speed, 5.02 s at half it, cold again in 4.02 s, and **cold in 4.02 s even with the gates held open** at a crawl |
| The mark broke into dashes | **Round three, and the round-two diagnosis was wrong.** Measured over 1 081 grounded frames of a drift that slowed across the ladder: the rear wheels changed band **58 times** and the fronts **30**, and most of those swaps were **0 or 1 stud apart** — a swap is a hole by construction, because the incoming trail has no points. `Marks.MinSegment = 0.5`, added in round two to cure what looked like the same symptom, then made every fresh trail wait half a stud before drawing, which turned hairline joins into long clean dashes. A third source in the same sample: the slip gate had no hysteresis and chattered at a density of 0.00 with the slip sitting on half a degree |
| And zero gaps after it | The bar was zero and the measure is frames in which a wheel is marking but nothing is drawn. **Round three, with the ladder spliced:** 0 blank over 1 438 grounded frames crossing all three bands, and 0 over a 60-second drive of 10 150 marking wheel-frames. **Round four, with the ladder gone:** **0 blank over a 60-second drive of 12 134 marking wheel-frames**, and 0 over 1 000 synthetic frames x 4 wheels in `FxTests`, where **never more than one of a wheel's trails is drawing** because there is only one. Photographed: about 240 studs of mark, four unbroken lines, one even shade |
| Frame cost | Frame time over a 60-second drive, effects on and off, on this PC. A cost worth naming is a cost worth a `SETTINGS.md` switch. **Measured and inconclusive, and the reason is worth writing down:** Studio throttles rendering to exactly 30 fps when its window is not focused, which an agent's window never is. Interleaved in 5-second blocks inside one drive, 900 frames each way, the medians were 33.3028 ms with the effects on and 33.2936 ms with them off — **9 microseconds apart, both pinned at the cap.** All that proves is that the effects do not push a 30 fps frame over its budget. **A real headroom number needs the user's own focused window,** and `DriftController:DebugWheelFx(false)` is the switch to take it with |

`DebugState()` on each of the three modules, reporting what it is doing and why — the gear and
pitch, the skid volume and its gate, and each wheel's four gates — so a playtest can say *which*
gate is wrong rather than "no smoke".

## Open questions

- ~~**The sounds themselves.**~~ **Closed 2026-11-04:** the user picked both by ear and decided
  against a backfire (`AUDIO.md`).
- **`MinPitch` and `MaxPitch`, still open, and the one thing `T-064` could not settle.** The spec's
  0.7 and 2.2 are what shipped, unchanged, **because an agent cannot hear.** What could be argued
  from numbers is in `Config/Fx.luau` beside them: the 3.14 ratio is about what a real gear sweeps;
  the shift drops are 0.76, 1.01, 1.17 and 1.28 of pitch, so narrowing the sweep would make the 4-5
  shift stop reading as a shift; and the clip is a 4.64 s **idle**, so 0.7× stretches a cycle to
  6.63 s and pushes it about five semitones below idle, into what a phone speaker reproduces least.
  **Drive it and say** — one number each, nothing else changes.
- **Whether `PitchLerpSpeed = 1 /s` is right.** It is the reference's, and it means the 0.76-pitch
  fall at the 1-2 shift takes about a second: the shift *slides* rather than snapping. Measured live
  and correct; whether it is slow is an ear's call.
- **The roll hiss does not scale with speed** (`T-083`). `RollVolume` is one number: a car creeping
  at 4 studs/s hisses exactly as loudly as one at 179. **The reference's does not scale either** — it
  is a flat per-clip minimum there too — so this is a faithful port and not an oversight. If the
  user dislikes it, the obvious refinement is a speed ramp on `RollVolume` (a lerp from near 0 at
  `MinSpeed` to 0.12 somewhere in the speed range), which is a few lines in `volumeFor` and two more
  config numbers. **Drive it first.**
- **Remote cars** (above): derived slip, or silent this round.
- **The backfire,** which needs an exhaust position per body. **The user decided against it for now**
  (`AUDIO.md`); the spec stays here so it need not be read off the reference twice.
- **An effects switch in settings,** once the frame cost is measured. `Wheels:SetEnabled` and
  `DriftController:DebugWheelFx` are already the switch; what is missing is a focused-window
  measurement to say whether it is worth a setting.
- **Coloured smoke and marks as a cosmetic,** which is a monetization decision and not this round's.

Added by `T-062`, from building it:

- **The look of the marks and the smoke.** The user's call, and the numbers to change are all in
  `Config/Fx.luau` under `Marks`, `Smoke`, `Stylized` and `Surfaces`.
- **Whether the smoke should be full at 90° rather than 180°.** The reference lerps the rate by
  `slip / π`, which is what is built — so a car fully sideways at 90° is only at 34 of 60. The
  squeal's own `MaxSlipDegrees` is 90. One number, `Gates.MaxSlipDegrees`.
- **Whether a crawling car should mark at all.** There is no minimum speed on the marks, only on
  the handbrake, which is what the reference does. Measured: a car creeping at 0.3 studs/s with
  14° of slip still has its rear trails enabled. It lays a dot, not a line, so it costs nothing to
  leave — but a `Gates.MinMarkSpeed` is a one-line addition if the user ever sees it.

Added by `T-062` round two, and these are the ones to drive and judge:

- ~~**The ladder fix is reasoned, not photographed.**~~ **Closed, and it was wrong.** The user
  photographed it and `Marks.MinSegment = 0.5` had made the breaks worse, not better. Round three
  measured the real cause (band chatter) and put `MinSegment` back to 0. **The lesson is worth
  keeping: a look fix that cannot be photographed should not be shipped as a fix, only as a
  guess.**
- **Whether a mark floating up to 0.7 studs over a grade reads wrong.** That is `Marks.Lift` at
  0.25, deliberately biased upward because a mark below the road vanishes and one above it does
  not. Dropping it trades float for the occasional dropout. The exact fix is a raycast per wheel per
  frame, which costs a `RaycastResult` a wheel a frame.
- **The one shade, which is now the whole look of a mark.** `Marks.Transparency` is 0.52, the
  middle rung of the ladder that was there. If marks read too faint or too much like paint, it is
  one number. **A darkness that varies along the mark is not one number** — see "The darkness ramp
  that was built and removed" before reaching for it again.
- **Whether the stylized layer is too much, or not enough.** It is zero at a cold tyre and 42 a
  second at a hot one, and nothing but the rate moves. If it should also *grow* with heat, that is a
  `NumberSequence` a frame and would have to be done as a ladder, the same way the marks are.
- **Whether the tyre heat should survive a respawn.** It does not: `Wheels:Cut()` clears it, on the
  reasoning that a car just put down has cold tyres. On a road that is respawning the car often, the
  heat never builds — which is what a 60-second drive full of respawns measured, at a hottest tyre
  of 0.00.

