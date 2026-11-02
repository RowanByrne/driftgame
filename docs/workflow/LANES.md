# Lanes

A **lane** is a worker's own copy of the game: a git worktree of this repo, its own Studio place, and its own Lync port. Each worker in a round gets one lane (CONDUCTOR.md), so workers build and playtest at the same time without touching each other's files or places.

## Layout

| Place | Checkout | Lync port |
|---|---|---|
| `places\<CODE>-Main.rbxl` | `repo\`, always on `main` | base |
| `places\<CODE>-LaneN.rbxl` | `lanes\laneN\`, a git worktree | base + N |

The port base is in `PROJECT.md` and in `default.project.json`.

- **Each place finds its own Lync server** through its `workspace.__lync_port` attribute.
- **Idle lanes sit on a detached `origin/main`**, so every idle place shows the merged game. A worker switches its lane to its `agent/<task-slug>` branch; refresh puts it back (CONDUCTOR.md "Refresh").
- **Workers work only in their lane.** `repo\` belongs to the conductor.
- **Lane links use relative paths**, so lanes survive the project folder moving or its drive changing letter. If git ever reports a lane missing after a move, run `git worktree repair` from `repo\`.
- **`list_roblox_studios` shows only the places open on this PC.** Match a lane to its place by name.

## How many lanes

A lane is created once per game, but opened per PC. A lane that exists costs only disk space (a checkout and a place file); an open lane costs a Studio instance's memory and CPU. So a game has as many lanes as its strongest PC can run, and each PC opens only as many as it can handle.

- **Created:** `lane1` to `laneN`, where N is what the strongest PC that works on the game opens. The user picks N; record it in `PROJECT.md` ("Lanes").
- **Open on this PC:** `lane1` to `laneK` only, where K is this PC's row in `PROJECT.md` "Workstations" (match `$env:COMPUTERNAME`). Always the lowest numbers, so a PC opens the same places every time. `tools\serve-all.bat` serves only those, and the conductor assigns only those.
- **A PC with no row:** before opening lanes, suggest a number, or let the user name one straight away:
  1. Read the PC's total memory and CPU cores.
  2. Measure one lane: with the Main place and one lane place open, start a playtest in the lane and read that Studio instance's memory use (Task Manager, or `Get-Process RobloxStudioBeta` with its window title).
  3. Suggest as many lanes as fit in memory, minus 2 to leave room for other apps, and show the numbers behind it.
  4. The user picks K. Add the row to `PROJECT.md`, commit and push.
- **Lower K first** when a PC struggles, and re-measure when the game gets heavier (a bigger world, more art).

## Lync

- **Starting servers:** `tools\serve-all.bat` starts Lync for the Main place and every lane this PC opens ("How many lanes"), each in its own window; `tools\serve-all.bat dry` lists what it would start. `tools\serve.bat` serves just the checkout it's in. In a lane it reads `.lane-port` and serves a generated `lane.project.json` (both gitignored).
- **Finding Lync:** `serve.bat` looks in the RoDev folder first (`RoDev\_tools\lync\lync.exe`), then on PATH, so every game in a RoDev folder shares one copy (WORKSTATION.md). Lync's Studio plugin installs itself on the first serve; restart Studio after.
- **The user starts Lync.** A server started from an agent's shell dies with that shell. If the conductor must restart one, start it detached:
  `Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = 'cmd.exe /K "<checkout>\tools\serve.bat"' }`
  After a restart, Studio's Lync plugin may wait on **Resume** until the user clicks it.

## Add a lane

1. From `repo\`: `powershell -ExecutionPolicy Bypass -File tools\add-lane.ps1 N`. It creates `..\lanes\laneN` from `origin/main` with relative paths, writes its `.lane-port`, and prints the next steps with this lane's port and place name.
2. Make the place: copy `places\<CODE>-Main.rbxl` to `places\<CODE>-LaneN.rbxl` and open it in Studio.
3. In its command bar, set `workspace:SetAttribute("__lync_port", <base + N>)` and the worker test profile (TESTING.md). Check the place settings in `CONTRACTS.md` "Place settings" are right. Save.
4. Add the lane to `PROJECT.md`, start its Lync server, and probe it.

## Probe a lane

Before assigning a lane, prove it syncs: write `src/Workspace/LaneProbe.luau` in the lane, check `workspace.LaneProbe` appears in that place's Edit datamodel, then delete the file. If it doesn't appear, fix Lync first. Never work around a broken sync by pushing code into the place with `execute_luau`.

## Hand-built content

Place files aren't in git, so anything built by hand in Studio (parts, models, UI) lives only in a place file. Lync leaves it alone as long as no file in `src\` has the same name in the same folder (CODING.md "Source and sync"). Build it in the Main place only. After it changes, re-copy `<CODE>-Main.rbxl` over each idle lane's place and set that lane's `__lync_port` and test profile again (steps 2 and 3 above). Take a copy in `backups\` before risky edits.

## Remove a lane

When the lane is idle: `git worktree remove ..\lanes\laneN` from `repo\`, then update `PROJECT.md`. Leave the place file unless the user asks to delete it.
