# {{GAME_NAME}}

This game's details. CLAUDE.md imports this file, so every session sees it: keep it short, and put design and detail in the other `docs/game/` files. Fill in every `{{...}}` when the game is created (docs/workflow/NEW-PROJECT.md).

## At a glance

| | |
|---|---|
| Game | {{GAME_NAME}} |
| Code | `{{CODE}}`: the short prefix for this game's place files, e.g. `places\{{CODE}}-Main.rbxl` |
| Phase | Pitch (Pitch, Foundation, Core loop, Production, UI, Launch, Live: see docs/workflow/WORKFLOW.md). Update it when a gate passes. |
| Launched | Not yet. The date it went public, once it does. |
| GitHub | `{{GITHUB_REPO}}` (`origin`); template `RowanByrne/rodev_template` (`template`) |
| Roblox | Experience (universe) `{{UNIVERSE_ID}}`, start place `{{PLACE_ID}}`, owned by `{{OWNER}}` (the user's account or a group; it decides who must grant asset permissions) |
| Update log | No. Whether the game has an in-game update log is the user's call; even with one, they decide per update whether it gets notes (docs/workflow/RELEASING.md). |
| Lync port base | `34870`: main serves on it, lane N on base + N. Must match `port` in `default.project.json`. Give each game its own base (34870, 34890, 34910, ...) so two can run at once. |

## Places

| Place file | Served from | Port | Use |
|---|---|---|---|
| `{{CODE}}-Main.rbxl` | `repo\` | base | Always shows merged `main`; the user's test place |
| `{{CODE}}-LaneN.rbxl` | `lanes\laneN` | base + N | Worker places, one per lane (docs/workflow/LANES.md) |

Add a row for any other place agents may use, such as an art workshop, with what they may do there.

**Hands-off places:** none yet. List any place agents must never inspect, playtest, attach Lync to or change (for example the user's Team Create map workplace).

## Game-only rules

Rules for agents that apply to this game only: exceptions, things to preserve, workshops. Rules that would suit every game belong in the template (CLAUDE.md "Template-owned files").

- None yet.

## Current focus

One or two lines on what we're working on now. The plan is in ROADMAP.md.
