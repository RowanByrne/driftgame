# Feature: The car's sound and wheel effects

**Status:** specced, waiting on the user's approval of the plan. **Owner task:** none yet (`T-056`).

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
| **Is the slip angle past this wheel's threshold?** | **The fronts and the rears have different thresholds, and that is the detail that sells it.** The front wheels are drawn pointing along the travel (opposite lock, `Drift/Render`), so they are not sliding until the slip exceeds that steering angle: their threshold is `slip − MaxSteerAngle`, the rears' is `slip > 0`. The rears mark first and alone through a small slide, and the fronts join in once it is a big one |
| **Is the throttle past `MinThrottleForFx`?** | A car coasting sideways does not light up the road |
| **Or is the handbrake down?** | The handbrake marks and smokes on its own, above `MinHandbrakeSpeed`, throttle or no throttle |

Smoke's **emission rate** is lerped from a minimum to a maximum by `slip / π`, so a big angle is a
big cloud. Marks have a fixed lifetime (`MarkSeconds`), with a hook to keep them for ever — the
reference uses that for its end-of-run replay shot, and we would want it for the same reason one
day.

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
| Wheel positions | `Render`'s rig: four wheels with their offsets | The effects hang off the wheel parts, which `Render` already places |

## How it plays

You press the throttle and the engine note climbs, drops through a shift, climbs again. You turn in
and the back steps out: a squeal fades up with the angle, the rear wheels start laying black on the
road and puffing smoke, and as the slide deepens the fronts join them and the cloud grows. Catch it
and all of it fades back down over about a second, leaving two dark lines through the corner that
stay for `MarkSeconds` and then fade. Lift off mid-slide and the marks stop while the car keeps
sliding — no throttle, no marks. Pull the handbrake at any speed and everything lights up at once.

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
| `MinPitch`, `MaxPitch` | 0.7, 2.2 | `Sound.PlaybackSpeed` floor and ceiling. **Ours to choose:** the reference's live on its car config and are not in the decompile |
| `AirbornePitch` | `MaxPitch` | Wheels up, engine free |

### Skid

| Number | Start | What it does |
|---|---|---|
| `MinSkidSpeed` | 3.6 studs/s | Below this, silence |
| `MinSkidVolume` | 0.25 | The volume a drift that has just begun plays at |
| `MaxSlipDegrees` | 90 | The angle the squeal is full at |
| `SkidVolumeLerpSpeed` | 1 /s | Fade in and out |

### Marks and smoke

| Number | Start | What it does |
|---|---|---|
| `MinThrottleForFx` | 0.2 | Coasting sideways leaves nothing |
| `MaxSteerAngle` | 30° | The fronts' extra threshold (see the gates table) |
| `MinHandbrakeSpeed` | 3.6 studs/s | Below this the handbrake smokes nothing |
| `MarkSeconds` | 5 | `Trail.Lifetime` |
| `MarkWidth` | 1.2 studs | A little under the tyre |
| `SmokeRateMin`, `SmokeRateMax` | 8, 60 /s | `ParticleEmitter.Rate`, lerped by `slip / π` |

### What it is made of in Roblox

| The reference | Us | Why |
|---|---|---|
| `AudioClip` + `AudioSource` | One `Sound` per role, parented to the car's body part, `RollOffMode = InverseTapered` | 3D by default, so a second car is heard where it is |
| Pitch | `Sound.PlaybackSpeed` | |
| `TrailRenderer` | `Trail` between two `Attachment`s at the wheel's contact patch | Lifetime, width and colour all map directly |
| `ParticleSystem` | `ParticleEmitter` on one `Attachment` at the contact patch | `Rate` maps to `rateOverTime` |

**The budget:** four wheels × (one `Trail` + one `ParticleEmitter` + two `Attachment`s) = 16
instances per car, made once when the rig is built and never again. Nothing is created or destroyed
while driving; emitters are switched with `Trail.Enabled` and `ParticleEmitter.Enabled`. **A frame
that allocates is the thing to measure and the thing to fail on.**

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

In `CONTRACTS.md`, in the same commit:

- `Config.Fx`, the new config module and every number in it.
- `Drift/Wheels`, `Drift/EngineSound`, `Drift/SkidSound`: the client modules and their
  `attach(rig, state)` / `update(state, dt)` / `DebugState()` surfaces.
- The `Trail`, `ParticleEmitter` and `Sound` instance names on a rig, so `Render` and the tests
  agree on what they are called.
- Any `Hit` change, if the per-wheel surface gap is closed in this round rather than deferred.

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

Three sounds, all 3D, all looping except the last:

| Role | Shape | Where from |
|---|---|---|
| Engine | Seamless loop, a low steady note with no obvious pitch movement of its own — it is going to be stretched from 0.7× to 2.2× and anything musical in it will warble | Creator Store, `asset-scout` |
| Tyre squeal, tarmac | Seamless loop, continuous, no transient at the start | Creator Store |
| Backfire pop | One-shot, short | Creator Store. Only if the backfire is built |

**The user picks, from candidates, as they do with art** (`AGENTS.md`). Rocco's cards play sound
options, so the pick is a question on a card, not a file to open.

No images: the smoke is a built-in particle texture and the tyre marks are a flat colour.

### The direction `AUDIO.md` does not have yet

`AUDIO.md` "Direction" is an empty template, and these are the first sounds in the game, so this
feature's approval sets it. **Proposed, for the user to take or change:**

- **Pillars:** *weighty, clean, never harsh.* The engine is felt more than heard; the squeal is the
  loudest thing in a drift; nothing in a corner is shrill enough to wear out over a ten-minute
  session.
- **Mix:** the squeal sits on top, the engine under it, everything else under both. A player with
  the sound off loses information but not the game.
- **Style:** realistic, not cartoon. The drift model is a simulation and the sound should agree
  with it.

## Testing

A playtest on the endless road, and a test file, `Tests/FxTests.luau` — but note what can and
cannot be measured: **sound is the user's ear, and the test's job is the state machine, not the
feel.**

| Check | Measured |
|---|---|
| The gearbox | Drive 0 → top speed and record every shift's speed. They must match the computed series within `GearOverlap`, and no two shifts within `MinTimeInGear` |
| Pitch is continuous | The largest single-frame change in `PlaybackSpeed` over a full-speed run, which must be bounded by `PitchLerpSpeed × dt` |
| Airborne | Off a crest or a fall: pitch at `MaxPitch`, skid volume 0, no trail emitting |
| The front/rear threshold | Hold a slide at 20° and at 60°: at 20° the two rear trails emit and the two fronts do not; at 60° all four do |
| Throttle gate | Coast sideways at zero throttle: slip above the threshold, no trail, no smoke |
| Handbrake | Handbrake from a standstill (nothing) and from 40 studs/s (all four, smoking) |
| Smoke rate | `ParticleEmitter.Rate` at 10°, 45° and 90° of slip against the configured lerp |
| It allocates nothing | Instance count on the rig before a 60-second drive and after: **identical**. The number that would fail this is the one worth having |
| Frame cost | Frame time over a 60-second drive, effects on and off, on this PC. A cost worth naming is a cost worth a `SETTINGS.md` switch |

`DebugState()` on each of the three modules, reporting what it is doing and why — the gear and
pitch, the skid volume and its gate, and each wheel's four gates — so a playtest can say *which*
gate is wrong rather than "no smoke".

## Open questions

- **The sounds themselves.** Three picks, from Creator Store candidates. The user's.
- **`MinPitch` and `MaxPitch`.** Not in the decompile. Ours to pick and then tune by ear.
- **Remote cars** (above): derived slip, or silent this round.
- **The backfire,** which needs an exhaust position per body.
- **An effects switch in settings,** once the frame cost is measured.
- **Coloured smoke and marks as a cosmetic,** which is a monetization decision and not this round's.
