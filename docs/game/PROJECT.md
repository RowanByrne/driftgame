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
| Lanes | 8 (lane1 to lane8) |
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
| `WKEYSTUDIOS1680` | 62 GB, 16 threads (AMD Ryzen 7 9800X3D 8-Core Processor) | 4 |

## Game-only rules

- None yet.

## Current focus

The first prototype is built and on `main`: the drift model on one gesture, and an open plate to feel it in (`features/drift-model.md`, `features/drift-playground.md`). **It is waiting on the user to drive it** — the feel is the gate, and nothing past it is decided until they say it is right. `PITCH.md` is still Draft and waiting on them too; the prototype ran ahead of that gate on their instruction (DECISIONS.md, 2026-11-03). Meta progression and the larger scale stay undecided until the feel is proven. Tuning is numbers in `Shared/Config/Drift.luau`, not code.
