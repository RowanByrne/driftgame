# Contracts

Everything code relies on across modules and tasks: data, remotes, tags, attributes, paths and service APIs. Code against this doc. A change to it goes in the same commit as the code, and a change other tasks build on goes in first, as its own small commit (docs/workflow/CONDUCTOR.md "Main"). Analytics events have their own contract in `EVENT-CATALOG.md`. Replace each prompt with the answer.

## Data

### Stores

> Every data store the game uses. Moving a store up a version starts everyone fresh (docs/workflow/LAUNCH.md "Launch wipe"), and each store needs a right-to-be-forgotten template keyed the same way.

| Store | Kind (standard or ordered) | Key | What it holds |
|---|---|---|---|
| `<CODE>_Player_v1` | standard | `u{UserId}` | Player profiles |

### Profile

**Schema version:** 1. A change to the profile ships with a migration, tested on saved data from the previous version (docs/workflow/CODING.md "Saving").

> Every profile key. Keys starting with `_` are server-only: they're saved, but never sent to the client.

| Key | Type | Default | Written by | Notes |
|---|---|---|---|---|
| | | | | |

### Settings

> The keys a player can change from the client, and how the server checks each value.

| Key | Type | Default | Allowed values |
|---|---|---|---|
| | | | |

### Migrations

| Version | Date | What changed |
|---|---|---|
| 1 | | First version |

## Remotes

> Every remote, named `<Feature><Action>` and created through `Shared/Net`. Every client-to-server remote lists the checks the server makes on it: types, ranges, rate limit.

| Name | Type | Direction | Owner | Payload and checks |
|---|---|---|---|---|
| `CarSpawn` | RemoteEvent | Server → client | `CarService` | `(car: Model, spawnCFrame: CFrame)`: the car this client drives, and where it starts |
| `CarState` | UnreliableRemoteEvent | Client → server | `CarService` | `(cf: CFrame, velocity: Vector3, drifting: boolean)` at 20 Hz. Server checks: types; speed ≤ `Config.Drift.TopSpeed` × 1.25; movement since the last packet ≤ that speed × elapsed × 1.5; rate limit 30/s per UserId. Out of range is dropped and counted, not kicked, while this is a prototype. **Not yet authoritative:** before anything is scored or sold, the server simulates or re-checks the model (`features/drift-model.md` "Open questions") |
| `CarStateOther` | UnreliableRemoteEvent | Server → client | `CarService` | `(userId: number, cf: CFrame, velocity: Vector3, drifting: boolean)`: another player's car, for drawing it |

## Tags and attributes

> Every tag and attribute that other code reads. Studio-only attributes start with `__`.

| Tag or attribute | On | Set by | Used by |
|---|---|---|---|
| attr `__lync_port` | Workspace (Studio only) | Set by hand per place (docs/workflow/LANES.md) | Lync |
| attr `__test_profile` | Workspace (Studio only) | Set by hand in worker places | DataService (docs/workflow/TESTING.md) |
| attr `__agent_play` | Workspace (Studio only) | Agents, before each playtest | The quiet-playtest module (docs/workflow/TESTING.md) |
| attr `__studio_audio` | Workspace (Studio only) | Agents, for deliberate audio tests | The quiet-playtest module (docs/workflow/TESTING.md) |
| tag `DriftSurface` | Every part the car may drive on | `PlaygroundService`, when it builds the world | The drift model's ground rays filter to it |

## Paths

> Instance paths other code relies on, such as where the world is built, its named-spot markers (WORLD.md "Named spots"), or where a folder of models lives.

| Path | What's there | Made by |
|---|---|---|
| `ReplicatedStorage.Remotes` | Every remote | `Shared/Net`, on the server |
| `Workspace.Playground` | The prototype world: every surface, ramp and cone | `PlaygroundService` at `Init` (`Priority = 100`), before anything spawns into the world |
| `Workspace.Cars` | One model per player's car | `CarService` |

## Service APIs

> Signals and methods that one service or controller exposes for others, with their signatures. Internal methods don't belong here.

| Module | Member | Signature | What it does |
|---|---|---|---|
| `Shared/Net` | `event` / `unreliable` / `func` | `(name: string) -> RemoteEvent / UnreliableRemoteEvent / RemoteFunction` | Creates the remote on the server, waits for it on the client |
| `Shared/Signal` | `new` | `() -> Signal` | `Connect(fn)`, `Once(fn)`, `Fire(...)`, `Wait()`, `DisconnectAll()` |
| `Shared/Config` | (index) | `Config.<Feature>` | The feature's tuning table, from `Shared/Config/<Feature>.luau` |
| `Shared/Loader` | `load` | `(folder: Instance?, label: string) -> { [string]: any }` | Requires each ModuleScript child, `Init()` by `Priority`, then `Start()` in threads |
| `Shared/Loader` | `bridge` | `(loaded, parent: Instance, testsFolder: Instance?) -> BindableFunction?` | The Studio-only `DebugBridge` (docs/workflow/TESTING.md) |
| `Shared/CarModel` | `build` | `() -> Model` | The placeholder car, built by code: anchored parts, no constraints |
| `PlaygroundService` | `GetSpot` | `(name: string) -> CFrame` | A named spot in the world; errors on an unknown name |
| `PlaygroundService` | `DebugState` | `() -> { built: boolean, partCount: number, coneCount: number, spots: { [string]: CFrame }, segments: number, plate: { size: Vector3, y: number } }` | The world as built, for tests and agent playtests. `DebugWalk` and `DebugBounds` sit beside it, Studio only |
| `DriftController` | `DebugDrive` | `(inputs: { { t: number, steer: number, drift: boolean, brake: boolean } }, seconds: number) -> { Vector3 }` | Runs the model with no player and returns the path, for the determinism test |

## Place settings

> Settings made in Studio, not in git, and set the same way in every place: the Main place, every lane, and the published game (docs/workflow/LANES.md "Add a lane").

- `Workspace.StreamingEnabled`: **off** (`ARCHITECTURE.md` "World and streaming"): the playground is small, and streaming surfaces in under a fast car would be felt as the ground failing a ray.
