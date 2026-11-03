# Drift

This game's details, loaded into every agent session: keep it short, and put design and detail in the other `docs/game/` files.

## At a glance

| | |
|---|---|
| Game | Drift |
| Code | `DR` |
| Phase | Pitch (docs/workflow/WORKFLOW.md) |
| Launched | Not yet |
| GitHub | `RowanByrne/driftgame` |
| Roblox | Experience (universe) `{{UNIVERSE_ID}}`, start place `{{PLACE_ID}}`, owned by `{{OWNER}}` |
| Update log | No |
| Lanes | None yet |
| Lync port base | `34870` |

## Places

Main is `places\DR-Main.rbxl`, served from `repo\` on the port base: always merged `main`, and the user's test place. Lane N is `DR-LaneN.rbxl`, served from `lanes\laneN` on base + N (docs/workflow/LANES.md). Other places agents may use, such as an art workshop, and what they may do there:

| Place file | Served from | Port | Use |
|---|---|---|---|
| | | | |

**Hands-off places:** none yet. Places agents must never inspect, playtest, attach Lync to or change, such as the user's Team Create map.

## Workstations

Each PC that works on this game, and how many lanes it opens: `lane1` up to that number (docs/workflow/LANES.md "How many lanes").

| PC (`$env:COMPUTERNAME`) | What it is | Lanes it opens |
|---|---|---|
| None yet | | |

## Game-only rules

- None yet.

## Current focus

The pitch: get `PITCH.md` approved. After that the focus is the drift feel itself — meta progression and the larger scale stay undecided until a baseplate prototype proves it. The plan is in ROADMAP.md.
