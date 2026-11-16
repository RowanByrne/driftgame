# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `feature/car-edges-follow-the-drawn-ground` | lent | `src/StarterPlayerScripts/Drift/SplineWorld.luau`, new `src/StarterPlayerScripts/Drift/OffRoadGround.luau`, `Config/Drift.luau` (an appended `OffRoad` block), new `src/ServerScriptService/Tests/OffRoadTests.luau`, `src/ServerScriptService/Tests/SplineWorldTests.luau` (section 5 "mountainside" only); for T-260: `Controllers/DriftController.luau` (the 300-stud check in `_frame`), `Services/RoadService.luau` (`SafeStart` only), `Road/SplineSequence.luau` (`locate`'s optional reach); for T-261: `Road/Spline.luau` (edge spans, `edgeAt`, `groundKind`, the edge kinds), `Road/SplineGen.luau` (its edge spans and their readers, same random streams), `Config/Spline.luau` (`Terrain` RockHeight/HedgeHeight/HedgeThickness), `Controllers/SplineRoadController.luau`, `Controllers/RoadGroundController.luau`, `Tests/SplineTests.luau`, `Tests/SplineTurnTests.luau`, all of `Tests/SplineWorldTests.luau`, `Tests/GroveTests.luau` (the section keys it compares), `features/mountain-road.md`; the `RoadSpline` wire format changes (one uphill-side list replaces `el`/`er`). Step 3 asks again for `Spline.luau` edge kinds and `SplineGen`'s edge choice | 2026-11-16 (T-258, T-259) |
| `agent/centred-steering-default` | lent | `Config/Drift.luau` (the `InputMode` line only), the steering default in `Controllers/CarInputController.luau` / `Drift/DragControl.luau` if it is set there, settings fixtures, docs that name the default | 2026-11-16 (T-262) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

