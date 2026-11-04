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
| `CarService` | Spawns a car per player, replicates each car's state to the other clients, and owns **which archetype each player is in** and **which world they are in** | `SpawnCFrame()`, `CarKey(player)`, `SetCar(player, key)`, `Respawn(player, to?)`, `DebugState()` |
| `RoadService` | The endless road: generates it from numbers, keeps a rolling window of about 14 pieces round the car, moves a closing barrier up behind it, and owns progress. **Off until `Generate(seed)`** -- nothing builds at `Init` (`features/track-generation.md`) | `Generate(seed?)`, `Stop()`, `HasRoad()`, `SpawnCFrame()`, `PieceAt(position)`, `Progress(position)`, `Bounds()`, `DebugState()` |
| `GarageService` | The player's tuned cars: validates a save against `Shared/Cars/Garage`, keeps them in a **throwaway dev store** (not `DataService`, which is still unbuilt), and widens the server's speed bound to cover a tuned car rather than dropping its packets | `Get(player)`, `Save(player, name, car)`, `Delete(player, name)`, `SetTune(player, car?)`, `DebugState()` |

## Controllers (client)

> Every module in `src/StarterPlayerScripts/Controllers/`, one line each.

| Controller | What it does | Main entry points (signatures in `CONTRACTS.md`) |
|---|---|---|
| `DriftController` | The drift model: the fixed-step simulation that moves the local player's car | `DebugState()`, `DebugDrive(inputs, seconds)` |
| `CarInputController` | Steering, drift and brake input across keyboard, touch and gamepad | `DebugState()` |
| `CarCameraController` | The reference game's in-game camera: it looks at the car from a fixed radius, swings that place round as the car turns, and leans it toward the travel as the slip opens. No roll, no zoom. Its targets run on their own fixed step (`CamTargetStep`), interpolated between, so every frame rate puts the camera in the same place | `Release()`, `Follow()`, `DebugState()`, `DebugProbe(opts)`, `DebugRecord(seconds)` |

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
  - Server, `game.ServerStorage.DebugBridge:Invoke(...)`: `PlaygroundService:DebugState()`, `DebugWalk(stepId, lateral, every)`, `DebugBounds()` and `DebugObstacles()`, `TrackService:DebugState()` and `DebugRoadWidths(lines?)`, `CarService:DebugState()`, `DebugRespawn(userId?)`, `DebugCross(world?, userId?)` (puts the car in the other world) and `DebugGroundUnder(position)`, `RoadService:DebugState()`, `DebugAdvance(position)`, `DebugAdvanceTo(n)`, `DebugGenerator()` and `DebugPieces()`, and `DebugDriftTests "useCar" <key>` (moves the SERVER's car and re-dresses every live one). `DebugRoadTests` takes `"run"`, `"drive"`, `"sweep"` or `"stalls"`.
  - Client, `game.Players.LocalPlayer.PlayerScripts.DebugBridge:Invoke(...)`: `DriftController:DebugState()`, `DebugDrive(inputs, seconds, opts)`, `DebugReset()` (asks the server for a respawn; where a car goes is not the client's to say) and `DebugTeleport(cf)` (moves it without asking, to prove the server rejects that), `CarInputController:DebugState()`, `DebugSetInput(steer, handbrake)`, `DebugClearInput()`, `DebugDrag(offsetPx, originPx)` (the real gesture, not a bypass), `DebugTravelPx(sensitivity?)` and `DebugSettings(mode?, sensitivity?)` (stands in for the settings screen), `CarCameraController:DebugState()`, `DebugProbe(opts)` (settles a throwaway rig against a car held at a fixed slip: `{ slipDeg, speed, seconds, fps, blend, yawDeg, sweepSeconds }`, where `blend` overrides `CamVelocityBlend` for that run only) and `DebugRecord(seconds)` (watches the live camera and returns the worst frame: position step, view turn, roll step, and the car's distance from the screen centre).
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
