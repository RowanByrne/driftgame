# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/car-looks` | lane4 | `src/StarterPlayerScripts/Controllers/CarLooksController.luau` (new), `src/StarterPlayerScripts/Drift/CarLooks.luau` (new), `src/ReplicatedStorage/Shared/Config/CarLooks.luau` (new), `src/ServerScriptService/Tests/CarLooksTests.luau` (new), `src/ReplicatedStorage/Shared/Customization/Catalog.luau` (look fields of Paint, Underglow and Wheels only) | 2026-11-10 (T-104) |
| `agent/suspension` | lane1 | `src/StarterPlayerScripts/Drift/Model.luau`, `src/StarterPlayerScripts/Drift/World.luau`, `src/StarterPlayerScripts/Drift/Render.luau`, `src/StarterPlayerScripts/Drift/Wheels.luau`, `src/ReplicatedStorage/Shared/Config/Drift.luau`, `src/StarterPlayerScripts/Drift/Suspension.luau` (new), `src/ServerScriptService/Tests/DriftTests.luau`, `src/ServerScriptService/Tests/SuspensionTests.luau` (new), `docs/game/CONTRACTS.md` (`CarState` row only), `docs/game/features/car-v2.md` ("Rules and numbers" only) | 2026-11-10 (T-095) |
| `agent/car-entry` | lane2 | `src/ServerScriptService/Services/CarService.luau`, `src/StarterPlayerScripts/Controllers/DriftController.luau`, `src/StarterPlayerScripts/Controllers/CarCameraController.luau`, `src/StarterPlayerScripts/Controllers/CarInputController.luau`, `src/StarterPlayerScripts/Drift/RemoteCars.luau`, `src/StarterPlayerScripts/Controllers/CarEntryController.luau` (new), `src/StarterPlayerScripts/Drift/Driver.luau` (new), `src/ReplicatedStorage/Shared/Config/CarEntry.luau` (new), `src/ServerScriptService/Tests/CarEntryTests.luau` (new), `docs/game/CONTRACTS.md` (new rows for the entry remotes and driver attribute only) | 2026-11-10 (T-096) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

