# Split Feed score sounds

**Status** — Lane build for T-312. On November 18, 2026 the user picked Tape Deck and Cassette Relay on T-309 and approved their combined mix and Score UI slider on T-311.

## How it sounds

| What the driver sees | What they hear | Audition |
|---|---|---|
| A one-off score line appears | One dry click | Cassette Relay |
| The named rank rises | Two rising notes at a low tier, three brighter notes at a high tier | Tape Deck |
| A held event starts | A short mechanical latch. The points can then count up quietly. | Cassette Relay |
| A grind banks | The tape motor winds up as the line moves, then a spring-loaded thump lands as it hits the rank. | Tape Deck |
| The points reach the run total | One small receipt click | Cassette Relay |
| The named rank falls | Two falling notes | Tape Deck |

The audition runs for 6.15 seconds. It uses the existing eight cues at their original times. Playback follows the score display. SIDEWAYS and above use the brighter rank gain. Each bank has its own transfer, with the receipt at the first frame the points reach the total.

## Implementation

1. Use the original Tape Deck sheet for the two rank gains, rank drop, windup and impact. Use the Cassette Relay recipes for the event tick, opening latch and receipt. The candidate masters, source hashes, slice bounds, speeds and levels are in the project's art folder under `generated/sfx-score-tape`. Only the original Drift master needs an upload. Play the two Creator Store sources by their existing IDs, `10066942189` and `10066968815`.
2. Drive local 2D playback from accepted feed events, named-rank changes and the existing bank animation. Track each bank through windup, impact and arrival. Limit rapid repeat ticks and give the impact priority. Opening a run initializes the rank quietly. A lost hold, a repeated snapshot or a restarted run must never sound like a payout. Reduced Motion gives an immediate bank one impact.
3. Give Score UI its own slider in Sound settings. Match the existing default mix at 30% and mute the cues at zero. Tune the default below the engine and tyres during a sustained drift.

## Lane review

Exercise both rank gains, a rank drop, a held grind, a lost grind, repeated events and two overlapping banks. Compare cue counts with their visible events and check run totals. Try Reduced Motion, mute and an immediate restart while a bank is in flight. The driver makes the final mix decision by ear in the lane.
