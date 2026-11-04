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
| attr `Shell` | A car model | `Shared/CarModel.build`, when the car gets a body shell | `Drift/Render`, to know a shell is coming. A Model replicates before its parts, so a client that catches the car mid-replication must not decide there is no shell (T-016) |
| attr `N` | A `Shell` group (`Body`, `WheelFL`…`WheelRR`) | `Shared/CarModel` | `Drift/Render`: how many parts to wait for before the group counts as arrived |
| attr `L` | Every shell part | `Shared/CarModel` | `Drift/Render`: the part's CFrame inside its group. Render writes `groupCF * L` **absolutely** every frame — **never a pivot**. `Model:PivotTo` applies a *delta*, and the server re-asserts part CFrames, so each re-assertion was paid twice and the shell walked 2500 studs off the car inside a minute while its pivot tracked perfectly (T-020) |
| tag `DriftSurface` | Every part the car may drive on | `PlaygroundService`, when it builds the world | The drift model's ground rays filter to it. Buildings, pillars and cones deliberately don't carry it: they are things to hit, not ground |
| attr `Surface` | A part tagged `DriftSurface` | Whoever builds the world | Which surface it is, for grip and score (`Config.Drift.GripTarmac` / `GripDirt`, `ScoreTarmac` / `ScoreDirt`). `"dirt"` is dirt; anything else, or absent, is tarmac. A solid the rays reach that is **not** tagged is "unspecified" and nearly frictionless (`GripUnspecified`) — except in a place where nothing at all carries the tag, where every solid is treated as road so a bare plate stays drivable |

## Paths

> Instance paths other code relies on, such as where the world is built, its named-spot markers (WORLD.md "Named spots"), or where a folder of models lives.

| Path | What's there | Made by |
|---|---|---|
| `ReplicatedStorage.Remotes` | Every remote | `Shared/Net`, on the server |
| `Workspace.Playground` | The prototype world: every surface, ramp and cone | `PlaygroundService` at `Init` (`Priority = 100`), before anything spawns into the world |
| `Workspace.Cars` | One model per player's car | `CarService` |
| `Workspace.Track` | A hand-placed track, when the place has one. Lives in the place file, never in git (AGENTS.md "Hand-built content"); the name is `Config.Drift.TrackName`. A place with one does not build the playground — both sit at the origin | Whoever placed it; adopted by `TrackService` |
| `Workspace.DriftTrajectory` | The projected-trajectory line while it is on, as a pool of reused anchored parts. Deliberately **not** inside `Workspace.Cars`, where the ground rays and the car-claiming logic would find it | `Drift/Trajectory` (client only) |

## Service APIs

> Signals and methods that one service or controller exposes for others, with their signatures. Internal methods don't belong here.

| Module | Member | Signature | What it does |
|---|---|---|---|
| `Shared/Net` | `event` / `unreliable` / `func` | `(name: string) -> RemoteEvent / UnreliableRemoteEvent / RemoteFunction` | Creates the remote on the server, waits for it on the client |
| `Shared/Signal` | `new` | `() -> Signal` | `Connect(fn)`, `Once(fn)`, `Fire(...)`, `Wait()`, `DisconnectAll()` |
| `Shared/Config` | (index) | `Config.<Feature>` | The feature's tuning table, from `Shared/Config/<Feature>.luau` |
| `Shared/Loader` | `load` | `(folder: Instance?, label: string) -> { [string]: any }` | Requires each ModuleScript child, `Init()` by `Priority`, then `Start()` in threads |
| `Shared/Loader` | `bridge` | `(loaded, parent: Instance, testsFolder: Instance?) -> BindableFunction?` | The Studio-only `DebugBridge` (docs/workflow/TESTING.md) |
| `Shared/CarModel` | `build` | `() -> Model` | The car, built by code: a `Body` and four `Wheel*` anchored parts at `wheelOffsets()`, plus a `Shell` model of matching groups when a body is configured. Nothing that moves itself |
| `Shared/CarModel` | `bodyName` / `setBody` | `() -> string` / `(name: string?) -> ()` | Which body the next car gets: `Config.Drift.CarBody`, else `"ae86"`. `setBody("block")` forces the box and four cylinders; `setBody(nil)` hands the choice back to the config |
| `Shared/CarModel` | `strayOffenders` | `(model: Instance) -> { string }` | Scripts, sounds, lights, emitters, detectors and GUIs in a car — everything that came with a Creator Store vehicle and was thrown away. Empty is the rule, and `DriftTests` asserts it beside `physicsOffenders` |
| `Drift/RemoteCars` | `DebugState` | `() -> { { userId: number, car: string, position: Vector3, reported: Vector3?, drawn: Vector3?, gap: number, drifting: boolean, live: boolean, complete: boolean, parts: number, attempts: number, firstParts: number, liveAfter: number } }` | The other players' cars as this client draws them. `gap` is the studs between where a car is **reported** and where it is **drawn** — the smoothing distance at most (`RemoteCarSmoothing` × speed, plus a packet's age), `-1` when nothing is drawn. `firstParts = 0` names the race every remote car is born with; `liveAfter` is how long that car took to catch its parts. **Not reachable through the debug bridge:** the bridge resolves loaded Controllers only, and this is an object `DriftController` owns |
| `Drift/Render` | `shellFrame` | `(shell) -> CFrame?` | Where a shell group was put, read back off its own parts. Tests only — **never `Model:GetPivot()`**, which is stale on a shell whose parts are written absolutely |
| `Drift/Render` | `apply` / `subStep` / `pose` | `(rig, state, rem: number?) -> ()` / `(state, rem: number?) -> (Vector3, number, number)` / `(state, rem: number?) -> (CFrame, number, number, number)` | `rem` is the simulation's leftover — `Sim`'s accumulator, from `DriftController:SubStep()` — and carrying the pose across it is what stopped the car juddering (T-025). The model steps at `FixedStep` and a frame lands *between* steps, so drawing `state.position` draws the car a **varying** fraction of a step behind itself; a lag that varies is judder. `rem` is clamped to `FixedStep`; nil or 0 is the old behaviour and is what a spawn, a respawn and a teleport still use. `Render.place` is unchanged, so remote cars are untouched |
| `DriftController` | `DebugTrajectory` / `DebugTrajectoryState` / `DebugTrajectoryPoints` | `(on: boolean?) -> boolean` / `() -> { enabled, flat, hz, points, segments, pathLength, simSteps, lastMs, avgMs, worstMs }` / `(opts?) -> { Vector3 }` | Studio only, and off by default (`Config.Drift.TrajectoryLine`, F6). The line where the car will go if the finger stays put, ten car lengths ahead. It is not a model of the car — the live state is deep-copied and the **real** `Model.step` is run forward, so it follows whichever archetype is active. **`flat` is a trade:** the prediction runs against a plane at the car's current ground height rather than raycasting, which costs nothing and is wrong over a crest or a ramp |
| `DriftController` | `SubStep` | `() -> number` | The simulation's leftover this frame. The camera draws from the same instant the car does; anything else reintroduces the judder in the gap between them |
| `PlaygroundService` | `GetSpot` | `(name: string) -> CFrame` | A named spot in the world; errors on an unknown name. The spots are `Spawn`, `OpenGround`, `PillarRun`, `DistrictGate`, `Boulevard`, `TightAlley`, `CircleCentre` and `RampBase` |
| `PlaygroundService` | `DebugState` | `() -> { built: boolean, partCount: number, coneCount: number, buildingCount: number, pillarCount: number, spots: { [string]: CFrame }, segments: number, plate: { size: Vector3, y: number }, open: { minX, maxX, minZ, maxZ, clearRadius: number } }` | The world as built, for tests and agent playtests. `DebugWalk` and `DebugBounds` sit beside it, Studio only |
| `PlaygroundService` | `DebugObstacles` | `() -> { { id: string, kind: string, x: number, z: number, halfX: number, halfZ: number, top: number, bottom: number } }` | Every wall as a flat footprint, measured from the built parts: the tests use it to prove the streets are open, that nothing drivable runs through a wall, and that the yard is clear. Studio only |
| `TrackService` | `HasTrack` / `SpawnCFrame` | `() -> boolean` / `() -> CFrame?` | Whether this place has a hand-placed track (a model named `Config.Drift.TrackName`), and where on its road a car starts. `PlaygroundService` asks the first before building — both worlds sit at the origin, so a place gets one or the other — and `CarService` asks the second before falling back to the playground's `Spawn` spot |
| `TrackService` | `DebugState` | `() -> { hasTrack: boolean, name: string?, size: Vector3, parts: number, road: number, scenery: number, anchoredHere: number, spawn: Vector3? }` | The adopted track. `road` is how many parts were tagged `DriftSurface` by colour; `scenery` is what was deliberately left untagged, so driving off the road is nearly frictionless (`GripUnspecified`) |
| `TrackService` | `DebugRoadWidths` | `(lines: number?) -> { crossings, narrowest, median, mean, widest, carWidth, medianInCarWidths }` | Studio only: scans the track by ray and measures how wide its roads are, in studs and in car widths. The answer to "is this track the right scale for this car?" |
| `CarService` | `SpawnCFrame` | `() -> CFrame` | Where a car starts, and where every respawn puts it back: `PlaygroundService:GetSpot("Spawn")`, or above the origin in a place with no playground |
| `CarService` | `Respawn` | `(player: Player) -> CFrame?` | Moves that player's car to `SpawnCFrame()`, records it as where the server expects the car, and tells the client over `CarRespawn`. `nil` if refused (no car, cooldown, rate limit). The only thing that moves a car after it spawns |
| `CarService` | `DebugState` | `() -> { cars: { { userId, name, position, expected: Vector3?, dropped: number } }, carCount, spawn: Vector3, droppedStates: number, respawns: number, respawnsRefused: number, inFlightKept: number, charactersOff: boolean, physicsOffenders: { string } }` | The cars as the server sees them, with where it expects each one and how many of its packets it has dropped. `DebugRespawn(userId?)` sits beside it, Studio only |
| `DriftController` | `DebugDrive` | `(inputs: { { t: number, steer: number, handbrake: boolean? } }, seconds: number, opts: { fps: number?, sample: number?, start: CFrame?, velocity: Vector3?, live: boolean? }?) -> ({ Vector3 }, Summary)` | Runs the model with no player and returns the path, for the determinism test, with a summary beside it: `entrySpeed` and `exitSpeed` (read off the car passing `MinSlipAngleForDrift`, not off an input — there is no drift input), `driftSeconds`, `peakSlipDeg`, `peakYawRate`, `peakGripAccel`, `headingChangeDeg`. `velocity` starts the car already moving. The score task adds `score` and `peakMultiplier` |
| `DriftController` | `DebugState` | `() -> { position: Vector3, headingDeg: number, speed: number, velocity: Vector3, forwardSpeed: number, lateralSpeed: number, verticalSpeed: number, yawRate: number, slipDeg: number, steer: number, throttle: number, gripAccel: number, braking: boolean, drifting: boolean, surfaceGrip: number, surfaceScore: number, wheelsDown: { boolean }, rearDown: boolean, grounded: boolean, airborne: boolean, wallHit: boolean, ... }` | The model's full state, for tests and agent playtests. Angles are degrees and named `*Deg`. `yawRate` **is** the finger times `MaxSteeringSpeed`, in rad/s, positive turning left; `slipDeg` is signed, positive when the car is travelling out to its left; `gripAccel` is the lateral pull in studs/s² and `braking` says it is pointing against the travel (past 90° of slip); `wheelsDown` is FL, FR, RL, RR. The model names no angle for the car to go to and has no drift input, mode or threshold (`features/drift-model.md`). Also `drawnGap: number` and `rigParts: number`. **`drawnGap`** is the studs between the car actually DRAWN and where the simulation has it **at this frame's moment** — the last step carried across `Sim`'s accumulator, not the last step itself (T-025). `-1` when nothing is drawn. It reads near zero on a healthy car at any speed; measured against the last *step* instead it would read zero by construction and hide the varying 1.49-stud lag that was the judder. **`rigParts`** is how many of the car's parts the controller can write through; 5 is a whole car. **Read both on the CLIENT datamodel.** The client writes its own car's CFrame locally and those writes never replicate, so the server's copy of the car sits at its spawn by design — it looks exactly like this bug and is not it |
| `DriftController` | `DrawnGap` / `DebugRig` | `() -> number` / `() -> { car, carInWorld, live, parts, wheels, hasBody, attempts, firstParts, liveAfter, drawnGap }` | Studio only. `DrawnGap()` is the one-call version of the check above. `DebugRig()` opens up the rig the controller draws through: `firstParts = 0` names the race every car is born with — a Model replicates before its parts do — and `liveAfter` is how long it took to catch them |
| `DriftController` | `DebugReset` / `DebugTeleport` | `() -> DebugState` / `(cf: CFrame) -> DebugState?` | Studio only. `DebugReset()` asks the server for a respawn and waits for the answer — it takes no CFrame, because where a car goes is not the client's to say. `DebugTeleport(cf)` moves the car **without** asking, which is what a cheat looks like: every `CarState` after it is dropped by the server |
| `CarInputController` | `Get` | `() -> { steer: number, handbrake: boolean }` | The one number the model wants. `steer` is the rate of turn as a share of `MaxSteeringSpeed`, **before** `InvertSteering`, which the model applies |
| `CarInputController` | `DebugSetInput` / `DebugClearInput` | `(steer: number?, handbrake: boolean?) -> input` / `() -> boolean` | Studio only. No `throttle` argument: the throttle is not an input, the model eases it in |
| `CarInputController` | `DebugDrag` | `(offsetPx: number?, originPx: number?) -> dragState` | Studio only: act out the real gesture rather than bypassing it. Origin defaults to the screen's middle; `nil` lifts the finger |
| `CarInputController` | `DebugTravelPx` | `(sensitivity: number?) -> number` | Studio only: a full finger in pixels, optionally at another sensitivity |
| `CarInputController` | `DebugSettings` | `(mode: string?, sensitivity: number?) -> dragState` | Studio only: stand in for the settings screen. `nil` goes back to Config |
| `Shared/CarModel` | `physicsOffenders` | `(model: Instance) -> { string }` | Everything in a car that would hand it to Roblox physics. Empty is the rule, and `DriftTests` asserts it |

## Place settings

> Settings made in Studio, not in git, and set the same way in every place: the Main place, every lane, and the published game (docs/workflow/LANES.md "Add a lane").

- `Workspace.StreamingEnabled`: **off** (`ARCHITECTURE.md` "World and streaming"): the playground is small, and streaming surfaces in under a fast car would be felt as the ground failing a ray.
