# Worker

The brief for a **worker**: an agent doing one task, for the conductor (CONDUCTOR.md). It's the same for every agent and every worker tier; how each agent starts a worker, and which model a tier runs, is in MODELS.md.

You are a worker on the Roblox game in this repo (Luau in `src/`, synced into Studio by Lync). The conductor gives you a task with its Workboard id (`T-012`), the files you own, and a **checkout**: a folder `<Game>\work\<name>` (given as an absolute path), already on your branch, `agent/<task-slug>`. It's yours alone, and it has no Studio place: you **borrow a lane** when you test (LANES.md "Lending a lane").

**Do all your work in your checkout.** If your session started in `repo\`, the main checkout (as a subagent does), use absolute paths or `git -C <checkout>`, and never edit files or run git commands that change state in `repo\`, or in any lane.

Rocco's commands are `..\..\..\_tools\rocco\rocco.ps1 <command>` from your checkout (`..\..\_tools\rocco\rocco.ps1` from `repo\`), in PowerShell.

## Start

1. Your checkout must be clean and on your branch (`git -C <checkout> status -sb`). If it isn't, stop and report.
2. In your checkout, read `AGENTS.md`, `docs/game/PROJECT.md`, the feature's spec in `docs/game/features/` if it has one, and what your task touches in `CONTRACTS.md`, `ARCHITECTURE.md` and `EVENT-CATALOG.md` (all in `docs/game/`). Then the workflow docs for the work: `docs/workflow/CODING.md` and `TESTING.md` always, `UI.md` for UI, `ART-PIPELINE.md` for art, `ANALYTICS.md` for events.

## Rules

- **Only edit the files you were given.** If the task needs a change elsewhere, make the smallest change possible and call it out, or stop and report if it's more than a few lines.
- **Template-owned files are off limits** unless the task says otherwise: `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.claude/`, `docs/workflow/`, `tools/`, `.gitignore`. So is `default.project.json`.
- **Contracts:** if you own `CONTRACTS.md` or `EVENT-CATALOG.md` for this task, update them in the same commit as the code. If not, put the exact new or changed entries in your report, so the conductor adds them at merge.
- **Studio: only the place of the lane you've borrowed,** through the Roblox Studio MCP (`Roblox_Studio`). Pass only the `studio_id` whose name is that place (`list_roblox_studios`), and only while you hold the lane. Never touch the hands-off places in `PROJECT.md`. If your session has no Studio tools, say so and work without Studio.
- **Studio is for testing,** never for writing code (TESTING.md): mark every playtest you start so it stays silent, prove behaviour by measuring, take at most 3 screenshots, and use the debug bridges to reach live state.
- **Stay in scope and be quick.** Do the task you were given. Report anything else you notice instead of fixing it.

## Testing in a lane

A lane's place holds a **commit**, never your uncommitted edits. So:

1. **Commit** what you want to test.
2. **Borrow:** `rocco.ps1 borrow T-012`. It gives you a free lane and puts your latest commit in its place, or waits in line when every lane is busy (if it says you kept your place, run it again). It prints the lane, the place's name (`<CODE>-LaneN`; `list_roblox_studios` shows it with `.rbxl` on the end), and the script count and fingerprint the place should now hold.
3. **Check it synced** before any playtest whose results you'll report: read the checker file `borrow` named (it's in `<Game>\rocco\`, outside your checkout) and send its contents as `execute_luau` code in that place (Edit). Compare what it returns with the line `borrow` printed. If they differ, wait a few seconds and run it again; still different, stop and report (a place that doesn't match can't be trusted).
4. **Test** (TESTING.md). After a fix: commit, then `rocco.ps1 sync T-012`, which puts the new commit in the same place, and check again.
5. **Return:** `rocco.ps1 return T-012` when you're done testing for now, with no playtest left running. Others are waiting for lanes, so don't hold one while you write code. The one exception is your last test before you report: keep that lane ("Finish", step 5).

**If the place disappears** from `list_roblox_studios` while you hold the lane, Studio went down (it sometimes does just after a large sync). Run `rocco.ps1 sync T-012`: Rocco opens the place again. Wait for it to show in `list_roblox_studios` (about 20 seconds), check the fingerprint, and redo the test that was cut off. Twice in a row: stop and report.

Never edit files in the lane, and never build anything by hand in its place that the next borrower would find: what a test needs is built by code in `src/`, or removed before you return.

## The Workboard

Keep your task's card current with Rocco. The user watches it live.

- **As you go:** `set T-012 -Step "Wiring the shop remote" -Progress 40`, and `log T-012 -Text "..."` for what you found or measured.
- **What you checked:** `result T-012 -Pass -Text "12 of 12 tests pass" -File console.txt` (or `-Fail`) for each check you run, the output saved as text (the tests' report, Studio's console; any file will do, since Rocco copies it onto the card). The card shows each one, so the user sees what was tried before they test it.
- **A decision only the user can make** (a look, a name, a sound): `ask T-012 -Question "..." -Options "A","B"` (sounds as `-Audio` files, one per option), then stop and report. The conductor carries on with their answer. Options are a few words each ("A lap", "An open pad"); what each one means goes in the question, since the card shows two lines of an option at most.
- **Leave the status to the conductor:** never set your task `ready` or `done`.
- **Deleted:** if Rocco says the user deleted your task, stop: commit what you have to your branch and report. The conductor cleans up.

## Finish

1. **Commit** in small logical commits, each ending with your Co-Authored-By line (AGENTS.md "Git").
2. `git -C <checkout> fetch origin`, then `git -C <checkout> rebase origin/main` (or the feature's branch, if the conductor gave you one to start from), so what you test is what merges. If the rebase conflicts in files you don't own, `git rebase --abort` and report instead of guessing.
3. **Test in a lane,** on the rebased commit ("Testing in a lane"): a quiet playtest, exercise the change, read `get_console_output` for errors and warnings, stop the playtest. Never leave one running. Run the automated tests for anything touching saving, purchases or odds. Fix what fails, commit, `sync`, and test again.
4. `git -C <checkout> push -u origin HEAD`.
5. **Keep the lane** you last tested in: when the conductor sets your task ready for the user to try, that lane holds it for them. If you tested nothing in Studio, there's none to keep.
6. **Report briefly** (to the conductor, or in your session's last message):
   - your branch and commits, and the files you changed
   - what you tested and how, with the numbers you measured
   - known issues and follow-ups, and anything you noticed outside your task
   - contract and analytics changes for the conductor to record

## A game that still gives each task a lane

A game on an older template, or a PC without Rocco, has no `work\` checkouts: the conductor gives you a lane, `<Game>\lanes\laneN`, with its place `<CODE>-LaneN`, to work in directly. Then your lane is your checkout: start with `git -C <lane> fetch origin` and `git -C <lane> switch -c agent/<task-slug> origin/main` (the lane must be clean first), Lync syncs your edits into its place as you save them, and there's nothing to borrow or return. Never commit the lane's own `.lane-port` and `lane.project.json`.
