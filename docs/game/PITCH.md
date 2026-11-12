# Pitch

What we're making and why it can win on Roblox: the Pitch phase's output (docs/workflow/WORKFLOW.md).

**Status:** Draft. When the user approves it, write "Approved YYYY-MM-DD" here and add a line to `DECISIONS.md`.

## Hook

A car game about clean drifts: one finger, one long slide, and the chase for the perfect line.

## Core loop

The feel first; how a run is framed and scored is open (see "Numbers" and "Biggest risks").

1. Line up a corner and build speed.
2. Break the car loose into a slide with one input.
3. Hold the drift through the corner, steering and bleeding speed with the slide itself.
4. Catch the exit clean and carry the speed into the next corner.
5. See how clean it was, and go again.

**(proposed)** Free roam is endless; a scored run is 60 to 90 seconds. To settle after the first prototype.

## Who it's for

Mobile first, all ages. Controls are simple enough that anyone can slide on their first try. Car players are the obvious audience, but the game is built to look and feel slick to everyone.

## Games we borrow from

| Game | What we take | What we do differently |
|---|---|---|
| DRIFTO (mobile) | One-finger drift control: a single held input does the whole slide | Nearly everything past the control scheme; what it becomes depends on the progression and meta, still open |
| Impossible Road (mobile) | The endless mode's shape: a generated track that falls away ahead of you into empty space, where the road itself is the only obstacle and speed is what a clean line pays. No traffic, no pickups | Ours is a drift game, so the line is held sideways rather than threaded, and leaving the road is a fall and not a shortcut. Its track is bare white; ours is not (`ART-DIRECTION.md`). Since 2026-11-12 ours is no longer in a void either: it is a mountain road, with grass, rock faces, hedges and cliff drops (`features/mountain-road.md`) |
| Subway Surfers (mobile) | The endless run's framing: a run that ends, a score that climbs while it lasts, things to read and react to arriving down the road, and a cosmetic meta (characters, boards) that the run pays into | Not lane-based and not a runner: the car is steered freely across a 50-stud road and the skill is the drift, not the dodge. What ends a run is still open (`features/endless-run.md`) |

## Why players come back

That slick feeling of the perfect drift: chasing perfection and the flow state. That's the core feeling and the first reason to return.

Meta progression, social features and long-term progression will carry retention beyond that, but which ones is **not decided yet** — the user wants to feel the drifting first.

## How it makes money

**(proposed)** Cosmetic-only: cars, liveries and trail effects, bought directly. No paid random rewards, nothing that makes a car drift better than a free one. Revisit once the meta progression is chosen; the detail goes in `MONETIZATION.md` in Production.

## Launch scope

**(proposed)**, from the answers so far:

- The drift model, custom-built, tuned and stable on phone, desktop and gamepad.
- One-input drift control, mobile first.
- One handcrafted drift map with corners, ramps and berms worth learning.
- A clean-drift score with a readable result at the end of a run.
- A small set of cosmetic cars.
- A leaderboard or personal best, so chasing perfection has somewhere to land.

Everything else, including whatever the meta progression turns out to be, goes in `ROADMAP.md` "Later" until the user picks a direction.

## Not doing

- **Roblox's physics system driving the cars.** The user's call: "it's unreliable and too random". The drift model is our own code.

## Numbers that show it works

**(proposed)** — targets to confirm with the user.

| Number | Target |
|---|---|
| Day-1 retention | 25% or better |
| Median session length | 8 minutes |
| New players who land a scored clean drift in their first 2 minutes | 70% |
| Runs per session | 4 or more |

## Biggest risks

- **The drift feel is the whole game.** If a custom, non-physics drift model doesn't feel great in the first prototype, nothing downstream saves it. Found out early: the first playtest is a baseplate with obstacles, nothing else.
- **Custom vehicle movement on mobile.** Hand-rolled movement has to stay smooth and consistent across devices and under lag. Measured with frame time and position traces during the Core loop phase.
- **No meta decided.** The hook is a feeling, not a progression. Retention past day 1 is unproven until that's chosen; the risk is building content before the direction is picked.
- **Terrain fidelity vs. the low-poly look.** Ramps and berms need enough geometric resolution for the drift model to behave; the look must not win that argument (`ART-DIRECTION.md`).
- **Platform risk — copyright.** Real manufacturers' cars, names, badges and logos are off limits. Every car is an original design. Likewise the comparison game's name stays in these docs, never in the game or on the store page.
- **Platform risk — audience.** All-ages means a Minimal or Mild maturity label: no paid random rewards, no free-form text or social-hangout features that would push the rating up (`docs/workflow/PLATFORM-RISKS.md`).
