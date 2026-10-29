# Conductor

The main Claude session is the **conductor**. It plans the work, hands tasks to worker agents (each in its own lane, LANES.md), merges their branches into `main`, and keeps every place showing the latest build.

The conductor works in `repo\`, the main checkout, which is always on `main` and serves the Main place. Workers never touch it.

## Workers or do it yourself

- **Workers:** several independent tasks, or one big task. One task per lane per round, using only the lanes this PC opens (`PROJECT.md` "Workstations"; LANES.md "How many lanes").
- **Conductor, directly in `repo\`:** a small change (one file, a few lines, nothing claimed), docs, claims, update notes. Commit to `main` and push.

## A round

1. **Plan.** Split the request into tasks that own **separate files**: no file belongs to two tasks. Shared modules (`src/ReplicatedStorage/Shared`, contracts) get one owner per round, or go first in a round of their own. Read `docs/CLAIMS.md` and never assign a file another task has claimed. Pick a lane and an agent per task (table below). Show the user the plan as a table (task, files, lane, branch, agent) before spawning.
2. **Claim and sync.** Add the round's claims to `docs/CLAIMS.md`, commit, and push `main`, so workers branch from the latest. Check each lane you'll use is idle (clean, detached HEAD) and its place is open and syncing (LANES.md "Probe").
3. **Spawn** the workers in parallel. Each prompt gives:
   - **Task:** what to build, and what done looks like.
   - **Files owned:** exact paths; new files marked "(new)".
   - **Lane:** the lane's absolute path, resolved now (the project folder can move between sessions), and its place, `<CODE>-LaneN`.
   - **Branch:** `agent/<task-slug>`.
   - **Proof:** the numbers, logs or debug state that will show it works. Screenshots only for "does it look right?", 2 or 3 at most, and the final look is left to the user.
4. **Merge.** When workers report, `git fetch origin`, `git pull`, then merge each `agent/*` branch into `main` with `--no-ff`. Resolve simple conflicts yourself; hand messy or multiple conflicts to the `git-integrator` agent. Record any contract or analytics changes the workers report in `CONTRACTS.md` / `EVENT-CATALOG.md`.
5. **Push and verify.** `git pull` again, push `main`, then check the merged build in the Main place with the Studio tools: playtest (marked quiet, TESTING.md), exercise what changed, read the console for errors and warnings.
6. **Refresh lanes.** Move every idle lane to the new `main` ("Refresh" step 4), so every place shows the merged game.
7. **Clean up.** Remove the round's lines from `docs/CLAIMS.md` and push. Delete the merged `agent/*` branches, locally and on GitHub.
8. **Report** to the user: what merged, what to try in the Main place, and any follow-ups or problems workers raised.

### Which agent

Pick a worker tier by how hard the task is. `MODELS.md` says which model and effort each tier runs.

| Tier | Agent | Use for |
|---|---|---|
| Heavy | `roblox-dev-heavy` | Core systems, tricky gameplay, anything touching player data or money |
| Standard | `roblox-dev-standard` | Well-specified features, content, UI |
| Light | `roblox-dev-light` | Small, mechanical, clearly specified fixes |

The three share one body and differ only in their frontmatter; keep their bodies identical.

## Claims

`docs/CLAIMS.md` lists every task in progress and the files it owns, so parallel sessions and workers never edit the same file.

- One row per task: its branch, its lane, and the files it owns (folders as `folder/*`, new files marked "(new)").
- Claim before spawning, and push the claim; remove it after merging, and push again.
- **Append-only registries** (a list that tasks only add to, like a sounds registry) can be shared by anchor: claim "new block after `X` only". Nobody else edits that file's existing lines.

## Refresh

When the user says **"refresh"**, sync with GitHub both ways and leave every place on the latest build.

1. **Check for local changes first; never throw anything away.** `git status` in `repo\` and every lane. Commit what you understand (docs, claims, finished work). Show the user anything unexplained or half-done, like a stopped worker's edits in a lane, and ask before committing it.
2. **Merge.** `git pull` (merge, not rebase) into `main`, then merge finished `agent/*` branches whose workers have reported, as in round step 4.
3. **Push** `main`. If it's rejected, pull, re-check, and push again.
4. **Refresh every idle lane.** For each lane that is clean and on a detached HEAD: `git -C <lane> fetch origin`, then `git -C <lane> switch --detach origin/main`. Lync syncs it into its place; a place in the middle of a playtest picks it up on the next one. A lane with a branch checked out or uncommitted work is in use: leave it and say so.
5. **Report** what went up, what came down, and where each lane and place stands.

## Main

- `git pull` (merge, not rebase) right before merging workers and again right before pushing. Never force-push or rewrite `main`.
- **Shared contracts move first.** A change to `CONTRACTS.md`, `EVENT-CATALOG.md` or `src/ReplicatedStorage/Shared` that other tasks build on is its own small commit, pushed straight away.
- `main` must always play (WORKFLOW.md): a branch that breaks the build doesn't merge until it's fixed.
