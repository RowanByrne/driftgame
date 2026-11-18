# Split Feed score sounds

## Earlier lane mixes

On November 18, 2026 the user selected "elements of tape deck and cassette relay are really good here, use both" (T-309) and approved the eight-cue mix and slider (T-311). The hybrid audition SHA-256 is `2c1107589e12878462b481e2a0218b25455b6d8db4e681ae508a84b62f18978d`.

| Source | Owner and rights | Asset ID | SHA-256 |
|---|---|---|---|
| `tape-deck-cues.wav`, original 48 kHz stereo 24-bit PCM | Authored for Drift with seeded filtered noise, damped resonators and oscillators. No recordings, third-party material or credit requirement. Uploaded unchanged as private Audio "Drift Score Tape Deck" on 2026-11-18 under Byrned_FPS (3383554889). Roblox moderation approved. | 108094209509984 | `13addb3a6351a6f5ac5c4dcb0b77e756ad5c1c4f7dcbd76c4e6e1b1c340fcf80` |
| RBLX UI Camera (SFX) | Roblox, creator 1. Free Creator Store audio for use on Roblox, played by ID. | 10066921516 | `f1dceeac4bf1170d1d5d57a7c4837805655ee36e54a96904c0a399379dbcba36` |
| RBLX UI Back (SFX) | Roblox, creator 1. Same license. | 10066914500 | `6a2089070e64e754d444bc71a01f99ea6a0b9f345960349a651d51177a177b2d` |
| RBLX UI Delete (SFX) | Roblox, creator 1. Same license. | 10066926605 | `b21556bd5641d1f8931e6093a5087fdd6492434ed5f2bc37ea318f3bc954d1d0` |

After the first lane audition the user asked for "no plop ploop sounds - the techno y stuff was what i liked". In the new lane mix, the digital shutter, sweep and switch come from the Cassette Relay audition and the tape motor comes from Tape Deck. The first mix's Hover 03 and Select 02 cues, damped sine notes and spring thump were removed.

The Store sounds use Cassette Relay's common audition gain of 1.9345988. The Tape Deck motor has its audition gain baked in. The score mix gain is 0.24 at the default 30% slider position.

| Cue | Source | Region in seconds | Speed | Cue gain |
|---|---|---|---:|---:|
| event | Shutter | 0.145 to 0.175 | 1 | 1 |
| hold_open | Sweep | 0.025 to 0.141 | 1 | 1.3 |
| score_receipt | Shutter | 0.195 to 0.235 | 1.17 | 0.85 |
| rankLow | Shutter | 0 to 0.12 | 0.98 | 0.7 |
| rankHigh | Shutter | 0 to 0.28 | 1.12 | 0.83 |
| rankDrop | Sweep | 0.112 to 0.32 | 0.9 | 1.3 |
| windup | Tape | 2.66 to 3.045 | 1 | 1 |
| bankImpact | Switch | 0.137 to 0.315 | 0.94 | 3.15 |

Shutter uses Camera, Sweep uses Back, and Switch uses Delete.

The experience-specific grant remains pending identification of the published Drift universe. The project currently uses local Studio places. [Roblox audio permissions and usage](https://create.roblox.com/docs/audio/assets)

## Arcade count auditions, November 18, 2026

Three original candidate sheets, synthesized from oscillators and clocked noise for Drift. Each 6.55-second audition uses the same score events, nine pulses of visible point growth, a pause in earning, and a bank. Each sheet and its exact brief, regions, timeline, speeds and hashes are kept in the project's art folder under `generated/sfx-score-tape/arcade-count`.

| Candidate | Design brief | Audition SHA-256 | Master SHA-256 |
|---|---|---|---|
| Bit Counter | Crunchy, gated noise from a clocked arcade counter. A short twin ratchet marks each new point pulse. | `2d798cf3ff99c4a0c27c3496669a40870135c5c7ca21d6283c513d0ce1c06769` | `cc628721aaf2c24c35775cb7021e78fd506be2928346176632224e67b9b19202` |
| Chip Sprint | Bright square-wave arpeggios. Progress plays a short two-note chip figure and banking resolves into a chord. | `527d484b18060241696258bb26d93288b7b9f15e44b4dbf1815d26e7546a8c24` | `eaa46eaaac987a1bf0948e62d41160d0343786de1e837996c507bf6d7574998f` |
| Vector Rush | Metallic FM sidebands, stereo laser sweeps and a swept bank accent. Keep the counting figure brief and incisive. | `0a3c58118c72112482ed70db942d5e5858942e840effd528c519df135683786a` | `870717fe697ea07a89038db319daaab7d8f6be145fe225778445f4a6a8be30e5` |

The user rejected all three arcade-count sets on November 18, 2026 and asked for a retro pinball feel with 1990s eurobeat drive. Those candidate masters remain local.

## Pinball bonus auditions, November 18, 2026

Original Drift compositions and procedural sound design. The two sets use a synthesized score reel, struck metal bars, synth brass, bass and percussion with different balances. Each plays twelve distinct progress strikes across a hold, pauses when the count pauses, and resolves on the bank. The project art folder under `generated/sfx-score-tape/pinball-bonus` holds the candidate WAV masters, review audio and exact slice maps.

| Candidate | Design brief | Audition SHA-256 | Master SHA-256 |
|---|---|---|---|
| Bonus Bells | Vintage bonus reel: a solenoid advances a wheel, tuned metal chimes alternate with each score increment, and a short synth-brass cadence answers the final target. | `61adb96ba1ababe343e4fda7c6c6819c84eb5e3b479da2fbcae029437efe6429` | `d7b0413dd888e23db54fde339872b149693119300a52f44e556d0b99bcbb26b4` |
| Redline Bonus | Fast original eurobeat score phrase: each bonus step strikes a metal target, opens a detuned synth-brass stab and answers on octave bass. The bank resolves into a chord and an answering lead. | `58b3a8df495c5b089183b73b3d2282421b97eb5cea044432d5ffc81bd96f2f69` | `ca819c6bd7d4866ada052b38e654ddecff4fe2354c513d8fd68c9315e8585bab` |

## Selected production master — Redline Bonus

The user selected **Redline Bonus** on T-312 on November 18, 2026. Bonus Bells was not selected. The approved 24-bit stereo 48 kHz master, `redline-bonus-sheet.wav`, was copied unchanged. It contains sixteen original regions. Its SHA-256 is `ca819c6bd7d4866ada052b38e654ddecff4fe2354c513d8fd68c9315e8585bab`. Roblox Audio `136427165925710` is the private upload "Drift Redline Bonus" under Byrned_FPS (user `3383554889`). The published-universe grant awaits Drift's universe ID.

The audition's relative gains are baked into the recording. At the default 30% Score UI slider, all voices use a gain of 0.24 at normal speed.

| Cue | Source seconds |
|---|---|
| event | 0.07 to 0.25 |
| hold_open | 0.34 to 0.62 |
| count1 | 0.71 to 0.883 |
| count2 | 0.973 to 1.146 |
| count3 | 1.236 to 1.409 |
| count4 | 1.499 to 1.672 |
| count5 | 1.762 to 1.935 |
| count6 | 2.025 to 2.198 |
| count7 | 2.288 to 2.461 |
| count8 | 2.551 to 2.724 |
| windup | 2.814 to 3.209 |
| bankImpact | 3.299 to 3.869 |
| score_receipt | 3.959 to 4.349 |
| rankLow | 4.439 to 4.839 |
| rankHigh | 4.929 to 5.459 |
| rankDrop | 5.549 to 5.949 |
