# Coding

How code is laid out and written in every game. This game's actual modules and APIs are in `docs/game/ARCHITECTURE.md`; what other code relies on is in `CONTRACTS.md` and `EVENT-CATALOG.md`.

## Source and sync

- Code lives in `src/`; `default.project.json` maps each folder to a Studio service, and Lync syncs it into the place.
- `.luau` files are ModuleScripts unless the first line is `--@script:server`, `--@script:client` or `--@localscript`. Rojo's `.server.luau` and `.client.luau` names don't work in Lync: such a file stays a ModuleScript. Lync maps `init.luau` folders like Rojo.
- **Other files Lync syncs:** `.json`, `.yaml` and `.toml` become ModuleScripts returning their data, `.txt` a StringValue, `.csv` a LocalizationTable, `.rbxm`/`.rbxmx` models, `.model.json` a JSON model, and `.meta.json` sets properties. Anything else is skipped.
- **What Lync leaves alone:** instances in a synced folder that have no file of their own stay as they are; a file replaces only the instance with its name. A folder empties itself on sync only when its project node sets `"$clearOnSync": true`.
- Code changes go in files only. Edits made in Studio aren't saved to git, and code is never pushed into a place with `execute_luau`.

## Layout

```
src/ReplicatedStorage/Shared/        shared modules: Config, Net, Signal, data tables, feature shared modules
src/ServerScriptService/Main.luau    server loader
src/ServerScriptService/Services/    one module per service, auto-loaded
src/ServerScriptService/<Feature>/   helper modules a service owns
src/StarterPlayerScripts/Client.luau client loader
src/StarterPlayerScripts/Controllers/ one module per controller, auto-loaded
src/StarterPlayerScripts/<Feature>/  helper modules a controller owns, its screens' views and their fixtures
src/StarterPlayerScripts/UI/         UI helpers: Theme, Create, Layers, Artwork; Dev/ for Studio-only UI tools
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
| UI kit | `UI/Theme` (colours, fonts, panels, labels, buttons) and `UI/Create`; programmer-art UI is built on these (WORKFLOW.md). `UI/Layers` for every ScreenGui's `DisplayOrder`. `UI/Artwork` puts generated art on frames, from the UI phase on (UI.md) |
| UI preview | Studio only: opens any screen with any of its fixtures, with the layout drag mode (UI.md "Programmer art", TESTING.md "Checking UI") |
| Notifications | One toast and banner API, callable from client and server |
| Analytics | The analytics module and standard events (ANALYTICS.md) |
| Live config | The config wrapper: reads Roblox configs, with a default in code for every key (CONFIGS.md) |
| Debug bridges | Studio-only `DebugBridge` on the server (`ServerStorage`) and client (`PlayerScripts`), so tests reach live services and controllers (TESTING.md) |
| Studio test kit | Quiet agent playtests, the test profile, photo mode (TESTING.md) |
| Admin console | Cmdr, vendored. Everyone in Studio; on live servers only the owner and the admins in `Config`. Rate-limited |

### The kit's fixed names

`src/` starts empty, and each game builds the kit. These names and signatures are the same in every game, because TESTING.md, the worker briefs and the tests call them:

| Piece | Where | API |
|---|---|---|
| Server loader | `ServerScriptService/Main.luau` | Loads `Services/`; in Studio, creates `ServerStorage.DebugBridge` |
| Client loader | `StarterPlayerScripts/Client.luau` | Loads `Controllers/`; in Studio, creates `PlayerScripts.DebugBridge` |
| `DebugBridge` | A `BindableFunction`, created only when `RunService:IsStudio()` | `Invoke(name, member, ...)`. `name` is a loaded service or controller, or `Debug<Name>Tests` for `ServerScriptService/Tests/<Name>Tests`. A function member is called as a method and its results returned; any other member returns its value. An unknown name or member errors with what exists |
| `DataService` | `ServerScriptService/Services/DataService.luau` | `WaitForProfile(player)` returns the profile's data, `Get(player, key)`, `Update(player, key, fn)` (`fn` gets the old value and returns the new one), `ProfileLoaded` and `ProfileReleased` signals. In memory mode it uses a fake store, which tests can swap in |
| Test profiles | `ServerScriptService/TestProfiles.luau` | A table of `name = function(data)` that edits a brand-new profile's data. DataService applies the one `workspace.__test_profile` names, in memory mode only |
| Quiet playtests | `ReplicatedFirst/QuietPlay.luau` | `QuietPlay.isQuiet()`. `Sounds` and music check it before playing |
| Photo mode | `StarterPlayerScripts/Controllers/PhotoController.luau` | `Frame(target, opts)` returns the target's predicted screen bounds; `Restore()` |
| Automated tests | `ServerScriptService/Tests/<Name>Tests.luau` | `run(...)` returns `{ passed, checks }`, each check `{ name, ok, detail }` |
| UI layers | `StarterPlayerScripts/UI/Layers.luau` | Named `DisplayOrder` values, in bands: input catchers 0–9, HUD 10–29, temporary cards 30–33, menus, dialog backdrops and dialogs 34–39, tooltips, rewards and notices 40–59, cutscenes 60–89, debug tools and the loading screen 1000 and up |
| Screen views | `StarterPlayerScripts/<Feature>/<Screen>View.luau`, with `<Screen>View.fixtures.luau` beside it | `new(parent)` builds the screen and returns a view: `setData(snapshot)` redraws it from a plain table, `show()`, `hide()`, `describe()` (its pieces' rects, states and art variants, for the UI checks), `setLayoutOffset(name, offset)` (for the drag mode) and `destroy()`. Its buttons fire `view.ActionRequested` with `(action, ...)`; the view never acts on them. The fixtures module is a table of `name = snapshot`, marked as sample data |
| UI artwork | `StarterPlayerScripts/UI/Artwork.luau` | `apply(frame, role)` puts the role's closest variant from the asset registry under `frame`, below its content and taking no input, and refits it on every resize: stretched within the 20% limit, fitted beyond it. It sets the frame's `ArtworkRole`, `ArtworkVariant`, `ArtworkDistortion` and `ArtworkWithinLimit` attributes, shows a plain fill until the image has loaded, replaces only its own art when applied again, and disconnects when the frame goes. `heightFor(role, width, minHeight)` returns the smallest height at which a variant fits within the limit |
| UI preview | `StarterPlayerScripts/Controllers/UIPreviewController.luau`, doing nothing outside Studio | Finds every `<Screen>View` with fixtures beside it. Its panel opens from the admin console's `uipreview` command: pick a screen and fixture; switch Move, Snap and the drag level (widgets or clusters); Reset and Export. Through the debug bridge: `Open(screen, fixture)`, `Close()`, `Describe()`, `Drag(on, level)` (`"items"` or `"groups"`), `Snap(on)`, `ExportLayout()` and `ResetLayout()` |
| Layout drag | `StarterPlayerScripts/UI/Dev/LayoutDrag.luau`, copied unchanged from `tools/ui/LayoutDrag.luau` | Its header has the API. A view tags each widget's top frame `LayoutItem = "<name>"`, a cluster's pieces `LayoutGroup = "<name>"`, and fixed areas, like Roblox's chat window, `LayoutReserve = "<name>"`; it adds each offset it's given to its own layout |

DataService can wrap a profile library, such as ProfileStore (loleris, 2024, the successor to his ProfileService), as long as it keeps this API and the saving rules below. Record the choice in `ARCHITECTURE.md` "Vendored libraries".

## Server rules

- **The server decides.** The client asks; the server checks and applies. Never trust a value the client sends: positions, prices, results, timings.
- **Every client-to-server handler** type-checks every argument, rate-limits per player, and survives junk. Fuzz new handlers with garbage calls.
- **Limits and cooldowns are keyed by UserId**, so rejoining doesn't reset them.
- **Purchases:** `ProcessReceipt` grants each receipt exactly once, across retries and servers, and fails closed: if the grant can't be saved, return `NotProcessedYet`. Checkout stays closed where nothing can be saved (memory mode, unpublished places).
- **Prices on screen** come from `MarketplaceService`, regional for each player, never from a number in code (REVENUE.md "Passes and developer products").

## Saving

- **Session lock.** Loading a profile takes a lock (server job id plus a per-load id). Every write checks the lock is still ours. A dead server's lock expires after a few autosave intervals, so a crash costs a rejoin, not a lockout.
- **One write at a time per user.** Saves, purchases and their queued work are serialized per UserId, and a rejoin waits for the previous session's final save.
- **Retry, then fail loudly.** Writes retry with backoff. Leaving and shutdown (`BindToClose`) share one release path that ends in the final save.
- **Memory mode** (nothing saved) only in Studio or when `game.PlaceId == 0`. A live server never falls back to it: if it can't load, it retries, then kicks with a message to rejoin, so it never pretends to have saved.
- **Schema.** Profiles carry a version. A schema change ships with a migration tested on saved data from the previous version, and a line in `CONTRACTS.md`.

### Data store limits

Roblox changed these in 2026; trust this over memory. Checked 2026-11-02 against [Roblox's limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits) and the [July 2026 change](https://devforum.roblox.com/t/unifying-data-stores-open-cloud-and-game-apis-and-increasing-storage-limits/4739240).

- **Storage per experience:** 500 MB plus 1 MB for every user who has ever joined. Live since 29 July 2026 (it was 100 MB plus 1 MB per user).
  - **What counts:** the compressed size of each key's latest version. Older versions and deleted keys don't count; a data store deleted through Open Cloud still counts for 30 days. Roblox compresses data itself, so don't compress it in code.
  - **Where to see it:** Creator Dashboard → the game → Configurations → Data stores manager → Summary shows the total size against the limit. Notifications at 60, 80, 90 and 100% of the limit are on by default.
  - **Over the limit:** the Summary starts showing estimated monthly costs. Extra storage is $0.12 per GB a month through Roblox Extended Services, which needs an owner who is 18 or older and ID-verified. Whether writes are blocked over the limit isn't documented, so stay well under it, and tell the user at the 60% notification.
- **Sizes:** a value up to 4,194,304 characters, as `JSONEncode` measures it (error 105, `ValueTooLarge`). Data store names, keys and scopes up to 50 characters each. Metadata up to 300 characters in all.
- **Requests a minute, for the whole experience,** in-game and Open Cloud together: reads 300 + 40 × concurrent players, writes 300 + 20 ×, lists 300 + 2 ×, removes 300 + 40 ×. `UpdateAsync` counts as a read and a write.
- **Requests a minute, per server,** on top: standard stores read 60 + 40 × players in that server, write 60 + 40 ×, list 5 + 2 ×, remove 60 + 40 ×; ordered stores write and remove 30 + 5 ×. Check what's left with `DataStoreService:GetRequestBudgetForRequestType`.
- **Per key:** 25 MB of reads and 4 MB of writes a minute. Requests beyond a full queue of 30 are dropped (errors 301 to 306).
- **So:** one key per player profile, saved on autosave (every few minutes), on leaving and on shutdown, never on every action. Anything that grows without end (logs, histories, other players' records) gets a cap or its own store.

## Conventions

- **Names:** `<Name>Service`, `<Name>Controller`, remotes `<Feature><Action>`. Studio-only attributes start with `__` (`__lync_port`, `__test_profile`, `__agent_play`). Every tag and attribute other code reads is listed in `CONTRACTS.md`.
- **Input:** every action works on keyboard and mouse, touch, and gamepad from its first version, and is listed in `docs/game/SETTINGS.md` "Controls". Bind actions with the Input Action System (`InputContext`, `InputAction`, `InputBinding`; released June 2026), not `ContextActionService`, which Roblox plans to deprecate. Input hints follow `UserInputService.PreferredInput` (UI.md "Player settings").
- **Third-party code** is vendored into `src/` (`Packages/` is gitignored). Record each library's version, source (its GitHub repo) and local patches in `ARCHITECTURE.md` "Vendored libraries": Rocco's Connections reads that table and shows when a newer release is out.
- **Contracts move first.** A change to `CONTRACTS.md`, `EVENT-CATALOG.md` or `Shared/` that other code builds on goes in as its own small commit (CONDUCTOR.md "Main").
- **The world:** decide early whether it's built by code at runtime or by hand in Studio, and record the choice in `ARCHITECTURE.md`. Gameplay code never holds world positions: it reads named spots (WORLD-BUILDING.md).
