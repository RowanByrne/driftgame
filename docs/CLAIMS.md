# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/steep-contour-road` | Borrow to test | `src/ReplicatedStorage/Shared/Road/SplineGen.luau` (native continuation), `Road/SplineContour*.luau` (new if needed), `Shared/Config/Range.luau`, `Shared/Config/Spline.luau`, `docs/game/features/mountain-range.md`, focused road tests | 2026-11-18, T-324, builds on T-323 |
| `agent/seed7-mountain-drive` | Borrow to test | `src/ReplicatedStorage/Shared/Road/Seed7*.luau` (new), `Road/Range.luau`, `Road/Ground.luau`, `Road/SplineGen.luau`, `Road/SplineSequence.luau` under Shared, `Shared/Config/Road.luau`, `src/ServerScriptService/Services/RoadService.luau`, `docs/game/features/mountain-range.md`, `src/ServerScriptService/Tests/Seed7*.luau` (new, if needed) | 2026-11-18, T-323 |
| `agent/closer-chase-zoom` | Borrow to test | `src/ReplicatedStorage/Shared/Config/Camera.luau`, `src/StarterPlayerScripts/Controllers/CarCameraController.luau` (near framing only if needed), `docs/game/features/drift-camera.md` | 2026-11-18, T-321 |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

