# Template

How the template and the games made from it stay in step: which files are whose, releasing the template, and bringing a release into a game. Games take the template only as releases, so a half-finished change in the template never reaches them.

## Three kinds of file

| Kind | Files | Whose | When a template update changes one |
|---|---|---|---|
| **Template-owned** | `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.claude/`, `docs/workflow/`, `tools/`, `.gitignore` | The template's. A game never edits them (AGENTS.md "Template-owned files") | The game takes the change as it is |
| **Starter files** | `docs/game/`, `docs/CLAIMS.md`, `live/`, `src/`, `README.md`, `default.project.json` | The game's, from the day it's made | If the game never changed the file, it gets the new version. If it did, it keeps its own, and the update lists the file so the game can bring over what it wants |
| **Shared** | `docs/README.md` (the template's index, with the game's own docs at the bottom), `assets/README.md`, `.gitattributes` | Both | A normal merge |

Starter files are protected only while a template update merges, by `tools\update-from-template.ps1`. A worker's branch merges them as usual, so its edits to `CONTRACTS.md` and the like are never lost.

## Releasing the template

In the template's own repo, when its `main` has changes ready for games (the user says **"release the template"**):

1. **Commit and push `main`.**
2. **Pick the version,** `template/vMAJOR.MINOR.PATCH`, from the last one (`git tag -l "template/v*" --sort=-v:refname`):
   - **PATCH:** fixes and wording.
   - **MINOR:** new docs, tools or rules; nothing a game has to do by hand.
   - **MAJOR:** a game has to do something by hand to take it. The notes say what.
3. **Tag it, with what's new as the message,** written for the user: one line per change, in plain words. Then push the tag:
   ```
   git tag -a template/v1.3.0 -m "Docs: a WORLD.md for the map" -m "LANES.md: how many lanes a PC opens"
   git push origin template/v1.3.0
   ```

Within half an hour, Rocco's Connections in every game shows the release and its notes, with a button that asks your agent to bring it in.

## Taking an update in a game

When the user says **"update from template"** (or asks from Rocco's Connections), the conductor, in `repo\`:

1. **Look first:** `powershell -ExecutionPolicy Bypass -File tools\update-from-template.ps1 -Check` says which release the game is on and lists what's newer, with each release's notes.
2. **Merge:** run it again without `-Check` (with `-To template/v1.2.0` for a release other than the newest). It needs `main`, with nothing uncommitted. It merges the release without committing, and lists the template-owned files that changed, the starter files it updated, and the starter files the game kept although the template changed them.
3. **Conflicts** happen only where the game edited a template-owned or shared file. A template-owned file takes the template's side, unless the game changed it on purpose: then keep both, and tell the user the change belongs in the template (AGENTS.md "Template-owned files"). To back out: `git merge --abort`.
4. **Kept starter files:** for each, `git diff <old release> <new release> -- <file>` shows what the template changed. Bring over what the game wants (a new section in a form, usually), and leave what doesn't fit it.
5. **Commit** as `Update from template: template/v1.2.0`, push `main`, and refresh the lanes (CONDUCTOR.md "Refresh").
6. **Report:** what's new (the notes, in a line each), what was brought into the game's own files, and anything the user has to do (a MAJOR release says).

A game is on the newest template release in its history: `git describe --tags --abbrev=0 --match "template/v*"`. Rocco's Connections shows it, and whether a newer one is out.
