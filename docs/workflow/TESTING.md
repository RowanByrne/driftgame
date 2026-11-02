# Testing

How agents test in Studio. The rule behind all of it: **prove it by measuring**, then leave the final look to the user.

## Studio tools

- **Use only your place.** Pass only the `studio_id` whose name matches your place (`list_roblox_studios`): `<CODE>-Main` for the conductor, `<CODE>-LaneN` for a worker. Never touch the hands-off places in `PROJECT.md`. If your place isn't open, say so and work without Studio.
- **Studio is for testing and inspecting:** playtests, console output, the instance tree, screenshots. Code goes in files (CODING.md).
- **Inspect a running playtest** with `execute_luau` on the `Server` or `Client` datamodel. If the world is built by code, the Edit datamodel looks nearly empty: playtest to see the game.
- **No DataStores in unpublished places.** DataService runs in memory mode there; that's expected, not an error.

## Every playtest

1. **Mark it quiet.** In the Edit datamodel run `workspace:SetAttribute("__agent_play", DateTime.now().UnixTimestamp)`, then start the playtest straight away. A playtest that starts within 60 s of the marker is silent; any other (the user pressing Play) has sound. Forget it and the user hears your test.
2. **Exercise the change.**
3. **Read the console** (`get_console_output`) for errors and warnings.
4. **Stop the playtest.** Never leave one running.

## Prove it by measuring

- **Use numbers:** positions and distances relative to a root part, GUI `AbsolutePosition` / `AbsoluteSize`, `Camera:WorldToViewportPoint` projections, instance counts, `DebugState()` dumps, logs.
- **Screenshot only to answer "does this look right?"** At most 3 per task, at most one retake each. Then report what you measured and tell the user where to look.
- **Report how you tested:** what you ran, what you measured, what you couldn't check.

## Reaching live game state

`execute_luau` gets its own copy of every module, so `require(...)` there can't see the running game. Use the Studio-only debug bridges (CODING.md "Foundation kit"):

- Server datamodel: `game.ServerStorage.DebugBridge:Invoke("<Service>", "<member>", ...)`
- Client datamodel: `game.Players.LocalPlayer.PlayerScripts.DebugBridge:Invoke("<Controller>", "<member>", ...)`

A function member is called as a method; anything else returns its value. Give your service or controller `Debug*` methods and a `DebugState()` whenever that makes it easier to test, and list them in `ARCHITECTURE.md`.

## Studio test kit

Built in the Foundation phase (CODING.md). It only ever acts in Studio; published servers and clients are unaffected.

- **Quiet playtests.** One module in `ReplicatedFirst` decides: silent when the client starts within 60 s of `__agent_play`, otherwise normal sound. `workspace.__studio_audio = true` forces sound in an agent playtest, for deliberate audio tests; clear it afterwards.
- **Test profile.** `workspace.__test_profile = "<name>"` gives a brand-new profile a named starting state in memory mode, such as past onboarding, so a playtest is in normal play about a second after joining. Worker places keep it set. Clear it only to test the real first join, and set it back after. The profiles a game offers are listed in `ARCHITECTURE.md`.
- **Photo mode.** For a screenshot, call `DebugBridge:Invoke("PhotoController", "Frame", target, opts)` on the Client datamodel. It hides the UI, holds the camera on the target, and returns the target's predicted screen bounds. Return from `execute_luau`, call `screen_capture` with no camera parameters, then `Restore()`.

## Automated tests

- **Where:** `src/ServerScriptService/Tests/<Name>Tests.luau`. Each module asserts it's running in Studio and has a `run(...)` that returns `{ passed, checks }`.
- **How to run:** call it through the debug bridge (`Debug<Name>Tests`), or `require(...).run()` directly when the code it tests is pure.
- **Deterministic:** fixed inputs and seeded random numbers. Data tests use DataService's fake store and stand-in users, never a real player's save.
- **What gets one:** saving, purchases, odds and anything a player could exploit. Rerun them after changing that code, and say so in your report.

## Gotchas

- **A running playtest doesn't get file changes.** Lync syncs the Edit datamodel; its Playtest Sync toggle (off by default) reaches only the server side. Stop the playtest and start it again after a change.
- **Stale modules.** `execute_luau`'s `require` cache outlives Lync edits. To check a pure module's current source, clone its folder into `ServerStorage`, require the clone, then destroy it.
- **Camera changes get reverted.** A camera-type change made while an `execute_luau` call is running is reverted. Schedule it with `task.delay` and return straight away.
- **Playtest won't start.** If `start_stop_play` hangs on "Start play hasn't finished yet", start from the Edit datamodel with `StudioTestService:ExecutePlayModeAsync` inside `task.spawn`, and return straight away.
- **Captures:**
  - `BillboardGui`s don't show.
  - A capture can time out during a cinematic.
  - A capture during a playtest leaves the camera `Scriptable`.
  - `camera_position` jumps the camera for one frame, so distant terrain is still at coarse detail. Hold the camera on the view for about 5 s first.
