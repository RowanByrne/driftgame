# Audio

How this game sounds, and every sound in it. The direction is the user's, set in Production before the first sounds are made (docs/workflow/WORKFLOW.md). Every sound is checked against it, and every generation prompt is built from it (docs/workflow/AUDIO-PIPELINE.md). Replace each prompt with the answer.

## Direction

Set 2026-11-04, with the user's approval of the `car-fx.md` plan. These are the first sounds in
the game, so approving that plan set the direction.

### Pillars

**Weighty, clean, never harsh.**

- **Weighty:** the engine is felt more than heard. It sits under everything and gives the car mass.
- **Clean:** nothing muddy and nothing clipping. A drift is a lot of sound at once and it has to stay legible.
- **Never harsh:** nothing shrill enough to wear a player out over a ten-minute session. The squeal is the loudest thing in the game and it still has to be bearable the fiftieth time.

### References

| Reference | What we take |
|---|---|
| The reference game (`PITCH.md` "Games we borrow from") | How the sound is *driven*, not how it sounds: one engine loop pitched by faked gears, one squeal loop whose volume is the slip angle. Its own audio never comes near this game (`PLATFORM-RISKS.md`) |
| Real cars | Realism. The drift model is a simulation and the sound should agree with it rather than cartoon it |

### Music

**Not decided.** There is no music in the game and no decision about it. It waits on what a run is
(`PITCH.md` is still Draft).

### Sound effects

- **Style:** realistic, not cartoon. The drift model is a simulation and the sound agrees with it.
- **Feel:** dry and close. No long tails — a tail on a looping sound is a smear, and both of the first two sounds loop.
- **Rewards and rarity:** nothing to sound better yet; there is no score and nothing is sold.

### UI sounds

> Clicks, opening and closing, buying, errors: one family that sounds like it belongs together.

### Ambience

> The background of each place: wind, birds, water, a crowd.

### Voice

> Voice lines, if any: text-to-speech, recorded, or none.

### Mix

**The squeal sits on top, the engine under it, everything else under both.** A player with the sound
off loses information but not the game — the drift is already readable from the car, the camera and
the tyre marks.

**That is the intent, and the numbers no longer match it** (T-083, 2026-11-08). The user called the
squeal too loud twice, so its peak is now 0.85 × 0.40 = **0.340**, while the engine bed plays flat at
**0.45**. The squeal is under the engine at every moment. It is left that way deliberately rather
than quietly put back: **if the drift stops reading over the engine, the engine comes down.**

**The player's levels sit on top of this mix** (T-256): Settings has a Sound tab with one slider per
category, 0 to 100%, kept for the session on this device (`Drift/SoundLevels`, `SETTINGS.md`).
**30% is this mix exactly** (the user, 2026-11-16): each category is a `SoundGroup` in `SoundService`
(`SoundLevel_<Category>`) at `level / 30`, and a sound plays at its own volume times its group's. So
the default 30% is 1x, 15% half, 0% silent and 100% about 3.33x, and a slider never changes
`Config.Fx`:

| Category | Sounds in it |
|---|---|
| Music | None yet. A music sound joins with `SoundLevels.apply(sound, "Music")` |
| Tire squeal | The tarmac skid clip (`Drift/SkidSound`) |
| Off-road drift | Every other skid clip: the dirt slide, played on grass, dirt and gravel |
| Suspension | The clunks, catches and landing slam (`Drift/SuspensionSound`) |
| Engine | Every engine loop, layered or the single clip (`Drift/EngineSound`) |

**Headroom at 100%** (measured in `DR-Lane2`, T-256). Roblox caps a `Sound`'s and a `SoundGroup`'s
`Volume` at 10 each, not their product, so nothing is capped by the slider; the loudest each sound
gets from the code today, and at 100%:

| Sound | Today's peak | At 100% |
|---|---|---|
| Engine, one layer (recorded sheet) | 0.84 | 2.80 |
| Tyre squeal, tarmac | 0.34 | 1.13 |
| Off-road slide (dirt clip, `ClipVolume` 3.2) | 1.09 | 3.63 |
| Suspension clunk, slices 1 / 2 / 3 (`Gain` 2.6 / 9.7 / 22.3) | 1.33 / 4.95 / **10** (wants 11.37, already held at Roblox's 10 today) | 4.42 / 16.5 / 33.3 |
| Landing | 0.54 | 1.81 |

Whether 3.33x clips on a speaker can't be measured in Studio (the legacy `Sound` has no output
meter). The gains are there because those files are quiet, so the clunks are not louder than the
rest in the ear; the third clunk slice is the one already at Roblox's per-sound limit before any
slider.

## Sounds

Every sound in the game. Status: candidate, approved, uploaded, in game.

The first two were picked by the user on 2026-11-04 from Creator Store candidates, played to them on
the card. **Both are used by id and nothing is uploaded**, so there is no master and no manifest:
Creator Store audio is licensed for use in any experience (`AUDIO-PIPELINE.md`). The candidates that
were not picked are in `..\art\generated\sfx-car\`, outside git.

| Sound | Plays when | Registry name | Asset id | Source and license | Status |
|---|---|---|---|---|---|
| Engine loop | Always, while a car exists. Pitched 0.7x to 2.2x across five faked gears by road speed (`features/car-fx.md`) | `engine` | `5015124019` | Creator Store, "Car idle" by 6ifqi. Free in any experience, nothing uploaded. Measured loading in `DR-Lane2`: 4.638 s | In game (`Drift/EngineSound`, T-064) |
| Engine, layered | Always, while a car exists: twelve slices of one file on two ladders, on and off throttle: on each, the two loops either side of the fake engine's rpm crossfaded, and the load crossfades the ladders (`features/engine-sound.md`). Without the id, the single "Car idle" clip above follows the same rpm | `engine` (`Config.Fx.Engine.Sheets.Synth`, named by `Sheet`) | `rbxassetid://132857262391195` (user Byrned_FPS, 2026-11-12) | **Ours**: synthesized in code (`assets/audio/sfx-engine/`), no license, no credit. Picked and approved by the user 2026-11-11 | Approved; uploaded. **Replaced by the recorded set 2026-11-13**, and one config line away (`Sheet = "Synth"`) |
| Engine, recorded (set B) | Always, while a car exists: eight slices of one file on two ladders, five loops on throttle and three off, recorded inside the car low down and outside it from about 6,300 rpm up (`features/engine-sound.md` "Next") | `engine` (`Config.Fx.Engine.Sheets.Recorded`, named by `Sheet`) | `rbxassetid://126307015260351` (user Byrned_FPS, 2026-11-13) | **A sound mod's recordings, reused on the user's word that its author permits it**; no link or written message in the record (`assets/audio/sfx-engine/MANIFEST.md`). Picked by ear by the user 2026-11-13 | Picked; uploaded, in use (T-170). Moderation was reviewing it on upload |
| Tyre squeal, tarmac | **Only while a tyre is actually sliding** (T-083): silent unless the car is grounded, above `MinSpeed` and drifting, then its volume is the **lateral slide speed** — `speed × sin(slip)`, how fast the contact patch is scrubbing across the road — lerped from `MinVolume` 0.08 to `MaxVolume` 0.40 across 90 studs/s of it. A slow pivot is quiet; a fast slide is loud. The clip is still never restarted (it runs at volume 0 between drifts), so its loop seam is never re-heard | `skid-tarmac` | `124978127809544` | Creator Store, "tyre_slide" by knightracers. Free in any experience, nothing uploaded. Measured loading in `DR-Lane2`: 2.996 s. **Kept over three longer candidates by the user on 2026-11-08** (`DECISIONS.md`) | In game (`Drift/SkidSound`, T-064, T-083) |
| Tyre slide, off-road | **Only while a tyre is sliding on grass, gravel or dirt,** in place of the tarmac squeal: the same gate and the same lateral-slide-speed curve, at its own level (`ClipVolume` 3.2, measured so its loudest swells sit level with the squeal's, under the engine). Both clips run while the car rolls and a change of ground crossfades them over 0.25 s, so neither is restarted | `skid-dirt` | `113023380554627` | Creator Store, "dirt" by clean_chips0, 7.65 s. Free in any experience, nothing uploaded. **Picked by ear by the user on 2026-11-15** over two other loops ("B: Loose dirt"; `assets/audio/sfx-skid-dirt/MANIFEST.md`) | In game (`Drift/SkidSound`, T-222) |
| Suspension clunk | A wheel's strut shoved up by a bump or kerb, or catching after a drop: one of three slices at random, a little faster or slower, louder for a taller step and a faster car; a 0.18 s wait per wheel (`features/car-fx.md` "Suspension sounds") | `Config.Fx.Suspension.Clunks` | `9120399954` (slices at 0.726, 1.108 and 4.452 s) | Creator Store, "Vehicle Suspension 1 (SFX)" by Pro Sound Effects. Free in any experience, nothing uploaded. **Picked by the user 2026-11-15 ("D: mixed")** from four (`assets/audio/sfx-suspension/MANIFEST.md`) | In game (`Drift/SuspensionSound`, T-223) |
| Landing clunk | The car touching down after 0.25 s or more with no wheel down, by how fast it fell; it replaces the clunks for 0.35 s | `Config.Fx.Suspension.Landing` | `9125661444` (slice at 0.127 s, 0.5 s long) | Creator Store, "Metal Bangs Shaking Large Aircraft Fuselage 3 (SFX)" by Pro Sound Effects. Free in any experience, nothing uploaded. **Picked by the user 2026-11-15 ("F: massive clunk")**, after turning down a first four ("None of these") | In game (`Drift/SuspensionSound`, T-223) |
| Backfire pop | — | — | — | — | **Not having one.** The user's call, 2026-11-04: the only candidate on the store that was not named after a real manufacturer ran 0.9 s, about twice as long as a pop wants, and several in a row would smear. The backfire stays specced in `features/car-fx.md` and unbuilt |

## Credits

Sounds whose license asks for a credit, and the line the game shows.

| Sound | Credit |
|---|---|
| | |
