# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/showroom-touge` | lane4 | `src/ServerScriptService/Tools/Showroom.luau`, `docs/game/WORLD.md` | 2026-11-06 (T-068) |
| `agent/road-seams` | lane3 | `src/ReplicatedStorage/Shared/Road/Builder.luau`, `src/ReplicatedStorage/Shared/Config/Road.luau`, `src/ServerScriptService/Tests/RoadTests.luau`, `docs/game/features/road-elevation.md` | 2026-11-06 (T-066) |
| `agent/wheel-fx-2` | lane2 | `src/StarterPlayerScripts/Drift/Wheels.luau`, `src/ReplicatedStorage/Shared/Config/Fx.luau`, `src/ServerScriptService/Tests/FxTests.luau`, `docs/game/features/car-fx.md` | 2026-11-06 (T-062) |
| `agent/unstick` | lane1 | `src/StarterPlayerScripts/Drift/Model.luau`, `src/ReplicatedStorage/Shared/Config/Drift.luau`, `src/ServerScriptService/Tests/DriftTests.luau`, `docs/game/features/drift-model.md` | 2026-11-06 (T-074) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

