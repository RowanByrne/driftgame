# Split Feed score sounds

**Status** — Lane build for T-312. On November 18, 2026 the user picked Tape Deck and Cassette Relay on T-309 and approved their combined mix and Score UI slider on T-311.

## How it sounds

| What the driver sees | What they hear | Audition |
|---|---|---|
| A one-off score line appears | A single clipped digital shutter tick | Cassette Relay |
| The named rank rises | A short shutter burst at a low tier, the full ratchet from SIDEWAYS upward | Cassette Relay |
| A held event starts | A short electronic sweep as the line opens | Cassette Relay |
| A grind banks | The tape motor spools up and a sharp electronic switch lands at the rank | Tape Deck and Cassette Relay |
| The points reach the run total | A small high tick from the shutter tail | Cassette Relay |
| The named rank falls | A descending filtered sweep | Cassette Relay |

After hearing the first lane mix, the user asked for "no plop ploop sounds - the techno y stuff was what i liked". The second mix uses the previously auditioned mechanical and electronic textures. Each bank follows its own transfer into the rank and across to the total.

## Implementation

1. Play the original Tape Deck recording for the motor. Use the original Cassette Relay shutter, sweep and switch by their Creator Store IDs. The source manifest records each slice. All eight cues follow the live score display.
2. Drive local 2D playback from accepted feed events, named-rank changes and the existing bank animation. Track each bank through windup, impact and arrival. Limit rapid repeat ticks and give the impact priority. Opening a run initializes the rank quietly. A lost hold, a repeated snapshot or a restarted run must never sound like a payout. Reduced Motion gives an immediate bank one impact.
3. Give Score UI its own slider in Sound settings. Match the existing default mix at 30% and mute the cues at zero. Tune the default below the engine and tyres during a sustained drift.

## Lane review

Exercise both rank gains, a rank drop, a held grind, a lost grind, repeated events and two overlapping banks. Compare cue counts with their visible events and check run totals. Try Reduced Motion, mute and an immediate restart while a bank is in flight. The driver makes the final mix decision by ear in the lane.
