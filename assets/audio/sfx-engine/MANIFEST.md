# sfx-engine

The car's engine sound (docs/game/features/engine-sound.md, docs/workflow/AUDIO-PIPELINE.md):
our own synthesized four-cylinder, as loops at six rev points, each on and off throttle,
crossfaded in the game by `Drift/EngineSound` from the fake engine's rpm and load.

## The approved master

| File | What | SHA-256 | Status | Asset id |
|---|---|---|---|---|
| `engine-sheet.ogg` | All twelve loops in one 31.2 s mono file, 48 kHz Ogg Vorbis. Each loop sits in a 2.6 s slot, padded with a quarter second of itself on each side; the game plays each one's slice through `PlaybackRegion` and `LoopRegion` | `c75b153cdc74423dbe157050b05095d153a0910e6020cb0a7f559eb08956df7d` | **approved** by the user 2026-11-11 ("Use this set"); **uploaded** 2026-11-12 as Audio under user Byrned_FPS (3383554889) | `132857262391195` |
| `engine-sheet-regions.json` | Each loop's rev point, load and region in the sheet, in seconds. Copied into `Config.Fx.Engine.Sheets.Synth` (its `On` and `Off` ladders) | `e481915ac085ee3b374d1d42eb8f65ea7e425ec30e2a74e3648d7e82b7ddb2c5` | the master's record | |

Rev points 900, 1370, 2090, 3190, 4860 and 7400 rpm, about 1.52x apart; each loop is a whole
number of engine cycles near 2 s, made by circular convolution so it wraps without a seam
(measured: the step across the wrap is within the loop's own 99th-percentile step, at most 1.7x).
All loops are normalised to the same loudness (RMS 0.16).

## Where it came from

**Made in code on this project's PC; no recording, library, AI generation or other game is in it.**
`synth.py` models an inline four-cylinder: an exhaust pulse per firing, two firings a revolution,
uneven cylinder strengths and timing for the four-cylinder texture, through a few damped
exhaust resonances plus combustion and intake noise; off throttle the pulses are weaker and
uneven. `build_set.py` renders the twelve loops, matches their loudness and packs the sheet.
Both scripts are kept here, so the set can be rebuilt or retuned (they need Python with numpy and
soundfile). It is the game's own audio: no license, no credit.

## Candidates

Kept outside git in `..\art\generated\sfx-engine\`.

| | What | SHA-256 | Status |
|---|---|---|---|
| A | `A-synth-demo-drive.ogg`: a first-pass synthesized drive | `5b9b78e04c30d020d98909aca4f117ba26051098381180888954dbb02d03af3c` | **picked** 2026-11-11 ("A: Synthesized, ours"); became set v1 |
| B | `B-hotrod-excerpt-9114833668.ogg`: Creator Store `9114833668`, Pro Sound Effects "Hot Rod Humming Idle 2", 30 to 58 s | `aa70191fbb496367772232b5e14c6014ae20c69adfa90fb20e6dcfd6986c8f08` | rejected |
| v1 | `set-v1\`: the twelve loops, the sheet, `demo-drive.ogg` | demo `7a6d81d5a41789eb7c15fdd3d809148bcbb7c6d82eff112b0c15636a74851dea` | **approved** 2026-11-11 ("Use this set") |

Left out of the search: the store's matched rpm sets (named like `eng_acc_4756`, `exh_dcl_7815`,
`ks_lamborghini_...`), which are ripped from racing games, and anything named after a real car
or engine (PLATFORM-RISKS.md).

## Recorded loops: candidates (T-170, 2026-11-13)

Three test drives for the user to pick from by ear, kept outside git in
`..\art\generated\sfx-engine\recorded-v1\`. **Nothing here is uploaded or in the game.**

**Source of A and B:** the engine loops in "Toyota AE86 Sound Mod by PheNom107th", a sound
replacement for Assetto Corsa (`..\import\AE86 Sound Mod\`, bank SHA-256
`41a291bc65497042226c5ae5a04e45d037a8ea86e6fe83b08cc868f4e72260b3`). What is in it, and which
samples must never be used, is in `..\art\source\sfx-engine\ae86-mod\FINDINGS.md`.
**License:** none in the download. The user, 2026-11-13: "yes, permission granted". **The link
or message that grants it is not recorded yet, and nothing is uploaded until it is here.** Where
the mod's author got the recordings is not known.

| | What | SHA-256 | Status |
|---|---|---|---|
| A | `A-inside.ogg`: on throttle `on_lower` 3,261 rpm, `on_low` 5,034, `on_lowmid` 5,604, `on_midhigh` 6,384, `on_high_valve2` 7,224; off throttle the outside `idle` 1,382, `off_mid` 4,074, `off_higher` 6,636 | `a895679e5166f1930e09e87690dfe33cd7011be1db97bf7916ba0f5b4935f19c` | candidate |
| B | `B-inside-low-outside-high.ogg`: as A, with `ext_on_mid` 6,348 and `ext_on_high_exhaust` 7,124 as the top two on-throttle loops | `69d7696bec476f74a588ded62b85f4facf341ad79ab622d786964db1d5223795` | candidate |
| C | `C-todays-sound.ogg`: today's sheet (`engine-sheet.ogg` above), for comparison | `44062cf6288aa8a938e53d20317e74c81252c1ceeaf92d8e310b563a7ac4d94f` | candidate |

Made by `..\art\source\sfx-engine\ae86-mod\tools\build_candidates.py` (numbers for every loop in
`recorded-v1\candidates.json`): each loop summed to mono, taken to 48 kHz, its end crossfaded into
its start on the engine's own cycle (40 ms), and brought to the loudness of today's loops (RMS
0.16); then played through the game's own mix (`Drift/EngineSound.mix`) on the scripted drive of
the earlier demos, with a lift and coast down to idle added at the end. All three share one
listening gain, so what is louder in the game is louder in the files. Idle is 1,382 rpm in A and
B, 900 in C.
