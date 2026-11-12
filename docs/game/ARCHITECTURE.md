# Architecture

This game's code as built: what each module does and where things are registered. The rules every game follows are in docs/workflow/CODING.md; what other code relies on (data, remotes, tags, attributes, events) is in `CONTRACTS.md` and `EVENT-CATALOG.md`. Started in the Foundation phase; update it in the same commit as the code it describes. Replace each prompt with the answer.

**Where it stands:** only the prototype skeleton and the drift prototype exist. The rest of the foundation kit (DataService, PlayerData, Sounds, the UI kit, notifications, analytics, live config, the admin console) is deliberately not built yet: the prototype's only job is to prove the drift feel (`ROADMAP.md` "Next"). It is built before anything that saves, sells or scores.

## Overview

The server builds the world and owns spawning; the client simulates its own car and draws it. They talk through remotes in `ReplicatedStorage.Remotes`, created by the server and listed in `CONTRACTS.md`.

The car is **not** driven by Roblox's physics (`DECISIONS.md`, 2026-11-03). Its parts are anchored and it is moved by our own fixed-step simulation each frame, on the client that drives it.

## Services (server)

> Every module in `src/ServerScriptService/Services/`, one line each.

| Service | What it does | Main entry points (signatures in `CONTRACTS.md`) |
|---|---|---|
| `PlaygroundService` | Builds the playground from its layout module and gives out its named spots. A place that also has a hand-placed track gets this one built **out of its way** (`PlaygroundOffsetFromTrack`) rather than not at all | `GetSpot(name)`, `Bounds()`, `DebugState()` |
| `TrackService` | Adopts a hand-placed track: tags its road by colour, leaves everything else as dirt, anchors what is loose, deletes what runs, keeps the baseplate as the floor of last resort, and finds a spawn on the road by ray | `HasTrack()`, `SpawnCFrame()`, `Bounds()`, `DebugState()`, `DebugRoadWidths(lines?)` |
| `CarService` | Spawns a car per player, replicates each car's state to the other clients, and owns **which archetype each player is in** and **which of the three worlds they are in** -- the road being a world that comes and goes (`features/endless-run.md`) | `SpawnCFrame()`, `CarKey(player)`, `SetCar(player, key)`, `Respawn(player, to?)`, `Place(player, cf)`, `WorldAt(position)`, `DebugState()` |
| `RoadService` | The endless road: generates it from numbers, keeps a rolling window of about 14 pieces round the car, moves a closing barrier up behind it, and owns progress -- **and the run**: who is on the road, which world each of them came from, and where a fall puts them back. **Off until somebody presses the start button** -- nothing builds at `Init` (`features/track-generation.md`, `features/endless-run.md`) | `Generate(seed?)`, `Stop()`, `HasRoad()`, `StartRun(player)`, `EndRun(player)`, `InRun(player)`, `RunState(player?)`, `SpawnCFrame()`, `JoinCFrame()`, `SafeStart(position?)`, `PieceAt(position)`, `Progress(position)`, `Bounds()`, `DebugState()` |
| `GarageService` | The player's tuned cars: validates a save against `Shared/Cars/Garage`, keeps them in a **throwaway dev store** (not `DataService`, which is still unbuilt), and widens the server's speed bound to cover a tuned car rather than dropping its packets | `Get(player)`, `Save(player, name, car)`, `Delete(player, name)`, `SetTune(player, car?)`, `DebugState()` |

## Controllers (client)

> Every module in `src/StarterPlayerScripts/Controllers/`, one line each.

| Controller | What it does | Main entry points (signatures in `CONTRACTS.md`) |
|---|---|---|
| `DriftController` | The drift model: the fixed-step simulation that moves the local player's car | `DebugState()`, `DebugDrive(inputs, seconds)` |
| `ScoreController` | The endless run's score, on the client: steps `Drift/Score` on every simulation step while the server says this player is in a run (`features/endless-score.md`) | `View()`, `DebugState()` |
| `CarInputController` | Steering, drift and brake input across keyboard, touch and gamepad | `DebugState()` |
| `CarCameraController` | The reference game's in-game camera: it looks at the car from a fixed radius, swings that place round as the car turns, and leans it toward the travel as the slip opens. **A touch of roll and a speed shake since `T-072`** -- both applied to the rendered camera only, downstream of the stepped targets, so neither can reach the feedback loop. Still no zoom and no position smoothing: those were the predecessor camera the user rejected. Its targets run on their own fixed step (`CamTargetStep`), interpolated between, so every frame rate puts the camera in the same place | `Release()`, `Follow()`, `DebugState()`, `DebugProbe(opts)`, `DebugShakeProbe(opts)`, `DebugRecord(seconds)` |
| `SkyController` | The sky and the day-night cycle (`features/day-night.md`, `T-144`): works the moment out from the server's clock, asks `Shared/DayNight` for its look and sets this client's Lighting, atmosphere, clouds and colour grading, and the cliffs' haze in the road mesh (`SplineMesh.setHaze`). Nothing is sent; the server sets no lighting | `DebugState()`, `DebugLook(t)`, `DebugKeyTimes()`, `DebugHold(t)`, `DebugSpeed(k, t?)`, `DebugResume()` |
| `RoadGroundController` | Solid ground for the local avatar while it is out of the car on the spline road (`T-154`, `features/mountain-road.md` "Walking on the road"): a patch of invisible anchored tiles over tarmac and grass, walls at rock faces, hedges, crash barriers and the closing barrier, nothing past a cliff's lip. Client-only `Workspace.RoadGround`, never tagged `DriftSurface`, and gone whenever the car is driven | `DebugState()`, `DebugPoint(s, d)` |

## Shared modules

> The modules in `src/ReplicatedStorage/Shared/` that other code requires.

| Module | What it holds |
|---|---|
| `Loader` | The shared half of both loaders: require, Init by Priority, Start in threads, and the Studio debug bridge |
| `Net` | The remotes registry: `event`, `unreliable`, `func`. The server creates them, the client waits |
| `Signal` | Events between modules: `new`, `Connect`, `Once`, `Fire`, `Wait`, `DisconnectAll` |
| `Config` | Every tuning number, one child module per feature, loaded on first use (`Config.Drift`) |
| `CarModel` | The car's shape and dimensions, built by code, shared so the server and client agree |
| `Cars` | Which archetype is active, how a key resolves, the live tune layer, the grip curve and the stat panel's data (`features/car-archetypes.md`) |
| `Road/Pieces`, `Road/Generator`, `Road/Builder` | The endless road as pure maths -- what a piece is, the rotate-and-translate join, the sequence with its bias and lookahead -- and the builder that turns a placed piece into anchored parts |
| `Road/Spline`, `Road/SplineGen` | The spline road (`T-132`, in progress) as pure maths: one continuous curve from curvature, grade and bank knots along arc length, the ground and normal under any point, and the seeded generator that lays it in sections with no crossing and no traps. `Config.Spline` holds its numbers. `Road/SplineParts` lays the same road as parts: the tests' yardstick, and a stand-in to look at before the mesh |
| `Drift/SplineWorld` | The car's world on the spline road (`T-134`): ground, walls and push-out from the curve's maths, wrapped round `World.live` for everywhere else. `DriftController:UseSpline` switches to it; `DebugSpline` reads where the car is on the curve |
| `Road/SplineMesh`, `Drift/SplineRoadView` | The spline road drawn on each client (`T-135`): one EditableMesh surface per 480-stud chunk (a client may hold eight), barriers and dashes as plain parts, a parts fallback; the view keeps five chunks round the car |
| `Road/SplineSequence`, `Controllers/SplineRoadController` | The endless run on the spline road (`T-136`), behind `Config.Road.Mode`: the spline as a sequence of pieces for `RoadService`, which then lays no parts and sends sections on `RoadSpline`; the client controller replays them into the curve the car drives on and the view draws |
| `Services/SplineTestService` | **Studio only.** The TEST ONLY panel's spline road (`T-134`): lays a spline road far out at `Config.Spline.TestOrigin`, sends the client its sections (the client draws the road), puts the car on it; a fall goes back on to it. `DebugState`, `DebugToggle` |
| `Cars/Garage` | The tuner's eight sliders **and every rule about what a tuned car may be**. Shared so the client draws from it and the server validates against it (`features/car-tuner.md`) |

Loaders: `ServerScriptService/Main.luau` loads `Services/`, `StarterPlayerScripts/Client.luau` loads `Controllers/`. Both call `Init()` on every module in `Priority` order (highest first, nothing yields), then `Start()` on each in its own thread. A module that fails to load is warned about and skipped.

## Registries

Where each kind of thing is listed in code, so nothing gets scattered.

| What | Module |
|---|---|
| Remotes | `Shared/Net` (names in `CONTRACTS.md`) |
| Config and tuning | `Shared/Config`, one child module per feature |
| Sounds | (not built yet) |
| Asset ids | (not built yet) |
| Analytics events | (not built yet) |
| Live config keys | (the config wrapper; keys and live values in `live/EXPERIENCE.md` "Configs") |
| Timed releases | (not built yet) |
| Update log | (only if the game has one, `PROJECT.md`) |

## Studio tools

> What tests and agents can reach (docs/workflow/TESTING.md).

- **Debug bridge members:**
  - Server, `game.ServerStorage.DebugBridge:Invoke(...)`: `PlaygroundService:DebugState()`, `DebugWalk(stepId, lateral, every)`, `DebugBounds()` and `DebugObstacles()`, `TrackService:DebugState()` and `DebugRoadWidths(lines?)`, `CarService:DebugState()`, `DebugRespawn(userId?)`, `DebugCross(world?, userId?)` (puts the car in the other world), `DebugGroundUnder(position)` and `DebugBelieve(userId, position)` (tells the server it has agreed a car is there -- every question about which world a car is in hangs off that one position, and a test with no client cannot send a `CarState` the movement check would accept), `RoadService:DebugProfile(on: boolean?)` (Studio only: `nil` reads it, `true`/`false` sets and clears the per-piece timing ring; returns `{ on, pieces, destroys, windows, totals }`), `RoadService:DebugState()`, `DebugAdvance(position)`, `DebugAdvanceTo(n)`, `DebugGenerator()`, `DebugPieces()`, `DebugPress(want, userId?)` (presses the start button through the real handler, guards and all), `DebugJoin(userId)` / `DebugLeave(userId)` (a second driver with no car behind it, because Studio gives a test one player), `DebugTick()` and `DebugClearLimits()`, and `DebugDriftTests "useCar" <key>` (moves the SERVER's car and re-dresses every live one). `DebugRoadTests` takes `"run"`, `"drive"`, `"sweep"` or `"stalls"`; `DebugRunTests` takes `"run"` or `"drive"` and **needs a playtest with a player in it**.
  - Client, `game.Players.LocalPlayer.PlayerScripts.DebugBridge:Invoke(...)`: `DriftController:DebugState()`, `DebugDrive(inputs, seconds, opts)`, `DebugReset()` (asks the server for a respawn; where a car goes is not the client's to say) and `DebugTeleport(cf)` (moves it without asking, to prove the server rejects that), `CarInputController:DebugState()`, `DebugSetInput(steer, handbrake)`, `DebugClearInput()`, `DebugDrag(offsetPx, originPx)` (the real gesture, not a bypass), `DebugTravelPx(sensitivity?)` and `DebugSettings(mode?, sensitivity?)` (stands in for the settings screen), `CarCameraController:DebugState()`, `DebugProbe(opts)` (settles a throwaway rig against a car held at a fixed slip: `{ slipDeg, speed, seconds, fps, blend, yawDeg, sweepSeconds }`, where `blend` overrides `CamVelocityBlend` for that run only) and `DebugRecord(seconds)` (watches the live camera and returns the worst frame: position step, view turn, roll step, and the car's distance from the screen centre).
  - **Two LocalScripts in `Drift/` carry their own bridges,** because the client loader's `DebugBridge` resolves loaded Controllers and neither is one: `PlayerScripts.TunerBridge` (the car tuner) and `PlayerScripts.RoadHudBridge` (`Invoke("DebugState")`, `Invoke("DebugPress")` -- the start button, pressed through its real handler).
  - Client, the sky: `SkyController:DebugHold(t)` holds the cycle at `t` seconds in (noon 60, sunset 130, midnight 200, sunrise 270), `DebugSpeed(k, t?)` runs it `k` times as fast, `DebugResume()` puts it back on the server's clock.
  - Tests: `Debug<Name>Tests` reaches `ServerScriptService/Tests/<Name>Tests`.
- **Test profiles:** none yet; there is no DataService.
- **Admin commands:** none yet.

## Vendored libraries

> One row per library in `src/` (docs/workflow/CODING.md "Third-party code"). Source is its GitHub repo, like `github.com/owner/name`, so Rocco can check for new releases; local patches are what we changed, or "none".

| Library | Version | Source | Local patches |
|---|---|---|---|
| | | | |

## World and streaming

**Built by code at runtime.** The playground is created by `PlaygroundService` from one layout module (`ServerScriptService/Playground/Layout.luau`), which holds every position and size; no gameplay code holds a coordinate. This keeps the world in git, identical in every lane and place, and changeable in a commit.

Named spots come from `PlaygroundService:GetSpot(name)`, never from coordinates in the code that uses them (`WORLD.md` "Named spots").

`StreamingEnabled` is **off**: the playground is small and the car moves fast enough that streaming in surfaces under it would be felt as the ground failing a ray.
