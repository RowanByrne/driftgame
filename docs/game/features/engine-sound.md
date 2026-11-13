# Feature: An engine that sounds like it's drifting

**Status:** built, for the user to hear (`T-123`, approved 2026-11-11). Step 1, our own
synthesized loops (`T-124`), was picked and approved 2026-11-11; step 2, the fake engine (`T-125`),
drives them; step 3, the layered sound (`T-129`), plays them from the uploaded sheet
`132857262391195` since 2026-11-12. Roblox moderation was still reviewing it on upload. **Owner task:** `T-123`, lane 1, `feature/drift-engine`.

## Goal

The user: *"I want to review how we do engine noise and make it much more realistic to drifting.
look up how drifting audio (specifically engine noise) works in real life and how it typically
sounds, and implement that."*

Today's engine is the reference's: one idle clip, pitched 0.7x to 2.2x by road speed across five
fake gears (`car-fx.md` "Engine sound"). Speed is all it hears, so a drift sounds like the car is
slowing down. That is the opposite of a real drift.

## How a real drift sounds

From how drifting is driven, and how racing games build engine sound (sources at the end):

1. **The revs stay high while the car is sideways.** The rear tyres are spinning faster than the
   car is moving. Engine speed follows the rear wheels, not the road, so a car can lose speed
   through a long drift while the engine sits at 5,000 to 7,500 rpm.
2. **Entry is a flare.** A clutch kick or a handbrake entry lets the engine free-rev for a
   moment. The revs jump up, and the tyres break loose as the clutch bites.
3. **The driver holds one gear through the corner,** usually second or third. No upshifts while
   sideways.
4. **Feathering the throttle** to hold the angle makes the revs wobble rather than sit still.
5. **A long drift bounces off the rev limiter:** a hard, stuttering "brap-brap-brap" at the top.
6. **The tyres hooking up at the exit** drag the revs down to match road speed, then the car pulls
   through the gears on the straight again.
7. **Lifting off** (a transition, or the end of a drift) drops the note to a softer, burbly
   overrun sound. **Downshifts are blipped:** a short rev spike on each.

Racing games get this out of **several recorded loops at fixed rpm**, crossfaded by rpm, with
separate **on-load** (throttle on) and **off-load** (throttle off) recordings, blended by load. One
clip pitched across a wide range sounds thin and squeaky at the top, as ours does at 2.2x.

## How it plays

You drive off and the engine pulls through the gears as now, but it sounds like an engine at each
rpm rather than one clip sped up. Flick into a drift and the revs flare and **stay up**. The gear
holds and the note wobbles with your corrections. An ordinary drift sits high but clearly under
the limiter; only an intense one, thrown deep with all four tyres going, hits it, and it comes off
the limiter as soon as the angle closes. Straighten out and the revs fall as the tyres grip, then it pulls through the gears
again. Press STOP or lift into a transition and you hear the off-throttle note.

## Left out

- **Backfire and overrun pops.** The user decided against a backfire on 2026-11-04 (no good
  candidate). A real drift car pops on lift-off, so it's an open question below, not built.
- **Other players' engines.** Still silent, as now (`car-fx.md` "Server and client").
- **A real throttle.** The control stays one finger (approved feel). "Throttle" here is inferred
  from what the car is doing, never a new input.
- **Turbo sounds** (spool, blow-off valve). The car is the naturally aspirated liftback.
- **Different engines per car or per garage part.** One engine sound for every car this round.
- **No change to the drive.** The rpm drives sound only; physics never reads it.

## Rules and numbers

### The fake engine (`Drift/Engine`, pure, client)

A small rpm model on top of today's gearbox, fed by the drift model's state each frame:

| What | How |
|---|---|
| Wheel speed | Road speed, plus a spin term while drifting: `SpinGain × speed × sin(slip)` |
| RPM | Wheel speed through the current gear's ratio: `ShiftRpm` at the gear's top, never under `IdleRpm`, clamped at `RedlineRpm` |
| Gear | Today's geometric gearbox, up at a gear's top and down `GearOverlap` under its bottom, but **held while drifting** and through the hook-up |
| Drift floor | **A ratchet**: in a drift the rpm takes the spin when it is higher and otherwise climbs at `DriftClimbRpm`, and falls only when the ceiling comes down on it. Measured on the real car: without it a 35° drift bleeding 15 studs/s sagged 900 rpm |
| Drift ceiling | (`T-147`) An ordinary drift's revs stop at `DriftCeilingRpm` (6,500), feathering and flare at most `FeatherRpm` over it. The ceiling rises with the slip angle from `IntenseFromDeg` (40°) to `IntenseCeilingRpm` (9,000) at `IntenseFullDeg` (60°), so the limiter is reachable from about 45°. The ceiling caps the floor too, so as the angle closes the revs come off the top while the car is still sliding |
| Engine's drift | Starts at `DriftEnterDeg` (10°) and `DriftMinSpeed`, not the model's 5°, so a straight's small corrections never flare; lasts while the model says drifting |
| Entry flare | When a drift starts, rpm jumps by `EntryFlareRpm`, then settles over `FlareSeconds` |
| Feathering | rpm wobbles by up to `FeatherRpm`, following how fast the slip angle is changing |
| Limiter | At `RedlineRpm`, rpm is cut and recovers at `LimiterHz` (the stutter). Only an intense drift gets there (the ceiling above) |
| Hook-up | Leaving a drift, the spin term eases away over `HookUpSeconds` |
| Load | 1 on throttle (the model's eased throttle), 0 under STOP, past 90° of slip, through a flick (sideways one way then the other inside `TransitionWindowSeconds`), for `ShiftLiftSeconds` at an upshift, and in a limiter cut |
| Downshift blip | Each downshift adds a short `BlipRpm` spike |

Starting values are set by ear in the lane and written into `Config.Fx.Engine`. Until the loops
land, the rpm drives today's single clip: pitch `MinPitch` at idle to `MaxPitch` at the redline,
volume down to `OffLoadVolume` off throttle. The F3 readout shows rpm, gear, throttle, DRIFT and
LIMITER.

### The sound (`Drift/EngineSound`, rebuilt)

- **Three to four rpm loops** (around idle, mid, high, near-redline), each from on-load and
  off-load recordings where the store has them. Crossfaded by rpm, each pitched only a little
  around its own rpm, never past about ±25%.
- **Load crossfades on-load and off-load.**
- **The limiter** is the rpm model's stutter, heard as the note cutting in and out, plus a
  volume dip.
- **Same mix:** the squeal stays on top. The engine bed's level is unchanged (`AUDIO.md` "Mix").
  The direction stays weighty, clean, never harsh.
- Nothing created or destroyed while driving. All the loops play always and only their volumes
  move, so no loop ever restarts in your ear.

### Next: recorded loops from the AE86 sound mod (`T-169`, planned 2026-11-13)

The user, 2026-11-13: switch the engine from our synthesized loops to the recorded loops in the
"AE86 Sound Mod" (`..\import\AE86 Sound Mod\`), which they have permission to reuse ("yes,
permission granted"). Everything measured about the mod is in
`..\art\source\sfx-engine\ae86-mod\FINDINGS.md`; the author's tuning in `author-recipe.json`
beside it. Nothing is uploaded before the user picks a set by ear, and nothing until the
permission's link or message is in the manifest.

**Two ladders.** The engine sound plays an **on-throttle ladder** and an **off-throttle ladder**,
each crossfaded by rpm on its own, and load crossfades between the two. The mod's on and off loops
sit at different revs and there are fewer off than on, so today's one-to-one pairs cannot hold them.
The current synthesized sheet must come out **exactly** as today in the new shape: the same volume
and playback speed for every loop at the same rpm and load (checked by a test over a grid of rpm and
load), so the switch is built and checked before the pick.

**Built (`T-171`, 2026-11-13).** `Config.Fx.Engine.Sheets` holds each sheet with its own `On` and
`Off` ladder (a rev point, start and length per loop), and `Config.Fx.Engine.Sheet` names the one
that plays: switching sound is that one line. `EngineSound.mix` writes the on ladder's loops first,
then the off ladder's. Checked in `EngineTests` against the old mix, frozen in the test: 106,740
points of rpm (200 to 9,600), load and limiter cut, 1,280,880 loop values, and the largest
difference in volume and in playback speed is exactly 0.

**The candidates**, rendered offline through the game's own mix, on the same scripted drive as the
earlier demos, played on the card:

| Set | On-throttle ladder (measured rpm) | Off-throttle ladder |
|---|---|---|
| A: inside | `on_lower` 3,261 · `on_low` 5,034 · `on_lowmid` 5,604 · `on_midhigh` 6,384 · `on_high_valve2` 7,224 | outside `idle` 1,382 · `off_mid` 4,074 · `off_higher` 6,636 |
| B: inside low, outside from about 6,300 | `on_lower` 3,261 · `on_low` 5,034 · `on_lowmid` 5,604 · `ext_on_mid` 6,348 · `ext_on_high_exhaust` 7,124 | as A (the outside set has no usable high off-throttle loop) |
| C: today's synthesized sheet | as now | as now |

- **Revs are the measured ones** from FINDINGS.md, not the author's (2 to 5 % high), so two loops
  crossfading sit at the same pitch.
- **One loop per rev point:** `on_lowmid` over `on_mid_power` (cleaner wrap), `off_higher` over
  `off_high` (cleaner wrap), `on_high_2` left out (240 rpm from `on_midhigh`). `on_high_valve2` is
  thin and 6 dB down: brought up to the others' loudness, and dropped for `on_high_2` if it still
  sounds weak.
- **Never used:** `high_off_ex` (clipped), the inside `idle` (no steady pitch), and the eight Assetto
  Corsa stock samples FINDINGS.md lists, which are never extracted at all.
- **Idle:** the outside idle sits at 1,382 rpm and the game idles at 900, so `IdleRpm` rises to
  match. Rpm drives sound only, so the drive doesn't change. Its click where it repeats gets a
  crossfade. If it sounds wrong, the alternative is offered on the card.
- **Low revs:** nothing sits between the idle and 3,261 rpm on throttle, so pulling away pitches
  `on_lower` further than the ±25 % above. Accepted; the user hears it in the candidates.

**After the pick:** the sheet is built mono, each loop cleaned where it repeats, at the same
loudness as today's loops so the mix level doesn't move (bright loops tamed by ear: "weighty,
clean, never harsh"). It's recorded in the manifest with the permission, uploaded **private as the
game's own audio** with a name and description that say nothing of the car, the mod or the game it
came from, set in config, and checked in a lane with sound on. Today's sheet `132857262391195`
stays one config line away.

**Left out:** backfires and pops, gear-change sounds, transmission whine, the `metallic` layer and
the `power` one-shots, other players' engines, an engine per car, any change to the drive. The mod's
backfire and gear-change samples are follow-ups to suggest.

**Risks:** Roblox checks every upload for copyright: if it's refused or flagged, stop and tell the
user, never retry with altered audio. Where the mod's author got the recordings is not known. Using
mod audio is the user's exception to this spec's "Platform risks" rule below and to
`AUDIO-PIPELINE.md`'s sources (DECISIONS.md, 2026-11-13).

## Server and client

Client only, local car only, as today. No remotes, no data.

## Contracts

None. New config numbers in `Config.Fx.Engine`. `Drift/Engine` is a new client module.

## Analytics

None.

## Monetization

None.

## Platform risks

**Audio copyright** (`PLATFORM-RISKS.md`): only Creator Store audio that is free in any
experience, or the user's own recordings. No sound ripped from a game or video, and none named
after a real manufacturer's car (the same rule as the backfire search).

## Art and sound

New engine loops, found on the Creator Store and **picked by the user by ear** from candidates on
the card (`AUDIO-PIPELINE.md`). Kept outside git with the other candidates
(`..\art\generated\sfx-car\`), and listed in `AUDIO.md` once picked. If the store has no set
that matches across rpm, the fallback is one good high-rpm on-load loop plus one off-load loop,
which already beats today's single idle clip.

## Testing

- **Unit tests** (`EngineTests`): rpm stays high through a slowing drift; the gear never changes
  while drifting; the limiter cuts at `RedlineRpm` and recovers; hook-up brings rpm back to road
  speed; a downshift blips; load is 0 under STOP; an ordinary drift (25 to 35°) never cuts, an
  intense one (55°) does, and straightening out stops the cuts within 0.3 s.
- **Measured in a lane:** a scripted drive (straight, a long drift, an exit) logging rpm, gear,
  load and each loop's volume ten times a second, written to the card.
- **Ear:** the user's, in a lane, before it merges.
- **The ceiling, measured (`T-147`),** before and after: a 30° drift held 6 s cut the limiter 16
  times from 3.5 s in, now never (tops at 6,518 rpm); a 25 to 35° wobble from 100 studs/s cut 45
  times from 0.1 s, now never (6,685). A 55° drift still cuts (22 times in 3 s, stutter unchanged at
  7.3 a second). Closing from 55° to 0 over 1 s, the last cut came 0.98 s after the angle began to
  close, now 0.08 s. On the real model, a gentle finger first hit the limiter at 17° of slip, now
  at 48°. An entry from low revs flares exactly as before (+1,390 rpm).

## Open questions

- **Overrun pops on lift-off.** Realistic for a drift car, but it reverses the 2026-11-04 "no
  backfire" call. Left out unless the user wants it.

## Sources

- [Clutch kicking explained](https://teamoneil.com/blog/clutch-kicking-explained)
- [Drifting techniques: clutch kick to flick](https://slrspeed.com/blogs/news/drifting-techniques-explained-clutch-kick-to-flick)
- [How to clutch kick](https://engineerfix.com/how-to-clutch-kick-the-technique-explained/)
- [Loop-based car engine design with Wwise, part 2](https://www.audiokinetic.com/en/loop-based-car-engine-design-with-wwise-part-2)
- [Engine sound modeling: from sampling to granular synthesis](https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise)
- [Vehicle engine design: Project CARS, Forza 5 and REV](https://designingsound.org/2014/08/11/vehicle-engine-design-project-cars-forza-motorsport-5-and-rev/)
