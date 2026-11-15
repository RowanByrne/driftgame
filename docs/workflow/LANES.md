# Lanes

A **lane** is a place to test in: a Studio place that stays open, a git worktree of this repo that Lync serves into it, and its own Lync port. Agents don't work in lanes. Each task has a **checkout** of its own to write code in, and **borrows a lane** when it tests ("Lending a lane"). So a PC's lanes are how many things can be tested at once, not how many are being built.

## Layout

| What | Where | Studio and Lync |
|---|---|---|
| Main | `places\<CODE>-Main.rbxl`, served from `repo\`, always on `main` | Port base |
| Lane N | `places\<CODE>-LaneN.rbxl`, served from `lanes\laneN\`, a git worktree | Port base + N |
| A task's checkout | `work\<its branch, with - for />\`, a git worktree on the task's branch | None |

The port base is in `PROJECT.md` and in `default.project.json`.

- **Each place finds its own Lync server** through its `workspace.__lync_port` attribute.
- **The Main place is the user's.** They playtest there, and agents don't, unless the user asks (TESTING.md). Code is checked in a lane before it reaches `main` (CONDUCTOR.md "Checking before main").
- **A lane's checkout is Rocco's.** It sits on a detached HEAD, on whatever commit it was last lent for, and only Rocco moves it. Nobody edits files or runs git in it. A lane with a branch checked out or uncommitted changes isn't lent.
- **A checkout is its task's.** The agent on the task works only there. `repo\` belongs to the conductor.
- **Worktree links use relative paths**, so lanes and checkouts survive the project folder moving or its drive changing letter. If git ever reports one missing after a move, run `git worktree repair` from `repo\`.
- **`list_roblox_studios` shows only the places open on this PC.** Match a lane to its place by name.

## Lending a lane

Rocco lends lanes (`rocco.ps1`, run in PowerShell from `repo\` as `..\..\_tools\rocco\rocco.ps1`, or from a checkout as `..\..\..\_tools\rocco\rocco.ps1`). A lane is lent **by commit**: its checkout is switched, detached, to the commit the task's checkout is on, and Lync, which never stops, syncs the difference into the lane's place, deletions included. Uncommitted edits don't reach a lane.

| Command | What it does |
|---|---|
| `work T-012 -Branch agent/<slug>` | Makes the task's checkout, `work\agent-<slug>`, on that branch from `origin/main`, and prints its folder. `-Base feature/<name>` starts it from a feature's branch (a piece of that feature). A branch that exists is carried on |
| `borrow T-012` | A lane for the task, holding its checkout's latest commit. With every lane busy it waits in line, in the order asked. Prints the lane, its place, and what the place should hold |
| `sync T-012` | The lane it has, moved to the checkout's latest commit |
| `return T-012` | Lets the lane go |

- **Who holds a lane:** a task's agent while it tests (`borrow` to `return`), the user while a card is ready for them to try in a lane, and the conductor while it checks a merge. Rocco's sidebar shows each.
- **A loan ends by itself** when its task stops testing: sent back, paused, deleted, or merged and cleared.
- **The user's testing gives way.** When every lane is taken and an agent is waiting, Rocco takes the lane that has waited on the user longest. That card then offers **Load into a lane**, which puts it back in a free one in seconds, since Studio is already open. Rocco's Settings can keep one lane for the user's testing.
- **Check what the place holds.** `borrow` and `sync` print a script count and a fingerprint, and name a checker file to run through `execute_luau` in that place (Edit). The two must match before a playtest counts (WORKER.md "Testing in a lane"). A place that holds scripts which aren't in `src/` (built by hand, or saved into the place file) won't match: take them out, or say so.
- **Leave nothing behind.** A lane's place is the next borrower's too. What a test needs is built by code in `src/`, or removed before `return`. Never save a lane's place.
- **A branch that changes `default.project.json`** needs that lane's Lync restarted (Lync reads the project file once): say so to the conductor.
- **Only so many agents work at once:** two per lane this PC opens, or the number in Rocco's Settings. Past that, `work` says so, and the task is parked until one finishes (CONDUCTOR.md "Every agent busy").

**Why a lane is switched, and Lync never repointed:** Lync's plugin removes a script only when its file is deleted while the server is watching, and it doesn't reconnect by itself after its server stops. A `git switch` inside a lane whose Lync keeps running gives it every deletion. One case needs care, and Rocco handles it: a folder that is itself a script (it has an `init.luau`) stays behind when the folder and its init file go at once, so Rocco deletes those init files first, waits for Lync, then switches.

## How many lanes

A lane is created once per game, but opened per PC. A lane that exists costs only disk space (a checkout and a place file); an open lane costs a Studio instance's memory and CPU. So a game has as many lanes as its strongest PC can run, and each PC opens only as many as it can handle.

- **Created:** `lane1` to `laneN`, where N is what the strongest PC that works on the game opens. The user picks N; record it in `PROJECT.md` ("Lanes").
- **Open on this PC:** `lane1` to `laneK` only, where K is this PC's row in `PROJECT.md` "Workstations" (match `$env:COMPUTERNAME`). Always the lowest numbers, so a PC opens the same places every time. `tools\serve-all.bat` serves only those, and Rocco lends only those.
- **A PC with no row:** Rocco asks: in a new game's onboarding, or from Lanes in its sidebar. It suggests a number from the PC's memory and threads (about 3 GB a lane, less the Main place and 2 for other apps), records the user's pick in `PROJECT.md`, and opens them ("Open them"). Without Rocco, suggest a number, or let the user name one straight away:
  1. Read the PC's total memory and CPU cores.
  2. Measure one lane: with the Main place and one lane place open, start a playtest in the lane and read that Studio instance's memory use (Task Manager, or `Get-Process RobloxStudioBeta` with its window title).
  3. Suggest as many lanes as fit in memory, minus 2 to leave room for other apps, and show the numbers behind it.
  4. The user picks K. Add the row to `PROJECT.md`, commit and push.
- **Fewer than before.** Lanes are only for testing now, so a PC needs fewer than it has tasks in progress: two or three serve most games.
- **Lower K first** when a PC struggles, and re-measure when the game gets heavier (a bigger world, more art). Rocco's guess is a starting point: once a lane has run a playtest, measure it (step 2) and suggest a better number if it's off.

## Open them

`..\..\_tools\rocco\rocco.ps1 lanes` (from `repo\`) opens this PC's lanes in one go: it makes any lane that's missing (`tools\add-lane.ps1`), makes any missing place (`places\<CODE>-Main.rbxl` and `<CODE>-LaneN.rbxl`, a plain baseplate with its `__lync_port` already set), starts Lync (with no window) for each checkout that isn't served yet, and opens each place in Studio that isn't open. What's there already is left alone. `-Count K` records this PC's row first. Rocco runs the same thing when the user picks a number. Set the worker test profile once the game has one (TESTING.md).

## Lync

- **Starting servers:** Rocco starts Lync for the Main place and every lane this PC opens ("How many lanes") with no windows: Lanes in its sidebar, `rocco.ps1 lanes`, or Start Lync in Connections. Each server's output goes to `<Game>\rocco\lync\main.log` or `laneN.log`; Connections' Studio sync row stops them, and so does quitting Rocco. Without Rocco, `tools\serve-all.bat` starts them, each in its own window (`tools\serve-all.bat dry` lists what it would start), and `tools\serve.bat` serves just the checkout it's in. In a lane, both read `.lane-port` and serve a generated `lane.project.json` (both gitignored).
- **Finding Lync:** the RoDev folder's copy first (`RoDev\_tools\lync\lync.exe`), then PATH, so every game in a RoDev folder shares one copy (WORKSTATION.md). Lync's Studio plugin installs itself on the first serve; restart Studio after.
- **The user starts Lync.** If the conductor must restart one (it isn't serving, so the place doesn't sync), `..\..\_tools\rocco\rocco.ps1 lanes` starts whichever of this PC's servers aren't running, detached from your shell. Without Rocco, a server started from an agent's shell dies with that shell, so start it detached:
  `Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = 'cmd.exe /K "<checkout>\tools\serve.bat"' }`
  After a restart, Studio's Lync plugin may wait on **Resume** until the user clicks it.
- **A lane that goes down.** Studio sometimes goes down just after a large sync. A task that holds the lane gets its place back with `sync`: Rocco opens the place again (clearing the lock a crashed Studio leaves behind), and the agent waits for it and checks the fingerprint. Rocco also watches each lane with a task in it: when its Lync stops or its place closes in Studio, the lane turns red in its sidebar and the user is told. **Fix lanes** opens again what's missing, as `rocco.ps1 lanes` does, and tells the agent with work there (a `[message]` from Rocco), which then runs `sync` and checks the place again. A lane nothing holds that isn't open isn't lent: closing one is the user's call.
- **A lane that was down missed what changed meanwhile.** Lync only adds and overwrites when a place opens: it removes nothing. So after a lane's Lync or Studio comes back, the first `borrow` or `sync` check may find scripts left from before. Say so to the conductor: the fix is to close that place without saving and open it again from its file.

## Add a lane

By hand, without Rocco ("Open them" does all of this but the test profile):

1. From `repo\`: `powershell -ExecutionPolicy Bypass -File tools\add-lane.ps1 N`. It creates `..\lanes\laneN` from `origin/main` (or local `main` before the game has a GitHub repo) with relative paths, writes its `.lane-port`, and prints the next steps with this lane's port and place name.
2. Make the place: copy `places\<CODE>-Main.rbxl` to `places\<CODE>-LaneN.rbxl` and open it in Studio.
3. In its command bar, set `workspace:SetAttribute("__lync_port", <base + N>)` and the worker test profile (TESTING.md). Check the place settings in `CONTRACTS.md` "Place settings" are right. Save.
4. Add the lane to `PROJECT.md`, start its Lync server, and probe it.

## Probe a lane

To prove a lane syncs at all (a new lane, or one that just came back up), with nothing lent to it: write `src/Workspace/LaneProbe.luau` in the lane, check `workspace.LaneProbe` appears in that place's Edit datamodel, then delete the file and check it's gone. If it doesn't appear, fix Lync first. Never work around a broken sync by pushing code into the place with `execute_luau`. A lane that's lent is checked by its fingerprint ("Lending a lane"), which says more.

## Hand-built content

Place files aren't in git, so anything built by hand in Studio (parts, models, UI) lives only in a place file. Lync leaves it alone as long as no file in `src\` has the same name in the same folder (CODING.md "Source and sync"). Build it in the Main place only, and since Main is the user's, only when they've asked for it, and not while they're in a playtest (`get_studio_state`). After it changes, close each lane's place that nothing holds, re-copy `<CODE>-Main.rbxl` over it, set that lane's `__lync_port` and test profile again ("Add a lane" steps 2 and 3), and open it. Take a copy in `backups\` before risky edits.

## Remove a lane

When nothing holds it: `git worktree remove ..\lanes\laneN` from `repo\`, then update `PROJECT.md`. Leave the place file unless the user asks to delete it.

## Without Rocco, or on an older template

With no Rocco on the PC there is nothing to lend lanes, so each task is given a lane to work in directly, one task a lane: the worker switches the lane to its `agent/<task-slug>` branch, Lync syncs its edits as it saves, and the conductor merges and checks in a lane (WORKER.md "A game that still gives each task a lane"). Idle lanes then sit on a detached `origin/main`, and "refresh" moves them to the latest.
