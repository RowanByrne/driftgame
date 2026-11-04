# Feature: The endless run

**Status:** **built** (`T-051`, step 3 of the `T-044` plan). **Owner task:** `T-051`, branch
`agent/road-run`.

The road itself is `features/track-generation.md` and is not this spec's. This is the **run**: the
button that starts one, where you land, what a fall costs, and how you get back to the other two
worlds.

## Goal

The road existed and nobody could reach it. `RoadService:Generate(seed)` was the only thing that
made one and nothing in the game called it. The user asked for one thing, verbatim: *"have it be a
button you press at the top of the screen to start the endless mode."* So: one button, at the top
of the screen, that starts and ends a run.

## How it plays

1. A plain button sits at the top middle of the screen, reading **START ENDLESS RUN**. It is there
   from the moment the client loads, in every world.
2. Press it. The server lays a road, picks a seed off its own clock, and puts your car on piece 1,
   on the centre line, facing the way the road goes. The button turns red and reads **END RUN**,
   and the line under it reads `on the road -- piece 12, alone`.
3. Drive. The road arrives in front of you and disappears behind you, exactly as
   `track-generation.md` describes; nothing about the run changes the road.
4. **Fall off** and you go back **on the road**, at the start of the piece you fell from. You do
   not lose the run and you do not lose your progress. The piece you were in the middle of is what
   a fall costs.
5. Press the button again and the run ends: the road comes down and your car is back in the world
   you pressed start in — the track, or the playground.

**Somebody else pressing start while you are driving joins your road.** Same seed, same pieces,
same window; they land beside whoever is furthest. They can end their run without ending yours.

## Left out

- **Any reason to drive it.** There is no score, no distance counter, no finish, no crash and no
  failure. A run ends when the player presses the button and in no other way
  (`track-generation.md` "What this spec does NOT decide"; scoring is specced in
  `drift-model.md` "Score" and deliberately not built).
- **A HUD.** The button says which state it is in and which piece the server has you on. That is
  the whole of it. The real run HUD waits for scoring.
- **Any art.** Two colours and a rounded rectangle (UI.md "Programmer art").
- **Analytics.** The loop's events are designed with scoring, which is not built.
- **Separate roads per player.** One server, one road. See "More than one player".

## Rules and numbers

### The button

| | |
|---|---|
| Where | Top middle, 8 px below the Roblox inset. 220 x 44 px at every layout |
| Says | `START ENDLESS RUN` (green) or `END RUN` (red), with a state line under it |
| Sends | `RoadRun`, one boolean: `true` start, `false` end, `nil` a question |
| Never sends | A position, a seed, a piece, a progress, or anything else at all |

**The two guards on it are not new numbers, and that is deliberate.** `Config/Road.luau` belongs
to another task (`T-050`) for as long as the piece set is being added to, so the run reuses the two
numbers that already bound the two other things a client may ask the server to do to its car:

| Guard | Number it borrows | Value |
|---|---|---|
| Asks a second per UserId | `Config.Drift.CarSwitchRateLimit` | 5 |
| Seconds between two presses that land | `Config.Drift.RespawnCooldown` | 0.5 |

A press is a car being put somewhere, so a respawn's cooldown is the right shape for it. They want
their own `Config.Road.RunRateLimit` and `RunCooldown` the day that file is free ("Open questions").

### Where you land

| Case | Where |
|---|---|
| First press of a run | Piece 1, 20 studs in from its start socket, on the centre line, at `SurfaceY + RideHeight` |
| Joining a run already going | The window's centre — the piece whoever is furthest is on |
| After a fall | The piece you were last located on |

All three are one function, `RoadService:SafeStart(position?)`, and all three obey the same two
limits: **never before `BarrierBehind - 1` pieces back from the window's centre**, because the
closing barrier is a wall at `BarrierBehind` and a car put down behind it would be facing it; and
**never before the first piece that still exists**, because the rest have been destroyed. The spec
called this `safeStart` and left it unbuilt in step 1 precisely because nothing respawned onto the
road yet.

### What a fall does

The game already had a `FallY` / `RespawnBelowY` pair and all three worlds top out at Y = 0, so no
new number was needed. A car below `RespawnBelowY` asks the server for a respawn (`CarRespawn`,
unchanged), and `CarService` answers with a place on the road.

**A fall never ends a run, and it never moves `N` backwards.** `furthestN` is the generator's own
high-water mark and nothing in the respawn path writes it; the car is put back on the piece it fell
from, which is at or behind `furthestN` and so changes nothing. Measured on a real drive: fell off
at piece 15 on purpose, put back on piece 15, furthest N went 14 → 15.

## UI

One screen, `Drift/RoadHud`, in `UI-INVENTORY.md`. A `ScreenGui` named `DriftRun` holding one
`TextButton` (`StartRun`) and one `TextLabel` (`RunState`).

**Two things about it are load-bearing rather than cosmetic:**

- **`ZIndexBehavior = Sibling`.** `Instance.new("ScreenGui")` still defaults to the legacy `Global`
  behaviour, in which a child does not draw above its parent. That has already cost this game a day
  once (`Drift/TunerUI`).
- **`DisplayOrder = 15`,** above the drag pad's 5 and below the tuner's 20. The whole screen is a
  steering pad — a finger's horizontal distance IS the car's rate of turn — so without this a thumb
  on the button would also be a thumb hauling the car round. Measured: at the button's own pixels
  the topmost Active GuiObject is `DriftRun.StartRun` with `DriftControls.DragArea` beneath it, and
  a real mouse click on it left `steer` at 0 and the drag pad's pointer at `none`.

It is a **LocalScript**, not a controller, for the same reason `Drift/TunerUI` is: the client loader
only loads `Controllers/`, this talks to one remote and nothing else, and as a LocalScript it starts
itself without `DriftController` growing a line to carry it. The day the run has a real HUD it
becomes a controller.

## Server and client

**The seed, the spawn and the progress are all the server's**, and the road is where that line gets
drawn, because a client that reports its own progress reports its own score later.

The client may say exactly one of three things, and nothing on the wire is read as anything else:

| What it sends | What the server does |
|---|---|
| `true` | Lay a road if there is none, put this player on the roster, move their car to `JoinCFrame()` |
| `false` | Take them off the roster, put their car back in the world they came from, and take the road down **if they were the last** |
| `nil` | Answer with the state, changing nothing. The HUD asks this once at startup so a client that joined mid-run shows END and not START |
| anything else | Refused and counted, and answered with the state the server really has |

**Nothing in `RoadService` moves a car.** `CarService` still owns that, as it has since T-026. The
one addition is `CarService:Place(player, cf)` — the same path as `Respawn(player, cf)` with the
respawn cooldown stood down, because that cooldown exists to stop a client hammering `CarRespawn`
and a move the server chose is not that. Its `cf` is never a value off the wire: the two callers are
the run and the Studio-only `DebugCross`.

**The road is a world `CarService` understands**, which is what makes a fall land back on it. It is
in `Worlds()` only while a run is going, and it differs from the other two in two ways that are
handled explicitly:

- **It moves.** The track and the playground are fixed boxes round a fixed spawn, so "which world is
  this position in" is the nearest spawn. The road grows away from its start for as long as the run
  lasts, so `WorldAt` asks the road directly (`PieceAt`) and only decides the other two by distance.
- **Its respawn is not its spawn.** `SpawnCFrameNear` answers with `SafeStart`, not piece 1.
- **It is never a fall-through.** `SpawnCFrameIn` can be asked for it by name, which is how a run
  starts, but `Config.Drift.StartWorld` stays `"track"` and nothing is ever sent there by default. A
  place with a road up and no track would otherwise start spawning cars into somebody else's run.

A player in a run is asked about **by the roster, not by their position**: a car that went off the
side and kept going, or that has not sent a packet yet, would otherwise fall through to the start
world and have its run silently ended by a fall.

## More than one player

**The honest answer for a test build, written down so it is a decision and not an accident: a second
player who presses start joins the road that is already there.** One server, one generator, one
window, one set of parts — the same road everyone else is driving. There is no second road, because
the window is a single server-owned thing and two of them would be two worlds.

| Question | Answer |
|---|---|
| Where do they land? | The window's centre — the piece whoever is furthest is on — never behind the closing barrier |
| Whose car does the window follow? | Whoever is furthest down the road. The barrier follows the same car |
| Can one player's END take the road out from under another? | **No.** `Stop()` runs only when the roster empties. While anyone is on it the window, the barrier and every piece stay exactly where they are, and the player who pressed END simply leaves |
| What if they disconnect mid-run? | `PlayerRemoving` takes them off the roster, and the road comes down if they were the last |
| Can a client call `Stop()`? | No. The remote reaches `StartRun` and `EndRun` and nothing else, and neither takes a position, a seed or a name |

**What this is not yet:** a race, a lobby, or a shared score. Two players on one road get in each
other's way, and the one behind is driving road the one in front chose the pace of. That is a
design question (`PITCH.md` is still Draft), not a bug.

## Contracts

In `CONTRACTS.md`, in the same commit:

- `RoadRun`, a new both-ways RemoteEvent, with its validation and both its guards.
- `RoadService:StartRun`, `EndRun`, `InRun`, `RunnerCount`, `RunState`, `SafeStart`, `JoinCFrame`,
  `RunReport`, and the Studio-only `DebugPress`, `DebugJoin`, `DebugLeave`, `DebugTick`,
  `DebugClearLimits`.
- `CarService:Place`, and the Studio-only `DebugBelieve`.
- `CarService:WorldAt` / `SpawnCFrameNear` / `Worlds`: the road as a third world.
- `PlayerScripts.RoadHudBridge`, the Studio-only bridge for a LocalScript the loader cannot see.

## Analytics

Not yet, for the same reason the road has none: the loop's events are designed with scoring.

## Monetization

None.

## Platform risks

None beyond what `drift-model.md` already records. The car on the road is still the AE86
placeholder, which is **not approved to publish**.

## Art and sound

Programmer art and nothing else: two colours, a rounded rectangle and native text. No sound — not
even on the press, which is its own small decision and is listed below.

## Testing

`ServerScriptService/Tests/RunTests.luau`, **15 checks**, run from the server debug bridge **in a
playtest**:

```
game.ServerStorage.DebugBridge:Invoke("DebugRunTests", "run")
```

**It needs a player, and that is not an accident of the harness:** every question it asks is about a
car being moved, and `CarService` will not move a car for somebody who is not there. With nobody in
the place it returns one failing check saying so rather than passing vacuously.

| Check | Measured |
|---|---|
| Nothing builds a road by itself | `HasRoad` false, no `Workspace.Road`, `StartWorld` still `track`, and `CarService` does not know the road |
| Pressing start builds a road and puts the car on piece 1 | Car moved from (-160, 3, -75) in the playground to (0, 2.400, -20020): piece 1, **0.00 studs** off the centre line of a 35-stud road, Y 2.400 against the 2.400 that is `SurfaceY + RideHeight` |
| A road built by the button is not physics | 502 parts, 167 drivable ground, **0** unanchored, **0** movers, constraints or scripts |
| A fall straight down comes back on the road | Fell from piece 18 at Y -228, put back on **piece 18**, 0.00 studs off the centre line; still in the run; the road still up with the same 16 children; furthest N 18 → 18 |
| A car that left the road altogether still comes back on to it | 4 000 studs off the side and 400 down, a position the road locates as `nil`; the respawn put it back on the road and the run survived. **The roster answered, not the position** |
| A second driver joins the same road | The generator is the same object, same seed, window unchanged at 14..28; the joiner lands on piece 18 with the closing barrier at piece 16; 2 on the roster |
| One player ending cannot strand another | The player left to the playground; the road is the **same folder** with the same 16 children, still running, 1 driver left on it |
| The last driver leaving takes the road down | `HasRoad` false, `Workspace.Road` nil, 0 on the roster |
| The same button ends the run and puts the car back | Started in the playground, drove in the road, ended in the playground **0.00 studs** from that world's spawn; `Workspace.Road` nil |
| A forged request starts nothing | **9 forgeries** — a CFrame, a Vector3, a seed, a string, a table naming a seed, a piece and a spawn, a list, an Instance, an Enum and a NaN — started nothing, were all refused and counted, and raised no error |
| A position, a seed and a progress sent **with a real press** are ignored | The car went to the road's own piece 1, **0.00 studs** from where the server computed it and **72 060 studs** from the place the "client" named |
| The cooldown | The press straight after a landed one did not start a run |
| The rate limit | 11 asks in one window: 5 taken, **6 refused**. Questions count against it too |
| **End to end** | Start, **30 pieces** driven by the autopilot in 113 s of simulation (13 552 steps), 40..117 studs/s, drifting **71%**; fell off at piece 15 on purpose, put back on piece 15, run survived, furthest N 14 → 15; ended, road gone, back in the playground |
| The drive never left the road | **0** steps off the road, **0** airborne, **0** backwards |

The drive's road is laid with a **pinned seed (8080)** and the button is pressed on to it — the join
path — so the numbers above mean the same thing every time. That the button also *makes* a road,
with a seed off the server's clock, is the second check's.

**The autopilot is a copy of `RoadTests`', not a share of it,** because that file belongs to `T-050`.
Copying it cost a day's worth of a lesson worth writing down: with `signedAngle`'s cross product the
other way round it steers away from every corner, and the car ran wide, spun into the barrier at
piece 2 and sat there for the remaining 294 simulated seconds. The handbrake-braking limb matters
for the same reason and is kept.

### Checked by hand in a playtest, which the suite cannot reach

The suite runs on the server and the button is on the client. Measured in `DR-Lane3`:

- A real mouse click on the button started a run: the HUD turned red and read `on the road -- piece
  1, alone`, and the client's own car was at (0, 2.399, -20023), `grounded` true, `airborne` false,
  `surfaceGrip` **1.00**, `rigParts` 5, `drawnGap` **0**, with 394 tagged surfaces in the client's
  ray list.
- A second click ended it: car back in the playground, `Workspace.Road` nil, HUD green.
- The click never steered: `steer` 0 and the drag pad's pointer `none` through both.

### The Studio-only methods it adds

| Method | What for |
|---|---|
| `RoadService:DebugPress(want, userId?)` | Press the button for a player with no client, through the real handler — rate limit, cooldown, type check and all |
| `RoadService:DebugJoin(userId)` / `DebugLeave(userId)` | A second driver, with no second client to be one. Puts a bare userId on the roster and hands back where their car would have gone. **The half it cannot prove is a second car moving** |
| `RoadService:DebugTick()` | Run the service's own tick now rather than waiting `TickSeconds`, so a drive is not mostly asleep |
| `RoadService:DebugClearLimits()` | Stand the two guards down, so a test that is not measuring them is not measuring a wait |
| `CarService:DebugBelieve(userId, position)` | Tell the server it has agreed a car is here. Every question about which world a car is in hangs off that one position, and a test with no client cannot send a `CarState` the movement check would accept |
| `PlayerScripts.RoadHudBridge` | `DebugState` and `DebugPress` on the client, for a LocalScript the client loader's own bridge cannot see |

## Open questions

- **The two guards want their own numbers.** `Config.Road.RunRateLimit` and `RunCooldown`, once
  `T-050` has released `Config/Road.luau`. They are borrowed, not chosen, and the borrowing is the
  only thing in this feature that is not where it belongs.
- **What two players on one road should actually be.** Joining is the honest answer for a test
  build, not a design. A race, a lobby, ghosts, or one road each are all still open, and all of them
  are downstream of what a run IS (`PITCH.md`).
- **Whether a fall should cost more than the piece you were on.** It currently costs the piece and
  nothing else. With a score there is an obvious alternative — a fall ends the run — and that is the
  user's call, not a measurement.
- **Whether the button should be the only way in.** `Config.Drift.StartWorld` could name the road
  and spawn everyone into a run. It deliberately does not: the road is entered by pressing the
  button and no other way, until there is a reason to be in one.
- **Whether the press wants a sound.** It has none. `AUDIO.md` has no entry for it.
