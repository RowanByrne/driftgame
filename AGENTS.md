# Agent rules

A Roblox game built from the RoDev template. Luau source in `src/` is synced into Studio by Lync. GitHub `origin/main` is the source of truth for code and every text file; place files and big art live in the project folder next to this repo, outside git.

These rules are for whichever coding agent the user works with: Claude Code, Codex, Gemini CLI or another (`docs/workflow/MODELS.md`). `CLAUDE.md` and `GEMINI.md` only point here.

**This game's details are in `docs/game/PROJECT.md`:** name, code, Roblox ids, port base, current phase, game-only rules. Claude Code and Gemini CLI load it with this file; any other agent reads it before any work.

## Project layout

The project folder sits in a RoDev folder next to `template\` and `_tools\` (WORKSTATION.md). That folder can move, even to another drive letter, so never write an absolute path or drive letter into a file or script.

```
<Game>\
  repo\          this repo (origin = this game on GitHub, template = rodev_template)
  lanes\laneN\   worker checkouts of this repo, one per lane (docs/workflow/LANES.md)
  places\        Studio places: <CODE>-Main.rbxl is served from repo\, <CODE>-LaneN.rbxl from lanes\laneN
  art\           art in progress (docs/workflow/ART-PIPELINE.md)
  backups\       place snapshots before risky edits
  scratch\       throwaway files; anyone may delete them
```

- **In git:** all text, and approved art that ships in the game, up to 5 MB a file (a commit check, `tools/hooks/pre-commit`, refuses anything bigger).
- **Outside git:** image candidates, source files (.psd, .blend, .kra), video, `.rbxl` places, backups.
- **Access:** agents work in the folders next to this repo and in the template's checkout too (MODELS.md "Setting up an agent").

## Who does what

| The user | The agent |
|---|---|
| Decides direction: the pitch, features, the look, names and prices players see | Proposes, plans, builds, tests, and keeps the docs current |
| Plays the game and says go or no-go at each phase gate (WORKFLOW.md) | Proves work by measuring, and says what to look at |
| Picks art and sounds from candidates | Generates candidates, uploads only what the user picked, sets the asset ids |
| Publishes to players, never the agent, and changes Creator Dashboard settings (or asks the agent to, in the browser) | Runs the pre-publish checks, writes update notes when asked, records dashboard settings in `live/EXPERIENCE.md` |
| Opens the lanes (Rocco's Lanes, which starts Lync with no windows; or `tools\serve-all.bat`) | Probes lanes before use; starts a Lync that isn't serving only when needed (LANES.md) |

The main session is the **conductor**: it plans, hands tasks to **workers** in lanes, and merges their work (CONDUCTOR.md). A worker follows `docs/workflow/WORKER.md`.

## Talking to the user

Keep replies short. The user wants two things:

- **Done:** what's finished, a line each.
- **Flagged:** what needs their decision, what's broken or risky, what couldn't be checked.

Then stop.
- **Lead with results, not process.** Don't narrate steps, or restate the request or the plan.
- **Leave out details** (file lists, measurements, reasoning) unless they change what the user should do, or the user asks.
- **Ask one question at a time,** and only when the work needs the answer.

## Rules

**Git**
- Never `reset --hard`, `checkout --` / `restore`, `clean`, `stash` or force-push to get a clean tree. Commit changes you understand; show the user anything unexplained or half-done and ask before committing it.
- Merge, don't rebase, into `main`, and `git pull` right before pushing it. Never rewrite `main`.
- Workers commit to `agent/<task-slug>` branches in their lane. Only the conductor merges into `main` (CONDUCTOR.md).
- **Claims:** check `docs/CLAIMS.md` before editing. Don't touch files another task owns, and keep other sessions' uncommitted changes.
- Commit messages end with your Co-Authored-By line, naming the agent and the model you run as, like `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Use your own agent's usual line.

**Code**
- Code changes go in files under `src/`; Lync syncs them into Studio. Never push code into a place with `execute_luau`, and never rely on edits made directly in Studio: they aren't saved to git.
- `.luau` files are ModuleScripts unless the first line is `--@script:server`, `--@script:client` or `--@localscript`. `default.project.json` maps `src/` folders to Studio services.
- Code against `docs/game/CONTRACTS.md` (data, remotes, tags, attributes, service APIs) and `docs/game/EVENT-CATALOG.md` (analytics events). A contract change updates its doc in the same commit; a change other tasks build on goes in first as its own small commit.

**Studio**
- Studio is reached through the Roblox Studio MCP, registered in your agent as `Roblox_Studio` (WORKSTATION.md). Without it, say so and work without Studio. Read TESTING.md before using its tools.
- Use only the place you were given (match its name in `list_roblox_studios`, which lists only this PC's open places), and never touch the hands-off places listed in PROJECT.md. Mark every playtest you start quiet, and never leave one running.
- **The Main place is the user's:** they playtest there. Check your work in a lane's place, never in Main, and don't change Main unless they ask (TESTING.md). Code reaches `main` only after it's checked in a lane (CONDUCTOR.md "Checking in a lane").
- Prove behaviour with numbers: positions, sizes, counts, debug state, logs. Screenshot only to answer "does this look right?", at most 3 per task, and leave the final look to the user.

**Art**
- Images come from the image tool in MODELS.md, or from an agent that makes images itself, through the same steps (ART-PIPELINE.md). On a PC where neither can run, say so; don't substitute.

## Shorthands

| The user says | Do |
|---|---|
| "refresh" | Sync with GitHub both ways and move every idle lane to the latest `main` (CONDUCTOR.md "Refresh") |
| "about to publish" | The pre-publish checks, and update notes if the game has an update log (RELEASING.md) |
| "update notes" | RELEASING.md "Update notes" |
| "set up the game" | Turn the onboarding answers in `docs/game/ONBOARDING.md` into the docs (SETUP.md) |
| "update from template" | TEMPLATE.md "Taking an update" |
| "release the template" | In the template's own repo: TEMPLATE.md "Releasing" |

## Docs

Every doc, with what it holds, is in `docs/README.md`. Read the workflow doc before the work it covers:

| Read | When |
|---|---|
| `docs/workflow/WORKFLOW.md` | Starting a phase, or unsure what the current phase allows |
| `docs/workflow/CONDUCTOR.md` | Planning, spawning workers, merging, "refresh", the Workboard |
| `docs/workflow/ROLLBACK.md` | Something that went out broke: code on main, a publish, a config, the map |
| `docs/workflow/WORKER.md` | Working on a task in a lane |
| `docs/workflow/MODELS.md` | Which agent and model runs what; setting up an agent |
| `docs/workflow/SETUP.md` | Turning the onboarding answers into the docs |
| `docs/workflow/LANES.md` | Adding a lane, Lync problems |
| `docs/workflow/CODING.md` | Writing any Luau |
| `docs/workflow/TESTING.md` | Before using Studio tools or starting a playtest |
| `docs/workflow/ANALYTICS.md` | Adding or changing analytics events |
| `docs/workflow/DATA-SYSTEM.md` | The game's own metrics, from its custom events |
| `docs/workflow/DASHBOARDS.md` | Numbers, charts and alerts in the Creator Hub |
| `docs/workflow/CONFIGS.md` | Changing a live value without publishing; kill switches |
| `docs/workflow/EXPERIMENTS.md` | Proposing, running or deciding an A/B test |
| `docs/workflow/REVENUE.md` | Designing anything players pay for, or anything Roblox pays for |
| `docs/workflow/PLATFORM-RISKS.md` | Maturity, audience, paid random items, copyright, moderation, text and links |
| `docs/workflow/ART-PIPELINE.md` | Generating, approving or uploading art; Creator Store assets |
| `docs/workflow/AUDIO-PIPELINE.md` and `docs/game/AUDIO.md` | Any sound, music or voice |
| `docs/workflow/WORLD-BUILDING.md` and `docs/game/WORLD.md` | Laying out, building or changing the world |
| `docs/workflow/UI.md`, `docs/game/ART-DIRECTION.md` and `docs/game/UI-INVENTORY.md` | Any UI work |
| `docs/workflow/RELEASING.md` | About to publish, update notes, game page text, events and thumbnails |
| `docs/workflow/POST-RELEASE.md` | After a publish |
| `docs/workflow/LAUNCH.md` | Preparing for launch |
| `docs/workflow/WORKSTATION.md` | Setting up a PC, ending a session, backups |
| `docs/workflow/NEW-PROJECT.md` | Starting a game, or bringing one in |
| `docs/workflow/TEMPLATE.md` | Template updates and releases; which files are whose |
| `docs/game/` | What this game is, for any work on it |
| `live/` | After launch: releases, dashboard settings, experiments, the game page, the calendar, incidents |

Keep them current:
- **New feature:** its own spec in `docs/game/features/<name>.md`, copied from `_TEMPLATE.md`. Don't grow one giant design doc.
- **User decision:** one dated line in `docs/game/DECISIONS.md`, so it isn't reopened later.
- **One-off reviews and audits:** `docs/archive/`.
- **Wrong doc:** fix it when you notice; a template-owned one is fixed in the template checkout ("Template-owned files"). A stale doc misleads every agent after you.

## Template-owned files

These files are the template's, the same in every game: `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.claude/`, `docs/workflow/`, `tools/`, `.gitignore`. **Don't edit them in a game.** When one should change, tell the user, then change it in the template checkout (`..\..\template\repo` from a game's `repo\`), commit and push it there; games get it in the next template release ("update from template", TEMPLATE.md). In the template repo itself, these are the files you edit.

- **Starter files** (`docs/game/`, `live/`, `src/` and the like) come from the template but are the game's own: a template update never overwrites them.
- **Game-specific rules go in `docs/game/PROJECT.md`;** game-only ignores go at the bottom of `.gitignore` under `# This game`.

## Workstations

- **Memory stays on the PC.** An agent's own memory, if it keeps one, is on each workstation, not in the project. Anything another session, PC or agent must know goes in the repo: PROJECT.md, DECISIONS.md, or the relevant doc.
- Setting up a new PC, and the checklist before stopping work: WORKSTATION.md.
