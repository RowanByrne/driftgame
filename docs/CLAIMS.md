# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/dirt-drift-sound` | lent | `src/StarterPlayerScripts/Drift/SkidSound.luau`, `src/ServerScriptService/Tests/FxTests.luau` (its sound-count checks), `src/ReplicatedStorage/Shared/Config/Fx.luau` (skid sound block only), `assets/audio/sfx-skid-dirt/*` (new); `docs/game/AUDIO.md` (its own row in "Sounds" only), `docs/game/features/car-fx.md` (sound section only) | 2026-11-15 (T-222) |
| `agent/suspension-sounds` | lent | `src/StarterPlayerScripts/Drift/SuspensionSound.luau` (new), `src/StarterPlayerScripts/Controllers/DriftController.luau` (only the lines that make and step the new sound), `src/StarterPlayerScripts/Drift/Suspension.luau` (read-only unless a hook is needed; ask first), `src/ReplicatedStorage/Shared/Config/Fx.luau` (new block after the skid sound block only), `assets/audio/sfx-suspension/*` (new); `docs/game/AUDIO.md` (its own rows in "Sounds" only), `docs/game/features/car-fx.md` (its own section only) | 2026-11-15 (T-223) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

