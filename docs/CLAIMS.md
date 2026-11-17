# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/ground-opaque` (T-276) | borrowed | `src/StarterPlayerScripts/Drift/GroundMeshView.luau`, `Drift/GroundTiles.luau`, `Drift/GroundDetail.luau`, `Drift/MeshBudget.luau`, `src/ReplicatedStorage/Shared/Road/GrassTexture.luau`, `Shared/Config/Spline.luau` (all but its `Tarmac` and `Gravel` tables and T-278's lines), `src/ServerScriptService/Tests/GroundTests.luau` | 2026-11-17 |
| `agent/road-range` (T-278) | borrowed | `Shared/Config/Spline.luau` (only `Mesh.Ahead`, `AheadDefault`, `AheadTouchDefault`, `Behind`, `BehindDefault`, `BehindTouchDefault` and their comments), `docs/game/SETTINGS.md`, `src/ServerScriptService/Tests/SplineMeshTests.luau`, `src/StarterPlayerScripts/Drift/RoadAhead.luau`, `Drift/RoadBehind.luau` | 2026-11-17 |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

