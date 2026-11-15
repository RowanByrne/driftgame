# sfx-skid-dirt

The sliding sound for a car drifting **off the road**: on grass, gravel and dirt, in place of the
tarmac squeal (T-222, `docs/game/features/car-fx.md` "Skid sound").

## Brief

A **loop** of tyres scrubbing sideways over loose dirt and gravel: crunch and hiss, **no squeal**.
3D, on the car's body, mono in effect. It loops and its volume follows the lateral slide speed exactly
as the tarmac squeal's does (`Config.Fx.Skid`), so it must wrap without a click. From `AUDIO.md`:
weighty, clean, never harsh; realistic, dry and close; no long tails.

## Candidates (2026-11-15)

All three are **Creator Store** audio, free in any experience, used **by id**: nothing is uploaded and
there is no master in git. The store files and the previews are outside git in
`..\art\generated\sfx-skid-dirt\` (store files in `raw\`).

**The previews** (`A-…ogg`, `B-…ogg`, `C-…ogg`, 10 s each) play each clip the way the game would: one
drift whose lateral slide rises to 110 studs/s and falls again, through the squeal's own curve
(`MinVolume` 0.08 to `MaxVolume` 0.40 across 90 studs/s, lerped at 1 /s, master 0.85), with the clip
looping from its start so its seam falls where it would in game. Each is **level-matched to the
tarmac squeal** (same RMS), the way its own volume number in `Config.Fx` would set it, so they compare
at equal loudness. `ref-tarmac-squeal-today.ogg` is today's squeal through the same curve. Rendered by
a throwaway script (ffmpeg and numpy), not kept.

Measured on the store files, mixed to mono: steadiness is the spread of 100 ms loudness (lower is
steadier); tonality is the tallest spectral line over the mean, 500 to 6000 Hz (the tarmac squeal is
26.8 dB: a squeal is a tall line, a scrub is noise); the seam is the jump at the wrap against a typical
sample step.

| | Store id | Name, creator | Length | Steadiness | Tonality | Seam | Level match | Store file SHA-256 | Preview SHA-256 | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| A | `136328830019913` | "Gravel Skid Loop v2", f1rstn1ghtkn1ght. Described as "tyres sliding sideways on gravel, loop" | 7.30 s | 0.14 | 15.2 dB | 1.1x | +3.6 dB | `8C46A8A0DF58E0AC2C7DE020DFF742041BCB349B3F3DD84AA30DC2490FC889D4` | `AE46AF144C6C1001A10EB941EB17AA2832F69FB0FF8391A0BEE90722F2EF900D` | rejected |
| B | `113023380554627` | "dirt", clean_chips0. Stereo. Its loudness swells and dips more than A's | 7.65 s | 0.38 | 16.3 dB | 1.8x | +13.1 dB | `5C2DD3AA02C7A1FB0215346558D07E260AF1F3D15340C907FC744A635F313BEC` | `3AB546108C56BD31EAE7667F4C01759D49945D12E251395480C34A4E5D389DA6` | **approved** |
| C | `134976342848304` | "WheelsSandstone", shzexi9e3ca. A wheel rolling on rough ground more than a slide; its seam jumps (10.7x) and its tail is quieter than its head, so a faint tick each 3.7 s is possible | 3.68 s | 0.26 | 13.0 dB | 10.7x | +14.8 dB | `02092695D39196B2F915EE4CDBBF9D6A175448BC9A8A2C9F01D3CE0FE76210EE` | `AB3DB0D40EA5D4D3476A31919882BC56A9CA721901275D457AC0A9A8BD9A2174` | rejected |

Reference: today's squeal, `124978127809544` ("tyre_slide", knightracers), preview SHA-256
`3BA7085273E5C05BB95CAAF4173E089600C98E7630F34030C729C945D271412C`.

## Left out of the search

- **"skid_gravel1" to "skid_gravel4"** (`122588557195414`, `80915369421839`, `95752358949687`,
  `136909405449939`, Robloxianr6o6c6m1y): steady, loud loops, but four numbered files of exactly the
  same length (3.18 s) from an anonymous account is the shape of a racing game's sound bank, and where
  they came from is not known (`PLATFORM-RISKS.md`).
- **Squeals:** "skid_loop_01" (`4842084452`, tonality 27.0 dB, as tonal as the tarmac squeal), "Tire
  dirt skid/screech" (`103723782639124`), Pro Sound Effects' "Skids Tire Screeches On Dirt Pavement"
  set (squeals, and one-shots).
- **One-shots,** not loops: "tireskidhighfriction - tire skid dirt" (`116688724116942`, 1.8 s, fades
  to nothing), "brakeGravel" (`136296905927842`), Pro Sound Effects' gravel pass-bys and "Gravel
  Slide 1" (fade in and out, uneven).
- **Too quiet to use:** "slideeeeee" (`76569823275011`, -37.6 dBFS).

## The pick

**B, "dirt" (`113023380554627`), picked by the user on 2026-11-15.** Their answer on the card: "B: Loose
dirt". A and C are rejected. A Creator Store pick, so there is no master in git and nothing is
uploaded: the id is in `Config.Fx.Skid.SoundIds.dirt`.

**Its level in game, measured:** `ClipVolume.dirt` = **3.2**, not the 4.5 that matches the squeal's
average loudness. B swells and dips (its 100 ms loudness spans 15 dB), and at 4.5 its loudest 100 ms
at the top of the curve is -15.9 dBFS, over the engine bed (-17.4 dBFS: loops at RMS 0.16, volume
0.84). At 3.2 its loudest moment is level with the squeal's (-18.8 dBFS), its average 3 dB under the
squeal's, and its sample peak -6.8 dBFS. The instance volume tops out at 0.34 x 3.2 = 1.09, far under
Roblox's cap of 10.
