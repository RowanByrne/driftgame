# Split Feed score sounds

The user approved Redline Bonus in lane 1 on November 18, 2026 (T-312). Tuned metal targets, detuned synth brass, octave bass and a short bank chord give the score its pinball and eurobeat sound.

| Score display | Sound |
|---|---|
| One-off line appears | Short metal target hit |
| Held line opens | Score reel and brass opening |
| Held points climb | The next brass-and-bass hit in the original eight-step phrase |
| Named rank rises | Short rising phrase, extended from SIDEWAYS upward |
| Held line moves into the rank | A windup resolves onto a bank chord |
| Bank reaches the total | A final chime answers the bank chord |
| Named rank falls | A descending musical figure |

The count follows increases in each live line's rounded point total. Overlapping events share one musical phrase, advancing at most one note per eighth-note beat at 160 BPM under continuous growth. A pause in scoring pauses the phrase. The next increase resumes it. When all holds finish, the next hold starts at the first note. Repeated values, losses, summaries and fixtures stay quiet. A cancelled hold cuts off its current note. Reduced Motion plays one immediate bank impact.

Playback is local to the driver's Score UI sound group. The Settings slider defaults to 30%, and zero mutes the group. The score engine owns the points. The UI and audio follow its live feed, and an individual bank's receipt follows the displayed transfer.

## Lane review

Build a sustained event, pause earnings, let it grow again, then bank. Compare two overlapping holds, a lost hold, a run restart and Reduced Motion. Try Score UI at 0% and 30%. The original selected master and the exact cue regions are in the sound manifest and `Config.Fx.ScoreUI`.
