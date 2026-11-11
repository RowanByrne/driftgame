# Feature: Score in the endless run

**Status:** specced, waiting for the user's OK (`T-117`). **Owner task:** none yet.

## Goal

The endless run has no reason to drive it (`endless-run.md` "Left out"). The user asked for one:
*"ok lets do a bigger thing: adding score to endless mode."* Drifting earns points, holding a drift
climbs a multiplier ladder, and a run ends with a total to beat.

## How it plays

1. Press **START ENDLESS RUN**. A score panel appears at the top centre, under the run button:
   the score (0), the multiplier (x1) and a thin bar that fills toward the next rung.
2. **Drift.** While the car is sideways and moving forward, points pour in. They come faster the
   more sideways and the faster you are. Their rate is multiplied by the current rung.
3. **Hold it.** Drifting fills the bar; a full bar is the next rung, up to **x9**. Driving straight
   drains the bar, and below empty you drop a rung. The higher the rung, the faster it drains.
4. **Basic scoring only** (the user, on the plan: *"don't do the wall hit yet. for now just basic
   scoring."*). Hitting a wall or falling off costs nothing of its own; the ladder simply drains
   while you are not drifting. The score already earned is never taken away.
5. Press **END RUN**. The panel shows the run's final score, and your best this session, for a
   few seconds, then hides. The next run starts at 0.

## Left out

- **Saving your best between sessions, and leaderboards.** Both need the server to trust a
  score, and saved player data. They are the next step if the user wants them.
- **Analytics.** The run's events (start, end, score) come with saving, when the server first
  hears a score.
- **Penalties and bonuses.** No cost for a wall hit or a fall, and no reverse-drift or air-time
  bonus (`drift-model.md` "Score" has their maths). Added later, one at a time, if wanted.
- **Score anywhere but the endless run.** The track and the playground stay unscored.
- **Any reward for score.** No currency, unlocks or progression (`PITCH.md`: meta progression is
  undecided).
- **Final art and sound.** Programmer UI; no score sounds yet.
- **Other players' scores.** Each player sees their own.

## Rules and numbers

The maths is the reference's, as read off its decompile and written down in `drift-model.md`
"Score". Its numbers move into `Shared/Config/Score.luau`, with those starting values:

```
base       = |slipAngle| * speed * surfaceScore * ScoreRate * dt
score     += base * multiplier
progress  += clamp(base * ProgressRate - (grounded and MultiplierDecay * multiplier * dt or 0),
                   -MaxProgressDown * dt, MaxProgressUp * dt)
progress > 1           -> multiplier += 1 (to MaxMultiplier), progress -= 1
progress <= MinProgress -> multiplier -= 1 (to 1), progress += 1 - MinProgress
```

Scored only while slip ≥ `MinSlipAngleForDrift` and the car makes forward progress.

The reference's bonus numbers (`ReverseDriftBonus`, `AirTimeBonusMin`) are not used yet. Ours:

| Number | Start | What it does |
|---|---|---|
| `SummarySeconds` | 5 | How long the final score shows after END RUN |

The score is a whole number on screen; the engine keeps it as a float.

## UI

One new screen, `Drift/ScoreHud`, added to `UI-INVENTORY.md`. Programmer art (UI.md):

- **Top centre, under the run button:** the score in large digits, `x3` beside it, and a bar
  under both for the rung's progress. Hidden outside a run.
- **Run summary:** `RUN SCORE 48,210` and `BEST 61,004` in place of the live score, for
  `SummarySeconds` after END RUN.
- Not `Active`, so it never takes a press from the steering pad, and below the run button's
  `DisplayOrder` 15.

## Server and client

**All on the client this time.** The car is driven on the client, so the slip and speed
are there already, and nothing is saved or shared, so there is nothing for the server to trust
yet. When saving or leaderboards come, the server will receive the score at run end and bound it
(points a second against the run's time).

A run starting and ending is already on the client (`Drift/RoadHud` sends `RoadRun`, and the
state line says which); the score listens to that.

## Contracts

- New config `Config.Score`.
- New client module `Drift/Score`: `new()`, `Step(dt, state)`, `Reset()`,
  `Get() -> { score, multiplier, progress, best }`.
- No remotes, data keys or attributes.

## Analytics

None in this step ("Left out").

## Monetization

None.

## Platform risks

None: no paid items, no player text, no outside assets.

## Art and sound

None, placeholder UI only.

## Testing

- **Unit tests** (`ScoreTests`): the ladder climbs under a steady drift and drains on a straight;
  it never passes x9 or drops under x1; nothing scores below `MinSlipAngleForDrift` or going
  backward; `Reset()` zeroes the run and keeps the best.
- **Playtest in a lane:** a run started on a fixed seed, driven by the Studio drive helpers. Read
  `Score:Get()` each second: the score rises only while sliding, the multiplier climbs to at
  least x3 on a held drift and drains on a straight, and END RUN shows the summary
  and hides the panel.

## Open questions

- Whether the `fallback` numbers (`MaxMultiplier`, the ladder's rates) feel right.
  They were not in the decompile; the user tunes them by driving.
