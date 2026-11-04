# Feature: Car archetypes

**Status:** built and measured, **not driven by the user yet**. Four cars exist and are
provably different, and the default one is the car the user approved on 2026-11-03,
unchanged to the stud. Which of the three new ones are worth keeping, and what they are
called, is the user's. **Owner task:** `T-027` (`agent/car-archetypes`). The art that
would give each of them its own body is `T-028`, behind this one.

## Goal

More than one car to drive, each with a character a player could name blindfolded, and the
machinery to add more without touching the model. A car stops being "the numbers in
`Config.Drift`" and becomes a named table, so adding one is data and never code.

The reference game does the same thing, and the useful half of how it does it is copied
here: what genuinely varies per car, and what it shows a player about each.

## How it plays

1. A car is a named set of numbers. Today the game picks one and everybody drives it; a
   tester switches with **F4** (or gamepad DPad right), and the car changes on the very
   next simulation step — a finger held through the switch feels the car change underneath
   it.
2. The four differ in how fast they rotate, how hard they resist sliding, how hard they
   bite once sliding, how quickly they get going and how fast they end up. Nothing else
   about them differs: the gesture, the camera, the surfaces and the world are the model's
   and are the same for every car.
3. **The stat panel** is folded into the debug readout (`F3` opens the readout, `F5` folds
   the panel, or click its header). It shows the car the way a shop would:
   - three bars — acceleration, handling, top speed — that are **hand-written and display
     only**;
   - the four numbers that are really the car, each as a fraction of the design space's
     maximum;
   - the grip curve those four make, plotted from 0 to 90 degrees of slip with the car's
     ceiling drawn across it, and sampled as text underneath.

### Why the three bars are a lie, on purpose

The reference's shop shows three bars per car. They are a display field written by hand
per car; nothing computes them from the physics and nothing reads them back into the
simulation. We do exactly the same, because the alternative — deriving them — is a lie
that looks like a fact. A car's handling is not one number, and the panel says so by
showing the four numbers that *are* the car, right underneath.

A check proves the bars are inert: set all three to 10 on a car and the same corner moves
**0.000000000 studs**, and `Config.Drift` cannot see them at all.

## Rules and numbers

### Where a car lives

| File | What it holds |
|---|---|
| `Shared/Config/Drift.luau` | **the model**: the step, gravity, the surfaces, the ground, the walls, the network, the respawn, the control, the camera, the score, the debug UI — and `CarBody` |
| `Shared/Cars/Archetypes.luau` | **the cars**: `Base`, every car field at the approved value, and four sparse override tables on top of it |
| `Shared/Cars/init.luau` | which car is active, how a key resolves, runtime tuning, the grip curve and the stat panel's data |

`Config.Drift` holds **no car key raw**. Reading one misses and falls through a metatable
to `Cars.value(key)`, which answers for whichever car is active. So `Drift/Model`'s
`local C = Config.Drift; C.MaxSteeringSpeed` reads the active car's rate of turn — and
**not one line of `Drift/Model` changed to make that true.**

Writing a car number into `Config.Drift` **errors**, with the alternative in the message.
That write would create a raw key that shadows every car from then on and silently make
them all the same, which is the one failure the split exists to prevent. Moving a car
number at runtime is `Cars.tune(key, value)` / `Cars.untune(key)`, or
`Cars.withTuning({...}, fn)` which puts them back however the call ends.

**A car is not a body.** `Config.Drift.CarBody` picks the shape that is drawn (`ae86`,
`block`); this picks how it drives. They are deliberately separate axes: any body may wear
any archetype's numbers, which is how all four are driven today with the one body the game
has. `T-028` gives them their own.

### What varies per car

Everything the reference varies, except which wheels drive (see "Open questions"):

- `MaxSteeringSpeed`, `SteeringSensitivity`
- `ConstantFriction`, `SlipFriction`, `SlipSqFriction`, `MaxFriction`, `FrictionMultiplier`
- `MaxAcceleration`, `AccelMultiplier`, `TopSpeed`, `SpeedMultiplier`, `StartThrottle`,
  `FullThrottleSeconds`, `HandbrakeDecel`
- `DownforcePerSpeed`, `DownforceCutoff`
- the geometry: `Wheelbase`, `TrackWidth`, `WheelDiameter`, `WheelWidth`, `RideHeight`,
  `CenterOfMass`, the body box, the cosmetic roll and the drawn wheel steer

**Every archetype shares the approved car's geometry today**, because all four wear one
body. Geometry is read when a car *model* is built, so changing it per car is legitimate
but only lands on the next respawn; nothing in the drift reads it at all (the model has no
bicycle geometry).

### The four cars

| | `balanced` | `gripper` | `slider` | `bruiser` |
|---|---|---|---|---|
| Character | the car the feel gate was passed on | corners on rails; a slide has to be provoked and it tidies itself up | slides at a touch and never catches itself; holding it is the skill | carries speed in a straight line and has to be turned early |
| `MaxSteeringSpeed` (rad/s) | **2** | 1.6 | 2.6 | 1.2 |
| `ConstantFriction` | **14.3** | 57.2 | 4.3 | 35.8 |
| `SlipFriction` | **14.3** | 28.6 | 17.2 | 42.9 |
| `SlipSqFriction` | **14.3** | 85.8 | 7.2 | 7.2 |
| `MaxFriction` | **107** | 143 | 71 | 107 |
| `MaxAcceleration` | **14.3** | 21.5 | 16 | 10 |
| `TopSpeed` (studs/s) | **179** | 150 | 170 | 215 |
| `DownforcePerSpeed` | **0.2** | 0.3 | 0.15 | 0.35 |
| Bars (accel / handling / top) — **display only** | 5 / 5 / 7 | 7 / 9 / 5 | 6 / 3 / 6 | 3 / 4 / 10 |

`balanced` overrides **nothing**: it is `Base`, which is every number the user approved on
2026-11-03, moved out of `Config.Drift` unchanged. It is the default.

### The design space

The stat panel draws the four real numbers as fractions of the reference's own maxima,
converted to studs. They are the space the cars are drawn from, not a limit the code
enforces:

| Number | Max | Where the approved car sits |
|---|---|---|
| `MaxSteeringSpeed` | 4 rad/s | 50% |
| `ConstantFriction` | 114.3 studs/s² (32 m/s²) | 13% |
| `SlipFriction` | 228.6 studs/s² per rad (64) | 6% |
| `SlipSqFriction` | 114.3 studs/s² per rad² (32) | 13% |

So the approved car is a small car in a large space, and the three new ones are still well
inside it: the furthest out is the gripper's squared term at 75%.

## UI

Programmer art, folded into the existing debug readout (`Drift/DebugHud`), and none of it
is the shipping shop (`UI-INVENTORY.md`). One column, top left: the readout's eight rows,
then the stat panel under it.

| Row | What it says |
|---|---|
| header | the car's name and key, and that F4 switches and F5 folds. A `TextButton`, so touch and mouse fold it too |
| character | the car's one line |
| bars | the three hand-written bars, with the words `HAND-WRITTEN, display only` above them, in a different colour from the real numbers |
| real ×4 | each real number, its maximum, its unit and its percentage |
| graph | 31 bars, 0 to 90 degrees of slip across, grip up, on a scale shared by every car so switching moves the curve rather than rescaling the axis. The car's `MaxFriction` is a red line across it |
| curve | the same curve as text at 0/15/30/45/60/90 degrees |

The panel redraws only when the car changes, not every frame.

## Server and client

Unchanged, and this adds nothing to the wire. The client that drives a car simulates it,
so switching car on the client is what a player would feel; the server keeps its own
active car for the checks it makes on `CarState`.

**The two can disagree, and that is why every archetype's top speed stays under 223.75
studs/s** — the default car's 179 times `StateSpeedTolerance`. A client in the bruiser
(215) is still inside what a server that thinks it is the `balanced` car will accept, so
no packet is dropped. See "Open questions": that slack is a prototype's answer, not a
game's.

## Contracts

No new remotes, no new data keys, no new tags or attributes. New service API, in
`CONTRACTS.md`:

- `Shared/Cars` (ModuleScript, `ReplicatedStorage.Shared.Cars`):
  `activeKey()`, `active()`, `exists(key)`, `setActive(key)`, `cycle()`, `isField(key)`,
  `value(key)`, `tune(key, v)`, `untune(key)`, `untuneAll()`, `withTuning(overrides, fn)`,
  `gripAt(slipDeg, car?)`, `gripCurve(count, car?)`, `stats(key?)`, `DebugState()`,
  and the constants `Order`, `StatMax`, `Archetypes`.
- `Config.Drift` **refuses a write to any car key** and errors naming `Cars.tune`. Every
  car key still reads normally and resolves to the active car.
- `DebugHud:ToggleStats()` alongside `Toggle` / `SetVisible` / `IsVisible`.

## Analytics

None. Which car a player picks is worth an event the day a car is a choice a player makes
rather than a tester's key (`ANALYTICS.md`, `EVENT-CATALOG.md`); there is nothing to
measure while every player is in the same car.

## Monetization

None, and deliberately not designed. Cars are the obvious thing to sell and that
conversation belongs to the Monetization phase and to `REVENUE.md`, after the user has
driven these and said which are worth keeping.

## Platform risks

None beyond what the model already carries: all four cars wear the same placeholder body,
which is the AE86 and is **not approved to publish** (`features/drift-model.md` "Platform
risks"). The archetypes make that worse in one way worth saying out loud — four cars is
four chances to reach for a real manufacturer's car for each. They get original bodies or
Creator Store ones with a clean licence (`ART-PIPELINE.md`), and `T-028` owns that.

## Art and sound

None yet, and the system is built so there need not be: any body may wear any archetype's
numbers, so all four are driveable today on the one body the game has, and on the block
car in a place whose meshes will not load. `T-028` draws them.

## Testing

`ServerScriptService/Tests/DriftTests.luau`, through the server debug bridge
(`DebugDriftTests`). Six new checks on top of the twenty-five that were already there; all
thirty-one pass.

| Check | What proves it |
|---|---|
| **The default car is still the car the user approved** | all 24 of its numbers against literals, and `balanced` still the default |
| **Four archetypes that settle somewhere different** | one rolling start, one held finger, four different answers, with two strict orderings that have to survive |
| **Every car's grip curve is its own four numbers** | the curve the panel draws, measured back out of the model at 15/30/45/60/89 degrees, for every car |
| **Switching car changes the car and switching back puts it back** | the same corner 232 studs away on the gripper, and back to within 1e-9 studs of itself |
| **The three display bars reach nothing** | all three set to 10: the same corner moves 0 studs |
| **A car number cannot be written into the model's table** | the write is refused, a model number still writes, and `tune`/`untune` round-trips |

### What it measured, 2026-11-04 (`T-027`)

**The default car is unchanged, and not "within a stud" — identical.** The same scripted
corner, same start, same inputs, run on `origin/main` and on this branch:

| | `origin/main` | this branch |
|---|---|---|
| End of the corner | −162.037384, 2.394425, −312.193268 | the same, to six decimals |
| Every tenth point of 102 | | the same, to six decimals |
| Heading turned | 110.007897° | 110.007897° |
| Speed at the end / fastest | 28.866060 / 124.779358 | the same |
| End of an 8 s held half-finger drift | −116.955582, 2.394173, −333.454681 | the same |
| Slip and speed there | −33.984247°, 30.170761 studs/s | the same |

And all twenty-five of `main`'s checks report the same numbers word for word on both.

**The four cars, from 140 studs/s on one held finger.** Settled values are means over the
last second of eight; "sliding after" is when the car first passes
`MinSlipAngleForDrift` (5°).

| Car | ½ finger: slip (peak) | speed kept | circle | sliding after | ¼ finger: slip | speed kept | circle | sliding after |
|---|---|---|---|---|---|---|---|---|
| `slider` | 40.9° (180.0) | 18.3 (13%) | 14 studs | 0.07 s | 24.4° | 37.8 (27%) | 58 studs | 0.15 s |
| `balanced` | 33.4° (135.8) | 32.0 (23%) | 32 studs | 0.10 s | 11.8° | 39.7 (28%) | 79 studs | 0.22 s |
| `gripper` | 12.1° (26.7) | 88.0 (63%) | 110 studs | 0.22 s | 2.4° | 143.9 (103%) | 360 studs | **never** |
| `bruiser` | 5.2° (33.0) | 69.3 (50%) | 116 studs | 0.26 s | 8.7° | 143.5 (102%) | 478 studs | 2.56 s |

Two strict orderings, and the checks hold them: **speed kept** rises slider → balanced →
bruiser → gripper, and **how far round the tail comes** falls slider → balanced → gripper
→ bruiser. The sharpest single number is the quarter finger: the gripper never slides at
all, the bruiser takes two and a half seconds, and the slider is sideways in 0.15.

**The grip curves**, studs/s² at 0/15/30/45/60/90° of slip — measured back out of the model
to within 0.001 of what the panel draws:

| Car | 0° | 15° | 30° | 45° | 60° | 90° |
|---|---|---|---|---|---|---|
| `balanced` | 14.3 | 19.0 | 25.7 | 34.4 | 45.0 | 72.0 |
| `gripper` | 57.2 | 70.6 | 95.7 | 132.6 | **143.0** | **143.0** |
| `slider` | 4.3 | 9.3 | 15.3 | 22.3 | 30.2 | 49.1 |
| `bruiser` | 35.8 | 47.5 | 60.2 | 73.9 | 88.6 | **107.0** |

The gripper is the only car whose ceiling binds early (48° of slip); the bruiser's binds at
78°; the approved car's and the slider's never bind at all, which was already known
(`features/drift-model.md`, "`MaxFriction` is inert as tuned").

**Straight line from a standstill**, 5 / 10 / 20 s: gripper 71.0 / 126.3 / 148.5, slider
58.3 / 115.4 / 160.3, balanced 52.6 / 108.3 / 161.9, bruiser 24.7 / 71.8 / 144.0 and still
climbing to 215.

**In a playtest in `DR-Lane3`**, with one steering key held and F4 pressed between reads:
the gripper turned at 1.20 rad/s against a 143 ceiling at 16.7° of slip and 63.5 studs/s;
one press later the slider turned at 1.95 rad/s against 71 at 40.4° and 13.0 studs/s. The
panel followed on the same frame. `get_console_output` clean of anything from game code.

- **Playtest:** drive all four. The user decides which are worth keeping and what they are
  called; that is the gate, and nothing above is a feel judgement.

## Open questions

- **Which cars survive, and their names.** Four is a demonstration of the system, not a
  line-up. The user drives them and says which are keepers; names and anything a player
  reads are theirs (`AGENTS.md`).
- **Front-wheel drive, and which wheels drive at all.** The reference varies it per car and
  we do not: `Drift/Model` drives the rear pair, as a constant (`Model.REAR_WHEELS`), and
  making it a car field is a small change in a file this task did not own. It would be a
  genuinely different feel — a front-drive car pulls itself straight out of a slide — and
  is the obvious fifth archetype.
- **The server does not know which car a player is in.** It bounds a reported speed against
  the top speed of the car *it* thinks is active, so every archetype is deliberately kept
  under the default car's tolerance. The day a car is a player's choice, the server has to
  be told, and has to keep its own copy of that car's numbers — the same open question the
  model already carries about validation (`features/drift-model.md`, "Open questions").
- **The display bars are placeholders too.** Three hand-written numbers per car, written by
  the agent. They are marketing and the user owns marketing.
- **A fifth axis nobody has asked for yet:** the reference layers per-car multipliers over
  acceleration, top speed, friction and the steering rate as well as the absolute numbers.
  All four exist here (`AccelMultiplier`, `SpeedMultiplier`, `FrictionMultiplier`,
  `SteeringSensitivity`) and every car leaves them at 1. They are the natural home for an
  upgrade or a tune a player buys, which is why they are kept.
