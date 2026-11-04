# Feature: The car's sound and wheel effects

**Status:** approved; **built**, all three steps. **Owner task:** `T-056`.

| Part | State |
|---|---|
| Tyre marks and smoke, four gates, per wheel, per surface | **Built** — `Config/Fx.luau`, `Drift/Wheels.luau`, `Tests/FxTests.luau` (`T-062`) |
| Engine note and the gearbox that does not exist | **Built** — `Config/Fx.luau` `Engine`, `Drift/EngineSound.luau` (`T-064`) |
| Tyre squeal | **Built** — `Config/Fx.luau` `Skid`, `Drift/SkidSound.luau` (`T-064`) |
| Backfire | Not built, and deliberately — the user decided against it, 2026-11-04 (`AUDIO.md`) |
| Remote cars | Not built, and out of scope for this round |

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

### Skid sound: one loop per surface, volume by slip angle

One looping clip **per surface type**, all of them live at once, each one's volume lerped rather
than switched:

- Volume is `lerp(MinSkidVolume, 1, slip / maxSlip)` while the car counts as drifting, and **0**
  when it does not, when it is airborne, or when horizontal speed is under `MinSkidSpeed`.
- The lerped-toward volume means a drift fades in and out instead of clicking on.
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
| `MinSpeed` | 3.6 studs/s | `MinSkidSpeed` | Below this, silence |
| `MinVolume` | 0.25 | `MinSkidVolume` | The volume a drift that has just begun plays at |
| `MaxSlipDegrees` | 90 | — | The angle the squeal is full at |
| `VolumeLerpSpeed` | 1 /s | `SkidVolumeLerpSpeed` | Fade in and out |
| `Volume` | 0.85 | — | **Ours, and new.** The master the mix sets, on top of the `MinVolume`..1 lerp: the squeal is the loudest thing in a drift and still has somewhere to go (`AUDIO.md` "Mix") |
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

**The spec named one number for the look and the instances need fifteen,** so the rest are ours and
are in `Config/Fx.luau` with a line each: `Marks.Lift` (0.05 studs, which stops a mark z-fighting
the road it is drawn on), `Marks.Transparency`, `Marks.FadeAt`, `Marks.LightInfluence`,
`Marks.TextureLength`, and the whole of the `Smoke` block beyond its rate — lifetime, start and end
size, transparency, speed, spread, the upward acceleration, drag, rotation and lighting.
`Surfaces.<name>.MarkColour` and `.SmokeColour` are the per-surface look, and `Built` is the list of
surfaces a car is actually given instances for. **These are a first pass at a look and nothing
more: the look is the user's call.**

### What it is made of in Roblox

| The reference | Us | Why |
|---|---|---|
| `AudioClip` + `AudioSource` | One `Sound` per role, parented to the car's body part, `RollOffMode = InverseTapered` | 3D by default, so a second car is heard where it is |
| Pitch | `Sound.PlaybackSpeed` | |
| `TrailRenderer` | `Trail` between two `Attachment`s at the wheel's contact patch | Lifetime, width and colour all map directly |
| `ParticleSystem` | `ParticleEmitter` on one `Attachment` at the contact patch | `Rate` maps to `rateOverTime` |

**The budget:** four wheels × (one `Trail` + one `ParticleEmitter` + two `Attachment`s) = 16
instances per car, **plus two `Sound`s** — one engine, one squeal per built surface — made once when
the rig is built and never again. Nothing is created or destroyed
while driving; emitters are switched with `Trail.Enabled` and `ParticleEmitter.Enabled`. **A frame
that allocates is the thing to measure and the thing to fail on.** Measured: 16 before a 60-second
drive and 16 after, and the car's whole descendant count 56 either side.

**They hang off the car's `Body`, not off the wheels, and that is not a detail.** `Drift/Render`
spins each wheel about its own axle every frame (`CFrame.Angles(wheelSpin, 0, 0)`), so an
attachment parented to a wheel and offset down to the contact patch would **orbit the axle** and
draw a circle rather than a line. The `Body` part's CFrame *is* the car's pose, so the four contact
patches are four fixed local offsets on it, read straight off the rig's own wheel offsets. The only
error this costs is the body's cosmetic lean (`s.bodyRoll`, a couple of degrees), which moves a
patch by hundredths of a stud — less than the mark is wide, and arguably the honest place for it.

There is **no folder**: the eight attachments are direct children of `Body` (an `Attachment` has to
be parented to a `BasePart` to have a position), and each wheel's `Trail` and `ParticleEmitter` hang
off its first attachment. A folder would be a seventeenth instance for nothing.

**A trail must be cut when the car jumps.** A spawn, a respawn or a `DebugTeleport` moves the body
hundreds or thousands of studs in one frame, and a `Trail` that is still enabled across that draws
one straight black line across the world. `Wheels:Cut()` puts everything out, and `DriftController`
calls it on all three paths before the car is put down.

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
| `Drift/Wheels` | `new()`, `Attach(rig) -> boolean`, `Update(state, input, dt)`, `Cut()`, `Clear()`, `SetEnabled(on) -> boolean`, `SetMarkSeconds(s)`, `DebugState(state, input)`, `CountInstances() -> number`, and the pure `Wheels.evaluate(state, handbrake, front, down) -> (emit, rate, slipPast, throttleOk, handbrakeOk)` and `Wheels.surfaceOf(state, index, down) -> string?`. **`Update` takes the INPUT as well as the state**, unlike the `update(state, dt)` this spec first guessed at: the handbrake is a `Drift/Model` *input* and is not on the state, and there is nowhere else honest to read it |
| `DriftController` | `DebugWheels() -> { enabled, attached, instances, liveInstances, surfaces, slipDeg, throttle, handbrake, speed, airborne, wheels: { { name, front, down, surface, thresholdDeg, slipPast, throttleOk, handbrakeOk, emit, emitting, rate } } }` and `DebugWheelFx(on: boolean?) -> boolean`. Studio only, through the client debug bridge |
| Instance names on a rig | `Config.Fx.Names`: `FxA_<Wheel>_<L\|R>` (8 `Attachment`s, direct children of `Body`), `FxMark_<Wheel>_<surface>` (4 `Trail`s) and `FxSmoke_<Wheel>_<surface>` (4 `ParticleEmitter`s), each parented to that wheel's `_L` attachment |

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
0.85, the latter a master over the `MinVolume`..1 lerp. Both are a first pass and both are an ear's
call.

## Testing

A playtest on the endless road, and a test file, `Tests/FxTests.luau` — but note what can and
cannot be measured: **sound is the user's ear, and the test's job is the state machine, not the
feel.**

| Check | Measured |
|---|---|
| The gearbox | Drive 0 → top speed and record every shift's speed. They must match the computed series within `GearOverlap`, and no two shifts within `MinTimeInGear`. **Done (`T-064`):** the five tops are 13.57, 33.93, 64.47, 110.28 and 179.00 studs/s, which is the series to 1e-6 and `TopSpeed` exactly. Live on `DR-Lane2`'s plate, a straight run to 162 studs/s shifted at **23.63, 44.02, 74.53 and 120.34**, each **+10.05 to +10.09** past its band edge — the overlap, to a hundredth. And slammed from a standstill to top speed in one frame, the box still walks up one gear every 0.517 s against a 0.5 s debounce |
| Pitch is continuous | The largest single-frame change in `PlaybackSpeed` over a full-speed run, which must be bounded by `PitchLerpSpeed × dt`. **Done:** 0.01322 live over the straight run and 0.01379 over a 60-second drive, against a bound of 0.05 at Studio's unfocused 30 fps; 0.01905 against 0.02500 in the synthetic 60 fps run. **What makes a shift a shift, measured:** the pitch target drops 2.20 → 1.44 at the 1-2 and 1.01, 1.17 and 1.28 at the three above it, and the lerp walks the sound down each gap instead of stepping |
| Airborne | Off a crest or a fall: pitch at `MaxPitch`, skid volume 0, no trail emitting. **Done:** off the playground ramp, 135 airborne frames, peak 17.3 studs up — the pitch target was `MaxPitch` on **every one of them** and the pitch climbed 1.89 → 2.10 across the 1.3 s of air (the lerp, not a snap), with the squeal at **0.00000000** and its clip stopped throughout |
| The squeal tracks the angle | Volume at 10°, 45° and 90° of slip against the configured lerp, and 0 when not drifting, airborne or under `MinSkidSpeed`. **Done, live:** 10.04° → 0.3337, 45.07° → 0.6256, 89.70° → 0.9975, each **exactly** the configured lerp; over 1 921 live samples the worst gap to it was 1.11e-16, and every sample the model did not call drifting had a target of 0. In `FxTests`, silent at 4.99° and loud at 5.00° (the model's own `MinSlipAngleForDrift`, not a second threshold), silent at 3.59 studs/s and not at 3.60, silent airborne at 90° |
| A quiet playtest is silent | **Done, and this is the one to re-check whenever a sound is added.** With the `__agent_play` marker set, the two `Sound`s on the car are at **volume 0.0000 and were never started** — of the five `Sound`s anywhere in the datamodel the only non-zero volumes were Roblox's own CoreGui clips, none of them playing. The logic runs anyway, so a silent playtest still measures the whole state machine. The other branch is proved the same way and just as silently: a fresh require with the marker cleared, on a body in `ServerStorage`, gives engine volume 0.4500 playing and squeal 0.6375 = 0.85 × 0.75 at 60° of slip |
| The front/rear threshold | Hold a slide at 20° and at 60°: at 20° the two rear trails emit and the two fronts do not; at 60° all four do. **Done (`T-062`):** live in `DR-Lane2` at 18.8° only `WheelRL` and `WheelRR` emitted, at 59.5° all four; and the pure sweep puts the fronts' switch-on at 30.5° against a configured 30 + 0.5 and the rears' at 0.50° |
| Throttle gate | Coast sideways at zero throttle: slip above the threshold, no trail, no smoke. **Done in `FxTests`, and NOT reachable live** — the throttle is never an input in this model (see "How it plays"). 60° of slip at zero throttle marks nothing; it marks at exactly `MinThrottle` and not a hundredth below |
| Handbrake | Handbrake from a standstill (nothing) and from 40 studs/s (all four, smoking). **Done (`T-062`):** live, nothing at 0.00 studs/s; all four emitting at 36.7 studs/s with the car dead straight (`slipPast` false) and off nothing but the brake |
| Smoke rate | `ParticleEmitter.Rate` at 10°, 45° and 90° of slip against the configured lerp. **Done:** 10.89, 21.00 and 34.00 /s against the same three computed from the config, to within 1e-6, and 8.00 .. 60.00 at the two ends |
| It allocates nothing — sounds included | Instance count on the rig before a 60-second drive and after: **identical**. The number that would fail this is the one worth having. **Done:** 16 → 16, and the car's whole descendant count 56 → 56, over 60 s of a drive that was sliding past 5° on 2 884 of its frames; and 16 → 16 over 1 000 synthetic frames with 272 gate flips in `FxTests`. **With the sounds (`T-064`):** the same drive, 60 s with 13 shifts and 4 730 drifting samples, left the two `Sound`s at 2 → 2, the `Body`'s descendants at **18 → 18** and the whole car's at **58 → 58**; and 2 → 2 over 3 120 synthetic frames in `FxTests` |
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
- **Remote cars** (above): derived slip, or silent this round.
- **The backfire,** which needs an exhaust position per body. **The user decided against it for now**
  (`AUDIO.md`); the spec stays here so it need not be read off the reference twice.
- **An effects switch in settings,** once the frame cost is measured. `Wheels:SetEnabled` and
  `DriftController:DebugWheelFx` are already the switch; what is missing is a focused-window
  measurement to say whether it is worth a setting.
- **Coloured smoke and marks as a cosmetic,** which is a monetization decision and not this round's.

Added by `T-062`, from building it:

- **The look of the marks and the smoke.** The user's call, and the numbers to change are all in
  `Config/Fx.luau` under `Marks`, `Smoke` and `Surfaces`. What is there now is a first pass: a
  near-black mark at 0.45 transparency fading out over the last 40% of its five seconds, and a
  near-white puff that grows from 2.5 to 11 studs, rises and drags out.
- **Whether the smoke should be full at 90° rather than 180°.** The reference lerps the rate by
  `slip / π`, which is what is built — so a car fully sideways at 90° is only at 34 of 60. The
  squeal's own `MaxSlipDegrees` is 90. One number, `Gates.MaxSlipDegrees`.
- **Whether a crawling car should mark at all.** There is no minimum speed on the marks, only on
  the handbrake, which is what the reference does. Measured: a car creeping at 0.3 studs/s with
  14° of slip still has its rear trails enabled. It lays a dot, not a line, so it costs nothing to
  leave — but a `Gates.MinMarkSpeed` is a one-line addition if the user ever sees it.
