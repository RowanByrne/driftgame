# Claims

Every task in progress and the files it owns, so parallel sessions and workers never edit the same file (docs/workflow/CONDUCTOR.md "Claims").

- **Read it before planning.** Never assign a file another task has claimed. If you need one, tell the user which task holds it.
- **Claim before spawning:** add the round's rows, commit and push, then spawn the workers. **Remove them after merging,** and push again.
- **One row per task:** its branch, its lane, and the files it owns. Folders as `folder/*`; new files marked "(new)".
- **Append-only registries** (a list tasks only add to, like the sounds registry) can be shared by anchor: claim "`Sounds` (new block after `X` only)". Another task may claim a different anchor; nobody edits that file's existing lines.

| Branch | Lane | Files owned | Since |
|---|---|---|---|
| `agent/ground-carries-runoff` | lent | EXPERIMENT, not for merge until the user picks it: `src/ReplicatedStorage/Shared/Road/Ground.luau`, `src/StarterPlayerScripts/Drift/GroundMeshView.luau`, `src/StarterPlayerScripts/Drift/GroundTiles.luau`, the runoff and skirt parts of `src/ReplicatedStorage/Shared/Road/SplineMesh.luau` and `Spline.luau` (`terrainY`), `Config/Spline.luau` `Ground` keys. Overlaps T-247's removal by design; reconciled after it lands | 2026-11-16 (T-251) |
| `agent/sound-settings-tab` | lent | `src/StarterPlayerScripts/Settings/SettingsView.luau` (+ fixtures), `src/StarterPlayerScripts/Controllers/SettingsController.luau`, a new sound-volume module, the volume hookup in `Drift/EngineSound.luau`, `Drift/SkidSound.luau`, `Drift/SuspensionSound.luau` | 2026-11-16 (T-256) |
| `agent/fix-range-test-checks` | lent | `src/ServerScriptService/Tests/SplineTurnTests.luau`, `src/ServerScriptService/Tests/GroveTests.luau` (a game file only if a check finds a real bug, after asking the conductor) | 2026-11-16 (T-257) |
| `feature/car-edges-follow-the-drawn-ground` | lent | `src/StarterPlayerScripts/Drift/SplineWorld.luau`, new `src/StarterPlayerScripts/Drift/OffRoadGround.luau`, `Config/Drift.luau` (an appended `OffRoad` block), new `src/ServerScriptService/Tests/OffRoadTests.luau`. Step 3 asks again for `Spline.luau` edge kinds and `SplineGen`'s edge choice | 2026-11-16 (T-258, T-259) |

## Notes between sessions

> A short note for another session or PC that can't be said in a commit, such as "lane 3 has unpushed work, ask before refreshing it". Date it, say who it's for, and remove it once it's been seen.

