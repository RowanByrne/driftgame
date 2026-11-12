# Testing

How agents test in Studio. The rule behind all of it: **prove it by measuring**, then leave the final look to the user.

## Studio tools

- **Use only your place.** Pass only the `studio_id` whose name matches your place (`list_roblox_studios`): `<CODE>-LaneN`, a worker's lane, or the lane the conductor is checking in (CONDUCTOR.md "Checking in a lane"). Never touch the hands-off places in `PROJECT.md`. If your place isn't open, say so and work without Studio.
- **The Main place (`<CODE>-Main`) is the user's.** They playtest there, so never start or stop a playtest in it or change it, unless they ask: their pre-publish check (RELEASING.md), or hand-built content (LANES.md). Even then, check first that they're not in a playtest (`get_studio_state`). Reading its console or state when they point you at something there is fine. On a PC with no lanes, Main is the only place: CONDUCTOR.md "Checking in a lane" says how.
- **Studio is for testing and inspecting:** playtests, console output, the instance tree, screenshots. Code goes in files (CODING.md).
- **Inspect a running playtest** with `execute_luau` on the `Server` or `Client` datamodel. If the world is built by code, the Edit datamodel looks nearly empty: playtest to see the game.
- **No DataStores in unpublished places.** DataService runs in memory mode there; that's expected, not an error.

## Every playtest

1. **Check Studio has your changes** before a playtest whose results you'll report. A playtest started before Lync synced your last edit tests the old code, and its numbers and screenshots prove nothing. `powershell -ExecutionPolicy Bypass -File tools\ui\source-gate.ps1 -Root . -Out "$env:TEMP\SourceGate-$(Split-Path -Leaf (Get-Location)).luau"` hashes the files changed since the last commit (or the ones you name with `-Files`) and writes a check; send that file as `execute_luau` code in the Edit datamodel. `ok = true` means every one of them in Studio matches the disk and compiles. Say in your report what it checked. **The file name carries the checkout's folder** (`SourceGate-lane2.luau`) on purpose: lanes run at the same time, and a fixed name means two workers overwrite each other's check and one of them gates the wrong lane.
2. **Mark it quiet.** In the Edit datamodel run `workspace:SetAttribute("__agent_play", DateTime.now().UnixTimestamp)`, then start the playtest straight away. A playtest that starts within 60 s of the marker is silent; any other (the user pressing Play) has sound. Forget it and the user hears your test.
3. **Exercise the change.**
4. **Read the console** (`get_console_output`) for errors and warnings.
5. **Stop the playtest.** Never leave one running.

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

## Checking UI

UI is proved by measuring at real screen sizes, then a few screenshots against the approved reference (UI.md). The tools are in `tools/ui/` (its README has each one's usage); each Luau tool is sent whole as `execute_luau` code, with its `CONFIG` filled in.

1. **Real screen sizes.** `tools/ui/SimulatorSweep.luau` drives Studio's device simulator one step per call: `plan` matches each screen size in UI.md to a simulator device, `set` switches to one at actual resolution and returns the viewport it really got, and `stop` puts Studio back. Run it in the Edit datamodel, or in Client during a playtest. Always run `stop`, even after an error. Record the measured viewport, not the device's advertised one.
2. **Measure each size** with `tools/ui/MeasureUI.luau` in the Client datamodel: text fits, essential text at 16 effective px or more, targets of 44 px or more, images loaded, art within the 20% limit (`ArtworkWithinLimit`), captions above their art, no overlaps between the pieces you list (touch-control zones included on touch), and everything inside the safe area. A label marked `TextAux = true` may go down to 14 px; a button marked `TargetExempt = "<reason>"` skips the target check, and every exemption needs its reason. Keep each run's result with its screen size.
3. **Every state, from the fixtures.** Open each screen through the UI preview (CODING.md "The kit's fixed names") with each of its fixtures, stress ones included: `PlayerScripts.DebugBridge:Invoke("UIPreviewController", "Open", "<Screen>", "<fixture>")`, then `"Describe"` for its rects, states and art variants.
4. **Lifecycle:** open and close it ten times quickly (exactly one of everything afterwards, no leftover input blockers), resize and rotate it while open, respawn, and hide it for a cutscene if the game does.
5. **Every input:** gamepad focus order and where focus returns after a close, touch with no hover, and the keyboard's close and back keys. When Studio can't send a key (Escape, ButtonB), call the same handler through the debug bridge and say it was simulated.
6. **Screenshots last,** at actual display scale over bright, dark and busy scenes, after animations settle, within the limit in "Prove it by measuring". Then put the simulator back to its default device.

**If a number misses by more than 20%,** look for a coordinate mix-up or stale code before reporting it ("Gotchas").

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
- **A call that blocks drops the connection.** An `execute_luau` that doesn't return within a few seconds fails with "Target is not reachable", and the next call works again — so a test suite that takes a minute never reports. Run the slow thing in a `task.spawn` that writes its result into a `StringValue`, return straight away, then poll that value with short calls.
- **UI coordinates:**
  - A ScreenGui with `IgnoreGuiInset` reports `AbsolutePosition` 58 px higher than one without, the height of Roblox's top bar. Compare positions only within one coordinate space.
  - `user_mouse_input` takes coordinates without the top bar: subtract 58 from a screen y measured in an `IgnoreGuiInset` gui.
  - Roblox's chat window (`ChatWindowConfiguration.AbsolutePosition`) also reports without the top bar, and its size leaves out the input bar, about 48 px more below it.
- **UI measurements:**
  - `TextBounds` already includes every ancestor's `UIScale`; don't multiply it in again.
  - `TextFits` reads false on a hidden label, and can read false on an `AutomaticSize` label whose text shows whole. Check only visible labels, and size a label that hugs its text from a measured width plus 2 px instead of `AutomaticSize`.
  - An image off screen or not parented can report `IsLoaded = false` forever: put it on screen before checking.
  - Preload with instances (`ImageLabel`, `Sound`), not bare id strings, which report `Failure` for good ids.
  - A client viewport of 1 × 1 means the renderer stalled: restart the playtest before trusting any pixel.
- **The Lync plugin reads `workspace.__lync_port` only when the place opens.** Setting it in an open place does nothing until the user types the port into the Lync panel and presses Sync.
- **Captures:**
  - `BillboardGui`s don't show.
  - A capture can time out during a cinematic.
  - A capture during a playtest leaves the camera `Scriptable`.
  - `camera_position` jumps the camera for one frame, so distant terrain is still at coarse detail. Hold the camera on the view for about 5 s first.
