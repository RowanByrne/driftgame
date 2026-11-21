# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/climb-range-fix` | Borrow to test | `src/ServerScriptService/Tests/RangeTests.luau`, `Tests/SplineContourTests.luau`, `src/ReplicatedStorage/Shared/Road/SplineContourTraverse.luau`, `Shared/Road/SplineGen.luau`, `Shared/Config/Range.luau`, `docs/game/features/mountain-range.md` | 2026-11-21, T-341 (range test and seed 7 climb) |
| `feature/ground-look-by-steepness-and-height` | Borrow to test | `src/StarterPlayerScripts/Drift/GroundMeshView.luau`, `src/ReplicatedStorage/Shared/Road/GroundLook.luau`, `Shared/Road/DetailTexture.luau`, `Shared/Road/GroundSheet.luau` (new), `Shared/Config/GroundLook.luau`, `src/ServerScriptService/AdminConsole/Commands/World/groundLook.luau`, `src/ServerScriptService/Tests/GroundLookTests.luau`, `docs/game/features/ground-look.md`, `assets/ground-textures/*` (new) | 2026-11-20, T-340 (ground look texture sheet) |
## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

- **2026-11-19, for any conductor:** in `_tools\rocco` (9 files) and `template\repo` (CONDUCTOR.md, WORKER.md) there were uncommitted changes from another session (13:00 to 13:43 that day), not the Drift conductor's: leave them for whoever made them.

