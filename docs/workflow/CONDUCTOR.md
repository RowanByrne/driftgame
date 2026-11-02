# Conductor

The main agent session is the **conductor**, whichever agent the user works with (MODELS.md). It plans the work, hands tasks to workers (each in its own lane, LANES.md, following WORKER.md), merges their branches into `main`, and keeps every place showing the latest build.

The conductor works in `repo\`, the main checkout, which is always on `main` and serves the Main place. Workers never touch it.

The user hands over work and follows it in Rocco's Workboard, and the conductor keeps the board current ("The Workboard").

## Workers or do it yourself

- **Workers:** several independent tasks, or one big task. One task per lane per round, using only the lanes this PC opens (`PROJECT.md` "Workstations"; LANES.md "How many lanes").
- **Conductor, directly in `repo\`:** a small change (one file, a few lines, nothing claimed), docs, claims, update notes. Commit to `main` and push.

## A round

1. **Plan.** Split the request into tasks that own **separate files**: no file belongs to two tasks. Shared modules (`src/ReplicatedStorage/Shared`, contracts) get one owner per round, or go first in a round of their own. Read `docs/CLAIMS.md` and never assign a file another task has claimed. Pick a lane and a worker tier per task (table below). Show the user the plan as a table (task, files, lane, branch, tier) before spawning. Each task is a Workboard task: the user's note itself, or one you add ("The Workboard").
2. **Claim and sync.** Add the round's claims to `docs/CLAIMS.md`, commit, and push `main`, so workers branch from the latest. Check each lane you'll use is idle (clean, detached HEAD) and its place is open and syncing (LANES.md "Probe").
3. **Spawn** the workers in parallel, each task's card set Working first, the way your agent starts workers (MODELS.md "Workers by agent"). Each prompt starts with "Follow docs/workflow/WORKER.md", then gives:
   - **Task:** what to build, and what done looks like, with its Workboard id (`T-012`).
   - **Files owned:** exact paths; new files marked "(new)".
   - **Lane:** the lane's absolute path, resolved now (the project folder can move between sessions), and its place, `<CODE>-LaneN`.
   - **Branch:** `agent/<task-slug>`.
   - **Proof:** the numbers, logs or debug state that will show it works. Screenshots only for "does it look right?", at most 3, and the final look is left to the user.
4. **Merge.** When workers report, `git fetch origin`, `git pull`, then merge each `agent/*` branch into `main` with `--no-ff`. Resolve simple conflicts yourself, keeping both sides' intent; with Claude Code, messy or multiple conflicts can go to the `git-integrator` subagent. Record any contract or analytics changes the workers report in `CONTRACTS.md` / `EVENT-CATALOG.md`.
5. **Verify, then push.** `git pull` again, then check the merged build in the Main place before it goes up: Main is served from `repo\`, so it already shows what you merged. Playtest (marked quiet, TESTING.md), exercise what changed, and read the console for errors and warnings. Push `main` only when it plays; when it doesn't, fix it first or back the merge out (ROLLBACK.md).
6. **Refresh lanes.** Move every idle lane to the new `main` ("Refresh" step 4), so every place shows the merged game.
7. **Clean up.** Remove the round's lines from `docs/CLAIMS.md` and push. Delete the merged `agent/*` branches, locally and on GitHub.
8. **Report** to the user, short (AGENTS.md "Talking to the user"): what merged and what to try in the Main place, then anything flagged: problems workers raised, follow-ups, decisions needed. On the Workboard, each merged task goes to To test, with what to try.

### Which tier

Pick a worker tier by how hard the task is. `MODELS.md` says which model and effort each tier runs, and how your agent starts a worker of that tier (with Claude Code: the `roblox-dev-heavy`, `-standard` or `-light` subagent).

| Tier | Use for |
|---|---|
| Heavy | Core systems, tricky gameplay, anything touching player data or money |
| Standard | Well-specified features, content, UI |
| Light | Small, mechanical, clearly specified fixes |

Every tier follows the same brief, WORKER.md; only the model and effort differ.

## The Workboard

Rocco's Workboard (`tools\rocco.bat`) is where the user hands over work and follows it: notes they send, questions, plans to approve, and cards that move from Up next through Working (or Stuck) to To test, until they approve. Keep it current with Rocco's commands, run in PowerShell from `repo\`: `..\..\_tools\rocco\rocco.ps1 <command>` (Rocco's README, "Commands", and the script's header list every option). Not through `powershell -File`: lists like `-Steps` and `-Options` don't survive it. On a PC without Rocco, skip this section.

**What waits on you.** At the start of a session, and of every round, `rocco.ps1 list -Pending`, then `show` each task it lists. What the user did decides what you do:

| `list` shows | The user | You |
|---|---|---|
| `[plan]` | Sent a note: a bug, tweak, idea or feature | Plan it, as a round. Something with several tasks becomes a feature plan for them to approve: `plan -Title "..." -Summary "..." -Steps "title\|lane\|tier",...`, then `set <note> -Status removed`. A single task is the note itself |
| `[question]` | Asked something | `reply T-012 -Text "..."`, short. It shows under their note box |
| `[approved]` | Approved a feature plan | A task per step: `new -Title "..." -Plan T-020 [-After T-021]` (`-After`: it needs that done first). Then `clear T-020` |
| `[revise]` | Asked for changes to a plan | `set T-020 -Summary "..." -Steps ...`, then `clear` |
| `[answer]` | Answered a Stuck task's question | Carry on with their answer (to the worker, if one asked), and `set -Status working` |
| `[reopen]` | Tested it: not right yet | Their words are the last `you` line in `show`. Fix it as a task again |
| `[followup]` | Added to a task while it ran | Fold it in, or pass it to the worker; then `clear` |
| `[merge]` | Approved a feature they tested in a lane | Merge its branch ("A round", step 4), then `clear` |

**Through a round:**
- **Spawning:** `set T-012 -Status working -Lane 3 -Branch agent/<slug> -Step "Starting"`, and give the worker its id. Workers add their own steps, progress and questions.
- **Work you do yourself:** `set -Status working -Step "..."` as you start, and `log` what matters.
- **Merged and checked:** `set T-012 -Status ready -Where main -Summary "what changed" -Test "what to try in the Main place"`. A feature the user should try before it merges stays on its branch: `-Where lane`, and the test is in that lane's place. Approving it asks you to merge it (`[merge]`).
- **The user's questions while a task runs** (`ask` from a worker) turn its card Stuck until they answer.
- **Things you notice outside the task:** `suggest -Title "..." -Summary "why"`. The user queues or dismisses them.

The user approves a task, never you: don't set one `done`.

## Claims

`docs/CLAIMS.md` lists every task in progress and the files it owns, so parallel sessions and workers never edit the same file.

- One row per task: its branch, its lane, and the files it owns (folders as `folder/*`, new files marked "(new)").
- Claim before spawning, and push the claim; remove it after merging, and push again.
- **Append-only registries** (a list that tasks only add to, like a sounds registry) can be shared by anchor: claim "new block after `X` only". Nobody else edits that file's existing lines.

## Refresh

When the user says **"refresh"**, sync with GitHub both ways and leave every place on the latest build.

1. **Check for local changes first; never throw anything away.** `git status` in `repo\` and every lane. Commit what you understand (docs, claims, finished work). Show the user anything unexplained or half-done, like a stopped worker's edits in a lane, and ask before committing it.
2. **Merge.** `git pull` (merge, not rebase) into `main`, then merge finished `agent/*` branches whose workers have reported, as in round step 4.
3. **Push** `main`, once anything merged in step 2 plays in the Main place (round step 5). If the push is rejected, pull, re-check, and push again.
4. **Refresh every idle lane.** For each lane that is clean and on a detached HEAD: `git -C <lane> fetch origin`, then `git -C <lane> switch --detach origin/main`. Lync syncs it into its place; a place in the middle of a playtest picks it up on the next one. A lane with a branch checked out or uncommitted work is in use: leave it and say so.
5. **Check the calendar.** An update in `live/CALENDAR.md` that's due its game page event and still says `Not yet` gets one queued (RELEASING.md "Game page events"). Rocco does this by itself while it runs.
6. **Report**, short: what went up and what came down, then any lane or place that's in use or needs attention.

## Main

- `git pull` (merge, not rebase) right before merging workers and again right before pushing. Never force-push or rewrite `main`.
- **Shared contracts move first.** A change to `CONTRACTS.md`, `EVENT-CATALOG.md` or `src/ReplicatedStorage/Shared` that other tasks build on is its own small commit, pushed straight away.
- `main` must always play (WORKFLOW.md): a branch that breaks the build doesn't merge until it's fixed.

