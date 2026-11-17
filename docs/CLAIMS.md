# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/graphics-settings-midrun` | lent | fixes only if the check finds a fault: `Drift/RoadAhead.luau`, `Drift/RoadBehind.luau`, `Drift/GroundDetail.luau`, `Drift/SplineRoadView.luau`, `Drift/GroundMeshView.luau`, `Controllers/SettingsController.luau`, `Controllers/DriftController.luau` (the view update off the road), their tests | 2026-11-16 (T-275) |
| `agent/mesh-savings` | lent | the same files as `agent/road-vanishes`, built on top of it (T-273 merges first), plus `assets/road/*` (new) | 2026-11-16 (T-275) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

