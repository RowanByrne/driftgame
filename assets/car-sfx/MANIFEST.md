# car-sfx

Sound candidates for the car (docs/workflow/AUDIO-PIPELINE.md). All are Creator Store audio,
used by id: nothing is downloaded or uploaded, so this folder holds only this record.

## Floor scrape (T-097)

The loop that plays while the car's floor grinds on something (a ledge, a kerb), louder the
faster it slides (`docs/game/features/car-v2.md` "Floor scraping"). Looped, 3D, on the car's
body; volume from `Config.Fx.Scrape`.

**Wired now as a placeholder:** A, chosen by its description (a long gritty metal-on-asphalt
drag) rather than by ear, since an agent's playtests are silent. **The user picks.**

| | Store id | Name | By | Length | License | Status |
|---|---|---|---|---|---|---|
| A | `9125686089` | Metal Scrape Dragging Car Hood Across Asphalt 1 | Pro Sound Effects (Roblox audio partner) | 3.8 s | Creator Store, free in any experience | candidate, placeholder in `Config.Fx.Scrape.SoundId` |
| B | `9125686374` | Metal Scrape Dragging Car Hood Across Asphalt 4 | Pro Sound Effects | 4.5 s | Creator Store, free in any experience | candidate |
| C | `9120371395` | Vehicle Door Curb Scrapes Gritty Drag Car 1 | Pro Sound Effects | 1.4 s | Creator Store, free in any experience | candidate: shorter and lighter, a kerb scuff rather than a grind |

Found 2026-11-10 with `search_asset` ("car scrape", "metal scrape loop", "metal grind drag
asphalt"). Left out: `136913781328946` "metal_box_scrape_rough_loop1" and `134321442344840`
"hl2 metal scrape loop", re-uploads of Valve's Half-Life 2 sounds by unrelated accounts (a
copyright risk, PLATFORM-RISKS.md); the "Metal Creaks Destroying A Car" set (14 to 22 s, full
of crashes and impacts, not a loop).

Notes for the pick:
- A and B are one-take recordings with "short pulling bursts" and a "deep booming impact":
  looped, the impact may be heard once a loop. If it is, C or a trimmed upload is the fallback.
- The id is one line in `src/ReplicatedStorage/Shared/Config/Fx.luau` (`Scrape.SoundId`).
