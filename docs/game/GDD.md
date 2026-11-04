# Game design

The map of the game's design: how the parts fit together. Keep it short. Each feature's detail lives in its own spec in `features/`, linked from here, and exact numbers live in the config modules (CODING.md). Started in the Core loop phase and kept current after that (docs/workflow/WORKFLOW.md). Replace each prompt with the answer.

## Overview

Drift is a car game about clean drifts. The player slides a low-poly car through corners, controlling speed and angle with the slide itself rather than the brake, and chases the feeling of a perfect, unbroken line. The cars are driven by our own movement code, not Roblox physics. Controls are simple enough for one finger on a phone, so the skill is in reading the corner and holding the slide, not in working the inputs. What sits on top of that feeling — progression, a meta game, the long-term scale — is deliberately undecided until the drifting feels right.

## Core loop

1. **Approach.** The player reads the next corner and builds speed on the way in. *(sees: the road ahead and current speed)*
2. **Break loose.** One input throws the car into a slide. *(does: a single held input)*
3. **Hold.** The player steers through the corner on the slide, bleeding and carrying speed with the drift angle. *(sees: the car's angle and the line it's drawing)*
4. **Catch.** The exit is caught cleanly and the speed carries into the next corner, or the drift breaks and the chain ends.
5. **Read back.** How clean the drift was is shown, and the player goes again.

**(proposed)** A free-roam run is endless; a scored run is 60 to 90 seconds. To settle after the first prototype.

## Systems

> Every feature, one line each, linked to its spec.

| System | What it does | Spec |
|---|---|---|
| Drift model and one-finger control | The car. The finger IS its rate of turn; the drift is momentum lagging behind, and a quadratic grip force pulling it back. **Built and approved** | `features/drift-model.md` |
| The playground | A flat plate with buildings, alleys and a ramp: the place the feel was proved in. **Built** | `features/drift-playground.md` |
| Car archetypes and stats | Per-car configs so cars feel genuinely different, plus the stat breakdown and the grip curve. **Being built** | `features/car-archetypes.md` |
| Track pieces and the endless road | Socket-to-socket pieces chosen against repetition, with a lookahead so the road cannot trap itself. **Specced, not built** | `features/track-generation.md` |
| Drift score and the multiplier ladder | Points from slip × speed × surface, and a 1–9 ladder. **Specced, deliberately not built** (`DECISIONS.md`) | `features/drift-model.md` "Score" |

## Progression

> How the player grows: levels, unlocks and gates. How long each should take is in `PACING.md`.

Not decided. The user wants the drift feel proven first (see "Open after the prototype").

## Economy

> Every currency, where it comes from and where it goes. Prices and amounts are in the config modules; this shows the shape. Each source and sink is also an analytics event (ANALYTICS.md).

| Currency | Sources | Sinks |
|---|---|---|
| | | |

## Content

> What there is to find, collect or beat (items, areas, creatures, quests), with counts.

## World

> The places in the game and how the player moves between them, in a few lines. The detail (areas, routes, named spots, the map) is in `WORLD.md`.

## Social

> What players do with or around each other: playing together, trading, competing, showing off. Server size, private servers and teleports are in `live/EXPERIENCE.md` "Multiplayer"; what brings players back is in `RETENTION.md`.

## First five minutes

The player learns how to drive. That's all that's settled: the user's words were "not too important right now, we will revisit later".

To revisit once the drifting works, beat by beat, from join to the first reward.

### Open after the prototype

The user asked for these to be written down rather than guessed at now:

- How a player is taught to drift: a tutorial, a guided first corner, or just a forgiving space to try.
- What the first reward is, and when it lands.
- Meta progression: what the player grows, unlocks or collects.
- The "big scale group" direction — what the game is beyond a single run.
- Scored runs vs. free roam, and how a run is framed and ends.
- Whether other players share a server, and what they do around each other.
- How money is made (the cosmetic-only proposal in `PITCH.md` is a placeholder).
