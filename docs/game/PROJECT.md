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
| Game code review | Lane first |

## Places

Main is `places\DR-Main.rbxl`, served from `repo\` on the port base: always merged `main`, and the user's test place: agents check their work in lanes, not here (docs/workflow/TESTING.md). Lane N is `DR-LaneN.rbxl`, served from `lanes\laneN` on base + N (docs/workflow/LANES.md). Other places agents may use, such as an art workshop, and what they may do there:

**No place holds a track.** `DR-Main.rbxl` once held the kart circuit the user built by hand as `workspace.Track`, scaled 2x and lifted onto the baseplate, which `TrackService` adopts at runtime. That place was never saved, so on 2026-11-08 Main was back to the plain baseplate and the circuit is gone (AGENTS.md "Hand-built content": a place file isn't in git, so hand-built content survives only if it's saved). Until the user rebuilds it, anything that needs a real track uses a stand-in built in a lane. `DR-Lane4.rbxl` does hold a saved `workspace.Showroom`, from 2026-11-06.

| Place file | Served from | Port | Use |
|---|---|---|---|
| | | | |

**Studio crashes on large live syncs (2026-11-15):** Studio 0.747 crashes (native null-read, same site every time) about 1-3 s after Lync pushes an edit of a large road source file (`SplineGen`, `SplineMesh` and the like) into an open place: six lane crashes and one Main crash that day. Opening a place with the code already on disk has not crashed. Save Main before pulling a change to those files into `repo\`. **Small files too (later that day):** Main also went down on three merges pulled into `repo\`, the last of them only `SkidSound`, `Config/Fx` and docs, so save Main before every pull into `repo\`, and reopen it with `rocco.ps1 lanes`. **Check Main's Lync after a crash (2026-11-16):** a crash took Main's Lync down with it and `lanes` reopened only the place, so Main sat unsynced; and because Main is saved, the scripts of removed systems stayed in it (Lync doesn't take out what an earlier session put there). After reopening, check port 34870 is listening and connected, and that Main's script count matches `src` (295 that day); remove leftovers by hand, then save. A lane on loan whose place went down is opened again by `rocco.ps1 sync <task>`; wait for it, and check its fingerprint.

**Hands-off places:** none yet. Places agents must never inspect, playtest, attach Lync to or change, such as the user's Team Create map.

## Workstations

Each PC that works on this game, and how many lanes it opens: `lane1` up to that number (docs/workflow/LANES.md "How many lanes").

| PC (`$env:COMPUTERNAME`) | What it is | Lanes it opens |
|---|---|---|
| `MONSOONPC` | 62 GB, 32 threads (AMD Ryzen 9 9950X3D 16-Core Processor) | 6 |
| `WKEYSTUDIOS1680` | 62 GB, 16 threads (AMD Ryzen 7 9800X3D 8-Core Processor) | 6 |

## Game-only rules

- **Use project tools for Rocco work.** The conductor, feature leads and all workers use the Rocco CLI and the Roblox Studio MCP. Never use the Computer Use skill or its desktop-control tools for Rocco work. Include this rule in every worker and feature lead brief.
- **Game code goes through a worker and through lane review.** The conductor scopes and assigns each game code fix to a worker at the appropriate tier, including small fixes, each in a checkout of its own (`rocco.ps1 work`; LANES.md "Lending a lane"). It may handle plans, claims, docs, and errands. The worker builds the change, tests it in a lane it borrows, and keeps that lane. Then use `set -Status ready -Where lane` with steps for the user to try: Rocco holds a lane on the task's commit for them, and the card says which (or offers Load into a lane when none is free). Merge and update Main only after that approval (CONDUCTOR.md "Checking before main"). A send-back goes to the worker, which borrows a lane again for its next check. This overrides the small-change and merge-before-testing defaults in `CONDUCTOR.md`.
- **Lanes are lent (2026-11-15).** Nobody works in a lane any more: a task's code is written in its checkout in `work\`, and a lane only ever shows a commit (LANES.md). Never save a lane's place, and build nothing by hand in one. A place that doesn't match the fingerprint `borrow` prints is reported, not worked around. Both of this PC's lanes matched on the day of the switch.
- **Either agent conducts (2026-11-19).** Drift is agent-neutral: the conductor is whichever agent the user opens, and its workers are that agent's own. **Claude Code:** Opus 5.5 for everything, the conductor and the `roblox-dev-light`, `-standard` and `-heavy` subagents (MODELS.md "Jobs"). **Codex:** GPT-6.2 Astra, the conductor at extra high reasoning; native Codex workers by tier as `drift_light` (medium), `drift_standard` (high) or `drift_heavy` (extra high), whose profiles are in `.codex/agents/`. In a session that accepts explicit spawn settings, pass `gpt-6.2-astra` and the tier's effort (`medium`, `high` or `xhigh`) with a fresh worker context. Either way, give each worker its Rocco card and its checkout.


## Current focus

**The feel gate is passed.** The drift model is a port of the reference game's, read off a decompile of it, and the user drove it and approved it on 2026-11-03 (DECISIONS.md): the finger IS the car's rate of turn, the drift is momentum lagging behind it, and a quadratic grip force pulls it back — past 90° of slip that force becomes a brake. The one-finger control and the camera are approved with it, and the car is the AE86 the user added, as a **placeholder that is not approved to publish** (`features/drift-model.md` "Platform risks").

Not built, deliberately: the drift score and its multiplier ladder — specced in `features/drift-model.md` "Score", task deleted by the user. Still undecided: what a run is, meta progression and the larger scale. `PITCH.md` is still Draft.

One open tuning question survives the approval: only the bottom fifth of the finger's travel is usable before the car spins rather than drifts, because the reference's real tuning is not in the decompile. Tripling the three grip numbers opens the whole stick (measured). Tuning is numbers in `Shared/Config/Drift.luau`, not code.
