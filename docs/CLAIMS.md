# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `feature/linked-biomes` (T-203, roads and rails T-210) | 2 | `docs/game/features/road-biomes.md`, `mountain-direction.md`, `continuous-mountain.md`; `assets/reference/road-biomes/*`; `docs/game/DECISIONS.md` (append T-203 only); `docs/game/CONTRACTS.md` and `ARCHITECTURE.md` (biome entries); `src/ReplicatedStorage/Shared/Config/Spline.luau`; `src/ReplicatedStorage/Shared/Road/SplineBiome.luau`, `SplineRoadStyle.luau` (new), `SplineGradePolicy.luau` (new), `SplineHillCuts.luau` (new), `SplineCorridor.luau` (new), `Spline.luau`, `SplineGen.luau`, `SplineProfile.luau`, `SplineSequence.luau`, `SplineMesh.luau`, `SplineParts.luau`, `SplineBoundary.luau` (new), `SplineSurfaceCuts.luau` (new); `src/StarterPlayerScripts/Drift/SplineWorld.luau`, `SplineRoadView.luau`; `src/StarterPlayerScripts/Controllers/SplineRoadController.luau`, `RoadGroundController.luau`, `DriftController.luau` (projection hint on placement and walking handoff only); `src/ServerScriptService/Tests/SplineTests.luau`, `SplineHillTests.luau`, `SplineBiomeTests.luau`, `SplineCorridorTests.luau` (new), `SplineTurnTests.luau`, `SplineWorldTests.luau`, `SplineGroundDrawTests.luau` (new), `SplineMeshTests.luau`, `SplineBiomeRoadTests.luau` (new); `src/ServerScriptService/Services/RoadService.luau` (runner projection/progress/recovery points only), `CarService.luau` (pass runner identity to road recovery only) | 2026-11-14 |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.



