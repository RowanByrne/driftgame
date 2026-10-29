# Agent rules

A Roblox game built from the RoDev template. Luau source in `src/` is synced into Studio by Lync. GitHub `origin/main` is the source of truth for code and every text file; place files and big art live in the project folder next to this repo, outside git.

This file is the same in every game. This game's details (name, code, Roblox ids, port base, current phase, game-only rules) are in PROJECT.md:

@docs/game/PROJECT.md

## Project layout

The project folder sits in a RoDev folder next to `template\` and `_tools\` (WORKSTATION.md). That folder can be anywhere, from a user folder to a portable drive with a changing letter, so use paths relative to this repo and never write an absolute path or drive letter into a file or script.

```
<Game>\
  repo\          this repo: code, docs, live records, approved art (origin = this game on GitHub, template = rodev_template)
  lanes\laneN\   worker checkouts of this repo, one per lane (docs/workflow/LANES.md)
  places\        Studio places: <CODE>-Main.rbxl is served from repo\, <CODE>-LaneN.rbxl from lanes\laneN
  art\           art in progress: generated\ candidates, source\ (.psd, .blend), reference\, captures\, marketing\
  backups\       place snapshots before risky edits
  scratch\       throwaway files; anyone may delete them
```

- **In git:** all text, and approved art that ships in the game, up to about 5 MB a file.
- **Outside git:** image candidates, source files (.psd, .blend, .kra), video, `.rbxl` places, backups.

## Who does what

| The user | Claude |
|---|---|
| Decides direction: the pitch, features, the look, names and prices players see | Proposes, plans, builds, tests, and keeps the docs current |
| Plays the game and says go or no-go at each phase gate (WORKFLOW.md) | Proves work by measuring, and says what to look at |
| Picks art from candidates | Generates candidates, uploads the picked art, sets the asset ids |
| Publishes to players, and changes Creator Dashboard settings (or asks Claude to, in the browser) | Runs the pre-publish checks, writes update notes when asked, records dashboard settings in `live/EXPERIENCE.md` |
| Starts Lync (`tools\serve-all.bat`) | Probes lanes before use; restarts Lync detached only when needed (LANES.md) |

## Rules

**Git**
- Never `reset --hard`, `checkout --` / `restore`, `clean`, `stash` or force-push to get a clean tree. Commit changes you understand; show the user anything unexplained or half-done and ask before committing it.
- Merge, don't rebase, into `main`, and `git pull` right before pushing it. Never rewrite `main`.
- Workers commit to `agent/<task-slug>` branches in their lane. Only the conductor merges into `main` (CONDUCTOR.md).
- Commit messages end with your Co-Authored-By line, naming the model you run as: `Co-Authored-By: Claude <model> <noreply@anthropic.com>`.

**Code**
- Code changes go in files under `src/`; Lync syncs them into Studio. Never push code into a place with `execute_luau`, and never rely on edits made directly in Studio: they aren't saved to git.
- `.luau` files are ModuleScripts unless the first line is `--@script:server`, `--@script:client` or `--@localscript`. `default.project.json` maps `src/` folders to Studio services.
- Code against `docs/game/CONTRACTS.md` (data, remotes, tags, attributes, service APIs) and `docs/game/EVENT-CATALOG.md` (analytics events). A contract change updates its doc in the same commit; a change other tasks build on goes in first as its own small commit.

**Studio**
- Use only the place you were given (match its name in `list_roblox_studios`), and never touch the hands-off places listed in PROJECT.md.
- Mark every playtest you start so it stays silent, and never leave one running (TESTING.md).
- Prove behaviour with numbers: positions, sizes, counts, debug state, logs. Screenshot only to answer "does this look right?", at most 3 per task, and leave the final look to the user.

**Art**
- Images come from the image tool in MODELS.md (`tools\imagegen.ps1` today; ART-PIPELINE.md). On a PC where it can't run, say so; don't substitute.
- Show candidates to the user. Never upload art they haven't picked.

**Publishing**
- Publishing to players is the user's job, never Claude's. When they say they're about to publish, run the checks in RELEASING.md first. Update notes are written only when the game has an update log and the user wants notes for this update.

## Shorthands

| The user says | Do |
|---|---|
| "refresh" | Sync with GitHub both ways and move every idle lane to the latest `main` (CONDUCTOR.md "Refresh") |
| "about to publish" | Run the pre-publish checklist, and ask about update notes if the game has an update log (RELEASING.md) |
| "update notes" | Write update notes for this update (RELEASING.md "Update notes") |
| "update from template" | `git fetch template`, then `git merge template/main`, and report what changed |

## Docs

| Read | When |
|---|---|
| `docs/workflow/WORKFLOW.md` | Starting a phase, or unsure what the current phase allows |
| `docs/workflow/CONDUCTOR.md` | Planning work, spawning workers, merging, "refresh" |
| `docs/workflow/MODELS.md` | Which model and effort each job and worker tier uses; changing them |
| `docs/workflow/LANES.md` | Adding a lane, Lync problems |
| `docs/workflow/CODING.md` | Writing any Luau |
| `docs/workflow/TESTING.md` | Before using Studio tools or starting a playtest |
| `docs/workflow/ANALYTICS.md` | Adding or changing analytics events; anything touching the pipeline |
| `docs/workflow/ART-PIPELINE.md` | Generating, approving or uploading art; finding Creator Store assets |
| `docs/workflow/UI.md`, `docs/game/ART-DIRECTION.md` and `docs/game/UI-INVENTORY.md` | Any UI work |
| `docs/workflow/RELEASING.md` | The user is about to publish, asks for update notes, or wants game page text or events |
| `docs/workflow/LAUNCH.md` | Preparing for launch |
| `docs/workflow/WORKSTATION.md` | Where projects live, setting up a PC, ending a session, backups |
| `docs/workflow/NEW-PROJECT.md` | Starting a new game from the template |
| `docs/game/` | What this game is: PITCH, GDD, ARCHITECTURE, CONTRACTS, EVENT-CATALOG, ART-DIRECTION, UI-INVENTORY, MONETIZATION, ROADMAP, DECISIONS, `features/` |
| `live/` | After launch: releases, dashboard settings, the game page, metrics, the calendar (live events, timed releases, game page events), incidents |

Keep them current:
- **New feature:** its own spec in `docs/game/features/<name>.md`, copied from `_TEMPLATE.md`. Don't grow one giant design doc.
- **User decision:** one dated line in `docs/game/DECISIONS.md`, so it isn't reopened later.
- **One-off reviews and audits:** `docs/archive/`.
- **Wrong doc:** fix it when you notice. A stale doc misleads every agent after you.

## Template-owned files

This repo started from `rodev_template` (remote `template`). These files belong to the template and are the same in every game: `CLAUDE.md`, `AGENTS.md`, `.claude/`, `docs/workflow/`, `tools/`, `.gitignore`.

- **Don't edit them in a game.** When one should change, tell the user, make the change in the template checkout (`..\..\template\repo` from a game's `repo\`), commit and push it there, then bring it into the game with "update from template". That keeps every game in step and template merges free of conflicts.
- **Game-specific rules go in `docs/game/PROJECT.md`**, never here. Game-only ignores go at the bottom of `.gitignore` under `# This game`.
- **In the template repo itself**, these are the files you edit.

## Workstations

- **Memory stays on the PC.** Claude's memory is stored on each workstation, not in the project. Anything another session or PC must know goes in the repo: PROJECT.md, DECISIONS.md, or the relevant doc.
- **Studio tools are per PC.** `list_roblox_studios` only lists places open on this PC.
- **The Studio MCP must be registered as `Roblox_Studio`.** The agent files allow Studio tools by that exact name; under any other name, workers get no Studio tools.
- Setting up a new PC, and the checklist before stopping work: WORKSTATION.md.
