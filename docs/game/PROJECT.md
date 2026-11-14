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

Main is `places\DR-Main.rbxl`, served from `repo\` on the port base: always merged `main`, and the user's test place: agents check their work in lanes, not here (docs/workflow/TESTING.md). Lane N is `DR-LaneN.rbxl`, served from `lanes\laneN` on base + N (docs/workflow/LANES.md). Other places agents may use, such as an art workshop, and what they may do there:

**No place holds a track.** `DR-Main.rbxl` once held the kart circuit the user built by hand as `workspace.Track`, scaled 2x and lifted onto the baseplate, which `TrackService` adopts at runtime. That place was never saved, so on 2026-11-08 Main was back to the plain baseplate and the circuit is gone (AGENTS.md "Hand-built content": a place file isn't in git, so hand-built content survives only if it's saved). Until the user rebuilds it, anything that needs a real track uses a stand-in built in a lane. `DR-Lane4.rbxl` does hold a saved `workspace.Showroom`, from 2026-11-06.

| Place file | Served from | Port | Use |
|---|---|---|---|
| | | | |

**Hands-off places:** none yet. Places agents must never inspect, playtest, attach Lync to or change, such as the user's Team Create map.

## Workstations

Each PC that works on this game, and how many lanes it opens: `lane1` up to that number (docs/workflow/LANES.md "How many lanes").

| PC (`$env:COMPUTERNAME`) | What it is | Lanes it opens |
|---|---|---|
| `MONSOONPC` | 62 GB, 32 threads (AMD Ryzen 9 9950X3D 16-Core Processor) | 4 |
| `WKEYSTUDIOS1680` | 62 GB, 16 threads (AMD Ryzen 7 9800X3D 8-Core Processor) | 6 |

## Game-only rules

- Agent choice (2026-11-13): Codex on `gpt-6.1-sol`, ultra effort, for the conductor and feature leads. Workers also use `gpt-6.1-sol`: light = high, standard = xhigh, heavy = ultra. This overrides the template's model defaults while Claude credits are exhausted. Use explicit model and effort overrides when starting workers; the template's worker launcher still has its older defaults.

## Current focus

**The feel gate is passed.** The drift model is a port of the reference game's, read off a decompile of it, and the user drove it and approved it on 2026-11-03 (DECISIONS.md): the finger IS the car's rate of turn, the drift is momentum lagging behind it, and a quadratic grip force pulls it back — past 90° of slip that force becomes a brake. The one-finger control and the camera are approved with it, and the car is the AE86 the user added, as a **placeholder that is not approved to publish** (`features/drift-model.md` "Platform risks").

Not built, deliberately: the drift score and its multiplier ladder — specced in `features/drift-model.md` "Score", task deleted by the user. Still undecided: what a run is, meta progression and the larger scale. `PITCH.md` is still Draft.

One open tuning question survives the approval: only the bottom fifth of the finger's travel is usable before the car spins rather than drifts, because the reference's real tuning is not in the decompile. Tripling the three grip numbers opens the whole stick (measured). Tuning is numbers in `Shared/Config/Drift.luau`, not code.
