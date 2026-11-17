# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/gravel-texture` | lent | `Road/RoadTexture.luau`, the gravel bevel's look in `Road/SplineMesh.luau`, the gravel runoff's colouring in `Drift/GroundMeshView.luau` (look only), `Config/Road.luau` and `Config/Spline.luau` gravel colour/texture keys, `features/road-surface.md` | 2026-11-16 (T-270) |
| `agent/tarmac-mark-ribbons` | lent | `Drift/Wheels.luau`, `Drift/GroundMarks.luau`, `Config/Fx.luau` (`Marks`, `Ground` keys), `Tests/FxTests.luau`, `features/car-fx.md`; reads (not edits) `Road/Spline` for the tarmac's height | 2026-11-16 (T-269) |
| `feature/painted-vista-ridges-and-a-cloud-sea` | lent | new `Config/Vista.luau`, `Drift/VistaView.luau`, `Tests/VistaTests.luau`, admin command `World/vista.luau`, `pipeline/vista/*` (not `tools/`, which is the template's), `assets/painted-vista/*`; `Config/DayNight.luau` (two new keyframe values), `Controllers/SkyController.luau` (exposing the current look), `Controllers/DriftController.luau` (`UseSpline` builds and destroys the vista), `features/painted-vista.md`, `features/day-night.md` | 2026-11-16 (T-266) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

