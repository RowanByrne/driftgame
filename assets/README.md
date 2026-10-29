# Assets

Approved art that ships in the game, kept in git so every PC and clone has the masters. How art gets here is in docs/workflow/ART-PIPELINE.md.

## What goes here

- **Approved masters only,** about 5 MB a file at most: images, and model exports small enough. Candidates stay in `..\art\generated\`, and working files (.psd, .blend, .kra) in `..\art\source\`.
- **One folder per topic,** named for its role: `assets/<topic>/`, such as `hud-currency`, `shop-buttons` or `boat-models`. Each topic has a `MANIFEST.md`.
- **`reference/`** holds the approved style references (`docs/game/ART-DIRECTION.md`). **`marketing/`** holds the icon, thumbnails and event cards (`live/GAME-PAGE.md`, `live/CALENDAR.md`).

## Rules

- **Copied unchanged.** A master is the exact file the user picked: never re-saved, recompressed or cropped.
- **Never overwritten.** A new version gets a new file name (`-v2`), so older notes and reviews still point at what they saw.
- **An unchanged master keeps its asset id.** New pixels mean a new upload and a new manifest entry.
- **Ids live in the code's asset registry** (`docs/game/ARCHITECTURE.md` "Registries"), and in the manifest, nowhere else.

## MANIFEST.md

Each topic's manifest records every candidate and every approved master, so the history survives without chat. Copy this into a new topic:

```markdown
# <Topic>

What it's for and where it shows in the game.

## Candidates

| File (in ..\art\generated\<topic>\) | Prompt | References | SHA-256 | Status |
|---|---|---|---|---|
| <name>-01.png | (see below) | | | candidate / approved / rejected |

### <name>-01.png prompt

(the exact prompt, word for word)

## Approved

### <name>.png

- **Picked:** <date>; the user's words when they picked it
- **Master:** `<name>.png`, <width> × <height>, transparent yes / no, SHA-256 <hash>
- **Made with:** the image tool and its prompt above, or "supplied by the user"
- **Uploaded:** `rbxassetid://<id>` on <date>, by <account or group>; decoded size checked in Studio
- **Used by:** the code that shows it (`src/...`)
- **Checked:** how it was verified in game
```
