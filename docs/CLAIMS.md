# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/ground-wall-sawtooth` | lent | `src/StarterPlayerScripts/Drift/GroundMeshView.luau` (how tiles are triangulated and their heights; not its use of `Mesh.Behind`, which is T-230's), `src/StarterPlayerScripts/Drift/GroundTiles.luau`, `Config/Spline.luau` (the ground mesh keys `Spacings` to `ReleaseOnFail` only), `src/ServerScriptService/Tests/GroundTests.luau` (new checks at the end only) | 2026-11-15 (T-231) |
| `agent/horizon-uphill-only` | lent | `src/ReplicatedStorage/Shared/Horizon.luau`, `src/ReplicatedStorage/Shared/Config/Horizon.luau`, `src/StarterPlayerScripts/Drift/HorizonView.luau`, `src/ServerScriptService/Tests/HorizonTests.luau`, `docs/game/features/horizon.md`, `src/StarterPlayerScripts/Controllers/DriftController.luau` (one line in `UseSpline`) | 2026-11-15 (T-232) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

