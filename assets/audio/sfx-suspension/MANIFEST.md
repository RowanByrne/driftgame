# sfx-suspension

The car's suspension sounds (docs/game/features/car-fx.md "Suspension sounds", T-223,
docs/workflow/AUDIO-PIPELINE.md): a short clunk when a wheel's strut knocks on a bump or catches
after a drop, and one heavier thud-clunk when the car lands from a jump.

**All candidates are Creator Store audio, used by id:** free in any experience, nothing uploaded,
so this folder holds only this record. Each candidate is a **slice** of one Store file, played in
the game through `PlaybackRegion` (start and length below). The previews, outside git in
`..\art\generated\sfx-suspension\`, are those slices with a 3 ms fade in and a short fade out,
each slice brought to the same peak (-3 dBFS) so they compare fairly; the game sets each slice's
level the same way (`Gain` in `Config.Fx.Suspension`).

## Briefs

From docs/game/AUDIO.md (weighty, clean, never harsh; realistic, dry and close; no long tails).
Both are one-shots, 3D, on the car's body; mono.

- **Clunk:** well under 0.5 s, a strut or bushing knocking as a wheel hits a bump or drops and
  catches: dull, metallic-rubbery. Two or three variations, picked at random with a small pitch
  shift, so repeats don't machine-gun.
- **Landing:** one heavier, bigger thud-clunk for the car coming down off a jump: the springs
  bottoming out with the body's weight behind them.

## Clunk candidates

| | Preview | Store id | Name (Pro Sound Effects, Roblox audio partner) | Slices: start s, length s | SHA-256 of preview | Status |
|---|---|---|---|---|---|---|
| A | `clunk-A-ronk-2-9120399974.ogg` | `9120399974` | Vehicle Suspension 2 (SFX): "Metal Ronk, Creaks, Various Versions", 20.0 s | 1.827, 0.116; 3.271, 0.189; 17.848, 0.128. Dull (centroid about 750 Hz), the three at the same level | `a6aefa068984b4c12b8a97466bd233c5ae172ef6afc6f0e523bcf1a9b062eaad` | candidate |
| B | `clunk-B-ronk-3-9120400025.ogg` | `9120400025` | Vehicle Suspension 3 (SFX): "Metal Ronk, Creaks, Various Versions", 35.9 s | 3.095, 0.169; 3.636, 0.179; 4.482, 0.159. Dull (700 to 1,200 Hz); the third is 12 dB quieter in the file, so its noise is lifted with it | `e288273d3ccfbfb354647ea4623ef299eaa4e902639f0a8cc57d806b8a17eab7` | candidate |
| C | `clunk-C-hits-twists-3-9120400369.ogg` | `9120400369` | Vehicle Suspension 3 (SFX): "Hits, Twists, Creaky, Hollow Metal", 7.6 s | 3.331, 0.35; 5.683, 0.35; 6.938, 0.35. Brighter and louder (3 to 4 kHz), hollow metal, rings past 0.35 s so it is cut there | `27c7018055226d1f0cddc1eff6d4be1529ab26f2ba5c4a743637781be3425cf5` | candidate |
| D | `clunk-D-ronk-1-9120399954.ogg` | `9120399954` | Vehicle Suspension 1 (SFX): "Metal Ronk, Creaks, Various Versions", 7.1 s | 0.726, 0.289; 1.108, 0.198; 4.452, 0.176. Mixed: one bright, two dull | `a0e9b609b33b77486a3acae8838700e783dd6444ddd26fad8d368f3c2e271964` | candidate |

## Landing candidates

| | Preview | Store id | Name (Pro Sound Effects) | Slice: start s, length s | SHA-256 of preview | Status |
|---|---|---|---|---|---|---|
| A | `land-A-vehicle-impact-2-9120386657.ogg` | `9120386657` | Vehicle Impact 2 (SFX): "Body Thumps, Hits, Against Car Metal", 2.6 s | 0.304, 0.229. The file's first, loudest hit | `bdaceb2fb6e6fa164116ab5adcdd09f174c7bc52451439b882d80cda633c8ba4` | candidate |
| B | `land-B-metal-impacts-2-9116695115.ogg` | `9116695115` | Metal Impacts 2 (SFX): "Stabbing Interior Vehicle Floor, Rattling, Vibrating", 2.3 s | 0.891, 0.219. Low (about 900 Hz) | `9ca6319a5be9e99f26a5e12f5a591761289f51e1b4956a47facdf48350f0c71e` | candidate |
| C | `land-C-hits-twists-3-9120400369.ogg` | `9120400369` | Vehicle Suspension 3 (SFX): "Hits, Twists, Creaky, Hollow Metal", 7.6 s | 0.182, 0.6. The suspension set's big first hit, with some of its creak; cut at 0.6 s | `6b1476c6d4e7ec2facac70c0358c42979235815eca8f5e1fbffaea41f2b3d4be` | candidate |
| D | `land-D-metal-impacts-6-9116699196.ogg` | `9116699196` | Metal Impacts 6 (SFX): "Interior Vehicle Floor, Deep Rumbling Hits, Thudding", 2.1 s | 0.449, 0.285 | `668ee5608569a617cd6ca5e54b04166da5c8c65fe4cc7c5922ccd1e6c59db915` | candidate |

## How they were found and cut

Found 2026-11-15 with `search_asset` (Creator Store, audio): "suspension clunk", "car
suspension", "vehicle suspension", "car landing thud", "car jump landing", "car body impact",
"Vehicle Impact (SFX)", "metal clunk", "car trunk thud", "car drop thud", "shock absorber",
"pothole bump car". The store's "Vehicles - Suspension" category (Pro Sound Effects) has six
files, each a take of many knocks and creaks rather than one hit, so the candidates are single
hits sliced out of them.

The files were loaded in `DR-Lane3` (Edit) and read from Studio's content cache. Each hit was
found from its loudness envelope (a rise of 10 dB within 30 ms), started 4 ms before its rise and
ended where it fell 35 dB under its peak (45 dB for landings). The tools are in the session
scratchpad, not kept: the slice table above is the whole of what they decided.

**Left out of the search:** `vehicle_impact_heavy1` and `vehicle_rollover1` (by KumaWar2) and
"My summer car car smash/hit 4", which are named after or ripped from other games; "Car crash!",
"black mesa car crash" and the like, for the same reason; anything named after a real car or
maker (PLATFORM-RISKS.md, `assets/audio/sfx-engine/MANIFEST.md` "Left out of the search").
