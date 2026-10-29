# Coding

How code is laid out and written in every game. This game's actual modules and APIs are in `docs/game/ARCHITECTURE.md`; what other code relies on is in `CONTRACTS.md` and `EVENT-CATALOG.md`.

## Source and sync

- Code lives in `src/`; `default.project.json` maps each folder to a Studio service, and Lync syncs it into the place.
- `.luau` files are ModuleScripts unless the first line is `--@script:server`, `--@script:client` or `--@localscript`. Lync maps `init.luau` folders like Rojo.
- Code changes go in files only. Edits made in Studio aren't saved to git, and code is never pushed into a place with `execute_luau`.

## Layout

```
src/ReplicatedStorage/Shared/        shared modules: Config, Net, Signal, data tables, feature shared modules
src/ServerScriptService/Main.luau    server loader
src/ServerScriptService/Services/    one module per service, auto-loaded
src/ServerScriptService/<Feature>/   helper modules a service owns
src/StarterPlayerScripts/Client.luau client loader
src/StarterPlayerScripts/Controllers/ one module per controller, auto-loaded
src/StarterPlayerScripts/<Feature>/  helper modules a controller owns
src/StarterPlayerScripts/UI/         UI helpers: Theme, Create
```

- **Loaders** require every direct ModuleScript child of `Services/` (server) or `Controllers/` (client), call `Init()` on all of them (highest `Priority` first; no yielding; create remotes here), then `Start()` on each in its own thread.
- **Services and controllers require each other directly.** Helpers go in a feature folder, not in `Services/` or `Controllers/`, which hold only loadable modules.
- **Split big controllers.** When one grows past a few hundred lines, turn it into a folder: one shared state module, one module per phase or job, and the controller keeps only its lifecycle and public API.

## Foundation kit

Built in the Foundation phase (WORKFLOW.md), before any gameplay. Record each piece's API in `ARCHITECTURE.md`.

| Piece | What it does |
|---|---|
| Loaders | The Services and Controllers loaders above |
| `Net` | Remotes registry: `Net.event(name)`, `Net.unreliable(name)`, `Net.func(name)`. The server creates them in `Init`, the client waits for them. Flat names, `<Feature><Action>`; every remote listed in `CONTRACTS.md` |
| `Signal` | Events between modules: `new`, `Connect`, `Once`, `Fire`, `Wait` |
| `Config` | Every tuning number, in config modules (`Shared/Config`, per-feature tuning modules), never in the logic |
| `DataService` | Player profiles with the saving rules below |
| `PlayerData` | The client's read-only mirror of its profile: `Get`, `Observe(key, fn)`, `Changed`, `WaitUntilReady` |
| `Sounds` | Sounds played by name; ids filled in one registry, and an empty id is a silent no-op |
| UI kit | `UI/Theme` (colours, fonts, panels, labels, buttons) and `UI/Create`; programmer-art UI is built on these (WORKFLOW.md) |
| Notifications | One toast and banner API, callable from client and server |
| Analytics | The analytics module and standard events (ANALYTICS.md) |
| Debug bridges | Studio-only `DebugBridge` on the server (`ServerStorage`) and client (`PlayerScripts`), so tests reach live services and controllers (TESTING.md) |
| Studio test kit | Quiet agent playtests, the test profile, photo mode (TESTING.md) |
| Admin console | Cmdr, vendored. Everyone in Studio; on live servers only the owner and the admins in `Config`. Rate-limited |

## Server rules

- **The server decides.** The client asks; the server checks and applies. Never trust a value the client sends: positions, prices, results, timings.
- **Every client-to-server handler** type-checks every argument, rate-limits per player, and survives junk. Fuzz new handlers with garbage calls.
- **Limits and cooldowns are keyed by UserId**, so rejoining doesn't reset them.
- **Purchases:** `ProcessReceipt` grants each receipt exactly once, across retries and servers, and fails closed: if the grant can't be saved, return `NotProcessedYet`. Checkout stays closed where nothing can be saved (memory mode, unpublished places).

## Saving

- **Session lock.** Loading a profile takes a lock (server job id plus a per-load id). Every write checks the lock is still ours. A dead server's lock expires after a few autosave intervals, so a crash costs a rejoin, not a lockout.
- **One write at a time per user.** Saves, purchases and their queued work are serialized per UserId, and a rejoin waits for the previous session's final save.
- **Retry, then fail loudly.** Writes retry with backoff. Leaving and shutdown (`BindToClose`) share one release path that ends in the final save.
- **Memory mode** (nothing saved) only in Studio or when `game.PlaceId == 0`. A live server never falls back to it: if it can't load, it retries, then kicks with a message to rejoin, so it never pretends to have saved.
- **Schema.** Profiles carry a version. A schema change ships with a migration tested on saved data from the previous version, and a line in `CONTRACTS.md`.

## Conventions

- **Names:** `<Name>Service`, `<Name>Controller`, remotes `<Feature><Action>`. Studio-only attributes start with `__` (`__lync_port`, `__test_profile`, `__agent_play`). Every tag and attribute other code reads is listed in `CONTRACTS.md`.
- **Input:** every action works on keyboard and mouse, touch, and gamepad from its first version.
- **Third-party code** is vendored into `src/` (`Packages/` is gitignored). Record each library's version, source and local patches in `ARCHITECTURE.md`.
- **Contracts move first.** A change to `CONTRACTS.md`, `EVENT-CATALOG.md` or `Shared/` that other code builds on goes in as its own small commit (CONDUCTOR.md "Main").
- **The world:** decide early whether it's built by code at runtime or by hand in Studio (LANES.md "Hand-built content"), and record the choice in `ARCHITECTURE.md`.
