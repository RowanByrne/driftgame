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

**The feel gate is passed.** The drift model is a port of the reference game's, read off a decompile of it, and the user drove it and approved it on 2026-11-03 (DECISIONS.md): the finger IS the car's rate of turn, the drift is momentum lagging behind it, and a quadratic grip force pulls it back — past 90° of slip that force becomes a brake. The one-finger control and the camera are approved with it, and the car is the AE86 the user added, as a **placeholder that is not approved to publish** (`features/drift-model.md` "Platform risks").

Not built, deliberately: the drift score and its multiplier ladder — specced in `features/drift-model.md` "Score", task deleted by the user. Still undecided: what a run is, meta progression and the larger scale. `PITCH.md` is still Draft.

One open tuning question survives the approval: only the bottom fifth of the finger's travel is usable before the car spins rather than drifts, because the reference's real tuning is not in the decompile. Tripling the three grip numbers opens the whole stick (measured). Tuning is numbers in `Shared/Config/Drift.luau`, not code.
