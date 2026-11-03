# Roadmap

What we're building, in what order. The current phase is in `PROJECT.md`; the phases are in docs/workflow/WORKFLOW.md. Started in the Pitch phase. After launch, the weekly review of the numbers steers it (docs/workflow/DASHBOARDS.md shows where to find them). Replace each prompt with the answer.

## Milestones

> Each phase gate the game still has to pass, with a rough target date. Mark it done, with the date, when the user says go.

| Milestone | Target | Done |
|---|---|---|
| Pitch approved | | |
| Foundation checklist passes | | |
| Core loop: the user says go | | |
| Launch scope built | | |
| UI approved | | |
| Launch offers work end to end | | |
| Public launch | | |

## Launch scope

**(proposed)**, from `PITCH.md` "Launch scope". Not to be built until the pitch is approved and the drift feel is proven.

| Item | Spec | Status |
|---|---|---|
| Custom drift model (no Roblox physics) | `features/drift-model.md` | Prototype in progress |
| One-input drift control, mobile first | `features/drift-model.md` | Prototype in progress |
| One handcrafted drift map: corners, ramps, berms | `features/<name>.md` | Not started |
| Clean-drift scoring and end-of-run readout | `features/<name>.md` | Not started |
| A small set of cosmetic cars | `features/<name>.md` | Not started |
| Leaderboard or personal best | `features/<name>.md` | Not started |

## Now

Pitch: approve `PITCH.md`.

## Next

Core loop: a basic baseplate world with some obstacles to drift around, to feel how the drifting feels. That's step 1 — nothing else goes in it.

## After launch

> How the game keeps going once it's live: how often updates ship, the kinds of update (new content, live events, seasons, fixes and tuning), and the plan for the first 4 to 8 weeks. Each dated update gets a card in `live/CALENDAR.md`; the weekly numbers that steer this come from Rocco's Metrics (docs/workflow/DATA-SYSTEM.md).

- **Cadence:**
- **Kinds of update:**
- **First weeks:**

## Later

Parked until the drift feel is proven and the user picks a direction (`GDD.md` "Open after the prototype"):

- **Meta progression** — undecided, and the main open question in the pitch. Worth doing because the hook is a feeling, and a feeling alone doesn't hold players past day 1.
- **The "big scale group" direction** — what the game is beyond a single run. Decides most of the rest of the roadmap.
- **Social and multiplayer** — ghosts, shared servers, competing. Worth doing because showing off a clean line is most of the appeal.
- **Tutorial and first five minutes** — deliberately deferred: the user wants to revisit it once there's something to teach.
- **Monetization beyond cosmetics** — only after the meta is chosen.
- **An artist for the cars** — the user intends to bring one in if development goes well.
