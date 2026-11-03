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
| `PlaygroundService` | Builds the prototype playground from its layout module and gives out its named spots | `GetSpot(name)`, `DebugState()` |
| `CarService` | Spawns a car per player, replicates each car's state to the other clients | `DebugState()` |

## Controllers (client)

> Every module in `src/StarterPlayerScripts/Controllers/`, one line each.

| Controller | What it does | Main entry points (signatures in `CONTRACTS.md`) |
|---|---|---|
| `DriftController` | The drift model: the fixed-step simulation that moves the local player's car | `DebugState()`, `DebugDrive(inputs, seconds)` |
| `CarInputController` | Steering, drift and brake input across keyboard, touch and gamepad | `DebugState()` |
| `CarCameraController` | The chase camera that follows the car and leads the slide | `DebugState()` |

## Shared modules

> The modules in `src/ReplicatedStorage/Shared/` that other code requires.

| Module | What it holds |
|---|---|
| `Loader` | The shared half of both loaders: require, Init by Priority, Start in threads, and the Studio debug bridge |
| `Net` | The remotes registry: `event`, `unreliable`, `func`. The server creates them, the client waits |
| `Signal` | Events between modules: `new`, `Connect`, `Once`, `Fire`, `Wait`, `DisconnectAll` |
| `Config` | Every tuning number, one child module per feature, loaded on first use (`Config.Drift`) |
| `CarModel` | The car's shape and dimensions, built by code, shared so the server and client agree |

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
  - Server, `game.ServerStorage.DebugBridge:Invoke(...)`: `PlaygroundService:DebugState()`, `DebugWalk(stepId, lateral, every)` and `DebugBounds()`, `CarService:DebugState()`.
  - Client, `game.Players.LocalPlayer.PlayerScripts.DebugBridge:Invoke(...)`: `DriftController:DebugState()`, `DebugDrive(inputs, seconds, opts)` and `DebugReset()`, `CarInputController:DebugState()`, `DebugSetInput(steer, drift, brake)`, `DebugClearInput()` and `DebugDrag(offsetPx, flickRate)` (the real gesture, not a bypass), `CarCameraController:DebugState()`.
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
