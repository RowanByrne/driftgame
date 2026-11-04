# Feature: Car tuner

**Status:** built, and **not driven by the user yet**. The sliders, the garage and the
server's half are measured; what the eight sliders should be called and whether the panel
is the right shape are the user's, and so is every number anybody saves with it.
**Owner task:** `T-040` (`agent/car-tuner`).

It is a **dev tool**, in the same family as the debug readout (`F3`) and the trajectory
line (`F6`): off by default, Studio-grade, and none of it is the garage screen this game
will one day have (`UI-INVENTORY.md`, `docs/workflow/UI.md`).

## Goal

Move the car's numbers while driving it, and keep the ones that felt right. The feel gate
is the user's and nothing past it is decided (`PROJECT.md` "Current focus"), so the fastest
way to find the car is to let them move it themselves rather than ask an agent to guess,
edit `Archetypes.luau` and wait for a sync.

## How it plays

1. **F8** opens the panel (the gamepad's **Y**, or the **TUNE** button under the readout's
   **DBG**). It sits on the right; the debug readout owns the top left and the two are
   meant to be open together.
2. **Eight sliders.** Drag one and the car changes **on the next simulation step** — one
   120th of a second — with no rebuild and nothing to refresh. A finger held on the steering
   through a slider move feels the car change underneath it.
3. Each row says what the driver feels, then the number, then a dim line with **the real
   key it is moving** and what that does. The names are not technical; the line underneath
   is, so the tool is never dishonest about what it is doing.
4. **A notch on each track** is the base car's own value, so "how far have I moved this
   from the car it came from" needs no arithmetic. A moved slider's number goes orange.
5. **`<` and `>`** change the base archetype under the tune. The tune is kept: "the gripper
   with my steering rate" is a car somebody may want.
6. **SAVE** writes over the car being edited; **SAVE AS…** asks for a name; **RESET** puts
   the plain archetype back. Saved cars list underneath: click one to **drive it**, `×` to
   delete it. The one being edited is highlighted, with a `*` while it has unsaved changes.
7. **It never steers the car.** The whole screen is a drag pad (`Drift/DragControl`), and
   this panel sits above it: a thumb on a slider is a slider. Closed, the panel gives the
   whole screen back.

## Left out

- **It is not a garage screen and not a shop.** No art, no prices, no car previews, no
  sharing a car with another player. The day a car is something a player picks or buys,
  this is thrown away and the screen is designed properly (`REVENUE.md`).
- **It does not write archetypes.** A tuned car is a saved tune, not a fifth entry in
  `Cars/Archetypes`. Promoting one to an archetype is a person editing that file.
- **No undo, and no history.** Reset goes back to the plain car; the last saved version is
  the only version.
- **It does not tune the model**, only the car: the step, gravity, the surfaces, the
  camera and the control are `Config.Drift`'s and are deliberately out of reach
  (`features/car-archetypes.md` "Where a car lives").
- **Geometry is not a slider.** `Wheelbase` and the rest are read when a car *model* is
  built, so a live slider for one would change nothing until a rejoin — a slider that lies.

## Rules and numbers

### A tuned car

```
{ base = "gripper", tune = { eagerness = 2.6, grip = 41.3, ... } }
```

One of the four archetypes, with some of its numbers moved. That shape is the whole design:

- the tune lands through **`Cars.tune` / `Cars.setTuning`**, and `Config.Drift` resolves
  every car key through the active car on **every read**, so a slider is live on the next
  step and `Drift/Model` needed no change at all;
- the base is a real archetype, so the car keeps **its own body**, its geometry and
  everything the tuner does not expose;
- the server already owns which archetype a player is in (`CarService`, `T-033`) and
  nothing here has to argue with it.

A tune only holds sliders that **differ from the base**, so "the plain gripper" and "the
gripper with nothing moved" are the same state.

### The eight sliders

The user asked for "stuff that isn't super technical", so each is named for what the car
does. The real key is printed under every row.

| Slider | Really | What the driver feels | Range | The four cars sit at |
|---|---|---|---|---|
| **Eagerness** | `MaxSteeringSpeed` | how fast the car rotates when you move your finger | 0.2 – 4 rad/s | 1.2 – 2.6 |
| **Grip** | `ConstantFriction` | how hard it resists sliding at all | 0 – 114.3 | 4.3 – 57.2 |
| **Catch** | `SlipFriction` | how quickly it starts fighting back as the tail steps out | 0 – 228.6 | 14.3 – 42.9 |
| **Bite** | `SlipSqFriction` | how hard it hauls itself straight once it IS sliding | 0 – 114.3 | 7.2 – 85.8 |
| **Grip limit** | `MaxFriction` | the tightest circle it can hold before it just slides | 0 – 300 | 71 – 143 |
| **Power** | `MaxAcceleration` | how hard it pulls away | 0 – 60 | 10 – 21.5 |
| **Top speed** | `TopSpeed` | where it stops pulling | 20 – 400 studs/s | 150 – 215 |
| **Planted** | `DownforcePerSpeed` | how much it is pressed into the road with speed | 0 – 1 | 0.15 – 0.35 |

**Eight, not the seven asked for.** `SlipFriction` is the linear grip term and decides how
a car behaves between "straight" and "properly sideways"; without it the bruiser cannot be
built in this tool at all, since its 42.9 is three times everything else's and is most of
its character. It is here as **Catch**.

**What is deliberately not a slider:** the four multipliers (`AccelMultiplier` and friends,
all 1 on every car and redundant with the absolute numbers beside them),
`SteeringSensitivity` (the same dial as Eagerness), the throttle ramp and the handbrake
(not felt in a corner), and all the geometry (see "Left out").

**Where the ranges come from.** The four with an entry in `Archetypes.StatMax` use the
reference's own design space — the same maxima the stat panel already draws them as a
fraction of. The other four are drawn from the spread the four cars use, opened up far
enough either side to be worth a slider. **Every archetype is inside every slider**, so any
of the four can be dialled up from any other (checked).

**A slider may make a car undrivable** — that is a thing a person tuning a car is allowed
to find, and every range here is recoverable by moving the slider back. It may not make one
that breaks the simulation, and there is exactly one such number: **`TopSpeed` cannot reach
zero**, because the drivetrain divides by it (`clamp01(1 - (u/TopSpeed)^2)`) and zero is a
NaN velocity and a car that is nowhere. Its floor is 20 studs/s.

### The numbers behind it

All in `Config.Drift` ("the tuner", "the garage"): `Tuner`, `TunerOpen`, `TunerKey` (F8),
`TunerGamepadKey` (ButtonY), `TunerWidth` (336 px), `TunerRowHeight` (38 px),
`TunerSendRate` (10 Hz), `GarageMaxCars` (12), `GarageNameMax` (24), `GarageSaveRateLimit`
(4/s), `GarageTuneRateLimit` (30/s), `GarageWriteInterval` (8 s), `GarageWriteRetries` (3),
`GarageRetryBackoff` (2 s).

## UI

Programmer art, one `ScreenGui` (`DriftTuner`), built in code, `ResetOnSpawn = false`.
There is no UI kit in this game yet (`ARCHITECTURE.md`), so it draws its own flat frames in
the debug readout's palette so the two read as one tool.

| Row | Where | What it is |
|---|---|---|
| header | fixed, top | `CAR TUNER` and a CLOSE button |
| car | fixed, top | `<` `Balanced (balanced)` `>` |
| editing | fixed, top | which saved car is being edited, with `*` while it has unsaved changes |
| slider ×8 | **scrolls** | `Eagerness` + the real key in grey, the value on the right; then `-` track `+`. The base car's own value is a notch on the track |
| actions | scrolls | `SAVE` `SAVE AS…` `RESET` |
| garage | scrolls | `SAVED CARS n/12`, then a row per car: the name (loads it) and `×` (deletes it) |
| status | fixed, bottom | **the tooltip** — touch or hover a slider and this is what that slider does — and what just happened, and a warning when the store is this-server-only |
| dialog | centred | a name box with SAVE and CANCEL, Enter to accept |

**The panel is sized from the screen, not from its contents,** and the middle of it
scrolls. Eight sliders, three buttons and twelve saved cars is about 870 px of panel;
measured in the lane place the viewport was **663 px tall**. A panel that grew to fit would
run off the bottom and, worse, **cover the handbrake** — the only way to stop a car once a
run is over. It is `TunerTop` (168) from the top and leaves `TunerBottomGap` (190) clear at
the bottom: measured 110 → 415 against a handbrake whose top edge is at 481, **66 px of
clear air**, on a screen where the un-scrolled version reached 719.

That is also why the real key sits beside the slider's name rather than under it, and why
what the driver *feels* is a tooltip on the status line: two lines a row instead of three.

**Layouts.** One layout today, 336 px wide on the right. It is a dev tool, so it does not
get the per-device treatment a player-facing screen must have (`UI.md` "Layouts per
device") — and it must not be the model for one. On a phone it covers about a third of the
screen; the rest still steers.

**One naming trap, worth knowing:** the dialog's TextBox is called `Entry`, not `Name` — a
child called `Name` shadows `Instance.Name`, so `NameDialog.Name` is the string
`"NameDialog"` and every path to the box is a trap. It cost a confusing half-hour here.

**Input.** Pointer and touch drag the tracks; the `-` / `+` buttons either side of every
track are `Selectable`, so a gamepad reaches every slider through Roblox's own GUI
navigation without a single new keybind — which matters, because the arrow keys and `S` are
already steering and the handbrake. F8 / ButtonY / the TUNE button open it. **Not F7**, which was the obvious next key after the readout's F3/F4/F5 and the line's F6: Studio eats F7 for its own Client/Server view toggle and the press never reaches the game (measured: F8, F10, G and T all arrive, F7 alone does not).

### Why it does not fight the steering

The whole screen is a drag pad: one finger, held, and its horizontal distance **is** the
car's rate of turn (`features/drift-model.md` "The control"). So a thumb dragging a slider
would also be a thumb hauling the car round. It is not, because:

- the pad lives in `DriftControls` at `DisplayOrder = 5`; this panel is at **20**;
- every part of the panel that can be touched — the panel background, every button, every
  slider track — is an **Active** GuiObject, so the press is consumed here and
  `DragControl`'s `pad.InputBegan` never fires;
- closed, the panel is `Visible = false` **and `Active = false`**: an invisible Active frame
  would still swallow a touch meant for the car.

Both halves are measured (see "Testing").

## Server and client

**The client tunes its own car and that is correct**: it simulates the car, so the feel has
to change where the simulation is. **The server owns what it will believe.**

### The one thing a tuned car breaks, and how it is answered

`CarService` bounds every `CarState` against the top speed of the car it believes that
player is in (`T-033`): more than `TopSpeed × StateSpeedTolerance` and the packet is
dropped. A player who drags **Top speed** past their archetype's own is therefore driving a
car the server does not believe in — every packet thrown away, the car frozen for everyone
else, the drop counter climbing.

`Cars.resolve`, which is what `CarService` asks, **applies the tuning layer**. So
`GarageService` tunes the server's own `TopSpeed` to a **ceiling**:

```
ceiling = max(the fastest archetype, every tuning player's effective top speed)
```

applied only while somebody is actually tuned above their own car. Three things make that
safe rather than a hole:

- **It only ever loosens.** The floor is the fastest archetype (215 studs/s today), so no
  player in a plain car is ever bounded below their own top speed, whatever anybody else is
  tuning. A tighter ceiling would drop honest packets, which is the failure this exists to
  prevent.
- **It is bounded by the slider.** `TopSpeed` maxes at 400, so the loosest the server can
  ever be is 400 × 1.25 = 500 studs/s — and the distance check moves with it, so a teleport
  is still a teleport.
- **It goes away.** The moment nobody is tuned above their car the tune is removed and the
  bound is exactly what `T-033` made it, to the stud.

**What it is not: per player.** `Cars.tune` is one layer over one Lua VM and
`CarService:_numbers` asks `Cars.resolve(key)` with no player in hand, so a per-player bound
is not expressible from `GarageService`. **The proper fix is three lines in
`CarService:_numbers`** — resolve the car, then lay that player's own tune over it — in a
file `T-040` did not own. Until then, while somebody is tuning, every player on that server
shares the loosest bound: the same slack the game lived with before `T-033`, and a dev
tool's price.

### What the server checks

Everything, through `Shared/Cars/Garage` — **the same module the client draws its sliders
from**, so there is one definition of what a tuned car may be and no chance of the two ends
disagreeing. Off the wire: unknown slider ids dropped, non-numbers dropped, **NaN and the
infinities dropped**, every value clamped to its range and snapped to its step, names
trimmed and bounded, an unknown base archetype falls back to the default, saves and deletes
rate-limited at 4/s and live tunes at 30/s per UserId.

### The store, and what it is not

**This is the first thing in this game that persists anything, and it is not the save
system.** The foundation kit's `DataService` and `PlayerData` are deliberately unbuilt
(`ARCHITECTURE.md`): nothing is meant to save until the drift feel is proven. So
`GarageService` keeps **one small dedicated store for tuned cars only** —

- one key per player (`garage_<userId>`) in one store of its own (`DriftGarageDev_v1`),
  holding named tunes and nothing else;
- **no session lock**: there is nothing here two servers can fight over that matters. Last
  write wins and the thing lost is a slider position;
- **the in-memory copy is the live one.** A write is retried three times with a doubling
  backoff, then warned about, and the garage **stays in memory and stays dirty** so the next
  flush tries again. A failed write never costs the user the car they are driving;
- **never on every change.** A slider being dragged is twenty changes a second; the store
  sees a dirty garage every 8 s, on leaving, and on `BindToClose`
  (`CODING.md` "Data store limits");
- nothing else in the game may read it.

**Replacing it properly** is deliberately easy, and the shape saved here is already the
shape a profile key would hold: build `DataService` to the kit's API, give the profile a
`garage` key, and this file becomes `DataService:Get(player, "garage")` and
`:Update(player, "garage", fn)`. About forty lines go; the remotes and the validation stay.

**Memory mode is the normal case today and is not an error.** Drift has no published place
(`PROJECT.md`), and Roblox refuses DataStore calls from one — so in Studio the garage lives
as long as the server. Saving, loading, editing and the whole round trip work there; what
does not survive is **stopping the playtest**. The panel says so: `(this server only: no
DataStore)`. A live server never silently falls back to memory.

## Contracts

**Four new remotes**, all created by `GarageService`. They are *not* in `CarService`, which
is where the car remotes live — `T-040` did not own that file, and a dev tool's remotes
should be deletable with the tool:

| Remote | Direction | Payload | What the server does |
|---|---|---|---|
| `GarageData` | both | client: nothing ("what is in my garage?"). Server: `{ version, cars, loaded, persists }` | answers with the whole garage; the whole thing every time, so a client can never be half out of step |
| `GarageSave` | client → server | `(name, base, tune)` | cleans the name, sanitizes the tune, refuses a **new** name in a full garage but always takes an overwrite, marks dirty, answers on `GarageData`. 4/s per UserId |
| `GarageDelete` | client → server | `(name)` | deletes it if it exists, answers on `GarageData`. Shares the save limit |
| `GarageTune` | client → server | `(tune)` | records the live tune and recomputes the speed ceiling. 30/s per UserId |

`TunerUI` also **fires the existing `CarSwitch`** when its `<` / `>` change the base
archetype, and listens to the answer — exactly as `DebugHud`'s F4 does, and for the same
reason: the server decides which archetype a player is in.

**New service API** (`CONTRACTS.md`):

- `Shared/Cars/Garage` (ModuleScript, `ReplicatedStorage.Shared.Cars.Garage`):
  `Sliders`, `Order`, `Version`, `slider(id)`, `sliderForKey(key)`, `clamp(id, v)`,
  `sanitizeTune(t)`, `toCarFields(t)`, `baseValues(base)`, `values(base, tune)`,
  `cleanName(n)`, `sanitizeCar(c)`, `sanitizeGarage(raw)`, `count(g)`, `names(g)`,
  `topSpeed(base, tune)`, `fastestArchetype()`, `finite(v)`.
- `Shared/Cars` gains `tuning()` and `setTuning(overrides)` — the whole tuning layer read
  and replaced in **one rebuild**, so the model never sees half a car.
- `Services/GarageService`: `Flush(now?)`, `DebugState()`, `DebugSave`, `DebugTune`,
  `DebugForget`, `DebugRejoin`, `DebugCar`, `DebugSwapStore`, `MemoryStore`.
- Client: `PlayerScripts.TunerBridge`, a Studio-only `BindableFunction` —
  `Invoke("DebugState" | "Toggle" | "SetOpen" | "Set" | "SetBase" | "Save" | "Load" |
  "Delete" | "Reset", ...)`. It exists because the client debug bridge only reaches loaded
  **controllers** and this is a LocalScript.

**New data, and the only data this game saves:** one key per player,
`DriftGarageDev_v1 / garage_<userId>` = `{ version = 1, at = <os.time>, cars = { [name] =
{ base, tune, savedAt } } }`.

No new tags or attributes.

## Analytics

None, and deliberately. A dev tool's use is not a player behaviour, and there is nothing to
measure while the only person tuning a car is the person building the game
(`ANALYTICS.md`). Which car a player picks earns an event the day a car is a player's choice
(`features/car-archetypes.md`).

## Monetization

None, and deliberately not designed. Cars and tunes are the obvious thing to sell and that
conversation belongs to the Monetization phase (`REVENUE.md`), after the user has driven
these. Worth knowing for then: the four per-car multipliers exist and every car leaves them
at 1, which is the natural home for an upgrade somebody buys.

## Platform risks

**One, and it is closed by scope.** The user types a car's name, which is player text — and
player text that another player could see must go through
`TextService:FilterStringAsync` (`PLATFORM-RISKS.md`). Here it cannot: a name is stored under
that player's own key, is only ever sent back to the player who typed it, and is not
rendered for anybody else. `Garage.cleanName` strips control characters and bounds the
length; **it is not moderation and the code says so.** The day a tuned car is shareable,
named in a leaderboard, or visible to another player, filtering goes in **before** that
ships.

## Art and sound

None. Programmer art frames and native text; no asset ids, no sounds. A tuned car wears its
base archetype's body, which is ours and in git as text (`features/car-archetypes.md`).

## Testing

`ServerScriptService/Tests/GarageTests.luau`, through the server debug bridge
(`DebugGarageTests`). **Seventeen checks, all passing.** It gets the treatment saving gets
(`TESTING.md`): the store is a **fake one swapped in for the length of the run**, no real
player's garage is touched, and the checks cover what loses data.

| Check | What it reported, 2026-11-04 |
|---|---|
| Every car is inside every slider | 8 sliders × 4 cars, all inside |
| Top speed can never reach zero | min 20; `clamp(0)` = 20, `clamp(-500)` = 20 |
| NaN, infinity, junk and unknown sliders never reach the car | 7 kinds of garbage in, 1 clamped number out |
| A clamped value is stable | `clamp(clamp(x)) == clamp(x)` on all 8 |
| Names | 6 cases: trimmed, newline → space, empty refused, over-long cut |
| **Eagerness changes the yaw rate on the next step** | 2 rad/s → **2.000000 measured**; 4 → **4.000000** |
| **Grip changes the sideways pull on the next step** | grip 14.3 → **20.56 studs/s²** at 20° of slip; grip 100 → **106.73** |
| **Power changes the acceleration on the next step** | power 14.3 → **4.63 studs/s²** from 20 studs/s; power 50 → **24.73** |
| The tuning layer goes on and comes off exactly | 2 → 3.5 → 2 |
| **A saved car survives being forgotten, to the value** | "Night Runner" on gripper: 2.65 / 41.3 / 233 / 0.44, identical |
| **Two saved cars are edited independently** | Alpha grip 10 → 95.5; Beta untouched at 3.2 / 300, no grip |
| A full garage refuses a new name and takes an overwrite | 12/12 from 15 asked; "car 1" overwritten |
| A flood of saves is rate-limited | **4 of 40 taken** |
| **A failed write keeps the in-memory car and stays dirty** | write false, car still there at 390, dirty true |
| **A tuned car faster than its archetype is not dropped** | gripper at 299: **dropped** against its own 150 (bound 187.5), **accepted** against the ceiling 300 (bound 375); a plain bruiser at 215 still accepted while somebody tunes *down* to 60 |
| The ceiling's floor is the fastest archetype | 215, the fastest of the four |
| The tests left no tuning behind | the car is the car |

Also run after any change here, and all passing on this branch: `DebugDriftTests` (40),
`DebugCollisionTests` (39), `DebugJitterTests` (11), `DebugTrajectoryTests` (13),
`DebugPlaygroundTests` (45) — this task touches `Config.Drift` and `Shared/Cars`, which
every one of them reads.

### What a playtest measured, 2026-11-04 (`T-040`, `DR-Lane2`)

**A slider lands, and the model agrees.** One real mouse drag across the whole screen,
started on the Eagerness track: the value tracked the pointer from 2 → **3.8** at the right
edge → **0.2** at the left, and `Config.Drift.MaxSteeringSpeed` — what `Drift/Model` reads
on its next step — followed it to **0.2** exactly.

**The panel does not steer the car.** Over **1720 frames**, **956** of them with a slider
being dragged across the full width of the screen: `CarInputController.steer` **0**,
`DragControl.steer` **0**, and the pad was down on **0 frames**. Closed again, the same
screen region steers normally: the pad down for **755 frames** at a steer of **0.236** (160
px of a 678 px travel).

**Typing a car's name does not drive it.** The name box focused for **1498 of 1498 frames**
while `D`, `A`, `D` and `S` — two steering keys and the handbrake — were pressed: steer
**0**, raw `InputAction` state **(0, 0)**, handbrake on **0 frames**. Roblox's focused
TextBox swallows the keyboard before the Input Action System sees it. *(Synthetic key
presses do not put characters in a Roblox TextBox, so the text itself was placed and the
real SAVE button clicked: the name `"  Sad Dad Salad  "` saved as `Sad Dad Salad`.)*

**A tuned car faster than its archetype is not dropped, live.** A gripper (top speed 150,
un-ceilinged bound 187.5) tuned to 233 and driven flat out reached **214.1 studs/s** over 15
seconds: the server believed **233**, allowed **291.25**, and dropped **0 of 0** packets.
With the top speed tuned to 310 the ceiling followed to **310** and the bound to **387.5**.
The car kept its **gripper body** throughout.

**Save, forget, reload.** Two cars saved, then everything the server held in memory for that
player dropped exactly as leaving drops it, then read back out of the store exactly as
joining reads it: *Night Runner* (gripper, 2.65 / 41.3 / 233) and *Brick* (bruiser, bite 90,
power 35) both came back **identical**, and were nil in between. *Brick* was then loaded,
edited to power 12.5 and saved again; *Night Runner* reloaded unchanged at 2.65 / 41.3 /
233, with `MaxAcceleration` back to the gripper's own 21.5.

**The console** was clean of anything from game code across both playtests.

**Not checked:** real typed characters reaching the TextBox (the MCP's synthetic key presses
do not reach one), and the panel on a phone or a gamepad — the `-` / `+` buttons are
`Selectable` but gamepad navigation was not driven.

- **Playtest:** the user drives it and moves the sliders. Whether these are the right eight,
  what they should be called and whether the panel is in the right place are theirs.

## Open questions

- **Are these the right eight, and are the names right?** Every one of them is an agent's
  guess at what a driver would call it. The user renames anything a person reads
  (`AGENTS.md`).
- **Should a tuned car be promotable to an archetype?** Today a saved car is a tune and
  `Cars/Archetypes` is written by hand. "Make this one of the four" is one button and a file
  write, and it is a decision about where the line is, not a feature.
- **Per-player speed bounds.** The ceiling above is a dev tool's answer. The proper one is
  three lines in `CarService:_numbers` and should happen the moment a tuned car is anything
  a player can have.
- **Does the panel belong on the right?** It is where the readout is not. On a phone the two
  together cover a lot of screen.
