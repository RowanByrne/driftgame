# {{GAME_NAME}}

This game's details, loaded into every agent session: keep it short, and put design and detail in the other `docs/game/` files.

## At a glance

| | |
|---|---|
| Game | {{GAME_NAME}} |
| Code | `{{CODE}}` |
| Phase | Pitch (docs/workflow/WORKFLOW.md) |
| Launched | Not yet |
| GitHub | `{{GITHUB_REPO}}` |
| Roblox | Experience (universe) `{{UNIVERSE_ID}}`, start place `{{PLACE_ID}}`, owned by `{{OWNER}}` |
| Update log | No |
| Lanes | 2 (lane1 to lane2) |
| Lync port base | `34870` |

## Places

Main is `places\{{CODE}}-Main.rbxl`, served from `repo\` on the port base: always merged `main`, and the user's test place: agents check their work in lanes, not here (docs/workflow/TESTING.md). Lane N is `{{CODE}}-LaneN.rbxl`, served from `lanes\laneN` on base + N (docs/workflow/LANES.md). Other places agents may use, such as an art workshop, and what they may do there:

| Place file | Served from | Port | Use |
|---|---|---|---|
| | | | |

**Hands-off places:** none yet. Places agents must never inspect, playtest, attach Lync to or change, such as the user's Team Create map.

## Workstations

Each PC that works on this game, and how many lanes it opens: `lane1` up to that number (docs/workflow/LANES.md "How many lanes").

| PC (`$env:COMPUTERNAME`) | What it is | Lanes it opens |
|---|---|---|
| `MONSOONPC` | 62 GB, 32 threads (AMD Ryzen 9 9950X3D 16-Core Processor) | 2 |

## Game-only rules

- None yet.

## Current focus

One or two lines on what we're working on now. The plan is in ROADMAP.md.
