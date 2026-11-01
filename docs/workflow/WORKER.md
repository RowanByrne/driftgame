# Worker

The brief for a **worker**: an agent doing one task in one lane, for the conductor (CONDUCTOR.md). It's the same for every agent and every worker tier; how each agent starts a worker, and which model a tier runs, is in MODELS.md.

You are a worker on the Roblox game in this repo (Luau in `src/`, synced into Studio by Lync). The conductor gives you a task, the files you own, a branch name `agent/<task-slug>`, and a **lane**: a folder `<Game>\lanes\laneN` (given as an absolute path) paired with the Studio place `<CODE>-LaneN`.

**Do all your work in your lane folder.** If your session started in `repo\`, the main checkout (as a subagent does), use absolute paths or `git -C <lane>`, and never edit files or run git commands that change state in `repo\`.

## Start

1. Your lane must be clean (`git -C <lane> status --porcelain` is empty). If it isn't, stop and report.
2. `git -C <lane> fetch origin`, then `git -C <lane> switch -c agent/<task-slug> origin/main`.
3. In your lane, read `AGENTS.md`, `docs/game/PROJECT.md`, the feature's spec in `docs/game/features/` if it has one, and what your task touches in `docs/game/CONTRACTS.md`, `ARCHITECTURE.md` and `EVENT-CATALOG.md`. Then the workflow docs for the work: `docs/workflow/CODING.md` and `TESTING.md` always, `UI.md` for UI, `ART-PIPELINE.md` for art, `ANALYTICS.md` for events.

Lync serves your lane into its place, so file edits show up there within a second or two.

## Rules

- **Only edit the files you were given.** If the task needs a change elsewhere, make the smallest change possible and call it out, or stop and report if it's more than a few lines.
- **Template-owned files are off limits** unless the task says otherwise: `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.claude/`, `docs/workflow/`, `tools/`, `.gitignore`. So are `default.project.json` and the lane's own `.lane-port` and `lane.project.json` (never commit those two).
- **Contracts:** if you own `CONTRACTS.md` or `EVENT-CATALOG.md` for this task, update them in the same commit as the code. If not, put the exact new or changed entries in your report, so the conductor adds them at merge.
- **Studio: only your own place,** through the Roblox Studio MCP (`Roblox_Studio`). Pass only the `studio_id` whose name is your lane's place (`list_roblox_studios`). Never touch the hands-off places in `PROJECT.md`. If your place isn't open, or your session has no Studio tools, say so and work without Studio.
- **Studio is for testing,** never for writing code (TESTING.md): mark every playtest you start so it stays silent, prove behaviour by measuring, take at most 3 screenshots, and use the debug bridges to reach live state.
- **Stay in scope and be quick.** Do the task you were given. Report anything else you notice instead of fixing it.

## The Workboard

If your task came with a Workboard id (`T-012`), keep its card current with Rocco, in PowerShell: `..\..\_tools\rocco\rocco.ps1 <command>` from `repo\`, or `..\..\..\_tools\rocco\rocco.ps1 <command>` from your lane. The user watches it live.

- **As you go:** `set T-012 -Step "Wiring the shop remote" -Progress 40`, and `log T-012 -Text "..."` for what you found or measured.
- **A decision only the user can make** (a look, a name, a sound): `ask T-012 -Question "..." -Options "A","B"` (sounds as `-Audio` files, one per option), then stop and report. The conductor carries on with their answer.
- **Leave the status to the conductor:** never set your task `ready` or `done`.

## Finish

1. **Test in your place** if it's open: start a quiet playtest, exercise the change, read `get_console_output` for errors and warnings, stop the playtest. Never leave one running. Run the automated tests for anything touching saving, purchases or odds.
2. **Commit** in small logical commits, each ending with your Co-Authored-By line (AGENTS.md "Git").
3. `git -C <lane> fetch origin`, then `git -C <lane> rebase origin/main`. If the rebase conflicts in files you don't own, `git rebase --abort` and report instead of guessing.
4. `git -C <lane> push -u origin HEAD`.
5. **Report briefly** (to the conductor, or in your session's last message):
   - your branch and commits, and the files you changed
   - what you tested and how, with the numbers you measured
   - known issues and follow-ups, and anything you noticed outside your task
   - contract and analytics changes for the conductor to record
