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
| `CarState` | UnreliableRemoteEvent | Client → server | `CarService` | `(cf: CFrame, velocity: Vector3, drifting: boolean)` at 20 Hz. Server checks, in order: the player has a car the server has put somewhere; types; rate limit `StateRateLimit`/s per UserId; speed checked horizontal and vertical apart (`Config.Drift.TopSpeed` × `StateSpeedTolerance`, and `TerminalFall` × the same); the distance from where the server expects the car, with the budget since that position was agreed split the same way (`StateMoveTolerance`, plus `StateMoveAllowance` studs). A packet that fails is dropped and counted, not kicked, while this is a prototype — **and the next packet is checked against the same position**: a rejected packet never becomes the truth. For `RespawnGrace` after a respawn a packet that fails against the new position is also tried against the position the car was moved from, because a packet sent before the respawn can land after it; that one is passed on but does not move where the car is expected. **Not yet authoritative:** the server bounds speed and distance, it does not re-run the model. Before anything is scored or sold it must (`features/drift-model.md` "Open questions") |
| `CarRespawn` | RemoteEvent | Both ways | `CarService` | **Client → server:** `()`, a request, when the client's car has fallen below `Config.Drift.RespawnBelowY` or `DriftController:DebugReset()` is called. **No payload: the client cannot propose a position,** and anything sent is ignored. Server checks: the player has a live car (else ignored); rate limit `RespawnRateLimit` requests a second per UserId, the rest dropped and counted in `respawnsRefused`; at least `RespawnCooldown` seconds since that player's last respawn. A refused request gets no answer, and the client asks again after `RespawnAnswerWait`. **Server → client:** `(cf: CFrame)`, where the server has just put the car; the client restarts its simulation there. The client sends no `CarState` between asking and being answered |
| `CarStateOther` | UnreliableRemoteEvent | Server → client | `CarService` | `(userId: number, cf: CFrame, velocity: Vector3, drifting: boolean)`: another player's car, for drawing it |

## Tags and attributes

> Every tag and attribute that other code reads. Studio-only attributes start with `__`.

| Tag or attribute | On | Set by | Used by |
|---|---|---|---|
| attr `__lync_port` | Workspace (Studio only) | Set by hand per place (docs/workflow/LANES.md) | Lync |
| attr `__test_profile` | Workspace (Studio only) | Set by hand in worker places | DataService (docs/workflow/TESTING.md) |
| attr `__agent_play` | Workspace (Studio only) | Agents, before each playtest | The quiet-playtest module (docs/workflow/TESTING.md) |
| attr `__studio_audio` | Workspace (Studio only) | Agents, for deliberate audio tests | The quiet-playtest module (docs/workflow/TESTING.md) |
| tag `DriftSurface` | Every part the car may drive on | `PlaygroundService`, when it builds the world | The drift model's ground rays filter to it. Buildings, pillars and cones deliberately don't carry it: they are things to hit, not ground |

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
| `PlaygroundService` | `GetSpot` | `(name: string) -> CFrame` | A named spot in the world; errors on an unknown name. The spots are `Spawn`, `OpenGround`, `PillarRun`, `DistrictGate`, `Boulevard`, `TightAlley`, `CircleCentre` and `RampBase` |
| `PlaygroundService` | `DebugState` | `() -> { built: boolean, partCount: number, coneCount: number, buildingCount: number, pillarCount: number, spots: { [string]: CFrame }, segments: number, plate: { size: Vector3, y: number }, open: { minX, maxX, minZ, maxZ, clearRadius: number } }` | The world as built, for tests and agent playtests. `DebugWalk` and `DebugBounds` sit beside it, Studio only |
| `PlaygroundService` | `DebugObstacles` | `() -> { { id: string, kind: string, x: number, z: number, halfX: number, halfZ: number, top: number, bottom: number } }` | Every wall as a flat footprint, measured from the built parts: the tests use it to prove the streets are open, that nothing drivable runs through a wall, and that the yard is clear. Studio only |
| `CarService` | `SpawnCFrame` | `() -> CFrame` | Where a car starts, and where every respawn puts it back: `PlaygroundService:GetSpot("Spawn")`, or above the origin in a place with no playground |
| `CarService` | `Respawn` | `(player: Player) -> CFrame?` | Moves that player's car to `SpawnCFrame()`, records it as where the server expects the car, and tells the client over `CarRespawn`. `nil` if refused (no car, cooldown, rate limit). The only thing that moves a car after it spawns |
| `CarService` | `DebugState` | `() -> { cars: { { userId, name, position, expected: Vector3?, dropped: number } }, carCount, spawn: Vector3, droppedStates: number, respawns: number, respawnsRefused: number, inFlightKept: number, charactersOff: boolean, physicsOffenders: { string } }` | The cars as the server sees them, with where it expects each one and how many of its packets it has dropped. `DebugRespawn(userId?)` sits beside it, Studio only |
| `DriftController` | `DebugDrive` | `(inputs: { { t: number, steer: number, drift: boolean, brake: boolean } }, seconds: number, opts: { fps: number?, sample: number?, start: CFrame?, live: boolean? }?) -> ({ Vector3 }, Summary)` | Runs the model with no player and returns the path, for the determinism test, with a summary beside it: entry and exit speed, peak slip, time to break loose, heading change |
| `DriftController` | `DebugState` | `() -> { position: Vector3, headingDeg: number, speed: number, forwardSpeed: number, lateralSpeed: number, verticalSpeed: number, slipDeg: number, slipFrontDeg: number, slipRearDeg: number, wheelAngleDeg: number, yawRate: number, load: number, slideFrac: number, phase: string, gripBlend: number, rearGrip: number, airborne: boolean, wallHit: boolean, breakLooseSeconds: number, ... }` | The model's full state, for tests and agent playtests. Angles are degrees and named `*Deg`. `load` is −1..1, where the car's weight has got to; `slideFrac` is 0..1, how sideways it is as a share of `SlideAngleFull`. There is no `wantedSlipDeg`: the model names no angle for the car to go to (`features/drift-model.md` "Rules and numbers") |
| `DriftController` | `DebugReset` / `DebugTeleport` | `() -> DebugState` / `(cf: CFrame) -> DebugState?` | Studio only. `DebugReset()` asks the server for a respawn and waits for the answer — it takes no CFrame, because where a car goes is not the client's to say. `DebugTeleport(cf)` moves the car **without** asking, which is what a cheat looks like: every `CarState` after it is dropped by the server |
| `CarInputController` | `DebugSetInput` / `DebugClearInput` | `(steer: number?, drift: boolean?, brake: boolean?) -> input` / `() -> boolean` | Studio only: drive the live car with no keyboard |
| `CarInputController` | `DebugDrag` | `(offsetPx: number?, flickRate: number?) -> dragState` | Studio only: act out the real gesture rather than bypassing it. `nil` lifts the finger |
| `Shared/CarModel` | `physicsOffenders` | `(model: Instance) -> { string }` | Everything in a car that would hand it to Roblox physics. Empty is the rule, and `DriftTests` asserts it |

## Place settings

> Settings made in Studio, not in git, and set the same way in every place: the Main place, every lane, and the published game (docs/workflow/LANES.md "Add a lane").

- `Workspace.StreamingEnabled`: **off** (`ARCHITECTURE.md` "World and streaming"): the playground is small, and streaming surfaces in under a fast car would be felt as the ground failing a ray.
