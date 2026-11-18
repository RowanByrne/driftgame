# Split Feed score sounds

**Status** — Third audition, November 18, 2026. After trying the electronic shutter mix, the user asked for "more arcade-y ness, and sounds for the accumulation of sustained events too". The three samples on T-312 play the same opening, nine progress pulses, a pause in accumulation, bank, receipt and rank changes.

## Arcade sound selection

| Audition | What distinguishes it |
|---|---|
| Bit Counter | Crunchy twin ticks from a clocked noise register, with a fast ratchet at the bank |
| Chip Sprint | Bright pulse-wave arpeggios, a two-note count and a chord at the bank |
| Vector Rush | Metallic FM chirps during the count and a rising laser sweep into the bank |

While a held line is live, growth in its displayed points can sound a short progress pulse. A pause in earning points pauses the sound. Concurrent holds share a cadence limit. A settlement stops the count immediately, and a lost hold ends quietly. Score UI volume and mute cover the pulses. The approved 1.3× display and the score calculation stay as they are.

## Previous lane mix

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
